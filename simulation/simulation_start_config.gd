## simulation_start_config.gd
## Small debug-facing start configuration for rebuilding the simulation.
## Stable MVP remains the untouched reference mode; Chaos Inflow is a lab mode.
class_name SimulationStartConfig
extends RefCounted

enum StartMode {
	STABLE_MVP = 0,
	CHAOS_INFLOW = 1,
}

const DEFAULT_SEED: int = 1337
const DEFAULT_SPAWN_RADIUS_AU: float = 3.2
const DEFAULT_SPAWN_SPREAD_AU: float = 0.8
const DEFAULT_INFLOW_SPEED_SCALE: float = 0.85
const DEFAULT_TANGENTIAL_BIAS: float = 0.65
const DEFAULT_BODY_COUNT: int = 4

var mode: int = StartMode.STABLE_MVP
var seed: int = DEFAULT_SEED
var spawn_radius_au: float = DEFAULT_SPAWN_RADIUS_AU
var spawn_spread_au: float = DEFAULT_SPAWN_SPREAD_AU
var inflow_speed_scale: float = DEFAULT_INFLOW_SPEED_SCALE
var tangential_bias: float = DEFAULT_TANGENTIAL_BIAS
var body_count: int = DEFAULT_BODY_COUNT

func copy():
	var config = get_script().new()
	config.mode = mode
	config.seed = seed
	config.spawn_radius_au = spawn_radius_au
	config.spawn_spread_au = spawn_spread_au
	config.inflow_speed_scale = inflow_speed_scale
	config.tangential_bias = tangential_bias
	config.body_count = body_count
	return config

func clamp_values() -> void:
	seed = maxi(seed, 0)
	spawn_radius_au = clampf(spawn_radius_au, 2.5, 12.0)
	spawn_spread_au = clampf(spawn_spread_au, 0.0, 4.0)
	inflow_speed_scale = clampf(inflow_speed_scale, 0.05, 3.0)
	tangential_bias = clampf(tangential_bias, 0.0, 1.0)
	body_count = clampi(body_count, 1, 12)
