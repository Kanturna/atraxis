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

func test_simplified_cluster_step_applies_black_hole_pull_to_deactivated_dynamic_body() -> void:
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
	var black_hole_states: Array = first_cluster.get_objects_by_kind("black_hole")
	var expected_acceleration: Vector2 = _compute_black_hole_only_acceleration(simplified_star, black_hole_states)
	var expected_velocity: Vector2 = old_velocity + expected_acceleration * SimConstants.FIXED_DT
	var expected_position: Vector2 = old_position + expected_velocity * SimConstants.FIXED_DT

	runtime.step(SimConstants.FIXED_DT)

	var advanced_star: ClusterObjectState = first_cluster.get_object(saved_object_id)
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
		"simplified stepping should advance remote dynamic bodies with the stored BH pull on x"
	)
	assert_almost_eq(
		advanced_star.local_position.y,
		expected_position.y,
		0.01,
		"simplified stepping should advance remote dynamic bodies with the stored BH pull on y"
	)
	assert_almost_eq(
		advanced_star.local_velocity.x,
		expected_velocity.x,
		0.01,
		"simplified stepping should update remote dynamic x velocity from black-hole pull"
	)
	assert_almost_eq(
		advanced_star.local_velocity.y,
		expected_velocity.y,
		0.01,
		"simplified stepping should update remote dynamic y velocity from black-hole pull"
	)
	assert_eq(
		advanced_star.residency_state,
		ObjectResidencyState.State.SIMPLIFIED,
		"simplified stepping should keep remote objects marked as simplified"
	)

func test_focus_relevance_switches_active_cluster_to_nearest_focus_cluster() -> void:
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
	var second_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, first_cluster_id)
	var second_cluster: ClusterState = runtime.galaxy_state.get_cluster(second_cluster_id)

	runtime.update_focus_context(second_cluster.global_center, 0.0)
	runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.active_cluster_session.cluster_id,
		second_cluster_id,
		"focus relevance should promote the cluster nearest the focus position into the active bubble"
	)

func test_focus_relevance_keeps_nearest_remote_cluster_simplified_while_it_stays_relevant() -> void:
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
	var second_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, first_cluster_id)
	var second_cluster: ClusterState = runtime.galaxy_state.get_cluster(second_cluster_id)
	var focus_radius: float = first_cluster.global_center.distance_to(second_cluster.global_center)

	runtime.update_focus_context(first_cluster.global_center, focus_radius)

	var steps_to_cover_unload_delay: int = int(ceil(
		SimConstants.CLUSTER_SIMPLIFIED_UNLOAD_DELAY / SimConstants.FIXED_DT
	)) + 2
	for _i in range(steps_to_cover_unload_delay):
		runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		second_cluster.activation_state,
		ClusterActivationState.State.SIMPLIFIED,
		"clusters that remain relevant to the current focus should stay simplified instead of unloading"
	)
	assert_true(
		second_cluster.last_relevance_runtime_time > second_cluster.last_unloaded_runtime_time,
		"relevant simplified clusters should keep refreshing their relevance timestamp"
	)

func test_manual_activation_request_overrides_focus_temporarily_then_releases_back_to_auto() -> void:
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
	var second_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, first_cluster_id)

	runtime.update_focus_context(first_cluster.global_center, 0.0)
	assert_true(
		runtime.request_cluster_activation(second_cluster_id),
		"manual activation requests should be accepted for non-active clusters"
	)

	runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.active_cluster_session.cluster_id,
		second_cluster_id,
		"manual activation requests should beat automatic focus selection on the next runtime step"
	)

	var grace_steps: int = int(ceil(
		SimConstants.CLUSTER_MANUAL_ACTIVATION_GRACE_PERIOD / SimConstants.FIXED_DT
	)) - 1
	for _i in range(maxi(grace_steps, 0)):
		runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.active_cluster_session.cluster_id,
		second_cluster_id,
		"manual activation should hold the requested cluster briefly before auto focus takes back over"
	)

	runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.active_cluster_session.cluster_id,
		first_cluster_id,
		"after the grace window ends, automatic focus relevance should regain control"
	)

func test_activation_override_pins_cluster_until_cleared() -> void:
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
	var second_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, first_cluster_id)

	runtime.update_focus_context(first_cluster.global_center, 0.0)
	assert_true(
		runtime.request_cluster_activation_override(second_cluster_id),
		"override requests should be accepted for valid clusters"
	)

	runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.active_cluster_session.cluster_id,
		second_cluster_id,
		"override requests should switch the active cluster even against the current focus"
	)
	assert_true(runtime.has_cluster_activation_override(), "override state should stay active until explicitly cleared")
	assert_eq(
		runtime.get_cluster_activation_override_id(),
		second_cluster_id,
		"runtime should expose which cluster is currently pinned by override"
	)

	var steps_past_grace: int = int(ceil(
		(SimConstants.CLUSTER_MANUAL_ACTIVATION_GRACE_PERIOD + SimConstants.FIXED_DT) / SimConstants.FIXED_DT
	)) + 2
	for _i in range(steps_past_grace):
		runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.active_cluster_session.cluster_id,
		second_cluster_id,
		"persistent overrides should keep the pinned cluster active after the temporary manual grace period"
	)

	runtime.clear_cluster_activation_override()
	runtime.step(SimConstants.FIXED_DT)

	assert_false(runtime.has_cluster_activation_override(), "override state should clear cleanly")
	assert_eq(
		runtime.active_cluster_session.cluster_id,
		first_cluster_id,
		"after clearing the override, automatic focus relevance should take control again"
	)

func test_simplified_cluster_unloads_after_idle_delay() -> void:
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
	var persisted_star_id: String = first_star.persistent_object_id
	var second_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, first_cluster_id)

	runtime.activate_cluster(second_cluster_id)

	var steps_until_unload: int = int(ceil(
		SimConstants.CLUSTER_SIMPLIFIED_UNLOAD_DELAY / SimConstants.FIXED_DT
	)) + 1
	for _i in range(steps_until_unload):
		runtime.step(SimConstants.FIXED_DT)

	var unloaded_star: ClusterObjectState = first_cluster.get_object(persisted_star_id)
	assert_eq(
		first_cluster.activation_state,
		ClusterActivationState.State.UNLOADED,
		"simplified clusters should freeze back into unloaded source state after the unload delay"
	)
	assert_eq(
		unloaded_star.residency_state,
		ObjectResidencyState.State.RESIDENT,
		"unloaded clusters should persist objects as resident data instead of active or simplified runtime state"
	)
	assert_true(
		first_cluster.last_unloaded_runtime_time - first_cluster.last_deactivated_runtime_time
			>= SimConstants.CLUSTER_SIMPLIFIED_UNLOAD_DELAY,
		"unload policy should wait at least the configured simplified idle delay"
	)

func test_pending_manual_target_is_not_unloaded_before_activation() -> void:
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
	var second_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, first_cluster_id)
	var second_cluster: ClusterState = runtime.galaxy_state.get_cluster(second_cluster_id)

	assert_eq(
		second_cluster.activation_state,
		ClusterActivationState.State.UNLOADED,
		"secondary clusters should start unloaded before they become relevant or targeted"
	)
	assert_true(
		runtime.request_cluster_activation(second_cluster_id),
		"manual activation requests should be queueable before the next runtime step"
	)

	var steps_past_unload_delay: int = int(ceil(
		(SimConstants.CLUSTER_SIMPLIFIED_UNLOAD_DELAY + SimConstants.CLUSTER_MANUAL_ACTIVATION_GRACE_PERIOD) / SimConstants.FIXED_DT
	))
	for _i in range(steps_past_unload_delay):
		runtime.step(SimConstants.FIXED_DT)
		if runtime.active_cluster_session.cluster_id == second_cluster_id:
			break

	assert_eq(
		runtime.active_cluster_session.cluster_id,
		second_cluster_id,
		"queued manual targets should remain activatable instead of being lost to auto unload pressure"
	)

func test_unloaded_cluster_reloads_from_persisted_snapshot() -> void:
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
	var persisted_star_id: String = first_star.persistent_object_id
	var second_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, first_cluster_id)

	runtime.step(SimConstants.FIXED_DT)
	runtime.activate_cluster(second_cluster_id)

	var steps_until_unload: int = int(ceil(
		SimConstants.CLUSTER_SIMPLIFIED_UNLOAD_DELAY / SimConstants.FIXED_DT
	)) + 1
	for _i in range(steps_until_unload):
		runtime.step(SimConstants.FIXED_DT)

	var persisted_star: ClusterObjectState = first_cluster.get_object(persisted_star_id)
	var persisted_position: Vector2 = persisted_star.local_position
	var persisted_time: float = first_cluster.simulated_time

	runtime.activate_cluster(first_cluster_id)

	var reloaded_star: SimBody = runtime.get_active_sim_world().get_star()
	assert_eq(
		first_cluster.activation_state,
		ClusterActivationState.State.ACTIVE,
		"reactivating an unloaded cluster should promote it back into the active bubble"
	)
	assert_true(
		reloaded_star.position.is_equal_approx(persisted_position),
		"unloaded clusters should reload from their persisted snapshot state instead of regenerating a different runtime layout"
	)
	assert_almost_eq(
		runtime.get_active_sim_world().time_elapsed,
		persisted_time,
		0.0001,
		"reloading an unloaded cluster should restore its persisted simulation time"
	)

func test_cluster_activation_request_switches_cluster_on_next_step() -> void:
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
	var second_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, first_cluster_id)

	assert_true(
		runtime.request_cluster_activation(second_cluster_id),
		"valid non-active clusters should be accepted as queued activation targets"
	)
	assert_true(runtime.has_pending_activation_request(), "queued activation requests should remain pending until the next runtime step")
	assert_eq(
		runtime.get_pending_activation_cluster_id(),
		second_cluster_id,
		"runtime should expose which cluster is queued for activation"
	)
	assert_eq(
		runtime.active_cluster_session.cluster_id,
		first_cluster_id,
		"requesting a cluster switch should not replace the active session until the runtime advances"
	)

	runtime.step(SimConstants.FIXED_DT)

	assert_false(runtime.has_pending_activation_request(), "the queued activation should be consumed by the next runtime step")
	assert_eq(
		runtime.active_cluster_session.cluster_id,
		second_cluster_id,
		"queued activation requests should switch the active cluster at the start of the next runtime step"
	)

func _find_secondary_cluster_id(galaxy_state: GalaxyState, active_cluster_id: int) -> int:
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id != active_cluster_id:
			return cluster_state.cluster_id
	return -1

func _compute_black_hole_only_acceleration(object_state: ClusterObjectState, black_hole_states: Array) -> Vector2:
	var acceleration: Vector2 = Vector2.ZERO
	for black_hole_state in black_hole_states:
		var delta: Vector2 = black_hole_state.local_position - object_state.local_position
		var dist_sq: float = delta.length_squared() + SimConstants.GRAVITY_SOFTENING_SQ
		if dist_sq <= 0.0:
			continue
		var inv_dist: float = 1.0 / sqrt(dist_sq)
		var accel_scale: float = SimConstants.G \
			* float(black_hole_state.descriptor.get("mass", SimConstants.BLACK_HOLE_MASS)) \
			/ dist_sq
		acceleration += delta * inv_dist * accel_scale
	return acceleration
