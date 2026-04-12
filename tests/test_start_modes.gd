extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const GALAXY_BUILDER_SCRIPT := preload("res://simulation/galaxy_builder.gd")

func test_default_config_starts_on_the_public_main_universe_path() -> void:
	var config = START_CONFIG_SCRIPT.new()

	assert_eq(
		config.anchor_topology,
		START_CONFIG_SCRIPT.AnchorTopology.CENTRAL_BH,
		"the public bootstrap should start on the canonical central-anchor universe path"
	)

func test_public_builder_ignores_internal_fixture_profile_selection() -> void:
	var sandbox_config = START_CONFIG_SCRIPT.new()
	sandbox_config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	sandbox_config.black_hole_count = 6
	sandbox_config.star_count = 2
	sandbox_config.planets_per_star = 1
	sandbox_config.disturbance_body_count = 2

	var reference_config = sandbox_config.copy()
	reference_config.world_profile = START_CONFIG_SCRIPT.WorldProfile.ORBITAL_REFERENCE

	var inflow_config = sandbox_config.copy()
	inflow_config.world_profile = START_CONFIG_SCRIPT.WorldProfile.INFLOW_LAB
	inflow_config.chaos_body_count = 5

	var sandbox_world := SimWorld.new()
	var reference_world := SimWorld.new()
	var inflow_world := SimWorld.new()
	WorldBuilder.build_from_config(sandbox_world, sandbox_config)
	WorldBuilder.build_from_config(reference_world, reference_config)
	WorldBuilder.build_from_config(inflow_world, inflow_config)

	assert_eq(
		sandbox_world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE),
		reference_world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE),
		"public startup should ignore internal reference fixtures and keep the same universe path"
	)
	assert_eq(
		sandbox_world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE),
		inflow_world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE),
		"public startup should ignore internal inflow fixtures and keep the same universe path"
	)
	assert_eq(
		_sorted_positions_by_type(sandbox_world, SimBody.BodyType.BLACK_HOLE),
		_sorted_positions_by_type(reference_world, SimBody.BodyType.BLACK_HOLE),
		"reference fixture flags must not alter the public world layout"
	)
	assert_eq(
		_sorted_positions_by_type(sandbox_world, SimBody.BodyType.BLACK_HOLE),
		_sorted_positions_by_type(inflow_world, SimBody.BodyType.BLACK_HOLE),
		"inflow fixture flags must not alter the public world layout"
	)

func test_internal_fixture_builder_can_still_materialize_reference_carriers() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.world_profile = START_CONFIG_SCRIPT.WorldProfile.ORBITAL_REFERENCE
	config.star_count = 2
	config.planets_per_star = 2
	config.disturbance_body_count = 3

	var galaxy_state: GalaxyState = GALAXY_BUILDER_SCRIPT.build_fixture_from_config(config)
	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state)
	var world: SimWorld = session.sim_world

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE), 1, "internal reference fixture should keep one black hole")
	for body in world.bodies:
		if body.body_type == SimBody.BodyType.STAR:
			assert_true(body.kinematic, "internal reference fixture stars should remain analytic carriers")
			assert_true(body.is_analytic_orbit_bound(), "internal reference fixture stars should stay analytically bound")

func test_internal_fixture_builder_can_still_materialize_inflow_lab() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.world_profile = START_CONFIG_SCRIPT.WorldProfile.INFLOW_LAB
	config.chaos_body_count = 4
	config.seed = 42

	var galaxy_state: GalaxyState = GALAXY_BUILDER_SCRIPT.build_fixture_from_config(config)
	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state)
	var world: SimWorld = session.sim_world

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE), 0, "internal inflow lab fixture should stay black-hole free")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), 1, "internal inflow lab fixture should still create one central star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), 4, "internal inflow lab fixture should create the configured inflow body count")

func test_public_field_patch_builds_central_and_outer_black_holes() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
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

func test_public_field_patch_remains_stable_for_initial_steps() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	config.black_hole_count = 5
	config.star_count = 1
	config.planets_per_star = 1
	config.disturbance_body_count = 0
	config.black_hole_mass = 12_000_000.0
	config.field_spacing_au = 9.0
	config.seed = 42

	WorldBuilder.build_from_config(world, config)

	var star: SimBody = world.get_star()
	var initial_speed: float = star.velocity.length()
	for _step in range(240):
		world.step_sim(SimConstants.FIXED_DT)

	var nearest_black_hole_distance: float = INF
	for black_hole in world.get_black_holes():
		nearest_black_hole_distance = minf(
			nearest_black_hole_distance,
			star.position.distance_to(black_hole.position)
		)

	assert_true(star.active, "field-patch startup stars should survive the initial multi-BH evolution")
	assert_lt(
		star.velocity.length(),
		initial_speed * 5.0,
		"field-patch startup should not explode into runaway velocity during the first seconds"
	)
	assert_gt(
		nearest_black_hole_distance,
		SimConstants.BLACK_HOLE_RADIUS + SimConstants.STAR_RADIUS,
		"field-patch startup stars should stay outside direct BH impact in the initial smoke test"
	)

func _sorted_positions_by_type(world: SimWorld, body_type: int) -> Array:
	var positions: Array = []
	for body in world.bodies:
		if body.active and body.body_type == body_type:
			positions.append(body.position)
	positions.sort_custom(func(a, b):
		if not is_equal_approx(a.x, b.x):
			return a.x < b.x
		return a.y < b.y
	)
	return positions
