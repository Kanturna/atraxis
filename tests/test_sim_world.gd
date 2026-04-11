extends GutTest

func test_near_dominant_black_hole_enables_local_substeps() -> void:
	var world := SimWorld.new()

	var black_hole := SimBody.new()
	black_hole.active = true
	black_hole.body_type = SimBody.BodyType.BLACK_HOLE
	black_hole.kinematic = true
	black_hole.mass = 12_000_000.0
	world.add_body(black_hole)

	var star := SimBody.new()
	star.active = true
	star.body_type = SimBody.BodyType.STAR
	star.kinematic = false
	star.mass = SimConstants.STAR_MASS
	star.position = Vector2(400.0, 0.0)
	world.add_body(star)

	world._rebuild_dominant_bh_cache()
	assert_eq(
		world._determine_black_hole_nearfield_substeps(),
		SimConstants.BH_NEARFIELD_SUBSTEPS,
		"dynamic bodies deep inside a dominant BH nearfield should trigger local integration substeps"
	)

func test_far_from_black_hole_keeps_normal_step_count() -> void:
	var world := SimWorld.new()

	var black_hole := SimBody.new()
	black_hole.active = true
	black_hole.body_type = SimBody.BodyType.BLACK_HOLE
	black_hole.kinematic = true
	black_hole.mass = 12_000_000.0
	world.add_body(black_hole)

	var star := SimBody.new()
	star.active = true
	star.body_type = SimBody.BodyType.STAR
	star.kinematic = false
	star.mass = SimConstants.STAR_MASS
	star.position = Vector2(20_000.0, 0.0)
	world.add_body(star)

	world._rebuild_dominant_bh_cache()
	assert_eq(
		world._determine_black_hole_nearfield_substeps(),
		1,
		"bodies outside the dominant BH nearfield should keep the normal integration step count"
	)

func test_star_periapsis_guardrail_projects_inward_crossing_to_minimum_radius() -> void:
	var world := SimWorld.new()

	var black_hole := SimBody.new()
	black_hole.active = true
	black_hole.body_type = SimBody.BodyType.BLACK_HOLE
	black_hole.kinematic = true
	black_hole.mass = 12_000_000.0
	black_hole.radius = SimConstants.BLACK_HOLE_RADIUS
	world.add_body(black_hole)

	var star := SimBody.new()
	star.active = true
	star.body_type = SimBody.BodyType.STAR
	star.kinematic = false
	star.mass = SimConstants.STAR_MASS
	star.radius = SimConstants.STAR_RADIUS
	star.position = Vector2(50.0, 0.0)
	star.velocity = Vector2(-120.0, 30.0)
	world.add_body(star)

	world._rebuild_dominant_bh_cache()
	var previous_position := Vector2(70.0, 0.0)
	world._apply_star_black_hole_periapsis_guardrail(star, previous_position)

	var expected_distance: float = black_hole.radius + star.radius + SimConstants.BH_STAR_APPROACH_PADDING
	assert_almost_eq(
		star.position.distance_to(black_hole.position),
		expected_distance,
		0.001,
		"inward near-BH crossings should be corrected onto the periapsis guardrail radius"
	)
	assert_almost_eq(star.velocity.x, 0.0, 0.001, "inward radial velocity should be removed")
	assert_almost_eq(star.velocity.y, 30.0, 0.001, "tangential velocity should remain visible")

func test_star_periapsis_guardrail_does_not_retrigger_while_moving_outward() -> void:
	var world := SimWorld.new()

	var black_hole := SimBody.new()
	black_hole.active = true
	black_hole.body_type = SimBody.BodyType.BLACK_HOLE
	black_hole.kinematic = true
	black_hole.mass = 12_000_000.0
	black_hole.radius = SimConstants.BLACK_HOLE_RADIUS
	world.add_body(black_hole)

	var star := SimBody.new()
	star.active = true
	star.body_type = SimBody.BodyType.STAR
	star.kinematic = false
	star.mass = SimConstants.STAR_MASS
	star.radius = SimConstants.STAR_RADIUS
	star.position = Vector2(50.0, 0.0)
	star.velocity = Vector2(40.0, 25.0)
	world.add_body(star)

	world._rebuild_dominant_bh_cache()
	var before_position: Vector2 = star.position
	var before_velocity: Vector2 = star.velocity
	world._apply_star_black_hole_periapsis_guardrail(star, Vector2(45.0, 0.0))

	assert_eq(star.position, before_position, "outward motion inside the guardrail should not be corrected again")
	assert_eq(star.velocity, before_velocity, "outward motion should preserve the current velocity")

func test_guardrail_clamps_super_escape_tangential_speed() -> void:
	# A star fires the guardrail with a tangential speed that exceeds local escape
	# velocity. The escape-velocity clamp must reduce it to MARGIN × v_esc while
	# preserving the direction of motion.
	var world := SimWorld.new()

	var black_hole := SimBody.new()
	black_hole.active = true
	black_hole.body_type = SimBody.BodyType.BLACK_HOLE
	black_hole.kinematic = true
	black_hole.mass = 12_000_000.0
	black_hole.radius = SimConstants.BLACK_HOLE_RADIUS
	world.add_body(black_hole)

	var star := SimBody.new()
	star.active = true
	star.body_type = SimBody.BodyType.STAR
	star.kinematic = false
	star.mass = SimConstants.STAR_MASS
	star.radius = SimConstants.STAR_RADIUS
	# Place the star just inside minimum_distance so the guardrail fires.
	var minimum_distance: float = SimConstants.BLACK_HOLE_RADIUS + SimConstants.STAR_RADIUS + SimConstants.BH_STAR_APPROACH_PADDING
	star.position = Vector2(minimum_distance - 1.0, 0.0)
	# Give the star a large tangential (Y-axis) velocity well above escape velocity.
	# v_esc = sqrt(2 * G * M / r) = sqrt(2 * 100 * 12M / 58) ≈ 6 434 units/s
	var escape_speed: float = sqrt(2.0 * SimConstants.G * black_hole.mass / minimum_distance)
	# Set tangential speed to 2× escape velocity — clearly unbound.
	star.velocity = Vector2(-50.0, escape_speed * 2.0)
	world.add_body(star)

	# previous_position was outside minimum_distance → guardrail triggers.
	world._rebuild_dominant_bh_cache()
	world._apply_star_black_hole_periapsis_guardrail(star, Vector2(minimum_distance + 1.0, 0.0))

	var expected_max_speed: float = escape_speed * SimConstants.BH_GUARDRAIL_ESCAPE_MARGIN
	assert_true(
		star.velocity.length() <= expected_max_speed + 0.01,
		"after guardrail, speed must be at or below MARGIN × escape velocity"
	)
	assert_true(
		star.velocity.length() > escape_speed * (SimConstants.BH_GUARDRAIL_ESCAPE_MARGIN - 0.05),
		"clamped speed should be close to MARGIN × escape velocity, not zeroed"
	)

func test_guardrail_does_not_clamp_sub_escape_tangential_speed() -> void:
	# A star fires the guardrail with a tangential speed well below escape velocity.
	# The clamp must not fire; the velocity is left exactly as the guardrail set it.
	var world := SimWorld.new()

	var black_hole := SimBody.new()
	black_hole.active = true
	black_hole.body_type = SimBody.BodyType.BLACK_HOLE
	black_hole.kinematic = true
	black_hole.mass = 12_000_000.0
	black_hole.radius = SimConstants.BLACK_HOLE_RADIUS
	world.add_body(black_hole)

	var star := SimBody.new()
	star.active = true
	star.body_type = SimBody.BodyType.STAR
	star.kinematic = false
	star.mass = SimConstants.STAR_MASS
	star.radius = SimConstants.STAR_RADIUS
	var minimum_distance: float = SimConstants.BLACK_HOLE_RADIUS + SimConstants.STAR_RADIUS + SimConstants.BH_STAR_APPROACH_PADDING
	star.position = Vector2(minimum_distance - 1.0, 0.0)
	# Tangential speed at 40% of escape velocity — clearly bound.
	var escape_speed: float = sqrt(2.0 * SimConstants.G * black_hole.mass / minimum_distance)
	var safe_tangential_speed: float = escape_speed * 0.40
	star.velocity = Vector2(-50.0, safe_tangential_speed)
	world.add_body(star)

	world._rebuild_dominant_bh_cache()
	world._apply_star_black_hole_periapsis_guardrail(star, Vector2(minimum_distance + 1.0, 0.0))

	# After guardrail: inward radial (-50, 0) removed; tangential (0, safe_speed) kept.
	# The clamp should NOT fire since safe_tangential_speed < escape_speed.
	assert_almost_eq(
		star.velocity.length(),
		safe_tangential_speed,
		1.0,
		"sub-escape tangential speed should not be clamped by the escape-velocity guardrail"
	)
