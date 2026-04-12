## Runtime wrapper that owns the active local simulation projection for one cluster.
class_name ActiveClusterSession
extends RefCounted

var galaxy_state: GalaxyState = null
var active_cluster_state: ClusterState = null
var cluster_id: int = -1
var cluster_global_origin: Vector2 = Vector2.ZERO
var sim_world: SimWorld = null

func bind(next_galaxy_state: GalaxyState, next_cluster_state: ClusterState, next_sim_world: SimWorld) -> void:
	if galaxy_state != null and active_cluster_state != null and active_cluster_state.cluster_id != next_cluster_state.cluster_id:
		active_cluster_state.activation_state = ClusterActivationState.State.SIMPLIFIED
	galaxy_state = next_galaxy_state
	active_cluster_state = next_cluster_state
	cluster_id = next_cluster_state.cluster_id
	cluster_global_origin = next_cluster_state.global_center
	sim_world = next_sim_world
	active_cluster_state.activation_state = ClusterActivationState.State.ACTIVE

func to_global(local_position: Vector2) -> Vector2:
	return cluster_global_origin + local_position

func to_local(global_position: Vector2) -> Vector2:
	return global_position - cluster_global_origin

func set_black_hole_mass(new_mass: float) -> void:
	if active_cluster_state == null:
		return
	active_cluster_state.simulation_profile["black_hole_mass"] = new_mass
	var layout_specs: Array = active_cluster_state.cluster_blueprint.get("local_black_hole_specs", [])
	for spec in layout_specs:
		spec["mass"] = new_mass
	for object_state in active_cluster_state.get_objects_by_kind("black_hole"):
		object_state.descriptor["mass"] = new_mass
	if sim_world != null:
		sim_world.set_black_hole_mass(new_mass)

