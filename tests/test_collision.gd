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
	bound_planet.orbit_radius = 60.0
	bound_planet.orbit_angle = 0.0
	bound_planet.orbit_angular_speed = 0.5
	bound_planet.position = lighter_star.position + Vector2(60.0, 0.0)
	world.add_body(bound_planet)

	world.step_sim(0.0)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 1, "star-star overlaps should now resolve to exactly one surviving star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 0, "analytic children of the removed star should be pruned in the same tick")
	assert_eq(world.get_star().id, heavy_star.id, "the more massive star should survive the deterministic star-star collision rule")
	assert_almost_eq(
		world.get_star().mass,
		SimConstants.STAR_MASS * 2.0,
		0.001,
		"the surviving star should absorb the removed star's mass"
	)
	assert_eq(world.get_active_debris_count(), 1, "star-star collisions should still leave a debris trace for diagnostics")
