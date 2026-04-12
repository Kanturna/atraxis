## Explicit mapping layer between public worldgen parameters and the internal
## procedural grammar. Keep the actual influence readable here instead of
## scattering magic numbers across builder/runtime code.
class_name GalaxyWorldgenMapping
extends RefCounted

static func archetype_weights(config) -> Dictionary:
	var density: float = clampf(config.cluster_density, 0.0, 1.0)
	var void_strength: float = clampf(config.void_strength, 0.0, 1.0)
	var bh_richness: float = clampf(config.bh_richness, 0.0, 1.0)
	var star_richness: float = clampf(config.star_richness, 0.0, 1.0)
	var rare: float = clampf(config.rare_zone_frequency, 0.0, 1.0)
	return {
		"void": 0.30 + void_strength * 1.10,
		"sparse_relic_cluster": 0.34 + density * 0.22,
		"dense_bh_knot": 0.18 + density * 0.28 + bh_richness * 0.90 + rare * 0.15,
		"star_nursery": 0.18 + density * 0.24 + star_richness * 0.90 + rare * 0.10,
		"scrap_rich_remnant": 0.12 + rare * 0.80 + density * 0.16,
	}

static func archetype_modifiers(archetype: String) -> Dictionary:
	match archetype:
		"void":
			return {
				"density": -0.45,
				"void_strength": 0.55,
				"cluster_chance": -0.55,
				"bh_richness": -0.35,
				"star_richness": -0.40,
				"scrap_potential": -0.30,
				"life_potential": -0.45,
			}
		"sparse_relic_cluster":
			return {
				"density": -0.08,
				"void_strength": -0.05,
				"cluster_chance": -0.02,
				"bh_richness": 0.10,
				"star_richness": -0.18,
				"scrap_potential": 0.38,
				"life_potential": -0.12,
			}
		"dense_bh_knot":
			return {
				"density": 0.30,
				"void_strength": -0.25,
				"cluster_chance": 0.26,
				"bh_richness": 0.42,
				"star_richness": -0.25,
				"scrap_potential": 0.08,
				"life_potential": -0.28,
			}
		"star_nursery":
			return {
				"density": 0.16,
				"void_strength": -0.16,
				"cluster_chance": 0.14,
				"bh_richness": -0.12,
				"star_richness": 0.42,
				"scrap_potential": 0.02,
				"life_potential": 0.42,
			}
		"scrap_rich_remnant":
			return {
				"density": 0.05,
				"void_strength": -0.08,
				"cluster_chance": 0.06,
				"bh_richness": 0.08,
				"star_richness": 0.05,
				"scrap_potential": 0.55,
				"life_potential": -0.06,
			}
		_:
			return {
				"density": 0.0,
				"void_strength": 0.0,
				"cluster_chance": 0.0,
				"bh_richness": 0.0,
				"star_richness": 0.0,
				"scrap_potential": 0.0,
				"life_potential": 0.0,
			}

static func base_cluster_chance(config) -> float:
	var density: float = clampf(config.cluster_density, 0.0, 1.0)
	var void_strength: float = clampf(config.void_strength, 0.0, 1.0)
	return clampf(0.10 + density * 0.78 - void_strength * 0.52, 0.02, 0.95)

static func candidate_slot_threshold(region_descriptor, candidate_index: int) -> float:
	# V1 only allows up to three cluster candidates per sector. This is an
	# implementation limit for the first readable worldgen pass, not a final
	# world rule.
	var slot_falloff: float = 0.28
	return clampf(
		region_descriptor.cluster_chance - float(candidate_index) * slot_falloff,
		0.0,
		0.98
	)

static func candidate_bh_count(
		config,
		region_descriptor,
		noise: float) -> int:
	var richness: float = clampf(region_descriptor.bh_richness, 0.0, 1.0)
	var count_from_richness: float = lerpf(1.0, 12.0, richness)
	if config.legacy_generation_hints_enabled and config.legacy_black_hole_count_hint > 0:
		count_from_richness = lerpf(
			count_from_richness,
			minf(float(config.legacy_black_hole_count_hint), 18.0),
			0.55
		)
	return clampi(int(round(count_from_richness + noise * 2.0)), 1, 18)

static func candidate_bh_spacing_au(
		config,
		region_descriptor,
		noise: float) -> float:
	var richness: float = clampf(region_descriptor.bh_richness, 0.0, 1.0)
	var base_spacing: float = lerpf(10.5, 4.5, richness)
	base_spacing += lerpf(-1.5, 1.5, noise)
	if config.legacy_generation_hints_enabled and config.legacy_field_spacing_au_hint >= 0.0:
		base_spacing = lerpf(base_spacing, config.legacy_field_spacing_au_hint, 0.45)
	return clampf(base_spacing, 3.5, SimConstants.MAX_FIELD_PATCH_SPACING_AU)

static func candidate_cluster_radius_au(
		config,
		region_descriptor,
		bh_count: int,
		bh_spacing_au: float,
		noise: float) -> float:
	var density: float = clampf(region_descriptor.density, 0.0, 1.0)
	var local_radius: float = bh_spacing_au * (0.8 + float(maxi(bh_count - 1, 0)) * 0.25)
	local_radius += lerpf(4.0, 14.0, density)
	local_radius += lerpf(-2.0, 3.0, noise)
	if config.legacy_generation_hints_enabled and config.legacy_galaxy_cluster_radius_au_hint >= 0.0:
		local_radius = lerpf(local_radius, config.legacy_galaxy_cluster_radius_au_hint * 4.0, 0.40)
	return maxf(local_radius, config.star_outer_orbit_au + 3.0)

static func candidate_star_count(config, candidate_descriptor) -> int:
	if config.legacy_generation_hints_enabled and config.legacy_star_count_hint >= 0:
		return config.legacy_star_count_hint
	var star_richness: float = clampf(candidate_descriptor.star_richness, 0.0, 1.0)
	return clampi(int(round(lerpf(0.0, 5.0, star_richness))), 0, SimConstants.MAX_START_STAR_COUNT)

static func candidate_planets_per_star(config, candidate_descriptor) -> int:
	if config.legacy_generation_hints_enabled and config.legacy_planets_per_star_hint >= 0:
		return config.legacy_planets_per_star_hint
	var planet_richness: float = clampf(
		candidate_descriptor.star_richness * 0.75 + candidate_descriptor.scrap_potential * 0.20,
		0.0,
		1.0
	)
	return clampi(int(round(lerpf(0.0, 6.0, planet_richness))), 0, SimConstants.MAX_PLANETS_PER_STAR)

static func candidate_disturbance_count(config, candidate_descriptor) -> int:
	if config.legacy_generation_hints_enabled and config.legacy_disturbance_body_count_hint >= 0:
		return config.legacy_disturbance_body_count_hint
	var disturbance_signal: float = clampf(
		candidate_descriptor.scrap_potential * 0.70 + candidate_descriptor.bh_richness * 0.20,
		0.0,
		1.0
	)
	return clampi(int(round(lerpf(0.0, 6.0, disturbance_signal))), 0, SimConstants.MAX_DISTURBANCE_BODY_COUNT)
