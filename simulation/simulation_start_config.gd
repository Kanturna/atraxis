## Small debug-facing start configuration for rebuilding the simulation.
## Dynamic Anchor is the main world-evolution mode.
## Stable Anchor is the calm reference mode; Chaos Inflow stays the lab mode.
class_name SimulationStartConfig
extends RefCounted

enum StartMode {
	DYNAMIC_ANCHOR = 0,
	STABLE_ANCHOR = 1,
	CHAOS_INFLOW = 2,
}

enum AnchorTopology {
	CENTRAL_BH = 0,
	FIELD_PATCH = 1,
}

const DEFAULT_SEED: int = 1337
const DEFAULT_BLACK_HOLE_MASS: float = 12_000_000.0
const DEFAULT_DISTURBANCE_BODY_COUNT: int = 4
const DEFAULT_SPAWN_RADIUS_AU: float = 3.2
const DEFAULT_SPAWN_SPREAD_AU: float = 0.8
const DEFAULT_INFLOW_SPEED_SCALE: float = 0.85
const DEFAULT_TANGENTIAL_BIAS: float = 0.65
const DEFAULT_CHAOS_BODY_COUNT: int = 4
const DEFAULT_STAR_COUNT: int = 2
const DEFAULT_PLANETS_PER_STAR: int = 2
const DEFAULT_STAR_INNER_ORBIT_AU: float = 4.0
const DEFAULT_STAR_OUTER_ORBIT_AU: float = 20.0
const DEFAULT_BLACK_HOLE_COUNT: int = 5
const DEFAULT_FIELD_SPACING_AU: float = 9.0

var mode: int = StartMode.DYNAMIC_ANCHOR
var anchor_topology: int = AnchorTopology.CENTRAL_BH
var seed: int = DEFAULT_SEED
var black_hole_mass: float = DEFAULT_BLACK_HOLE_MASS
var disturbance_body_count: int = DEFAULT_DISTURBANCE_BODY_COUNT
var spawn_radius_au: float = DEFAULT_SPAWN_RADIUS_AU
var spawn_spread_au: float = DEFAULT_SPAWN_SPREAD_AU
var inflow_speed_scale: float = DEFAULT_INFLOW_SPEED_SCALE
var tangential_bias: float = DEFAULT_TANGENTIAL_BIAS
var chaos_body_count: int = DEFAULT_CHAOS_BODY_COUNT
var star_count: int = DEFAULT_STAR_COUNT
var planets_per_star: int = DEFAULT_PLANETS_PER_STAR
var star_inner_orbit_au: float = DEFAULT_STAR_INNER_ORBIT_AU
var star_outer_orbit_au: float = DEFAULT_STAR_OUTER_ORBIT_AU
var black_hole_count: int = DEFAULT_BLACK_HOLE_COUNT
var field_spacing_au: float = DEFAULT_FIELD_SPACING_AU

func copy():
	var config = get_script().new()
	config.mode = mode
	config.anchor_topology = anchor_topology
	config.seed = seed
	config.black_hole_mass = black_hole_mass
	config.disturbance_body_count = disturbance_body_count
	config.spawn_radius_au = spawn_radius_au
	config.spawn_spread_au = spawn_spread_au
	config.inflow_speed_scale = inflow_speed_scale
	config.tangential_bias = tangential_bias
	config.chaos_body_count = chaos_body_count
	config.star_count = star_count
	config.planets_per_star = planets_per_star
	config.star_inner_orbit_au = star_inner_orbit_au
	config.star_outer_orbit_au = star_outer_orbit_au
	config.black_hole_count = black_hole_count
	config.field_spacing_au = field_spacing_au
	return config

func clamp_values() -> void:
	seed = maxi(seed, 0)
	# Anchor topologies belong to the Dynamic Anchor mainline only.
	# Other modes intentionally fall back to the central single-BH setup.
	anchor_topology = clampi(anchor_topology, AnchorTopology.CENTRAL_BH, AnchorTopology.FIELD_PATCH)
	black_hole_mass = clampf(black_hole_mass, 2_000_000.0, 30_000_000.0)
	disturbance_body_count = clampi(disturbance_body_count, 0, 8)
	spawn_radius_au = clampf(spawn_radius_au, 2.5, 12.0)
	spawn_spread_au = clampf(spawn_spread_au, 0.0, 4.0)
	inflow_speed_scale = clampf(inflow_speed_scale, 0.05, 3.0)
	tangential_bias = clampf(tangential_bias, 0.0, 1.0)
	chaos_body_count = clampi(chaos_body_count, 1, 12)
	star_count = clampi(star_count, 1, 4)
	planets_per_star = clampi(planets_per_star, 1, 3)
	star_inner_orbit_au = clampf(star_inner_orbit_au, 3.5, 8.0)
	star_outer_orbit_au = clampf(star_outer_orbit_au, 6.0, 40.0)
	star_outer_orbit_au = maxf(star_outer_orbit_au, star_inner_orbit_au + 0.5)
	black_hole_count = clampi(black_hole_count, 1, SimConstants.MAX_FIELD_PATCH_BLACK_HOLES)
	field_spacing_au = clampf(field_spacing_au, 6.0, 20.0)
