extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const GALAXY_BUILDER_SCRIPT := preload("res://simulation/galaxy_builder.gd")

func test_default_config_starts_on_the_public_main_universe_path() -> void:
	var config = START_CONFIG_SCRIPT.new()

	assert_eq(
		config.anchor_topology,
		START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER,
		"the public bootstrap should start on the canonical universe path"
	)

func test_public_generation_config_clamps_worldgen_parameters_into_supported_ranges() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.sector_scale = 999_999_999.0
	config.cluster_density = 99.0
	config.void_strength = -10.0
	config.bh_richness = 99.0
	config.star_richness = -5.0
	config.rare_zone_frequency = 99.0
	config.clamp_values()

	assert_eq(config.sector_scale, SimConstants.MAX_WORLDGEN_SECTOR_SCALE, "sector scale should clamp to the supported public worldgen maximum")
	assert_eq(config.cluster_density, SimConstants.MAX_WORLDGEN_NORMALIZED_PARAM, "cluster density should clamp to the normalized public worldgen range")
	assert_eq(config.void_strength, 0.0, "void strength should clamp to the normalized public worldgen range")
	assert_eq(config.bh_richness, SimConstants.MAX_WORLDGEN_NORMALIZED_PARAM, "BH richness should clamp to the normalized public worldgen range")
	assert_eq(config.star_richness, 0.0, "star richness should clamp to the normalized public worldgen range")
	assert_eq(config.rare_zone_frequency, SimConstants.MAX_WORLDGEN_NORMALIZED_PARAM, "rare-zone frequency should clamp to the normalized public worldgen range")

func test_public_builder_ignores_internal_fixture_profile_selection() -> void:
	var sandbox_config = START_CONFIG_SCRIPT.new()
	sandbox_config.seed = 91
	sandbox_config.cluster_density = 0.72
	sandbox_config.void_strength = 0.18
	sandbox_config.bh_richness = 0.61
	sandbox_config.star_richness = 0.57
	sandbox_config.rare_zone_frequency = 0.28

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

func test_public_worldgen_builder_materializes_active_cluster_from_derived_profile() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 133
	config.cluster_density = 0.80
	config.void_strength = 0.18
	config.bh_richness = 0.74
	config.star_richness = 0.70
	config.rare_zone_frequency = 0.30

	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_config(config)
	var world: SimWorld = session.sim_world
	var active_cluster: ClusterState = session.active_cluster_state

	assert_eq(
		active_cluster.simulation_profile.get("topology_role", ""),
		"sector_worldgen_cluster",
		"public startup should materialize the canonical sector-worldgen cluster path"
	)
	assert_eq(
		world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE),
		active_cluster.get_objects_by_kind("black_hole").size(),
		"public startup should materialize exactly the active cluster's registered BH count"
	)
	assert_eq(
		world.count_bodies_by_type(SimBody.BodyType.STAR),
		int(active_cluster.simulation_profile.get("star_count", 0)),
		"public startup should materialize the cluster's derived star richness"
	)
	assert_eq(
		world.count_bodies_by_type(SimBody.BodyType.PLANET),
		int(active_cluster.simulation_profile.get("star_count", 0))
			* int(active_cluster.simulation_profile.get("planets_per_star", 0)),
		"public startup should materialize the derived planet count from the active cluster profile"
	)
	assert_eq(
		world.count_bodies_by_type(SimBody.BodyType.ASTEROID),
		int(active_cluster.simulation_profile.get("disturbance_body_count", 0)),
		"public startup should materialize the derived disturbance count from the active cluster profile"
	)

func test_public_worldgen_startup_remains_stable_for_initial_steps() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 42
	config.cluster_density = 0.78
	config.void_strength = 0.20
	config.bh_richness = 0.60
	config.star_richness = 0.52
	config.rare_zone_frequency = 0.22
	config.black_hole_mass = 12_000_000.0

	WorldBuilder.build_from_config(world, config)

	var star: SimBody = world.get_star()
	assert_not_null(star, "worldgen startup smoke test needs at least one star in the active cluster")
	var initial_speed: float = star.velocity.length()
	for _step in range(240):
		world.step_sim(SimConstants.FIXED_DT)

	var nearest_black_hole_distance: float = INF
	for black_hole in world.get_black_holes():
		nearest_black_hole_distance = minf(
			nearest_black_hole_distance,
			star.position.distance_to(black_hole.position)
		)

	assert_true(star.active, "worldgen startup stars should survive the initial local evolution")
	assert_lt(
		star.velocity.length(),
		initial_speed * 5.0,
		"worldgen startup should not explode into runaway velocity during the first seconds"
	)
	assert_gt(
		nearest_black_hole_distance,
		SimConstants.BLACK_HOLE_RADIUS + SimConstants.STAR_RADIUS,
		"worldgen startup stars should stay outside direct BH impact in the initial smoke test"
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
