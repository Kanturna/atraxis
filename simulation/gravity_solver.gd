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
	for i in range(level_a.size()):
		for j in range(i + 1, level_a.size()):
			_apply_mutual(level_a[i], level_a[j])

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
		target.acceleration += delta.normalized() * (gm / dist_sq)

func _apply_mutual(body_a: SimBody, body_b: SimBody) -> void:
	var delta: Vector2 = body_b.position - body_a.position
	var dist_sq: float = delta.length_squared() + SimConstants.GRAVITY_SOFTENING_SQ
	var dir: Vector2 = delta.normalized()
	if not body_a.kinematic:
		body_a.acceleration += dir * (SimConstants.G * body_b.mass / dist_sq)
	if not body_b.kinematic:
		body_b.acceleration -= dir * (SimConstants.G * body_a.mass / dist_sq)

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
