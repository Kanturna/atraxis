extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")

func test_stable_mode_preserves_existing_mvp_reference_layout() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()

	WorldBuilder.build_from_config(world, config)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 1, "stable mode should keep exactly one star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 3, "stable mode should keep three scripted planets")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.ASTEROID), 15, "stable mode should keep fifteen asteroids")

	for body in world.bodies:
		if body.body_type != SimBody.BodyType.PLANET:
			continue
		assert_true(body.kinematic, "stable mode planets must remain kinematic")
		assert_true(body.scripted_orbit_enabled, "stable mode planets must remain scripted")

func test_chaos_mode_creates_dynamic_inflow_bodies() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW
	config.body_count = 4
	config.seed = 42

	WorldBuilder.build_from_config(world, config)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 1, "chaos mode should still create one central star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 4, "chaos mode should create the configured inflow body count")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.ASTEROID), 0, "chaos mode should not mix in the stable asteroid belt")

	for body in world.bodies:
		if body.body_type != SimBody.BodyType.PLANET:
			continue
		assert_false(body.kinematic, "chaos inflow bodies should be fully dynamic")
		assert_false(body.scripted_orbit_enabled, "chaos inflow bodies should not use scripted orbiting")
		assert_eq(body.influence_level, SimBody.InfluenceLevel.B, "chaos inflow bodies should remain star-focused rather than dominant gravity centers")

func test_chaos_mode_same_seed_rebuilds_identical_start_state() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW
	config.seed = 2026
	config.body_count = 5
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

func test_chaos_mode_different_seed_changes_the_inflow_layout() -> void:
	var config_a = START_CONFIG_SCRIPT.new()
	config_a.mode = START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW
	config_a.seed = 100
	config_a.body_count = 4

	var config_b = config_a.copy()
	config_b.seed = 101

	var world_a := SimWorld.new()
	var world_b := SimWorld.new()
	WorldBuilder.build_from_config(world_a, config_a)
	WorldBuilder.build_from_config(world_b, config_b)

	var planets_a := _collect_planets(world_a)
	var planets_b := _collect_planets(world_b)
	var found_difference: bool = false

	for i in range(min(planets_a.size(), planets_b.size())):
		if not planets_a[i].position.is_equal_approx(planets_b[i].position):
			found_difference = true
			break
		if not planets_a[i].velocity.is_equal_approx(planets_b[i].velocity):
			found_difference = true
			break

	assert_true(found_difference, "different seeds should alter the inflow layout")

func _collect_planets(world: SimWorld) -> Array:
	var planets: Array = []
	for body in world.bodies:
		if body.active and body.body_type == SimBody.BodyType.PLANET:
			planets.append(body)
	return planets
