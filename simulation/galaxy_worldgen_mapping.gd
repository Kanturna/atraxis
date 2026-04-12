## Explicit mapping layer between public worldgen parameters and the internal
## procedural grammar. Keep the actual influence readable here instead of
## scattering magic numbers across builder/runtime code.
class_name GalaxyWorldgenMapping
extends RefCounted

const ANCHOR_FIELD_SCRIPT := preload("res://simulation/anchor_field.gd")
const MATERIAL_PROFILE_KEYS := ["rocky", "icy", "metallic", "mixed"]
const FRIENDLY_SPAWN_ARCHETYPES := [
	"star_nursery",
	"scrap_rich_remnant",
	"sparse_relic_cluster",
]
const HOSTILE_CLUSTER_ARCHETYPES := [
	"dense_bh_knot",
	"void",
]

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
		noise: float,
		content_profile: Dictionary = {}) -> int:
	var resolved_content_profile: Dictionary = content_profile \
		if not content_profile.is_empty() \
		else build_minimal_region_content_profile(config, region_descriptor)
	var richness: float = clampf(region_descriptor.bh_richness, 0.0, 1.0)
	var max_count: int = candidate_bh_count_cap_for_archetype(region_descriptor.region_archetype)
	var count_from_richness: float = lerpf(1.0, float(max_count), richness)
	if config.legacy_generation_hints_enabled and config.legacy_black_hole_count_hint > 0:
		count_from_richness = lerpf(
			count_from_richness,
			minf(float(config.legacy_black_hole_count_hint), 18.0),
			0.55
		)
	var bh_count: int = clampi(int(round(count_from_richness + noise * 1.5)), 1, max_count)
	var layout_targets: Dictionary = build_candidate_layout_targets(
		config,
		region_descriptor,
		resolved_content_profile
	)
	return mini(
		bh_count,
		candidate_safe_bh_count_cap(
			region_descriptor,
			resolved_content_profile,
			layout_targets,
			max_count
		)
	)

static func candidate_bh_spacing_au(
		config,
		region_descriptor,
		noise: float,
		content_profile: Dictionary = {}) -> float:
	var richness: float = clampf(region_descriptor.bh_richness, 0.0, 1.0)
	var resolved_content_profile: Dictionary = content_profile \
		if not content_profile.is_empty() \
		else build_minimal_region_content_profile(config, region_descriptor)
	var layout_targets: Dictionary = build_candidate_layout_targets(
		config,
		region_descriptor,
		resolved_content_profile
	)
	var base_spacing: float = lerpf(
		14.0,
		8.0,
		richness
	) if is_spawn_friendly_archetype(region_descriptor.region_archetype) else lerpf(11.5, 5.0, richness)
	base_spacing += lerpf(-1.0, 1.2, noise)
	if config.legacy_generation_hints_enabled and config.legacy_field_spacing_au_hint >= 0.0:
		base_spacing = lerpf(base_spacing, config.legacy_field_spacing_au_hint, 0.35)
	base_spacing = clampf(base_spacing, 3.5, SimConstants.MAX_FIELD_PATCH_SPACING_AU)
	return maxf(base_spacing, float(layout_targets.get("spacing_floor_au", 0.0)))

static func candidate_cluster_radius_au(
		config,
		region_descriptor,
		bh_count: int,
		bh_spacing_au: float,
		noise: float,
		content_profile: Dictionary = {}) -> float:
	var density: float = clampf(region_descriptor.density, 0.0, 1.0)
	var resolved_content_profile: Dictionary = content_profile \
		if not content_profile.is_empty() \
		else build_minimal_region_content_profile(config, region_descriptor)
	var layout_targets: Dictionary = build_candidate_layout_targets(
		config,
		region_descriptor,
		resolved_content_profile
	)
	var star_outer_au: float = float(resolved_content_profile.get("star_outer_orbit_au", config.star_outer_orbit_au))
	var spacing_floor_au: float = float(layout_targets.get("spacing_floor_au", bh_spacing_au))
	var realized_spacing_au: float = maxf(bh_spacing_au, spacing_floor_au)
	var geometry_radius_floor_au: float = maxf(
		float(layout_targets.get("cluster_radius_floor_au", config.star_outer_orbit_au + 3.0)),
		star_outer_au + 2.0 + float(maxi(bh_count - 1, 0)) * 0.5 * realized_spacing_au
	)
	var local_radius: float = geometry_radius_floor_au
	local_radius += lerpf(1.5, 5.0, density)
	local_radius += lerpf(-1.0, 1.6, noise)
	if config.legacy_generation_hints_enabled and config.legacy_galaxy_cluster_radius_au_hint >= 0.0:
		local_radius = lerpf(local_radius, config.legacy_galaxy_cluster_radius_au_hint * 4.0, 0.40)
	return maxf(local_radius, geometry_radius_floor_au)

static func candidate_star_count(config, candidate_descriptor) -> int:
	return int(build_cluster_content_profile(config, candidate_descriptor).get("star_count", 0))

static func candidate_planets_per_star(config, candidate_descriptor) -> int:
	return int(build_cluster_content_profile(config, candidate_descriptor).get("planets_per_star", 0))

static func candidate_disturbance_count(config, candidate_descriptor) -> int:
	return int(build_cluster_content_profile(config, candidate_descriptor).get("disturbance_body_count", 0))

static func build_cluster_content_profile(config, candidate_descriptor) -> Dictionary:
	return _build_content_profile(
		config,
		str(candidate_descriptor.region_archetype),
		clampf(candidate_descriptor.star_richness, 0.0, 1.0),
		clampf(candidate_descriptor.bh_richness, 0.0, 1.0),
		clampf(candidate_descriptor.scrap_potential, 0.0, 1.0),
		clampf(candidate_descriptor.life_potential, 0.0, 1.0)
	)

static func build_minimal_region_content_profile(config, region_descriptor) -> Dictionary:
	return _build_content_profile(
		config,
		str(region_descriptor.region_archetype),
		clampf(region_descriptor.star_richness, 0.0, 1.0),
		clampf(region_descriptor.bh_richness, 0.0, 1.0),
		clampf(region_descriptor.scrap_potential, 0.0, 1.0),
		clampf(region_descriptor.life_potential, 0.0, 1.0)
	)

static func build_candidate_layout_targets(
		config,
		region_descriptor,
		content_profile: Dictionary) -> Dictionary:
	var archetype: String = str(region_descriptor.region_archetype)
	var dominance_radius_au: float = dominance_radius_au_for_config(config)
	var reserved_start_band_au: float = maxf(
		float(content_profile.get("star_inner_orbit_au", config.star_inner_orbit_au)),
		float(config.spawn_radius_au) + float(config.spawn_spread_au)
	)
	var star_outer_orbit_au: float = float(content_profile.get("star_outer_orbit_au", config.star_outer_orbit_au))
	var spawn_relevant: bool = is_spawn_relevant_content_profile(content_profile)
	var star_bearing: bool = is_star_bearing_content_profile(content_profile)
	var readability_clearance: bool = star_bearing or spawn_relevant
	var friendly_spacing_floor_au: float = maxf(dominance_radius_au * 1.15, reserved_start_band_au)
	var hostile_spacing_floor_au: float = dominance_radius_au
	var spacing_floor_au: float = friendly_spacing_floor_au \
		if prefers_clear_spawn_geometry(archetype, content_profile) \
		else hostile_spacing_floor_au
	var cluster_radius_floor_au: float = maxf(
		star_outer_orbit_au + 2.0,
		reserved_start_band_au + 1.0
	)
	return {
		"dominance_radius_au": dominance_radius_au,
		"reserved_start_band_au": reserved_start_band_au,
		"friendly_spacing_floor_au": friendly_spacing_floor_au,
		"hostile_spacing_floor_au": hostile_spacing_floor_au,
		"spacing_floor_au": spacing_floor_au,
		"cluster_radius_floor_au": cluster_radius_floor_au,
		"spawn_relevant": spawn_relevant,
		"star_bearing": star_bearing,
		"readability_clearance": readability_clearance,
		"prefers_clear_spawn_geometry": prefers_clear_spawn_geometry(archetype, content_profile),
	}

static func dominance_radius_au_for_config(config) -> float:
	if config == null:
		return 0.0
	return ANCHOR_FIELD_SCRIPT.dominance_radius_for_mass(float(config.black_hole_mass)) / SimConstants.AU

static func is_spawn_friendly_archetype(archetype: String) -> bool:
	return FRIENDLY_SPAWN_ARCHETYPES.has(archetype)

static func is_hostile_cluster_archetype(archetype: String) -> bool:
	return HOSTILE_CLUSTER_ARCHETYPES.has(archetype)

static func is_spawn_relevant_content_profile(content_profile: Dictionary) -> bool:
	return int(content_profile.get("spawn_priority", 0)) > 0

static func is_star_bearing_content_profile(content_profile: Dictionary) -> bool:
	return int(content_profile.get("star_count", 0)) > 0

static func prefers_clear_spawn_geometry(archetype: String, content_profile: Dictionary) -> bool:
	return not is_hostile_cluster_archetype(archetype) \
		and (is_star_bearing_content_profile(content_profile) or is_spawn_relevant_content_profile(content_profile))

static func candidate_bh_count_cap_for_archetype(archetype: String) -> int:
	match archetype:
		"star_nursery":
			return 3
		"scrap_rich_remnant":
			return 4
		"sparse_relic_cluster":
			return 3
		"void":
			return 3
		"dense_bh_knot":
			return 12
		_:
			return 8

static func candidate_safe_bh_count_cap(
		region_descriptor,
		content_profile: Dictionary,
		layout_targets: Dictionary,
		default_cap: int) -> int:
	if not bool(layout_targets.get("prefers_clear_spawn_geometry", false)):
		return default_cap
	var spacing_floor_au: float = maxf(float(layout_targets.get("spacing_floor_au", 0.0)), 1.0)
	var cluster_radius_floor_au: float = float(layout_targets.get("cluster_radius_floor_au", 0.0))
	var reserved_start_band_au: float = float(layout_targets.get("reserved_start_band_au", 0.0))
	var geometry_budget_au: float = maxf(cluster_radius_floor_au - reserved_start_band_au, 0.0)
	var additional_slots: int = maxi(
		int(floor(geometry_budget_au / maxf(spacing_floor_au * 0.75, 1.0))),
		0
	)
	var safe_cap: int = clampi(2 + additional_slots, 1, default_cap)
	return mini(safe_cap, candidate_bh_count_cap_for_archetype(str(region_descriptor.region_archetype)))

static func _build_content_profile(
		config,
		archetype: String,
		star_signal: float,
		bh_signal: float,
		scrap_signal: float,
		life_signal: float) -> Dictionary:
	var base_inner: float = clampf(config.star_inner_orbit_au, 3.5, SimConstants.MAX_STAR_INNER_ORBIT_AU)
	var base_outer: float = maxf(
		base_inner + 0.5,
		clampf(config.star_outer_orbit_au, 6.0, SimConstants.MAX_STAR_OUTER_ORBIT_AU)
	)
	var content_profile := {
		"content_archetype": archetype,
		"spawn_priority": _spawn_priority_for_archetype(archetype),
		"star_count": 0,
		"planets_per_star": 0,
		"disturbance_body_count": 0,
		"star_inner_orbit_au": base_inner,
		"star_outer_orbit_au": base_outer,
		"star_mass_scale_min": 0.85,
		"star_mass_scale_max": 1.15,
		"planet_temperature_offset": 0.0,
		"planet_material_profile": _material_profile(0.25, 0.25, 0.25, 0.25),
		"disturbance_eccentricity_min": 0.03,
		"disturbance_eccentricity_max": 0.18,
		"disturbance_material_profile": _material_profile(0.25, 0.25, 0.25, 0.25),
		"scrap_marker_count": 0,
		"scrap_marker_layout": "none",
	}

	match archetype:
		"void":
			content_profile["star_count"] = clampi(int(round(lerpf(1.0, 2.0, star_signal * 0.25))), 1, 2)
			content_profile["planets_per_star"] = clampi(int(round(lerpf(0.0, 1.0, life_signal * 0.70))), 0, 1)
			content_profile["disturbance_body_count"] = clampi(int(round(lerpf(0.0, 1.0, scrap_signal * 0.30))), 0, 1)
			content_profile["star_inner_orbit_au"] = base_inner * 1.50
			content_profile["star_outer_orbit_au"] = base_outer * 1.35
			content_profile["star_mass_scale_min"] = 0.70
			content_profile["star_mass_scale_max"] = 0.98
			content_profile["planet_temperature_offset"] = -75.0
			content_profile["planet_material_profile"] = _material_profile(0.05, 0.55, 0.05, 0.35)
			content_profile["disturbance_eccentricity_min"] = 0.02
			content_profile["disturbance_eccentricity_max"] = 0.10
			content_profile["disturbance_material_profile"] = _material_profile(0.10, 0.45, 0.10, 0.35)
		"sparse_relic_cluster":
			content_profile["star_count"] = clampi(int(round(lerpf(1.0, 2.0, star_signal * 0.85))), 1, 2)
			content_profile["planets_per_star"] = clampi(int(round(lerpf(1.0, 2.0, life_signal * 0.80))), 1, 2)
			content_profile["disturbance_body_count"] = clampi(int(round(lerpf(1.0, 3.0, scrap_signal * 0.85))), 1, 3)
			content_profile["star_inner_orbit_au"] = base_inner * 1.15
			content_profile["star_outer_orbit_au"] = base_outer * 0.95
			content_profile["star_mass_scale_min"] = 0.82
			content_profile["star_mass_scale_max"] = 1.08
			content_profile["planet_temperature_offset"] = -35.0
			content_profile["planet_material_profile"] = _material_profile(0.10, 0.30, 0.40, 0.20)
			content_profile["disturbance_eccentricity_min"] = 0.08
			content_profile["disturbance_eccentricity_max"] = 0.20
			content_profile["disturbance_material_profile"] = _material_profile(0.10, 0.20, 0.50, 0.20)
			content_profile["scrap_marker_count"] = clampi(int(round(lerpf(4.0, 6.0, scrap_signal))), 4, 6)
			content_profile["scrap_marker_layout"] = "relic_shell"
		"dense_bh_knot":
			content_profile["star_count"] = clampi(int(round(lerpf(1.0, 2.0, star_signal * 0.40))), 1, 2)
			content_profile["planets_per_star"] = clampi(int(round(lerpf(0.0, 1.0, life_signal * 0.55))), 0, 1)
			content_profile["disturbance_body_count"] = clampi(int(round(lerpf(1.0, 3.0, bh_signal * 0.80))), 1, 3)
			content_profile["star_inner_orbit_au"] = base_inner * 0.85
			content_profile["star_outer_orbit_au"] = base_outer * 0.65
			content_profile["star_mass_scale_min"] = 0.72
			content_profile["star_mass_scale_max"] = 1.05
			content_profile["planet_temperature_offset"] = 95.0
			content_profile["planet_material_profile"] = _material_profile(0.25, 0.05, 0.40, 0.30)
			content_profile["disturbance_eccentricity_min"] = 0.18
			content_profile["disturbance_eccentricity_max"] = 0.42
			content_profile["disturbance_material_profile"] = _material_profile(0.30, 0.05, 0.55, 0.10)
		"star_nursery":
			content_profile["star_count"] = clampi(int(round(lerpf(3.0, 5.0, star_signal))), 3, 5)
			content_profile["planets_per_star"] = clampi(int(round(lerpf(2.0, 5.0, life_signal))), 2, 5)
			content_profile["disturbance_body_count"] = clampi(int(round(lerpf(0.0, 1.0, scrap_signal * 0.35))), 0, 1)
			content_profile["star_inner_orbit_au"] = base_inner * 1.05
			content_profile["star_outer_orbit_au"] = base_outer * 1.18
			content_profile["star_mass_scale_min"] = 0.92
			content_profile["star_mass_scale_max"] = 1.42
			content_profile["planet_temperature_offset"] = 55.0
			content_profile["planet_material_profile"] = _material_profile(0.45, 0.10, 0.10, 0.35)
			content_profile["disturbance_eccentricity_min"] = 0.03
			content_profile["disturbance_eccentricity_max"] = 0.12
			content_profile["disturbance_material_profile"] = _material_profile(0.30, 0.20, 0.10, 0.40)
		"scrap_rich_remnant":
			content_profile["star_count"] = clampi(int(round(lerpf(2.0, 3.0, star_signal * 0.80))), 2, 3)
			content_profile["planets_per_star"] = clampi(int(round(lerpf(1.0, 3.0, life_signal * 0.85))), 1, 3)
			content_profile["disturbance_body_count"] = clampi(int(round(lerpf(3.0, 6.0, scrap_signal))), 3, 6)
			content_profile["star_inner_orbit_au"] = base_inner * 1.02
			content_profile["star_outer_orbit_au"] = base_outer * 1.08
			content_profile["star_mass_scale_min"] = 0.82
			content_profile["star_mass_scale_max"] = 1.18
			content_profile["planet_temperature_offset"] = 10.0
			content_profile["planet_material_profile"] = _material_profile(0.15, 0.10, 0.45, 0.30)
			content_profile["disturbance_eccentricity_min"] = 0.16
			content_profile["disturbance_eccentricity_max"] = 0.36
			content_profile["disturbance_material_profile"] = _material_profile(0.10, 0.05, 0.65, 0.20)
			content_profile["scrap_marker_count"] = clampi(int(round(lerpf(6.0, 9.0, scrap_signal))), 6, 9)
			content_profile["scrap_marker_layout"] = "wreck_band"
		_:
			pass

	if config.legacy_generation_hints_enabled and config.legacy_star_count_hint >= 0:
		content_profile["star_count"] = config.legacy_star_count_hint
	if config.legacy_generation_hints_enabled and config.legacy_planets_per_star_hint >= 0:
		content_profile["planets_per_star"] = config.legacy_planets_per_star_hint
	if config.legacy_generation_hints_enabled and config.legacy_disturbance_body_count_hint >= 0:
		content_profile["disturbance_body_count"] = config.legacy_disturbance_body_count_hint

	content_profile["star_inner_orbit_au"] = clampf(
		float(content_profile["star_inner_orbit_au"]),
		3.5,
		SimConstants.MAX_STAR_INNER_ORBIT_AU
	)
	content_profile["star_outer_orbit_au"] = maxf(
		float(content_profile["star_inner_orbit_au"]) + 0.5,
		clampf(float(content_profile["star_outer_orbit_au"]), 6.0, SimConstants.MAX_STAR_OUTER_ORBIT_AU)
	)
	content_profile["star_mass_scale_min"] = clampf(float(content_profile["star_mass_scale_min"]), 0.5, 2.0)
	content_profile["star_mass_scale_max"] = maxf(
		float(content_profile["star_mass_scale_min"]) + 0.02,
		clampf(float(content_profile["star_mass_scale_max"]), 0.52, 2.2)
	)
	content_profile["planet_temperature_offset"] = clampf(float(content_profile["planet_temperature_offset"]), -150.0, 180.0)
	content_profile["disturbance_eccentricity_min"] = clampf(float(content_profile["disturbance_eccentricity_min"]), 0.0, 0.75)
	content_profile["disturbance_eccentricity_max"] = maxf(
		float(content_profile["disturbance_eccentricity_min"]) + 0.01,
		clampf(float(content_profile["disturbance_eccentricity_max"]), 0.02, 0.85)
	)
	content_profile["star_count"] = clampi(int(content_profile["star_count"]), 0, SimConstants.MAX_START_STAR_COUNT)
	content_profile["planets_per_star"] = clampi(int(content_profile["planets_per_star"]), 0, SimConstants.MAX_PLANETS_PER_STAR)
	content_profile["disturbance_body_count"] = clampi(
		int(content_profile["disturbance_body_count"]),
		0,
		SimConstants.MAX_DISTURBANCE_BODY_COUNT
	)
	content_profile["planet_material_profile"] = _normalize_material_profile(content_profile["planet_material_profile"])
	content_profile["disturbance_material_profile"] = _normalize_material_profile(
		content_profile["disturbance_material_profile"]
	)
	content_profile["scrap_marker_count"] = clampi(int(content_profile["scrap_marker_count"]), 0, 12)
	content_profile["scrap_marker_layout"] = str(content_profile["scrap_marker_layout"])
	return content_profile

static func build_scrap_markers(candidate_descriptor, content_profile: Dictionary) -> Array:
	var markers: Array = []
	var marker_count: int = int(content_profile.get("scrap_marker_count", 0))
	var archetype: String = str(content_profile.get("content_archetype", candidate_descriptor.region_archetype))
	if marker_count <= 0:
		return markers

	match archetype:
		"sparse_relic_cluster":
			var shell_count: int = maxi(marker_count - 1, 3)
			markers.append_array(_build_relic_shell_markers(candidate_descriptor, shell_count, 0))
			if marker_count > shell_count:
				markers.append_array(_build_scrap_field_markers(candidate_descriptor, marker_count - shell_count, shell_count))
		"scrap_rich_remnant":
			var band_count: int = maxi(3, int(ceil(float(marker_count) * 0.6)))
			band_count = mini(band_count, marker_count)
			markers.append_array(_build_wreck_band_markers(candidate_descriptor, content_profile, band_count, 0))
			if marker_count > band_count:
				markers.append_array(_build_scrap_field_markers(candidate_descriptor, marker_count - band_count, band_count))
		_:
			pass

	markers.sort_custom(func(a, b): return str(a["marker_id"]) < str(b["marker_id"]))
	return markers

static func _spawn_priority_for_archetype(archetype: String) -> int:
	match archetype:
		"star_nursery":
			return 100
		"scrap_rich_remnant":
			return 80
		"sparse_relic_cluster":
			return 60
		"dense_bh_knot":
			return 15
		"void":
			return 0
		_:
			return 25

static func _material_profile(rocky: float, icy: float, metallic: float, mixed: float) -> Dictionary:
	return _normalize_material_profile({
		"rocky": rocky,
		"icy": icy,
		"metallic": metallic,
		"mixed": mixed,
	})

static func _normalize_material_profile(profile: Dictionary) -> Dictionary:
	var normalized := {
		"rocky": maxf(float(profile.get("rocky", 0.0)), 0.0),
		"icy": maxf(float(profile.get("icy", 0.0)), 0.0),
		"metallic": maxf(float(profile.get("metallic", 0.0)), 0.0),
		"mixed": maxf(float(profile.get("mixed", 0.0)), 0.0),
	}
	var total: float = 0.0
	for key in MATERIAL_PROFILE_KEYS:
		total += float(normalized[key])
	if total <= 0.0:
		return {
			"rocky": 0.25,
			"icy": 0.25,
			"metallic": 0.25,
			"mixed": 0.25,
		}
	for key in MATERIAL_PROFILE_KEYS:
		normalized[key] = float(normalized[key]) / total
	return normalized

static func _build_relic_shell_markers(candidate_descriptor, marker_count: int, marker_offset: int) -> Array:
	var markers: Array = []
	var shell_rng := RandomNumberGenerator.new()
	shell_rng.seed = candidate_descriptor.cluster_seed + 11_701
	var shell_radius: float = candidate_descriptor.radius * 0.82
	for marker_index in range(marker_count):
		var angle: float = ((float(marker_index) + 0.5) / float(marker_count)) * TAU \
			+ shell_rng.randf_range(-0.18, 0.18)
		var radial_scale: float = shell_rng.randf_range(0.94, 1.02)
		var position: Vector2 = Vector2(cos(angle), sin(angle)) * shell_radius * radial_scale
		markers.append(_make_marker(
			marker_offset + marker_index,
			"relic_shell",
			position,
			candidate_descriptor.radius * 0.08,
			shell_rng.randf_range(0.45, 0.72)
		))
	return markers

static func _build_wreck_band_markers(candidate_descriptor, content_profile: Dictionary, marker_count: int, marker_offset: int) -> Array:
	var markers: Array = []
	var band_rng := RandomNumberGenerator.new()
	band_rng.seed = candidate_descriptor.cluster_seed + 29_911
	var orbit_mid_au: float = (
		float(content_profile.get("star_inner_orbit_au", 0.0))
		+ float(content_profile.get("star_outer_orbit_au", 0.0))
	) * 0.5
	var band_radius: float = clampf(
		orbit_mid_au * SimConstants.AU,
		candidate_descriptor.radius * 0.24,
		candidate_descriptor.radius * 0.62
	)
	for marker_index in range(marker_count):
		var angle: float = ((float(marker_index) + 0.35) / float(marker_count)) * TAU \
			+ band_rng.randf_range(-0.14, 0.14)
		var radial_scale: float = band_rng.randf_range(0.90, 1.08)
		var position: Vector2 = Vector2(cos(angle), sin(angle)) * band_radius * radial_scale
		markers.append(_make_marker(
			marker_offset + marker_index,
			"wreck_band",
			position,
			candidate_descriptor.radius * 0.06,
			band_rng.randf_range(0.55, 0.95)
		))
	return markers

static func _build_scrap_field_markers(candidate_descriptor, marker_count: int, marker_offset: int) -> Array:
	var markers: Array = []
	var field_rng := RandomNumberGenerator.new()
	field_rng.seed = candidate_descriptor.cluster_seed + 47_501
	var clump_count: int = clampi(int(ceil(float(marker_count) / 2.0)), 1, 3)
	var clump_centers: Array = []
	for clump_index in range(clump_count):
		var clump_angle: float = ((float(clump_index) + 0.5) / float(clump_count)) * TAU \
			+ field_rng.randf_range(-0.35, 0.35)
		var clump_radius: float = field_rng.randf_range(
			candidate_descriptor.radius * 0.22,
			candidate_descriptor.radius * 0.52
		)
		clump_centers.append(Vector2(cos(clump_angle), sin(clump_angle)) * clump_radius)
	for marker_index in range(marker_count):
		var clump_center: Vector2 = clump_centers[marker_index % clump_centers.size()]
		var jitter_angle: float = field_rng.randf_range(0.0, TAU)
		var jitter_radius: float = field_rng.randf_range(
			candidate_descriptor.radius * 0.03,
			candidate_descriptor.radius * 0.09
		)
		var position: Vector2 = clump_center + Vector2(cos(jitter_angle), sin(jitter_angle)) * jitter_radius
		markers.append(_make_marker(
			marker_offset + marker_index,
			"scrap_field",
			position,
			candidate_descriptor.radius * 0.07,
			field_rng.randf_range(0.40, 0.80)
		))
	return markers

static func _make_marker(marker_index: int, kind: String, local_position: Vector2, radius: float, signal_strength: float) -> Dictionary:
	return {
		"marker_id": "marker_%02d_%s" % [marker_index, kind],
		"kind": kind,
		"local_position": local_position,
		"radius": radius,
		"signal_strength": signal_strength,
	}
