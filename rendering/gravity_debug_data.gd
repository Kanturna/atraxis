## gravity_debug_data.gd
## Builds render-ready ring data for debug visualization of stellar gravity.
## The rings represent fixed acceleration thresholds, not physical cutoffs.
class_name GravityDebugData
extends RefCounted

func build_ring_specs(bodies: Array) -> Array:
	var specs: Array = []

	for body in bodies:
		if not _is_debug_star(body):
			continue

		for i in range(SimConstants.GRAVITY_DEBUG_THRESHOLDS.size()):
			var threshold: float = SimConstants.GRAVITY_DEBUG_THRESHOLDS[i]
			var sim_radius: float = radius_from_mass_and_threshold(body.mass, threshold)
			var screen_radius: float = BodyRenderer.sim_dist_to_screen(sim_radius)
			if screen_radius < SimConstants.GRAVITY_DEBUG_MIN_SCREEN_RADIUS:
				continue

			specs.append({
				"body_id": body.id,
				"center": BodyRenderer.sim_to_screen(body.position),
				"sim_radius": sim_radius,
				"screen_radius": screen_radius,
				"threshold": threshold,
				"color": SimConstants.GRAVITY_DEBUG_COLORS[i],
			})

	return specs

func radius_from_mass_and_threshold(mass: float, threshold: float) -> float:
	if mass <= 0.0 or threshold <= 0.0:
		return 0.0
	return sqrt((SimConstants.G * mass) / threshold)

func _is_debug_star(body: SimBody) -> bool:
	return body.active and body.body_type == SimBody.BodyType.STAR
