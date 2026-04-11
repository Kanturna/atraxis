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

	assert_eq(
		world._determine_black_hole_nearfield_substeps(),
		1,
		"bodies outside the dominant BH nearfield should keep the normal integration step count"
	)
