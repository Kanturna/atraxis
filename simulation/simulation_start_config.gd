## Small debug-facing start configuration for rebuilding the simulation.
## Stable Anchor is the calm macro-reference mode; Chaos Inflow is a lab mode.
class_name SimulationStartConfig
extends RefCounted

enum StartMode {
	STABLE_ANCHOR = 0,
	CHAOS_INFLOW = 1,
}

const DEFAULT_SEED: int = 1337
const DEFAULT_SUN_ORBIT_RADIUS_AU: float = 4.0
const DEFAULT_SUN_ORBIT_SPEED_SCALE: float = 1.0
const DEFAULT_CORE_PLANET_COUNT: int = 3
const DEFAULT_DISTURBANCE_BODY_COUNT: int = 6
const DEFAULT_SPAWN_RADIUS_AU: float = 3.2
const DEFAULT_SPAWN_SPREAD_AU: float = 0.8
const DEFAULT_INFLOW_SPEED_SCALE: float = 0.85
const DEFAULT_TANGENTIAL_BIAS: float = 0.65
const DEFAULT_CHAOS_BODY_COUNT: int = 4
const DEFAULT_STAR_COUNT: int = 1
const DEFAULT_PLANETS_PER_STAR: int = 2
const DEFAULT_STAR_INNER_ORBIT_AU: float = 4.0
const DEFAULT_STAR_OUTER_ORBIT_AU: float = 20.0

var mode: int = StartMode.STABLE_ANCHOR
var seed: int = DEFAULT_SEED
var sun_orbit_radius_au: float = DEFAULT_SUN_ORBIT_RADIUS_AU
var sun_orbit_speed_scale: float = DEFAULT_SUN_ORBIT_SPEED_SCALE
var core_planet_count: int = DEFAULT_CORE_PLANET_COUNT
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

func copy():
	var config = get_script().new()
	config.mode = mode
	config.seed = seed
	config.sun_orbit_radius_au = sun_orbit_radius_au
	config.sun_orbit_speed_scale = sun_orbit_speed_scale
	config.core_planet_count = core_planet_count
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
	return config

func clamp_values() -> void:
	seed = maxi(seed, 0)
	sun_orbit_radius_au = clampf(sun_orbit_radius_au, 2.5, 8.0)
	sun_orbit_speed_scale = clampf(sun_orbit_speed_scale, 0.2, 2.0)
	core_planet_count = clampi(core_planet_count, 1, 4)
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
