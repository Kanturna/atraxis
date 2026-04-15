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

func test_adaptive_substeps_do_not_double_advance_scripted_orbiters_per_frame() -> void:
	var world := SimWorld.new()

	var black_hole := _make_black_hole()
	world.add_body(black_hole)

	var star := _make_dynamic_star()
	star.position = Vector2(200.0, 0.0)
	star.velocity = Vector2(0.0, 900.0)
	world.add_body(star)

	var planet := SimBody.new()
	planet.active = true
	planet.body_type = SimBody.BodyType.PLANET
	planet.influence_level = SimBody.InfluenceLevel.B
	planet.material_type = SimBody.MaterialType.ROCKY
	planet.mass = SimConstants.PLANET_MASS_MIN
	planet.radius = SimConstants.PLANET_RADIUS_MIN
	planet.kinematic = true
	planet.scripted_orbit_enabled = true
	planet.orbit_binding_state = SimBody.OrbitBindingState.BOUND_ANALYTIC
	planet.orbit_parent_id = star.id
	planet.orbit_radius = 120.0
	planet.orbit_angle = 1.25
	planet.orbit_angular_speed = 0.5
	planet.position = star.position + Vector2(cos(planet.orbit_angle), sin(planet.orbit_angle)) * planet.orbit_radius
	world.add_body(planet)

	world._rebuild_dominant_bh_cache()
	var substeps: int = world._determine_black_hole_adaptive_substeps(SimConstants.FIXED_DT)
	assert_gt(substeps, 1, "the fixture should trigger adaptive BH substeps before measuring scripted orbit behavior")

	var initial_angle: float = planet.orbit_angle
	world.step_sim(SimConstants.FIXED_DT)

	assert_true(star.active, "the adaptive-substep fixture should keep the scripted planet's parent alive during the measured frame")
	assert_true(planet.active, "the scripted planet should still be active when verifying its per-frame orbit advancement")

	assert_almost_eq(
		planet.orbit_angle,
		wrapf(initial_angle + planet.orbit_angular_speed * SimConstants.FIXED_DT, 0.0, TAU),
		0.0001,
		"scripted orbiters should currently advance once per frame by sim_dt, not once per adaptive substep"
	)
	assert_almost_eq(
		planet.age,
		SimConstants.FIXED_DT,
		0.0001,
		"scripted orbiters should currently age once per frame even when adaptive substeps trigger elsewhere in the world"
	)

func test_sleep_timer_progress_matches_frame_dt_even_when_adaptive_substeps_trigger() -> void:
	var close_world := SimWorld.new()
	var close_black_hole := _make_black_hole()
	close_world.add_body(close_black_hole)

	var close_star := _make_dynamic_star()
	close_star.position = Vector2(200.0, 0.0)
	close_world.add_body(close_star)

	var close_fragment := SimBody.new()
	close_fragment.active = true
	close_fragment.body_type = SimBody.BodyType.FRAGMENT
	close_fragment.influence_level = SimBody.InfluenceLevel.C
	close_fragment.material_type = SimBody.MaterialType.ROCKY
	close_fragment.mass = 1.0
	close_fragment.radius = 2.0
	close_fragment.position = Vector2(50_000.0, 0.0)
	close_fragment.velocity = Vector2.ZERO
	close_world.add_body(close_fragment)

	close_world._rebuild_dominant_bh_cache()
	assert_gt(
		close_world._determine_black_hole_adaptive_substeps(SimConstants.FIXED_DT),
		1,
		"the close-world fixture should trigger adaptive substeps before measuring sleep timing"
	)

	var far_world := SimWorld.new()
	var far_black_hole := _make_black_hole()
	far_world.add_body(far_black_hole)

	var far_star := _make_dynamic_star()
	far_star.position = Vector2(20_000.0, 0.0)
	far_world.add_body(far_star)

	var far_fragment := SimBody.new()
	far_fragment.active = true
	far_fragment.body_type = SimBody.BodyType.FRAGMENT
	far_fragment.influence_level = SimBody.InfluenceLevel.C
	far_fragment.material_type = SimBody.MaterialType.ROCKY
	far_fragment.mass = 1.0
	far_fragment.radius = 2.0
	far_fragment.position = Vector2(50_000.0, 0.0)
	far_fragment.velocity = Vector2.ZERO
	far_world.add_body(far_fragment)

	far_world._rebuild_dominant_bh_cache()
	assert_eq(
		far_world._determine_black_hole_adaptive_substeps(SimConstants.FIXED_DT),
		1,
		"the far-world fixture should stay on the default single-step path"
	)

	close_world.step_sim(SimConstants.FIXED_DT)
	far_world.step_sim(SimConstants.FIXED_DT)

	assert_almost_eq(
		close_fragment.sleep_timer,
		SimConstants.FIXED_DT,
		0.0001,
		"sleep timer should currently accumulate only the frame dt even when adaptive substeps are active elsewhere"
	)
	assert_almost_eq(
		far_fragment.sleep_timer,
		SimConstants.FIXED_DT,
		0.0001,
		"single-step worlds should accumulate the same frame dt into sleep timers"
	)
	assert_false(close_fragment.sleeping, "one frame below the sleep threshold should not confirm sleep yet")
	assert_false(far_fragment.sleeping, "control world should match the close-world sleep confirmation behavior")
	assert_almost_eq(
		close_fragment.sleep_timer,
		far_fragment.sleep_timer,
		0.0001,
		"sleep timer progression should currently be invariant to the adaptive-substep count"
	)

func test_sleeping_body_near_black_hole_remains_asleep_under_current_rules() -> void:
	var world := SimWorld.new()

	var black_hole := _make_black_hole()
	world.add_body(black_hole)

	var asteroid := SimBody.new()
	asteroid.active = true
	asteroid.body_type = SimBody.BodyType.ASTEROID
	asteroid.influence_level = SimBody.InfluenceLevel.B
	asteroid.material_type = SimBody.MaterialType.ROCKY
	asteroid.mass = 8.0
	asteroid.radius = 3.0
	asteroid.position = Vector2(120.0, 0.0)
	asteroid.velocity = Vector2.ZERO
	asteroid.sleeping = true
	asteroid.sleep_timer = SimConstants.SLEEP_CONFIRM_TIME
	world.add_body(asteroid)

	var initial_position: Vector2 = asteroid.position
	var initial_velocity: Vector2 = asteroid.velocity
	world.step_sim(SimConstants.FIXED_DT)

	assert_true(asteroid.sleeping, "under the current rules a sleeping body near a strong source stays asleep without an explicit wake path")
	assert_true(
		asteroid.position.is_equal_approx(initial_position),
		"sleeping bodies currently skip integration even when they are close to a black hole"
	)
	assert_true(
		asteroid.velocity.is_equal_approx(initial_velocity),
		"sleeping bodies currently do not pick up new velocity from nearby black-hole gravity"
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

func test_dynamic_star_host_hysteresis_ignores_short_dominance_blips() -> void:
	var fixture: Dictionary = _make_dynamic_star_host_handoff_fixture()
	var world: SimWorld = fixture["world"]
	var left_black_hole: SimBody = fixture["left_black_hole"]
	var right_black_hole: SimBody = fixture["right_black_hole"]
	var star: SimBody = fixture["star"]

	star.position = Vector2(6500.0, 0.0)
	star.velocity = Vector2(0.0, 300.0)

	world._update_dynamic_star_host_assignments(0.25)

	assert_eq(star.pending_host_bh_id, right_black_hole.id, "a valid foreign dominant BH should become the pending host candidate")
	assert_eq(star.pending_host_time, 0.0, "a fresh pending candidate should start at zero observed stable time")
	assert_eq(star.orbit_parent_id, left_black_hole.id, "short dominance blips should not immediately reparent the star")

	world._update_dynamic_star_host_assignments(0.25)

	assert_almost_eq(star.pending_host_time, 0.25, 0.001, "later stable samples should accumulate the observed pending time")

	star.position = Vector2(2200.0, 0.0)

	world._update_dynamic_star_host_assignments(0.25)

	assert_eq(star.pending_host_bh_id, -1, "losing the foreign dominance signal should clear the pending candidate")
	assert_eq(star.pending_host_time, 0.0, "clearing the pending candidate should reset its timer")
	assert_eq(star.orbit_parent_id, left_black_hole.id, "short blips should leave the confirmed host untouched")
	assert_eq(star.confirmed_host_handoff_count, 0, "short blips should not count as confirmed host handoffs")
	assert_eq(star.orbit_binding_state, SimBody.OrbitBindingState.FREE_DYNAMIC, "host hysteresis should keep dynamic stars dynamic")

func test_dynamic_star_host_hysteresis_confirms_persistent_foreign_capture_signal() -> void:
	var fixture: Dictionary = _make_dynamic_star_host_handoff_fixture()
	var world: SimWorld = fixture["world"]
	var left_black_hole: SimBody = fixture["left_black_hole"]
	var right_black_hole: SimBody = fixture["right_black_hole"]
	var star: SimBody = fixture["star"]

	star.position = Vector2(6500.0, 0.0)
	star.velocity = Vector2(0.0, 300.0)

	world._update_dynamic_star_host_assignments(0.25)
	world._update_dynamic_star_host_assignments(0.25)
	world._update_dynamic_star_host_assignments(0.25)

	assert_eq(star.orbit_parent_id, left_black_hole.id, "the host should not switch before the hysteresis duration is fully observed")
	assert_eq(star.pending_host_bh_id, right_black_hole.id, "the same foreign host should remain pending while the signal stays stable")
	assert_almost_eq(star.pending_host_time, 0.5, 0.001, "pending time should reflect only the stable samples after the first pending frame")
	assert_eq(star.confirmed_host_handoff_count, 0, "the confirmed counter should stay flat before the threshold is met")

	world._update_dynamic_star_host_assignments(0.25)

	assert_eq(star.orbit_parent_id, right_black_hole.id, "persistent foreign dominance plus negative energy should confirm the host change")
	assert_eq(star.confirmed_host_handoff_count, 1, "confirmed host switches should increment their own counter")
	assert_eq(star.pending_host_bh_id, -1, "confirming a host switch should clear the pending candidate")
	assert_eq(star.pending_host_time, 0.0, "confirming a host switch should reset the pending timer")
	assert_eq(star.orbit_binding_state, SimBody.OrbitBindingState.FREE_DYNAMIC, "confirmed host changes should not convert the star into an analytic orbiter")

func test_analytic_orbiter_with_missing_parent_is_removed_instead_of_freezing() -> void:
	var world := SimWorld.new()

	var planet := SimBody.new()
	planet.active = true
	planet.body_type = SimBody.BodyType.PLANET
	planet.influence_level = SimBody.InfluenceLevel.B
	planet.material_type = SimBody.MaterialType.ROCKY
	planet.mass = SimConstants.PLANET_MASS_MIN
	planet.radius = SimConstants.PLANET_RADIUS_MIN
	planet.kinematic = true
	planet.scripted_orbit_enabled = true
	planet.orbit_binding_state = SimBody.OrbitBindingState.BOUND_ANALYTIC
	planet.orbit_parent_id = 42
	planet.orbit_radius = 60.0
	planet.orbit_angular_speed = 0.5
	world.add_body(planet)

	world.step_sim(SimConstants.FIXED_DT)

	assert_eq(
		world.count_bodies_by_type(SimBody.BodyType.PLANET),
		0,
		"analytic orbiters with missing parents should be removed instead of lingering in a frozen orphan state"
	)

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

func test_segment_black_hole_impact_prunes_star_children_in_same_tick() -> void:
	var world := SimWorld.new()

	var black_hole := _make_black_hole()
	world.add_body(black_hole)

	var star := _make_dynamic_star()
	star.position = Vector2(200.0, 0.0)
	star.velocity = Vector2(-30_000.0, 0.0)
	world.add_body(star)

	var planet := SimBody.new()
	planet.active = true
	planet.body_type = SimBody.BodyType.PLANET
	planet.influence_level = SimBody.InfluenceLevel.B
	planet.material_type = SimBody.MaterialType.ROCKY
	planet.mass = SimConstants.PLANET_MASS_MIN
	planet.radius = SimConstants.PLANET_RADIUS_MIN
	planet.kinematic = true
	planet.scripted_orbit_enabled = true
	planet.orbit_binding_state = SimBody.OrbitBindingState.BOUND_ANALYTIC
	planet.orbit_parent_id = star.id
	planet.orbit_radius = 60.0
	planet.orbit_angle = 0.0
	planet.orbit_angular_speed = 0.5
	planet.position = star.position + Vector2(60.0, 0.0)
	world.add_body(planet)

	world.step_sim(SimConstants.FIXED_DT)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE), 1, "the black hole should remain active after the impact")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 0, "the tunneled star should still be removed")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 0, "analytic children of the removed star should be pruned immediately instead of lingering for one tick")
	assert_eq(world.get_active_body_count(), 1, "no orphaned child should remain after the parent star dies")

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

func _make_dynamic_star_host_handoff_fixture() -> Dictionary:
	var world := SimWorld.new()

	var left_black_hole := _make_black_hole()
	left_black_hole.position = Vector2.ZERO
	world.add_body(left_black_hole)

	var right_black_hole := _make_black_hole()
	right_black_hole.position = Vector2(9000.0, 0.0)
	world.add_body(right_black_hole)

	var star := _make_dynamic_star()
	star.position = Vector2(2200.0, 0.0)
	star.velocity = Vector2(0.0, 300.0)
	star.orbit_parent_id = left_black_hole.id
	world.add_body(star)

	return {
		"world": world,
		"left_black_hole": left_black_hole,
		"right_black_hole": right_black_hole,
		"star": star,
	}

func _specific_orbital_energy(body: SimBody, black_hole: SimBody) -> float:
	var distance: float = body.position.distance_to(black_hole.position)
	return 0.5 * body.velocity.length_squared() - (SimConstants.G * black_hole.mass / distance)
