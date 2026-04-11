## Central simulation container. Owns all SimBody and DebrisField objects.
## step_sim() is the sole entry point for advancing simulation state.
##
## Rendering and UI listen to signals emitted here; they never write back.
class_name SimWorld
extends RefCounted

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

func _init() -> void:
	_gravity = GravitySolver.new()
	_detector = CollisionDetector.new()
	_resolver = CollisionResolver.new(self)

func step_sim(dt: float) -> void:
	var sim_dt: float = dt * time_scale

	for body in bodies:
		if body.active:
			body.acceleration = Vector2.ZERO

	_gravity.apply_gravity(bodies)

	for body in bodies:
		if not body.active or body.sleeping or body.kinematic:
			continue
		body.velocity += body.acceleration * sim_dt
		body.position += body.velocity * sim_dt
		body.age += sim_dt

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

func get_black_hole() -> SimBody:
	for body in bodies:
		if body.active and body.body_type == SimBody.BodyType.BLACK_HOLE:
			return body
	return null

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
