## Owns the active cluster session and advances simplified remote clusters.
## GalaxyState remains the durable truth; this class coordinates runtime writes
## back into that truth and activates one local SimWorld projection at a time.
class_name GalaxyRuntime
extends RefCounted

const ACTIVE_SECTOR_SESSION_SCRIPT := preload("res://simulation/active_sector_session.gd")
const ACTIVE_MACRO_SECTOR_SESSION_SCRIPT := preload("res://simulation/active_macro_sector_session.gd")
const MACRO_SECTOR_DESCRIPTOR_SCRIPT := preload("res://simulation/macro_sector_descriptor.gd")
const MACRO_SECTOR_ZONE_SCRIPT := preload("res://simulation/macro_sector_zone.gd")
const OBJECT_RESIDENCY_POLICY_SCRIPT := preload("res://simulation/object_residency_policy.gd")
const TRANSIT_OBJECT_STATE_SCRIPT := preload("res://simulation/transit_object_state.gd")
const WORLDGEN_SCRIPT := preload("res://simulation/galaxy_worldgen.gd")
const MAX_SIMPLIFIED_CLUSTERS_STEPPED_PER_TICK: int = 4
const FAR_ZONE_STEP_INTERVAL_TICKS: int = 4
const ACTIVE_SECTOR_DISCOVERY_RADIUS: int = 2
const AMBIENT_SECTOR_RADIUS: int = 1
const FAR_SECTOR_RADIUS: int = 2
const ACTIVE_SECTOR_SWITCH_HYSTERESIS_FACTOR: float = 0.06

var galaxy_state: GalaxyState = null
var active_sector_session = null
var active_cluster_session: ActiveClusterSession = null
var active_macro_sector_session = null
var active_sector_world: SimWorld = null
var time_scale: float = 1.0
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
var _snapshot_prewarm_queue: Array = []

func initialize(next_galaxy_state: GalaxyState, initial_cluster_id: int = -1) -> void:
	galaxy_state = next_galaxy_state
	active_sector_session = null
	active_cluster_session = null
	active_macro_sector_session = null
	active_sector_world = null
	time_scale = 1.0
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
	_snapshot_prewarm_queue = []
	worldgen = WORLDGEN_SCRIPT.new(galaxy_state.worldgen_config) \
		if galaxy_state != null and galaxy_state.worldgen_config != null else null
	if galaxy_state == null:
		return
	if worldgen != null and galaxy_state.get_discovered_sector_count() == 0:
		GalaxyBuilder.discover_sector_neighborhood(galaxy_state, worldgen, Vector2i.ZERO, ACTIVE_SECTOR_DISCOVERY_RADIUS)
	var initial_sector_coord: Vector2i = _resolve_initial_sector_coord(initial_cluster_id)
	_activate_sector_internal(initial_sector_coord, initial_cluster_id)
	_rebuild_active_macro_sector(
		active_cluster_session.cluster_id if active_cluster_session != null else -1,
		false
	)
	_apply_time_scale_to_active_world()
	galaxy_state.sync_world_entity_bindings()

func step(dt: float) -> void:
	if dt <= 0.0:
		return
	var sim_dt: float = dt * time_scale
	_discover_focus_sector_neighborhood()
	_enqueue_approaching_sector_snapshots()
	_drain_snapshot_prewarm_queue()
	_sync_active_sector_to_focus_context()
	_apply_focus_relevance_policy()
	_flush_pending_activation_request()
	_apply_time_scale_to_active_world()
	WorldBuilder.step_transit_objects(galaxy_state, sim_dt)
	_settle_arrived_transit_objects_into_inactive_clusters()
	if active_cluster_session != null and active_cluster_session.sim_world != null:
		active_cluster_session.sim_world.step_sim(dt)
		_export_outbound_active_cluster_objects_to_transit()
		WorldBuilder.writeback_world_into_cluster(
			active_cluster_session.sim_world,
			active_cluster_session.active_cluster_state,
			ObjectResidencyState.State.ACTIVE
		)
	elif active_sector_world != null:
		active_sector_world.step_sim(dt)
	_step_simplified_clusters(sim_dt)
	_import_transit_objects_into_active_cluster()
	galaxy_state.sync_world_entity_bindings()
	# Runtime clocks drive focus, activation and unload hysteresis, so they
	# intentionally remain tied to real frame time instead of simulation speed.
	runtime_time_elapsed += dt
	_apply_simplified_unload_policy()

func set_time_scale(value: float) -> void:
	time_scale = clampf(value, SimConstants.MIN_TIME_SCALE, SimConstants.MAX_TIME_SCALE)
	_apply_time_scale_to_active_world()

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
	_ensure_cluster_has_coherent_snapshot_for_activation(target_cluster)
	activate_sector(_resolve_sector_coord_for_cluster(target_cluster), target_cluster_id)
	_clear_pending_activation_target(target_cluster_id)

func activate_sector(target_sector_coord: Vector2i, preferred_cluster_id: int = -1) -> void:
	_transition_active_sector(target_sector_coord, preferred_cluster_id, false)

func _transition_active_sector(
		target_sector_coord: Vector2i,
		preferred_cluster_id: int = -1,
		preserve_active_cluster_session: bool = false) -> void:
	if galaxy_state == null:
		return
	var current_sector_coord: Vector2i = _get_active_sector_coord()
	var same_sector: bool = active_sector_session != null and current_sector_coord == target_sector_coord
	if preserve_active_cluster_session:
		if same_sector:
			return
	else:
		var same_cluster: bool = preferred_cluster_id < 0 \
			or (active_cluster_session != null and active_cluster_session.cluster_id == preferred_cluster_id)
		if same_sector and same_cluster:
			return
	if active_sector_session != null and active_sector_session.sector_state != null:
		active_sector_session.sector_state.mark_remote(runtime_time_elapsed)
	if not preserve_active_cluster_session:
		_demote_active_cluster_to_simplified()
	far_zone_tick_counter = 0
	_activate_sector_internal(
		target_sector_coord,
		preferred_cluster_id,
		preserve_active_cluster_session
	)
	_rebuild_active_macro_sector(
		active_cluster_session.cluster_id if active_cluster_session != null else -1,
		false
	)

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
	if galaxy_state == null:
		return MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE
	var cluster_state: ClusterState = galaxy_state.get_cluster(cluster_id)
	return _sector_zone_for_cluster(cluster_state)

func is_cluster_in_active_macro_sector(cluster_id: int) -> bool:
	return get_cluster_macro_sector_zone(cluster_id) != MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE

func get_active_sector_state():
	return active_sector_session.sector_state if active_sector_session != null else null

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
	return active_sector_world

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

func _activate_sector_internal(
		target_sector_coord: Vector2i,
		preferred_cluster_id: int = -1,
		preserve_active_cluster_session: bool = false) -> void:
	if galaxy_state == null:
		return
	var preserved_frame_global_origin = active_sector_session.frame_global_origin \
		if active_sector_session != null else null
	if worldgen != null:
		GalaxyBuilder.discover_sector_neighborhood(
			galaxy_state,
			worldgen,
			target_sector_coord,
			ACTIVE_SECTOR_DISCOVERY_RADIUS
		)
	var sector_state = galaxy_state.get_or_create_sector_state(target_sector_coord)
	if preserve_active_cluster_session:
		# Focus-driven sector changes should only move the semantic sector frame.
		# Keeping the materialized cluster/world alive avoids a visible hitch when
		# the blue active-sector highlight advances during free camera movement.
		if active_sector_world == null:
			active_sector_world = active_cluster_session.sim_world if active_cluster_session != null else SimWorld.new()
	else:
		var target_cluster_id: int = _resolve_target_cluster_id_for_sector(target_sector_coord, preferred_cluster_id)
		active_cluster_session = null
		active_sector_world = null
		if target_cluster_id >= 0:
			active_cluster_session = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state, target_cluster_id)
			if active_cluster_session != null and active_cluster_session.active_cluster_state != null:
				if active_cluster_session.sim_world != null:
					WorldBuilder.writeback_world_into_cluster(
						active_cluster_session.sim_world,
						active_cluster_session.active_cluster_state,
						ObjectResidencyState.State.ACTIVE
					)
				active_cluster_session.active_cluster_state.mark_active(runtime_time_elapsed)
				active_sector_world = active_cluster_session.sim_world
		if active_sector_world == null:
			active_sector_world = SimWorld.new()
	_apply_time_scale_to_active_world()
	active_sector_session = ACTIVE_SECTOR_SESSION_SCRIPT.new()
	active_sector_session.bind(
		galaxy_state,
		sector_state,
		active_cluster_session,
		preserved_frame_global_origin
	)
	if sector_state != null:
		sector_state.mark_active(runtime_time_elapsed)
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
	if active_cluster_id >= 0:
		var active_cluster_state: ClusterState = galaxy_state.get_cluster(active_cluster_id)
		if active_cluster_state != null:
			active_cluster_state.mark_relevant(runtime_time_elapsed)
	if active_macro_sector_session == null or active_macro_sector_session.descriptor == null:
		return
	for cluster_id in active_macro_sector_session.descriptor.member_cluster_ids:
		if int(cluster_id) == active_cluster_id:
			continue
		var cluster_state: ClusterState = galaxy_state.get_cluster(int(cluster_id))
		if cluster_state == null:
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
	GalaxyBuilder.discover_sector_neighborhood(galaxy_state, worldgen, focus_sector, ACTIVE_SECTOR_DISCOVERY_RADIUS)

func _resolve_focus_context() -> Dictionary:
	if has_focus_context:
		return {
			"focus_global_position": focus_global_position,
			"visible_world_radius": focus_visible_world_radius,
		}
	if active_sector_session != null and active_sector_session.sector_state != null:
		return {
			"focus_global_position": active_sector_session.sector_center(),
			"visible_world_radius": 0.0,
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

func _sync_active_sector_to_focus_context() -> void:
	if galaxy_state == null or worldgen == null:
		return
	var context: Dictionary = _resolve_focus_context()
	var focus_global_position: Vector2 = context["focus_global_position"]
	var focus_sector: Vector2i = worldgen.sector_coord_for_global_position(focus_global_position)
	if active_sector_session == null or active_sector_session.sector_state == null:
		_activate_sector_internal(focus_sector)
		_rebuild_active_macro_sector(
			active_cluster_session.cluster_id if active_cluster_session != null else -1,
			false
		)
		return
	if focus_sector == active_sector_session.sector_state.sector_coord:
		return
	if _should_keep_current_sector_during_boundary_hysteresis(focus_global_position, focus_sector):
		return
	var should_preserve_loaded_cluster: bool = active_cluster_session != null \
		and not galaxy_state.get_cluster_ids_for_sector(focus_sector).is_empty()
	_transition_active_sector(focus_sector, -1, should_preserve_loaded_cluster)

func _should_keep_current_sector_during_boundary_hysteresis(
		focus_global_position: Vector2,
		focus_sector: Vector2i) -> bool:
	if active_sector_session == null or active_sector_session.sector_state == null:
		return false
	var current_sector_coord: Vector2i = active_sector_session.sector_state.sector_coord
	if focus_sector == current_sector_coord:
		return false
	var sector_delta := focus_sector - current_sector_coord
	if maxi(absi(sector_delta.x), absi(sector_delta.y)) != 1:
		return false
	var sector_size: float = float(active_sector_session.sector_state.size)
	if sector_size <= 0.0:
		return false
	var hysteresis_margin: float = sector_size * ACTIVE_SECTOR_SWITCH_HYSTERESIS_FACTOR
	var hysteresis_rect := Rect2(
		active_sector_session.sector_state.global_origin - Vector2.ONE * hysteresis_margin,
		Vector2.ONE * (sector_size + hysteresis_margin * 2.0)
	)
	return hysteresis_rect.has_point(focus_global_position)

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
	if WorldBuilder.cluster_has_unsupported_outbound_dynamic_stars(cluster_state):
		return true
	return false

func _apply_time_scale_to_active_world() -> void:
	if active_cluster_session != null and active_cluster_session.sim_world != null:
		active_cluster_session.sim_world.time_scale = time_scale
	if active_sector_world != null:
		active_sector_world.time_scale = time_scale

func _rebuild_active_macro_sector(focus_cluster_id: int, preserve_existing_members: bool) -> void:
	if galaxy_state == null or active_sector_session == null or active_sector_session.sector_state == null:
		active_macro_sector_session = null
		return
	var descriptor := MACRO_SECTOR_DESCRIPTOR_SCRIPT.new()
	descriptor.anchor_cluster_id = active_cluster_session.cluster_id if active_cluster_session != null else -1
	descriptor.focus_cluster_id = descriptor.anchor_cluster_id
	descriptor.discovery_radius = ACTIVE_SECTOR_DISCOVERY_RADIUS
	var member_cluster_ids: Array = []
	var zone_by_cluster_id: Dictionary = {}
	var active_sector_coord: Vector2i = active_sector_session.sector_state.sector_coord
	for cluster_id in _cluster_ids_in_sector_radius(active_sector_coord, FAR_SECTOR_RADIUS):
		var cluster_state: ClusterState = galaxy_state.get_cluster(int(cluster_id))
		if cluster_state == null:
			continue
		var zone: int = _sector_zone_for_cluster(cluster_state)
		if zone == MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE:
			continue
		member_cluster_ids.append(cluster_state.cluster_id)
		zone_by_cluster_id[cluster_state.cluster_id] = zone
	if descriptor.focus_cluster_id >= 0 and member_cluster_ids.has(descriptor.focus_cluster_id):
		member_cluster_ids.erase(descriptor.focus_cluster_id)
		member_cluster_ids.insert(0, descriptor.focus_cluster_id)
	descriptor.member_cluster_ids = member_cluster_ids
	descriptor.zone_by_cluster_id = zone_by_cluster_id
	if descriptor.member_cluster_ids.is_empty() and descriptor.focus_cluster_id < 0:
		active_macro_sector_session = null
		return
	active_macro_sector_session = ACTIVE_MACRO_SECTOR_SESSION_SCRIPT.new()
	active_macro_sector_session.bind(galaxy_state, descriptor, active_cluster_session)
	_prime_macro_sector_ambient_snapshots(descriptor)
	_apply_focus_relevance_policy()

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
		if not _snapshot_prewarm_queue.has(cluster_id):
			_snapshot_prewarm_queue.append(cluster_id)

## Proactively enqueues snapshot priming for clusters near the sector the focus
## is currently in. Runs before _sync_active_sector_to_focus_context so that
## work is spread over multiple steps before the actual transition fires.
func _enqueue_approaching_sector_snapshots() -> void:
	if not has_focus_context or worldgen == null or galaxy_state == null:
		return
	if active_sector_session == null or active_sector_session.sector_state == null:
		return
	var focus_sector: Vector2i = worldgen.sector_coord_for_global_position(focus_global_position)
	if focus_sector == active_sector_session.sector_state.sector_coord:
		return
	for cluster_id in _cluster_ids_in_sector_radius(focus_sector, AMBIENT_SECTOR_RADIUS):
		var cluster_state: ClusterState = galaxy_state.get_cluster(int(cluster_id))
		if cluster_state == null:
			continue
		if cluster_state.last_activated_runtime_time >= 0.0 \
				or WorldBuilder.has_coherent_runtime_snapshot(cluster_state):
			continue
		var cluster_sector: Vector2i = _resolve_sector_coord_for_cluster(cluster_state)
		var sector_delta: Vector2i = cluster_sector - focus_sector
		if maxi(absi(sector_delta.x), absi(sector_delta.y)) > AMBIENT_SECTOR_RADIUS:
			continue
		if not _snapshot_prewarm_queue.has(cluster_state.cluster_id):
			_snapshot_prewarm_queue.append(cluster_state.cluster_id)

## Processes one pending snapshot priming entry per call so the cost is
## amortised across frames instead of spiking at the moment of sector switch.
func _drain_snapshot_prewarm_queue() -> void:
	while not _snapshot_prewarm_queue.is_empty():
		var cluster_id: int = _snapshot_prewarm_queue.pop_front()
		var cluster_state: ClusterState = galaxy_state.get_cluster(int(cluster_id)) \
			if galaxy_state != null else null
		if cluster_state == null:
			continue
		if cluster_state.last_activated_runtime_time >= 0.0 \
				or WorldBuilder.has_coherent_runtime_snapshot(cluster_state):
			continue
		WorldBuilder.ensure_coherent_simplified_snapshot(cluster_state)
		return

func _macro_sector_member_ids_match(left_member_cluster_ids: Array, right_member_cluster_ids: Array) -> bool:
	if left_member_cluster_ids.size() != right_member_cluster_ids.size():
		return false
	var left_sorted: Array = left_member_cluster_ids.duplicate()
	var right_sorted: Array = right_member_cluster_ids.duplicate()
	left_sorted.sort()
	right_sorted.sort()
	return left_sorted == right_sorted

func _cluster_ids_in_sector_radius(center_sector_coord: Vector2i, radius: int) -> Array:
	if galaxy_state == null:
		return []
	var deduped_cluster_ids: Dictionary = {}
	var ordered_cluster_ids: Array = []
	for y in range(center_sector_coord.y - radius, center_sector_coord.y + radius + 1):
		for x in range(center_sector_coord.x - radius, center_sector_coord.x + radius + 1):
			for cluster_id in galaxy_state.get_cluster_ids_for_sector(Vector2i(x, y)):
				var cluster_id_int: int = int(cluster_id)
				if deduped_cluster_ids.has(cluster_id_int):
					continue
				deduped_cluster_ids[cluster_id_int] = true
				ordered_cluster_ids.append(cluster_id_int)
	return ordered_cluster_ids

func _resolve_initial_sector_coord(initial_cluster_id: int) -> Vector2i:
	if galaxy_state == null:
		return Vector2i.ZERO
	if initial_cluster_id >= 0 and galaxy_state.has_cluster(initial_cluster_id):
		return _resolve_sector_coord_for_cluster(galaxy_state.get_cluster(initial_cluster_id))
	if galaxy_state.primary_cluster_id >= 0 and galaxy_state.has_cluster(galaxy_state.primary_cluster_id):
		return _resolve_sector_coord_for_cluster(galaxy_state.get_cluster(galaxy_state.primary_cluster_id))
	if galaxy_state.get_discovered_sector_count() > 0:
		return galaxy_state.get_discovered_sector_coords()[0]
	return Vector2i.ZERO

func _resolve_target_cluster_id_for_sector(target_sector_coord: Vector2i, preferred_cluster_id: int = -1) -> int:
	if galaxy_state == null:
		return -1
	if preferred_cluster_id >= 0:
		var preferred_cluster: ClusterState = galaxy_state.get_cluster(preferred_cluster_id)
		if preferred_cluster != null and _resolve_sector_coord_for_cluster(preferred_cluster) == target_sector_coord:
			return preferred_cluster_id
	var sector_cluster_ids: Array = galaxy_state.get_cluster_ids_for_sector(target_sector_coord)
	if sector_cluster_ids.is_empty():
		return -1
	return int(sector_cluster_ids[0])

func _get_active_sector_coord() -> Vector2i:
	if active_sector_session != null and active_sector_session.sector_state != null:
		return active_sector_session.sector_state.sector_coord
	if active_cluster_session != null and active_cluster_session.active_cluster_state != null:
		return _resolve_sector_coord_for_cluster(active_cluster_session.active_cluster_state)
	return Vector2i.ZERO

func _resolve_sector_coord_for_cluster(cluster_state: ClusterState) -> Vector2i:
	if cluster_state == null:
		return Vector2i.ZERO
	var sector_coord_variant = cluster_state.simulation_profile.get("sector_coord", null)
	if sector_coord_variant is Vector2i:
		return sector_coord_variant
	if galaxy_state != null:
		return galaxy_state.find_sector_for_global_position(cluster_state.global_center)
	if worldgen != null:
		return worldgen.sector_coord_for_global_position(cluster_state.global_center)
	return Vector2i.ZERO

func _sector_zone_for_cluster(cluster_state: ClusterState) -> int:
	if cluster_state == null or active_sector_session == null or active_sector_session.sector_state == null:
		return MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE
	if active_cluster_session != null and cluster_state.cluster_id == active_cluster_session.cluster_id:
		return MACRO_SECTOR_ZONE_SCRIPT.Zone.FOCUS
	var sector_coord: Vector2i = _resolve_sector_coord_for_cluster(cluster_state)
	var active_sector_coord: Vector2i = active_sector_session.sector_state.sector_coord
	var sector_distance: int = maxi(
		absi(sector_coord.x - active_sector_coord.x),
		absi(sector_coord.y - active_sector_coord.y)
	)
	if sector_distance <= AMBIENT_SECTOR_RADIUS:
		return MACRO_SECTOR_ZONE_SCRIPT.Zone.AMBIENT
	if sector_distance <= FAR_SECTOR_RADIUS:
		return MACRO_SECTOR_ZONE_SCRIPT.Zone.FAR
	return MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE
