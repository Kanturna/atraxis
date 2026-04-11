## Central simulation container. Owns all SimBody and DebrisField objects.
## step_sim() is the sole entry point for advancing simulation state.
##
## Rendering and UI listen to signals emitted here; they never write back.
class_name SimWorld
extends RefCounted

const ANCHOR_FIELD_SCRIPT := preload("res://simulation/anchor_field.gd")

signal body_added(body: SimBody)
signal body_removed(body_id: int)
signal debris_field_changed(field: DebrisField)
signal collision_occurred(pos: Vector2)

var bodies: Array = []
var debris_fields: Array = []
var time_elapsed: float = 0.0
var time_scale: float = 1.0
var _next_id: int = 0

var _gravity: GravitySolver
var _detector: CollisionDetector
var _resolver: CollisionResolver

# Dominant-BH cache: rebuilt once per step_sim call so that the O(n_bodies × n_BH)
# scan happens exactly once per frame, not once per substep per body.
# Bodies use this for the periapsis guardrail and nearfield substep check.
# BHs are kinematic and do not move within a single step, so the cache is valid
# for all substeps of the same frame.
var _dominant_bh_cache: Dictionary = {}  # body.id → {dominant_bh: SimBody, distance: float}

func _init() -> void:
	_gravity = GravitySolver.new()
	_detector = CollisionDetector.new()
	_resolver = CollisionResolver.new(self)

func step_sim(dt: float) -> void:
	var sim_dt: float = dt * time_scale
	_rebuild_dominant_bh_cache()
	var integration_substeps: int = _determine_black_hole_nearfield_substeps()
	var sub_dt: float = sim_dt / float(integration_substeps)

	for _substep in range(integration_substeps):
		for body in bodies:
			if body.active:
				body.acceleration = Vector2.ZERO

		_gravity.apply_gravity(bodies)

		for body in bodies:
			if not body.active or body.sleeping or body.kinematic:
				continue
			var previous_position: Vector2 = body.position
			body.velocity += body.acceleration * sub_dt
			body.position += body.velocity * sub_dt
			_apply_star_black_hole_periapsis_guardrail(body, previous_position)
			body.age += sub_dt

	_update_scripted_orbiters(sim_dt)

	for body in bodies:
		if not body.active or body.kinematic or body.scripted_orbit_enabled:
			continue
		if body.check_sleep_eligible():
			body.sleep_timer += sim_dt
			if body.sleep_timer >= SimConstants.SLEEP_CONFIRM_TIME:
				body.sleeping = true
		else:
			body.reset_sleep_timer()

	var pairs: Array = _detector.broadphase(bodies)
	for pair in pairs:
		var result: CollisionDetector.CollisionResult = _detector.narrowphase(pair[0], pair[1])
		if result.colliding:
			_resolver.resolve(result)
			collision_occurred.emit(result.body_a.position)

	_aggregate_debris_fields()
	_cleanup_inactive_debris_fields()
	_flush_removals()
	_enforce_fragment_cap()
	time_elapsed += sim_dt

func add_body(body: SimBody) -> void:
	body.id = _next_id
	_next_id += 1
	bodies.append(body)
	body_added.emit(body)

func add_debris_at(pos: Vector2, mass: float) -> void:
	if mass <= 0.0:
		return
	var nearest: DebrisField = null
	var nearest_dist_sq: float = SimConstants.DEBRIS_MERGE_RADIUS * SimConstants.DEBRIS_MERGE_RADIUS
	for field in debris_fields:
		if not field.active:
			continue
		var d: float = field.position.distance_squared_to(pos)
		if d < nearest_dist_sq:
			nearest_dist_sq = d
			nearest = field

	if nearest != null:
		nearest.add_mass(mass, pos)
		debris_field_changed.emit(nearest)
	elif _active_debris_count() < SimConstants.MAX_DEBRIS_FIELDS:
		var field := DebrisField.new()
		field.id = _next_id
		_next_id += 1
		field.position = pos
		field.total_mass = mass
		field.active = true
		debris_fields.append(field)
		debris_field_changed.emit(field)

func count_bodies_by_type(type: int) -> int:
	var count: int = 0
	for body in bodies:
		if body.active and body.body_type == type:
			count += 1
	return count

func get_active_body_count() -> int:
	var count: int = 0
	for body in bodies:
		if body.active:
			count += 1
	return count

func get_sleeping_body_count() -> int:
	var count: int = 0
	for body in bodies:
		if body.active and body.sleeping:
			count += 1
	return count

func get_active_debris_count() -> int:
	return _active_debris_count()

func get_star() -> SimBody:
	for body in bodies:
		if body.active and body.body_type == SimBody.BodyType.STAR:
			return body
	return null

func get_stars() -> Array:
	var result: Array = []
	for body in bodies:
		if body.active and body.body_type == SimBody.BodyType.STAR:
			result.append(body)
	return result

func get_body_by_id(body_id: int) -> SimBody:
	return _find_body_by_id(body_id)

func get_black_hole() -> SimBody:
	# Legacy helper for callers that still expect a single dominant BH.
	# In field-patch setups this intentionally returns the first active BH only.
	for body in bodies:
		if body.active and body.body_type == SimBody.BodyType.BLACK_HOLE:
			return body
	return null

func get_black_holes() -> Array:
	var result: Array = []
	for body in bodies:
		if body.active and body.body_type == SimBody.BodyType.BLACK_HOLE:
			result.append(body)
	return result

func set_black_hole_mass(new_mass: float) -> void:
	var black_holes: Array = get_black_holes()
	if black_holes.is_empty():
		return
	var black_hole_ids: Dictionary = {}
	for black_hole in black_holes:
		black_hole.mass = new_mass
		black_hole_ids[black_hole.id] = true
	for body in bodies:
		if not body.active or body.body_type != SimBody.BodyType.STAR:
			continue
		if body.is_analytic_orbit_bound() and black_hole_ids.has(body.orbit_parent_id) and body.orbit_radius > 0.0:
			var parent_black_hole: SimBody = get_body_by_id(body.orbit_parent_id)
			var orbit_speed: float = sqrt(SimConstants.G * parent_black_hole.mass / body.orbit_radius)
			body.orbit_angular_speed = orbit_speed / body.orbit_radius

func _rebuild_dominant_bh_cache() -> void:
	_dominant_bh_cache.clear()
	var black_holes: Array = get_black_holes()
	if black_holes.is_empty():
		return
	for body in bodies:
		if not _requires_black_hole_nearfield_substeps(body) and not _requires_star_black_hole_guardrail(body):
			continue
		var best_bh: SimBody = null
		var best_strength: float = -1.0
		var best_dist: float = INF
		for bh in black_holes:
			if bh == null or not bh.active:
				continue
			var delta: Vector2 = bh.position - body.position
			var dist_sq: float = delta.length_squared() + SimConstants.GRAVITY_SOFTENING_SQ
			var strength: float = SimConstants.G * bh.mass / dist_sq
			if strength > best_strength:
				best_strength = strength
				best_bh = bh
				best_dist = delta.length()
		if best_bh != null:
			_dominant_bh_cache[body.id] = {"dominant_bh": best_bh, "distance": best_dist}

func _determine_black_hole_nearfield_substeps() -> int:
	if _dominant_bh_cache.is_empty():
		return 1
	for body in bodies:
		if not _requires_black_hole_nearfield_substeps(body):
			continue
		if not _dominant_bh_cache.has(body.id):
			continue
		var entry: Dictionary = _dominant_bh_cache[body.id]
		var dominant_black_hole: SimBody = entry["dominant_bh"]
		var dominant_distance: float = entry["distance"]
		var nearfield_radius: float = ANCHOR_FIELD_SCRIPT.nearfield_radius_for_mass(dominant_black_hole.mass)
		if nearfield_radius > 0.0 and dominant_distance <= nearfield_radius:
			return SimConstants.BH_NEARFIELD_SUBSTEPS
	return 1

func _requires_black_hole_nearfield_substeps(body: SimBody) -> bool:
	if not body.active or body.sleeping or body.kinematic:
		return false
	return body.body_type in [
		SimBody.BodyType.STAR,
		SimBody.BodyType.PLANET,
		SimBody.BodyType.ASTEROID,
	]

func _apply_star_black_hole_periapsis_guardrail(body: SimBody, previous_position: Vector2) -> void:
	if not _requires_star_black_hole_guardrail(body):
		return
	if not _dominant_bh_cache.has(body.id):
		return
	var dominant_black_hole: SimBody = _dominant_bh_cache[body.id]["dominant_bh"]
	var offset_from_black_hole: Vector2 = body.position - dominant_black_hole.position
	var current_distance: float = offset_from_black_hole.length()
	var minimum_distance: float = dominant_black_hole.radius + body.radius + SimConstants.BH_STAR_APPROACH_PADDING
	if minimum_distance <= 0.0 or current_distance > minimum_distance:
		return
	var previous_distance: float = previous_position.distance_to(dominant_black_hole.position)
	if previous_distance < minimum_distance:
		return
	if current_distance > 0.0:
		var radial_direction: Vector2 = offset_from_black_hole / current_distance
		var radial_velocity: float = body.velocity.dot(radial_direction)
		if radial_velocity >= 0.0:
			return
		# Project the star back onto the smallest allowed periapsis radius while
		# preserving visible tangential motion. This is a local guardrail against
		# unusable ultra-close inward passes, not a capture or parent-change rule.
		var tangential_velocity: Vector2 = body.velocity - radial_direction * radial_velocity
		body.position = dominant_black_hole.position + radial_direction * minimum_distance
		# Local binding aid: if the remaining tangential speed already exceeds local
		# escape velocity (v_esc = sqrt(2·G·M/r)) — e.g. due to numerical energy
		# injection at high time_scale — clamp it to BH_GUARDRAIL_ESCAPE_MARGIN × v_esc
		# so the star stays bound. The direction is preserved; only the magnitude is
		# reduced. BH_GUARDRAIL_ESCAPE_MARGIN is a tuning constant in sim_constants.gd.
		var escape_vel_sq: float = 2.0 * SimConstants.G * dominant_black_hole.mass / minimum_distance
		if tangential_velocity.length_squared() >= escape_vel_sq:
			tangential_velocity = tangential_velocity.normalized() * (sqrt(escape_vel_sq) * SimConstants.BH_GUARDRAIL_ESCAPE_MARGIN)
		body.velocity = tangential_velocity
		return
	var fallback_offset: Vector2 = previous_position - dominant_black_hole.position
	if fallback_offset == Vector2.ZERO:
		fallback_offset = Vector2.RIGHT
	var fallback_direction: Vector2 = fallback_offset.normalized()
	body.position = dominant_black_hole.position + fallback_direction * minimum_distance
	var fallback_radial_velocity: float = body.velocity.dot(fallback_direction)
	if fallback_radial_velocity < 0.0:
		body.velocity -= fallback_direction * fallback_radial_velocity

func _requires_star_black_hole_guardrail(body: SimBody) -> bool:
	return body.active \
		and not body.sleeping \
		and not body.kinematic \
		and body.body_type == SimBody.BodyType.STAR

func _update_scripted_orbiters(sim_dt: float) -> void:
	for body in bodies:
		if not body.active or not body.is_analytic_orbit_bound():
			continue
		var parent: SimBody = _find_body_by_id(body.orbit_parent_id)
		if parent == null or not parent.active:
			continue
		body.sleeping = false
		body.sleep_timer = 0.0
		body.orbit_angle = wrapf(body.orbit_angle + body.orbit_angular_speed * sim_dt, 0.0, TAU)
		var radial: Vector2 = Vector2(cos(body.orbit_angle), sin(body.orbit_angle))
		var tangent: Vector2 = Vector2(-sin(body.orbit_angle), cos(body.orbit_angle))
		body.orbit_center = parent.position
		body.position = parent.position + radial * body.orbit_radius
		body.velocity = parent.velocity + tangent * (body.orbit_angular_speed * body.orbit_radius)
		body.age += sim_dt

func _aggregate_debris_fields() -> void:
	for i in range(debris_fields.size()):
		var fi: DebrisField = debris_fields[i]
		if not fi.active:
			continue
		for j in range(i + 1, debris_fields.size()):
			var fj: DebrisField = debris_fields[j]
			if not fj.active:
				continue
			var sum_r: float = fi.radius + fj.radius
			if fi.position.distance_squared_to(fj.position) < sum_r * sum_r:
				fi.absorb(fj)
				debris_field_changed.emit(fi)

func _cleanup_inactive_debris_fields() -> void:
	var i: int = debris_fields.size() - 1
	while i >= 0:
		if not debris_fields[i].active:
			debris_fields.remove_at(i)
		i -= 1

func _flush_removals() -> void:
	var i: int = bodies.size() - 1
	while i >= 0:
		var body: SimBody = bodies[i]
		if body.marked_for_removal:
			bodies.remove_at(i)
			body_removed.emit(body.id)
		i -= 1

func _enforce_fragment_cap() -> void:
	var fragments: Array = []
	for body in bodies:
		if body.active and body.body_type == SimBody.BodyType.FRAGMENT:
			fragments.append(body)
	if fragments.size() <= SimConstants.MAX_ACTIVE_FRAGMENTS:
		return
	fragments.sort_custom(func(a, b): return a.mass < b.mass)
	var excess: int = fragments.size() - SimConstants.MAX_ACTIVE_FRAGMENTS
	for i in range(excess):
		var frag: SimBody = fragments[i]
		add_debris_at(frag.position, frag.mass)
		frag.marked_for_removal = true
	_flush_removals()

func _active_debris_count() -> int:
	var count: int = 0
	for field in debris_fields:
		if field.active:
			count += 1
	return count

func _find_body_by_id(body_id: int) -> SimBody:
	for body in bodies:
		if body.id == body_id:
			return body
	return null
