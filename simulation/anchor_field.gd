## anchor_field.gd
## Small helper for Dynamic Anchor topologies with one or more fixed black holes.
## Provides ordered field layouts plus diagnostic helpers for dominant anchors.
class_name AnchorField
extends RefCounted

static func build_field_patch_specs(total_count: int, field_spacing_au: float, mass: float) -> Array:
	var spacing: float = field_spacing_au * SimConstants.AU
	var safe_total: int = maxi(total_count, 1)
	var specs: Array = [
		{
			"id": 0,
			"is_central": true,
			"ring_index": 0,
			"position": Vector2.ZERO,
			"mass": mass,
		},
	]
	var remaining: int = safe_total - 1
	var ring_index: int = 1
	var next_id: int = 1
	while remaining > 0:
		var slots_in_ring: int = SimConstants.ANCHOR_FIELD_RING_SLOT_SCALE * ring_index
		var used_slots: int = mini(remaining, slots_in_ring)
		var slot_indices: Array = _spread_slot_indices(slots_in_ring, used_slots)
		for slot_index in slot_indices:
			var angle: float = -PI * 0.5 + (TAU * float(slot_index) / float(slots_in_ring))
			specs.append({
				"id": next_id,
				"is_central": false,
				"ring_index": ring_index,
				"position": Vector2(cos(angle), sin(angle)) * (spacing * ring_index),
				"mass": mass,
			})
			next_id += 1
		remaining -= used_slots
		ring_index += 1
	return specs

static func field_ring_count_for_total(total_count: int) -> int:
	var safe_total: int = maxi(total_count, 1)
	var remaining: int = safe_total - 1
	var ring_count: int = 1
	var ring_index: int = 1
	while remaining > 0:
		remaining -= SimConstants.ANCHOR_FIELD_RING_SLOT_SCALE * ring_index
		ring_count += 1
		ring_index += 1
	return ring_count

static func min_black_hole_distance(black_holes: Array) -> float:
	var min_distance: float = INF
	for i in range(black_holes.size()):
		for j in range(i + 1, black_holes.size()):
			min_distance = minf(
				min_distance,
				black_holes[i].position.distance_to(black_holes[j].position)
			)
	if min_distance == INF:
		return 0.0
	return min_distance

static func dominance_radius_for_mass(mass: float) -> float:
	if mass <= 0.0 or SimConstants.ANCHOR_DOMINANCE_THRESHOLD <= 0.0:
		return 0.0
	return sqrt((SimConstants.G * mass) / SimConstants.ANCHOR_DOMINANCE_THRESHOLD)

static func nearfield_radius_for_mass(mass: float) -> float:
	return dominance_radius_for_mass(mass) * SimConstants.BH_NEARFIELD_DISTANCE_FACTOR

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

static func _spread_slot_indices(slot_count: int, used_count: int) -> Array:
	var indices: Array = []
	if used_count >= slot_count:
		for i in range(slot_count):
			indices.append(i)
		return indices
	for i in range(used_count):
		indices.append(int(floor(float(i) * float(slot_count) / float(used_count))))
	return indices
