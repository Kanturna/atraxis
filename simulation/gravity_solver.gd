## gravity_solver.gd
## Hierarchy-aware gravity calculation.
##
## Influence hierarchy:
##   A → B, A → C  (always, full strength)
##   A ↔ A          (mutual; in MVP with 1 star this loop is empty)
##   B ↔ B          (mutual, proximity-limited for performance)
##   B → C          (one-way from B)
##   C → nothing    (C bodies never source gravity)
##
## kinematic bodies: receive no acceleration from gravity but still act
## as sources so other bodies orbit around them correctly.
class_name GravitySolver
extends RefCounted

func apply_gravity(bodies: Array) -> void:
	# Partition active bodies by influence level
	var level_a: Array = []
	var level_b: Array = []
	var level_c: Array = []

	for body in bodies:
		if not body.active:
			continue
		match body.influence_level:
			SimBody.InfluenceLevel.A: level_a.append(body)
			SimBody.InfluenceLevel.B: level_b.append(body)
			SimBody.InfluenceLevel.C: level_c.append(body)

	# A as sources → affect B and C
	for source in level_a:
		_apply_from_source(source, level_b)
		_apply_from_source(source, level_c)

	# A ↔ A mutual (empty in single-star MVP; ready for multi-star)
	# Skip pairs where both bodies are kinematic (e.g. two fixed BHs): neither
	# receives acceleration, so the full distance/direction computation is wasted.
	# With N kinematic BHs this saves N*(N-1)/2 iterations per substep — the
	# dominant cost with large BH counts.
	for i in range(level_a.size()):
		for j in range(i + 1, level_a.size()):
			var body_a: SimBody = level_a[i]
			var body_b: SimBody = level_a[j]
			if body_a.kinematic and body_b.kinematic:
				continue
			if _is_black_hole(body_a) and _is_black_hole(body_b):
				_apply_mutual(body_a, body_b)
				continue
			if _is_star(body_a) and _is_star(body_b):
				_apply_star_star_mutual(body_a, body_b)
				continue
			_apply_mutual(body_a, body_b)

	# B ↔ B mutual, proximity-limited
	_apply_b_b_limited(level_b)

	# B as sources → affect C
	for source in level_b:
		if source.sleeping:
			continue
		_apply_from_source(source, level_c)

	# C never sources gravity; no further loops needed

func _apply_from_source(source: SimBody, targets: Array) -> void:
	var gm: float = SimConstants.G * source.mass
	for target in targets:
		if target.sleeping or target.kinematic or target.id == source.id:
			continue
		var delta: Vector2 = source.position - target.position
		var dist_sq: float = delta.length_squared() + SimConstants.GRAVITY_SOFTENING_SQ
		# a = G*M / r² (target mass cancels: F = G*M*m/r², a = F/m = G*M/r²)
		var accel_magnitude: float = gm / dist_sq
		target.acceleration += delta.normalized() * accel_magnitude

func _apply_mutual(body_a: SimBody, body_b: SimBody) -> void:
	_apply_mutual_scaled(body_a, body_b, 1.0)

func _apply_mutual_scaled(body_a: SimBody, body_b: SimBody, force_scale: float) -> void:
	var delta: Vector2 = body_b.position - body_a.position
	var dist_sq: float = delta.length_squared() + SimConstants.GRAVITY_SOFTENING_SQ
	var dir: Vector2 = delta.normalized()
	if not body_a.kinematic:
		body_a.acceleration += dir * (SimConstants.G * body_b.mass / dist_sq) * force_scale
	if not body_b.kinematic:
		body_b.acceleration -= dir * (SimConstants.G * body_a.mass / dist_sq) * force_scale

func _apply_star_star_mutual(star_a: SimBody, star_b: SimBody) -> void:
	var distance: float = star_a.position.distance_to(star_b.position)
	_apply_mutual_scaled(star_a, star_b, _star_star_gravity_scale_for_distance(distance))

func _star_star_gravity_scale_for_distance(distance: float) -> float:
	var full_force_distance: float = SimConstants.STAR_STAR_FULL_FORCE_DISTANCE
	var fade_distance: float = maxf(SimConstants.STAR_STAR_FORCE_FADE_DISTANCE, full_force_distance)
	if distance <= full_force_distance:
		return 1.0
	if distance >= fade_distance:
		return SimConstants.STAR_STAR_GRAVITY_FAR_SCALE
	if fade_distance <= full_force_distance + 0.000001:
		return SimConstants.STAR_STAR_GRAVITY_FAR_SCALE
	var t: float = clampf(
		(distance - full_force_distance) / (fade_distance - full_force_distance),
		0.0,
		1.0
	)
	var smooth_t: float = t * t * (3.0 - 2.0 * t)
	return lerpf(1.0, SimConstants.STAR_STAR_GRAVITY_FAR_SCALE, smooth_t)

func _is_black_hole(body: SimBody) -> bool:
	return body.body_type == SimBody.BodyType.BLACK_HOLE

func _is_star(body: SimBody) -> bool:
	return body.body_type == SimBody.BodyType.STAR

func _apply_b_b_limited(level_b: Array) -> void:
	for i in range(level_b.size()):
		var bi: SimBody = level_b[i]
		if bi.sleeping:
			continue
		for j in range(i + 1, level_b.size()):
			var bj: SimBody = level_b[j]
			if bj.sleeping:
				continue
			var delta: Vector2 = bj.position - bi.position
			if delta.length_squared() > SimConstants.B_B_GRAVITY_RADIUS_SQ:
				continue
			_apply_mutual(bi, bj)
