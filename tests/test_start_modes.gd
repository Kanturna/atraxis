extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")

func test_default_config_prefers_dynamic_anchor() -> void:
	var config = START_CONFIG_SCRIPT.new()
	assert_eq(config.mode, START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR, "dynamic anchor should be the default main mode")
	assert_eq(config.anchor_topology, START_CONFIG_SCRIPT.AnchorTopology.CENTRAL_BH, "dynamic anchor should default to the existing central-BH topology")

func test_dynamic_anchor_builds_macro_topology_with_dynamic_stars() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.star_count = 2
	config.planets_per_star = 2
	config.disturbance_body_count = 3
	config.black_hole_mass = 12_000_000.0
	config.seed = 42

	WorldBuilder.build_from_config(world, config)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE), 1, "dynamic anchor should build one black hole")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 2, "dynamic anchor should build the configured stars")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 4, "dynamic anchor should build planets per star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.ASTEROID), 3, "dynamic anchor should build the configured disturbance bodies")

	for body in world.bodies:
		if body.body_type == SimBody.BodyType.STAR:
			assert_false(body.kinematic, "dynamic anchor stars should be free-dynamic")
			assert_eq(body.orbit_binding_state, SimBody.OrbitBindingState.FREE_DYNAMIC, "dynamic anchor stars should start free")
		elif body.body_type == SimBody.BodyType.PLANET:
			assert_true(body.is_analytic_orbit_bound(), "dynamic anchor planets should remain analytic carriers")

func test_stable_anchor_builds_same_topology_with_analytic_stars() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.STABLE_ANCHOR
	config.star_count = 2
	config.planets_per_star = 2
	config.disturbance_body_count = 3
	config.black_hole_mass = 12_000_000.0
	config.seed = 42

	WorldBuilder.build_from_config(world, config)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE), 1, "stable anchor should build one black hole")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 2, "stable anchor should build the configured stars")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 4, "stable anchor should build planets per star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.ASTEROID), 3, "stable anchor should build the configured disturbance bodies")

	for body in world.bodies:
		if body.body_type == SimBody.BodyType.STAR:
			assert_true(body.kinematic, "stable anchor stars should remain analytic carriers")
			assert_true(body.is_analytic_orbit_bound(), "stable anchor stars should stay analytically bound to the black hole")
		elif body.body_type == SimBody.BodyType.PLANET:
			assert_true(body.is_analytic_orbit_bound(), "stable anchor planets should remain analytic carriers")

func test_chaos_mode_creates_dynamic_inflow_bodies_without_black_hole() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW
	config.chaos_body_count = 4
	config.seed = 42

	WorldBuilder.build_from_config(world, config)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE), 0, "chaos inflow should stay separate from anchor modes")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 1, "chaos inflow should still create one central star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 4, "chaos inflow should create the configured inflow body count")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.ASTEROID), 0, "chaos inflow should not mix in anchor disturbance asteroids")

func test_dynamic_anchor_field_patch_builds_central_and_outer_black_holes() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	config.black_hole_count = 6
	config.star_count = 2
	config.planets_per_star = 1
	config.disturbance_body_count = 2
	config.field_spacing_au = 9.0

	WorldBuilder.build_from_config(world, config)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE), 6, "field patch should build the configured total black-hole count")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 2, "field patch should still build the configured stars")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 2, "field patch should keep the configured planets per star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.ASTEROID), 2, "field patch should keep the configured disturbance count")
