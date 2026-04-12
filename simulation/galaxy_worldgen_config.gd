## Canonical public description of the procedural universe.
## This config feeds the deterministic sector worldgen and keeps any remaining
## legacy builder hints explicitly quarantined as internal compatibility data.
class_name GalaxyWorldgenConfig
extends RefCounted

var sector_scale: float = SimConstants.DEFAULT_WORLDGEN_SECTOR_SCALE
var cluster_density: float = SimConstants.DEFAULT_WORLDGEN_CLUSTER_DENSITY
var void_strength: float = SimConstants.DEFAULT_WORLDGEN_VOID_STRENGTH
var bh_richness: float = SimConstants.DEFAULT_WORLDGEN_BH_RICHNESS
var star_richness: float = SimConstants.DEFAULT_WORLDGEN_STAR_RICHNESS
var rare_zone_frequency: float = SimConstants.DEFAULT_WORLDGEN_RARE_ZONE_FREQUENCY

var black_hole_mass: float = 12_000_000.0
var star_inner_orbit_au: float = 4.0
var star_outer_orbit_au: float = 20.0
var spawn_radius_au: float = 3.2
var spawn_spread_au: float = 0.8
var inflow_speed_scale: float = 0.85
var tangential_bias: float = 0.65
var chaos_body_count: int = 4

var legacy_generation_hints_enabled: bool = false
var legacy_anchor_topology: int = 2
var legacy_black_hole_count_hint: int = -1
var legacy_galaxy_cluster_count_hint: int = -1
var legacy_field_spacing_au_hint: float = -1.0
var legacy_star_count_hint: int = -1
var legacy_planets_per_star_hint: int = -1
var legacy_disturbance_body_count_hint: int = -1
var legacy_galaxy_cluster_radius_au_hint: float = -1.0
var legacy_galaxy_void_scale_hint: float = -1.0

func copy():
	var duplicate_config = get_script().new()
	duplicate_config.sector_scale = sector_scale
	duplicate_config.cluster_density = cluster_density
	duplicate_config.void_strength = void_strength
	duplicate_config.bh_richness = bh_richness
	duplicate_config.star_richness = star_richness
	duplicate_config.rare_zone_frequency = rare_zone_frequency
	duplicate_config.black_hole_mass = black_hole_mass
	duplicate_config.star_inner_orbit_au = star_inner_orbit_au
	duplicate_config.star_outer_orbit_au = star_outer_orbit_au
	duplicate_config.spawn_radius_au = spawn_radius_au
	duplicate_config.spawn_spread_au = spawn_spread_au
	duplicate_config.inflow_speed_scale = inflow_speed_scale
	duplicate_config.tangential_bias = tangential_bias
	duplicate_config.chaos_body_count = chaos_body_count
	duplicate_config.legacy_generation_hints_enabled = legacy_generation_hints_enabled
	duplicate_config.legacy_anchor_topology = legacy_anchor_topology
	duplicate_config.legacy_black_hole_count_hint = legacy_black_hole_count_hint
	duplicate_config.legacy_galaxy_cluster_count_hint = legacy_galaxy_cluster_count_hint
	duplicate_config.legacy_field_spacing_au_hint = legacy_field_spacing_au_hint
	duplicate_config.legacy_star_count_hint = legacy_star_count_hint
	duplicate_config.legacy_planets_per_star_hint = legacy_planets_per_star_hint
	duplicate_config.legacy_disturbance_body_count_hint = legacy_disturbance_body_count_hint
	duplicate_config.legacy_galaxy_cluster_radius_au_hint = legacy_galaxy_cluster_radius_au_hint
	duplicate_config.legacy_galaxy_void_scale_hint = legacy_galaxy_void_scale_hint
	return duplicate_config

func clamp_values() -> void:
	sector_scale = clampf(
		sector_scale,
		SimConstants.MIN_WORLDGEN_SECTOR_SCALE,
		SimConstants.MAX_WORLDGEN_SECTOR_SCALE
	)
	cluster_density = clampf(cluster_density, 0.0, SimConstants.MAX_WORLDGEN_NORMALIZED_PARAM)
	void_strength = clampf(void_strength, 0.0, SimConstants.MAX_WORLDGEN_NORMALIZED_PARAM)
	bh_richness = clampf(bh_richness, 0.0, SimConstants.MAX_WORLDGEN_NORMALIZED_PARAM)
	star_richness = clampf(star_richness, 0.0, SimConstants.MAX_WORLDGEN_NORMALIZED_PARAM)
	rare_zone_frequency = clampf(rare_zone_frequency, 0.0, SimConstants.MAX_WORLDGEN_NORMALIZED_PARAM)
	black_hole_mass = clampf(black_hole_mass, 2_000_000.0, 30_000_000.0)
	star_inner_orbit_au = clampf(star_inner_orbit_au, 3.5, SimConstants.MAX_STAR_INNER_ORBIT_AU)
	star_outer_orbit_au = clampf(star_outer_orbit_au, 6.0, SimConstants.MAX_STAR_OUTER_ORBIT_AU)
	star_outer_orbit_au = maxf(star_outer_orbit_au, star_inner_orbit_au + 0.5)
	spawn_radius_au = clampf(spawn_radius_au, 2.5, 12.0)
	spawn_spread_au = clampf(spawn_spread_au, 0.0, 4.0)
	inflow_speed_scale = clampf(inflow_speed_scale, 0.05, 3.0)
	tangential_bias = clampf(tangential_bias, 0.0, 1.0)
	chaos_body_count = clampi(chaos_body_count, 1, 12)
	if legacy_black_hole_count_hint >= 0:
		legacy_black_hole_count_hint = clampi(legacy_black_hole_count_hint, 1, SimConstants.MAX_GALAXY_BLACK_HOLES)
	if legacy_galaxy_cluster_count_hint >= 0:
		legacy_galaxy_cluster_count_hint = clampi(legacy_galaxy_cluster_count_hint, 1, SimConstants.MAX_GALAXY_CLUSTER_COUNT)
	if legacy_field_spacing_au_hint >= 0.0:
		legacy_field_spacing_au_hint = clampf(legacy_field_spacing_au_hint, 6.0, SimConstants.MAX_FIELD_PATCH_SPACING_AU)
	if legacy_star_count_hint >= 0:
		legacy_star_count_hint = clampi(legacy_star_count_hint, 0, SimConstants.MAX_START_STAR_COUNT)
	if legacy_planets_per_star_hint >= 0:
		legacy_planets_per_star_hint = clampi(legacy_planets_per_star_hint, 0, SimConstants.MAX_PLANETS_PER_STAR)
	if legacy_disturbance_body_count_hint >= 0:
		legacy_disturbance_body_count_hint = clampi(legacy_disturbance_body_count_hint, 0, SimConstants.MAX_DISTURBANCE_BODY_COUNT)
	if legacy_galaxy_cluster_radius_au_hint >= 0.0:
		legacy_galaxy_cluster_radius_au_hint = clampf(
			legacy_galaxy_cluster_radius_au_hint,
			1.0,
			SimConstants.MAX_GALAXY_CLUSTER_RADIUS_AU
		)
	if legacy_galaxy_void_scale_hint >= 0.0:
		legacy_galaxy_void_scale_hint = clampf(
			legacy_galaxy_void_scale_hint,
			2.0,
			SimConstants.MAX_GALAXY_VOID_SCALE
		)
