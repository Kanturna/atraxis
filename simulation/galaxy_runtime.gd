## Owns the active cluster session and advances simplified remote clusters.
## GalaxyState remains the durable truth; this class coordinates runtime writes
## back into that truth and activates one local SimWorld projection at a time.
class_name GalaxyRuntime
extends RefCounted

var galaxy_state: GalaxyState = null
var active_cluster_session: ActiveClusterSession = null

func initialize(next_galaxy_state: GalaxyState, initial_cluster_id: int = -1) -> void:
	galaxy_state = next_galaxy_state
	active_cluster_session = null
	if galaxy_state == null or galaxy_state.get_cluster_count() == 0:
		return

	var resolved_cluster_id: int = initial_cluster_id if initial_cluster_id >= 0 else galaxy_state.primary_cluster_id
	_activate_cluster_internal(resolved_cluster_id)

func step(dt: float) -> void:
	if dt <= 0.0:
		return
	if active_cluster_session != null and active_cluster_session.sim_world != null:
		active_cluster_session.sim_world.step_sim(dt)
		WorldBuilder.writeback_world_into_cluster(
			active_cluster_session.sim_world,
			active_cluster_session.active_cluster_state,
			ObjectResidencyState.State.ACTIVE
		)
	_step_simplified_clusters(dt)

func activate_cluster(target_cluster_id: int) -> void:
	if galaxy_state == null:
		return
	var target_cluster: ClusterState = galaxy_state.get_cluster(target_cluster_id)
	if target_cluster == null:
		return
	if active_cluster_session != null and active_cluster_session.cluster_id == target_cluster_id:
		return

	if active_cluster_session != null and active_cluster_session.sim_world != null:
		WorldBuilder.writeback_world_into_cluster(
			active_cluster_session.sim_world,
			active_cluster_session.active_cluster_state,
			ObjectResidencyState.State.SIMPLIFIED
		)
		active_cluster_session.active_cluster_state.activation_state = ClusterActivationState.State.SIMPLIFIED
		active_cluster_session.active_cluster_state.set_object_residency_state(
			ObjectResidencyState.State.SIMPLIFIED
		)

	_activate_cluster_internal(target_cluster_id)

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

func _activate_cluster_internal(target_cluster_id: int) -> void:
	active_cluster_session = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state, target_cluster_id)
	if active_cluster_session == null or active_cluster_session.active_cluster_state == null:
		return
	active_cluster_session.active_cluster_state.activation_state = ClusterActivationState.State.ACTIVE
	active_cluster_session.active_cluster_state.set_object_residency_state(ObjectResidencyState.State.ACTIVE)
	if active_cluster_session.sim_world != null:
		WorldBuilder.writeback_world_into_cluster(
			active_cluster_session.sim_world,
			active_cluster_session.active_cluster_state,
			ObjectResidencyState.State.ACTIVE
		)

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
