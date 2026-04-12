## Owns the active cluster session and advances simplified remote clusters.
## GalaxyState remains the durable truth; this class coordinates runtime writes
## back into that truth and activates one local SimWorld projection at a time.
class_name GalaxyRuntime
extends RefCounted

var galaxy_state: GalaxyState = null
var active_cluster_session: ActiveClusterSession = null
var runtime_time_elapsed: float = 0.0
var pending_manual_activation_cluster_id: int = -1
var pending_auto_activation_cluster_id: int = -1
var activation_override_cluster_id: int = -1
var manual_activation_hold_cluster_id: int = -1
var manual_activation_hold_until_runtime_time: float = -1.0
var focus_global_position: Vector2 = Vector2.ZERO
var focus_visible_world_radius: float = 0.0
var has_focus_context: bool = false

func initialize(next_galaxy_state: GalaxyState, initial_cluster_id: int = -1) -> void:
	galaxy_state = next_galaxy_state
	active_cluster_session = null
	runtime_time_elapsed = 0.0
	pending_manual_activation_cluster_id = -1
	pending_auto_activation_cluster_id = -1
	activation_override_cluster_id = -1
	manual_activation_hold_cluster_id = -1
	manual_activation_hold_until_runtime_time = -1.0
	has_focus_context = false
	focus_global_position = Vector2.ZERO
	focus_visible_world_radius = 0.0
	if galaxy_state == null or galaxy_state.get_cluster_count() == 0:
		return

	var resolved_cluster_id: int = initial_cluster_id if initial_cluster_id >= 0 else galaxy_state.primary_cluster_id
	_activate_cluster_internal(resolved_cluster_id)

func step(dt: float) -> void:
	if dt <= 0.0:
		return
	_apply_focus_relevance_policy()
	_flush_pending_activation_request()
	_apply_focus_relevance_policy()
	WorldBuilder.step_transit_objects(galaxy_state, dt)
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

	_demote_active_cluster_to_simplified()
	_activate_cluster_internal(target_cluster_id)
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

func _step_simplified_clusters(dt: float) -> void:
	if galaxy_state == null:
		return
	var active_cluster_id: int = active_cluster_session.cluster_id if active_cluster_session != null else -1
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id == active_cluster_id:
			continue
		if cluster_state.activation_state != ClusterActivationState.State.SIMPLIFIED:
			continue
		WorldBuilder.step_simplified_cluster(cluster_state, dt)

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
		var target_cluster: ClusterState = galaxy_state.find_cluster_containing_global_position(
			transit_state.global_position,
			SimConstants.CLUSTER_TRANSIT_IMPORT_RADIUS_FACTOR
		)
		transit_state.target_cluster_id = target_cluster.cluster_id if target_cluster != null else -1
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

func _apply_simplified_unload_policy() -> void:
	if galaxy_state == null:
		return
	var active_cluster_id: int = active_cluster_session.cluster_id if active_cluster_session != null else -1
	var context: Dictionary = _resolve_focus_context()
	var relevance_radius: float = _simplified_relevance_radius(float(context["visible_world_radius"]))
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id == active_cluster_id:
			continue
		if _should_keep_cluster_simplified(
			cluster_state,
			context["focus_global_position"],
			relevance_radius
		):
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
	var context: Dictionary = _resolve_focus_context()
	var ranked_clusters: Array = _rank_clusters_by_focus_distance(context["focus_global_position"])
	if ranked_clusters.is_empty():
		return
	var desired_active_cluster_id: int = _determine_focus_active_cluster_id(
		ranked_clusters,
		float(context["visible_world_radius"])
	)
	if desired_active_cluster_id >= 0:
		_queue_auto_activation_request(desired_active_cluster_id)

	var active_cluster_id: int = active_cluster_session.cluster_id if active_cluster_session != null else -1
	var relevance_radius: float = _simplified_relevance_radius(float(context["visible_world_radius"]))
	for entry in ranked_clusters:
		var cluster_state: ClusterState = entry["cluster_state"]
		if cluster_state == null:
			continue
		if cluster_state.cluster_id == active_cluster_id:
			cluster_state.mark_relevant(runtime_time_elapsed)
			continue
		if not _should_keep_cluster_simplified(
			cluster_state,
			context["focus_global_position"],
			relevance_radius
		):
			continue
		if cluster_state.activation_state == ClusterActivationState.State.UNLOADED:
			cluster_state.mark_simplified(runtime_time_elapsed)
		elif cluster_state.activation_state == ClusterActivationState.State.SIMPLIFIED:
			cluster_state.mark_relevant(runtime_time_elapsed)

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

func _rank_clusters_by_focus_distance(target_focus_global_position: Vector2) -> Array:
	var ranked_clusters: Array = []
	for cluster_state in galaxy_state.get_clusters():
		ranked_clusters.append({
			"cluster_state": cluster_state,
			"distance": cluster_state.global_center.distance_to(target_focus_global_position),
		})
	ranked_clusters.sort_custom(func(a, b): return a["distance"] < b["distance"])
	return ranked_clusters

func _determine_focus_active_cluster_id(ranked_clusters: Array, visible_world_radius: float) -> int:
	if ranked_clusters.is_empty():
		return -1
	var forced_cluster_id: int = _forced_active_cluster_id()
	if forced_cluster_id >= 0:
		return forced_cluster_id
	var nearest_cluster: ClusterState = ranked_clusters[0]["cluster_state"]
	if nearest_cluster == null:
		return -1
	if active_cluster_session == null or active_cluster_session.active_cluster_state == null:
		return nearest_cluster.cluster_id
	var active_cluster_id: int = active_cluster_session.cluster_id
	if active_cluster_id == nearest_cluster.cluster_id:
		return nearest_cluster.cluster_id
	var active_distance: float = _find_ranked_cluster_distance(ranked_clusters, active_cluster_id)
	if active_distance == INF:
		return nearest_cluster.cluster_id
	var switch_margin: float = visible_world_radius * SimConstants.CLUSTER_ACTIVE_SWITCH_HYSTERESIS_FACTOR
	if active_distance <= float(ranked_clusters[0]["distance"]) + switch_margin:
		return active_cluster_id
	return nearest_cluster.cluster_id

func _find_ranked_cluster_distance(ranked_clusters: Array, cluster_id: int) -> float:
	for entry in ranked_clusters:
		var cluster_state: ClusterState = entry["cluster_state"]
		if cluster_state != null and cluster_state.cluster_id == cluster_id:
			return float(entry["distance"])
	return INF

func _simplified_relevance_radius(visible_world_radius: float) -> float:
	return visible_world_radius * SimConstants.CLUSTER_SIMPLIFIED_RANGE_FACTOR

func _is_cluster_simplified_relevant(
		cluster_state: ClusterState,
		target_focus_global_position: Vector2,
		relevance_radius: float) -> bool:
	if cluster_state == null:
		return false
	return cluster_state.global_center.distance_to(target_focus_global_position) <= relevance_radius

func _queue_auto_activation_request(target_cluster_id: int) -> void:
	if target_cluster_id < 0:
		return
	if pending_manual_activation_cluster_id >= 0:
		return
	if active_cluster_session != null and active_cluster_session.cluster_id == target_cluster_id:
		pending_auto_activation_cluster_id = -1
		return
	pending_auto_activation_cluster_id = target_cluster_id

func _forced_active_cluster_id() -> int:
	if has_cluster_activation_override():
		return activation_override_cluster_id
	if _is_manual_activation_hold_active():
		return manual_activation_hold_cluster_id
	return -1

func _is_manual_activation_hold_active() -> bool:
	if manual_activation_hold_cluster_id < 0 or galaxy_state == null:
		return false
	if not galaxy_state.has_cluster(manual_activation_hold_cluster_id):
		return false
	return runtime_time_elapsed + (SimConstants.FIXED_DT * 0.5) < manual_activation_hold_until_runtime_time

func _should_keep_cluster_simplified(
		cluster_state: ClusterState,
		target_focus_global_position: Vector2,
		relevance_radius: float) -> bool:
	if cluster_state == null:
		return false
	if cluster_state.cluster_id == activation_override_cluster_id:
		return true
	if cluster_state.cluster_id == pending_manual_activation_cluster_id:
		return true
	if cluster_state.cluster_id == pending_auto_activation_cluster_id:
		return true
	if cluster_state.cluster_id == manual_activation_hold_cluster_id and _is_manual_activation_hold_active():
		return true
	if _is_cluster_simplified_relevant(cluster_state, target_focus_global_position, relevance_radius):
		return true
	return false

func _clear_pending_activation_target(target_cluster_id: int) -> void:
	if pending_manual_activation_cluster_id == target_cluster_id:
		pending_manual_activation_cluster_id = -1
	if pending_auto_activation_cluster_id == target_cluster_id:
		pending_auto_activation_cluster_id = -1
