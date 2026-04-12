extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")

func test_runtime_step_writes_active_cluster_back_into_source_of_truth() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	config.black_hole_count = 5
	config.star_count = 2
	config.planets_per_star = 2
	config.disturbance_body_count = 1

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var active_world: SimWorld = runtime.get_active_sim_world()
	var active_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state

	runtime.step(SimConstants.FIXED_DT)

	assert_true(
		active_cluster.simulation_profile.get("has_runtime_snapshot", false),
		"runtime stepping should persist an active cluster snapshot into ClusterState"
	)
	assert_eq(
		active_cluster.activation_state,
		ClusterActivationState.State.ACTIVE,
		"the active cluster should stay active after runtime stepping"
	)
	assert_eq(
		active_cluster.get_objects_by_kind("star").size(),
		config.star_count,
		"writeback should persist every active star into the cluster registry"
	)
	assert_eq(
		active_cluster.get_objects_by_kind("planet").size(),
		config.star_count * config.planets_per_star,
		"writeback should persist every active planet into the cluster registry"
	)
	assert_eq(
		active_cluster.get_objects_by_kind("asteroid").size(),
		config.disturbance_body_count,
		"writeback should persist active disturbance bodies into the cluster registry"
	)

	var world_star: SimBody = active_world.get_star()
	var persisted_star: ClusterObjectState = active_cluster.get_object(world_star.persistent_object_id)
	assert_not_null(persisted_star, "the active star should be addressable through its persisted object id")
	assert_true(
		persisted_star.local_position.is_equal_approx(world_star.position),
		"writeback should copy the active star position into the cluster truth"
	)
	assert_true(
		persisted_star.local_velocity.is_equal_approx(world_star.velocity),
		"writeback should copy the active star velocity into the cluster truth"
	)
	assert_eq(
		persisted_star.residency_state,
		ObjectResidencyState.State.ACTIVE,
		"active writeback should mark persisted objects as active"
	)
	assert_almost_eq(
		active_cluster.simulated_time,
		active_world.time_elapsed,
		0.0001,
		"cluster simulated time should track the active SimWorld time"
	)

func test_runtime_cluster_switch_writes_back_and_reloads_from_snapshot() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	config.black_hole_count = 9
	config.galaxy_cluster_count = 3
	config.star_count = 1
	config.planets_per_star = 1
	config.disturbance_body_count = 0

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var first_cluster_id: int = runtime.active_cluster_session.cluster_id
	var first_cluster: ClusterState = runtime.galaxy_state.get_cluster(first_cluster_id)
	var first_star: SimBody = runtime.get_active_sim_world().get_star()

	runtime.step(SimConstants.FIXED_DT)
	var saved_position: Vector2 = first_star.position
	var saved_object_id: String = first_star.persistent_object_id

	var second_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, first_cluster_id)
	assert_true(second_cluster_id != -1, "the runtime test needs a second cluster to switch to")

	runtime.activate_cluster(second_cluster_id)

	var persisted_star: ClusterObjectState = first_cluster.get_object(saved_object_id)
	assert_not_null(persisted_star, "deactivation should write the active star back into the previous cluster")
	assert_eq(
		first_cluster.activation_state,
		ClusterActivationState.State.SIMPLIFIED,
		"switching away should demote the previous active cluster to simplified"
	)
	assert_eq(
		persisted_star.residency_state,
		ObjectResidencyState.State.SIMPLIFIED,
		"deactivated cluster objects should switch to simplified residency"
	)
	assert_true(
		persisted_star.local_position.is_equal_approx(saved_position),
		"cluster switch should preserve the written-back star position exactly"
	)

	runtime.activate_cluster(first_cluster_id)

	var reloaded_star: SimBody = runtime.get_active_sim_world().get_star()
	assert_not_null(reloaded_star, "reactivating a simplified cluster should rebuild its persisted star")
	assert_eq(
		runtime.active_cluster_session.cluster_id,
		first_cluster_id,
		"reactivation should restore the requested cluster as active"
	)
	assert_true(
		reloaded_star.position.is_equal_approx(persisted_star.local_position),
		"reactivating from a runtime snapshot should restore the persisted star position"
	)
	assert_almost_eq(
		runtime.get_active_sim_world().time_elapsed,
		first_cluster.simulated_time,
		0.0001,
		"reactivation should restore the cluster's persisted simulation time into SimWorld"
	)

func test_simplified_cluster_step_advances_deactivated_dynamic_body_linearly() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	config.black_hole_count = 9
	config.galaxy_cluster_count = 3
	config.star_count = 1
	config.planets_per_star = 1
	config.disturbance_body_count = 0

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var first_cluster_id: int = runtime.active_cluster_session.cluster_id
	var first_cluster: ClusterState = runtime.galaxy_state.get_cluster(first_cluster_id)

	runtime.step(SimConstants.FIXED_DT)
	var first_star: SimBody = runtime.get_active_sim_world().get_star()
	var saved_object_id: String = first_star.persistent_object_id
	var second_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, first_cluster_id)
	runtime.activate_cluster(second_cluster_id)

	var simplified_star: ClusterObjectState = first_cluster.get_object(saved_object_id)
	var old_position: Vector2 = simplified_star.local_position
	var old_velocity: Vector2 = simplified_star.local_velocity
	var old_time: float = first_cluster.simulated_time

	runtime.step(SimConstants.FIXED_DT)

	var advanced_star: ClusterObjectState = first_cluster.get_object(saved_object_id)
	var expected_position: Vector2 = old_position + old_velocity * SimConstants.FIXED_DT
	assert_eq(
		first_cluster.activation_state,
		ClusterActivationState.State.SIMPLIFIED,
		"simplified stepping should keep the remote cluster in simplified state"
	)
	assert_almost_eq(
		first_cluster.simulated_time,
		old_time + SimConstants.FIXED_DT,
		0.0001,
		"simplified stepping should advance cluster simulated time"
	)
	assert_almost_eq(
		advanced_star.local_position.x,
		expected_position.x,
		0.01,
		"simplified stepping should advance remote dynamic bodies along their stored x velocity"
	)
	assert_almost_eq(
		advanced_star.local_position.y,
		expected_position.y,
		0.01,
		"simplified stepping should advance remote dynamic bodies along their stored y velocity"
	)
	assert_eq(
		advanced_star.residency_state,
		ObjectResidencyState.State.SIMPLIFIED,
		"simplified stepping should keep remote objects marked as simplified"
	)

func _find_secondary_cluster_id(galaxy_state: GalaxyState, active_cluster_id: int) -> int:
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id != active_cluster_id:
			return cluster_state.cluster_id
	return -1
