## Constructs the initial reference systems for Atraxis.
## Stable Anchor is the calm macro test mode; Chaos Inflow remains the lab mode.
class_name WorldBuilder
extends RefCounted

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")

class ZoneBoundaries:
	var inner_max: float
	var middle_min: float
	var middle_max: float
	var outer_min: float

static func build_from_config(world: SimWorld, start_config) -> void:
	var config = start_config if start_config != null else START_CONFIG_SCRIPT.new()
	var safe_config = config.copy()
	safe_config.clamp_values()

	match safe_config.mode:
		START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW:
			_build_chaos_inflow(world, safe_config)
		_:
			_build_stable_anchor(world, safe_config)

static func compute_zones(star: SimBody) -> ZoneBoundaries:
	var mass_factor: float = star.mass / SimConstants.STAR_MASS
	var bounds := ZoneBoundaries.new()
	bounds.inner_max = SimConstants.INNER_ZONE_MAX * mass_factor
	bounds.middle_min = SimConstants.MIDDLE_ZONE_MIN * mass_factor
	bounds.middle_max = SimConstants.MIDDLE_ZONE_MAX * mass_factor
	bounds.outer_min = SimConstants.OUTER_ZONE_MIN * mass_factor
	return bounds

static func _build_stable_anchor(world: SimWorld, config) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed

	var black_hole := _make_black_hole()
	world.add_body(black_hole)

	if config.star_count <= 1:
		var star := _make_anchor_star(black_hole, config.sun_orbit_radius_au, config.sun_orbit_speed_scale)
		world.add_body(star)

		for i in range(config.core_planet_count):
			world.add_body(_make_core_planet(star, i, config.core_planet_count))

		for i in range(config.disturbance_body_count):
			world.add_body(_make_disturbance_body(star, rng, i))
	else:
		var stars := _place_multi_stars(black_hole, config, rng)
		for star in stars:
			world.add_body(star)
		for star in stars:
			for i in range(config.planets_per_star):
				world.add_body(_make_core_planet(star, i, config.planets_per_star))
		for i in range(config.disturbance_body_count):
			world.add_body(_make_disturbance_body(stars[0], rng, i))

static func _build_chaos_inflow(world: SimWorld, config) -> void:
	var star := _make_star()
	world.add_body(star)

	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed

	for i in range(config.chaos_body_count):
		world.add_body(_make_inflow_body(star, config, rng, i))

static func _make_black_hole() -> SimBody:
	var body := SimBody.new()
	body.body_type = SimBody.BodyType.BLACK_HOLE
	body.influence_level = SimBody.InfluenceLevel.A
	body.material_type = SimBody.MaterialType.STELLAR
	body.mass = SimConstants.BLACK_HOLE_MASS
	body.radius = SimConstants.BLACK_HOLE_RADIUS
	body.position = Vector2.ZERO
	body.velocity = Vector2.ZERO
	body.temperature = 3.0
	body.kinematic = true
	body.active = true
	return body

static func _make_star() -> SimBody:
	var body := SimBody.new()
	body.body_type = SimBody.BodyType.STAR
	body.influence_level = SimBody.InfluenceLevel.A
	body.material_type = SimBody.MaterialType.STELLAR
	body.mass = SimConstants.STAR_MASS
	body.radius = SimConstants.STAR_RADIUS
	body.position = Vector2.ZERO
	body.velocity = Vector2.ZERO
	body.temperature = 5778.0
	body.kinematic = true
	body.active = true
	return body

static func _make_anchor_star(black_hole: SimBody, orbit_radius_au: float, speed_scale: float) -> SimBody:
	var star := _make_star()
	star.kinematic = false
	star.scripted_orbit_enabled = false
	star.orbit_binding_state = SimBody.OrbitBindingState.FREE_DYNAMIC
	_place_in_orbit(star, black_hole, orbit_radius_au * SimConstants.AU, 0.0, 0.0)
	star.velocity *= speed_scale
	return star

static func _place_multi_stars(black_hole: SimBody, config, rng: RandomNumberGenerator) -> Array:
	var stars: Array = []
	var n: int = config.star_count
	var inner: float = config.star_inner_orbit_au * SimConstants.AU
	var outer: float = config.star_outer_orbit_au * SimConstants.AU
	var band_width: float = (outer - inner) / float(n)

	for i in range(n):
		var band_center: float = inner + (float(i) + 0.5) * band_width
		var offset: float = rng.randf_range(-0.2, 0.2) * band_width
		var orbit_radius: float = band_center + offset
		var phase: float = (float(i) / float(n)) * TAU + rng.randf_range(-0.25, 0.25)
		var mass_scale: float = rng.randf_range(0.7, 1.3)

		var star := SimBody.new()
		star.body_type = SimBody.BodyType.STAR
		star.influence_level = SimBody.InfluenceLevel.A
		star.material_type = SimBody.MaterialType.STELLAR
		star.mass = SimConstants.STAR_MASS * mass_scale
		star.radius = SimConstants.STAR_RADIUS * sqrt(mass_scale)
		star.temperature = 5778.0
		star.kinematic = false
		star.scripted_orbit_enabled = false
		star.orbit_binding_state = SimBody.OrbitBindingState.FREE_DYNAMIC
		_place_in_orbit(star, black_hole, orbit_radius, phase, 0.0)
		stars.append(star)

	return stars

static func _make_core_planet(star: SimBody, index: int, total_count: int) -> SimBody:
	var orbit_radii_au := [0.38, 1.0, 2.2, 3.0]
	var masses := [800.0, 1100.0, 2800.0, 1900.0]
	var materials := [
		SimBody.MaterialType.ROCKY,
		SimBody.MaterialType.ROCKY,
		SimBody.MaterialType.ICY,
		SimBody.MaterialType.MIXED,
	]
	var temperatures := [400.0, 280.0, 120.0, 90.0]
	var clamped_index: int = clampi(index, 0, orbit_radii_au.size() - 1)
	var angle: float = (float(index) / maxf(1.0, float(total_count))) * TAU

	return _make_planet(
		star,
		orbit_radii_au[clamped_index] * SimConstants.AU,
		masses[clamped_index],
		materials[clamped_index],
		temperatures[clamped_index],
		angle
	)

static func _make_planet(parent: SimBody, orbital_radius: float, mass: float,
		material: int, temperature: float, start_angle: float) -> SimBody:
	var body := SimBody.new()
	body.body_type = SimBody.BodyType.PLANET
	body.influence_level = SimBody.InfluenceLevel.A
	body.material_type = material
	body.mass = mass
	body.radius = clamp(
		SimConstants.PLANET_RADIUS_MIN + log(mass / SimConstants.PLANET_MASS_MIN + 1.0),
		SimConstants.PLANET_RADIUS_MIN,
		SimConstants.PLANET_RADIUS_MAX
	)
	body.temperature = temperature
	body.kinematic = true
	body.scripted_orbit_enabled = true
	body.orbit_binding_state = SimBody.OrbitBindingState.BOUND_ANALYTIC
	body.orbit_parent_id = parent.id
	_place_in_orbit(body, parent, orbital_radius, start_angle, 0.0)
	return body

static func _make_asteroid(parent: SimBody, orbital_radius: float, angle: float,
		eccentricity: float, mass: float, material: int) -> SimBody:
	var body := SimBody.new()
	body.body_type = SimBody.BodyType.ASTEROID
	body.influence_level = SimBody.InfluenceLevel.B
	body.material_type = material
	body.mass = mass
	body.radius = clamp(
		SimConstants.ASTEROID_RADIUS_MIN + mass * 0.06,
		SimConstants.ASTEROID_RADIUS_MIN,
		SimConstants.ASTEROID_RADIUS_MAX
	)
	body.temperature = 200.0 + randf_range(-30.0, 30.0)
	body.kinematic = false
	body.scripted_orbit_enabled = false
	body.orbit_binding_state = SimBody.OrbitBindingState.FREE_DYNAMIC
	_place_in_orbit(body, parent, orbital_radius, angle, eccentricity)
	return body

static func _make_disturbance_body(star: SimBody, rng: RandomNumberGenerator, index: int) -> SimBody:
	var orbital_radius: float = rng.randf_range(2.6, 3.5) * SimConstants.AU
	var angle: float = rng.randf_range(0.0, TAU)
	var eccentricity: float = rng.randf_range(0.03, 0.18)
	var mass: float = rng.randf_range(SimConstants.ASTEROID_MASS_MIN, SimConstants.ASTEROID_MASS_MAX)
	var material: int = SimBody.MaterialType.ROCKY if (index + rng.randi_range(0, 1)) % 2 == 0 \
		else SimBody.MaterialType.METALLIC
	return _make_asteroid(star, orbital_radius, angle, eccentricity, mass, material)

static func _place_in_orbit(body: SimBody, parent: SimBody,
		orbital_radius: float, angle: float, eccentricity: float) -> void:
	body.position = parent.position + Vector2(
		cos(angle) * orbital_radius,
		sin(angle) * orbital_radius
	)
	var semi_major: float = orbital_radius / (1.0 - eccentricity) \
			if eccentricity > 0.0 else orbital_radius
	var speed: float = sqrt(SimConstants.G * parent.mass * (2.0 / orbital_radius - 1.0 / semi_major))
	var tangent: Vector2 = Vector2(-sin(angle), cos(angle))
	body.velocity = parent.velocity + tangent * speed
	body.orbit_parent_id = parent.id
	body.orbit_center = parent.position
	body.orbit_radius = orbital_radius
	body.orbit_angle = angle
	body.orbit_angular_speed = speed / orbital_radius if orbital_radius > 0.0 else 0.0

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
	body.orbit_binding_state = SimBody.OrbitBindingState.FREE_DYNAMIC

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
