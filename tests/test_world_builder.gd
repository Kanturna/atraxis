extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const GALAXY_BUILDER_SCRIPT := preload("res://simulation/galaxy_builder.gd")

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

func _build_fixture_world(configure: Callable) -> SimWorld:
	var config = START_CONFIG_SCRIPT.new()
	configure.call(config)
	var galaxy_state: GalaxyState = GALAXY_BUILDER_SCRIPT.build_fixture_from_config(config)
	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state)
	return session.sim_world
