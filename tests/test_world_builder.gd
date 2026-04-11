extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")

func test_world_builder_creates_stable_anchor_reference_layout() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.STABLE_ANCHOR
	config.star_count = 2
	config.planets_per_star = 2
	config.disturbance_body_count = 3

	WorldBuilder.build_from_config(world, config)

	assert_eq(world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE), 1, "stable anchor should create one black hole")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.STAR), config.star_count, "stable anchor should create the configured stars")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.PLANET), config.star_count * config.planets_per_star, "stable anchor should create planets for each star")
	assert_eq(world.count_bodies_by_type(SimBody.BodyType.ASTEROID), config.disturbance_body_count, "stable anchor should create the configured disturbance bodies")

	for body in world.bodies:
		if body.body_type == SimBody.BodyType.STAR:
			assert_true(body.kinematic, "stable anchor stars should remain analytic carriers")
			assert_true(body.scripted_orbit_enabled, "stable anchor stars should use analytic orbiting")
		elif body.body_type == SimBody.BodyType.PLANET:
			assert_true(body.kinematic, "stable anchor core planets remain kinematic")
			assert_true(body.scripted_orbit_enabled, "stable anchor core planets should use analytic orbiting")
			assert_eq(body.orbit_binding_state, SimBody.OrbitBindingState.BOUND_ANALYTIC, "core planets should advertise their bound state")
			assert_gt(body.orbit_radius, 0.0, "planet should have a configured orbit radius")
			assert_gt(body.orbit_angular_speed, 0.0, "planet should have a configured orbit speed")

func test_bound_core_planet_advances_with_moving_parent() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.STABLE_ANCHOR

	WorldBuilder.build_from_config(world, config)
	var star: SimBody = world.get_star()
	var planet: SimBody = null
	for body in world.bodies:
		if body.body_type == SimBody.BodyType.PLANET:
			planet = body
			break

	assert_not_null(planet, "world builder should create at least one core planet")

	var old_planet_position: Vector2 = planet.position
	var old_star_position: Vector2 = star.position
	var orbit_radius: float = planet.orbit_radius
	world.step_sim(SimConstants.FIXED_DT)

	assert_false(star.position.is_equal_approx(old_star_position), "moving sun should advance each tick")
	assert_false(planet.position.is_equal_approx(old_planet_position), "bound core planets should visibly advance each tick")
	assert_almost_eq(
		planet.position.distance_to(star.position),
		orbit_radius,
		0.01,
		"bound core planets should stay on their configured parent-relative orbit radius"
	)

func test_live_black_hole_mass_updates_analytic_star_carrier_speed() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.STABLE_ANCHOR

	WorldBuilder.build_from_config(world, config)
	var star: SimBody = world.get_star()
	var old_speed: float = star.orbit_angular_speed

	world.set_black_hole_mass(config.black_hole_mass * 1.5)

	assert_gt(star.orbit_angular_speed, old_speed, "raising BH mass should immediately strengthen analytic star carrier speed")

func test_field_patch_layout_keeps_central_bh_at_origin_and_outer_ring_spaced() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	config.black_hole_count = 7
	config.field_spacing_au = 9.0

	WorldBuilder.build_from_config(world, config)
	var black_holes: Array = world.get_black_holes()

	assert_eq(black_holes.size(), 7, "field patch should create the configured total BH count")

	var central_count: int = 0
	var ring_one_count: int = 0
	for black_hole in black_holes:
		var distance: float = black_hole.position.length()
		if is_zero_approx(distance):
			central_count += 1
		else:
			if is_equal_approx(distance, config.field_spacing_au * SimConstants.AU):
				ring_one_count += 1

	assert_eq(central_count, 1, "field patch should keep exactly one black hole at the center")
	assert_eq(ring_one_count, 6, "with 7 total black holes the first outer ring should fill all 6 slots")

func test_field_patch_accepts_single_black_hole_count_as_center_only() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	config.black_hole_count = 1

	WorldBuilder.build_from_config(world, config)

	assert_eq(world.get_black_holes().size(), 1, "field patch with one BH should remain a valid center-only layout")
	assert_true(is_zero_approx(world.get_black_hole().position.length()), "the single field-patch BH should stay at the center")

func test_live_black_hole_mass_updates_every_field_patch_anchor() -> void:
	var world := SimWorld.new()
	var config = START_CONFIG_SCRIPT.new()
	config.mode = START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH

	WorldBuilder.build_from_config(world, config)
	world.set_black_hole_mass(config.black_hole_mass * 1.25)

	for black_hole in world.get_black_holes():
		assert_almost_eq(black_hole.mass, config.black_hole_mass * 1.25, 0.001, "live BH mass changes should affect all anchors in the field patch")
