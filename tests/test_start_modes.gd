extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")

func test_stable_anchor_builds_one_black_hole_one_sun_and_configured_bodies() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.STABLE_ANCHOR
	config.core_planet_count = 3
	config.disturbance_body_count = 4
	config.seed = 42

	WorldBuilder.build_from_config(world, config)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE), 1, "stable anchor should build exactly one black hole")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 1, "stable anchor should build exactly one moving sun")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 3, "stable anchor should build the configured core planets")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.ASTEROID), 4, "stable anchor should build the configured disturbance bodies")

	var black_hole: SimBody = world.get_black_hole()
	var star: SimBody = world.get_star()
	assert_not_null(black_hole, "stable anchor should expose the black hole anchor")
	assert_not_null(star, "stable anchor should expose the moving sun")
	assert_true(black_hole.kinematic, "black hole should remain fixed")
	assert_false(star.kinematic, "stable anchor sun should move dynamically")

	for body in world.bodies:
		if body.body_type == SimBody.BodyType.PLANET:
			assert_true(body.kinematic, "core planets should remain analytic in stable anchor")
			assert_true(body.is_analytic_orbit_bound(), "core planets should start in a bound analytic state")
			assert_eq(body.orbit_binding_state, SimBody.OrbitBindingState.BOUND_ANALYTIC, "core planets should advertise their orbit state")
			assert_eq(body.orbit_parent_id, star.id, "core planets should bind to the moving sun")
		elif body.body_type == SimBody.BodyType.ASTEROID:
			assert_false(body.kinematic, "disturbance bodies should remain dynamic")
			assert_eq(body.influence_level, SimBody.InfluenceLevel.B, "disturbance bodies should remain limited gravity sources")

func test_stable_anchor_sun_moves_while_black_hole_stays_fixed() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.STABLE_ANCHOR

	WorldBuilder.build_from_config(world, config)

	var black_hole: SimBody = world.get_black_hole()
	var star: SimBody = world.get_star()
	var initial_star_pos: Vector2 = star.position
	var initial_black_hole_pos: Vector2 = black_hole.position

	world.step_sim(SimConstants.FIXED_DT)

	assert_false(star.position.is_equal_approx(initial_star_pos), "the stable anchor sun should actually move")
	assert_true(black_hole.position.is_equal_approx(initial_black_hole_pos), "the black hole anchor should remain fixed")

func test_chaos_mode_creates_dynamic_inflow_bodies_without_black_hole() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW
	config.chaos_body_count = 4
	config.seed = 42

	WorldBuilder.build_from_config(world, config)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE), 0, "chaos inflow should stay separate from the stable anchor macro test")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 1, "chaos inflow should still create one central star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 4, "chaos inflow should create the configured inflow body count")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.ASTEROID), 0, "chaos inflow should not mix in stable anchor disturbance asteroids")

	for body in world.bodies:
		if body.body_type != SimBody.BodyType.PLANET:
			continue
		assert_false(body.kinematic, "chaos inflow bodies should be fully dynamic")
		assert_false(body.scripted_orbit_enabled, "chaos inflow bodies should not use analytic orbiting")
		assert_eq(body.orbit_binding_state, SimBody.OrbitBindingState.FREE_DYNAMIC, "chaos inflow should start fully free")
		assert_eq(body.influence_level, SimBody.InfluenceLevel.B, "chaos inflow bodies should remain star-focused rather than dominant gravity centers")

func test_chaos_mode_same_seed_rebuilds_identical_start_state() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW
	config.seed = 2026
	config.chaos_body_count = 5
	config.spawn_radius_au = 4.1
	config.spawn_spread_au = 0.6
	config.inflow_speed_scale = 0.9
	config.tangential_bias = 0.55

	var world_a := SimWorld.new()
	var world_b := SimWorld.new()
	WorldBuilder.build_from_config(world_a, config)
	WorldBuilder.build_from_config(world_b, config)

	var planets_a := _collect_planets(world_a)
	var planets_b := _collect_planets(world_b)

	assert_eq(planets_a.size(), planets_b.size(), "same-seed worlds should create the same planet count")
	for i in range(planets_a.size()):
		assert_eq(planets_a[i].material_type, planets_b[i].material_type, "same seed should keep material selection stable")
		assert_almost_eq(planets_a[i].mass, planets_b[i].mass, 0.001, "same seed should keep mass stable")
		assert_almost_eq(planets_a[i].position.x, planets_b[i].position.x, 0.001, "same seed should keep spawn x stable")
		assert_almost_eq(planets_a[i].position.y, planets_b[i].position.y, 0.001, "same seed should keep spawn y stable")
		assert_almost_eq(planets_a[i].velocity.x, planets_b[i].velocity.x, 0.001, "same seed should keep velocity x stable")
		assert_almost_eq(planets_a[i].velocity.y, planets_b[i].velocity.y, 0.001, "same seed should keep velocity y stable")

func _collect_planets(world: SimWorld) -> Array:
	var planets: Array = []
	for body in world.bodies:
		if body.active and body.body_type == SimBody.BodyType.PLANET:
			planets.append(body)
	return planets
