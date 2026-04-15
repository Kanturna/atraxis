extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const GALAXY_BUILDER_SCRIPT := preload("res://simulation/galaxy_builder.gd")
const GALAXY_WORLDGEN_SCRIPT := preload("res://simulation/galaxy_worldgen.gd")
const DEBUG_METRICS_SCRIPT := preload("res://debug/debug_metrics.gd")

func test_internal_reference_fixture_creates_analytic_reference_layout() -> void:
	var world := _build_fixture_world(func(config):
		config.world_profile = START_CONFIG_SCRIPT.WorldProfile.ORBITAL_REFERENCE
		config.star_count = 2
		config.planets_per_star = 2
		config.disturbance_body_count = 3
	)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE), 1, "internal reference fixture should create one black hole")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 2, "internal reference fixture should create the configured stars")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 4, "internal reference fixture should create planets for each star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.ASTEROID), 3, "internal reference fixture should create the configured disturbance bodies")

	for body in world.bodies:
		if body.body_type == SimBody.BodyType.STAR:
			assert_true(body.kinematic, "internal reference fixture stars should remain analytic carriers")
			assert_true(body.scripted_orbit_enabled, "internal reference fixture stars should use analytic orbiting")
		elif body.body_type == SimBody.BodyType.PLANET:
			assert_true(body.kinematic, "internal reference fixture core planets remain kinematic")
			assert_true(body.scripted_orbit_enabled, "internal reference fixture core planets should use analytic orbiting")
			assert_eq(body.orbit_binding_state, SimBody.OrbitBindingState.BOUND_ANALYTIC, "core planets should advertise their bound state")
			assert_gt(body.orbit_radius, 0.0, "planet should have a configured orbit radius")
			assert_gt(body.orbit_angular_speed, 0.0, "planet should have a configured orbit speed")

func test_bound_core_planet_advances_with_moving_parent_in_internal_reference_fixture() -> void:
	var world := _build_fixture_world(func(config):
		config.world_profile = START_CONFIG_SCRIPT.WorldProfile.ORBITAL_REFERENCE
	)
	var star: SimBody = world.get_star()
	var planet: SimBody = null
	for body in world.bodies:
		if body.body_type == SimBody.BodyType.PLANET:
			planet = body
			break

	assert_not_null(planet, "fixture world should create at least one core planet")

	var old_planet_position: Vector2 = planet.position
	var old_star_position: Vector2 = star.position
	var orbit_radius: float = planet.orbit_radius
	world.step_sim(SimConstants.FIXED_DT)

	assert_false(star.position.is_equal_approx(old_star_position), "moving sun should advance each tick")
	assert_false(planet.position.is_equal_approx(old_planet_position), "bound core planets should visibly advance each tick")
	assert_almost_eq(
		planet.position.distance_to(star.position),
		orbit_radius,
		0.01,
		"bound core planets should stay on their configured parent-relative orbit radius"
	)

func test_live_black_hole_mass_updates_analytic_star_carrier_speed_in_internal_reference_fixture() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.world_profile = START_CONFIG_SCRIPT.WorldProfile.ORBITAL_REFERENCE
	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_galaxy_state(
		GALAXY_BUILDER_SCRIPT.build_fixture_from_config(config)
	)
	var world: SimWorld = session.sim_world
	var star: SimBody = world.get_star()
	var old_speed: float = star.orbit_angular_speed

	world.set_black_hole_mass(config.black_hole_mass * 1.5)

	assert_gt(star.orbit_angular_speed, old_speed, "raising BH mass should immediately strengthen analytic star carrier speed")

func test_worldgen_materialization_matches_the_active_cluster_black_hole_registry() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 27
	config.cluster_density = 0.88
	config.void_strength = 0.10
	config.bh_richness = 0.74
	config.star_richness = 0.46
	config.rare_zone_frequency = 0.35

	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_config(config)
	var world: SimWorld = session.sim_world
	var active_cluster: ClusterState = session.active_cluster_state
	var black_hole_states: Array = active_cluster.get_objects_by_kind("black_hole")

	assert_eq(
		world.get_black_holes().size(),
		black_hole_states.size(),
		"the active local projection should materialize exactly the registered active-cluster BH count"
	)
	for object_state in black_hole_states:
		var body: SimBody = world.get_body_by_persistent_object_id(object_state.object_id)
		assert_not_null(body, "every registered active-cluster BH should materialize into the local SimWorld")
		assert_true(
			body.position.is_equal_approx(object_state.local_position),
			"materialized black holes should keep the cluster registry's local positions"
		)
		assert_almost_eq(
			body.mass,
			float(object_state.descriptor.get("mass", 0.0)),
			0.001,
			"materialized black holes should keep the cluster registry's stored mass"
		)

func test_runtime_star_descriptor_round_trips_pending_and_confirmed_host_state() -> void:
	var cluster_state := ClusterState.new()
	cluster_state.cluster_seed = 42

	var star := WorldBuilder._make_star()
	star.kinematic = false
	star.scripted_orbit_enabled = false
	star.orbit_binding_state = SimBody.OrbitBindingState.FREE_DYNAMIC
	star.last_dominant_bh_id = 11
	star.dominant_bh_handoff_count = 3
	star.pending_host_bh_id = 23
	star.pending_host_time = 0.5
	star.confirmed_host_handoff_count = 2
	star.position = Vector2(12.0, 34.0)
	star.velocity = Vector2(5.0, -7.0)

	var object_state: ClusterObjectState = WorldBuilder._build_object_state_from_body(
		cluster_state,
		star,
		"cluster_0:star_0",
		ObjectResidencyState.State.ACTIVE
	)
	var restored: SimBody = WorldBuilder._make_body_from_object_state(object_state)

	assert_eq(restored.last_dominant_bh_id, 11, "runtime star descriptors should persist the last dominant BH id")
	assert_eq(restored.dominant_bh_handoff_count, 3, "runtime star descriptors should persist the raw dominant handoff counter")
	assert_eq(restored.pending_host_bh_id, 23, "runtime star descriptors should persist pending host candidates")
	assert_almost_eq(restored.pending_host_time, 0.5, 0.001, "runtime star descriptors should persist pending host timers")
	assert_eq(restored.confirmed_host_handoff_count, 2, "runtime star descriptors should persist confirmed host handoff counters")

func test_registered_cluster_materialization_relinks_parent_ids_from_object_registry() -> void:
	var cluster_state := ClusterState.new()
	cluster_state.cluster_seed = 9
	cluster_state.simulation_profile["spawn_anchor_content"] = false
	cluster_state.cluster_blueprint["primary_black_hole_object_id"] = "cluster_0:black_hole_0"

	cluster_state.register_object(_make_manual_cluster_object_state_for_world_builder_test(
		"cluster_0:black_hole_0",
		"black_hole",
		Vector2.ZERO,
		Vector2.ZERO,
		{
			"body_type": SimBody.BodyType.BLACK_HOLE,
			"material_type": SimBody.MaterialType.STELLAR,
			"influence_level": SimBody.InfluenceLevel.A,
			"mass": SimConstants.BLACK_HOLE_MASS,
			"radius": SimConstants.BLACK_HOLE_RADIUS,
			"is_primary": true,
		}
	))
	cluster_state.register_object(_make_manual_cluster_object_state_for_world_builder_test(
		"cluster_0:star_0",
		"star",
		Vector2(400.0, 0.0),
		Vector2.ZERO,
		{
			"body_type": SimBody.BodyType.STAR,
			"material_type": SimBody.MaterialType.STELLAR,
			"influence_level": SimBody.InfluenceLevel.A,
			"mass": SimConstants.STAR_MASS,
			"radius": SimConstants.STAR_RADIUS,
			"kinematic": false,
			"scripted_orbit_enabled": false,
			"orbit_binding_state": SimBody.OrbitBindingState.FREE_DYNAMIC,
			"parent_object_id": "cluster_0:black_hole_0",
		}
	))
	cluster_state.register_object(_make_manual_cluster_object_state_for_world_builder_test(
		"cluster_0:star_0:planet_0",
		"planet",
		Vector2(460.0, 0.0),
		Vector2.ZERO,
		{
			"body_type": SimBody.BodyType.PLANET,
			"material_type": SimBody.MaterialType.ROCKY,
			"influence_level": SimBody.InfluenceLevel.B,
			"mass": SimConstants.PLANET_MASS_MIN,
			"radius": SimConstants.PLANET_RADIUS_MIN,
			"kinematic": true,
			"scripted_orbit_enabled": true,
			"orbit_binding_state": SimBody.OrbitBindingState.BOUND_ANALYTIC,
			"orbit_radius": 60.0,
			"orbit_angle": 0.0,
			"orbit_angular_speed": 0.5,
			"parent_object_id": "cluster_0:star_0",
		}
	))

	var world := SimWorld.new()
	WorldBuilder.materialize_cluster_into_world(world, cluster_state)

	var black_hole: SimBody = world.get_body_by_persistent_object_id("cluster_0:black_hole_0")
	var star: SimBody = world.get_body_by_persistent_object_id("cluster_0:star_0")
	var planet: SimBody = world.get_body_by_persistent_object_id("cluster_0:star_0:planet_0")

	assert_not_null(black_hole, "registered black holes should materialize into the world")
	assert_not_null(star, "registered stars should materialize into the world")
	assert_not_null(planet, "registered planets should materialize into the world")
	assert_eq(star.orbit_parent_id, black_hole.id, "registered stars should relink their stored parent object id to the live black-hole body id")
	assert_eq(planet.orbit_parent_id, star.id, "registered planets should relink their stored parent object id to the live parent star body id")

func test_writeback_preserves_previous_parent_object_id_when_parent_is_temporarily_unresolved() -> void:
	var cluster_state := ClusterState.new()
	cluster_state.cluster_seed = 17
	cluster_state.register_object(_make_manual_cluster_object_state_for_world_builder_test(
		"cluster_0:planet_0",
		"planet",
		Vector2(60.0, 0.0),
		Vector2.ZERO,
		{
			"body_type": SimBody.BodyType.PLANET,
			"material_type": SimBody.MaterialType.ROCKY,
			"influence_level": SimBody.InfluenceLevel.B,
			"kinematic": true,
			"scripted_orbit_enabled": true,
			"orbit_binding_state": SimBody.OrbitBindingState.BOUND_ANALYTIC,
			"parent_object_id": "cluster_0:star_0",
		}
	))

	var planet := SimBody.new()
	planet.body_type = SimBody.BodyType.PLANET
	planet.material_type = SimBody.MaterialType.ROCKY
	planet.influence_level = SimBody.InfluenceLevel.B
	planet.mass = SimConstants.PLANET_MASS_MIN
	planet.radius = SimConstants.PLANET_RADIUS_MIN
	planet.kinematic = true
	planet.scripted_orbit_enabled = true
	planet.orbit_binding_state = SimBody.OrbitBindingState.BOUND_ANALYTIC
	planet.orbit_parent_id = 999
	planet.position = Vector2(60.0, 0.0)

	var object_state: ClusterObjectState = WorldBuilder._build_object_state_from_body(
		cluster_state,
		planet,
		"cluster_0:planet_0",
		ObjectResidencyState.State.ACTIVE,
		{}
	)

	assert_eq(
		str(object_state.descriptor.get("parent_object_id", "")),
		"cluster_0:star_0",
		"writeback should keep the last known persistent parent id when the live parent body is temporarily unresolved"
	)

func test_simplified_cluster_prunes_analytic_orbiters_whose_parent_is_missing() -> void:
	var cluster_state := ClusterState.new()
	cluster_state.radius = 100.0
	cluster_state.register_object(_make_manual_cluster_object_state_for_world_builder_test(
		"cluster_0:orphan_planet_0",
		"planet",
		Vector2(120.0, 0.0),
		Vector2(10.0, 0.0),
		{
			"body_type": SimBody.BodyType.PLANET,
			"material_type": SimBody.MaterialType.ROCKY,
			"influence_level": SimBody.InfluenceLevel.B,
			"kinematic": true,
			"scripted_orbit_enabled": true,
			"orbit_binding_state": SimBody.OrbitBindingState.BOUND_ANALYTIC,
			"orbit_radius": 40.0,
			"orbit_angle": 0.0,
			"orbit_angular_speed": 0.5,
			"parent_object_id": "cluster_0:missing_star",
		}
	))

	WorldBuilder.step_simplified_cluster(cluster_state, SimConstants.FIXED_DT)

	assert_false(
		cluster_state.has_object("cluster_0:orphan_planet_0"),
		"simplified stepping should remove analytic orbiters instead of leaving orphaned bodies behind when their parent is missing"
	)

func test_worldgen_active_cluster_keeps_sector_metadata_for_runtime_and_debug() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 61
	config.cluster_density = 0.82
	config.void_strength = 0.16
	config.bh_richness = 0.69
	config.star_richness = 0.58
	config.rare_zone_frequency = 0.44

	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_config(config)
	var profile: Dictionary = session.active_cluster_state.simulation_profile

	assert_true(profile.get("sector_coord", null) is Vector2i, "active worldgen clusters should keep their source sector coordinate")
	assert_true(int(profile.get("candidate_index", -1)) >= 0, "active worldgen clusters should keep their candidate index")
	assert_true(str(profile.get("region_archetype", "")) != "", "active worldgen clusters should keep their source archetype")
	assert_true(str(profile.get("content_archetype", "")) != "", "active worldgen clusters should keep their resolved content archetype")
	assert_true(profile.get("content_profile", null) is Dictionary, "active worldgen clusters should keep their resolved content profile")
	assert_true(profile.has("layout_min_bh_distance_au"), "active worldgen clusters should expose their local BH spacing diagnostics")
	assert_true(profile.has("layout_primary_clearance_au"), "active worldgen clusters should expose their primary-clearance diagnostics")
	assert_true(profile.has("layout_reserved_start_band_au"), "active worldgen clusters should expose their reserved start band for debug")
	assert_true(profile.has("layout_required_primary_clearance_au"), "active worldgen clusters should expose their required primary-clearance target")
	assert_true(profile.has("layout_primary_clearance_margin_au"), "active worldgen clusters should expose their primary-clearance margin")
	assert_true(profile.has("layout_cluster_radius_floor_au"), "active worldgen clusters should expose their cluster-radius floor")
	assert_true(profile.has("layout_cluster_radius_margin_au"), "active worldgen clusters should expose their cluster-radius margin")
	assert_true(profile.has("spawn_viable"), "active worldgen clusters should expose their hard spawn-viability result")
	assert_true(str(profile.get("spawn_viability_reason", "")) != "", "active worldgen clusters should expose a readable spawn-viability reason")
	assert_true(
		session.active_cluster_state.cluster_blueprint.get("content_markers", null) is Array,
		"active worldgen clusters should keep their passive content markers in the blueprint"
	)
	assert_true(
		session.active_cluster_state.cluster_blueprint.get("layout_diagnostics", null) is Dictionary,
		"active worldgen clusters should keep their layout diagnostics in the blueprint for debug rendering"
	)
	assert_true(
		session.active_cluster_state.cluster_blueprint.get("preview_object_specs", null) is Array,
		"active worldgen clusters should store deterministic remote-preview specs in the blueprint"
	)
	assert_eq(
		profile.get("topology_role", ""),
		"sector_worldgen_cluster",
		"active worldgen clusters should advertise the canonical topology role to runtime and diagnostics"
	)

func test_live_black_hole_mass_updates_every_active_cluster_black_hole() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 44
	config.cluster_density = 0.84
	config.void_strength = 0.10
	config.bh_richness = 0.72

	var world := SimWorld.new()
	WorldBuilder.build_from_config(world, config)
	world.set_black_hole_mass(config.black_hole_mass * 1.25)

	for black_hole in world.get_black_holes():
		assert_almost_eq(black_hole.mass, config.black_hole_mass * 1.25, 0.001, "live BH mass changes should affect all active-cluster anchors")

func test_dynamic_star_spawn_distributes_hosts_across_available_black_holes() -> void:
	var world := SimWorld.new()

	var primary_bh := WorldBuilder._make_black_hole(12_000_000.0)
	primary_bh.position = Vector2.ZERO
	world.add_body(primary_bh)

	var secondary_bh := WorldBuilder._make_black_hole(12_000_000.0)
	secondary_bh.position = Vector2(11.0 * SimConstants.AU, 0.0)
	world.add_body(secondary_bh)

	var tertiary_bh := WorldBuilder._make_black_hole(12_000_000.0)
	tertiary_bh.position = Vector2(0.0, 11.5 * SimConstants.AU)
	world.add_body(tertiary_bh)

	var spawned_black_holes: Array = [
		{"object_id": "cluster_0:black_hole_0", "is_primary": true, "body": primary_bh},
		{"object_id": "cluster_0:black_hole_1", "is_primary": false, "body": secondary_bh},
		{"object_id": "cluster_0:black_hole_2", "is_primary": false, "body": tertiary_bh},
	]
	var profile := {
		"star_count": 4,
		"star_inner_orbit_au": 4.0,
		"star_outer_orbit_au": 20.0,
		"star_mass_scale_min": 0.9,
		"star_mass_scale_max": 1.1,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 77

	var stars: Array = WorldBuilder._place_dynamic_stars(spawned_black_holes, profile, rng)
	var distinct_host_ids: Dictionary = {}

	assert_eq(stars.size(), 4, "test setup should materialize all requested dynamic stars")
	for star in stars:
		distinct_host_ids[star.orbit_parent_id] = true
		assert_true(
			star.orbit_parent_id in [primary_bh.id, secondary_bh.id, tertiary_bh.id],
			"each dynamic star should keep a valid host black hole id"
		)
		var host_black_hole: SimBody = world.get_body_by_id(star.orbit_parent_id)
		assert_not_null(host_black_hole, "the stored host id should resolve back to a live black hole")
		assert_gte(
			star.position.distance_to(host_black_hole.position),
			4.0 * SimConstants.AU - 0.001,
			"host-aware stars should start on the configured inner orbit radius or beyond"
		)

	assert_gt(distinct_host_ids.size(), 1, "dynamic stars should no longer all spawn around the primary black hole")

func test_dynamic_star_spawn_uses_distinct_safe_shells_for_multi_star_single_host_systems() -> void:
	var host_bh := WorldBuilder._make_black_hole(12_000_000.0)
	host_bh.position = Vector2.ZERO
	var spawned_black_holes: Array = [
		{"object_id": "cluster_0:black_hole_0", "is_primary": true, "body": host_bh},
	]
	var profile := {
		"star_count": 4,
		"planets_per_star": 3,
		"star_inner_orbit_au": 4.0,
		"star_outer_orbit_au": 20.0,
		"star_mass_scale_min": 1.0,
		"star_mass_scale_max": 1.0,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	var stars: Array = WorldBuilder._place_dynamic_stars(spawned_black_holes, profile, rng)
	var shell_spacing: float = 2.0 * WorldBuilder._max_core_planet_orbit_radius(3) * SimConstants.AU + 0.75 * SimConstants.AU
	var orbit_radii: Array = []
	var phases: Array = []

	assert_eq(stars.size(), 4, "the single-host shell test should keep all four requested stars")
	for star in stars:
		orbit_radii.append(star.position.distance_to(host_bh.position))
		phases.append(wrapf((star.position - host_bh.position).angle(), 0.0, TAU))

	orbit_radii.sort()
	phases.sort()

	for index in range(1, orbit_radii.size()):
		assert_gt(
			float(orbit_radii[index]) - float(orbit_radii[index - 1]),
			shell_spacing - 0.01,
			"each star should occupy a distinct shell with enough room for neighboring planetary envelopes"
		)

	var expected_phase_step: float = TAU / 4.0
	for index in range(1, phases.size()):
		assert_almost_eq(
			float(phases[index]) - float(phases[index - 1]),
			expected_phase_step,
			0.01,
			"same-host stars should be spread evenly around the host instead of bunching into one wedge"
		)

func test_dynamic_star_spawn_uses_other_hosts_before_capping_overflow() -> void:
	var world := SimWorld.new()
	var primary_bh := WorldBuilder._make_black_hole(12_000_000.0)
	primary_bh.position = Vector2.ZERO
	world.add_body(primary_bh)
	var secondary_bh := WorldBuilder._make_black_hole(12_000_000.0)
	secondary_bh.position = Vector2(12.0 * SimConstants.AU, 0.0)
	world.add_body(secondary_bh)
	var spawned_black_holes: Array = [
		{"object_id": "cluster_0:black_hole_0", "is_primary": true, "body": primary_bh},
		{"object_id": "cluster_0:black_hole_1", "is_primary": false, "body": secondary_bh},
	]
	var profile := {
		"star_count": 5,
		"planets_per_star": 5,
		"star_inner_orbit_au": 4.0,
		"star_outer_orbit_au": 20.0,
		"star_mass_scale_min": 1.0,
		"star_mass_scale_max": 1.0,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 27

	var stars: Array = WorldBuilder._place_dynamic_stars(spawned_black_holes, profile, rng)
	var distinct_host_ids: Dictionary = {}

	assert_eq(stars.size(), 4, "overflow should cap to the combined safe host capacity instead of spawning overlapping shells")
	for star in stars:
		distinct_host_ids[star.orbit_parent_id] = true
	assert_eq(distinct_host_ids.size(), 2, "overflow should redistribute stars across other hosts before dropping the excess")

func test_initial_host_system_frame_prefers_primary_star_bearing_black_hole() -> void:
	var world := SimWorld.new()
	var cluster_state: ClusterState = _make_cluster_state_with_black_holes([
		{
			"object_id": "cluster_0:black_hole_0",
			"local_position": Vector2.ZERO,
			"is_primary": true,
		},
		{
			"object_id": "cluster_0:black_hole_1",
			"local_position": Vector2(12.0 * SimConstants.AU, 0.0),
			"is_primary": false,
		},
	])
	var primary_bh: SimBody = _spawn_black_hole_for_frame_test(
		world,
		"cluster_0:black_hole_0",
		Vector2.ZERO
	)
	var secondary_bh: SimBody = _spawn_black_hole_for_frame_test(
		world,
		"cluster_0:black_hole_1",
		Vector2(12.0 * SimConstants.AU, 0.0)
	)
	_spawn_bound_star_for_frame_test(world, primary_bh, Vector2(5.0 * SimConstants.AU, 0.0))
	_spawn_bound_star_for_frame_test(world, secondary_bh, Vector2(14.0 * SimConstants.AU, 0.0))
	_spawn_bound_star_for_frame_test(world, secondary_bh, Vector2(12.0 * SimConstants.AU, 6.0 * SimConstants.AU))

	var frame: Dictionary = WorldBuilder.compute_initial_host_system_frame(world, cluster_state)

	assert_true(bool(frame.get("found_host_system", false)), "frame computation should find a host system when the primary BH has a bound star")
	assert_eq(
		frame.get("host_black_hole_object_id", ""),
		"cluster_0:black_hole_0",
		"the primary BH should win host selection as soon as it has at least one bound star"
	)
	assert_eq(
		frame.get("focus_local_position", Vector2.ONE),
		primary_bh.position,
		"camera framing should focus the selected host BH position"
	)

func test_initial_host_system_frame_falls_back_to_non_primary_star_bearing_black_hole() -> void:
	var world := SimWorld.new()
	var cluster_state: ClusterState = _make_cluster_state_with_black_holes([
		{
			"object_id": "cluster_0:black_hole_0",
			"local_position": Vector2.ZERO,
			"is_primary": true,
		},
		{
			"object_id": "cluster_0:black_hole_1",
			"local_position": Vector2(10.0 * SimConstants.AU, 0.0),
			"is_primary": false,
		},
	])
	_spawn_black_hole_for_frame_test(world, "cluster_0:black_hole_0", Vector2.ZERO)
	var secondary_bh: SimBody = _spawn_black_hole_for_frame_test(
		world,
		"cluster_0:black_hole_1",
		Vector2(10.0 * SimConstants.AU, 0.0)
	)
	_spawn_bound_star_for_frame_test(world, secondary_bh, Vector2(10.0 * SimConstants.AU, 4.5 * SimConstants.AU))

	var frame: Dictionary = WorldBuilder.compute_initial_host_system_frame(world, cluster_state)

	assert_true(bool(frame.get("found_host_system", false)), "frame computation should still find a host system when the primary BH has no stars")
	assert_eq(
		frame.get("host_black_hole_object_id", ""),
		"cluster_0:black_hole_1",
		"host selection should fall back to another star-bearing BH when the primary is empty"
	)

func test_initial_host_system_frame_uses_live_bound_positions_and_ignores_unbound_bodies() -> void:
	var world := SimWorld.new()
	var cluster_state: ClusterState = _make_cluster_state_with_black_holes([
		{
			"object_id": "cluster_0:black_hole_0",
			"local_position": Vector2.ZERO,
			"is_primary": true,
		},
	])
	var host_bh: SimBody = _spawn_black_hole_for_frame_test(world, "cluster_0:black_hole_0", Vector2.ZERO)
	var bound_star: SimBody = _spawn_bound_star_for_frame_test(
		world,
		host_bh,
		Vector2(5.0 * SimConstants.AU, 0.0),
		1.0 * SimConstants.AU
	)
	var bound_planet: SimBody = _spawn_bound_planet_for_frame_test(
		world,
		bound_star,
		Vector2(5.0 * SimConstants.AU, 2.0 * SimConstants.AU),
		0.5 * SimConstants.AU
	)
	_spawn_unbound_star_for_frame_test(world, Vector2(20.0 * SimConstants.AU, 0.0))
	_spawn_unbound_planet_for_frame_test(world, Vector2(30.0 * SimConstants.AU, 0.0))

	var frame: Dictionary = WorldBuilder.compute_initial_host_system_frame(world, cluster_state)
	var expected_system_radius: float = maxf(
		host_bh.radius,
		host_bh.position.distance_to(bound_star.position)
			+ maxf(
				bound_star.radius,
				bound_star.position.distance_to(bound_planet.position) + bound_planet.radius
			)
	)

	assert_true(bool(frame.get("found_host_system", false)), "the bound host system should still be discovered")
	assert_almost_eq(
		float(frame.get("visible_radius_sim", 0.0)),
		expected_system_radius * 1.15,
		0.001,
		"camera framing should follow the loaded live body positions rather than stale orbit_radius values"
	)

func test_dynamic_star_orbit_band_raises_inner_clearance_for_scaled_bodies() -> void:
	var profile := {
		"star_inner_orbit_au": 4.0,
		"star_outer_orbit_au": 20.0,
		"planets_per_star": 5,
		"star_mass_scale_min": 1.0,
		"star_mass_scale_max": 1.3,
	}

	var orbit_band: Dictionary = WorldBuilder._resolve_dynamic_star_orbit_band(profile)
	var expected_clearance: float = SimConstants.BLACK_HOLE_RADIUS \
		+ SimConstants.STAR_RADIUS * sqrt(1.3) \
		+ WorldBuilder._max_core_planet_orbit_radius(5) * SimConstants.AU \
		+ 0.75 * SimConstants.AU

	assert_almost_eq(
		float(orbit_band.get("inner", 0.0)),
		expected_clearance,
		0.001,
		"the effective inner star orbit should expand to the required clearance when scaled bodies need more room"
	)
	assert_almost_eq(
		float(orbit_band.get("outer", 0.0)),
		20.0 * SimConstants.AU,
		0.001,
		"the configured outer orbit should remain unchanged when only the inner clearance grows"
	)

func test_public_worldgen_cluster_can_materialize_more_than_four_planets_per_star_when_legacy_hint_requests_it() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	config.black_hole_count = 5
	config.star_count = 1
	config.planets_per_star = 6
	config.disturbance_body_count = 0

	WorldBuilder.build_from_config(world, config)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 1, "test setup should create one local spawn star")
	assert_eq(
		world.count_bodies_by_type(SimBody.BodyType.PLANET),
		6,
		"planet generation should no longer be capped by the old four-slot orbit template"
	)

func test_star_nursery_materializes_richer_local_system_than_dense_bh_knot() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 1888
	config.cluster_density = 0.92
	config.void_strength = 0.16
	config.bh_richness = 0.55
	config.star_richness = 0.62
	config.rare_zone_frequency = 1.0

	var nursery_world: SimWorld = _materialize_worldgen_archetype(config, "star_nursery")
	var dense_world: SimWorld = _materialize_worldgen_archetype(config, "dense_bh_knot")

	assert_gt(
		nursery_world.count_bodies_by_type(SimBody.BodyType.STAR),
		dense_world.count_bodies_by_type(SimBody.BodyType.STAR),
		"star nurseries should materialize more stars than dense BH knots"
	)
	assert_gt(
		nursery_world.count_bodies_by_type(SimBody.BodyType.PLANET),
		dense_world.count_bodies_by_type(SimBody.BodyType.PLANET),
		"star nurseries should materialize more planets than dense BH knots"
	)

func test_scrap_rich_remnant_materializes_more_disturbances_than_void() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 1999
	config.cluster_density = 0.94
	config.void_strength = 0.18
	config.bh_richness = 0.57
	config.star_richness = 0.57
	config.rare_zone_frequency = 1.0

	var remnant_world: SimWorld = _materialize_worldgen_archetype(config, "scrap_rich_remnant")
	var void_world: SimWorld = _materialize_worldgen_archetype(config, "void")

	assert_gt(
		remnant_world.count_bodies_by_type(SimBody.BodyType.ASTEROID),
		void_world.count_bodies_by_type(SimBody.BodyType.ASTEROID),
		"scrap-rich remnants should materialize more disturbance bodies than void clusters"
	)

func test_archetype_material_profiles_bias_materialized_body_materials() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 2111
	config.cluster_density = 0.94
	config.void_strength = 0.18
	config.bh_richness = 0.58
	config.star_richness = 0.59
	config.rare_zone_frequency = 1.0

	var remnant_world: SimWorld = _materialize_worldgen_archetype(config, "scrap_rich_remnant")
	var nursery_world: SimWorld = _materialize_worldgen_archetype(config, "star_nursery")

	var remnant_metallic_asteroids: int = _count_bodies_with_material(
		remnant_world,
		SimBody.BodyType.ASTEROID,
		SimBody.MaterialType.METALLIC
	)
	var nursery_rocky_or_mixed_planets: int = _count_bodies_with_materials(
		nursery_world,
		SimBody.BodyType.PLANET,
		[SimBody.MaterialType.ROCKY, SimBody.MaterialType.MIXED]
	)

	assert_gt(
		remnant_metallic_asteroids,
		0,
		"scrap-rich remnants should bias at least some disturbance bodies toward metallic materials"
	)
	assert_gt(
		nursery_rocky_or_mixed_planets,
		0,
		"star nurseries should bias at least some planets toward rocky or mixed materials"
	)

func test_spawn_viable_star_bearing_archetypes_begin_with_host_aligned_dynamic_stars() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 2442
	config.cluster_density = 0.94
	config.void_strength = 0.18
	config.bh_richness = 0.60
	config.star_richness = 0.60
	config.rare_zone_frequency = 1.0

	for archetype in ["dense_bh_knot", "star_nursery", "scrap_rich_remnant"]:
		var world: SimWorld = _materialize_worldgen_archetype(config, archetype)
		var anchor: Dictionary = DEBUG_METRICS_SCRIPT.new().build_snapshot(world, 0)["anchor"]

		assert_eq(
			anchor["stars_with_host"],
			world.get_stars().size(),
			"%s should assign every spawned star a host black hole" % archetype
		)
		assert_eq(
			anchor["host_dominance_mismatch_count"],
			0,
			"%s should begin with host-aligned dominant anchors" % archetype
		)
		if world.get_black_holes().size() > 1 and world.get_stars().size() > 1:
			assert_gt(
				_count_distinct_star_hosts(world),
				1,
				"%s should spread dynamic stars across more than one black hole when multiple hosts exist" % archetype
			)

func test_spawn_viable_star_bearing_archetypes_still_materialize_requested_star_counts_after_rescale() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 2442
	config.cluster_density = 0.94
	config.void_strength = 0.18
	config.bh_richness = 0.60
	config.star_richness = 0.60
	config.rare_zone_frequency = 1.0
	var safe_config = config.copy()
	safe_config.clamp_values()
	var worldgen_config = GALAXY_BUILDER_SCRIPT._build_public_worldgen_config(safe_config)
	var worldgen = GALAXY_WORLDGEN_SCRIPT.new(worldgen_config)

	for archetype in ["dense_bh_knot", "star_nursery", "scrap_rich_remnant"]:
		var cluster_state: ClusterState = _find_spawn_viable_cluster_state_for_archetype(
			worldgen_config,
			worldgen,
			safe_config.seed,
			archetype,
			40
		)
		assert_not_null(cluster_state, "test setup should find a spawn-viable %s candidate within the scan window" % archetype)
		var world := SimWorld.new()
		WorldBuilder.materialize_cluster_into_world(world, cluster_state)
		assert_eq(
			world.count_bodies_by_type(SimBody.BodyType.STAR),
			int(cluster_state.simulation_profile.get("star_count", 0)),
			"%s should still materialize its requested star count after the scaled-body clearance change" % archetype
		)

func _build_fixture_world(configure: Callable) -> SimWorld:
	var config = START_CONFIG_SCRIPT.new()
	configure.call(config)
	var galaxy_state: GalaxyState = GALAXY_BUILDER_SCRIPT.build_fixture_from_config(config)
	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state)
	return session.sim_world

func _materialize_worldgen_archetype(config, archetype: String) -> SimWorld:
	var safe_config = config.copy()
	safe_config.clamp_values()
	var worldgen_config = GALAXY_BUILDER_SCRIPT._build_public_worldgen_config(safe_config)
	var worldgen = GALAXY_WORLDGEN_SCRIPT.new(worldgen_config)
	var candidate_descriptor = _find_candidate_descriptor_for_archetype(worldgen, safe_config.seed, archetype, 40)
	assert_not_null(candidate_descriptor, "test setup should find a %s candidate within the scan window" % archetype)
	var cluster_state: ClusterState = GALAXY_BUILDER_SCRIPT._build_cluster_state_from_candidate(
		worldgen_config,
		candidate_descriptor
	)
	var world := SimWorld.new()
	WorldBuilder.materialize_cluster_into_world(world, cluster_state)
	return world

func _materialize_spawn_viable_worldgen_archetype(config, archetype: String) -> SimWorld:
	var safe_config = config.copy()
	safe_config.clamp_values()
	var worldgen_config = GALAXY_BUILDER_SCRIPT._build_public_worldgen_config(safe_config)
	var worldgen = GALAXY_WORLDGEN_SCRIPT.new(worldgen_config)
	var cluster_state: ClusterState = _find_spawn_viable_cluster_state_for_archetype(
		worldgen_config,
		worldgen,
		safe_config.seed,
		archetype,
		40
	)
	assert_not_null(cluster_state, "test setup should find a spawn-viable %s candidate within the scan window" % archetype)
	var world := SimWorld.new()
	WorldBuilder.materialize_cluster_into_world(world, cluster_state)
	return world

func _find_candidate_descriptor_for_archetype(worldgen, galaxy_seed: int, archetype: String, scan_radius: int):
	for y in range(-scan_radius, scan_radius + 1):
		for x in range(-scan_radius, scan_radius + 1):
			var region_descriptor = worldgen.describe_region(galaxy_seed, Vector2i(x, y))
			var candidates: Array = worldgen.build_cluster_candidates(galaxy_seed, region_descriptor)
			for candidate_descriptor in candidates:
				if candidate_descriptor.region_archetype == archetype:
					return candidate_descriptor
	return null

func _find_spawn_viable_cluster_state_for_archetype(
		worldgen_config,
		worldgen,
		galaxy_seed: int,
		archetype: String,
		scan_radius: int) -> ClusterState:
	for y in range(-scan_radius, scan_radius + 1):
		for x in range(-scan_radius, scan_radius + 1):
			var region_descriptor = worldgen.describe_region(galaxy_seed, Vector2i(x, y))
			var candidates: Array = worldgen.build_cluster_candidates(galaxy_seed, region_descriptor)
			for candidate_descriptor in candidates:
				if candidate_descriptor.region_archetype != archetype:
					continue
				var cluster_state: ClusterState = GALAXY_BUILDER_SCRIPT._build_cluster_state_from_candidate(
					worldgen_config,
					candidate_descriptor
				)
				if bool(cluster_state.simulation_profile.get("spawn_viable", false)):
					return cluster_state
	return null

func _count_distinct_star_hosts(world: SimWorld) -> int:
	var host_ids: Dictionary = {}
	for star in world.get_stars():
		if star.orbit_parent_id >= 0:
			host_ids[star.orbit_parent_id] = true
	return host_ids.size()

func _count_bodies_with_material(world: SimWorld, body_type: int, material_type: int) -> int:
	var count: int = 0
	for body in world.bodies:
		if body.active and body.body_type == body_type and body.material_type == material_type:
			count += 1
	return count

func _count_bodies_with_materials(world: SimWorld, body_type: int, material_types: Array) -> int:
	var count: int = 0
	for body in world.bodies:
		if body.active and body.body_type == body_type and material_types.has(body.material_type):
			count += 1
	return count

func _make_cluster_state_with_black_holes(black_hole_specs: Array) -> ClusterState:
	var cluster_state := ClusterState.new()
	for spec in black_hole_specs:
		var object_state := ClusterObjectState.new()
		object_state.object_id = str(spec.get("object_id", ""))
		object_state.kind = "black_hole"
		object_state.local_position = Vector2(spec.get("local_position", Vector2.ZERO))
		object_state.descriptor = {
			"body_type": SimBody.BodyType.BLACK_HOLE,
			"material_type": SimBody.MaterialType.STELLAR,
			"radius": SimConstants.BLACK_HOLE_RADIUS,
			"is_primary": bool(spec.get("is_primary", false)),
		}
		cluster_state.register_object(object_state)
		if bool(spec.get("is_primary", false)):
			cluster_state.cluster_blueprint["primary_black_hole_object_id"] = object_state.object_id
	return cluster_state

func _make_manual_cluster_object_state_for_world_builder_test(
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

func _spawn_black_hole_for_frame_test(world: SimWorld, object_id: String, position: Vector2) -> SimBody:
	var black_hole := WorldBuilder._make_black_hole(12_000_000.0)
	black_hole.persistent_object_id = object_id
	black_hole.position = position
	world.add_body(black_hole)
	return black_hole

func _spawn_bound_star_for_frame_test(
		world: SimWorld,
		host_bh: SimBody,
		position: Vector2,
		orbit_radius: float = 0.0) -> SimBody:
	var star := WorldBuilder._make_star()
	star.kinematic = false
	star.scripted_orbit_enabled = false
	star.orbit_binding_state = SimBody.OrbitBindingState.FREE_DYNAMIC
	star.orbit_parent_id = host_bh.id
	star.orbit_radius = orbit_radius
	star.position = position
	world.add_body(star)
	return star

func _spawn_bound_planet_for_frame_test(
		world: SimWorld,
		host_star: SimBody,
		position: Vector2,
		orbit_radius: float = 0.0) -> SimBody:
	var planet := SimBody.new()
	planet.body_type = SimBody.BodyType.PLANET
	planet.influence_level = SimBody.InfluenceLevel.A
	planet.material_type = SimBody.MaterialType.ROCKY
	planet.mass = SimConstants.PLANET_MASS_MIN
	planet.radius = SimConstants.PLANET_RADIUS_MIN
	planet.kinematic = true
	planet.scripted_orbit_enabled = true
	planet.orbit_binding_state = SimBody.OrbitBindingState.BOUND_ANALYTIC
	planet.orbit_parent_id = host_star.id
	planet.orbit_radius = orbit_radius
	planet.position = position
	world.add_body(planet)
	return planet

func _spawn_unbound_star_for_frame_test(world: SimWorld, position: Vector2) -> SimBody:
	var star := WorldBuilder._make_star()
	star.kinematic = false
	star.scripted_orbit_enabled = false
	star.orbit_binding_state = SimBody.OrbitBindingState.FREE_DYNAMIC
	star.position = position
	world.add_body(star)
	return star

func _spawn_unbound_planet_for_frame_test(world: SimWorld, position: Vector2) -> SimBody:
	var planet := SimBody.new()
	planet.body_type = SimBody.BodyType.PLANET
	planet.influence_level = SimBody.InfluenceLevel.A
	planet.material_type = SimBody.MaterialType.ROCKY
	planet.mass = SimConstants.PLANET_MASS_MIN
	planet.radius = SimConstants.PLANET_RADIUS_MIN
	planet.position = position
	world.add_body(planet)
	return planet
