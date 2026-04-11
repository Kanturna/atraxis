extends GutTest

const DEBUG_METRICS_SCRIPT := preload("res://debug/debug_metrics.gd")

func test_scripted_planet_metrics_report_orbit_deviation() -> void:
	var world := SimWorld.new()
	var planet := SimBody.new()
	planet.active = true
	planet.body_type = SimBody.BodyType.PLANET
	planet.kinematic = true
	planet.scripted_orbit_enabled = true
	planet.orbit_binding_state = SimBody.OrbitBindingState.BOUND_ANALYTIC
	planet.orbit_center = Vector2.ZERO
	planet.orbit_radius = 100.0
	planet.orbit_angular_speed = 0.5
	planet.position = Vector2(102.0, 0.0)
	planet.velocity = Vector2(53.0, 0.0)
	world.add_body(planet)

	var snapshot: Dictionary = DEBUG_METRICS_SCRIPT.new().build_snapshot(world, 0)
	var orbit: Dictionary = snapshot["orbit"]

	assert_eq(orbit["analytic_planets"], 1, "analytic planet should be counted")
	assert_almost_eq(orbit["average_radial_deviation"], 2.0, 0.001, "average radial deviation should match the configured offset")
	assert_almost_eq(orbit["max_radial_deviation"], 2.0, 0.001, "max radial deviation should match the configured offset")
	assert_almost_eq(orbit["average_speed_deviation"], 3.0, 0.001, "average speed deviation should match the configured offset")

func test_chaos_score_uses_fixed_phase1_formula() -> void:
	var world := SimWorld.new()

	for i in range(4):
		var body := SimBody.new()
		body.active = true
		body.body_type = SimBody.BodyType.ASTEROID
		body.kinematic = false
		body.sleeping = (i == 0)
		world.add_body(body)

	for _i in range(15):
		var fragment := SimBody.new()
		fragment.active = true
		fragment.body_type = SimBody.BodyType.FRAGMENT
		fragment.kinematic = false
		world.add_body(fragment)

	for i in range(3):
		var field := DebrisField.new()
		field.active = true
		field.id = i
		world.debris_fields.append(field)

	var snapshot: Dictionary = DEBUG_METRICS_SCRIPT.new().build_snapshot(world, 4)
	var chaos: Dictionary = snapshot["chaos"]

	assert_almost_eq(chaos["collision_pressure"], 0.5, 0.001, "collision pressure should clamp from the rolling count")
	assert_almost_eq(chaos["fragment_pressure"], 0.5, 0.001, "fragment pressure should use the global fragment cap")
	assert_almost_eq(chaos["debris_pressure"], 0.2, 0.001, "debris pressure should use the global debris cap")
	assert_almost_eq(chaos["awake_dynamic_ratio"], 18.0 / 19.0, 0.001, "awake dynamic ratio should only consider dynamic bodies")
	assert_almost_eq(chaos["awake_unrest"], (18.0 / 19.0) * 0.5, 0.001, "awake unrest should only amplify score while the sim is otherwise active")
	assert_eq(chaos["score"], 43, "chaos score should stay calmer in otherwise stable scenes")

func test_calm_but_awake_world_stays_near_zero_chaos() -> void:
	var world := SimWorld.new()

	for _i in range(3):
		var body := SimBody.new()
		body.active = true
		body.body_type = SimBody.BodyType.ASTEROID
		body.kinematic = false
		world.add_body(body)

	var snapshot: Dictionary = DEBUG_METRICS_SCRIPT.new().build_snapshot(world, 0)
	var chaos: Dictionary = snapshot["chaos"]

	assert_almost_eq(chaos["awake_dynamic_ratio"], 1.0, 0.001, "awake ratio can still be 1.0 in a calm world")
	assert_almost_eq(chaos["awake_unrest"], 0.0, 0.001, "awake bodies alone should not imply chaos")
	assert_eq(chaos["score"], 0, "a calm startup state should not begin with built-in chaos")

func test_empty_world_metrics_are_stable() -> void:
	var snapshot: Dictionary = DEBUG_METRICS_SCRIPT.new().build_snapshot(SimWorld.new(), 0)
	var sim_stats: Dictionary = snapshot["simulation"]
	var orbit: Dictionary = snapshot["orbit"]
	var chaos: Dictionary = snapshot["chaos"]

	assert_eq(sim_stats["active_bodies"], 0, "empty worlds should report zero active bodies")
	assert_eq(sim_stats["dynamic_bodies"], 0, "empty worlds should report zero dynamic bodies")
	assert_eq(sim_stats["sleeping_bodies"], 0, "empty worlds should report zero sleeping bodies")
	assert_eq(sim_stats["fragment_count"], 0, "empty worlds should report zero fragments")
	assert_eq(sim_stats["debris_count"], 0, "empty worlds should report zero debris")
	assert_eq(orbit["analytic_planets"], 0, "empty worlds should report zero analytic planets")
	assert_almost_eq(orbit["average_radial_deviation"], 0.0, 0.001, "empty worlds should not divide by zero for radial deviation")
	assert_almost_eq(orbit["average_speed_deviation"], 0.0, 0.001, "empty worlds should not divide by zero for speed deviation")
	assert_almost_eq(chaos["awake_dynamic_ratio"], 0.0, 0.001, "empty worlds should not divide by zero for awake ratio")
	assert_eq(chaos["score"], 0, "empty worlds should have a zero chaos score")

func test_simulation_counts_include_sleeping_fragments_and_debris() -> void:
	var world := SimWorld.new()

	var sleeping_asteroid := SimBody.new()
	sleeping_asteroid.active = true
	sleeping_asteroid.body_type = SimBody.BodyType.ASTEROID
	sleeping_asteroid.kinematic = false
	sleeping_asteroid.sleeping = true
	world.add_body(sleeping_asteroid)

	var awake_fragment := SimBody.new()
	awake_fragment.active = true
	awake_fragment.body_type = SimBody.BodyType.FRAGMENT
	awake_fragment.kinematic = false
	world.add_body(awake_fragment)

	var inactive_body := SimBody.new()
	inactive_body.active = false
	inactive_body.body_type = SimBody.BodyType.ASTEROID
	inactive_body.kinematic = false
	world.add_body(inactive_body)

	var active_field := DebrisField.new()
	active_field.active = true
	world.debris_fields.append(active_field)

	var inactive_field := DebrisField.new()
	inactive_field.active = false
	world.debris_fields.append(inactive_field)

	var snapshot: Dictionary = DEBUG_METRICS_SCRIPT.new().build_snapshot(world, 0)
	var sim_stats: Dictionary = snapshot["simulation"]
	var chaos: Dictionary = snapshot["chaos"]

	assert_eq(sim_stats["active_bodies"], 2, "inactive bodies should not be counted")
	assert_eq(sim_stats["dynamic_bodies"], 2, "dynamic body count should include non-kinematic active bodies")
	assert_eq(sim_stats["sleeping_bodies"], 1, "sleeping count should include active sleeping bodies")
	assert_eq(sim_stats["awake_dynamic_bodies"], 1, "awake dynamic count should exclude sleeping bodies")
	assert_eq(sim_stats["fragment_count"], 1, "fragment count should include active fragments")
	assert_eq(sim_stats["debris_count"], 1, "debris count should ignore inactive debris fields")
	assert_almost_eq(chaos["awake_dynamic_ratio"], 0.5, 0.001, "awake ratio should use active dynamic bodies only")
