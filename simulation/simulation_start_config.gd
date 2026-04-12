## Small debug-facing start configuration for rebuilding the simulation.
## The runtime now follows one canonical world path; these values only select
## a generation preset/profile for that shared path.
class_name SimulationStartConfig
extends RefCounted

enum WorldProfile {
	ORBITAL_SANDBOX = 0,
	ORBITAL_REFERENCE = 1,
	INFLOW_LAB = 2,
}

# Backward-compatible alias for older tests/callers while the project converges
# on world-profile language instead of equal-status runtime modes.
enum StartMode {
	DYNAMIC_ANCHOR = WorldProfile.ORBITAL_SANDBOX,
	STABLE_ANCHOR = WorldProfile.ORBITAL_REFERENCE,
	CHAOS_INFLOW = WorldProfile.INFLOW_LAB,
}

enum AnchorTopology {
	CENTRAL_BH = 0,
	FIELD_PATCH = 1,
	GALAXY_CLUSTER = 2,
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
const DEFAULT_GALAXY_CLUSTER_COUNT: int = SimConstants.DEFAULT_GALAXY_CLUSTER_COUNT
const DEFAULT_GALAXY_CLUSTER_RADIUS_AU: float = SimConstants.DEFAULT_GALAXY_CLUSTER_RADIUS_AU
const DEFAULT_GALAXY_VOID_SCALE: float = SimConstants.DEFAULT_GALAXY_VOID_SCALE

var world_profile: int = WorldProfile.ORBITAL_SANDBOX
var mode: int:
	get:
		return world_profile
	set(value):
		world_profile = value
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
var galaxy_cluster_count: int = DEFAULT_GALAXY_CLUSTER_COUNT
var galaxy_cluster_radius_au: float = DEFAULT_GALAXY_CLUSTER_RADIUS_AU
var galaxy_void_scale: float = DEFAULT_GALAXY_VOID_SCALE

func copy():
	var config = get_script().new()
	config.world_profile = world_profile
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
	config.galaxy_cluster_count = galaxy_cluster_count
	config.galaxy_cluster_radius_au = galaxy_cluster_radius_au
	config.galaxy_void_scale = galaxy_void_scale
	return config

func clamp_values() -> void:
	seed = maxi(seed, 0)
	world_profile = clampi(world_profile, WorldProfile.ORBITAL_SANDBOX, WorldProfile.INFLOW_LAB)
	anchor_topology = clampi(anchor_topology, AnchorTopology.CENTRAL_BH, AnchorTopology.GALAXY_CLUSTER)
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
	var max_bh: int = SimConstants.MAX_GALAXY_BLACK_HOLES \
		if anchor_topology == AnchorTopology.GALAXY_CLUSTER \
		else SimConstants.MAX_FIELD_PATCH_BLACK_HOLES
	black_hole_count = clampi(black_hole_count, 1, max_bh)
	# Upper bound raised to 60 AU so users can spread BHs beyond the dominance
	# radius (~11 AU for a 12M BH) and avoid gravity-field overlap.
	field_spacing_au = clampf(field_spacing_au, 6.0, 60.0)
	galaxy_cluster_count = clampi(galaxy_cluster_count, 2, 12)
	galaxy_cluster_radius_au = clampf(galaxy_cluster_radius_au, 1.0, 8.0)
	galaxy_void_scale = clampf(galaxy_void_scale, 2.0, 6.0)

func uses_inflow_lab_profile() -> bool:
	return world_profile == WorldProfile.INFLOW_LAB

func uses_reference_star_carriers() -> bool:
	return world_profile == WorldProfile.ORBITAL_REFERENCE

func supports_anchor_topology_selection() -> bool:
	return world_profile == WorldProfile.ORBITAL_SANDBOX

func resolved_anchor_topology() -> int:
	return anchor_topology if supports_anchor_topology_selection() else AnchorTopology.CENTRAL_BH
