extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const ACTIVE_SECTOR_SESSION_SCRIPT := preload("res://simulation/active_sector_session.gd")
const MACRO_SECTOR_ZONE_SCRIPT := preload("res://simulation/macro_sector_zone.gd")
const OBJECT_RESIDENCY_POLICY_SCRIPT := preload("res://simulation/object_residency_policy.gd")
const TRANSIT_OBJECT_STATE_SCRIPT := preload("res://simulation/transit_object_state.gd")
const WORLD_ENTITY_STATE_SCRIPT := preload("res://simulation/world_entity_state.gd")

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
	var galaxy_state: GalaxyState = _make_manual_runtime_snapshot_galaxy(3)
	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_galaxy_state(galaxy_state, 0)
	var first_cluster_id: int = 0
	var first_cluster: ClusterState = galaxy_state.get_cluster(first_cluster_id)

	runtime.step(SimConstants.FIXED_DT)
	var first_star: SimBody = runtime.get_active_sim_world().get_star()
	var saved_object_id: String = first_star.persistent_object_id
	var second_cluster_id: int = 1
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

func test_active_macro_sector_caps_members_and_assigns_ambient_and_far_zones() -> void:
	var galaxy_state: GalaxyState = _make_manual_runtime_snapshot_galaxy(7)
	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_galaxy_state(galaxy_state, 0)
	var descriptor = runtime.get_active_macro_sector()

	assert_not_null(descriptor, "runtime should expose the active macro sector descriptor once initialized")
	assert_eq(descriptor.member_cluster_ids.size(), 5, "v1 macro sectors should cap membership at five clusters")
	assert_eq(descriptor.focus_cluster_id, 0, "the initial focus cluster should seed the macro sector focus id")
	assert_eq(runtime.get_cluster_macro_sector_zone(0), MACRO_SECTOR_ZONE_SCRIPT.Zone.FOCUS, "the active cluster should be the macro sector focus zone")
	assert_eq(runtime.get_cluster_macro_sector_zone(1), MACRO_SECTOR_ZONE_SCRIPT.Zone.AMBIENT, "the nearest remote cluster should become an ambient neighbor")
	assert_eq(runtime.get_cluster_macro_sector_zone(2), MACRO_SECTOR_ZONE_SCRIPT.Zone.AMBIENT, "the second nearest remote cluster should also stay ambient")
	assert_eq(runtime.get_cluster_macro_sector_zone(3), MACRO_SECTOR_ZONE_SCRIPT.Zone.FAR, "more distant members should downgrade into the far zone")
	assert_eq(runtime.get_cluster_macro_sector_zone(4), MACRO_SECTOR_ZONE_SCRIPT.Zone.FAR, "the fifth member should still remain inside the macro sector as far structure")
	assert_eq(runtime.get_cluster_macro_sector_zone(5), MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE, "clusters beyond the five-member cap should stay outside the active macro sector")
	assert_eq(runtime.get_cluster_macro_sector_zone(6), MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE, "extra distant clusters should remain outside the active macro sector")

func test_macro_sector_zone_step_budget_advances_ambient_each_tick_and_far_in_batches() -> void:
	var galaxy_state: GalaxyState = _make_manual_runtime_snapshot_galaxy(7)
	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_galaxy_state(galaxy_state, 0)

	runtime.step(SimConstants.FIXED_DT)

	assert_almost_eq(
		galaxy_state.get_cluster(1).simulated_time,
		SimConstants.FIXED_DT,
		0.0001,
		"ambient cluster 1 should advance every fixed tick"
	)
	assert_almost_eq(
		galaxy_state.get_cluster(2).simulated_time,
		SimConstants.FIXED_DT,
		0.0001,
		"ambient cluster 2 should also advance every fixed tick"
	)
	assert_almost_eq(
		galaxy_state.get_cluster(3).simulated_time,
		0.0,
		0.0001,
		"far cluster 3 should stay frozen until the batched far-zone interval elapses"
	)
	assert_almost_eq(
		galaxy_state.get_cluster(4).simulated_time,
		0.0,
		0.0001,
		"far cluster 4 should also wait for the batched far-zone step"
	)
	assert_almost_eq(
		galaxy_state.get_cluster(5).simulated_time,
		0.0,
		0.0001,
		"clusters outside the macro sector should not receive simplified runtime steps"
	)
	assert_almost_eq(
		galaxy_state.get_cluster(6).simulated_time,
		0.0,
		0.0001,
		"non-member clusters should stay frozen outside the active macro sector"
	)

	for _i in range(3):
		runtime.step(SimConstants.FIXED_DT)

	assert_almost_eq(
		galaxy_state.get_cluster(1).simulated_time,
		SimConstants.FIXED_DT * 4.0,
		0.0001,
		"ambient clusters should continue stepping every tick across the full batch window"
	)
	assert_almost_eq(
		galaxy_state.get_cluster(2).simulated_time,
		SimConstants.FIXED_DT * 4.0,
		0.0001,
		"both ambient members should stay fully live inside the simplified budget"
	)
	assert_almost_eq(
		galaxy_state.get_cluster(3).simulated_time,
		SimConstants.FIXED_DT * 4.0,
		0.0001,
		"far clusters should catch up in one bundled 4x fixed-dt step"
	)
	assert_almost_eq(
		galaxy_state.get_cluster(4).simulated_time,
		SimConstants.FIXED_DT * 4.0,
		0.0001,
		"every far member should advance only on the four-tick cadence"
	)
	assert_almost_eq(
		galaxy_state.get_cluster(5).simulated_time,
		0.0,
		0.0001,
		"clusters outside the active macro sector should remain frozen even after the far-zone batch"
	)
	assert_almost_eq(
		galaxy_state.get_cluster(6).simulated_time,
		0.0,
		0.0001,
		"the runtime should still avoid spending simplified steps on non-members"
	)

func test_focus_context_keeps_active_sector_stable_within_sector_bounds() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 144
	config.cluster_density = 1.0
	config.void_strength = 0.0
	config.bh_richness = 0.82
	config.star_richness = 0.52
	config.rare_zone_frequency = 0.55

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var initial_sector_state = runtime.get_active_sector_state()
	assert_not_null(initial_sector_state, "the sector continuity test needs an active rectangular sector")
	assert_not_null(runtime.active_cluster_session, "the sector continuity test needs a loaded contained system")
	var initial_sector_coord: Vector2i = initial_sector_state.sector_coord
	var initial_cluster_id: int = runtime.active_cluster_session.cluster_id
	var in_sector_focus: Vector2 = initial_sector_state.global_origin + Vector2(
		initial_sector_state.size * 0.78,
		initial_sector_state.size * 0.24
	)

	runtime.update_focus_context(in_sector_focus, initial_sector_state.size * 0.35)
	for _i in range(4):
		runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.get_active_sector_state().sector_coord,
		initial_sector_coord,
		"camera movement inside one rectangular sector should not trigger a top-level sector switch"
	)
	assert_eq(
		runtime.active_cluster_session.cluster_id,
		initial_cluster_id,
		"the contained system should stay loaded while the camera moves around inside the same sector"
	)

func test_active_sector_session_anchors_local_frame_to_sector_center_even_with_loaded_system() -> void:
	var galaxy_state := GalaxyState.new()
	var sector_state = galaxy_state.get_or_create_sector_state(Vector2i(0, 0))
	sector_state.global_origin = Vector2(-800.0, -800.0)
	sector_state.size = 1_600.0

	var cluster_state := ClusterState.new()
	cluster_state.cluster_id = 7
	cluster_state.global_center = Vector2(320.0, -140.0)
	var cluster_session := ActiveClusterSession.new()
	cluster_session.bind(galaxy_state, cluster_state, SimWorld.new())

	var sector_session = ACTIVE_SECTOR_SESSION_SCRIPT.new()
	sector_session.bind(galaxy_state, sector_state, cluster_session)

	assert_true(
		sector_session.frame_global_origin.is_equal_approx(sector_state.center()),
		"the active rectangular-sector frame should stay pinned to the sector center even when a system is loaded"
	)
	assert_true(
		sector_session.cluster_frame_offset().is_equal_approx(cluster_state.global_center - sector_state.center()),
		"loaded systems should become contained offsets inside the sector frame instead of redefining the frame origin"
	)

func test_active_sector_session_can_preserve_existing_view_frame_origin_across_sector_switch() -> void:
	var galaxy_state := GalaxyState.new()
	var first_sector_state = galaxy_state.get_or_create_sector_state(Vector2i(0, 0))
	first_sector_state.global_origin = Vector2(-800.0, -800.0)
	first_sector_state.size = 1_600.0
	var second_sector_state = galaxy_state.get_or_create_sector_state(Vector2i(1, 0))
	second_sector_state.global_origin = Vector2(800.0, -800.0)
	second_sector_state.size = 1_600.0

	var first_sector_session = ACTIVE_SECTOR_SESSION_SCRIPT.new()
	first_sector_session.bind(galaxy_state, first_sector_state)

	var cluster_state := ClusterState.new()
	cluster_state.cluster_id = 8
	cluster_state.global_center = Vector2(1_360.0, -120.0)
	var cluster_session := ActiveClusterSession.new()
	cluster_session.bind(galaxy_state, cluster_state, SimWorld.new())

	var second_sector_session = ACTIVE_SECTOR_SESSION_SCRIPT.new()
	second_sector_session.bind(
		galaxy_state,
		second_sector_state,
		cluster_session,
		first_sector_session.frame_global_origin
	)

	assert_true(
		second_sector_session.frame_global_origin.is_equal_approx(first_sector_session.frame_global_origin),
		"sector switches should be able to preserve the existing view-frame origin instead of snapping to the new tile center"
	)
	assert_true(
		second_sector_session.cluster_frame_offset().is_equal_approx(
			cluster_state.global_center - first_sector_session.frame_global_origin
		),
		"contained systems in the new sector should be localized against the preserved view frame"
	)

func test_focus_context_switches_active_sector_once_when_crossing_sector_boundary() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 144
	config.cluster_density = 1.0
	config.void_strength = 0.0
	config.bh_richness = 0.82
	config.star_richness = 0.52
	config.rare_zone_frequency = 0.55

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var initial_sector_state = runtime.get_active_sector_state()
	assert_not_null(initial_sector_state, "the sector-boundary test needs an active rectangular sector")
	var initial_sector_coord: Vector2i = initial_sector_state.sector_coord
	var target_sector_coord := initial_sector_coord + Vector2i(1, 0)
	var crossed_focus: Vector2 = initial_sector_state.global_origin + Vector2(
		initial_sector_state.size * 1.5,
		initial_sector_state.size * 0.5
	)

	runtime.update_focus_context(crossed_focus, 0.0)
	runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.get_active_sector_state().sector_coord,
		target_sector_coord,
		"crossing a rectangular sector boundary should switch the top-level active sector exactly at the new tile"
	)

	runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.get_active_sector_state().sector_coord,
		target_sector_coord,
		"once the camera is inside the new sector, follow-up steps should keep the new top-level sector stable"
	)

func test_sector_boundary_switch_preserves_view_frame_and_focus_projection() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 144
	config.cluster_density = 1.0
	config.void_strength = 0.0
	config.bh_richness = 0.82
	config.star_richness = 0.52
	config.rare_zone_frequency = 0.55

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var initial_sector_state = runtime.get_active_sector_state()
	assert_not_null(initial_sector_state, "the view-frame continuity test needs an active rectangular sector")
	var initial_view_frame: Vector2 = runtime.active_sector_session.frame_global_origin
	var target_sector_coord: Vector2i = initial_sector_state.sector_coord + Vector2i(1, 0)
	var crossed_focus: Vector2 = initial_sector_state.global_origin + Vector2(
		initial_sector_state.size * 1.5,
		initial_sector_state.size * 0.5
	)
	var local_focus_before_switch: Vector2 = runtime.active_sector_session.to_local(crossed_focus)

	runtime.update_focus_context(crossed_focus, 0.0)
	runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.get_active_sector_state().sector_coord,
		target_sector_coord,
		"crossing the sector boundary should still switch the semantic active tile"
	)
	assert_true(
		runtime.active_sector_session.frame_global_origin.is_equal_approx(initial_view_frame),
		"the visible view frame should stay stable across the sector switch to avoid a camera-frame jump"
	)
	assert_true(
		runtime.active_sector_session.to_local(crossed_focus).is_equal_approx(local_focus_before_switch),
		"the same global focus position should keep the same local projection after the sector switch"
	)

func test_macro_sector_zone_rules_keep_ambient_planets_live_and_far_planets_frozen() -> void:
	var galaxy_state: GalaxyState = _make_manual_runtime_snapshot_galaxy(5, 2_000.0, true)
	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_galaxy_state(galaxy_state, 0)
	var ambient_cluster_id: int = _find_first_cluster_in_macro_sector_zone(
		runtime,
		MACRO_SECTOR_ZONE_SCRIPT.Zone.AMBIENT
	)
	var far_cluster_id: int = _find_first_cluster_in_macro_sector_zone(
		runtime,
		MACRO_SECTOR_ZONE_SCRIPT.Zone.FAR
	)
	var ambient_cluster: ClusterState = galaxy_state.get_cluster(ambient_cluster_id)
	var far_cluster: ClusterState = galaxy_state.get_cluster(far_cluster_id)
	var ambient_planet_id: String = "cluster_%d:star_0:planet_0" % ambient_cluster_id
	var far_planet_id: String = "cluster_%d:star_0:planet_0" % far_cluster_id
	var far_star_id: String = "cluster_%d:star_0" % far_cluster_id
	var ambient_planet_before: Vector2 = ambient_cluster.get_object(ambient_planet_id).local_position
	var far_planet_before: Vector2 = far_cluster.get_object(far_planet_id).local_position
	var far_star_before: Vector2 = far_cluster.get_object(far_star_id).local_position

	for _i in range(4):
		runtime.step(SimConstants.FIXED_DT)

	var ambient_planet_after: Vector2 = ambient_cluster.get_object(ambient_planet_id).local_position
	var far_planet_after: Vector2 = far_cluster.get_object(far_planet_id).local_position
	var far_star_after: Vector2 = far_cluster.get_object(far_star_id).local_position

	assert_false(
		ambient_planet_after.is_equal_approx(ambient_planet_before),
		"ambient neighbors should keep registered planets moving under simplified stepping"
	)
	assert_true(
		far_planet_after.is_equal_approx(far_planet_before),
		"far-zone planets should remain frozen on their last snapshot instead of continuing to step"
	)
	assert_false(
		far_star_after.is_equal_approx(far_star_before),
		"far-zone stars should still advance as macro-structure carriers during the batched far step"
	)
	assert_eq(
		ambient_cluster.get_objects_by_kind("fragment").size(),
		0,
		"ambient simplified stepping should not generate fragments or collision byproducts"
	)
	assert_eq(
		far_cluster.get_objects_by_kind("fragment").size(),
		0,
		"far simplified stepping should also avoid any fragment generation"
	)

func test_focus_context_can_enter_empty_sector_without_creating_a_fallback_cluster() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 911
	config.cluster_density = 0.18
	config.void_strength = 0.86
	config.bh_richness = 0.22
	config.star_richness = 0.18
	config.rare_zone_frequency = 0.05

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var current_sector_coord: Vector2i = runtime.get_active_sector_state().sector_coord
	var empty_sector_coord: Vector2i = _find_empty_discovered_sector_coord(runtime.galaxy_state, current_sector_coord)

	assert_ne(
		empty_sector_coord,
		Vector2i(9_999_999, 9_999_999),
		"the empty-sector test needs at least one discovered sector without a primary system"
	)

	var sector_state = runtime.galaxy_state.get_sector_state(empty_sector_coord)
	var preserved_view_frame: Vector2 = runtime.active_sector_session.frame_global_origin
	runtime.update_focus_context(sector_state.center(), sector_state.size * 0.35)
	runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.get_active_sector_state().sector_coord,
		empty_sector_coord,
		"camera focus should be able to enter an empty rectangular sector directly"
	)
	assert_null(
		runtime.active_cluster_session,
		"entering an empty sector should not synthesize a fallback cluster bubble"
	)
	assert_not_null(runtime.get_active_sim_world(), "empty active sectors should still expose a valid top-level SimWorld shell")
	assert_eq(
		runtime.get_active_sim_world().bodies.size(),
		0,
		"empty active sectors should stay empty instead of inventing system content"
	)
	assert_true(
		runtime.active_sector_session.frame_global_origin.is_equal_approx(preserved_view_frame),
		"entering an empty sector should also preserve the visible view frame instead of snapping to the empty tile center"
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

func test_activating_a_never_visited_remote_cluster_materializes_planets_from_blueprint_content() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 1337
	config.cluster_density = 0.92
	config.void_strength = 0.16
	config.bh_richness = 0.55
	config.star_richness = 0.80
	config.rare_zone_frequency = 1.0
	config.planets_per_star = 4

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var active_cluster_id: int = runtime.active_cluster_session.cluster_id
	var target_cluster: ClusterState = null
	for cluster_state in runtime.galaxy_state.get_clusters():
		if cluster_state.cluster_id == active_cluster_id:
			continue
		if int(cluster_state.simulation_profile.get("star_count", 0)) <= 0:
			continue
		if int(cluster_state.simulation_profile.get("planets_per_star", 0)) <= 0:
			continue
		if cluster_state.last_activated_runtime_time >= 0.0:
			continue
		target_cluster = cluster_state
		break

	assert_not_null(target_cluster, "the activation regression needs a remote star-bearing cluster with planets")

	runtime.activate_cluster(target_cluster.cluster_id)

	var active_planets: Array = []
	for body in runtime.get_active_sim_world().bodies:
		if body.body_type == SimBody.BodyType.PLANET and body.active:
			active_planets.append(body)

	assert_gt(
		active_planets.size(),
		0,
		"activating a never-visited remote cluster should materialize its planet content instead of loading a BH-only snapshot"
	)

func test_active_cluster_stays_loaded_across_same_sector_camera_motion() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 144
	config.cluster_density = 1.0
	config.void_strength = 0.0
	config.bh_richness = 0.82
	config.star_richness = 0.52
	config.rare_zone_frequency = 0.55

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var initial_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state
	var sector_state = runtime.get_active_sector_state()
	var steps_to_cover_unload_delay: int = int(ceil(
		SimConstants.CLUSTER_SIMPLIFIED_UNLOAD_DELAY / SimConstants.FIXED_DT
	)) + 2

	for step_index in range(steps_to_cover_unload_delay):
		var blend: float = float(step_index) / maxf(float(steps_to_cover_unload_delay - 1), 1.0)
		var focus_position: Vector2 = sector_state.global_origin + Vector2(
			lerpf(sector_state.size * 0.20, sector_state.size * 0.80, blend),
			sector_state.size * 0.55
		)
		runtime.update_focus_context(focus_position, sector_state.size * 0.40)
		runtime.step(SimConstants.FIXED_DT)

	assert_eq(
		runtime.active_cluster_session.cluster_id,
		initial_cluster.cluster_id,
		"camera motion inside one active sector should not eject the contained system out of the loaded session"
	)
	assert_eq(
		initial_cluster.activation_state,
		ClusterActivationState.State.ACTIVE,
		"the contained system should stay ACTIVE for the full active-sector session"
	)

func test_activate_sector_can_enter_empty_space_without_fallback_cluster() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 911
	config.cluster_density = 0.18
	config.void_strength = 0.86
	config.bh_richness = 0.22
	config.star_richness = 0.18
	config.rare_zone_frequency = 0.05

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var current_sector_coord: Vector2i = runtime.get_active_sector_state().sector_coord
	var empty_sector_coord: Vector2i = _find_empty_discovered_sector_coord(runtime.galaxy_state, current_sector_coord)

	assert_ne(
		empty_sector_coord,
		Vector2i(9_999_999, 9_999_999),
		"the empty-sector activation test needs a discovered sector without a primary system"
	)

	runtime.activate_sector(empty_sector_coord)

	assert_eq(
		runtime.get_active_sector_state().sector_coord,
		empty_sector_coord,
		"manual sector activation should allow entering a large empty tile directly"
	)
	assert_null(
		runtime.active_cluster_session,
		"manual sector activation should keep empty sectors truly empty instead of creating a fallback system"
	)
	assert_eq(runtime.get_active_sim_world().bodies.size(), 0, "empty active sectors should not materialize any bodies")

func test_simplified_cluster_unloads_after_idle_delay() -> void:
	var galaxy_state: GalaxyState = _make_manual_runtime_snapshot_galaxy(7)
	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_galaxy_state(galaxy_state, 0)
	var first_cluster_id: int = runtime.active_cluster_session.cluster_id
	var first_cluster: ClusterState = runtime.galaxy_state.get_cluster(first_cluster_id)
	var first_star: SimBody = runtime.get_active_sim_world().get_star()
	var persisted_star_id: String = first_star.persistent_object_id
	var second_cluster_id: int = _find_cluster_outside_active_macro_sector(runtime)
	assert_true(second_cluster_id >= 0, "the unload test needs a switch target outside the current macro sector")

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
	var galaxy_state: GalaxyState = _make_manual_runtime_snapshot_galaxy(7)
	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_galaxy_state(galaxy_state, 0)
	var first_cluster_id: int = runtime.active_cluster_session.cluster_id
	var second_cluster_id: int = _find_cluster_outside_active_macro_sector(runtime)
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
	config.cluster_density = 0.90
	config.void_strength = 0.12
	config.bh_richness = 0.68
	config.star_richness = 0.42
	config.disturbance_body_count = 1

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var active_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state
	var asteroid: SimBody = _find_active_body_of_type(runtime.get_active_sim_world(), SimBody.BodyType.ASTEROID)
	assert_not_null(asteroid, "the export test needs one free dynamic asteroid in the active cluster")

	var export_radius: float = OBJECT_RESIDENCY_POLICY_SCRIPT.transit_export_radius(active_cluster)
	var outbound_dir: Vector2 = Vector2.RIGHT
	asteroid.position = outbound_dir * (export_radius + SimConstants.AU)
	asteroid.velocity = Vector2(0.0, 0.0)
	var expected_global_position: Vector2 = runtime.active_cluster_session.to_global(asteroid.position)
	var discovered_sectors_before: int = runtime.get_discovered_sector_count()
	var exported_object_id: String = asteroid.persistent_object_id

	runtime.step(SimConstants.FIXED_DT)

	var transit_state = runtime.galaxy_state.get_transit_object(exported_object_id)
	var expected_target_cluster_id: int = _find_best_non_source_claim_cluster_id(
		runtime.galaxy_state,
		expected_global_position,
		active_cluster.cluster_id
	)
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
		expected_target_cluster_id,
		"exported objects should claim the current best non-source cluster after worldgen-aware discovery"
	)
	assert_eq(
		transit_state.arrival_phase,
		TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.EN_ROUTE,
		"objects outside the target cluster radius should remain en route until they actually enter the target cluster"
	)
	assert_true(
		runtime.get_discovered_sector_count() >= discovered_sectors_before,
		"transit export should be allowed to discover additional sectors without depending on camera focus"
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

func test_grouped_transit_objects_share_one_group_target_and_anchor_routing() -> void:
	var galaxy_state := GalaxyState.new()
	galaxy_state.add_cluster(_make_manual_cluster(0, Vector2.ZERO, 100.0))
	galaxy_state.add_cluster(_make_manual_cluster(1, Vector2(1000.0, 0.0), 100.0))
	galaxy_state.add_cluster(_make_manual_cluster(2, Vector2(1400.0, 0.0), 100.0))

	var left_member = _make_test_transit_asteroid(
		"transit:group_left",
		0,
		Vector2(1080.0, 0.0),
		Vector2.ZERO,
		"convoy:test",
		"convoy",
		true,
		true
	)
	var right_member = _make_test_transit_asteroid(
		"transit:group_right",
		0,
		Vector2(1420.0, 0.0),
		Vector2.ZERO,
		"convoy:test",
		"convoy"
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
	assert_eq(transit_group.primary_object_id, left_member.object_id, "the explicit group primary should persist into the transit group state")
	assert_eq(transit_group.anchor_object_id, left_member.object_id, "the explicit group anchor should persist into the transit group state")
	assert_eq(transit_group.group_kind, "convoy", "the grouped transfer should preserve its declared group kind")
	assert_true(
		transit_group.global_position.is_equal_approx(left_member.global_position),
		"group routing should use the declared anchor member instead of falling back to the centroid"
	)
	assert_eq(
		transit_group.target_cluster_id,
		1,
		"the grouped convoy should choose one shared target from its anchor/primary member instead of splitting per member"
	)
	assert_eq(left_member.target_cluster_id, 1, "every group member should inherit the shared group target")
	assert_eq(right_member.target_cluster_id, 1, "every group member should inherit the shared group target")
	assert_eq(
		left_member.arrival_phase,
		TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.ARRIVING,
		"grouped routing should mark every member as arriving once the shared group anchor reaches the target cluster"
	)

func test_arriving_transit_object_settles_into_unloaded_target_cluster_as_resident() -> void:
	var galaxy_state: GalaxyState = _make_manual_runtime_snapshot_galaxy(7)
	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_galaxy_state(galaxy_state, 0)
	var source_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state
	var target_cluster_id: int = _find_cluster_outside_active_macro_sector(runtime)
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

func test_worldgen_cluster_radius_stays_authoritative_through_writeback_and_arrival() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	config.cluster_density = 0.92
	config.void_strength = 0.10
	config.bh_richness = 0.74
	config.star_richness = 0.58
	config.rare_zone_frequency = 0.36
	config.disturbance_body_count = 1

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var active_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state
	var active_authoritative_radius: float = active_cluster.radius
	var target_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, active_cluster.cluster_id)
	var target_cluster: ClusterState = runtime.galaxy_state.get_cluster(target_cluster_id)
	var target_authoritative_radius: float = target_cluster.radius

	runtime.step(SimConstants.FIXED_DT)

	assert_almost_eq(
		active_cluster.radius,
		active_authoritative_radius,
		0.001,
		"active-cluster writeback should not replace the authoritative worldgen radius with a runtime extent estimate"
	)

	var import_radius: float = OBJECT_RESIDENCY_POLICY_SCRIPT.transit_import_radius(target_cluster)
	var transit_state = _make_test_transit_asteroid(
		"transit:authoritative_radius_arrival",
		active_cluster.cluster_id,
		target_cluster.global_center + Vector2(import_radius * 0.5, 0.0),
		Vector2.ZERO
	)
	runtime.galaxy_state.register_transit_object(transit_state)

	runtime.step(SimConstants.FIXED_DT)

	assert_almost_eq(
		target_cluster.radius,
		target_authoritative_radius,
		0.001,
		"resident arrivals should not silently expand the authoritative cluster radius beyond the worldgen-owned extent"
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
		"convoy:active_import",
		"convoy",
		true,
		true
	)
	var second_transit = _make_test_transit_asteroid(
		"transit:group_import_b",
		-1,
		active_cluster.global_center + Vector2(import_radius * 1.05, 0.0),
		Vector2.ZERO,
		"convoy:active_import",
		"convoy"
	)
	runtime.galaxy_state.register_transit_object(first_transit)
	runtime.galaxy_state.register_transit_object(second_transit)

	runtime.step(SimConstants.FIXED_DT)

	var first_body: SimBody = runtime.get_active_sim_world().get_body_by_persistent_object_id(first_transit.object_id)
	var second_body: SimBody = runtime.get_active_sim_world().get_body_by_persistent_object_id(second_transit.object_id)
	var first_object: ClusterObjectState = active_cluster.get_object(first_transit.object_id)
	var second_object: ClusterObjectState = active_cluster.get_object(second_transit.object_id)
	var imported_group = active_cluster.get_group("convoy:active_import")
	assert_not_null(first_body, "group arrival should import the first member into the active cluster")
	assert_not_null(second_body, "group arrival should import the second member with the same shared handoff")
	assert_not_null(first_object, "group arrival should persist the first imported member in the active cluster")
	assert_not_null(second_object, "group arrival should persist the second imported member in the active cluster")
	assert_not_null(imported_group, "group arrival should create a persistent cluster group record for the imported convoy")
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
	assert_eq(imported_group.primary_object_id, first_transit.object_id, "the imported cluster group should preserve the explicit primary object id")
	assert_eq(imported_group.anchor_object_id, first_transit.object_id, "the imported cluster group should preserve the explicit anchor object id")
	assert_eq(imported_group.group_kind, "convoy", "the imported cluster group should preserve its declared group kind")

func test_group_identity_survives_cluster_switch_and_reload() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	config.black_hole_count = 6
	config.galaxy_cluster_count = 2
	config.star_count = 1
	config.planets_per_star = 0
	config.disturbance_body_count = 0

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var source_cluster_id: int = runtime.active_cluster_session.cluster_id
	var source_cluster: ClusterState = runtime.galaxy_state.get_cluster(source_cluster_id)
	var other_cluster_id: int = _find_secondary_cluster_id(runtime.galaxy_state, source_cluster_id)
	var import_radius: float = OBJECT_RESIDENCY_POLICY_SCRIPT.transit_import_radius(source_cluster)
	var first_transit = _make_test_transit_asteroid(
		"transit:group_persist_a",
		-1,
		source_cluster.global_center + Vector2(import_radius * 0.35, 0.0),
		Vector2.ZERO,
		"convoy:persist",
		"convoy",
		true,
		true
	)
	var second_transit = _make_test_transit_asteroid(
		"transit:group_persist_b",
		-1,
		source_cluster.global_center + Vector2(import_radius * 0.90, 0.0),
		Vector2.ZERO,
		"convoy:persist",
		"convoy"
	)
	runtime.galaxy_state.register_transit_object(first_transit)
	runtime.galaxy_state.register_transit_object(second_transit)

	runtime.step(SimConstants.FIXED_DT)

	var imported_group = source_cluster.get_group("convoy:persist")
	assert_not_null(imported_group, "the persistence test needs the grouped convoy to exist in the source cluster before switching")

	runtime.activate_cluster(other_cluster_id)

	var persisted_group = source_cluster.get_group("convoy:persist")
	assert_not_null(persisted_group, "switching away should keep the grouped ownership record in the previous cluster")
	assert_eq(persisted_group.primary_object_id, first_transit.object_id, "the simplified cluster should preserve the group's primary id")
	assert_eq(persisted_group.anchor_object_id, first_transit.object_id, "the simplified cluster should preserve the group's anchor id")
	assert_eq(persisted_group.group_kind, "convoy", "the simplified cluster should preserve the group's kind")
	assert_eq(
		persisted_group.residency_state,
		ObjectResidencyState.State.SIMPLIFIED,
		"switching away should demote the persisted group residency alongside its member objects"
	)

	runtime.activate_cluster(source_cluster_id)

	var reloaded_group = runtime.active_cluster_session.active_cluster_state.get_group("convoy:persist")
	var reloaded_primary: SimBody = runtime.get_active_sim_world().get_body_by_persistent_object_id(first_transit.object_id)
	var reloaded_secondary: SimBody = runtime.get_active_sim_world().get_body_by_persistent_object_id(second_transit.object_id)
	assert_not_null(reloaded_group, "reactivating the cluster should restore the persistent group identity from source-of-truth")
	assert_not_null(reloaded_primary, "reactivating the cluster should restore the primary group member")
	assert_not_null(reloaded_secondary, "reactivating the cluster should restore the follower group member")
	assert_eq(reloaded_group.primary_object_id, first_transit.object_id, "reload should keep the same group primary")
	assert_eq(reloaded_group.anchor_object_id, first_transit.object_id, "reload should keep the same group anchor")
	assert_eq(reloaded_group.group_kind, "convoy", "reload should keep the same group kind")
	assert_eq(
		reloaded_group.member_object_ids.size(),
		2,
		"reload should preserve the full grouped membership set"
	)

func test_world_entity_bound_to_group_tracks_cluster_residency_and_anchor_identity() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.CENTRAL_BH
	config.star_count = 1
	config.planets_per_star = 0
	config.disturbance_body_count = 0

	var runtime: GalaxyRuntime = WorldBuilder.build_runtime_from_config(config)
	var active_cluster: ClusterState = runtime.active_cluster_session.active_cluster_state
	var import_radius: float = OBJECT_RESIDENCY_POLICY_SCRIPT.transit_import_radius(active_cluster)
	var primary_transit = _make_test_transit_asteroid(
		"transit:entity_group_primary",
		-1,
		active_cluster.global_center + Vector2(import_radius * 0.40, 0.0),
		Vector2.ZERO,
		"convoy:entity_group",
		"convoy",
		true,
		true
	)
	var follower_transit = _make_test_transit_asteroid(
		"transit:entity_group_follower",
		-1,
		active_cluster.global_center + Vector2(import_radius * 0.85, 0.0),
		Vector2.ZERO,
		"convoy:entity_group",
		"convoy"
	)
	runtime.galaxy_state.register_transit_object(primary_transit)
	runtime.galaxy_state.register_transit_object(follower_transit)
	var entity_state = _make_test_world_entity(
		"entity:crew_member",
		"agent",
		"convoy:entity_group",
		WORLD_ENTITY_STATE_SCRIPT.ATTACHMENT_GROUP_PRIMARY
	)
	runtime.galaxy_state.register_world_entity(entity_state)

	runtime.step(SimConstants.FIXED_DT)

	var active_group = active_cluster.get_group("convoy:entity_group")
	assert_eq(runtime.get_world_entity_count(), 1, "runtime should expose the registered world entity count")
	assert_eq(runtime.get_active_world_entities().size(), 1, "group-bound entities should become active with their active owner cluster")
	assert_not_null(active_group, "group-bound entities should sit on a persistent cluster group after the grouped arrival")
	assert_eq(active_group.primary_object_id, primary_transit.object_id, "the owning cluster group should preserve the explicit primary object id")
	assert_eq(entity_state.current_cluster_id, active_cluster.cluster_id, "group-bound entities should resolve into the owning active cluster")
	assert_eq(entity_state.current_group_id, "convoy:entity_group", "group-bound entities should keep their stable group id while resident")
	assert_eq(entity_state.current_transit_group_id, "", "resident group-bound entities should not report a transit-group binding")
	assert_eq(entity_state.resolved_anchor_object_id, primary_transit.object_id, "GROUP_PRIMARY entities should resolve to the group's primary object")
	assert_eq(entity_state.residency_state, ObjectResidencyState.State.ACTIVE, "resident entities in the active cluster should be ACTIVE")

func test_world_entity_can_bind_to_transit_group_before_arrival() -> void:
	var galaxy_state := GalaxyState.new()
	galaxy_state.add_cluster(_make_manual_cluster(0, Vector2.ZERO, 100.0))
	galaxy_state.add_cluster(_make_manual_cluster(1, Vector2(1000.0, 0.0), 100.0))
	var first_member = _make_test_transit_asteroid(
		"transit:entity_transit_anchor",
		0,
		Vector2(450.0, 0.0),
		Vector2.ZERO,
		"convoy:transit_only",
		"convoy",
		true,
		true
	)
	var second_member = _make_test_transit_asteroid(
		"transit:entity_transit_follower",
		0,
		Vector2(520.0, 0.0),
		Vector2.ZERO,
		"convoy:transit_only",
		"convoy"
	)
	galaxy_state.register_transit_object(first_member)
	galaxy_state.register_transit_object(second_member)
	var entity_state = _make_test_world_entity(
		"entity:traveler",
		"agent",
		"convoy:transit_only",
		WORLD_ENTITY_STATE_SCRIPT.ATTACHMENT_GROUP_ANCHOR
	)
	galaxy_state.register_world_entity(entity_state)
	WorldBuilder.step_transit_objects(galaxy_state, SimConstants.FIXED_DT)
	galaxy_state.sync_world_entity_bindings()

	assert_eq(entity_state.residency_state, ObjectResidencyState.State.IN_TRANSIT, "entities bound to a transit group should resolve as in transit before arrival")
	assert_eq(entity_state.current_transit_group_id, "convoy:transit_only", "transit-bound entities should keep the shared transit group id")
	assert_eq(entity_state.current_group_id, "convoy:transit_only", "transit-bound entities should keep the stable group id while traveling")
	assert_eq(entity_state.current_cluster_id, 1, "transit-bound entities should expose the current target cluster chosen by the transit group")
	assert_eq(entity_state.resolved_anchor_object_id, first_member.object_id, "GROUP_ANCHOR entities should resolve to the transit group's anchor object")

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
	cluster_state.simulation_profile["sector_coord"] = _manual_sector_coord_for_cluster_id(cluster_id)
	return cluster_state

func _make_manual_runtime_snapshot_galaxy(
		cluster_count: int,
		spacing: float = 2_000.0,
		include_planet: bool = false) -> GalaxyState:
	var galaxy_state := GalaxyState.new()
	for cluster_id in range(cluster_count):
		galaxy_state.add_cluster(_make_manual_runtime_snapshot_cluster(
			cluster_id,
			Vector2(float(cluster_id) * spacing, 0.0),
			include_planet
		))
	return galaxy_state

func _make_manual_runtime_snapshot_cluster(
		cluster_id: int,
		global_center: Vector2,
		include_planet: bool = false) -> ClusterState:
	var cluster_state: ClusterState = _make_manual_cluster(cluster_id, global_center, 100.0)
	var black_hole_object_id: String = "cluster_%d:black_hole_0" % cluster_id
	var star_object_id: String = "cluster_%d:star_0" % cluster_id
	cluster_state.cluster_blueprint["primary_black_hole_object_id"] = black_hole_object_id
	cluster_state.simulation_profile["has_runtime_snapshot"] = true
	cluster_state.register_object(_make_manual_cluster_object_state(
		black_hole_object_id,
		"black_hole",
		Vector2.ZERO,
		Vector2.ZERO,
		{
			"body_type": SimBody.BodyType.BLACK_HOLE,
			"material_type": SimBody.MaterialType.STELLAR,
			"influence_level": SimBody.InfluenceLevel.A,
			"mass": SimConstants.BLACK_HOLE_MASS,
			"radius": SimConstants.BLACK_HOLE_RADIUS,
			"temperature": 0.0,
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
		}
	))
	cluster_state.register_object(_make_manual_cluster_object_state(
		star_object_id,
		"star",
		Vector2(400.0, 0.0),
		Vector2.ZERO,
		{
			"body_type": SimBody.BodyType.STAR,
			"material_type": SimBody.MaterialType.STELLAR,
			"influence_level": SimBody.InfluenceLevel.A,
			"mass": SimConstants.STAR_MASS,
			"radius": SimConstants.STAR_RADIUS,
			"temperature": 5000.0,
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
		}
	))
	if include_planet:
		cluster_state.register_object(_make_manual_cluster_object_state(
			"%s:planet_0" % star_object_id,
			"planet",
			Vector2(460.0, 0.0),
			Vector2.ZERO,
			{
				"body_type": SimBody.BodyType.PLANET,
				"material_type": SimBody.MaterialType.ROCKY,
				"influence_level": SimBody.InfluenceLevel.B,
				"mass": SimConstants.PLANET_MASS_MIN,
				"radius": SimConstants.PLANET_RADIUS_MIN,
				"temperature": 260.0,
				"kinematic": false,
				"scripted_orbit_enabled": true,
				"orbit_binding_state": SimBody.OrbitBindingState.BOUND_ANALYTIC,
				"orbit_radius": 60.0,
				"orbit_angle": 0.0,
				"orbit_angular_speed": 0.5,
				"debris_mass": 0.0,
				"sleeping": false,
				"active": true,
				"parent_object_id": star_object_id,
			}
		))
	return cluster_state

func _make_manual_cluster_object_state(
		object_id: String,
		kind: String,
		local_position: Vector2,
		local_velocity: Vector2,
		descriptor: Dictionary) -> ClusterObjectState:
	var object_state := ClusterObjectState.new()
	object_state.object_id = object_id
	object_state.kind = kind
	object_state.residency_state = ObjectResidencyState.State.SIMPLIFIED
	object_state.local_position = local_position
	object_state.local_velocity = local_velocity
	object_state.descriptor = descriptor.duplicate(true)
	return object_state

func _find_secondary_cluster_id(galaxy_state: GalaxyState, active_cluster_id: int) -> int:
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id != active_cluster_id:
			return cluster_state.cluster_id
	return -1

func _find_empty_discovered_sector_coord(
		galaxy_state: GalaxyState,
		excluded_sector_coord: Vector2i = Vector2i(9_999_998, 9_999_998)) -> Vector2i:
	if galaxy_state == null:
		return Vector2i(9_999_999, 9_999_999)
	for sector_coord in galaxy_state.get_discovered_sector_coords():
		if sector_coord == excluded_sector_coord:
			continue
		if galaxy_state.get_cluster_ids_for_sector(sector_coord).is_empty():
			return sector_coord
	return Vector2i(9_999_999, 9_999_999)

func _manual_sector_coord_for_cluster_id(cluster_id: int) -> Vector2i:
	var layout := [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(2, 0),
		Vector2i(0, 2),
		Vector2i(3, 0),
		Vector2i(0, 3),
	]
	if cluster_id >= 0 and cluster_id < layout.size():
		return layout[cluster_id]
	return Vector2i(cluster_id, 0)

func _find_cluster_outside_active_macro_sector(runtime: GalaxyRuntime) -> int:
	if runtime == null or runtime.galaxy_state == null:
		return -1
	for cluster_state in runtime.galaxy_state.get_clusters():
		if cluster_state == null:
			continue
		if cluster_state.cluster_id == runtime.active_cluster_session.cluster_id:
			continue
		if not runtime.is_cluster_in_active_macro_sector(cluster_state.cluster_id):
			return cluster_state.cluster_id
	return -1

func _find_first_cluster_in_macro_sector_zone(runtime: GalaxyRuntime, zone: int) -> int:
	if runtime == null or runtime.galaxy_state == null:
		return -1
	for cluster_state in runtime.galaxy_state.get_clusters():
		if cluster_state == null:
			continue
		if runtime.get_cluster_macro_sector_zone(cluster_state.cluster_id) == zone:
			return cluster_state.cluster_id
	return -1

func _find_best_non_source_claim_cluster_id(
		galaxy_state: GalaxyState,
		global_position: Vector2,
		source_cluster_id: int) -> int:
	var matched_cluster_id: int = -1
	var best_score: float = INF
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id == source_cluster_id:
			continue
		var claim_score: float = OBJECT_RESIDENCY_POLICY_SCRIPT.cluster_claim_score_for_position(
			global_position,
			cluster_state
		)
		if claim_score < best_score:
			best_score = claim_score
			matched_cluster_id = cluster_state.cluster_id
	return matched_cluster_id

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
		transfer_group_id: String = "",
		group_kind: String = "",
		group_primary: bool = false,
		group_anchor: bool = false):
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
		"group_kind": group_kind,
		"group_primary": group_primary,
		"group_anchor": group_anchor,
		"group_primary_requested": group_primary,
		"group_anchor_requested": group_anchor,
	}
	return transit_state

func _make_test_world_entity(
		entity_id: String,
		entity_kind: String,
		bound_group_id: String,
		attachment_mode: int,
		preferred_object_id: String = ""):
	var entity_state = WORLD_ENTITY_STATE_SCRIPT.new()
	entity_state.entity_id = entity_id
	entity_state.entity_kind = entity_kind
	entity_state.bound_group_id = bound_group_id
	entity_state.attachment_mode = attachment_mode
	entity_state.preferred_object_id = preferred_object_id
	entity_state.descriptor = {
		"label": entity_id,
		"entity_kind": entity_kind,
	}
	return entity_state
