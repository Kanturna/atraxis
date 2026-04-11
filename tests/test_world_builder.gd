extends GutTest

func test_world_builder_creates_phase1_mvp_layout() -> void:
	var world := SimWorld.new()

	WorldBuilder.build_mvp(world)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 1, "MVP should create one star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 3, "MVP should create three planets")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.ASTEROID), 15, "MVP should create fifteen asteroids")

	for body in world.bodies:
		if body.body_type != SimBody.BodyType.PLANET:
			continue
		assert_true(body.kinematic, "phase-1 planets remain kinematic")
		assert_true(body.scripted_orbit_enabled, "phase-1 planets should use scripted orbiting")
		assert_gt(body.orbit_radius, 0.0, "planet should have a configured orbit radius")
		assert_gt(body.orbit_angular_speed, 0.0, "planet should have a configured orbit speed")

func test_scripted_planet_orbit_advances_without_leaving_its_radius() -> void:
	var world := SimWorld.new()

	WorldBuilder.build_mvp(world)
	var planet: SimBody = null
	for body in world.bodies:
		if body.body_type == SimBody.BodyType.PLANET:
			planet = body
			break

	assert_not_null(planet, "world builder should create at least one planet")

	var old_position: Vector2 = planet.position
	var orbit_radius: float = planet.orbit_radius
	world.step_sim(SimConstants.FIXED_DT)

	assert_ne(planet.position, old_position, "scripted planets should visibly advance each tick")
	assert_almost_eq(
		planet.position.distance_to(planet.orbit_center),
		orbit_radius,
		0.01,
		"scripted planets should stay on their configured orbit radius"
	)
