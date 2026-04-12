extends GutTest

func test_close_black_hole_requests_multiple_adaptive_substeps() -> void:
	var world := SimWorld.new()

	var black_hole := _make_black_hole()
	world.add_body(black_hole)

	var star := _make_dynamic_star()
	star.position = Vector2(70.0, 0.0)
	world.add_body(star)

	world._rebuild_dominant_bh_cache()

	assert_gt(
		world._determine_black_hole_adaptive_substeps(SimConstants.FIXED_DT),
		1,
		"very close black-hole passes should request more than one integration substep"
	)

func test_far_from_black_hole_keeps_single_substep() -> void:
	var world := SimWorld.new()

	var black_hole := _make_black_hole()
	world.add_body(black_hole)

	var star := _make_dynamic_star()
	star.position = Vector2(20_000.0, 0.0)
	world.add_body(star)

	world._rebuild_dominant_bh_cache()

	assert_eq(
		world._determine_black_hole_adaptive_substeps(SimConstants.FIXED_DT),
		1,
		"bodies far from every black hole should keep the default single-step integration"
	)

func test_dominant_black_hole_handoffs_are_counted_when_anchor_changes() -> void:
	var world := SimWorld.new()

	var left_black_hole := _make_black_hole()
	left_black_hole.position = Vector2.ZERO
	world.add_body(left_black_hole)

	var right_black_hole := _make_black_hole()
	right_black_hole.position = Vector2(9000.0, 0.0)
	world.add_body(right_black_hole)

	var star := _make_dynamic_star()
	star.position = Vector2(2200.0, 0.0)
	world.add_body(star)

	world._rebuild_dominant_bh_cache()
	assert_eq(star.last_dominant_bh_id, left_black_hole.id, "initial dominant-anchor sampling should lock onto the nearer black hole")
	assert_eq(star.dominant_bh_handoff_count, 0, "the first dominant-anchor sample should not count as a handoff")

	star.position = Vector2(6800.0, 0.0)
	world._rebuild_dominant_bh_cache()

	assert_eq(star.last_dominant_bh_id, right_black_hole.id, "after crossing the balance region the other black hole should dominate")
	assert_eq(star.dominant_bh_handoff_count, 1, "switching dominant black holes should increment the persisted handoff counter")

func test_leapfrog_keeps_circular_star_orbit_stable() -> void:
	var world := SimWorld.new()

	var black_hole := _make_black_hole()
	world.add_body(black_hole)

	var star := _make_dynamic_star()
	var orbit_radius: float = 4.0 * SimConstants.AU
	star.position = Vector2(orbit_radius, 0.0)
	star.velocity = Vector2(0.0, sqrt(SimConstants.G * black_hole.mass / orbit_radius))
	world.add_body(star)

	var initial_energy: float = _specific_orbital_energy(star, black_hole)
	var max_radial_error: float = 0.0

	for _step in range(720):
		world.step_sim(SimConstants.FIXED_DT)
		var radius_error: float = absf(star.position.distance_to(black_hole.position) - orbit_radius)
		max_radial_error = maxf(max_radial_error, radius_error)

	var final_energy: float = _specific_orbital_energy(star, black_hole)

	assert_true(star.active, "stable circular orbits should stay active")
	assert_lt(max_radial_error, 80.0, "circular orbits should not inflate or collapse visibly over time")
	assert_almost_eq(
		final_energy,
		initial_energy,
		absf(initial_energy) * 0.03,
		"specific orbital energy should stay close to the initial circular-orbit value"
	)

func test_close_flyby_stays_dynamic_without_periapsis_snap() -> void:
	var world := SimWorld.new()

	var black_hole := _make_black_hole()
	world.add_body(black_hole)

	var star := _make_dynamic_star()
	star.position = Vector2(440.0, 0.0)
	star.velocity = Vector2(-1000.0, 2000.0)
	world.add_body(star)

	world.step_sim(SimConstants.FIXED_DT)

	var distance: float = star.position.distance_to(black_hole.position)
	var impact_radius: float = black_hole.radius + star.radius

	assert_true(star.active, "a close flyby outside the collision radius should remain active")
	assert_false(star.is_analytic_orbit_bound(), "close flybys should stay dynamic instead of being re-bound into an analytic capture state")
	assert_gt(distance, impact_radius, "the flyby should not be treated as a collision")
	assert_lt(distance, 426.0, "close passes should evolve naturally instead of snapping back to an artificial periapsis floor")
	assert_gt(star.velocity.length(), 500.0, "flyby velocity should remain dynamic instead of being clamped away")

func test_segment_black_hole_impact_catches_tunneling_star() -> void:
	var world := SimWorld.new()

	var black_hole := _make_black_hole()
	world.add_body(black_hole)

	var star := _make_dynamic_star()
	star.position = Vector2(200.0, 0.0)
	star.velocity = Vector2(-30_000.0, 0.0)
	world.add_body(star)

	world.step_sim(SimConstants.FIXED_DT)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE), 1, "the black hole should remain in the world")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 0, "segment-based BH impacts should remove tunneled stars")
	assert_eq(world.get_active_body_count(), 1, "only the black hole should remain active after the impact")

func test_sim_world_releases_when_last_reference_goes_away() -> void:
	var world := SimWorld.new()
	var world_ref: WeakRef = weakref(world)

	world = null

	assert_eq(world_ref.get_ref(), null, "SimWorld should not stay alive through an internal RefCounted cycle.")

func _make_black_hole() -> SimBody:
	var black_hole := SimBody.new()
	black_hole.active = true
	black_hole.body_type = SimBody.BodyType.BLACK_HOLE
	black_hole.influence_level = SimBody.InfluenceLevel.A
	black_hole.kinematic = true
	black_hole.mass = 12_000_000.0
	black_hole.radius = SimConstants.BLACK_HOLE_RADIUS
	return black_hole

func _make_dynamic_star() -> SimBody:
	var star := SimBody.new()
	star.active = true
	star.body_type = SimBody.BodyType.STAR
	star.influence_level = SimBody.InfluenceLevel.A
	star.kinematic = false
	star.mass = SimConstants.STAR_MASS
	star.radius = SimConstants.STAR_RADIUS
	return star

func _specific_orbital_energy(body: SimBody, black_hole: SimBody) -> float:
	var distance: float = body.position.distance_to(black_hole.position)
	return 0.5 * body.velocity.length_squared() - (SimConstants.G * black_hole.mass / distance)
