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
