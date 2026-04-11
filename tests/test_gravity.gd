extends GutTest

func test_kinematic_source_accelerates_dynamic_target() -> void:
	var source := SimBody.new()
	source.id = 1
	source.active = true
	source.kinematic = true
	source.influence_level = SimBody.InfluenceLevel.A
	source.body_type = SimBody.BodyType.STAR
	source.mass = SimConstants.STAR_MASS
	source.position = Vector2.ZERO

	var target := SimBody.new()
	target.id = 2
	target.active = true
	target.kinematic = false
	target.influence_level = SimBody.InfluenceLevel.B
	target.body_type = SimBody.BodyType.ASTEROID
	target.mass = 10.0
	target.position = Vector2(100.0, 0.0)
	target.acceleration = Vector2.ZERO

	GravitySolver.new().apply_gravity([source, target])

	assert_gt(target.acceleration.length(), 0.0, "dynamic body should receive gravity from kinematic source")
	assert_lt(target.acceleration.x, 0.0, "gravity should point toward the source")

func test_kinematic_target_does_not_collect_acceleration() -> void:
	var source := SimBody.new()
	source.id = 1
	source.active = true
	source.kinematic = true
	source.influence_level = SimBody.InfluenceLevel.A
	source.body_type = SimBody.BodyType.STAR
	source.mass = SimConstants.STAR_MASS
	source.position = Vector2.ZERO

	var target := SimBody.new()
	target.id = 2
	target.active = true
	target.kinematic = true
	target.scripted_orbit_enabled = true
	target.influence_level = SimBody.InfluenceLevel.A
	target.body_type = SimBody.BodyType.PLANET
	target.mass = 1000.0
	target.position = Vector2(250.0, 0.0)
	target.acceleration = Vector2.ZERO

	GravitySolver.new().apply_gravity([source, target])

	assert_eq(target.acceleration, Vector2.ZERO, "scripted kinematic orbiters should not collect gravity")
