## debug_metrics.gd
## Pure debug-side metrics aggregator for the current simulation snapshot.
## Reads SimWorld state without mutating it so values can be tested in isolation.
## Anchor energy metrics are diagnostic only; they do not drive capture logic.
class_name DebugMetrics
extends RefCounted

const ANCHOR_FIELD_SCRIPT := preload("res://simulation/anchor_field.gd")
const CLOSE_STAR_ENCOUNTER_DISTANCE: float = 0.75 * SimConstants.AU

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
	var total_black_hole_mass: float = 0.0
	var negative_specific_energy_stars: int = 0
	var non_negative_specific_energy_stars: int = 0
	var field_ring_count: int = 0
	var min_black_hole_distance: float = 0.0
	var min_star_star_distance: float = INF
	var min_star_bh_distance: float = INF
	var min_star_host_bh_distance: float = INF
	var star_anchor_states: Array = []
	var black_holes: Array = world.get_black_holes()
	var black_hole_by_id: Dictionary = {}
	var stars: Array = world.get_stars()
	var min_other_star_distance_by_id: Dictionary = {}
	var stars_with_host: int = 0
	var host_dominance_match_count: int = 0
	var host_dominance_mismatch_count: int = 0
	var stars_with_dominant_handoffs: int = 0
	var total_dominant_handoffs: int = 0
	var close_star_encounter_count: int = 0
	for black_hole in black_holes:
		total_black_hole_mass += black_hole.mass
		black_hole_by_id[black_hole.id] = black_hole
	field_ring_count = ANCHOR_FIELD_SCRIPT.field_ring_count_for_total(black_holes.size())
	min_black_hole_distance = ANCHOR_FIELD_SCRIPT.min_black_hole_distance(black_holes)
	for star in stars:
		min_other_star_distance_by_id[star.id] = INF
	for i in range(stars.size()):
		for j in range(i + 1, stars.size()):
			var star_distance: float = stars[i].position.distance_to(stars[j].position)
			min_star_star_distance = minf(min_star_star_distance, star_distance)
			min_other_star_distance_by_id[stars[i].id] = minf(
				float(min_other_star_distance_by_id[stars[i].id]),
				star_distance
			)
			min_other_star_distance_by_id[stars[j].id] = minf(
				float(min_other_star_distance_by_id[stars[j].id]),
				star_distance
			)

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
			var anchor_state: Dictionary = ANCHOR_FIELD_SCRIPT.build_star_anchor_state(body, black_holes)
			var host_bh_id: int = -1
			var host_distance: float = 0.0
			if black_hole_by_id.has(body.orbit_parent_id):
				host_bh_id = body.orbit_parent_id
				host_distance = body.position.distance_to(black_hole_by_id[host_bh_id].position)
				stars_with_host += 1
				min_star_host_bh_distance = minf(min_star_host_bh_distance, host_distance)
			var min_other_star_distance: float = float(min_other_star_distance_by_id.get(body.id, INF))
			if min_other_star_distance == INF:
				min_other_star_distance = 0.0
			var dominant_matches_host: bool = host_bh_id >= 0 and host_bh_id == int(anchor_state["dominant_bh_id"])
			if host_bh_id >= 0:
				if dominant_matches_host:
					host_dominance_match_count += 1
				else:
					host_dominance_mismatch_count += 1
			if body.dominant_bh_handoff_count > 0:
				stars_with_dominant_handoffs += 1
			total_dominant_handoffs += body.dominant_bh_handoff_count
			if min_other_star_distance > 0.0 and min_other_star_distance <= CLOSE_STAR_ENCOUNTER_DISTANCE:
				close_star_encounter_count += 1
			anchor_state["host_bh_id"] = host_bh_id
			anchor_state["host_distance"] = host_distance
			anchor_state["dominant_matches_host"] = dominant_matches_host
			anchor_state["dominant_handoff_count"] = body.dominant_bh_handoff_count
			anchor_state["min_other_star_distance"] = min_other_star_distance
			star_anchor_states.append(anchor_state)
			if anchor_state["negative_specific_energy"]:
				negative_specific_energy_stars += 1
			else:
				non_negative_specific_energy_stars += 1
			if anchor_state["dominant_distance"] > 0.0:
				min_star_bh_distance = minf(min_star_bh_distance, anchor_state["dominant_distance"])

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
	if min_star_host_bh_distance == INF:
		min_star_host_bh_distance = 0.0
	var anchor_ratio: float = 0.0
	if total_star_mass > 0.0:
		anchor_ratio = total_black_hole_mass / total_star_mass
	star_anchor_states.sort_custom(func(a, b): return a["star_id"] < b["star_id"])

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
			"black_hole_count": black_holes.size(),
			"field_ring_count": field_ring_count,
			"black_hole_mass": total_black_hole_mass,
			"total_star_mass": total_star_mass,
			"anchor_ratio": anchor_ratio,
			"negative_specific_energy_stars": negative_specific_energy_stars,
			"non_negative_specific_energy_stars": non_negative_specific_energy_stars,
			"min_black_hole_distance": min_black_hole_distance,
			"min_star_star_distance": min_star_star_distance,
			"min_star_bh_distance": min_star_bh_distance,
			"min_star_host_bh_distance": min_star_host_bh_distance,
			"stars_with_host": stars_with_host,
			"host_dominance_match_count": host_dominance_match_count,
			"host_dominance_mismatch_count": host_dominance_mismatch_count,
			"stars_with_dominant_handoffs": stars_with_dominant_handoffs,
			"total_dominant_handoffs": total_dominant_handoffs,
			"close_star_encounter_count": close_star_encounter_count,
			"star_anchor_states": star_anchor_states,
		},
	}

func _safe_ratio(value: int, max_value: int) -> float:
	if max_value <= 0:
		return 0.0
	return clampf(float(value) / float(max_value), 0.0, 1.0)
