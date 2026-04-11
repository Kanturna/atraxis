## anchor_field.gd
## Small helper for Dynamic Anchor topologies with one or more fixed black holes.
## Provides ordered field layouts plus diagnostic helpers for dominant anchors.
class_name AnchorField
extends RefCounted

static func build_field_patch_specs(field_spacing_au: float, mass: float) -> Array:
	var spacing: float = field_spacing_au * SimConstants.AU
	return [
		{
			"id": 0,
			"is_central": true,
			"position": Vector2.ZERO,
			"mass": mass,
		},
		{
			"id": 1,
			"is_central": false,
			"position": Vector2.RIGHT * spacing,
			"mass": mass,
		},
		{
			"id": 2,
			"is_central": false,
			"position": Vector2.DOWN * spacing,
			"mass": mass,
		},
		{
			"id": 3,
			"is_central": false,
			"position": Vector2.LEFT * spacing,
			"mass": mass,
		},
		{
			"id": 4,
			"is_central": false,
			"position": Vector2.UP * spacing,
			"mass": mass,
		},
	]

static func dominance_radius_for_mass(mass: float) -> float:
	if mass <= 0.0 or SimConstants.ANCHOR_DOMINANCE_THRESHOLD <= 0.0:
		return 0.0
	return sqrt((SimConstants.G * mass) / SimConstants.ANCHOR_DOMINANCE_THRESHOLD)

static func rank_black_holes_for_body(body: SimBody, black_holes: Array) -> Array:
	var ranked: Array = []
	for black_hole in black_holes:
		if black_hole == null or not black_hole.active:
			continue
		var delta: Vector2 = black_hole.position - body.position
		var dist_sq: float = delta.length_squared() + SimConstants.GRAVITY_SOFTENING_SQ
		ranked.append({
			"black_hole": black_hole,
			"strength": SimConstants.G * black_hole.mass / dist_sq,
			"distance": delta.length(),
		})
	ranked.sort_custom(func(a, b): return a["strength"] > b["strength"])
	return ranked

static func build_star_anchor_state(star: SimBody, black_holes: Array) -> Dictionary:
	var ranked: Array = rank_black_holes_for_body(star, black_holes)
	if ranked.is_empty():
		return {
			"star_id": star.id,
			"dominant_bh_id": -1,
			"secondary_bh_id": -1,
			"dominance_ratio": 0.0,
			"energy_bound": false,
			"dominant_distance": 0.0,
		}

	var dominant: SimBody = ranked[0]["black_hole"]
	var secondary_id: int = -1
	var secondary_strength: float = 0.0
	if ranked.size() > 1:
		secondary_id = ranked[1]["black_hole"].id
		secondary_strength = ranked[1]["strength"]

	var dominance_ratio: float = 999.0
	if secondary_strength > 0.0:
		dominance_ratio = ranked[0]["strength"] / secondary_strength

	var rel_pos: Vector2 = star.position - dominant.position
	var rel_vel: Vector2 = star.velocity - dominant.velocity
	var distance: float = rel_pos.length()
	var specific_energy: float = 0.0
	if distance > 0.0:
		specific_energy = 0.5 * rel_vel.length_squared() - (SimConstants.G * dominant.mass / distance)

	return {
		"star_id": star.id,
		"dominant_bh_id": dominant.id,
		"secondary_bh_id": secondary_id,
		"dominance_ratio": dominance_ratio,
		# This is only the instantaneous energetic binding status relative to the
		# currently dominant BH. It does not imply any reparenting or capture API.
		"energy_bound": specific_energy < 0.0,
		"dominant_distance": ranked[0]["distance"],
	}
