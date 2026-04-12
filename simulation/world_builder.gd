## Materializes local cluster simulations from the galaxy data model.
## GalaxyState / ClusterState are the durable source of truth; SimWorld is only
## the active local projection used for rendering and physics.
class_name WorldBuilder
extends RefCounted

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const GALAXY_BUILDER_SCRIPT := preload("res://simulation/galaxy_builder.gd")

class ZoneBoundaries:
	var inner_max: float
	var middle_min: float
	var middle_max: float
	var outer_min: float

static func build_galaxy_state_from_config(start_config) -> GalaxyState:
	return GALAXY_BUILDER_SCRIPT.build_from_config(start_config)

static func build_active_session_from_config(start_config) -> ActiveClusterSession:
	var galaxy_state: GalaxyState = build_galaxy_state_from_config(start_config)
	return build_active_session_from_galaxy_state(galaxy_state, galaxy_state.primary_cluster_id)

static func build_active_session_from_config_into_world(
		start_config,
		target_world: SimWorld) -> ActiveClusterSession:
	var galaxy_state: GalaxyState = build_galaxy_state_from_config(start_config)
	return build_active_session_from_galaxy_state_into_world(
		galaxy_state,
		galaxy_state.primary_cluster_id,
		target_world
	)

static func build_active_session_from_galaxy_state(
		galaxy_state: GalaxyState,
		target_cluster_id: int = -1) -> ActiveClusterSession:
	return build_active_session_from_galaxy_state_into_world(galaxy_state, target_cluster_id, null)

static func build_active_session_from_galaxy_state_into_world(
		galaxy_state: GalaxyState,
		target_cluster_id: int = -1,
		target_world: SimWorld = null) -> ActiveClusterSession:
	var session := ActiveClusterSession.new()
	if galaxy_state == null or galaxy_state.get_cluster_count() == 0:
		return session

	var resolved_cluster_id: int = target_cluster_id if target_cluster_id >= 0 else galaxy_state.primary_cluster_id
	var cluster_state: ClusterState = galaxy_state.get_cluster(resolved_cluster_id)
	if cluster_state == null:
		return session

	var sim_world := target_world if target_world != null else SimWorld.new()
	materialize_cluster_into_world(sim_world, cluster_state)
	session.bind(galaxy_state, cluster_state, sim_world)
	return session

static func build_from_config(world: SimWorld, start_config) -> void:
	build_active_session_from_config_into_world(start_config, world)

static func materialize_cluster_into_world(world: SimWorld, cluster_state: ClusterState) -> void:
	if world == null or cluster_state == null:
		return

	var spawned_black_holes: Array = _spawn_black_holes_from_cluster(world, cluster_state)
	var profile: Dictionary = cluster_state.simulation_profile
	var start_mode: int = int(profile.get("start_mode", START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR))

	match start_mode:
		START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW:
			_materialize_chaos_cluster(world, profile, cluster_state.cluster_seed)
		START_CONFIG_SCRIPT.StartMode.STABLE_ANCHOR:
			_materialize_anchor_cluster(world, spawned_black_holes, profile, cluster_state.cluster_seed, true)
		_:
			_materialize_anchor_cluster(world, spawned_black_holes, profile, cluster_state.cluster_seed, false)

static func compute_zones(star: SimBody) -> ZoneBoundaries:
	var mass_factor: float = star.mass / SimConstants.STAR_MASS
	var bounds := ZoneBoundaries.new()
	bounds.inner_max = SimConstants.INNER_ZONE_MAX * mass_factor
	bounds.middle_min = SimConstants.MIDDLE_ZONE_MIN * mass_factor
	bounds.middle_max = SimConstants.MIDDLE_ZONE_MAX * mass_factor
	bounds.outer_min = SimConstants.OUTER_ZONE_MIN * mass_factor
	return bounds

static func _spawn_black_holes_from_cluster(world: SimWorld, cluster_state: ClusterState) -> Array:
	var spawned: Array = []
	for object_state in cluster_state.get_objects_by_kind("black_hole"):
		var mass: float = object_state.descriptor.get(
			"mass",
			cluster_state.simulation_profile.get("black_hole_mass", SimConstants.BLACK_HOLE_MASS)
		)
		var black_hole := _make_black_hole(mass)
		black_hole.position = object_state.local_position
		world.add_body(black_hole)
		spawned.append({
			"object_id": object_state.object_id,
			"is_primary": bool(object_state.descriptor.get("is_primary", false)),
			"body": black_hole,
		})

	spawned.sort_custom(func(a, b): return a["object_id"] < b["object_id"])
	return spawned

static func _materialize_anchor_cluster(
		world: SimWorld,
		spawned_black_holes: Array,
		profile: Dictionary,
		cluster_seed: int,
		stable_mode: bool) -> void:
	var spawn_anchor: SimBody = _resolve_primary_black_hole_body(spawned_black_holes)
	if spawn_anchor == null or not profile.get("spawn_anchor_content", true):
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = cluster_seed
	var stars: Array = _place_analytic_stars(spawn_anchor, profile, rng) \
		if stable_mode else _place_dynamic_stars(spawn_anchor, profile, rng)

	for star in stars:
		world.add_body(star)
	for star in stars:
		for i in range(int(profile.get("planets_per_star", 0))):
			world.add_body(_make_core_planet(star, i, int(profile.get("planets_per_star", 0))))
	for i in range(int(profile.get("disturbance_body_count", 0))):
		world.add_body(_make_disturbance_body(stars[i % stars.size()], rng, i))

static func _materialize_chaos_cluster(world: SimWorld, profile: Dictionary, cluster_seed: int) -> void:
	var star := _make_star()
	world.add_body(star)

	var rng := RandomNumberGenerator.new()
	rng.seed = cluster_seed
	for i in range(int(profile.get("chaos_body_count", 0))):
		world.add_body(_make_inflow_body(star, profile, rng, i))

static func _resolve_primary_black_hole_body(spawned_black_holes: Array) -> SimBody:
	for entry in spawned_black_holes:
		if entry["is_primary"]:
			return entry["body"]
	if spawned_black_holes.is_empty():
		return null
	return spawned_black_holes[0]["body"]

static func _make_black_hole(mass: float) -> SimBody:
	var body := SimBody.new()
	body.body_type = SimBody.BodyType.BLACK_HOLE
	body.influence_level = SimBody.InfluenceLevel.A
	body.material_type = SimBody.MaterialType.STELLAR
	body.mass = mass
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

static func _build_star_specs(profile: Dictionary, rng: RandomNumberGenerator) -> Array:
	var specs: Array = []
	var n: int = int(profile.get("star_count", 0))
	if n <= 0:
		return specs

	var inner: float = float(profile.get("star_inner_orbit_au", 0.0)) * SimConstants.AU
	var outer: float = float(profile.get("star_outer_orbit_au", 0.0)) * SimConstants.AU

	var log_inner: float = log(inner)
	var log_outer: float = log(outer)
	var log_band: float = (log_outer - log_inner) / float(n)

	for i in range(n):
		var log_center: float = log_inner + (float(i) + 0.5) * log_band
		var log_jitter: float = rng.randf_range(-0.1, 0.1) * log_band
		var orbit_radius: float = exp(log_center + log_jitter)
		var phase: float = (float(i) / float(n)) * TAU + rng.randf_range(-0.25, 0.25)
		var mass_scale: float = rng.randf_range(0.7, 1.3)
		specs.append({
			"orbit_radius": orbit_radius,
			"phase": phase,
			"mass_scale": mass_scale,
		})

	return specs

static func _place_dynamic_stars(black_hole: SimBody, profile: Dictionary, rng: RandomNumberGenerator) -> Array:
	var stars: Array = []
	for spec in _build_star_specs(profile, rng):
		var star := _make_star()
		star.mass = SimConstants.STAR_MASS * spec["mass_scale"]
		star.radius = SimConstants.STAR_RADIUS * sqrt(spec["mass_scale"])
		star.kinematic = false
		star.scripted_orbit_enabled = false
		star.orbit_binding_state = SimBody.OrbitBindingState.FREE_DYNAMIC
		_place_in_orbit(star, black_hole, spec["orbit_radius"], spec["phase"], 0.0)
		stars.append(star)
	return stars

static func _place_analytic_stars(black_hole: SimBody, profile: Dictionary, rng: RandomNumberGenerator) -> Array:
	var stars: Array = []
	for spec in _build_star_specs(profile, rng):
		var star := _make_star()
		star.mass = SimConstants.STAR_MASS * spec["mass_scale"]
		star.radius = SimConstants.STAR_RADIUS * sqrt(spec["mass_scale"])
		star.kinematic = true
		star.scripted_orbit_enabled = true
		star.orbit_binding_state = SimBody.OrbitBindingState.BOUND_ANALYTIC
		star.orbit_parent_id = black_hole.id
		_place_in_orbit(star, black_hole, spec["orbit_radius"], spec["phase"], 0.0)
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
		eccentricity: float, mass: float, material: int,
		rng: RandomNumberGenerator) -> SimBody:
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
	body.temperature = 200.0 + rng.randf_range(-30.0, 30.0)
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
	return _make_asteroid(star, orbital_radius, angle, eccentricity, mass, material, rng)

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

static func _make_inflow_body(star: SimBody, profile: Dictionary,
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
		float(profile.get("spawn_radius_au", 0.0))
		+ rng.randf_range(-float(profile.get("spawn_spread_au", 0.0)), float(profile.get("spawn_spread_au", 0.0)))
	) * SimConstants.AU
	spawn_radius = max(spawn_radius, 0.75 * SimConstants.AU)
	var angle: float = rng.randf_range(0.0, TAU)
	body.position = star.position + Vector2(cos(angle), sin(angle)) * spawn_radius

	var inward: Vector2 = (star.position - body.position).normalized()
	var tangent: Vector2 = Vector2(-inward.y, inward.x)
	if rng.randf() > 0.5:
		tangent = -tangent
	var travel_dir: Vector2 = inward.lerp(tangent, float(profile.get("tangential_bias", 0.0))).normalized()
	var reference_speed: float = sqrt(SimConstants.G * star.mass / spawn_radius)
	body.velocity = travel_dir * (reference_speed * float(profile.get("inflow_speed_scale", 1.0)))
	return body

static func _pick_inflow_material(rng: RandomNumberGenerator, index: int) -> int:
	var palette: Array[int] = [
		SimBody.MaterialType.ROCKY,
		SimBody.MaterialType.MIXED,
		SimBody.MaterialType.ICY,
	]
	return palette[(index + rng.randi_range(0, palette.size() - 1)) % palette.size()]
