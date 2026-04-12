## Deterministic sector-based worldgen that feeds GalaxyState with region
## descriptors and cluster candidates. It describes the universe everywhere,
## while runtime decides what gets materialized locally.
class_name GalaxyWorldgen
extends RefCounted

const REGION_DESCRIPTOR_SCRIPT := preload("res://simulation/galaxy_region_descriptor.gd")
const CANDIDATE_DESCRIPTOR_SCRIPT := preload("res://simulation/cluster_candidate_descriptor.gd")
const WORLDGEN_MAPPING_SCRIPT := preload("res://simulation/galaxy_worldgen_mapping.gd")
const WORLDGEN_CONFIG_SCRIPT := preload("res://simulation/galaxy_worldgen_config.gd")

const MAX_CLUSTER_CANDIDATES_PER_SECTOR_V1: int = 3
const SECTOR_ID_OFFSET: int = 524_288
const SECTOR_ID_RANGE: int = 1_048_576
const STARTER_FALLBACK_CANDIDATE_INDEX: int = 3

var config = null

func _init(next_config = null) -> void:
	config = next_config.copy() if next_config != null else WORLDGEN_CONFIG_SCRIPT.new()
	config.clamp_values()

func copy():
	return get_script().new(config)

func sector_key(sector_coord: Vector2i) -> String:
	return "%d:%d" % [sector_coord.x, sector_coord.y]

func sector_coord_for_global_position(global_position: Vector2) -> Vector2i:
	var scale: float = maxf(config.sector_scale, 1.0)
	return Vector2i(
		int(floor(global_position.x / scale)),
		int(floor(global_position.y / scale))
	)

func sector_origin(sector_coord: Vector2i) -> Vector2:
	return Vector2(float(sector_coord.x) * config.sector_scale, float(sector_coord.y) * config.sector_scale)

func describe_region(galaxy_seed: int, sector_coord: Vector2i):
	var descriptor := REGION_DESCRIPTOR_SCRIPT.new()
	descriptor.sector_coord = sector_coord
	descriptor.region_seed = _mix_many([
		galaxy_seed,
		sector_coord.x,
		sector_coord.y,
		17_021,
	])

	var region_rng := RandomNumberGenerator.new()
	region_rng.seed = descriptor.region_seed
	var archetype: String = _choose_region_archetype(region_rng)
	var modifiers: Dictionary = WORLDGEN_MAPPING_SCRIPT.archetype_modifiers(archetype)
	var density_noise: float = region_rng.randf_range(-0.14, 0.14)
	var void_noise: float = region_rng.randf_range(-0.12, 0.12)
	var cluster_noise: float = region_rng.randf_range(-0.18, 0.18)
	var bh_noise: float = region_rng.randf_range(-0.12, 0.12)
	var star_noise: float = region_rng.randf_range(-0.12, 0.12)
	var scrap_noise: float = region_rng.randf_range(-0.12, 0.12)
	var life_noise: float = region_rng.randf_range(-0.12, 0.12)

	descriptor.region_archetype = archetype
	descriptor.density = clampf(
		config.cluster_density + density_noise + float(modifiers.get("density", 0.0)),
		0.0,
		1.0
	)
	descriptor.void_strength = clampf(
		config.void_strength + void_noise + float(modifiers.get("void_strength", 0.0)),
		0.0,
		1.0
	)
	descriptor.cluster_chance = clampf(
		WORLDGEN_MAPPING_SCRIPT.base_cluster_chance(config)
			+ cluster_noise
			+ float(modifiers.get("cluster_chance", 0.0)),
		0.0,
		1.0
	)
	descriptor.bh_richness = clampf(
		config.bh_richness + bh_noise + float(modifiers.get("bh_richness", 0.0)),
		0.0,
		1.0
	)
	descriptor.star_richness = clampf(
		config.star_richness + star_noise + float(modifiers.get("star_richness", 0.0)),
		0.0,
		1.0
	)
	descriptor.rare_zone_weight = clampf(
		config.rare_zone_frequency + region_rng.randf_range(-0.08, 0.08),
		0.0,
		1.0
	)
	descriptor.scrap_potential = clampf(
		config.rare_zone_frequency * 0.35
			+ scrap_noise
			+ float(modifiers.get("scrap_potential", 0.0)),
		0.0,
		1.0
	)
	descriptor.life_potential = clampf(
		config.star_richness * 0.45
			+ life_noise
			+ float(modifiers.get("life_potential", 0.0)),
		0.0,
		1.0
	)
	return descriptor

func build_cluster_candidates(
		galaxy_seed: int,
		region_descriptor) -> Array:
	var candidates: Array = []
	if region_descriptor == null:
		return candidates
	for candidate_index in range(MAX_CLUSTER_CANDIDATES_PER_SECTOR_V1):
		var candidate_rng := RandomNumberGenerator.new()
		candidate_rng.seed = _candidate_seed(galaxy_seed, region_descriptor.sector_coord, candidate_index)
		var threshold: float = WORLDGEN_MAPPING_SCRIPT.candidate_slot_threshold(
			region_descriptor,
			candidate_index
		)
		if candidate_rng.randf() > threshold:
			continue
		candidates.append(_build_cluster_candidate(
			galaxy_seed,
			region_descriptor,
			candidate_index,
			candidate_rng,
			candidates
		))
	return candidates

func build_starter_fallback_candidate(galaxy_seed: int):
	var fallback_region = _describe_fallback_region(galaxy_seed)
	var fallback_content_profile: Dictionary = WORLDGEN_MAPPING_SCRIPT.build_minimal_region_content_profile(
		config,
		fallback_region
	)
	var layout_targets: Dictionary = WORLDGEN_MAPPING_SCRIPT.build_candidate_layout_targets(
		config,
		fallback_region,
		fallback_content_profile
	)
	var descriptor := CANDIDATE_DESCRIPTOR_SCRIPT.new()
	descriptor.sector_coord = Vector2i.ZERO
	descriptor.candidate_index = STARTER_FALLBACK_CANDIDATE_INDEX
	descriptor.cluster_id = make_cluster_id(Vector2i.ZERO, STARTER_FALLBACK_CANDIDATE_INDEX)
	descriptor.cluster_seed = _candidate_seed(galaxy_seed, Vector2i.ZERO, STARTER_FALLBACK_CANDIDATE_INDEX)
	descriptor.classification = "starter_fallback_cluster"
	descriptor.region_archetype = "star_nursery"
	descriptor.global_center = Vector2.ZERO
	descriptor.bh_richness = clampf(maxf(config.bh_richness, 0.35), 0.0, 1.0)
	descriptor.star_richness = clampf(maxf(config.star_richness, 0.50), 0.0, 1.0)
	descriptor.rare_zone_weight = config.rare_zone_frequency
	descriptor.scrap_potential = 0.15
	descriptor.life_potential = 0.45
	descriptor.bh_count = 1
	descriptor.bh_spacing_au = maxf(
		float(layout_targets.get("spacing_floor_au", 0.0)),
		WORLDGEN_MAPPING_SCRIPT.candidate_bh_spacing_au(
			config,
			fallback_region,
			0.5,
			fallback_content_profile
		)
	)
	descriptor.radius = maxf(
		(float(fallback_content_profile.get("star_outer_orbit_au", config.star_outer_orbit_au)) + 4.0) * SimConstants.AU,
		WORLDGEN_MAPPING_SCRIPT.candidate_cluster_radius_au(
			config,
			fallback_region,
			descriptor.bh_count,
			descriptor.bh_spacing_au,
			0.5,
			fallback_content_profile
		) * SimConstants.AU
	)
	descriptor.descriptor = {
		"starter_fallback": true,
		"content_profile": fallback_content_profile.duplicate(true),
		"layout_targets": layout_targets.duplicate(true),
	}
	return descriptor

func make_cluster_id(sector_coord: Vector2i, candidate_index: int) -> int:
	var encoded_x: int = sector_coord.x + SECTOR_ID_OFFSET
	var encoded_y: int = sector_coord.y + SECTOR_ID_OFFSET
	if encoded_x < 0 or encoded_x >= SECTOR_ID_RANGE or encoded_y < 0 or encoded_y >= SECTOR_ID_RANGE:
		push_warning("sector coordinate %s exceeds the current V1 packed cluster-id range" % [sector_coord])
	var packed_xy: int = encoded_x * SECTOR_ID_RANGE + encoded_y
	return packed_xy * 4 + candidate_index

func _build_cluster_candidate(
		galaxy_seed: int,
		region_descriptor,
		candidate_index: int,
		candidate_rng: RandomNumberGenerator,
		existing_candidates: Array):
	var descriptor := CANDIDATE_DESCRIPTOR_SCRIPT.new()
	var candidate_seed: int = _candidate_seed(galaxy_seed, region_descriptor.sector_coord, candidate_index)
	var sector_origin_world: Vector2 = sector_origin(region_descriptor.sector_coord)
	var bh_noise: float = candidate_rng.randf()
	var spacing_noise: float = candidate_rng.randf()
	var radius_noise: float = candidate_rng.randf()
	var content_profile: Dictionary = WORLDGEN_MAPPING_SCRIPT.build_minimal_region_content_profile(
		config,
		region_descriptor
	)
	var layout_targets: Dictionary = WORLDGEN_MAPPING_SCRIPT.build_candidate_layout_targets(
		config,
		region_descriptor,
		content_profile
	)

	descriptor.sector_coord = region_descriptor.sector_coord
	descriptor.candidate_index = candidate_index
	descriptor.cluster_id = make_cluster_id(region_descriptor.sector_coord, candidate_index)
	descriptor.cluster_seed = candidate_seed
	descriptor.classification = "%s_cluster" % region_descriptor.region_archetype
	descriptor.region_archetype = region_descriptor.region_archetype
	descriptor.bh_richness = region_descriptor.bh_richness
	descriptor.star_richness = region_descriptor.star_richness
	descriptor.rare_zone_weight = region_descriptor.rare_zone_weight
	descriptor.scrap_potential = region_descriptor.scrap_potential
	descriptor.life_potential = region_descriptor.life_potential
	descriptor.bh_count = WORLDGEN_MAPPING_SCRIPT.candidate_bh_count(
		config,
		region_descriptor,
		bh_noise,
		content_profile
	)
	descriptor.bh_spacing_au = WORLDGEN_MAPPING_SCRIPT.candidate_bh_spacing_au(
		config,
		region_descriptor,
		spacing_noise,
		content_profile
	)
	descriptor.radius = WORLDGEN_MAPPING_SCRIPT.candidate_cluster_radius_au(
		config,
		region_descriptor,
		descriptor.bh_count,
		descriptor.bh_spacing_au,
		radius_noise,
		content_profile
	) * SimConstants.AU
	descriptor.descriptor = {
		"sector_key": sector_key(region_descriptor.sector_coord),
		"sector_padding": _sector_candidate_padding(descriptor.radius),
		"content_profile": content_profile.duplicate(true),
		"layout_targets": layout_targets.duplicate(true),
	}
	var resolved_global_center: Vector2 = _resolve_candidate_global_center(
		sector_origin_world,
		candidate_rng,
		descriptor,
		existing_candidates
	)
	descriptor.global_center = resolved_global_center
	return descriptor

func _resolve_candidate_global_center(
		sector_origin_world: Vector2,
		candidate_rng: RandomNumberGenerator,
		candidate_descriptor,
		existing_candidates: Array) -> Vector2:
	var best_local_position: Vector2 = Vector2.ZERO
	var best_clearance_margin: float = -INF
	for _attempt in range(5):
		var local_position: Vector2 = _sample_candidate_local_center(candidate_rng, candidate_descriptor.radius)
		var clearance_margin: float = _candidate_clearance_margin(
			local_position,
			candidate_descriptor,
			existing_candidates
		)
		if clearance_margin > best_clearance_margin:
			best_clearance_margin = clearance_margin
			best_local_position = local_position
		if clearance_margin >= 0.0:
			break
	return sector_origin_world + best_local_position

func _sample_candidate_local_center(candidate_rng: RandomNumberGenerator, candidate_radius: float) -> Vector2:
	var sector_padding: float = _sector_candidate_padding(candidate_radius)
	return Vector2(
		candidate_rng.randf_range(sector_padding, config.sector_scale - sector_padding),
		candidate_rng.randf_range(sector_padding, config.sector_scale - sector_padding)
	)

func _sector_candidate_padding(candidate_radius: float) -> float:
	return minf(maxf(config.sector_scale * 0.16, candidate_radius * 0.30), config.sector_scale * 0.42)

func _candidate_clearance_margin(local_position: Vector2, candidate_descriptor, existing_candidates: Array) -> float:
	var best_margin: float = INF
	for existing_candidate in existing_candidates:
		if existing_candidate == null:
			continue
		var existing_local_position: Vector2 = existing_candidate.global_center - sector_origin(existing_candidate.sector_coord)
		var required_distance: float = _candidate_clearance_distance(candidate_descriptor, existing_candidate)
		var margin: float = local_position.distance_to(existing_local_position) - required_distance
		best_margin = minf(best_margin, margin)
	if best_margin == INF:
		return 0.0
	return best_margin

func _candidate_clearance_distance(candidate_descriptor, other_candidate) -> float:
	# Keep same-sector clusters visually distinct enough that they do not read as
	# one merged local formation during ordinary camera movement.
	var readability_multiplier: float = 1.0 \
		if _candidate_requires_readability_clearance(candidate_descriptor) \
			or _candidate_requires_readability_clearance(other_candidate) \
		else 0.85
	return (candidate_descriptor.radius + other_candidate.radius) * readability_multiplier

func _candidate_requires_readability_clearance(candidate_descriptor) -> bool:
	if candidate_descriptor == null:
		return false
	var descriptor_metadata: Dictionary = candidate_descriptor.descriptor if candidate_descriptor != null else {}
	var layout_targets_variant = descriptor_metadata.get("layout_targets", {})
	if layout_targets_variant is Dictionary and layout_targets_variant.has("readability_clearance"):
		return bool(layout_targets_variant.get("readability_clearance", false))
	var content_profile_variant = descriptor_metadata.get("content_profile", {})
	if content_profile_variant is Dictionary:
		return WORLDGEN_MAPPING_SCRIPT.is_star_bearing_content_profile(content_profile_variant) \
			or WORLDGEN_MAPPING_SCRIPT.is_spawn_relevant_content_profile(content_profile_variant)
	return false

func _describe_fallback_region(galaxy_seed: int):
	var descriptor := REGION_DESCRIPTOR_SCRIPT.new()
	descriptor.sector_coord = Vector2i.ZERO
	descriptor.region_seed = _mix_many([galaxy_seed, 41_003, 97])
	descriptor.region_archetype = "star_nursery"
	descriptor.density = maxf(config.cluster_density, 0.45)
	descriptor.void_strength = minf(config.void_strength, 0.30)
	descriptor.cluster_chance = 1.0
	descriptor.bh_richness = maxf(config.bh_richness, 0.35)
	descriptor.star_richness = maxf(config.star_richness, 0.55)
	descriptor.rare_zone_weight = config.rare_zone_frequency
	descriptor.scrap_potential = 0.15
	descriptor.life_potential = 0.45
	return descriptor

func _choose_region_archetype(region_rng: RandomNumberGenerator) -> String:
	var weights: Dictionary = WORLDGEN_MAPPING_SCRIPT.archetype_weights(config)
	var total_weight: float = 0.0
	for weight in weights.values():
		total_weight += float(weight)
	var roll: float = region_rng.randf() * total_weight
	var cursor: float = 0.0
	for archetype in ["void", "sparse_relic_cluster", "dense_bh_knot", "star_nursery", "scrap_rich_remnant"]:
		cursor += float(weights.get(archetype, 0.0))
		if roll <= cursor:
			return archetype
	return "void"

func _candidate_seed(galaxy_seed: int, sector_coord: Vector2i, candidate_index: int) -> int:
	return _mix_many([
		galaxy_seed,
		sector_coord.x,
		sector_coord.y,
		candidate_index,
		91_129,
	])

func _mix_many(values: Array) -> int:
	var mixed: int = 1_469_598_103
	for value in values:
		mixed = _mix_ints(mixed, int(value))
	return absi(mixed)

func _mix_ints(lhs: int, rhs: int) -> int:
	var mixed: int = lhs
	mixed ^= rhs + 0x9e3779b9 + (mixed << 6) + (mixed >> 2)
	return mixed
