extends GutTest

const FRAGMENT_TEST_SEED: int = 94731

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

func test_fragment_collision_is_pair_order_invariant_for_same_seed() -> void:
	var body_a_spec := {
		"mass": 20.0,
		"radius": 4.0,
		"position": Vector2(-2.0, 0.0),
		"velocity": Vector2(120.0, 10.0),
		"material_type": SimBody.MaterialType.ROCKY,
		"temperature": 180.0,
	}
	var body_b_spec := {
		"mass": 10.0,
		"radius": 4.0,
		"position": Vector2(2.0, 0.0),
		"velocity": Vector2(-90.0, -20.0),
		"material_type": SimBody.MaterialType.METALLIC,
		"temperature": 240.0,
	}

	var signature_forward: Dictionary = _run_fragment_collision_signature(body_a_spec, body_b_spec, false)
	var signature_reversed: Dictionary = _run_fragment_collision_signature(body_a_spec, body_b_spec, true)

	assert_eq(
		signature_forward,
		signature_reversed,
		"fragment outcomes should be invariant when the same collision is resolved with swapped pair order"
	)

func test_fragment_fallback_to_debris_is_pair_order_invariant_for_same_seed() -> void:
	var body_a_spec := {
		"mass": 3.0,
		"radius": 3.0,
		"position": Vector2(-1.5, 0.0),
		"velocity": Vector2(100.0, 5.0),
		"material_type": SimBody.MaterialType.ICY,
		"temperature": 90.0,
	}
	var body_b_spec := {
		"mass": 2.0,
		"radius": 3.0,
		"position": Vector2(1.5, 0.0),
		"velocity": Vector2(-110.0, -10.0),
		"material_type": SimBody.MaterialType.METALLIC,
		"temperature": 140.0,
	}

	var signature_forward: Dictionary = _run_fragment_collision_signature(body_a_spec, body_b_spec, false)
	var signature_reversed: Dictionary = _run_fragment_collision_signature(body_a_spec, body_b_spec, true)

	assert_eq(signature_forward["fragment_count"], 0, "fallback scenario should not emit active fragment bodies")
	assert_true(not signature_forward["debris_records"].is_empty(), "fallback scenario should convert the fragment pool into debris")
	assert_eq(
		signature_forward,
		signature_reversed,
		"debris fallback should also be invariant when the collision pair order is swapped"
	)

func test_fragment_collision_preserves_mass_budget() -> void:
	var body_a_spec := {
		"mass": 20.0,
		"radius": 4.0,
		"position": Vector2(-2.0, 0.0),
		"velocity": Vector2(120.0, 10.0),
		"material_type": SimBody.MaterialType.ROCKY,
		"temperature": 180.0,
	}
	var body_b_spec := {
		"mass": 10.0,
		"radius": 4.0,
		"position": Vector2(2.0, 0.0),
		"velocity": Vector2(-90.0, -20.0),
		"material_type": SimBody.MaterialType.METALLIC,
		"temperature": 240.0,
	}

	var signature: Dictionary = _run_fragment_collision_signature(body_a_spec, body_b_spec, false)
	var initial_total_mass: float = float(body_a_spec["mass"]) + float(body_b_spec["mass"])

	assert_almost_eq(
		signature["mass_budget_total"],
		initial_total_mass,
		0.001,
		"fragment collisions should preserve the total mass budget across parents, fragments and debris"
	)

func _run_fragment_collision_signature(body_a_spec: Dictionary, body_b_spec: Dictionary, swap_order: bool) -> Dictionary:
	seed(FRAGMENT_TEST_SEED)
	var world := SimWorld.new()
	var body_a: SimBody = _make_fragment_test_body(body_a_spec)
	var body_b: SimBody = _make_fragment_test_body(body_b_spec)
	world.add_body(body_a)
	world.add_body(body_b)

	var pre_a: Dictionary = _capture_body_state(body_a)
	var pre_b: Dictionary = _capture_body_state(body_b)
	var detector := CollisionDetector.new()
	var result: CollisionDetector.CollisionResult = detector.narrowphase(
		body_b if swap_order else body_a,
		body_a if swap_order else body_b
	)
	assert_true(result.colliding, "fragment test setup should start with an overlapping collision pair")

	CollisionResolver.new(world).resolve(result)
	world.flush_marked_removals()
	return _build_fragment_outcome_signature(world, pre_a, pre_b, body_a, body_b)

func _make_fragment_test_body(spec: Dictionary) -> SimBody:
	var body := SimBody.new()
	body.body_type = SimBody.BodyType.ASTEROID
	body.influence_level = SimBody.InfluenceLevel.B
	body.kinematic = false
	body.active = true
	body.mass = float(spec["mass"])
	body.radius = float(spec["radius"])
	body.position = Vector2(spec["position"])
	body.velocity = Vector2(spec["velocity"])
	body.material_type = int(spec["material_type"])
	body.temperature = float(spec["temperature"])
	return body

func _capture_body_state(body: SimBody) -> Dictionary:
	return {
		"mass": body.mass,
		"radius": body.radius,
		"position": body.position,
		"velocity": body.velocity,
		"material_type": body.material_type,
	}

func _build_fragment_outcome_signature(
		world: SimWorld,
		pre_a: Dictionary,
		pre_b: Dictionary,
		body_a: SimBody,
		body_b: SimBody) -> Dictionary:
	var collision_center: Vector2 = (Vector2(pre_a["position"]) + Vector2(pre_b["position"])) * 0.5
	var initial_total_mass: float = float(pre_a["mass"]) + float(pre_b["mass"])
	var base_velocity: Vector2 = (
		Vector2(pre_a["velocity"]) * float(pre_a["mass"])
		+ Vector2(pre_b["velocity"]) * float(pre_b["mass"])
	) / initial_total_mass

	var remaining_parent_masses: Array = [
		_quantize_float(body_a.mass),
		_quantize_float(body_b.mass),
	]
	remaining_parent_masses.sort()

	var remaining_parent_materials: Array = [
		body_a.material_type,
		body_b.material_type,
	]
	remaining_parent_materials.sort()

	var fragment_records: Array = []
	var fragment_total_mass: float = 0.0
	for body in world.bodies:
		if not body.active or body.body_type != SimBody.BodyType.FRAGMENT:
			continue
		fragment_total_mass += body.mass
		fragment_records.append([
			_quantize_float(body.mass),
			body.material_type,
			_quantize_vec2(body.position - collision_center),
			_quantize_vec2(body.velocity - base_velocity),
		])
	_lexicographic_sort(fragment_records)

	var debris_records: Array = []
	var debris_total_mass: float = 0.0
	for field in world.debris_fields:
		if field == null or not field.active:
			continue
		debris_total_mass += field.total_mass
		debris_records.append([
			_quantize_float(field.total_mass),
			_quantize_vec2(field.position - collision_center),
		])
	_lexicographic_sort(debris_records)

	return {
		"remaining_parent_masses_sorted": remaining_parent_masses,
		"remaining_parent_materials_sorted": remaining_parent_materials,
		"fragment_count": fragment_records.size(),
		"fragment_total_mass": _quantize_float(fragment_total_mass),
		"fragment_records": fragment_records,
		"debris_total_mass": _quantize_float(debris_total_mass),
		"debris_records": debris_records,
		"mass_budget_total": _quantize_float(
			body_a.mass + body_b.mass + fragment_total_mass + debris_total_mass
		),
	}

func _quantize_float(value: float) -> float:
	return round(value * 1000.0) / 1000.0

func _quantize_vec2(value: Vector2) -> Array:
	return [
		_quantize_float(value.x),
		_quantize_float(value.y),
	]

func _lexicographic_sort(records: Array) -> void:
	records.sort_custom(func(lhs, rhs): return _lexicographic_less(lhs, rhs))

func _lexicographic_less(lhs: Array, rhs: Array) -> bool:
	for index in range(min(lhs.size(), rhs.size())):
		var left_value = lhs[index]
		var right_value = rhs[index]
		if left_value is Array and right_value is Array:
			if _lexicographic_less(left_value, right_value):
				return true
			if _lexicographic_less(right_value, left_value):
				return false
			continue
		if left_value == right_value:
			continue
		return left_value < right_value
	return lhs.size() < rhs.size()
