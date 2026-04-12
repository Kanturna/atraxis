## Owns the active cluster session and advances simplified remote clusters.
## GalaxyState remains the durable truth; this class coordinates runtime writes
## back into that truth and activates one local SimWorld projection at a time.
class_name GalaxyRuntime
extends RefCounted

const ACTIVE_MACRO_SECTOR_SESSION_SCRIPT := preload("res://simulation/active_macro_sector_session.gd")
const MACRO_SECTOR_DESCRIPTOR_SCRIPT := preload("res://simulation/macro_sector_descriptor.gd")
const MACRO_SECTOR_ZONE_SCRIPT := preload("res://simulation/macro_sector_zone.gd")
const OBJECT_RESIDENCY_POLICY_SCRIPT := preload("res://simulation/object_residency_policy.gd")
const TRANSIT_OBJECT_STATE_SCRIPT := preload("res://simulation/transit_object_state.gd")
const WORLDGEN_SCRIPT := preload("res://simulation/galaxy_worldgen.gd")
const MAX_SIMPLIFIED_CLUSTERS_STEPPED_PER_TICK: int = 4
const MAX_MACRO_SECTOR_CLUSTER_COUNT: int = 5
const MAX_AMBIENT_MACRO_SECTOR_CLUSTERS: int = 2
const MAX_FAR_MACRO_SECTOR_CLUSTERS: int = 2
const MIN_RADIUS_ONE_MACRO_SECTOR_CLUSTER_COUNT: int = 3
const FAR_ZONE_STEP_INTERVAL_TICKS: int = 4

var galaxy_state: GalaxyState = null
var active_cluster_session: ActiveClusterSession = null
var active_macro_sector_session = null
var runtime_time_elapsed: float = 0.0
var pending_manual_activation_cluster_id: int = -1
var pending_auto_activation_cluster_id: int = -1
var activation_override_cluster_id: int = -1
var manual_activation_hold_cluster_id: int = -1
var manual_activation_hold_until_runtime_time: float = -1.0
var focus_global_position: Vector2 = Vector2.ZERO
var focus_visible_world_radius: float = 0.0
var has_focus_context: bool = false
var far_zone_tick_counter: int = 0
var worldgen = null

func initialize(next_galaxy_state: GalaxyState, initial_cluster_id: int = -1) -> void:
	galaxy_state = next_galaxy_state
	active_cluster_session = null
	active_macro_sector_session = null
	runtime_time_elapsed = 0.0
	pending_manual_activation_cluster_id = -1
	pending_auto_activation_cluster_id = -1
	activation_override_cluster_id = -1
	manual_activation_hold_cluster_id = -1
	manual_activation_hold_until_runtime_time = -1.0
	has_focus_context = false
	focus_global_position = Vector2.ZERO
	focus_visible_world_radius = 0.0
	far_zone_tick_counter = 0
	worldgen = WORLDGEN_SCRIPT.new(galaxy_state.worldgen_config) \
		if galaxy_state != null and galaxy_state.worldgen_config != null else null
	if galaxy_state == null or galaxy_state.get_cluster_count() == 0:
		return

	var resolved_cluster_id: int = initial_cluster_id if initial_cluster_id >= 0 else galaxy_state.primary_cluster_id
	_activate_cluster_internal(resolved_cluster_id)
	_rebuild_active_macro_sector(resolved_cluster_id, false)
	galaxy_state.sync_world_entity_bindings()

func step(dt: float) -> void:
	if dt <= 0.0:
		return
	_discover_focus_sector_neighborhood()
	_apply_focus_relevance_policy()
	_flush_pending_activation_request()
	WorldBuilder.step_transit_objects(galaxy_state, dt)
	_settle_arrived_transit_objects_into_inactive_clusters()
	if active_cluster_session != null and active_cluster_session.sim_world != null:
		active_cluster_session.sim_world.step_sim(dt)
		_export_outbound_active_cluster_objects_to_transit()
		WorldBuilder.writeback_world_into_cluster(
			active_cluster_session.sim_world,
			active_cluster_session.active_cluster_state,
			ObjectResidencyState.State.ACTIVE
		)
	_step_simplified_clusters(dt)
	_import_transit_objects_into_active_cluster()
	galaxy_state.sync_world_entity_bindings()
	runtime_time_elapsed += dt
	_apply_simplified_unload_policy()

func update_focus_context(next_focus_global_position: Vector2, visible_world_radius: float) -> void:
	focus_global_position = next_focus_global_position
	focus_visible_world_radius = maxf(visible_world_radius, 0.0)
	has_focus_context = true

func activate_cluster(target_cluster_id: int) -> void:
	if galaxy_state == null:
		return
	var target_cluster: ClusterState = galaxy_state.get_cluster(target_cluster_id)
	if target_cluster == null:
		return
	if active_cluster_session != null and active_cluster_session.cluster_id == target_cluster_id:
		_clear_pending_activation_target(target_cluster_id)
		return

	var is_focus_promotion_within_macro_sector: bool = is_cluster_in_active_macro_sector(target_cluster_id)
	_ensure_cluster_has_coherent_snapshot_for_activation(target_cluster)
	_demote_active_cluster_to_simplified()
	_activate_cluster_internal(target_cluster_id)
	_rebuild_active_macro_sector(target_cluster_id, is_focus_promotion_within_macro_sector)
	_clear_pending_activation_target(target_cluster_id)

func request_cluster_activation(target_cluster_id: int) -> bool:
	if galaxy_state == null or not galaxy_state.has_cluster(target_cluster_id):
		return false
	if active_cluster_session != null and active_cluster_session.cluster_id == target_cluster_id:
		return false
	pending_manual_activation_cluster_id = target_cluster_id
	pending_auto_activation_cluster_id = -1
	manual_activation_hold_cluster_id = target_cluster_id
	manual_activation_hold_until_runtime_time = runtime_time_elapsed + SimConstants.CLUSTER_MANUAL_ACTIVATION_GRACE_PERIOD
	return true

func request_cluster_activation_override(target_cluster_id: int) -> bool:
	if galaxy_state == null or not galaxy_state.has_cluster(target_cluster_id):
		return false
	activation_override_cluster_id = target_cluster_id
	manual_activation_hold_cluster_id = target_cluster_id
	manual_activation_hold_until_runtime_time = runtime_time_elapsed + SimConstants.CLUSTER_MANUAL_ACTIVATION_GRACE_PERIOD
	if active_cluster_session != null and active_cluster_session.cluster_id == target_cluster_id:
		_clear_pending_activation_target(target_cluster_id)
		return true
	pending_manual_activation_cluster_id = target_cluster_id
	pending_auto_activation_cluster_id = -1
	return true

func clear_cluster_activation_override() -> void:
	activation_override_cluster_id = -1

func has_cluster_activation_override() -> bool:
	return activation_override_cluster_id >= 0 and galaxy_state != null and galaxy_state.has_cluster(activation_override_cluster_id)

func get_cluster_activation_override_id() -> int:
	return activation_override_cluster_id

func has_pending_activation_request() -> bool:
	return pending_manual_activation_cluster_id >= 0 or pending_auto_activation_cluster_id >= 0

func get_pending_activation_cluster_id() -> int:
	if pending_manual_activation_cluster_id >= 0:
		return pending_manual_activation_cluster_id
	return pending_auto_activation_cluster_id

func get_active_macro_sector():
	if active_macro_sector_session == null or active_macro_sector_session.descriptor == null:
		return null
	return active_macro_sector_session.descriptor.copy()

func get_cluster_macro_sector_zone(cluster_id: int) -> int:
	if active_macro_sector_session == null:
		return MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE
	return active_macro_sector_session.zone_for_cluster(cluster_id)

func is_cluster_in_active_macro_sector(cluster_id: int) -> bool:
	return active_macro_sector_session != null and active_macro_sector_session.has_member_cluster(cluster_id)

func writeback_active_cluster() -> void:
	if active_cluster_session == null or active_cluster_session.sim_world == null:
		return
	WorldBuilder.writeback_world_into_cluster(
		active_cluster_session.sim_world,
		active_cluster_session.active_cluster_state,
		ObjectResidencyState.State.ACTIVE
	)

func set_black_hole_mass(new_mass: float) -> void:
	if active_cluster_session == null:
		return
	active_cluster_session.set_black_hole_mass(new_mass)
	writeback_active_cluster()

func get_active_sim_world() -> SimWorld:
	return active_cluster_session.sim_world if active_cluster_session != null else null

func get_transit_object_count() -> int:
	if galaxy_state == null:
		return 0
	return galaxy_state.get_transit_object_count()

func get_world_entity_count() -> int:
	if galaxy_state == null:
		return 0
	return galaxy_state.get_world_entity_count()

func get_active_world_entities() -> Array:
	if galaxy_state == null or active_cluster_session == null:
		return []
	return galaxy_state.get_world_entities_for_cluster(
		active_cluster_session.cluster_id,
		ObjectResidencyState.State.ACTIVE
	)

func get_world_entities_in_transit() -> Array:
	if galaxy_state == null:
		return []
	return galaxy_state.get_world_entities_in_transit()

func get_discovered_sector_count() -> int:
	if galaxy_state == null:
		return 0
	return galaxy_state.get_discovered_sector_count()

func _activate_cluster_internal(target_cluster_id: int) -> void:
	active_cluster_session = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state, target_cluster_id)
	if active_cluster_session == null or active_cluster_session.active_cluster_state == null:
		return
	if active_cluster_session.sim_world != null:
		WorldBuilder.writeback_world_into_cluster(
			active_cluster_session.sim_world,
			active_cluster_session.active_cluster_state,
			ObjectResidencyState.State.ACTIVE
		)
	active_cluster_session.active_cluster_state.mark_active(runtime_time_elapsed)
	galaxy_state.sync_world_entity_bindings()

func _step_simplified_clusters(dt: float) -> void:
	if galaxy_state == null or active_macro_sector_session == null or MAX_SIMPLIFIED_CLUSTERS_STEPPED_PER_TICK <= 0:
		return
	var stepped_clusters: int = 0
	for cluster_id in active_macro_sector_session.get_cluster_ids_for_zone(MACRO_SECTOR_ZONE_SCRIPT.Zone.AMBIENT):
		if stepped_clusters >= MAX_SIMPLIFIED_CLUSTERS_STEPPED_PER_TICK:
			break
		var cluster_state: ClusterState = galaxy_state.get_cluster(int(cluster_id))
		if cluster_state == null:
			continue
		if cluster_state.activation_state != ClusterActivationState.State.SIMPLIFIED:
			continue
		WorldBuilder.step_simplified_cluster(
			cluster_state,
			dt,
			MACRO_SECTOR_ZONE_SCRIPT.Zone.AMBIENT
		)
		stepped_clusters += 1
	far_zone_tick_counter += 1
	if far_zone_tick_counter < FAR_ZONE_STEP_INTERVAL_TICKS:
		return
	far_zone_tick_counter = 0
	for cluster_id in active_macro_sector_session.get_cluster_ids_for_zone(MACRO_SECTOR_ZONE_SCRIPT.Zone.FAR):
		if stepped_clusters >= MAX_SIMPLIFIED_CLUSTERS_STEPPED_PER_TICK:
			break
		var far_cluster_state: ClusterState = galaxy_state.get_cluster(int(cluster_id))
		if far_cluster_state == null:
			continue
		if far_cluster_state.activation_state != ClusterActivationState.State.SIMPLIFIED:
			continue
		WorldBuilder.step_simplified_cluster(
			far_cluster_state,
			dt * float(FAR_ZONE_STEP_INTERVAL_TICKS),
			MACRO_SECTOR_ZONE_SCRIPT.Zone.FAR
		)
		stepped_clusters += 1

func _flush_pending_activation_request() -> void:
	var target_cluster_id: int = get_pending_activation_cluster_id()
	if target_cluster_id < 0:
		return
	activate_cluster(target_cluster_id)

func _demote_active_cluster_to_simplified() -> void:
	if active_cluster_session == null or active_cluster_session.sim_world == null:
		return
	WorldBuilder.writeback_world_into_cluster(
		active_cluster_session.sim_world,
		active_cluster_session.active_cluster_state,
		ObjectResidencyState.State.SIMPLIFIED
	)
	active_cluster_session.active_cluster_state.mark_simplified(runtime_time_elapsed)

func _export_outbound_active_cluster_objects_to_transit() -> void:
	if galaxy_state == null or active_cluster_session == null:
		return
	for transit_state in WorldBuilder.extract_outbound_transit_objects_from_active_session(active_cluster_session):
		WorldBuilder.refresh_transit_target_assignment(galaxy_state, transit_state)
		galaxy_state.register_transit_object(transit_state)

func _import_transit_objects_into_active_cluster() -> void:
	if active_cluster_session == null or active_cluster_session.active_cluster_state == null:
		return
	var imported_object_ids: Array = WorldBuilder.import_transit_objects_into_active_session(active_cluster_session)
	if imported_object_ids.is_empty():
		return
	WorldBuilder.writeback_world_into_cluster(
		active_cluster_session.sim_world,
		active_cluster_session.active_cluster_state,
		ObjectResidencyState.State.ACTIVE
	)

func _settle_arrived_transit_objects_into_inactive_clusters() -> void:
	if galaxy_state == null:
		return
	var active_cluster_id: int = active_cluster_session.cluster_id if active_cluster_session != null else -1
	WorldBuilder.settle_arrived_transit_objects_into_inactive_clusters(galaxy_state, active_cluster_id)

func _apply_simplified_unload_policy() -> void:
	if galaxy_state == null:
		return
	var active_cluster_id: int = active_cluster_session.cluster_id if active_cluster_session != null else -1
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id == active_cluster_id:
			continue
		if _should_keep_cluster_simplified(cluster_state):
			continue
		if not cluster_state.can_unload_from_simplified(
			runtime_time_elapsed,
			SimConstants.CLUSTER_SIMPLIFIED_UNLOAD_DELAY
		):
			continue
		cluster_state.mark_unloaded(runtime_time_elapsed)

func _apply_focus_relevance_policy() -> void:
	if galaxy_state == null or galaxy_state.get_cluster_count() == 0:
		return
	var active_cluster_id: int = active_cluster_session.cluster_id if active_cluster_session != null else -1
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state == null:
			continue
		if cluster_state.cluster_id == active_cluster_id:
			cluster_state.mark_relevant(runtime_time_elapsed)
			continue
		if not _should_keep_cluster_simplified(cluster_state):
			continue
		if cluster_state.activation_state == ClusterActivationState.State.UNLOADED:
			cluster_state.mark_simplified(runtime_time_elapsed)
		elif cluster_state.activation_state == ClusterActivationState.State.SIMPLIFIED:
			cluster_state.mark_relevant(runtime_time_elapsed)

func _discover_focus_sector_neighborhood() -> void:
	if galaxy_state == null or worldgen == null:
		return
	var context: Dictionary = _resolve_focus_context()
	var focus_sector: Vector2i = worldgen.sector_coord_for_global_position(context["focus_global_position"])
	GalaxyBuilder.discover_sector_neighborhood(galaxy_state, worldgen, focus_sector, 1)

func _resolve_focus_context() -> Dictionary:
	if has_focus_context:
		return {
			"focus_global_position": focus_global_position,
			"visible_world_radius": focus_visible_world_radius,
		}
	if active_cluster_session != null and active_cluster_session.active_cluster_state != null:
		return {
			"focus_global_position": active_cluster_session.active_cluster_state.global_center,
			"visible_world_radius": 0.0,
		}
	return {
		"focus_global_position": Vector2.ZERO,
		"visible_world_radius": 0.0,
	}

func _is_manual_activation_hold_active() -> bool:
	if manual_activation_hold_cluster_id < 0 or galaxy_state == null:
		return false
	if not galaxy_state.has_cluster(manual_activation_hold_cluster_id):
		return false
	return runtime_time_elapsed + (SimConstants.FIXED_DT * 0.5) < manual_activation_hold_until_runtime_time

func _should_keep_cluster_simplified(cluster_state: ClusterState) -> bool:
	if cluster_state == null:
		return false
	var active_cluster_id: int = active_cluster_session.cluster_id if active_cluster_session != null else -1
	if active_macro_sector_session != null \
			and active_macro_sector_session.has_member_cluster(cluster_state.cluster_id) \
			and cluster_state.cluster_id != active_cluster_id:
		return true
	if cluster_state.cluster_id == activation_override_cluster_id:
		return true
	if cluster_state.cluster_id == pending_manual_activation_cluster_id:
		return true
	if cluster_state.cluster_id == pending_auto_activation_cluster_id:
		return true
	if cluster_state.cluster_id == manual_activation_hold_cluster_id and _is_manual_activation_hold_active():
		return true
	return false

func _rebuild_active_macro_sector(focus_cluster_id: int, preserve_existing_members: bool) -> void:
	if galaxy_state == null or active_cluster_session == null:
		active_macro_sector_session = null
		return
	var previous_descriptor = active_macro_sector_session.descriptor \
		if active_macro_sector_session != null else null
	var descriptor = null
	if preserve_existing_members and active_macro_sector_session != null and active_macro_sector_session.descriptor != null:
		descriptor = _build_macro_sector_descriptor_from_existing_members(
			focus_cluster_id,
			active_macro_sector_session.descriptor
		)
	if descriptor == null:
		descriptor = _build_macro_sector_descriptor(focus_cluster_id)
	if descriptor == null:
		active_macro_sector_session = null
		return
	active_macro_sector_session = ACTIVE_MACRO_SECTOR_SESSION_SCRIPT.new()
	active_macro_sector_session.bind(galaxy_state, descriptor, active_cluster_session)
	_prime_macro_sector_ambient_snapshots(descriptor)
	if not _macro_sector_member_ids_match(
			descriptor.member_cluster_ids,
			previous_descriptor.member_cluster_ids if previous_descriptor != null else []
	):
		far_zone_tick_counter = 0
	_apply_focus_relevance_policy()

func _build_macro_sector_descriptor(focus_cluster_id: int):
	var focus_cluster: ClusterState = galaxy_state.get_cluster(focus_cluster_id)
	if focus_cluster == null:
		return null
	var discovery_radius: int = 1
	var candidates: Array = _collect_macro_sector_candidate_clusters(focus_cluster, discovery_radius)
	if candidates.size() < MIN_RADIUS_ONE_MACRO_SECTOR_CLUSTER_COUNT:
		discovery_radius = 2
		candidates = _collect_macro_sector_candidate_clusters(focus_cluster, discovery_radius)
	var member_cluster_ids: Array = _select_macro_sector_member_ids(focus_cluster, candidates)
	return _make_macro_sector_descriptor(
		focus_cluster_id,
		focus_cluster_id,
		member_cluster_ids,
		discovery_radius
	)

func _build_macro_sector_descriptor_from_existing_members(
		focus_cluster_id: int,
		previous_descriptor):
	if previous_descriptor == null or not previous_descriptor.has_member(focus_cluster_id):
		return null
	var member_cluster_ids: Array = []
	for cluster_id in previous_descriptor.member_cluster_ids:
		if galaxy_state.has_cluster(int(cluster_id)):
			member_cluster_ids.append(int(cluster_id))
	if not member_cluster_ids.has(focus_cluster_id):
		return null
	return _make_macro_sector_descriptor(
		previous_descriptor.anchor_cluster_id,
		focus_cluster_id,
		member_cluster_ids,
		previous_descriptor.discovery_radius
	)

func _make_macro_sector_descriptor(
		anchor_cluster_id: int,
		focus_cluster_id: int,
		member_cluster_ids: Array,
		discovery_radius: int):
	var descriptor := MACRO_SECTOR_DESCRIPTOR_SCRIPT.new()
	var ordered_member_cluster_ids: Array = member_cluster_ids.duplicate()
	ordered_member_cluster_ids.erase(focus_cluster_id)
	ordered_member_cluster_ids.insert(0, focus_cluster_id)
	descriptor.anchor_cluster_id = anchor_cluster_id
	descriptor.focus_cluster_id = focus_cluster_id
	descriptor.member_cluster_ids = ordered_member_cluster_ids
	descriptor.discovery_radius = discovery_radius
	descriptor.zone_by_cluster_id = _build_macro_sector_zone_map(focus_cluster_id, descriptor.member_cluster_ids)
	return descriptor

func _collect_macro_sector_candidate_clusters(focus_cluster: ClusterState, discovery_radius: int) -> Array:
	var candidates: Array = []
	if focus_cluster == null:
		return candidates
	var focus_sector: Vector2i = _macro_sector_focus_sector_coord(focus_cluster)
	if worldgen != null:
		GalaxyBuilder.discover_sector_neighborhood(galaxy_state, worldgen, focus_sector, discovery_radius)
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state == null:
			continue
		if _cluster_belongs_to_macro_sector_candidate_set(cluster_state, focus_sector, discovery_radius):
			candidates.append(cluster_state)
	if candidates.is_empty():
		candidates = galaxy_state.get_clusters()
	return candidates

func _macro_sector_focus_sector_coord(focus_cluster: ClusterState) -> Vector2i:
	if focus_cluster == null:
		return Vector2i.ZERO
	var sector_coord_variant = focus_cluster.simulation_profile.get("sector_coord", null)
	if sector_coord_variant is Vector2i:
		return sector_coord_variant
	if worldgen != null:
		return worldgen.sector_coord_for_global_position(focus_cluster.global_center)
	return Vector2i.ZERO

func _cluster_belongs_to_macro_sector_candidate_set(
		cluster_state: ClusterState,
		focus_sector: Vector2i,
		discovery_radius: int) -> bool:
	if cluster_state == null:
		return false
	var sector_coord_variant = cluster_state.simulation_profile.get("sector_coord", null)
	if sector_coord_variant is Vector2i:
		var sector_coord: Vector2i = sector_coord_variant
		return abs(sector_coord.x - focus_sector.x) <= discovery_radius \
			and abs(sector_coord.y - focus_sector.y) <= discovery_radius
	return true

func _select_macro_sector_member_ids(focus_cluster: ClusterState, candidates: Array) -> Array:
	var ranked_members: Array = []
	if focus_cluster == null:
		return ranked_members
	for cluster_state in candidates:
		if cluster_state == null:
			continue
		var priority_bucket: int = 0 if _is_cluster_macro_sector_priority_candidate(cluster_state) else 1
		ranked_members.append({
			"cluster_id": cluster_state.cluster_id,
			"priority_bucket": priority_bucket,
			"distance": cluster_state.global_center.distance_to(focus_cluster.global_center),
			"spawn_priority": int(cluster_state.simulation_profile.get("spawn_priority", 0)),
		})
	ranked_members.sort_custom(func(a, b):
		if int(a["cluster_id"]) == focus_cluster.cluster_id:
			return true
		if int(b["cluster_id"]) == focus_cluster.cluster_id:
			return false
		if int(a["priority_bucket"]) != int(b["priority_bucket"]):
			return int(a["priority_bucket"]) < int(b["priority_bucket"])
		if not is_equal_approx(float(a["distance"]), float(b["distance"])):
			return float(a["distance"]) < float(b["distance"])
		if int(a["spawn_priority"]) != int(b["spawn_priority"]):
			return int(a["spawn_priority"]) > int(b["spawn_priority"])
		return int(a["cluster_id"]) < int(b["cluster_id"])
	)
	var member_cluster_ids: Array = []
	for entry in ranked_members:
		var cluster_id: int = int(entry["cluster_id"])
		if member_cluster_ids.has(cluster_id):
			continue
		member_cluster_ids.append(cluster_id)
		if member_cluster_ids.size() >= MAX_MACRO_SECTOR_CLUSTER_COUNT:
			break
	if not member_cluster_ids.has(focus_cluster.cluster_id):
		member_cluster_ids.insert(0, focus_cluster.cluster_id)
		while member_cluster_ids.size() > MAX_MACRO_SECTOR_CLUSTER_COUNT:
			member_cluster_ids.pop_back()
	return member_cluster_ids

func _is_cluster_macro_sector_priority_candidate(cluster_state: ClusterState) -> bool:
	if cluster_state == null:
		return false
	if bool(cluster_state.simulation_profile.get("spawn_viable", false)):
		return true
	return int(cluster_state.simulation_profile.get("star_count", 0)) > 0

func _build_macro_sector_zone_map(focus_cluster_id: int, member_cluster_ids: Array) -> Dictionary:
	var zone_by_cluster_id: Dictionary = {}
	zone_by_cluster_id[focus_cluster_id] = MACRO_SECTOR_ZONE_SCRIPT.Zone.FOCUS
	var ranked_members: Array = []
	var focus_cluster: ClusterState = galaxy_state.get_cluster(focus_cluster_id)
	for cluster_id in member_cluster_ids:
		var member_id: int = int(cluster_id)
		if member_id == focus_cluster_id:
			continue
		var cluster_state: ClusterState = galaxy_state.get_cluster(member_id)
		if cluster_state == null or focus_cluster == null:
			continue
		ranked_members.append({
			"cluster_id": member_id,
			"distance": cluster_state.global_center.distance_to(focus_cluster.global_center),
		})
	ranked_members.sort_custom(func(a, b):
		if not is_equal_approx(float(a["distance"]), float(b["distance"])):
			return float(a["distance"]) < float(b["distance"])
		return int(a["cluster_id"]) < int(b["cluster_id"])
	)
	for index in range(ranked_members.size()):
		var member_id: int = int(ranked_members[index]["cluster_id"])
		if index < MAX_AMBIENT_MACRO_SECTOR_CLUSTERS:
			zone_by_cluster_id[member_id] = MACRO_SECTOR_ZONE_SCRIPT.Zone.AMBIENT
		else:
			zone_by_cluster_id[member_id] = MACRO_SECTOR_ZONE_SCRIPT.Zone.FAR
	for cluster_id in member_cluster_ids:
		var member_id: int = int(cluster_id)
		if not zone_by_cluster_id.has(member_id):
			zone_by_cluster_id[member_id] = MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE
	return zone_by_cluster_id

func _clear_pending_activation_target(target_cluster_id: int) -> void:
	if pending_manual_activation_cluster_id == target_cluster_id:
		pending_manual_activation_cluster_id = -1
	if pending_auto_activation_cluster_id == target_cluster_id:
		pending_auto_activation_cluster_id = -1

func _ensure_cluster_has_coherent_snapshot_for_activation(cluster_state: ClusterState) -> void:
	if cluster_state == null:
		return
	if cluster_state.last_activated_runtime_time >= 0.0:
		return
	WorldBuilder.ensure_coherent_simplified_snapshot(cluster_state)

func _prime_macro_sector_ambient_snapshots(descriptor) -> void:
	if descriptor == null or galaxy_state == null:
		return
	for cluster_id in descriptor.get_cluster_ids_for_zone(MACRO_SECTOR_ZONE_SCRIPT.Zone.AMBIENT):
		var cluster_state: ClusterState = galaxy_state.get_cluster(int(cluster_id))
		if cluster_state == null:
			continue
		if cluster_state.last_activated_runtime_time >= 0.0 \
				or WorldBuilder.has_coherent_runtime_snapshot(cluster_state):
			continue
		WorldBuilder.ensure_coherent_simplified_snapshot(cluster_state)

func _macro_sector_member_ids_match(left_member_cluster_ids: Array, right_member_cluster_ids: Array) -> bool:
	if left_member_cluster_ids.size() != right_member_cluster_ids.size():
		return false
	var left_sorted: Array = left_member_cluster_ids.duplicate()
	var right_sorted: Array = right_member_cluster_ids.duplicate()
	left_sorted.sort()
	right_sorted.sort()
	return left_sorted == right_sorted
