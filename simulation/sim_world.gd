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

# Dominant-BH cache: rebuilt from the current positions and used only to steer
# adaptive integration around the strongest nearby black hole.
var _dominant_bh_cache: Dictionary = {}  # body.id → {dominant_bh: SimBody, distance: float, orbital_timescale: float}

func _init() -> void:
	_gravity = GravitySolver.new()
	_detector = CollisionDetector.new()
	_resolver = CollisionResolver.new(self)

func step_sim(dt: float) -> void:
	var sim_dt: float = dt * time_scale

	if sim_dt > 0.0:
		_rebuild_dominant_bh_cache()
		var integration_substeps: int = _determine_black_hole_adaptive_substeps(sim_dt)
		var sub_dt: float = sim_dt / float(integration_substeps)
		for _substep in range(integration_substeps):
			_integrate_dynamic_bodies(sub_dt)
		_update_scripted_orbiters(sim_dt)
		_run_sleep_phase(sim_dt)
		_rebuild_dominant_bh_cache()
		_update_dynamic_star_host_assignments(sim_dt)

	_run_collision_phase()
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

func get_body_by_persistent_object_id(object_id: String) -> SimBody:
	for body in bodies:
		if body.active and body.persistent_object_id == object_id:
			return body
	return null

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

func dispose() -> void:
	bodies.clear()
	debris_fields.clear()
	_dominant_bh_cache.clear()
	_resolver = null
	_detector = null
	_gravity = null

func flush_marked_removals() -> void:
	_flush_removals()

func _integrate_dynamic_bodies(sub_dt: float) -> void:
	var black_holes: Array = get_black_holes()

	_reset_accelerations()
	_gravity.apply_gravity(bodies)

	for body in bodies:
		if not _should_integrate_body(body):
			continue
		body.velocity += body.acceleration * (0.5 * sub_dt)
		var previous_position: Vector2 = body.position
		body.position += body.velocity * sub_dt
		_handle_black_hole_segment_impacts(body, previous_position, black_holes)
		if body.active:
			body.age += sub_dt

	_reset_accelerations()
	_gravity.apply_gravity(bodies)

	for body in bodies:
		if not _should_integrate_body(body):
			continue
		body.velocity += body.acceleration * (0.5 * sub_dt)

func _run_sleep_phase(sim_dt: float) -> void:
	for body in bodies:
		if not body.active or body.kinematic or body.scripted_orbit_enabled:
			continue
		if body.check_sleep_eligible():
			body.sleep_timer += sim_dt
			if body.sleep_timer >= SimConstants.SLEEP_CONFIRM_TIME:
				body.sleeping = true
		else:
			body.reset_sleep_timer()

func _run_collision_phase() -> void:
	var pairs: Array = _detector.broadphase(bodies)
	for pair in pairs:
		var result: CollisionDetector.CollisionResult = _detector.narrowphase(pair[0], pair[1])
		if result.colliding:
			_resolver.resolve(result)
			collision_occurred.emit(result.body_a.position)

func _reset_accelerations() -> void:
	for body in bodies:
		if body.active:
			body.acceleration = Vector2.ZERO

func _should_integrate_body(body: SimBody) -> bool:
	return body.active and not body.sleeping and not body.kinematic

func _rebuild_dominant_bh_cache() -> void:
	_dominant_bh_cache.clear()
	var black_holes: Array = get_black_holes()
	if black_holes.is_empty():
		return
	for body in bodies:
		if not _requires_black_hole_adaptive_integration(body):
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
			if body.last_dominant_bh_id >= 0 and body.last_dominant_bh_id != best_bh.id:
				body.dominant_bh_handoff_count += 1
			body.last_dominant_bh_id = best_bh.id
			var safe_distance: float = maxf(best_dist, best_bh.radius + body.radius)
			var orbital_timescale: float = 0.0
			if best_bh.mass > 0.0:
				orbital_timescale = sqrt(
					(safe_distance * safe_distance * safe_distance) / (SimConstants.G * best_bh.mass)
				)
			_dominant_bh_cache[body.id] = {
				"dominant_bh": best_bh,
				"distance": best_dist,
				"orbital_timescale": orbital_timescale,
			}
		else:
			body.last_dominant_bh_id = -1

func _determine_black_hole_adaptive_substeps(sim_dt: float) -> int:
	if sim_dt <= 0.0 or _dominant_bh_cache.is_empty():
		return 1
	var required_substeps: int = 1
	for body in bodies:
		if not _requires_black_hole_adaptive_integration(body):
			continue
		if not _dominant_bh_cache.has(body.id):
			continue
		var entry: Dictionary = _dominant_bh_cache[body.id]
		var orbital_timescale: float = entry["orbital_timescale"]
		if orbital_timescale <= 0.0:
			continue
		var target_dt: float = orbital_timescale * SimConstants.BH_ADAPTIVE_TIMESTEP_FACTOR
		if target_dt <= 0.0:
			continue
		required_substeps = maxi(required_substeps, int(ceil(sim_dt / target_dt)))
	return clampi(required_substeps, 1, SimConstants.BH_ADAPTIVE_MAX_SUBSTEPS)

func _requires_black_hole_adaptive_integration(body: SimBody) -> bool:
	if not body.active or body.sleeping or body.kinematic:
		return false
	return body.body_type in [
		SimBody.BodyType.STAR,
		SimBody.BodyType.PLANET,
		SimBody.BodyType.ASTEROID,
	]

func _update_dynamic_star_host_assignments(sim_dt: float) -> void:
	var black_holes: Array = get_black_holes()
	for body in bodies:
		if body == null or not body.active or body.body_type != SimBody.BodyType.STAR:
			continue
		if not _should_track_dynamic_star_host_assignment(body):
			_clear_pending_dynamic_star_host_assignment(body)
			continue
		if black_holes.is_empty():
			_clear_pending_dynamic_star_host_assignment(body)
			continue
		var anchor_state: Dictionary = ANCHOR_FIELD_SCRIPT.build_star_anchor_state(body, black_holes)
		var candidate_host_id: int = int(anchor_state.get("dominant_bh_id", -1))
		var candidate_host: SimBody = get_body_by_id(candidate_host_id)
		var valid_candidate: bool = candidate_host != null \
			and candidate_host_id != body.orbit_parent_id \
			and float(anchor_state.get("dominance_ratio", 0.0)) >= SimConstants.HOST_HANDOFF_MIN_DOMINANCE_RATIO \
			and bool(anchor_state.get("negative_specific_energy", false))
		if not valid_candidate:
			_clear_pending_dynamic_star_host_assignment(body)
			continue
		if body.pending_host_bh_id != candidate_host_id:
			body.pending_host_bh_id = candidate_host_id
			body.pending_host_time = 0.0
			continue
		body.pending_host_time += sim_dt
		if body.pending_host_time < SimConstants.HOST_HANDOFF_MIN_DURATION:
			continue
		body.orbit_parent_id = candidate_host_id
		body.confirmed_host_handoff_count += 1
		_clear_pending_dynamic_star_host_assignment(body)

func _should_track_dynamic_star_host_assignment(body: SimBody) -> bool:
	return body.active \
		and body.body_type == SimBody.BodyType.STAR \
		and body.orbit_binding_state == SimBody.OrbitBindingState.FREE_DYNAMIC \
		and not body.kinematic

func _clear_pending_dynamic_star_host_assignment(body: SimBody) -> void:
	body.pending_host_bh_id = -1
	body.pending_host_time = 0.0

func _handle_black_hole_segment_impacts(body: SimBody, previous_position: Vector2, black_holes: Array) -> void:
	if black_holes.is_empty():
		return
	# BH runtime hard rule: only true geometric impacts remove bodies.
	# Near-passes are left to raw gravity plus adaptive substeps.
	var hit: Dictionary = _find_black_hole_segment_hit(body, previous_position, body.position, black_holes)
	if hit.is_empty():
		return
	body.position = hit["position"]
	body.velocity = Vector2.ZERO
	mark_body_for_removal_with_analytic_dependents(body)
	collision_occurred.emit(body.position)

func _find_black_hole_segment_hit(body: SimBody, start: Vector2, finish: Vector2, black_holes: Array) -> Dictionary:
	var best_hit: Dictionary = {}
	var best_t: float = INF
	for black_hole in black_holes:
		if black_hole == null or not black_hole.active:
			continue
		var hit_radius: float = black_hole.radius + body.radius
		var hit: Dictionary = _first_segment_circle_hit(start, finish, black_hole.position, hit_radius)
		if hit.is_empty():
			continue
		var hit_t: float = hit["t"]
		if hit_t < best_t:
			best_t = hit_t
			best_hit = hit
	return best_hit

func _first_segment_circle_hit(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> Dictionary:
	var radius_sq: float = radius * radius
	var start_offset: Vector2 = start - center
	if start_offset.length_squared() <= radius_sq:
		return {
			"t": 0.0,
			"position": start,
		}

	var segment: Vector2 = finish - start
	var a: float = segment.length_squared()
	if a <= 0.000001:
		return {}

	var b: float = 2.0 * start_offset.dot(segment)
	var c: float = start_offset.length_squared() - radius_sq
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return {}

	var sqrt_disc: float = sqrt(discriminant)
	var denom: float = 2.0 * a
	var t0: float = (-b - sqrt_disc) / denom
	var t1: float = (-b + sqrt_disc) / denom
	var hit_t: float = INF
	if t0 >= 0.0 and t0 <= 1.0:
		hit_t = t0
	elif t1 >= 0.0 and t1 <= 1.0:
		hit_t = t1
	if hit_t == INF:
		return {}

	return {
		"t": hit_t,
		"position": start + segment * hit_t,
	}

func _update_scripted_orbiters(sim_dt: float) -> void:
	for body in bodies:
		if not body.active or not body.is_analytic_orbit_bound():
			continue
		var parent: SimBody = _find_body_by_id(body.orbit_parent_id)
		if parent == null or not parent.active:
			_remove_orphaned_analytic_orbiter(body)
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

func _remove_orphaned_analytic_orbiter(body: SimBody) -> void:
	if body == null:
		return
	_mark_body_for_removal(body)

func mark_body_for_removal_with_analytic_dependents(body: SimBody) -> void:
	if body == null:
		return
	var pending_parent_ids: Array = [body.id]
	var queued_parent_ids: Dictionary = {body.id: true}
	while not pending_parent_ids.is_empty():
		var parent_id: int = int(pending_parent_ids.pop_back())
		for candidate in bodies:
			if candidate == null or not candidate.active or not candidate.is_analytic_orbit_bound():
				continue
			if candidate.orbit_parent_id != parent_id:
				continue
			_mark_body_for_removal(candidate)
			if not queued_parent_ids.has(candidate.id):
				pending_parent_ids.append(candidate.id)
				queued_parent_ids[candidate.id] = true
	_mark_body_for_removal(body)

func _mark_body_for_removal(body: SimBody) -> void:
	if body == null:
		return
	body.active = false
	body.marked_for_removal = true
	body.scripted_orbit_enabled = false
	body.orbit_parent_id = -1
	body.orbit_center = body.position
	body.sleeping = false
	body.sleep_timer = 0.0

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
