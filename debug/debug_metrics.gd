## debug_metrics.gd
## Pure debug-side metrics aggregator for the current simulation snapshot.
## Reads SimWorld state without mutating it so values can be tested in isolation.
class_name DebugMetrics
extends RefCounted

func build_snapshot(world: SimWorld, collisions_last_3s: int) -> Dictionary:
	var active_bodies: int = 0
	var dynamic_bodies: int = 0
	var sleeping_bodies: int = 0
	var awake_dynamic_bodies: int = 0
	var fragment_count: int = 0
	var analytic_planets: int = 0
	var radial_deviation_sum: float = 0.0
	var radial_deviation_max: float = 0.0
	var speed_deviation_sum: float = 0.0
	var total_star_mass: float = 0.0
	var bound_stars: int = 0
	var unbound_stars: int = 0
	var min_star_star_distance: float = INF
	var min_star_bh_distance: float = INF
	var black_hole_mass: float = 0.0
	var black_hole: SimBody = world.get_black_hole()
	if black_hole != null:
		black_hole_mass = black_hole.mass

	for body in world.bodies:
		if not body.active:
			continue
		active_bodies += 1

		if body.sleeping:
			sleeping_bodies += 1

		if not body.kinematic:
			dynamic_bodies += 1
			if not body.sleeping:
				awake_dynamic_bodies += 1

		if body.body_type == SimBody.BodyType.FRAGMENT:
			fragment_count += 1

		if body.body_type == SimBody.BodyType.PLANET and body.is_analytic_orbit_bound():
			analytic_planets += 1
			var radial_error: float = abs(body.position.distance_to(body.orbit_center) - body.orbit_radius)
			var expected_speed: float = body.orbit_angular_speed * body.orbit_radius
			var speed_error: float = abs(body.velocity.length() - expected_speed)
			radial_deviation_sum += radial_error
			radial_deviation_max = max(radial_deviation_max, radial_error)
			speed_deviation_sum += speed_error

		if body.body_type == SimBody.BodyType.STAR:
			total_star_mass += body.mass
			if black_hole != null:
				var rel_pos: Vector2 = body.position - black_hole.position
				var rel_vel: Vector2 = body.velocity - black_hole.velocity
				var distance: float = rel_pos.length()
				min_star_bh_distance = minf(min_star_bh_distance, distance)
				if distance > 0.0:
					var specific_energy: float = 0.5 * rel_vel.length_squared() - (SimConstants.G * black_hole.mass / distance)
					if specific_energy < 0.0:
						bound_stars += 1
					else:
						unbound_stars += 1

	var stars: Array = world.get_stars()
	for i in range(stars.size()):
		for j in range(i + 1, stars.size()):
			min_star_star_distance = minf(
				min_star_star_distance,
				stars[i].position.distance_to(stars[j].position)
			)

	var debris_count: int = world.get_active_debris_count()
	var average_radial_deviation: float = 0.0
	var average_speed_deviation: float = 0.0
	if analytic_planets > 0:
		average_radial_deviation = radial_deviation_sum / analytic_planets
		average_speed_deviation = speed_deviation_sum / analytic_planets
	if min_star_star_distance == INF:
		min_star_star_distance = 0.0
	if min_star_bh_distance == INF:
		min_star_bh_distance = 0.0
	var anchor_ratio: float = 0.0
	if total_star_mass > 0.0:
		anchor_ratio = black_hole_mass / total_star_mass

	var collision_pressure: float = clampf(collisions_last_3s / 8.0, 0.0, 1.0)
	var fragment_pressure: float = _safe_ratio(fragment_count, SimConstants.MAX_ACTIVE_FRAGMENTS)
	var debris_pressure: float = _safe_ratio(debris_count, SimConstants.MAX_DEBRIS_FIELDS)
	var awake_dynamic_ratio: float = 0.0
	if dynamic_bodies > 0:
		awake_dynamic_ratio = float(awake_dynamic_bodies) / float(dynamic_bodies)
	var activity_pressure: float = maxf(collision_pressure, maxf(fragment_pressure, debris_pressure))
	var awake_unrest: float = awake_dynamic_ratio * activity_pressure

	var chaos_score: int = int(round(
		100.0 * (
			0.35 * collision_pressure
			+ 0.25 * fragment_pressure
			+ 0.20 * debris_pressure
			+ 0.20 * awake_unrest
		)
	))

	return {
		"simulation": {
			"active_bodies": active_bodies,
			"dynamic_bodies": dynamic_bodies,
			"sleeping_bodies": sleeping_bodies,
			"awake_dynamic_bodies": awake_dynamic_bodies,
			"fragment_count": fragment_count,
			"debris_count": debris_count,
		},
		"orbit": {
			"analytic_planets": analytic_planets,
			"average_radial_deviation": average_radial_deviation,
			"max_radial_deviation": radial_deviation_max,
			"average_speed_deviation": average_speed_deviation,
		},
		"chaos": {
			"collisions_last_3s": collisions_last_3s,
			"collision_pressure": collision_pressure,
			"fragment_pressure": fragment_pressure,
			"debris_pressure": debris_pressure,
			"awake_dynamic_ratio": awake_dynamic_ratio,
			"awake_unrest": awake_unrest,
			"score": chaos_score,
		},
		"anchor": {
			"black_hole_mass": black_hole_mass,
			"total_star_mass": total_star_mass,
			"anchor_ratio": anchor_ratio,
			"bound_stars": bound_stars,
			"unbound_stars": unbound_stars,
			"min_star_star_distance": min_star_star_distance,
			"min_star_bh_distance": min_star_bh_distance,
		},
	}

func _safe_ratio(value: int, max_value: int) -> float:
	if max_value <= 0:
		return 0.0
	return clampf(float(value) / float(max_value), 0.0, 1.0)
