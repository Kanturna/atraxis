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

func test_star_star_gravity_weakens_beyond_fade_distance() -> void:
	var near_acceleration: Vector2 = _measure_star_star_acceleration(
		0.5 * SimConstants.STAR_STAR_FULL_FORCE_DISTANCE
	)
	var far_distance: float = SimConstants.STAR_STAR_FORCE_FADE_DISTANCE + SimConstants.AU
	var far_acceleration: Vector2 = _measure_star_star_acceleration(far_distance)
	var expected_far: float = _expected_star_star_acceleration(
		far_distance,
		SimConstants.STAR_STAR_GRAVITY_FAR_SCALE
	)

	assert_lt(
		far_acceleration.length(),
		near_acceleration.length() * 0.1,
		"far-separated stars should influence each other much less than close pairs"
	)
	assert_almost_eq(
		far_acceleration.length(),
		expected_far,
		maxf(expected_far * 0.001, 0.000001),
		"beyond the fade distance star-star gravity should clamp to the far-field scale"
	)

func test_star_star_gravity_returns_full_strength_inside_full_force_distance() -> void:
	var distance: float = 0.5 * SimConstants.STAR_STAR_FULL_FORCE_DISTANCE
	var acceleration: Vector2 = _measure_star_star_acceleration(distance)
	var expected_acceleration: float = _expected_star_star_acceleration(distance, 1.0)

	assert_almost_eq(
		acceleration.length(),
		expected_acceleration,
		maxf(expected_acceleration * 0.001, 0.000001),
		"inside the full-force distance star-star gravity should keep full strength"
	)

func _measure_star_star_acceleration(distance: float) -> Vector2:
	var left_star := _make_dynamic_star(1, Vector2.ZERO)
	var right_star := _make_dynamic_star(2, Vector2(distance, 0.0))

	GravitySolver.new().apply_gravity([left_star, right_star])

	return left_star.acceleration

func _make_dynamic_star(id: int, position: Vector2) -> SimBody:
	var star := SimBody.new()
	star.id = id
	star.active = true
	star.kinematic = false
	star.influence_level = SimBody.InfluenceLevel.A
	star.body_type = SimBody.BodyType.STAR
	star.mass = SimConstants.STAR_MASS
	star.radius = SimConstants.STAR_RADIUS
	star.position = position
	star.acceleration = Vector2.ZERO
	return star

func _expected_star_star_acceleration(distance: float, force_scale: float) -> float:
	return (
		SimConstants.G * SimConstants.STAR_MASS
		/ (distance * distance + SimConstants.GRAVITY_SOFTENING_SQ)
	) * force_scale
