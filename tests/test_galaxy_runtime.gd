extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const OBJECT_RESIDENCY_POLICY_SCRIPT := preload("res://simulation/object_residency_policy.gd")
const TRANSIT_OBJECT_STATE_SCRIPT := preload("res://simulation/transit_object_state.gd")

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

func test_active_dynamic_asteroid_exports_into_galaxy_transit_registry() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	config.black_hole_count = 6
	config.galaxy_cluster_count = 2
	config.star_count = 1
	config.planets_per_star = 0
	config.disturbance_body_count = 1

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var active_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state
	var target_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, active_cluster.cluster_id)
	var target_cluster: ClusterState = runtime.galaxy_state.get_cluster(target_cluster_id)
	var asteroid: SimBody = _find_active_body_of_type(runtime.get_active_sim_world(), SimBody.BodyType.ASTEROID)
	assert_not_null(asteroid, "the export test needs one free dynamic asteroid in the active cluster")

	var export_radius: float = OBJECT_RESIDENCY_POLICY_SCRIPT.transit_export_radius(active_cluster)
	var to_target_dir: Vector2 = (target_cluster.global_center - active_cluster.global_center).normalized()
	var outbound_dir: Vector2 = Vector2(-to_target_dir.y, to_target_dir.x)
	asteroid.position = outbound_dir * (export_radius + SimConstants.AU)
	asteroid.velocity = Vector2(0.0, 0.0)
	var exported_object_id: String = asteroid.persistent_object_id

	runtime.step(SimConstants.FIXED_DT)

	var transit_state = runtime.galaxy_state.get_transit_object(exported_object_id)
	assert_not_null(transit_state, "free dynamic asteroids beyond cluster ownership range should become transit records")
	assert_eq(
		runtime.get_transit_object_count(),
		1,
		"exporting a single asteroid should create exactly one transit record"
	)
	assert_false(
		active_cluster.has_object(exported_object_id),
		"objects exported into transit should leave the source cluster registry instead of remaining cluster-owned"
	)
	assert_null(
		runtime.get_active_sim_world().get_body_by_persistent_object_id(exported_object_id),
		"exported transit objects should no longer stay materialized in the active SimWorld"
	)
	assert_eq(
		transit_state.residency_state,
		ObjectResidencyState.State.IN_TRANSIT,
		"exported objects should explicitly move into IN_TRANSIT residency"
	)
	assert_eq(
		transit_state.source_cluster_id,
		active_cluster.cluster_id,
		"transit records should remember which cluster most recently owned the object"
	)
	assert_eq(
		transit_state.target_cluster_id,
		target_cluster_id,
		"exported objects should be assigned to the nearest non-source cluster as their first transfer target"
	)
	assert_eq(
		transit_state.arrival_phase,
		TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.EN_ROUTE,
		"objects outside the target cluster radius should remain en route until they actually enter the target cluster"
	)

func test_transit_routing_keeps_current_target_until_a_competitor_wins_by_clear_margin() -> void:
	var galaxy_state := GalaxyState.new()
	galaxy_state.add_cluster(_make_manual_cluster(0, Vector2.ZERO, 100.0))
	galaxy_state.add_cluster(_make_manual_cluster(1, Vector2(1000.0, 0.0), 100.0))
	galaxy_state.add_cluster(_make_manual_cluster(2, Vector2(1400.0, 0.0), 100.0))

	var transit_state = _make_test_transit_asteroid(
		"transit:routing_hysteresis",
		0,
		Vector2(1215.0, 0.0),
		Vector2.ZERO
	)
	transit_state.target_cluster_id = 1
	transit_state.arrival_phase = TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.EN_ROUTE
	galaxy_state.register_transit_object(transit_state)

	WorldBuilder.step_transit_objects(galaxy_state, SimConstants.FIXED_DT)

	assert_eq(
		transit_state.target_cluster_id,
		1,
		"routing should keep the current non-source target when a competing cluster is only marginally better"
	)
	assert_eq(
		transit_state.arrival_phase,
		TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.EN_ROUTE,
		"the retained target should stay en route while the object is still outside its import radius"
	)

	transit_state.global_position = Vector2(1230.0, 0.0)
	WorldBuilder.step_transit_objects(galaxy_state, SimConstants.FIXED_DT)

	assert_eq(
		transit_state.target_cluster_id,
		2,
		"routing should retarget once a competing cluster wins by a clear claim margin"
	)
	assert_eq(
		transit_state.arrival_phase,
		TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.EN_ROUTE,
		"clear retargets should still remain en route until the new target is actually reached"
	)

func test_grouped_transit_objects_share_one_group_target_and_centroid_routing() -> void:
	var galaxy_state := GalaxyState.new()
	galaxy_state.add_cluster(_make_manual_cluster(0, Vector2.ZERO, 100.0))
	galaxy_state.add_cluster(_make_manual_cluster(1, Vector2(1000.0, 0.0), 100.0))
	galaxy_state.add_cluster(_make_manual_cluster(2, Vector2(1400.0, 0.0), 100.0))

	var left_member = _make_test_transit_asteroid(
		"transit:group_left",
		0,
		Vector2(1080.0, 0.0),
		Vector2.ZERO,
		"convoy:test"
	)
	var right_member = _make_test_transit_asteroid(
		"transit:group_right",
		0,
		Vector2(1420.0, 0.0),
		Vector2.ZERO,
		"convoy:test"
	)
	galaxy_state.register_transit_object(left_member)
	galaxy_state.register_transit_object(right_member)

	WorldBuilder.step_transit_objects(galaxy_state, SimConstants.FIXED_DT)

	var transit_group = galaxy_state.get_transit_group("convoy:test")
	assert_not_null(transit_group, "grouped transit objects should create a durable transit group record")
	assert_eq(
		galaxy_state.get_transit_group_count(),
		1,
		"two grouped transit objects should be represented by one transit group"
	)
	assert_true(
		transit_group.global_position.is_equal_approx(Vector2(1250.0, 0.0)),
		"group routing should use the centroid of all grouped member positions"
	)
	assert_eq(
		transit_group.target_cluster_id,
		2,
		"the grouped convoy should choose one shared target from its centroid instead of splitting per member"
	)
	assert_eq(left_member.target_cluster_id, 2, "every group member should inherit the shared group target")
	assert_eq(right_member.target_cluster_id, 2, "every group member should inherit the shared group target")
	assert_eq(
		left_member.arrival_phase,
		TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.EN_ROUTE,
		"grouped routing should keep members en route until the shared group centroid reaches the target"
	)

func test_arriving_transit_object_settles_into_unloaded_target_cluster_as_resident() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	config.black_hole_count = 6
	config.galaxy_cluster_count = 2
	config.star_count = 1
	config.planets_per_star = 0
	config.disturbance_body_count = 0

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var source_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state
	var target_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, source_cluster.cluster_id)
	var target_cluster: ClusterState = runtime.galaxy_state.get_cluster(target_cluster_id)
	var import_radius: float = OBJECT_RESIDENCY_POLICY_SCRIPT.transit_import_radius(target_cluster)
	var transit_state = _make_test_transit_asteroid(
		"transit:resident_arrival",
		source_cluster.cluster_id,
		target_cluster.global_center + Vector2(import_radius * 0.5, 0.0),
		Vector2.ZERO
	)
	runtime.galaxy_state.register_transit_object(transit_state)

	runtime.step(SimConstants.FIXED_DT)

	var arrived_object: ClusterObjectState = target_cluster.get_object(transit_state.object_id)
	assert_eq(
		target_cluster.activation_state,
		ClusterActivationState.State.UNLOADED,
		"the resident arrival test expects the target cluster to stay unloaded during the handoff"
	)
	assert_not_null(arrived_object, "arriving transit objects should be written into their unloaded target cluster")
	assert_eq(
		arrived_object.residency_state,
		ObjectResidencyState.State.RESIDENT,
		"arrival into an unloaded target cluster should hand the object back as RESIDENT data"
	)
	assert_eq(
		runtime.get_transit_object_count(),
		0,
		"once a transit object is handed into an unloaded cluster it should leave the global transit registry"
	)

func test_resident_arrival_reappears_when_target_cluster_becomes_active() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	config.black_hole_count = 6
	config.galaxy_cluster_count = 2
	config.star_count = 1
	config.planets_per_star = 0
	config.disturbance_body_count = 0

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var source_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state
	var target_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, source_cluster.cluster_id)
	var target_cluster: ClusterState = runtime.galaxy_state.get_cluster(target_cluster_id)
	var import_radius: float = OBJECT_RESIDENCY_POLICY_SCRIPT.transit_import_radius(target_cluster)
	var transit_state = _make_test_transit_asteroid(
		"transit:reactivation_arrival",
		source_cluster.cluster_id,
		target_cluster.global_center + Vector2(import_radius * 0.5, 0.0),
		Vector2.ZERO
	)
	runtime.galaxy_state.register_transit_object(transit_state)

	runtime.step(SimConstants.FIXED_DT)
	runtime.activate_cluster(target_cluster_id)

	var imported_body: SimBody = runtime.get_active_sim_world().get_body_by_persistent_object_id(transit_state.object_id)
	assert_not_null(
		imported_body,
		"resident arrivals stored on an unloaded target cluster should re-materialize once that cluster becomes active"
	)
	assert_true(
		imported_body.position.is_equal_approx(runtime.active_cluster_session.to_local(transit_state.global_position)),
		"reactivating the target cluster should restore the resident arrival at the stored local arrival position"
	)

func test_in_transit_asteroid_imports_into_active_cluster_when_it_enters_cluster_space() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.CENTRAL_BH
	config.star_count = 1
	config.planets_per_star = 0
	config.disturbance_body_count = 0

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var active_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state
	var import_radius: float = OBJECT_RESIDENCY_POLICY_SCRIPT.transit_import_radius(active_cluster)
	var transit_state = _make_test_transit_asteroid(
		"transit:test_asteroid",
		-1,
		active_cluster.global_center + Vector2(import_radius * 0.5, 0.0),
		Vector2.ZERO
	)
	runtime.galaxy_state.register_transit_object(transit_state)

	runtime.step(SimConstants.FIXED_DT)

	var imported_body: SimBody = runtime.get_active_sim_world().get_body_by_persistent_object_id(transit_state.object_id)
	var persisted_object: ClusterObjectState = active_cluster.get_object(transit_state.object_id)
	assert_not_null(imported_body, "transit objects entering the active cluster should be re-materialized into SimWorld")
	assert_not_null(persisted_object, "imported transit objects should be written back into the active cluster registry")
	assert_eq(
		runtime.get_transit_object_count(),
		0,
		"importing a transit object should consume it from the galaxy transit registry"
	)
	assert_eq(
		persisted_object.residency_state,
		ObjectResidencyState.State.ACTIVE,
		"re-imported transit objects should become ACTIVE again once the local cluster owns them"
	)
	assert_true(
		imported_body.position.is_equal_approx(runtime.active_cluster_session.to_local(transit_state.global_position)),
		"transit import should convert the stored global position back into the active cluster's local space"
	)

func test_grouped_arrival_imports_all_members_into_active_cluster_together() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.CENTRAL_BH
	config.star_count = 1
	config.planets_per_star = 0
	config.disturbance_body_count = 0

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var active_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state
	var import_radius: float = OBJECT_RESIDENCY_POLICY_SCRIPT.transit_import_radius(active_cluster)
	var first_transit = _make_test_transit_asteroid(
		"transit:group_import_a",
		-1,
		active_cluster.global_center + Vector2(import_radius * 0.50, 0.0),
		Vector2.ZERO,
		"convoy:active_import"
	)
	var second_transit = _make_test_transit_asteroid(
		"transit:group_import_b",
		-1,
		active_cluster.global_center + Vector2(import_radius * 1.05, 0.0),
		Vector2.ZERO,
		"convoy:active_import"
	)
	runtime.galaxy_state.register_transit_object(first_transit)
	runtime.galaxy_state.register_transit_object(second_transit)

	runtime.step(SimConstants.FIXED_DT)

	var first_body: SimBody = runtime.get_active_sim_world().get_body_by_persistent_object_id(first_transit.object_id)
	var second_body: SimBody = runtime.get_active_sim_world().get_body_by_persistent_object_id(second_transit.object_id)
	var first_object: ClusterObjectState = active_cluster.get_object(first_transit.object_id)
	var second_object: ClusterObjectState = active_cluster.get_object(second_transit.object_id)
	assert_not_null(first_body, "group arrival should import the first member into the active cluster")
	assert_not_null(second_body, "group arrival should import the second member with the same shared handoff")
	assert_not_null(first_object, "group arrival should persist the first imported member in the active cluster")
	assert_not_null(second_object, "group arrival should persist the second imported member in the active cluster")
	assert_eq(
		runtime.get_transit_object_count(),
		0,
		"once a grouped arrival is handed into the active cluster the whole convoy should leave global transit"
	)
	assert_eq(
		str(first_object.descriptor.get("transfer_group_id", "")),
		"convoy:active_import",
		"imported group members should preserve their shared transfer-group identity for future re-export"
	)
	assert_eq(
		str(second_object.descriptor.get("transfer_group_id", "")),
		"convoy:active_import",
		"every imported group member should preserve the shared transfer-group identity"
	)

func test_transit_object_reacquires_its_source_cluster_when_it_returns_inside_source_space() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	config.black_hole_count = 6
	config.galaxy_cluster_count = 2
	config.star_count = 1
	config.planets_per_star = 0
	config.disturbance_body_count = 0

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var source_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state
	var competing_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, source_cluster.cluster_id)
	var import_radius: float = OBJECT_RESIDENCY_POLICY_SCRIPT.transit_import_radius(source_cluster)
	var transit_state = _make_test_transit_asteroid(
		"transit:source_reacquire",
		source_cluster.cluster_id,
		source_cluster.global_center + Vector2(import_radius * 0.5, 0.0),
		Vector2.ZERO
	)
	transit_state.target_cluster_id = competing_cluster_id
	transit_state.arrival_phase = TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.EN_ROUTE
	runtime.galaxy_state.register_transit_object(transit_state)

	runtime.step(SimConstants.FIXED_DT)

	var imported_body: SimBody = runtime.get_active_sim_world().get_body_by_persistent_object_id(transit_state.object_id)
	var persisted_object: ClusterObjectState = source_cluster.get_object(transit_state.object_id)
	assert_eq(
		runtime.get_transit_object_count(),
		0,
		"returning inside the source cluster should hand the object back out of global transit"
	)
	assert_not_null(
		imported_body,
		"source-cluster reacquire should re-materialize the returning object into the active local simulation"
	)
	assert_not_null(
		persisted_object,
		"source-cluster reacquire should restore the object into the source cluster registry"
	)
	assert_eq(
		persisted_object.residency_state,
		ObjectResidencyState.State.ACTIVE,
		"reacquiring into the active source cluster should make the object ACTIVE again"
	)

func test_dynamic_stars_do_not_enter_transit_in_the_first_narrow_pipeline() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.CENTRAL_BH
	config.star_count = 1
	config.planets_per_star = 0
	config.disturbance_body_count = 0

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var active_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state
	var star: SimBody = runtime.get_active_sim_world().get_star()
	var export_radius: float = OBJECT_RESIDENCY_POLICY_SCRIPT.transit_export_radius(active_cluster)
	star.position = Vector2(export_radius + SimConstants.AU, 0.0)
	star.velocity = Vector2.ZERO

	runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.get_transit_object_count(),
		0,
		"the first transit pipeline should stay narrow and avoid exporting dynamic stars yet"
	)
	assert_not_null(
		runtime.get_active_sim_world().get_body_by_persistent_object_id(star.persistent_object_id),
		"unsupported object types should remain owned by the active cluster for now"
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

func _make_manual_cluster(cluster_id: int, global_center: Vector2, radius: float) -> ClusterState:
	var cluster_state := ClusterState.new()
	cluster_state.cluster_id = cluster_id
	cluster_state.global_center = global_center
	cluster_state.radius = radius
	cluster_state.cluster_seed = 10_000 + cluster_id
	cluster_state.classification = "test_cluster"
	cluster_state.activation_state = ClusterActivationState.State.UNLOADED
	return cluster_state

func _find_secondary_cluster_id(galaxy_state: GalaxyState, active_cluster_id: int) -> int:
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id != active_cluster_id:
			return cluster_state.cluster_id
	return -1

func _find_active_body_of_type(world: SimWorld, body_type: int) -> SimBody:
	for body in world.bodies:
		if body.active and body.body_type == body_type:
			return body
	return null

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

func _make_test_transit_asteroid(
		object_id: String,
		source_cluster_id: int,
		global_position: Vector2,
		global_velocity: Vector2,
		transfer_group_id: String = ""):
	var transit_state = TRANSIT_OBJECT_STATE_SCRIPT.new()
	transit_state.object_id = object_id
	transit_state.kind = "asteroid"
	transit_state.source_cluster_id = source_cluster_id
	transit_state.transfer_group_id = transfer_group_id
	transit_state.global_position = global_position
	transit_state.global_velocity = global_velocity
	transit_state.seed = 12345
	transit_state.descriptor = {
		"body_type": SimBody.BodyType.ASTEROID,
		"material_type": SimBody.MaterialType.ROCKY,
		"influence_level": SimBody.InfluenceLevel.B,
		"mass": 8.0,
		"radius": 3.0,
		"temperature": 200.0,
		"kinematic": false,
		"scripted_orbit_enabled": false,
		"orbit_binding_state": SimBody.OrbitBindingState.FREE_DYNAMIC,
		"orbit_radius": 0.0,
		"orbit_angle": 0.0,
		"orbit_angular_speed": 0.0,
		"debris_mass": 0.0,
		"sleeping": false,
		"active": true,
		"parent_object_id": "",
		"transfer_group_id": transfer_group_id,
	}
	return transit_state
