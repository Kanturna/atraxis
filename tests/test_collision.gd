extends GutTest

func test_broadphase_detects_star_overlap_before_grid_neighbors() -> void:
	var star := SimBody.new()
	star.id = 1
	star.active = true
	star.body_type = SimBody.BodyType.STAR
	star.radius = SimConstants.STAR_RADIUS
	star.position = Vector2.ZERO

	var impactor := SimBody.new()
	impactor.id = 2
	impactor.active = true
	impactor.body_type = SimBody.BodyType.ASTEROID
	impactor.radius = 2.0
	impactor.position = Vector2(SimConstants.STAR_RADIUS - 1.0, 0.0)

	var pairs: Array = CollisionDetector.new().broadphase([star, impactor])

	assert_eq(pairs.size(), 1, "star overlap should always produce a broadphase pair")
	assert_true(
		(pairs[0][0].id == star.id and pairs[0][1].id == impactor.id)
		or (pairs[0][1].id == star.id and pairs[0][0].id == impactor.id),
		"the detected pair should be star vs impactor"
	)

func test_star_impact_removes_impactor_and_spawns_debris() -> void:
	var world := SimWorld.new()

	var star := SimBody.new()
	star.body_type = SimBody.BodyType.STAR
	star.influence_level = SimBody.InfluenceLevel.A
	star.kinematic = true
	star.active = true
	star.mass = SimConstants.STAR_MASS
	star.radius = SimConstants.STAR_RADIUS
	star.position = Vector2.ZERO
	world.add_body(star)

	var impactor := SimBody.new()
	impactor.body_type = SimBody.BodyType.ASTEROID
	impactor.influence_level = SimBody.InfluenceLevel.B
	impactor.kinematic = false
	impactor.active = true
	impactor.mass = 20.0
	impactor.radius = 2.0
	impactor.position = Vector2(SimConstants.STAR_RADIUS - 1.0, 0.0)
	world.add_body(impactor)

	world.step_sim(0.0)

	assert_eq(world.get_active_body_count(), 1, "impactor should be removed after star collision")
	assert_eq(world.get_active_debris_count(), 1, "star collision should create a debris field")
	assert_almost_eq(
		world.debris_fields[0].total_mass,
		impactor.mass * CollisionResolver.STAR_IMPACT_DEBRIS_FRACTION,
		0.001,
		"star collision should use the fixed debris fraction"
	)

func test_star_star_collision_keeps_one_deterministic_survivor_and_prunes_removed_star_children() -> void:
	var world := SimWorld.new()

	var heavy_star := SimBody.new()
	heavy_star.body_type = SimBody.BodyType.STAR
	heavy_star.influence_level = SimBody.InfluenceLevel.A
	heavy_star.material_type = SimBody.MaterialType.STELLAR
	heavy_star.kinematic = false
	heavy_star.active = true
	heavy_star.mass = SimConstants.STAR_MASS * 1.2
	heavy_star.radius = SimConstants.STAR_RADIUS
	heavy_star.position = Vector2.ZERO
	heavy_star.velocity = Vector2(20.0, 0.0)
	world.add_body(heavy_star)
	var initial_heavy_mass: float = heavy_star.mass

	var lighter_star := SimBody.new()
	lighter_star.body_type = SimBody.BodyType.STAR
	lighter_star.influence_level = SimBody.InfluenceLevel.A
	lighter_star.material_type = SimBody.MaterialType.STELLAR
	lighter_star.kinematic = false
	lighter_star.active = true
	lighter_star.mass = SimConstants.STAR_MASS * 0.8
	lighter_star.radius = SimConstants.STAR_RADIUS
	lighter_star.position = Vector2(SimConstants.STAR_RADIUS * 0.5, 0.0)
	lighter_star.velocity = Vector2(-40.0, 0.0)
	world.add_body(lighter_star)
	var initial_removed_mass: float = lighter_star.mass

	var bound_planet := SimBody.new()
	bound_planet.body_type = SimBody.BodyType.PLANET
	bound_planet.influence_level = SimBody.InfluenceLevel.B
	bound_planet.material_type = SimBody.MaterialType.ROCKY
	bound_planet.kinematic = true
	bound_planet.active = true
	bound_planet.mass = SimConstants.PLANET_MASS_MIN
	bound_planet.radius = SimConstants.PLANET_RADIUS_MIN
	bound_planet.scripted_orbit_enabled = true
	bound_planet.orbit_binding_state = SimBody.OrbitBindingState.BOUND_ANALYTIC
	bound_planet.orbit_parent_id = lighter_star.id
	bound_planet.orbit_radius = 220.0
	bound_planet.orbit_angle = 0.0
	bound_planet.orbit_angular_speed = 0.5
	bound_planet.position = lighter_star.position + Vector2(220.0, 0.0)
	world.add_body(bound_planet)

	world.step_sim(0.0)

	var expected_debris_mass: float = initial_removed_mass * CollisionResolver.STAR_IMPACT_DEBRIS_FRACTION
	var expected_survivor_mass: float = initial_heavy_mass + initial_removed_mass - expected_debris_mass
	var expected_survivor_radius: float = SimConstants.STAR_RADIUS * sqrt(
		expected_survivor_mass / SimConstants.STAR_MASS
	)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 1, "star-star overlaps should now resolve to exactly one surviving star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 0, "analytic children of the removed star should be pruned in the same tick")
	assert_eq(world.get_star().id, heavy_star.id, "the more massive star should survive the deterministic star-star collision rule")
	assert_almost_eq(
		world.get_star().mass,
		expected_survivor_mass,
		0.001,
		"the surviving star should only retain the removed star mass that is not converted into debris"
	)
	assert_eq(world.get_active_debris_count(), 1, "star-star collisions should still leave a debris trace for diagnostics")
	assert_almost_eq(
		world.debris_fields[0].total_mass,
		expected_debris_mass,
		0.001,
		"star-star debris should match the configured stripped mass fraction"
	)
	assert_almost_eq(
		world.get_star().radius,
		expected_survivor_radius,
		0.001,
		"the surviving star radius should be recalculated from its new mass"
	)

func test_broadphase_pair_keys_do_not_alias_for_large_body_ids() -> void:
	var body_a := SimBody.new()
	body_a.id = 1
	body_a.active = true
	body_a.body_type = SimBody.BodyType.ASTEROID
	body_a.radius = 2.0
	body_a.position = Vector2.ZERO

	var body_b := SimBody.new()
	body_b.id = 100005
	body_b.active = true
	body_b.body_type = SimBody.BodyType.ASTEROID
	body_b.radius = 2.0
	body_b.position = Vector2(3.0, 0.0)

	var body_c := SimBody.new()
	body_c.id = 2
	body_c.active = true
	body_c.body_type = SimBody.BodyType.ASTEROID
	body_c.radius = 2.0
	body_c.position = Vector2(100.0, 0.0)

	var body_d := SimBody.new()
	body_d.id = 5
	body_d.active = true
	body_d.body_type = SimBody.BodyType.ASTEROID
	body_d.radius = 2.0
	body_d.position = Vector2(103.0, 0.0)

	var pairs: Array = CollisionDetector.new().broadphase([body_a, body_b, body_c, body_d])
	var pair_ids: Array = []
	for pair in pairs:
		var ids := [pair[0].id, pair[1].id]
		ids.sort()
		pair_ids.append(ids)

	assert_eq(pairs.size(), 2, "distinct overlapping pairs with alias-prone ids should both survive broadphase deduplication")
	assert_has(pair_ids, [1, 100005], "the first overlapping pair should be preserved")
	assert_has(pair_ids, [2, 5], "the second overlapping pair should be preserved")
