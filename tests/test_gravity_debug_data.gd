extends GutTest

const DATA_SCRIPT := preload("res://rendering/gravity_debug_data.gd")

func test_radius_from_mass_and_threshold_matches_inverse_square_formula() -> void:
	var data := DATA_SCRIPT.new()
	var radius: float = data.radius_from_mass_and_threshold(SimConstants.STAR_MASS, 100.0)

	assert_almost_eq(
		radius,
		sqrt((SimConstants.G * SimConstants.STAR_MASS) / 100.0),
		0.001,
		"gravity debug radius should follow r = sqrt(GM / threshold)"
	)

func test_build_ring_specs_only_uses_active_stars() -> void:
	var star := SimBody.new()
	star.id = 1
	star.active = true
	star.body_type = SimBody.BodyType.STAR
	star.mass = SimConstants.STAR_MASS

	var planet := SimBody.new()
	planet.id = 2
	planet.active = true
	planet.body_type = SimBody.BodyType.PLANET
	planet.mass = SimConstants.PLANET_MASS_MAX

	var inactive_star := SimBody.new()
	inactive_star.id = 3
	inactive_star.active = false
	inactive_star.body_type = SimBody.BodyType.STAR
	inactive_star.mass = SimConstants.STAR_MASS

	var specs: Array = DATA_SCRIPT.new().build_ring_specs([star, planet, inactive_star])

	assert_eq(
		specs.size(),
		SimConstants.GRAVITY_DEBUG_THRESHOLDS.size(),
		"only the active star should contribute gravity debug rings"
	)
	for spec in specs:
		assert_eq(spec["body_id"], star.id, "ring specs should belong to the active star only")

func test_small_rings_under_screen_threshold_are_not_emitted() -> void:
	var tiny_star := SimBody.new()
	tiny_star.id = 7
	tiny_star.active = true
	tiny_star.body_type = SimBody.BodyType.STAR
	tiny_star.mass = 1.0

	var specs: Array = DATA_SCRIPT.new().build_ring_specs([tiny_star])

	assert_eq(specs.size(), 0, "rings below the minimum screen radius should be skipped")

func test_multiple_stars_build_separate_centers() -> void:
	var star_a := SimBody.new()
	star_a.id = 1
	star_a.active = true
	star_a.body_type = SimBody.BodyType.STAR
	star_a.mass = SimConstants.STAR_MASS
	star_a.position = Vector2.ZERO

	var star_b := SimBody.new()
	star_b.id = 2
	star_b.active = true
	star_b.body_type = SimBody.BodyType.STAR
	star_b.mass = SimConstants.STAR_MASS * 0.5
	star_b.position = Vector2(250.0, -120.0)

	var specs: Array = DATA_SCRIPT.new().build_ring_specs([star_a, star_b])
	var count_a: int = 0
	var count_b: int = 0
	var center_a: Vector2 = BodyRenderer.sim_to_screen(star_a.position)
	var center_b: Vector2 = BodyRenderer.sim_to_screen(star_b.position)

	for spec in specs:
		if spec["body_id"] == star_a.id:
			count_a += 1
			assert_eq(spec["center"], center_a, "star A rings should use star A as center")
		elif spec["body_id"] == star_b.id:
			count_b += 1
			assert_eq(spec["center"], center_b, "star B rings should use star B as center")

	assert_eq(count_a, SimConstants.GRAVITY_DEBUG_THRESHOLDS.size(), "star A should get one ring per threshold")
	assert_eq(count_b, SimConstants.GRAVITY_DEBUG_THRESHOLDS.size(), "star B should get one ring per threshold")

func test_black_hole_also_contributes_gravity_debug_rings() -> void:
	var black_hole := SimBody.new()
	black_hole.id = 9
	black_hole.active = true
	black_hole.body_type = SimBody.BodyType.BLACK_HOLE
	black_hole.mass = SimConstants.BLACK_HOLE_MASS

	var specs: Array = DATA_SCRIPT.new().build_ring_specs([black_hole])

	assert_eq(specs.size(), SimConstants.GRAVITY_DEBUG_THRESHOLDS.size(), "black hole should emit one gravity ring per threshold")
	for spec in specs:
		assert_eq(spec["body_id"], black_hole.id, "black hole rings should belong to the black hole source")
