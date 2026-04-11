## world_builder.gd
## Constructs the initial MVP star system with deterministic, balanced starting conditions.
## All orbital velocities are calculated from the vis-viva equation so orbits are
## stable from frame 1 — no "settling" period needed.
class_name WorldBuilder
extends RefCounted

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")

## Zone boundary data (computed from star properties).
## Passed to the renderer for zone visualization and later to resource logic.
class ZoneBoundaries:
	var inner_max: float    # inner edge of temperate zone
	var middle_min: float
	var middle_max: float
	var outer_min: float

## Build the MVP system into the provided SimWorld.
static func build_mvp(world) -> void:  # world: SimWorld
	var star := _make_star()
	world.add_body(star)

	var planet1 := _make_planet(star, 0.38 * SimConstants.AU, 800.0,
			SimBody.MaterialType.ROCKY, 400.0, 0.0)
	var planet2 := _make_planet(star, 1.0 * SimConstants.AU, 1100.0,
			SimBody.MaterialType.ROCKY, 280.0, TAU / 3.0)
	var planet3 := _make_planet(star, 2.2 * SimConstants.AU, 2800.0,
			SimBody.MaterialType.ICY, 120.0, 2.0 * TAU / 3.0)
	world.add_body(planet1)
	world.add_body(planet2)
	world.add_body(planet3)

	# Asteroid belt between middle and outer zone
	for i in range(15):
		var dist: float = randf_range(1.6, 2.0) * SimConstants.AU
		var angle: float = randf_range(0.0, TAU)
		var ecc: float = randf_range(0.0, 0.12)
		var mass: float = randf_range(SimConstants.ASTEROID_MASS_MIN, SimConstants.ASTEROID_MASS_MAX)
		var mat: int = SimBody.MaterialType.ROCKY if randf() > 0.3 \
				else SimBody.MaterialType.METALLIC
		var asteroid := _make_asteroid(star, dist, angle, ecc, mass, mat)
		world.add_body(asteroid)

static func build_from_config(world: SimWorld, start_config) -> void:
	var config = start_config if start_config != null else START_CONFIG_SCRIPT.new()
	var safe_config = config.copy()
	safe_config.clamp_values()

	match safe_config.mode:
		START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW:
			_build_chaos_inflow(world, safe_config)
		_:
			build_mvp(world)

## Compute zone boundaries from star mass.
## Returns a ZoneBoundaries object for use by renderer and future systems.
static func compute_zones(star: SimBody) -> ZoneBoundaries:
	# Scale zone thresholds proportionally to star mass
	var mass_factor: float = star.mass / SimConstants.STAR_MASS
	var bounds := ZoneBoundaries.new()
	bounds.inner_max   = SimConstants.INNER_ZONE_MAX  * mass_factor
	bounds.middle_min  = SimConstants.MIDDLE_ZONE_MIN * mass_factor
	bounds.middle_max  = SimConstants.MIDDLE_ZONE_MAX * mass_factor
	bounds.outer_min   = SimConstants.OUTER_ZONE_MIN  * mass_factor
	return bounds

# -------------------------------------------------------------------------
# Factory helpers
# -------------------------------------------------------------------------

static func _make_star() -> SimBody:
	var b := SimBody.new()
	b.body_type = SimBody.BodyType.STAR
	b.influence_level = SimBody.InfluenceLevel.A
	b.material_type = SimBody.MaterialType.STELLAR
	b.mass = SimConstants.STAR_MASS
	b.radius = SimConstants.STAR_RADIUS
	b.position = Vector2.ZERO
	b.velocity = Vector2.ZERO
	b.temperature = 5778.0
	b.kinematic = true  # MVP: star is fixed at origin
	b.active = true
	return b

static func _make_planet(star: SimBody, orbital_radius: float, mass: float,
		material: int, temperature: float, start_angle: float) -> SimBody:
	var b := SimBody.new()
	b.body_type = SimBody.BodyType.PLANET
	b.influence_level = SimBody.InfluenceLevel.A
	b.material_type = material
	b.mass = mass
	b.radius = clamp(
		SimConstants.PLANET_RADIUS_MIN + log(mass / SimConstants.PLANET_MASS_MIN + 1.0),
		SimConstants.PLANET_RADIUS_MIN,
		SimConstants.PLANET_RADIUS_MAX
	)
	b.temperature = temperature
	b.kinematic = true
	b.scripted_orbit_enabled = true
	_place_in_orbit(b, star, orbital_radius, start_angle, 0.0)
	return b

static func _make_asteroid(star: SimBody, orbital_radius: float, angle: float,
		eccentricity: float, mass: float, material: int) -> SimBody:
	var b := SimBody.new()
	b.body_type = SimBody.BodyType.ASTEROID
	b.influence_level = SimBody.InfluenceLevel.B
	b.material_type = material
	b.mass = mass
	b.radius = clamp(
		SimConstants.ASTEROID_RADIUS_MIN + mass * 0.06,
		SimConstants.ASTEROID_RADIUS_MIN,
		SimConstants.ASTEROID_RADIUS_MAX
	)
	b.temperature = 200.0 + randf_range(-30.0, 30.0)
	b.kinematic = false
	_place_in_orbit(b, star, orbital_radius, angle, eccentricity)
	return b

## Place a body in orbit around a parent using the vis-viva equation.
## Ensures stable orbits from the first frame.
##
## v² = G*M * (2/r - 1/a)
## where r = current distance, a = semi-major axis
## For circular orbit (ecc=0): a = r, v = sqrt(G*M/r)
static func _place_in_orbit(body: SimBody, parent: SimBody,
		orbital_radius: float, angle: float, eccentricity: float) -> void:
	body.position = parent.position + Vector2(
		cos(angle) * orbital_radius,
		sin(angle) * orbital_radius
	)
	var semi_major: float = orbital_radius / (1.0 - eccentricity) \
			if eccentricity > 0.0 else orbital_radius
	var speed: float = sqrt(SimConstants.G * parent.mass * (2.0 / orbital_radius - 1.0 / semi_major))
	# Tangent direction: exact perpendicular to the radial vector
	# Using (-sin, cos) avoids floating-point error from angle addition
	var tangent: Vector2 = Vector2(-sin(angle), cos(angle))
	body.velocity = parent.velocity + tangent * speed
	body.orbit_center = parent.position
	body.orbit_radius = orbital_radius
	body.orbit_angle = angle
	body.orbit_angular_speed = speed / orbital_radius if orbital_radius > 0.0 else 0.0

static func _build_chaos_inflow(world: SimWorld, config) -> void:
	var star := _make_star()
	world.add_body(star)

	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed

	for i in range(config.body_count):
		var body := _make_inflow_body(star, config, rng, i)
		world.add_body(body)

static func _make_inflow_body(star: SimBody, config,
		rng: RandomNumberGenerator, index: int) -> SimBody:
	var body := SimBody.new()
	body.body_type = SimBody.BodyType.PLANET
	body.influence_level = SimBody.InfluenceLevel.B
	body.material_type = _pick_inflow_material(rng, index)
	body.mass = rng.randf_range(SimConstants.PLANET_MASS_MIN, SimConstants.PLANET_MASS_MAX)
	body.radius = clamp(
		SimConstants.PLANET_RADIUS_MIN + log(body.mass / SimConstants.PLANET_MASS_MIN + 1.0),
		SimConstants.PLANET_RADIUS_MIN,
		SimConstants.PLANET_RADIUS_MAX
	)
	body.temperature = rng.randf_range(120.0, 420.0)
	body.kinematic = false
	body.scripted_orbit_enabled = false

	var spawn_radius: float = (
		config.spawn_radius_au + rng.randf_range(-config.spawn_spread_au, config.spawn_spread_au)
	) * SimConstants.AU
	spawn_radius = max(spawn_radius, 0.75 * SimConstants.AU)
	var angle: float = rng.randf_range(0.0, TAU)
	body.position = star.position + Vector2(cos(angle), sin(angle)) * spawn_radius

	var inward: Vector2 = (star.position - body.position).normalized()
	var tangent: Vector2 = Vector2(-inward.y, inward.x)
	if rng.randf() > 0.5:
		tangent = -tangent
	var travel_dir: Vector2 = inward.lerp(tangent, config.tangential_bias).normalized()
	var reference_speed: float = sqrt(SimConstants.G * star.mass / spawn_radius)
	body.velocity = travel_dir * (reference_speed * config.inflow_speed_scale)
	return body

static func _pick_inflow_material(rng: RandomNumberGenerator, index: int) -> int:
	var palette: Array[int] = [
		SimBody.MaterialType.ROCKY,
		SimBody.MaterialType.MIXED,
		SimBody.MaterialType.ICY,
	]
	return palette[(index + rng.randi_range(0, palette.size() - 1)) % palette.size()]
