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
	var anchor: Dictionary = snapshot["anchor"]

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
	assert_almost_eq(anchor["black_hole_mass"], 0.0, 0.001, "empty worlds should report zero black-hole mass")
	assert_eq(anchor["negative_specific_energy_stars"], 0, "empty worlds should report zero E<0 diagnostic stars")
	assert_eq(anchor["non_negative_specific_energy_stars"], 0, "empty worlds should report zero E>=0 diagnostic stars")

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

func test_anchor_metrics_report_negative_and_non_negative_specific_energy_stars() -> void:
	var world := SimWorld.new()

	var black_hole := SimBody.new()
	black_hole.active = true
	black_hole.body_type = SimBody.BodyType.BLACK_HOLE
	black_hole.kinematic = true
	black_hole.mass = 10_000_000.0
	world.add_body(black_hole)

	var bound_star := SimBody.new()
	bound_star.active = true
	bound_star.body_type = SimBody.BodyType.STAR
	bound_star.kinematic = false
	bound_star.mass = SimConstants.STAR_MASS
	bound_star.position = Vector2(4000.0, 0.0)
	bound_star.velocity = Vector2(0.0, 300.0)
	world.add_body(bound_star)

	var unbound_star := SimBody.new()
	unbound_star.active = true
	unbound_star.body_type = SimBody.BodyType.STAR
	unbound_star.kinematic = false
	unbound_star.mass = SimConstants.STAR_MASS
	unbound_star.position = Vector2(-7000.0, 0.0)
	unbound_star.velocity = Vector2(0.0, 700.0)
	world.add_body(unbound_star)

	var snapshot: Dictionary = DEBUG_METRICS_SCRIPT.new().build_snapshot(world, 0)
	var anchor: Dictionary = snapshot["anchor"]

	assert_almost_eq(anchor["black_hole_mass"], black_hole.mass, 0.001, "anchor metrics should expose current black-hole mass")
	assert_almost_eq(anchor["total_star_mass"], bound_star.mass + unbound_star.mass, 0.001, "anchor metrics should aggregate star mass")
	assert_eq(anchor["negative_specific_energy_stars"], 1, "one star should report E<0 relative to the dominant black hole")
	assert_eq(anchor["non_negative_specific_energy_stars"], 1, "one star should report E>=0 relative to the dominant black hole")
	assert_almost_eq(anchor["anchor_ratio"], black_hole.mass / (bound_star.mass + unbound_star.mass), 0.001, "anchor ratio should compare BH mass to total star mass")

func test_anchor_energy_diagnostics_do_not_capture_or_rebind_stars() -> void:
	var world := SimWorld.new()

	var black_hole := SimBody.new()
	black_hole.active = true
	black_hole.body_type = SimBody.BodyType.BLACK_HOLE
	black_hole.kinematic = true
	black_hole.mass = 10_000_000.0
	world.add_body(black_hole)

	var star := SimBody.new()
	star.active = true
	star.body_type = SimBody.BodyType.STAR
	star.kinematic = false
	star.mass = SimConstants.STAR_MASS
	star.position = Vector2(4000.0, 0.0)
	star.velocity = Vector2(0.0, 300.0)
	world.add_body(star)

	var original_position: Vector2 = star.position
	var original_velocity: Vector2 = star.velocity

	var snapshot: Dictionary = DEBUG_METRICS_SCRIPT.new().build_snapshot(world, 0)
	var anchor: Dictionary = snapshot["anchor"]
	var star_state: Dictionary = anchor["star_anchor_states"][0]

	assert_true(star.active, "energy diagnostics should not deactivate the star")
	assert_false(star.scripted_orbit_enabled, "energy diagnostics should not convert dynamic stars into scripted orbiters")
	assert_eq(star.orbit_binding_state, SimBody.OrbitBindingState.FREE_DYNAMIC, "energy diagnostics should not rebind stars")
	assert_eq(star.position, original_position, "energy diagnostics should not move the star")
	assert_eq(star.velocity, original_velocity, "energy diagnostics should not alter the star velocity")
	assert_true(star_state["negative_specific_energy"], "the diagnostic should still expose the instantaneous E<0 classification")

func test_anchor_metrics_report_dominant_and_secondary_black_holes_per_star() -> void:
	var world := SimWorld.new()

	var central_bh := SimBody.new()
	central_bh.active = true
	central_bh.body_type = SimBody.BodyType.BLACK_HOLE
	central_bh.kinematic = true
	central_bh.mass = 12_000_000.0
	central_bh.position = Vector2.ZERO
	world.add_body(central_bh)

	var outer_bh := SimBody.new()
	outer_bh.active = true
	outer_bh.body_type = SimBody.BodyType.BLACK_HOLE
	outer_bh.kinematic = true
	outer_bh.mass = 12_000_000.0
	outer_bh.position = Vector2(9000.0, 0.0)
	world.add_body(outer_bh)

	var star := SimBody.new()
	star.active = true
	star.body_type = SimBody.BodyType.STAR
	star.kinematic = false
	star.mass = SimConstants.STAR_MASS
	star.position = Vector2(2500.0, 0.0)
	star.velocity = Vector2(0.0, 300.0)
	world.add_body(star)

	var snapshot: Dictionary = DEBUG_METRICS_SCRIPT.new().build_snapshot(world, 0)
	var anchor: Dictionary = snapshot["anchor"]
	var star_states: Array = anchor["star_anchor_states"]

	assert_eq(anchor["black_hole_count"], 2, "anchor metrics should count multiple black holes in a field patch")
	assert_eq(anchor["field_ring_count"], 2, "one center plus one outer BH should span two logical field rings")
	assert_almost_eq(anchor["black_hole_mass"], central_bh.mass + outer_bh.mass, 0.001, "anchor metrics should sum the mass of all black holes")
	assert_almost_eq(anchor["min_black_hole_distance"], 9000.0, 0.001, "anchor metrics should report the smallest BH-BH spacing")
	assert_eq(star_states.size(), 1, "one star should yield one anchor-state entry")
	assert_eq(star_states[0]["dominant_bh_id"], central_bh.id, "the closer central BH should dominate the star")
	assert_eq(star_states[0]["secondary_bh_id"], outer_bh.id, "the next strongest BH should be reported as the secondary anchor")
	assert_gt(star_states[0]["dominance_ratio"], 1.0, "dominant anchor should report a ratio above 1.0 against the secondary BH")

func test_anchor_metrics_report_host_alignment_handoffs_and_close_star_encounters() -> void:
	var world := SimWorld.new()

	var central_bh := SimBody.new()
	central_bh.active = true
	central_bh.body_type = SimBody.BodyType.BLACK_HOLE
	central_bh.kinematic = true
	central_bh.mass = 12_000_000.0
	central_bh.position = Vector2.ZERO
	world.add_body(central_bh)

	var outer_bh := SimBody.new()
	outer_bh.active = true
	outer_bh.body_type = SimBody.BodyType.BLACK_HOLE
	outer_bh.kinematic = true
	outer_bh.mass = 12_000_000.0
	outer_bh.position = Vector2(9000.0, 0.0)
	world.add_body(outer_bh)

	var matched_star := SimBody.new()
	matched_star.active = true
	matched_star.body_type = SimBody.BodyType.STAR
	matched_star.kinematic = false
	matched_star.mass = SimConstants.STAR_MASS
	matched_star.position = Vector2(2500.0, 0.0)
	matched_star.velocity = Vector2(0.0, 300.0)
	matched_star.orbit_parent_id = central_bh.id
	matched_star.dominant_bh_handoff_count = 2
	matched_star.confirmed_host_handoff_count = 1
	world.add_body(matched_star)

	var mismatched_star := SimBody.new()
	mismatched_star.active = true
	mismatched_star.body_type = SimBody.BodyType.STAR
	mismatched_star.kinematic = false
	mismatched_star.mass = SimConstants.STAR_MASS
	mismatched_star.position = Vector2(2900.0, 0.0)
	mismatched_star.velocity = Vector2(0.0, 300.0)
	mismatched_star.orbit_parent_id = outer_bh.id
	mismatched_star.pending_host_bh_id = central_bh.id
	mismatched_star.pending_host_time = 0.5
	mismatched_star.confirmed_host_handoff_count = 2
	world.add_body(mismatched_star)

	var snapshot: Dictionary = DEBUG_METRICS_SCRIPT.new().build_snapshot(world, 0)
	var anchor: Dictionary = snapshot["anchor"]
	var star_states: Array = anchor["star_anchor_states"]

	assert_eq(anchor["stars_with_host"], 2, "both stars should report their assigned host black hole")
	assert_eq(anchor["host_dominance_match_count"], 1, "one star should begin aligned with its dominant black hole")
	assert_eq(anchor["host_dominance_mismatch_count"], 1, "one star should expose a host-vs-dominant mismatch")
	assert_almost_eq(anchor["min_star_host_bh_distance"], 2500.0, 0.001, "host diagnostics should expose the nearest star-to-host distance")
	assert_eq(anchor["stars_with_dominant_handoffs"], 1, "handoff aggregation should count stars that already switched dominant BHs")
	assert_eq(anchor["total_dominant_handoffs"], 2, "handoff aggregation should sum the per-star counters")
	assert_eq(anchor["confirmed_host_handoff_count_total"], 3, "confirmed host handoffs should aggregate independently from raw dominant switches")
	assert_eq(anchor["close_star_encounter_count"], 2, "both stars should report the close encounter when their separation is small")
	assert_eq(star_states[0]["host_bh_id"], central_bh.id, "per-star diagnostics should expose the matched host id")
	assert_true(star_states[0]["dominant_matches_host"], "the matched star should report host alignment")
	assert_eq(star_states[0]["dominant_handoff_count"], 2, "per-star diagnostics should expose the persisted handoff counter")
	assert_eq(star_states[0]["confirmed_host_handoff_count"], 1, "per-star diagnostics should expose confirmed host handoff counts")
	assert_eq(star_states[0]["pending_host_bh_id"], -1, "stars without a pending host switch should expose the cleared pending host id")
	assert_almost_eq(star_states[0]["pending_host_time"], 0.0, 0.001, "stars without a pending host switch should expose a zero pending timer")
	assert_false(star_states[0]["handoff_pending"], "stars without a pending host switch should expose a false pending flag")
	assert_almost_eq(star_states[0]["min_other_star_distance"], 400.0, 0.001, "per-star diagnostics should expose the nearest other-star distance")
	assert_eq(star_states[1]["host_bh_id"], outer_bh.id, "per-star diagnostics should expose the mismatched host id")
	assert_false(star_states[1]["dominant_matches_host"], "the mismatched star should report a host mismatch")
	assert_almost_eq(star_states[1]["host_distance"], 6100.0, 0.001, "host distance should use the assigned host, not the dominant one")
	assert_eq(star_states[1]["confirmed_host_handoff_count"], 2, "per-star diagnostics should expose confirmed host switches")
	assert_eq(star_states[1]["pending_host_bh_id"], central_bh.id, "per-star diagnostics should expose the pending confirmed-host candidate")
	assert_almost_eq(star_states[1]["pending_host_time"], 0.5, 0.001, "per-star diagnostics should expose the pending host timer")
	assert_true(star_states[1]["handoff_pending"], "per-star diagnostics should flag stars with a pending confirmed-host switch")
