## collision_resolver.gd
## Determines and applies collision outcomes.
##
## Outcomes (in priority order):
##   absorb    — tiny body swallowed by massive one (mass_ratio < 0.001)
##   impact    — asteroid hits planet
##   merge     — similar-mass slow collision
##   fragment  — high-energy collision, spawn fragments
##   bounce    — default elastic/inelastic rebound
class_name CollisionResolver
extends RefCounted

## Reference to SimWorld for spawning new bodies and debris.
## Assigned in _init(); not a circular class_name import.
var _world  # SimWorld (typed at runtime, not at parse time)

func _init(world) -> void:
	_world = world

func resolve(result: CollisionDetector.CollisionResult) -> void:
	var a: SimBody = result.body_a
	var b: SimBody = result.body_b

	# Positional correction first — push overlapping bodies apart
	_separate(a, b, result)

	var outcome: String = _determine_outcome(a, b, result)
	match outcome:
		"star_impact": _star_impact(a, b)
		"absorb":      _absorb(a, b)
		"impact":      _impact(a, b, result)
		"merge":       _merge(a, b)
		"fragment":    _fragment(a, b, result)
		_:             _bounce(a, b, result)

# -------------------------------------------------------------------------
# Outcome determination
# -------------------------------------------------------------------------

func _determine_outcome(a: SimBody, b: SimBody,
		result: CollisionDetector.CollisionResult) -> String:

	# Star absorbs everything that touches it
	if a.body_type == SimBody.BodyType.STAR or b.body_type == SimBody.BodyType.STAR:
		return "star_impact"

	var heavy: SimBody = a if a.mass >= b.mass else b
	var light: SimBody = b if a.mass >= b.mass else a
	var mass_ratio: float = light.mass / heavy.mass

	# Tiny body swallowed by massive one
	if mass_ratio < 0.001:
		return "absorb"

	# Asteroid / fragment hitting a planet
	if heavy.body_type == SimBody.BodyType.PLANET and \
			light.body_type in [SimBody.BodyType.ASTEROID, SimBody.BodyType.FRAGMENT]:
		return "impact"

	# Asteroid/fragment vs asteroid/fragment
	var both_small: bool = (
		a.body_type in [SimBody.BodyType.ASTEROID, SimBody.BodyType.FRAGMENT] and
		b.body_type in [SimBody.BodyType.ASTEROID, SimBody.BodyType.FRAGMENT]
	)
	if both_small:
		# Merge if mass ratio is close (similar sizes)
		if mass_ratio > (1.0 - SimConstants.MERGE_MASS_RATIO):
			return "merge"
		# Fragment if enough energy and we haven't hit the global cap
		if _collision_ke_fraction(a, b, result) > SimConstants.FRAGMENT_KE_THRESHOLD:
			var frag_count: int = _world.count_bodies_by_type(SimBody.BodyType.FRAGMENT)
			if frag_count < SimConstants.MAX_ACTIVE_FRAGMENTS - 2:
				return "fragment"

	return "bounce"

# -------------------------------------------------------------------------
# Resolution implementations
# -------------------------------------------------------------------------

func _bounce(a: SimBody, b: SimBody,
		result: CollisionDetector.CollisionResult) -> void:
	if result.approach_speed <= 0.0:
		return  # Bodies already moving apart; no impulse needed
	# Impulse formula: j = (1+e) * approach_speed / (1/ma + 1/mb)
	# collision_normal points from b → a, so:
	#   a gets +j/ma in the normal direction (pushed away from b) ✓
	#   b gets -j/mb in the normal direction (pushed away from a) ✓
	var e: float = SimConstants.RESTITUTION
	var n: Vector2 = result.collision_normal  # from b toward a
	var inv_mass_sum: float = (1.0 / a.mass) + (1.0 / b.mass)
	var impulse_scalar: float = (1.0 + e) * result.approach_speed / inv_mass_sum
	var impulse: Vector2 = n * impulse_scalar
	if not a.kinematic:
		a.velocity += impulse / a.mass   # a pushed away from b
	if not b.kinematic:
		b.velocity -= impulse / b.mass   # b pushed away from a

func _merge(a: SimBody, b: SimBody) -> void:
	var heavy: SimBody = a if a.mass >= b.mass else b
	var light: SimBody = b if a.mass >= b.mass else a
	# Momentum-conserving velocity
	heavy.velocity = (heavy.velocity * heavy.mass + light.velocity * light.mass) \
					 / (heavy.mass + light.mass)
	heavy.mass += light.mass
	heavy.debris_mass += light.debris_mass
	heavy.radius = _radius_for_mass(heavy.mass, heavy.body_type)
	light.marked_for_removal = true

func _absorb(a: SimBody, b: SimBody) -> void:
	var heavy: SimBody = a if a.mass >= b.mass else b
	var light: SimBody = b if a.mass >= b.mass else a
	heavy.mass += light.mass
	heavy.radius = _radius_for_mass(heavy.mass, heavy.body_type)
	light.marked_for_removal = true

func _impact(a: SimBody, b: SimBody,
		result: CollisionDetector.CollisionResult) -> void:
	var planet: SimBody = a if a.body_type == SimBody.BodyType.PLANET else b
	var asteroid: SimBody = b if a.body_type == SimBody.BodyType.PLANET else a

	# 70% of asteroid mass transfers to planet, 30% → debris
	var transfer_mass: float = asteroid.mass * 0.7
	var debris_mass: float = asteroid.mass * 0.3

	planet.mass += transfer_mass
	planet.radius = _radius_for_mass(planet.mass, SimBody.BodyType.PLANET)
	# Small velocity nudge from momentum transfer
	if not planet.kinematic:
		planet.velocity += (asteroid.velocity * asteroid.mass * 0.05) / planet.mass
	# Small heat from impact
	planet.temperature += asteroid.get_kinetic_energy() / planet.mass * 0.0001

	_world.add_debris_at(asteroid.position, debris_mass)
	asteroid.marked_for_removal = true

func _fragment(a: SimBody, b: SimBody,
		result: CollisionDetector.CollisionResult) -> void:
	# --- Mass-conserving fragmentation ---
	# 15% of combined mass becomes fragments (or debris if too small).
	# That exact mass is removed from the two bodies proportionally to their masses
	# so that: (a.mass_after + b.mass_after) + fragment_total = a.mass_before + b.mass_before
	var original_total: float = a.mass + b.mass
	var frag_pool: float = original_total * 0.15       # mass to split off
	var a_share: float = frag_pool * (a.mass / original_total)
	var b_share: float = frag_pool * (b.mass / original_total)

	var frag_count: int = randi_range(2, SimConstants.MAX_ACTIVE_FRAGMENTS / 5)
	var per_frag_mass: float = frag_pool / float(frag_count)

	# Remove mass from each body first (do this before bounce so radii are updated)
	a.mass -= a_share
	b.mass -= b_share
	a.radius = _radius_for_mass(a.mass, a.body_type)
	b.radius = _radius_for_mass(b.mass, b.body_type)

	if per_frag_mass < SimConstants.MIN_FRAGMENT_MASS:
		# Fragments too small for real SimBodies → send entire pool to debris
		_world.add_debris_at(a.position, frag_pool)
		_bounce(a, b, result)
		return

	_bounce(a, b, result)

	# Spawn fragments — their total mass exactly equals frag_pool
	for i in range(frag_count):
		var frag := _make_fragment(per_frag_mass, a, result, i, frag_count)
		_world.add_body(frag)

func _star_impact(a: SimBody, b: SimBody) -> void:
	# Non-star body collides with the star. The star absorbs the impactor.
	# A small fraction of the impactor mass becomes a visible debris flash near the impact.
	var star: SimBody   = a if a.body_type == SimBody.BodyType.STAR else b
	var impactor: SimBody = b if a.body_type == SimBody.BodyType.STAR else a

	var debris_fraction: float = impactor.mass * 0.05  # 5% of impactor mass → debris cloud
	star.mass += impactor.mass - debris_fraction
	_world.add_debris_at(impactor.position, debris_fraction)
	impactor.marked_for_removal = true

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

func _separate(a: SimBody, b: SimBody,
		result: CollisionDetector.CollisionResult) -> void:
	var correction: Vector2 = result.collision_normal * result.penetration_depth
	var total_mass: float = a.mass + b.mass
	if not a.kinematic:
		a.position += correction * (b.mass / total_mass)
	if not b.kinematic:
		b.position -= correction * (a.mass / total_mass)

func _collision_ke_fraction(a: SimBody, b: SimBody,
		result: CollisionDetector.CollisionResult) -> float:
	var reduced_mass: float = (a.mass * b.mass) / (a.mass + b.mass)
	var approach_ke: float = 0.5 * reduced_mass * result.approach_speed * result.approach_speed
	var total_ke: float = a.get_kinetic_energy() + b.get_kinetic_energy()
	if total_ke < 0.0001:
		return 0.0
	return approach_ke / total_ke

func _make_fragment(mass: float, source: SimBody,
		result: CollisionDetector.CollisionResult,
		index: int, total: int) -> SimBody:
	var frag := SimBody.new()
	frag.body_type = SimBody.BodyType.FRAGMENT
	frag.influence_level = SimBody.InfluenceLevel.C
	frag.material_type = source.material_type
	frag.mass = mass
	frag.radius = _radius_for_mass(mass, SimBody.BodyType.FRAGMENT)
	# Spread in a cone around the collision normal
	var spread: float = (float(index) / float(total) - 0.5) * PI * 0.7
	var eject_dir: Vector2 = result.collision_normal.rotated(spread)
	frag.position = source.position + eject_dir * (source.radius * 1.5)
	frag.velocity = source.velocity + eject_dir * randf_range(20.0, 80.0)
	frag.temperature = source.temperature * 1.1
	frag.kinematic = false
	frag.active = true
	return frag

func _radius_for_mass(mass: float, body_type: int) -> float:
	match body_type:
		SimBody.BodyType.STAR:
			return SimConstants.STAR_RADIUS
		SimBody.BodyType.PLANET:
			return clamp(SimConstants.PLANET_RADIUS_MIN + log(mass / SimConstants.PLANET_MASS_MIN + 1.0),
						 SimConstants.PLANET_RADIUS_MIN, SimConstants.PLANET_RADIUS_MAX)
		SimBody.BodyType.ASTEROID:
			return clamp(SimConstants.ASTEROID_RADIUS_MIN + mass * 0.06,
						 SimConstants.ASTEROID_RADIUS_MIN, SimConstants.ASTEROID_RADIUS_MAX)
		_:  # FRAGMENT, DEBRIS_FIELD
			return clamp(mass * 0.1, SimConstants.FRAGMENT_RADIUS_MIN, SimConstants.FRAGMENT_RADIUS_MAX)
