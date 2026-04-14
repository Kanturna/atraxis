## Materializes local cluster simulations from the galaxy data model.
## GalaxyState / ClusterState are the durable source of truth; SimWorld is only
## the active local projection used for rendering and physics.
class_name WorldBuilder
extends RefCounted

const GALAXY_BUILDER_SCRIPT := preload("res://simulation/galaxy_builder.gd")
const MACRO_SECTOR_ZONE_SCRIPT := preload("res://simulation/macro_sector_zone.gd")
const OBJECT_RESIDENCY_POLICY_SCRIPT := preload("res://simulation/object_residency_policy.gd")
const TRANSIT_OBJECT_STATE_SCRIPT := preload("res://simulation/transit_object_state.gd")
const WORLDGEN_SCRIPT := preload("res://simulation/galaxy_worldgen.gd")

class ZoneBoundaries:
	var inner_max: float
	var middle_min: float
	var middle_max: float
	var outer_min: float

static func build_galaxy_state_from_config(start_config) -> GalaxyState:
	return GALAXY_BUILDER_SCRIPT.build_from_config(start_config)

static func build_runtime_from_config(start_config) -> GalaxyRuntime:
	var galaxy_state: GalaxyState = build_galaxy_state_from_config(start_config)
	return build_runtime_from_galaxy_state(galaxy_state, galaxy_state.primary_cluster_id)

static func build_runtime_from_galaxy_state(
		galaxy_state: GalaxyState,
		target_cluster_id: int = -1) -> GalaxyRuntime:
	var runtime := GalaxyRuntime.new()
	if galaxy_state == null:
		return runtime
	var resolved_cluster_id: int = target_cluster_id if target_cluster_id >= 0 else galaxy_state.primary_cluster_id
	runtime.initialize(galaxy_state, resolved_cluster_id)
	return runtime

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
	world.time_elapsed = cluster_state.simulated_time
	if _can_materialize_from_runtime_snapshot(cluster_state):
		_materialize_runtime_snapshot(world, cluster_state)
		return
	_materialize_cluster_blueprint_into_world(world, cluster_state)

static func compute_initial_host_system_frame(sim_world: SimWorld, cluster_state: ClusterState) -> Dictionary:
	var empty_frame := {
		"focus_local_position": Vector2.ZERO,
		"visible_radius_sim": 0.0,
		"host_black_hole_object_id": "",
		"found_host_system": false,
	}
	if sim_world == null or cluster_state == null:
		return empty_frame
	var host_candidate: Dictionary = _select_initial_host_black_hole_candidate(sim_world, cluster_state)
	if host_candidate.is_empty():
		return empty_frame
	var host_black_hole: SimBody = host_candidate.get("body", null)
	var bound_stars: Array = host_candidate.get("bound_stars", [])
	if host_black_hole == null or bound_stars.is_empty():
		return empty_frame
	var planets_by_star_id: Dictionary = _bound_planets_by_star_id(sim_world)
	var system_radius: float = host_black_hole.radius
	for star_entry in bound_stars:
		var star: SimBody = star_entry
		var host_distance: float = _bound_child_distance_to_parent(star, host_black_hole)
		var star_system_radius: float = star.radius
		for planet_entry in planets_by_star_id.get(star.id, []):
			var planet: SimBody = planet_entry
			var planet_distance: float = _bound_child_distance_to_parent(planet, star)
			star_system_radius = maxf(star_system_radius, planet_distance + planet.radius)
		system_radius = maxf(system_radius, host_distance + star_system_radius)
	return {
		"focus_local_position": host_black_hole.position,
		"visible_radius_sim": system_radius * 1.15,
		"host_black_hole_object_id": str(host_candidate.get("object_id", "")),
		"found_host_system": true,
	}

static func ensure_coherent_simplified_snapshot(cluster_state: ClusterState) -> bool:
	if cluster_state == null:
		return false
	if _runtime_snapshot_has_non_black_hole_content(cluster_state):
		return false
	var seeded_world := SimWorld.new()
	_materialize_cluster_blueprint_into_world(seeded_world, cluster_state)
	writeback_world_into_cluster(
		seeded_world,
		cluster_state,
		ObjectResidencyState.State.SIMPLIFIED
	)
	seeded_world.dispose()
	return true

static func has_coherent_runtime_snapshot(cluster_state: ClusterState) -> bool:
	return _runtime_snapshot_has_non_black_hole_content(cluster_state)

static func _materialize_cluster_blueprint_into_world(world: SimWorld, cluster_state: ClusterState) -> void:
	var spawned_black_holes: Array = _spawn_black_holes_from_cluster(world, cluster_state)
	var profile: Dictionary = cluster_state.simulation_profile
	var content_archetype: String = str(profile.get("content_archetype", "anchor_orbital"))
	if content_archetype == "inflow_lab":
		_materialize_inflow_lab_cluster(world, profile, cluster_state.cluster_seed, cluster_state.cluster_id)
	else:
		_materialize_anchor_cluster(
			world,
			spawned_black_holes,
			profile,
			cluster_state.cluster_seed,
			cluster_state.cluster_id,
			bool(profile.get("analytic_star_carriers", false))
		)
	_materialize_registered_cluster_objects(world, cluster_state)

static func build_cluster_preview_specs(
		cluster_id: int,
		local_black_hole_specs: Array,
		profile: Dictionary,
		cluster_seed: int) -> Array:
	var preview_specs: Array = []
	if local_black_hole_specs.is_empty():
		return preview_specs

	for spec in local_black_hole_specs:
		var black_hole_object_id: String = _make_cluster_object_id(
			cluster_id,
			"black_hole",
			int(spec.get("id", 0))
		)
		preview_specs.append({
			"object_id": black_hole_object_id,
			"kind": "black_hole",
			"body_type": SimBody.BodyType.BLACK_HOLE,
			"material_type": SimBody.MaterialType.STELLAR,
			"local_position": Vector2(spec.get("local_position", Vector2.ZERO)),
			"radius": SimConstants.BLACK_HOLE_RADIUS,
			"seed": _derive_runtime_object_seed(cluster_seed, black_hole_object_id),
			"descriptor": {
				"mass": float(spec.get("mass", profile.get("black_hole_mass", SimConstants.BLACK_HOLE_MASS))),
				"is_primary": bool(spec.get("is_primary", false)),
			},
		})

	var host_entries: Array = _build_preview_dynamic_star_host_entries(local_black_hole_specs, cluster_id)
	if host_entries.is_empty():
		return preview_specs

	var rng := RandomNumberGenerator.new()
	rng.seed = cluster_seed
	var layout_plan: Dictionary = _build_dynamic_star_layout_plan_from_host_entries(host_entries, profile, rng)
	var star_layouts: Array = layout_plan.get("assignments", [])
	for star_index in range(star_layouts.size()):
		var layout: Dictionary = star_layouts[star_index]
		var host_entry: Dictionary = host_entries[int(layout["host_index"])]
		var star_object_id: String = _make_cluster_object_id(cluster_id, "star", star_index)
		var star_position: Vector2 = Vector2(host_entry["local_position"]) \
			+ Vector2.RIGHT.rotated(float(layout["phase"])) * float(layout["orbit_radius"])
		var star_radius: float = SimConstants.STAR_RADIUS * sqrt(float(layout["mass_scale"]))
		var star_descriptor := {
			"host_object_id": str(layout["host_object_id"]),
			"host_index": int(layout["host_index"]),
			"shell_index": int(layout["shell_index"]),
			"orbit_radius": float(layout["orbit_radius"]),
			"phase": float(layout["phase"]),
			"planet_envelope_radius": float(layout["planet_envelope_radius"]),
			"mass": SimConstants.STAR_MASS * float(layout["mass_scale"]),
			"parent_object_id": str(layout["host_object_id"]),
		}
		preview_specs.append({
			"object_id": star_object_id,
			"kind": "star",
			"body_type": SimBody.BodyType.STAR,
			"material_type": SimBody.MaterialType.STELLAR,
			"local_position": star_position,
			"radius": star_radius,
			"seed": _derive_runtime_object_seed(cluster_seed, star_object_id),
			"descriptor": star_descriptor,
		})

		var planet_count: int = int(profile.get("planets_per_star", 0))
		for planet_index in range(planet_count):
			var planet_layout: Dictionary = _core_planet_layout_data(planet_index, planet_count)
			var planet_angle: float = (float(planet_index) / maxf(1.0, float(planet_count))) * TAU
			var orbit_radius: float = float(planet_layout["orbit_radius_au"]) * SimConstants.AU
			var planet_position: Vector2 = star_position + Vector2.RIGHT.rotated(planet_angle) * orbit_radius
			var planet_object_id: String = _make_child_object_id(star_object_id, "planet", planet_index)
			var planet_rng := RandomNumberGenerator.new()
			planet_rng.seed = _derive_runtime_object_seed(cluster_seed, planet_object_id)
			var planet_material: int = _pick_material_from_profile(
				profile.get("planet_material_profile", {}),
				planet_rng,
				SimBody.MaterialType.MIXED
			)
			var planet_mass: float = float(planet_layout["mass"])
			var planet_radius: float = clamp(
				SimConstants.PLANET_RADIUS_MIN + log(planet_mass / SimConstants.PLANET_MASS_MIN + 1.0),
				SimConstants.PLANET_RADIUS_MIN,
				SimConstants.PLANET_RADIUS_MAX
			)
			preview_specs.append({
				"object_id": planet_object_id,
				"kind": "planet",
				"body_type": SimBody.BodyType.PLANET,
				"material_type": planet_material,
				"local_position": planet_position,
				"radius": planet_radius,
				"seed": _derive_runtime_object_seed(cluster_seed, planet_object_id),
				"descriptor": {
					"parent_object_id": star_object_id,
					"orbit_radius": orbit_radius,
					"orbit_angle": planet_angle,
				},
			})

	return preview_specs

static func dynamic_star_safe_capacity(local_black_hole_count: int, profile: Dictionary) -> int:
	if local_black_hole_count <= 0:
		return 0
	return maxi(local_black_hole_count, 0) * _dynamic_star_host_capacity(profile)

static func compute_zones(star: SimBody) -> ZoneBoundaries:
	var mass_factor: float = star.mass / SimConstants.STAR_MASS
	var bounds := ZoneBoundaries.new()
	bounds.inner_max = SimConstants.INNER_ZONE_MAX * mass_factor
	bounds.middle_min = SimConstants.MIDDLE_ZONE_MIN * mass_factor
	bounds.middle_max = SimConstants.MIDDLE_ZONE_MAX * mass_factor
	bounds.outer_min = SimConstants.OUTER_ZONE_MIN * mass_factor
	return bounds

static func writeback_world_into_cluster(
		world: SimWorld,
		cluster_state: ClusterState,
		residency_state: int) -> void:
	if world == null or cluster_state == null:
		return

	var next_object_registry: Dictionary = {}
	var kind_indices: Dictionary = {}
	var used_object_ids: Dictionary = {}
	for object_id in cluster_state.object_registry.keys():
		used_object_ids[object_id] = true
	var persistent_id_by_sim_id: Dictionary = {}
	for body in world.bodies:
		if not body.active:
			continue
		var object_id: String = _ensure_body_object_id(
			cluster_state.cluster_id,
			body,
			kind_indices,
			used_object_ids
		)
		persistent_id_by_sim_id[body.id] = object_id

	var active_bodies: Array = []
	for body in world.bodies:
		if body.active:
			active_bodies.append(body)
	active_bodies.sort_custom(func(a, b): return a.persistent_object_id < b.persistent_object_id)

	for body in active_bodies:
		var object_state: ClusterObjectState = _build_object_state_from_body(
			cluster_state,
			body,
			persistent_id_by_sim_id[body.id],
			residency_state,
			persistent_id_by_sim_id
		)
		next_object_registry[object_state.object_id] = object_state

	cluster_state.replace_object_registry(next_object_registry)
	cluster_state.set_object_residency_state(residency_state)
	cluster_state.simulated_time = world.time_elapsed
	cluster_state.simulation_profile["has_runtime_snapshot"] = true
	cluster_state.update_runtime_extent(_estimate_runtime_cluster_radius(next_object_registry))
	if cluster_state.get_primary_black_hole_object_id() == "":
		for object_state in cluster_state.get_objects_by_kind("black_hole"):
			cluster_state.cluster_blueprint["primary_black_hole_object_id"] = object_state.object_id
			object_state.descriptor["is_primary"] = true
			break

static func extract_outbound_transit_objects_from_active_session(
		active_cluster_session: ActiveClusterSession) -> Array:
	var exported: Array = []
	if active_cluster_session == null \
			or active_cluster_session.sim_world == null \
			or active_cluster_session.active_cluster_state == null:
		return exported

	var cluster_state: ClusterState = active_cluster_session.active_cluster_state
	var world: SimWorld = active_cluster_session.sim_world
	var kind_indices: Dictionary = {}
	var used_object_ids: Dictionary = {}
	for object_id in cluster_state.object_registry.keys():
		used_object_ids[object_id] = true

	for body in world.bodies:
		if not OBJECT_RESIDENCY_POLICY_SCRIPT.should_export_body_from_active_cluster(body, cluster_state):
			continue
		var object_id: String = _ensure_body_object_id(
			cluster_state.cluster_id,
			body,
			kind_indices,
			used_object_ids
		)
		var transit_state = _build_transit_object_state_from_body(
			cluster_state,
			body,
			object_id,
			active_cluster_session.to_global(body.position)
		)
		exported.append(transit_state)
		body.active = false
		body.marked_for_removal = true

	if not exported.is_empty():
		world.flush_marked_removals()
	return exported

static func step_transit_objects(galaxy_state: GalaxyState, dt: float) -> void:
	if galaxy_state == null or dt <= 0.0:
		return
	for transit_state in galaxy_state.get_transit_objects():
		transit_state.global_position += transit_state.global_velocity * dt
		transit_state.age += dt
	galaxy_state.sync_transit_groups_from_objects()
	for transit_group in galaxy_state.get_transit_groups():
		_refresh_transit_group_target_assignment(galaxy_state, transit_group)
	for transit_state in galaxy_state.get_transit_objects():
		if transit_state.transfer_group_id != "" and galaxy_state.has_transit_group(transit_state.transfer_group_id):
			var transit_group = galaxy_state.get_transit_group(transit_state.transfer_group_id)
			transit_state.target_cluster_id = transit_group.target_cluster_id
			transit_state.arrival_phase = transit_group.arrival_phase
			continue
		refresh_transit_target_assignment(galaxy_state, transit_state)

static func settle_arrived_transit_objects_into_inactive_clusters(
		galaxy_state: GalaxyState,
		active_cluster_id: int = -1) -> Array:
	var settled_object_ids: Array = []
	if galaxy_state == null:
		return settled_object_ids
	galaxy_state.sync_transit_groups_from_objects()
	for transit_group in galaxy_state.get_transit_groups():
		if transit_group.arrival_phase != TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.ARRIVING:
			continue
		if transit_group.target_cluster_id < 0 or transit_group.target_cluster_id == active_cluster_id:
			continue
		var grouped_target_cluster: ClusterState = galaxy_state.get_cluster(transit_group.target_cluster_id)
		if grouped_target_cluster == null:
			continue
		for object_id in transit_group.member_object_ids.duplicate():
			var grouped_transit_state = galaxy_state.get_transit_object(str(object_id))
			if grouped_transit_state == null:
				continue
			_accept_transit_object_into_cluster(grouped_target_cluster, grouped_transit_state)
			galaxy_state.remove_transit_object(grouped_transit_state.object_id)
			settled_object_ids.append(grouped_transit_state.object_id)
	for transit_state in galaxy_state.get_transit_objects():
		if transit_state.transfer_group_id != "" and galaxy_state.has_transit_group(transit_state.transfer_group_id):
			continue
		if transit_state.arrival_phase != TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.ARRIVING:
			continue
		if transit_state.target_cluster_id < 0 or transit_state.target_cluster_id == active_cluster_id:
			continue
		var target_cluster: ClusterState = galaxy_state.get_cluster(transit_state.target_cluster_id)
		if target_cluster == null:
			continue
		_accept_transit_object_into_cluster(target_cluster, transit_state)
		galaxy_state.remove_transit_object(transit_state.object_id)
		settled_object_ids.append(transit_state.object_id)
	return settled_object_ids

static func import_transit_objects_into_active_session(
		active_cluster_session: ActiveClusterSession) -> Array:
	var imported_object_ids: Array = []
	if active_cluster_session == null \
			or active_cluster_session.galaxy_state == null \
			or active_cluster_session.active_cluster_state == null \
			or active_cluster_session.sim_world == null:
		return imported_object_ids

	var galaxy_state: GalaxyState = active_cluster_session.galaxy_state
	var cluster_state: ClusterState = active_cluster_session.active_cluster_state
	var sim_world: SimWorld = active_cluster_session.sim_world
	galaxy_state.sync_transit_groups_from_objects()
	for transit_group in galaxy_state.get_transit_groups():
		if transit_group.arrival_phase != TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.ARRIVING:
			continue
		if transit_group.target_cluster_id != cluster_state.cluster_id:
			continue
		for object_id in transit_group.member_object_ids.duplicate():
			var grouped_transit_state = galaxy_state.get_transit_object(str(object_id))
			if grouped_transit_state == null:
				continue
			if sim_world.get_body_by_persistent_object_id(grouped_transit_state.object_id) != null:
				galaxy_state.remove_transit_object(grouped_transit_state.object_id)
				continue
			var grouped_local_position: Vector2 = active_cluster_session.to_local(grouped_transit_state.global_position)
			cluster_state.register_object(_build_cluster_object_state_from_transit(
				grouped_transit_state,
				grouped_local_position,
				ObjectResidencyState.State.ACTIVE
			))
			var grouped_body: SimBody = _make_body_from_transit_state(grouped_transit_state, grouped_local_position)
			if grouped_body == null:
				continue
			sim_world.add_body(grouped_body)
			galaxy_state.remove_transit_object(grouped_transit_state.object_id)
			imported_object_ids.append(grouped_transit_state.object_id)
	for transit_state in galaxy_state.get_transit_objects():
		if transit_state.transfer_group_id != "" and galaxy_state.has_transit_group(transit_state.transfer_group_id):
			continue
		if transit_state.arrival_phase != TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.ARRIVING:
			continue
		if transit_state.target_cluster_id != cluster_state.cluster_id:
			continue
		if not OBJECT_RESIDENCY_POLICY_SCRIPT.can_import_transit_object_into_cluster(transit_state, cluster_state):
			continue
		if sim_world.get_body_by_persistent_object_id(transit_state.object_id) != null:
			galaxy_state.remove_transit_object(transit_state.object_id)
			continue
		var cluster_local_position: Vector2 = active_cluster_session.to_local(transit_state.global_position)
		cluster_state.register_object(_build_cluster_object_state_from_transit(
			transit_state,
			cluster_local_position,
			ObjectResidencyState.State.ACTIVE
		))
		var body: SimBody = _make_body_from_transit_state(transit_state, cluster_local_position)
		if body == null:
			continue
		sim_world.add_body(body)
		galaxy_state.remove_transit_object(transit_state.object_id)
		imported_object_ids.append(transit_state.object_id)
	return imported_object_ids

static func step_simplified_cluster(
		cluster_state: ClusterState,
		dt: float,
		macro_sector_zone: int = MACRO_SECTOR_ZONE_SCRIPT.Zone.AMBIENT) -> void:
	if cluster_state == null or dt <= 0.0:
		return
	if cluster_state.object_registry.is_empty():
		cluster_state.simulated_time += dt
		return

	var object_states: Array = cluster_state.object_registry.values()
	object_states.sort_custom(func(a, b):
		var kind_rank_a: int = _kind_sort_rank(a.kind)
		var kind_rank_b: int = _kind_sort_rank(b.kind)
		if kind_rank_a != kind_rank_b:
			return kind_rank_a < kind_rank_b
		return a.object_id < b.object_id
	)
	var object_by_id: Dictionary = {}
	var black_hole_states: Array = []
	for object_state in object_states:
		object_by_id[object_state.object_id] = object_state
		if object_state.kind == "black_hole":
			black_hole_states.append(object_state)

	for object_state in object_states:
		if not _should_step_simplified_object(object_state, macro_sector_zone):
			continue
		if _is_simplified_analytic_orbiter(object_state):
			continue
		if object_state.kind == "black_hole" or bool(object_state.descriptor.get("kinematic", false)):
			object_state.local_position += object_state.local_velocity * dt
			object_state.age += dt
			continue
		var acceleration: Vector2 = _compute_simplified_black_hole_acceleration(object_state, black_hole_states)
		object_state.local_velocity += acceleration * dt
		object_state.local_position += object_state.local_velocity * dt
		object_state.age += dt

	for object_state in object_states:
		if not _should_step_simplified_object(object_state, macro_sector_zone):
			continue
		if not _is_simplified_analytic_orbiter(object_state):
			continue
		var parent_object_id: String = str(object_state.descriptor.get("parent_object_id", ""))
		var parent_state: ClusterObjectState = object_by_id.get(parent_object_id, null)
		if parent_state == null:
			object_state.local_position += object_state.local_velocity * dt
			object_state.age += dt
			continue
		var orbit_angle: float = wrapf(
			float(object_state.descriptor.get("orbit_angle", 0.0))
				+ float(object_state.descriptor.get("orbit_angular_speed", 0.0)) * dt,
			0.0,
			TAU
		)
		var orbit_radius: float = float(object_state.descriptor.get("orbit_radius", 0.0))
		var radial: Vector2 = Vector2(cos(orbit_angle), sin(orbit_angle))
		var tangent: Vector2 = Vector2(-sin(orbit_angle), cos(orbit_angle))
		object_state.descriptor["orbit_angle"] = orbit_angle
		object_state.local_position = parent_state.local_position + radial * orbit_radius
		object_state.local_velocity = parent_state.local_velocity \
			+ tangent * (float(object_state.descriptor.get("orbit_angular_speed", 0.0)) * orbit_radius)
		object_state.age += dt

	cluster_state.set_object_residency_state(ObjectResidencyState.State.SIMPLIFIED)
	cluster_state.simulated_time += dt
	cluster_state.simulation_profile["has_runtime_snapshot"] = true
	cluster_state.update_runtime_extent(_estimate_runtime_cluster_radius(cluster_state.object_registry))

static func _should_step_simplified_object(object_state: ClusterObjectState, macro_sector_zone: int) -> bool:
	if object_state == null:
		return false
	if macro_sector_zone == MACRO_SECTOR_ZONE_SCRIPT.Zone.FAR:
		return object_state.kind in ["black_hole", "star"]
	return true

static func _compute_simplified_black_hole_acceleration(object_state: ClusterObjectState, black_hole_states: Array) -> Vector2:
	var acceleration: Vector2 = Vector2.ZERO
	for black_hole_state in black_hole_states:
		if black_hole_state == null or black_hole_state.object_id == object_state.object_id:
			continue
		var delta: Vector2 = black_hole_state.local_position - object_state.local_position
		var dist_sq: float = delta.length_squared() + SimConstants.GRAVITY_SOFTENING_SQ
		if dist_sq <= 0.0:
			continue
		var inv_dist: float = 1.0 / sqrt(dist_sq)
		var accel_scale: float = SimConstants.G \
			* float(black_hole_state.descriptor.get("mass", SimConstants.BLACK_HOLE_MASS)) \
			/ dist_sq
		acceleration += delta * inv_dist * accel_scale
	return acceleration

static func _has_runtime_snapshot(cluster_state: ClusterState) -> bool:
	return bool(cluster_state.simulation_profile.get("has_runtime_snapshot", false))

static func _can_materialize_from_runtime_snapshot(cluster_state: ClusterState) -> bool:
	if not _has_runtime_snapshot(cluster_state):
		return false
	# A remote cluster can become SIMPLIFIED and receive a BH-only runtime snapshot
	# before it has ever been ACTIVE. Remote previews supplement that sparse registry
	# with blueprint stars/planets, but activation must not reload the incomplete
	# BH-only snapshot or the visible star system disappears on cluster entry.
	if cluster_state.last_activated_runtime_time >= 0.0:
		return true
	return _runtime_snapshot_has_non_black_hole_content(cluster_state)

static func _runtime_snapshot_has_non_black_hole_content(cluster_state: ClusterState) -> bool:
	if cluster_state == null:
		return false
	for object_state in cluster_state.object_registry.values():
		if object_state == null:
			continue
		if object_state.kind != "black_hole" \
				and object_state.residency_state != ObjectResidencyState.State.IN_TRANSIT:
			return true
	return false

static func _materialize_runtime_snapshot(world: SimWorld, cluster_state: ClusterState) -> void:
	var object_states: Array = cluster_state.object_registry.values()
	object_states.sort_custom(func(a, b):
		var kind_rank_a: int = _kind_sort_rank(a.kind)
		var kind_rank_b: int = _kind_sort_rank(b.kind)
		if kind_rank_a != kind_rank_b:
			return kind_rank_a < kind_rank_b
		return a.object_id < b.object_id
	)

	var body_by_object_id: Dictionary = {}
	var pending_parent_links: Array = []
	for object_state in object_states:
		if object_state.residency_state == ObjectResidencyState.State.IN_TRANSIT:
			continue
		var body: SimBody = _make_body_from_object_state(object_state)
		if body == null or not body.active:
			continue
		world.add_body(body)
		body_by_object_id[object_state.object_id] = body
		var parent_object_id: String = str(object_state.descriptor.get("parent_object_id", ""))
		if parent_object_id != "":
			pending_parent_links.append({
				"body": body,
				"parent_object_id": parent_object_id,
			})

	for link in pending_parent_links:
		var body: SimBody = link["body"]
		var parent_body: SimBody = body_by_object_id.get(link["parent_object_id"], null)
		if parent_body == null:
			continue
		body.orbit_parent_id = parent_body.id
		body.orbit_center = parent_body.position

static func _materialize_registered_cluster_objects(world: SimWorld, cluster_state: ClusterState) -> void:
	if world == null or cluster_state == null:
		return
	var registered_states: Array = cluster_state.object_registry.values()
	registered_states.sort_custom(func(a, b): return a.object_id < b.object_id)
	for object_state in registered_states:
		if object_state == null:
			continue
		if object_state.kind == "black_hole":
			continue
		if object_state.residency_state == ObjectResidencyState.State.IN_TRANSIT:
			continue
		if world.get_body_by_persistent_object_id(object_state.object_id) != null:
			continue
		var body: SimBody = _make_body_from_object_state(object_state)
		if body == null or not body.active:
			continue
		world.add_body(body)

static func _make_body_from_object_state(object_state: ClusterObjectState) -> SimBody:
	var body := SimBody.new()
	body.persistent_object_id = object_state.object_id
	body.body_type = int(object_state.descriptor.get("body_type", _body_type_for_kind(object_state.kind)))
	body.material_type = int(object_state.descriptor.get("material_type", SimBody.MaterialType.ROCKY))
	body.influence_level = int(object_state.descriptor.get("influence_level", SimBody.InfluenceLevel.B))
	body.mass = float(object_state.descriptor.get("mass", 1.0))
	body.radius = float(object_state.descriptor.get("radius", 1.0))
	body.position = object_state.local_position
	body.velocity = object_state.local_velocity
	body.temperature = float(object_state.descriptor.get("temperature", 200.0))
	body.kinematic = bool(object_state.descriptor.get("kinematic", false))
	body.scripted_orbit_enabled = bool(object_state.descriptor.get("scripted_orbit_enabled", false))
	body.orbit_binding_state = int(object_state.descriptor.get(
		"orbit_binding_state",
		SimBody.OrbitBindingState.FREE_DYNAMIC
	))
	body.orbit_radius = float(object_state.descriptor.get("orbit_radius", 0.0))
	body.orbit_angle = float(object_state.descriptor.get("orbit_angle", 0.0))
	body.orbit_angular_speed = float(object_state.descriptor.get("orbit_angular_speed", 0.0))
	body.last_dominant_bh_id = int(object_state.descriptor.get("last_dominant_bh_id", -1))
	body.dominant_bh_handoff_count = int(object_state.descriptor.get("dominant_bh_handoff_count", 0))
	body.pending_host_bh_id = int(object_state.descriptor.get("pending_host_bh_id", -1))
	body.pending_host_time = float(object_state.descriptor.get("pending_host_time", 0.0))
	body.confirmed_host_handoff_count = int(object_state.descriptor.get("confirmed_host_handoff_count", 0))
	body.debris_mass = float(object_state.descriptor.get("debris_mass", 0.0))
	body.sleeping = bool(object_state.descriptor.get("sleeping", false))
	body.active = bool(object_state.descriptor.get("active", true))
	body.age = object_state.age
	return body

static func _make_body_from_transit_state(
		transit_state,
		cluster_local_position: Vector2) -> SimBody:
	if transit_state == null:
		return null
	var object_state := ClusterObjectState.new()
	object_state.object_id = transit_state.object_id
	object_state.kind = transit_state.kind
	object_state.residency_state = ObjectResidencyState.State.ACTIVE
	object_state.local_position = cluster_local_position
	object_state.local_velocity = transit_state.global_velocity
	object_state.age = transit_state.age
	object_state.seed = transit_state.seed
	object_state.descriptor = transit_state.descriptor.duplicate(true)
	return _make_body_from_object_state(object_state)

static func _spawn_black_holes_from_cluster(world: SimWorld, cluster_state: ClusterState) -> Array:
	var spawned: Array = []
	for object_state in cluster_state.get_objects_by_kind("black_hole"):
		var mass: float = object_state.descriptor.get(
			"mass",
			cluster_state.simulation_profile.get("black_hole_mass", SimConstants.BLACK_HOLE_MASS)
		)
		var black_hole := _make_black_hole(mass)
		black_hole.persistent_object_id = object_state.object_id
		black_hole.position = object_state.local_position
		black_hole.velocity = object_state.local_velocity
		black_hole.age = object_state.age
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
		cluster_id: int,
		analytic_star_carriers: bool) -> void:
	if not profile.get("spawn_anchor_content", true):
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = cluster_seed
	var stars: Array = []
	if analytic_star_carriers:
		var spawn_anchor: SimBody = _resolve_primary_black_hole_body(spawned_black_holes)
		if spawn_anchor == null:
			return
		stars = _place_analytic_stars(spawn_anchor, profile, rng)
	else:
		stars = _place_dynamic_stars(spawned_black_holes, profile, rng)

	for star_index in range(stars.size()):
		stars[star_index].persistent_object_id = _make_cluster_object_id(cluster_id, "star", star_index)
	for star in stars:
		world.add_body(star)
	for star_index in range(stars.size()):
		var star: SimBody = stars[star_index]
		for i in range(int(profile.get("planets_per_star", 0))):
			var planet := _make_core_planet(
				star,
				i,
				int(profile.get("planets_per_star", 0)),
				profile,
				rng
			)
			planet.persistent_object_id = _make_child_object_id(star.persistent_object_id, "planet", i)
			world.add_body(planet)
	if stars.is_empty():
		return
	for i in range(int(profile.get("disturbance_body_count", 0))):
		var disturbance := _make_disturbance_body(stars[i % stars.size()], profile, rng, i)
		disturbance.persistent_object_id = _make_cluster_object_id(cluster_id, "asteroid", i)
		world.add_body(disturbance)

static func _materialize_inflow_lab_cluster(
		world: SimWorld,
		profile: Dictionary,
		cluster_seed: int,
		cluster_id: int) -> void:
	var star := _make_star()
	star.persistent_object_id = _make_cluster_object_id(cluster_id, "star", 0)
	world.add_body(star)

	var rng := RandomNumberGenerator.new()
	rng.seed = cluster_seed
	for i in range(int(profile.get("chaos_body_count", 0))):
		var inflow_body := _make_inflow_body(star, profile, rng, i)
		inflow_body.persistent_object_id = _make_cluster_object_id(cluster_id, "chaos_inflow", i)
		world.add_body(inflow_body)

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
	var mass_scale_min: float = float(profile.get("star_mass_scale_min", 0.7))
	var mass_scale_max: float = maxf(
		mass_scale_min,
		float(profile.get("star_mass_scale_max", 1.3))
	)

	var log_inner: float = log(inner)
	var log_outer: float = log(outer)
	var log_band: float = (log_outer - log_inner) / float(n)

	for i in range(n):
		var log_center: float = log_inner + (float(i) + 0.5) * log_band
		var log_jitter: float = rng.randf_range(-0.1, 0.1) * log_band
		var orbit_radius: float = exp(log_center + log_jitter)
		var phase: float = (float(i) / float(n)) * TAU + rng.randf_range(-0.25, 0.25)
		var mass_scale: float = rng.randf_range(mass_scale_min, mass_scale_max)
		specs.append({
			"orbit_radius": orbit_radius,
			"phase": phase,
			"mass_scale": mass_scale,
		})

	return specs

static func _build_dynamic_star_specs(profile: Dictionary, rng: RandomNumberGenerator) -> Array:
	var specs: Array = []
	var n: int = int(profile.get("star_count", 0))
	if n <= 0:
		return specs

	var mass_scale_min: float = float(profile.get("star_mass_scale_min", 0.7))
	var mass_scale_max: float = maxf(
		mass_scale_min,
		float(profile.get("star_mass_scale_max", 1.3))
	)
	for _i in range(n):
		specs.append({
			"mass_scale": rng.randf_range(mass_scale_min, mass_scale_max),
		})
	return specs

static func _place_dynamic_stars(spawned_black_holes: Array, profile: Dictionary, rng: RandomNumberGenerator) -> Array:
	var stars: Array = []
	var host_entries: Array = _build_dynamic_star_host_entries(spawned_black_holes, rng)
	if host_entries.is_empty():
		return stars

	var layout_plan: Dictionary = _build_dynamic_star_layout_plan_from_host_entries(host_entries, profile, rng)
	for assignment in layout_plan.get("assignments", []):
		var host_entry: Dictionary = host_entries[int(assignment["host_index"])]
		var star := _make_star()
		star.mass = SimConstants.STAR_MASS * float(assignment["mass_scale"])
		star.radius = SimConstants.STAR_RADIUS * sqrt(float(assignment["mass_scale"]))
		star.kinematic = false
		star.scripted_orbit_enabled = false
		star.orbit_binding_state = SimBody.OrbitBindingState.FREE_DYNAMIC
		_place_in_orbit(
			star,
			host_entry["body"],
			float(assignment["orbit_radius"]),
			float(assignment["phase"]),
			0.0
		)
		stars.append(star)
	return stars

static func _build_dynamic_star_host_entries(spawned_black_holes: Array, rng: RandomNumberGenerator) -> Array:
	var host_entries: Array = []
	for entry in spawned_black_holes:
		var black_hole: SimBody = entry.get("body", null)
		if black_hole == null or not black_hole.active:
			continue
		host_entries.append({
			"body": black_hole,
			"local_position": black_hole.position,
			"object_id": str(entry.get("object_id", "")),
			"is_primary": bool(entry.get("is_primary", false)),
			"nearest_other_distance": 0.0,
			"base_phase": 0.0,
			"capacity": 0,
			"planned_count": 0,
		})
	return _finalize_dynamic_star_host_entries(host_entries, rng)

static func _build_preview_dynamic_star_host_entries(local_black_hole_specs: Array, cluster_id: int) -> Array:
	var host_entries: Array = []
	for spec in local_black_hole_specs:
		host_entries.append({
			"body": null,
			"local_position": Vector2(spec.get("local_position", Vector2.ZERO)),
			"object_id": _make_cluster_object_id(cluster_id, "black_hole", int(spec.get("id", 0))),
			"is_primary": bool(spec.get("is_primary", false)),
			"nearest_other_distance": 0.0,
			"base_phase": 0.0,
			"capacity": 0,
			"planned_count": 0,
		})
	var rng := RandomNumberGenerator.new()
	rng.seed = cluster_id
	return _finalize_dynamic_star_host_entries(host_entries, rng)

static func _finalize_dynamic_star_host_entries(host_entries: Array, rng: RandomNumberGenerator) -> Array:
	for entry in host_entries:
		entry["nearest_other_distance"] = _nearest_other_black_hole_distance_for_entry(entry, host_entries)
	host_entries.sort_custom(func(a, b):
		if bool(a["is_primary"]) != bool(b["is_primary"]):
			return bool(a["is_primary"])
		var distance_a: float = float(a["nearest_other_distance"])
		var distance_b: float = float(b["nearest_other_distance"])
		if not is_equal_approx(distance_a, distance_b):
			return distance_a > distance_b
		return str(a["object_id"]) < str(b["object_id"])
	)
	for entry in host_entries:
		entry["base_phase"] = _resolve_dynamic_star_host_base_phase_for_entry(entry, host_entries, rng)
	return host_entries

static func _nearest_other_black_hole_distance_for_entry(host_entry: Dictionary, host_entries: Array) -> float:
	var nearest_distance: float = INF
	var host_position: Vector2 = Vector2(host_entry.get("local_position", Vector2.ZERO))
	var host_object_id: String = str(host_entry.get("object_id", ""))
	for entry in host_entries:
		if str(entry.get("object_id", "")) == host_object_id:
			continue
		var other_position: Vector2 = Vector2(entry.get("local_position", Vector2.ZERO))
		nearest_distance = minf(
			nearest_distance,
			host_position.distance_to(other_position)
		)
	return nearest_distance

static func _resolve_dynamic_star_host_base_phase_for_entry(
		host_entry: Dictionary,
		host_entries: Array,
		rng: RandomNumberGenerator) -> float:
	var nearest_other_position: Vector2 = Vector2.ZERO
	var host_position: Vector2 = Vector2(host_entry.get("local_position", Vector2.ZERO))
	var host_object_id: String = str(host_entry.get("object_id", ""))
	var nearest_distance_sq: float = INF
	for entry in host_entries:
		if str(entry.get("object_id", "")) == host_object_id:
			continue
		var other_position: Vector2 = Vector2(entry.get("local_position", Vector2.ZERO))
		var distance_sq: float = host_position.distance_squared_to(other_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest_other_position = other_position
	if nearest_distance_sq == INF:
		return rng.randf_range(0.0, TAU)
	return (host_position - nearest_other_position).angle()

static func _resolve_dynamic_star_orbit_band(profile: Dictionary) -> Dictionary:
	var inner_orbit_radius: float = maxf(
		float(profile.get("star_inner_orbit_au", 0.0)) * SimConstants.AU,
		_required_dynamic_star_host_clearance_radius(profile)
	)
	var outer_orbit_radius: float = maxf(
		inner_orbit_radius,
		float(profile.get("star_outer_orbit_au", 0.0)) * SimConstants.AU
	)
	return {
		"inner": inner_orbit_radius,
		"outer": outer_orbit_radius,
	}

static func _resolve_dynamic_star_shell_spacing(profile: Dictionary) -> float:
	return maxf(
		2.0 * _dynamic_star_planet_envelope_radius(profile) + 0.75 * SimConstants.AU,
		0.75 * SimConstants.AU
	)

static func _required_dynamic_star_host_clearance_radius(profile: Dictionary) -> float:
	return SimConstants.BLACK_HOLE_RADIUS \
		+ _max_dynamic_star_radius_for_profile(profile) \
		+ _dynamic_star_planet_envelope_radius(profile) \
		+ 0.75 * SimConstants.AU

static func _dynamic_star_planet_envelope_radius(profile: Dictionary) -> float:
	return _max_core_planet_orbit_radius(int(profile.get("planets_per_star", 0))) * SimConstants.AU

static func _max_dynamic_star_radius_for_profile(profile: Dictionary) -> float:
	var mass_scale_min: float = float(profile.get("star_mass_scale_min", 0.7))
	var mass_scale_max: float = maxf(
		mass_scale_min,
		float(profile.get("star_mass_scale_max", 1.3))
	)
	return SimConstants.STAR_RADIUS * sqrt(mass_scale_max)

static func _dynamic_star_host_capacity(profile: Dictionary) -> int:
	var orbit_band: Dictionary = _resolve_dynamic_star_orbit_band(profile)
	var inner_orbit_radius: float = float(orbit_band.get("inner", 0.0))
	var outer_orbit_radius: float = float(orbit_band.get("outer", inner_orbit_radius))
	if outer_orbit_radius + 0.001 < inner_orbit_radius:
		return 0
	var shell_spacing: float = _resolve_dynamic_star_shell_spacing(profile)
	return maxi(int(floor((outer_orbit_radius - inner_orbit_radius) / shell_spacing)) + 1, 1)

static func _build_dynamic_star_layout_plan_from_host_entries(
		host_entries: Array,
		profile: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var assignments: Array = []
	if host_entries.is_empty():
		return {
			"assignments": assignments,
			"dropped_star_count": 0,
		}

	var star_specs: Array = _build_dynamic_star_specs(profile, rng)
	var orbit_band: Dictionary = _resolve_dynamic_star_orbit_band(profile)
	var inner_orbit_radius: float = float(orbit_band.get("inner", 0.0))
	var shell_spacing: float = _resolve_dynamic_star_shell_spacing(profile)
	var planet_envelope_radius: float = _dynamic_star_planet_envelope_radius(profile)
	for host_entry in host_entries:
		host_entry["planned_count"] = 0
		host_entry["capacity"] = _dynamic_star_host_capacity(profile)

	for spec in star_specs:
		var best_host_index: int = _pick_dynamic_star_host_with_capacity(host_entries)
		if best_host_index < 0:
			break
		var shell_index: int = int(host_entries[best_host_index]["planned_count"])
		host_entries[best_host_index]["planned_count"] = shell_index + 1
		assignments.append({
			"host_object_id": str(host_entries[best_host_index]["object_id"]),
			"host_index": best_host_index,
			"shell_index": shell_index,
			"orbit_radius": inner_orbit_radius + float(shell_index) * shell_spacing,
			"mass_scale": float(spec["mass_scale"]),
			"planet_envelope_radius": planet_envelope_radius,
		})

	var host_star_counts: Dictionary = {}
	for host_index in range(host_entries.size()):
		host_star_counts[host_index] = int(host_entries[host_index]["planned_count"])
	for assignment in assignments:
		var host_index: int = int(assignment["host_index"])
		assignment["phase"] = _resolve_dynamic_star_phase(
			host_entries[host_index],
			int(assignment["shell_index"]),
			int(host_star_counts.get(host_index, 1))
		)

	return {
		"assignments": assignments,
		"dropped_star_count": maxi(star_specs.size() - assignments.size(), 0),
	}

static func _pick_dynamic_star_host_with_capacity(host_entries: Array) -> int:
	var best_host_index: int = -1
	var best_planned_count: int = INF
	for host_index in range(host_entries.size()):
		var planned_count: int = int(host_entries[host_index].get("planned_count", 0))
		var capacity: int = int(host_entries[host_index].get("capacity", 0))
		if planned_count >= capacity:
			continue
		if best_host_index < 0 or planned_count < best_planned_count:
			best_host_index = host_index
			best_planned_count = planned_count
	return best_host_index

static func _resolve_dynamic_star_phase(host_entry: Dictionary, shell_index: int, host_star_count: int) -> float:
	if host_star_count <= 1:
		return wrapf(float(host_entry.get("base_phase", 0.0)), 0.0, TAU)
	var base_phase: float = float(host_entry.get("base_phase", 0.0))
	var nearest_other_distance: float = float(host_entry.get("nearest_other_distance", INF))
	if nearest_other_distance == INF:
		var phase_step: float = TAU / float(host_star_count)
		return wrapf(base_phase + float(shell_index) * phase_step, 0.0, TAU)
	var phase_span: float = PI
	var centered_index: float = float(shell_index) - (float(host_star_count - 1) * 0.5)
	var phase_step: float = phase_span / maxf(float(host_star_count - 1), 1.0)
	return wrapf(base_phase + centered_index * phase_step, 0.0, TAU)

static func _select_initial_host_black_hole_candidate(
		sim_world: SimWorld,
		cluster_state: ClusterState) -> Dictionary:
	if sim_world == null or cluster_state == null:
		return {}
	var primary_object_id: String = cluster_state.get_primary_black_hole_object_id()
	var bound_stars_by_host_id: Dictionary = _bound_stars_by_host_id(sim_world)
	var star_bearing_candidates: Array = []
	for black_hole_entry in sim_world.get_black_holes():
		var black_hole: SimBody = black_hole_entry
		var object_id: String = str(black_hole.persistent_object_id)
		var object_state: ClusterObjectState = cluster_state.get_object(object_id)
		var is_primary: bool = object_id == primary_object_id
		if object_state != null:
			is_primary = is_primary or bool(object_state.descriptor.get("is_primary", false))
		var bound_stars: Array = bound_stars_by_host_id.get(black_hole.id, [])
		if bound_stars.is_empty():
			continue
		var candidate := {
			"body": black_hole,
			"object_id": object_id,
			"is_primary": is_primary,
			"bound_stars": bound_stars,
		}
		if is_primary:
			return candidate
		star_bearing_candidates.append(candidate)
	if star_bearing_candidates.is_empty():
		return {}
	star_bearing_candidates.sort_custom(func(a, b):
		var bound_stars_a: Array = a.get("bound_stars", [])
		var bound_stars_b: Array = b.get("bound_stars", [])
		var star_count_a: int = bound_stars_a.size()
		var star_count_b: int = bound_stars_b.size()
		if star_count_a != star_count_b:
			return star_count_a > star_count_b
		if bool(a.get("is_primary", false)) != bool(b.get("is_primary", false)):
			return bool(a.get("is_primary", false))
		return str(a.get("object_id", "")) < str(b.get("object_id", ""))
	)
	return star_bearing_candidates[0]

static func _bound_stars_by_host_id(sim_world: SimWorld) -> Dictionary:
	var bound_stars_by_host_id: Dictionary = {}
	if sim_world == null:
		return bound_stars_by_host_id
	for body_entry in sim_world.bodies:
		var body: SimBody = body_entry
		if not body.active or body.body_type != SimBody.BodyType.STAR or body.orbit_parent_id < 0:
			continue
		if not bound_stars_by_host_id.has(body.orbit_parent_id):
			bound_stars_by_host_id[body.orbit_parent_id] = []
		bound_stars_by_host_id[body.orbit_parent_id].append(body)
	return bound_stars_by_host_id

static func _bound_planets_by_star_id(sim_world: SimWorld) -> Dictionary:
	var bound_planets_by_star_id: Dictionary = {}
	if sim_world == null:
		return bound_planets_by_star_id
	for body_entry in sim_world.bodies:
		var body: SimBody = body_entry
		if not body.active or body.body_type != SimBody.BodyType.PLANET or body.orbit_parent_id < 0:
			continue
		if not bound_planets_by_star_id.has(body.orbit_parent_id):
			bound_planets_by_star_id[body.orbit_parent_id] = []
		bound_planets_by_star_id[body.orbit_parent_id].append(body)
	return bound_planets_by_star_id

static func _bound_child_distance_to_parent(child: SimBody, parent: SimBody) -> float:
	if child == null:
		return 0.0
	if parent != null and parent.active:
		return child.position.distance_to(parent.position)
	if child.orbit_parent_id >= 0 and child.orbit_radius > 0.0:
		return child.orbit_radius
	return 0.0

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

static func _core_planet_layout_data(index: int, total_count: int) -> Dictionary:
	var orbit_radii_au := [0.38, 1.0, 2.2, 3.0]
	var masses := [800.0, 1100.0, 2800.0, 1900.0]
	var temperatures := [400.0, 280.0, 120.0, 90.0]
	if index < orbit_radii_au.size():
		return {
			"orbit_radius_au": orbit_radii_au[index],
			"mass": masses[index],
			"temperature": temperatures[index],
		}
	var extra_index: int = index - orbit_radii_au.size() + 1
	var progression: float = float(extra_index) / maxf(1.0, float(total_count - orbit_radii_au.size() + 1))
	return {
		"orbit_radius_au": orbit_radii_au[orbit_radii_au.size() - 1] + 1.35 * float(extra_index),
		"mass": lerpf(1900.0, 850.0, progression),
		"temperature": maxf(35.0, 90.0 - 12.0 * float(extra_index)),
	}

static func _max_core_planet_orbit_radius(total_count: int) -> float:
	var max_orbit_radius_au: float = 0.0
	for index in range(maxi(total_count, 0)):
		max_orbit_radius_au = maxf(
			max_orbit_radius_au,
			float(_core_planet_layout_data(index, total_count)["orbit_radius_au"])
		)
	return max_orbit_radius_au

static func _make_core_planet(
		star: SimBody,
		index: int,
		total_count: int,
		profile: Dictionary,
		rng: RandomNumberGenerator) -> SimBody:
	var layout: Dictionary = _core_planet_layout_data(index, total_count)
	var angle: float = (float(index) / maxf(1.0, float(total_count))) * TAU
	var orbit_radius_au: float = float(layout["orbit_radius_au"])
	var mass: float = float(layout["mass"])
	var material: int = SimBody.MaterialType.MIXED
	var temperature: float = float(layout["temperature"])
	var temperature_offset: float = float(profile.get("planet_temperature_offset", 0.0))
	var material_profile: Dictionary = profile.get("planet_material_profile", {})
	material = _pick_material_from_profile(material_profile, rng, SimBody.MaterialType.MIXED)
	temperature = clampf(temperature + temperature_offset, 20.0, 750.0)

	return _make_planet(
		star,
		orbit_radius_au * SimConstants.AU,
		mass,
		material,
		temperature,
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

static func _make_disturbance_body(
		star: SimBody,
		profile: Dictionary,
		rng: RandomNumberGenerator,
		index: int) -> SimBody:
	var orbital_radius: float = rng.randf_range(2.6, 3.5) * SimConstants.AU
	var angle: float = rng.randf_range(0.0, TAU)
	var eccentricity: float = rng.randf_range(
		float(profile.get("disturbance_eccentricity_min", 0.03)),
		float(profile.get("disturbance_eccentricity_max", 0.18))
	)
	var mass: float = rng.randf_range(SimConstants.ASTEROID_MASS_MIN, SimConstants.ASTEROID_MASS_MAX)
	var material: int = _pick_material_from_profile(
		profile.get("disturbance_material_profile", {}),
		rng,
		SimBody.MaterialType.METALLIC if index % 2 == 0 else SimBody.MaterialType.ROCKY
	)
	return _make_asteroid(star, orbital_radius, angle, eccentricity, mass, material, rng)

static func _pick_material_from_profile(
		material_profile: Dictionary,
		rng: RandomNumberGenerator,
		fallback_material: int = SimBody.MaterialType.MIXED) -> int:
	if material_profile == null or material_profile.is_empty():
		return fallback_material
	var normalized_profile: Dictionary = {
		"rocky": maxf(float(material_profile.get("rocky", 0.0)), 0.0),
		"icy": maxf(float(material_profile.get("icy", 0.0)), 0.0),
		"metallic": maxf(float(material_profile.get("metallic", 0.0)), 0.0),
		"mixed": maxf(float(material_profile.get("mixed", 0.0)), 0.0),
	}
	var total_weight: float = 0.0
	for key in normalized_profile.keys():
		total_weight += float(normalized_profile[key])
	if total_weight <= 0.0:
		return fallback_material
	var roll: float = rng.randf() * total_weight
	var cursor: float = 0.0
	for key in ["rocky", "icy", "metallic", "mixed"]:
		cursor += float(normalized_profile.get(key, 0.0))
		if roll <= cursor:
			match key:
				"rocky":
					return SimBody.MaterialType.ROCKY
				"icy":
					return SimBody.MaterialType.ICY
				"metallic":
					return SimBody.MaterialType.METALLIC
				"mixed":
					return SimBody.MaterialType.MIXED
	return fallback_material

static func _place_in_orbit(body: SimBody, parent: SimBody,
		orbital_radius: float, angle: float, eccentricity: float) -> void:
	var radial: Vector2 = Vector2(cos(angle), sin(angle))
	body.position = parent.position + radial * orbital_radius
	var orbit_offset: Vector2 = body.position - parent.position
	var semi_major: float = orbital_radius / (1.0 - eccentricity) \
			if eccentricity > 0.0 else orbital_radius
	var speed: float = sqrt(SimConstants.G * parent.mass * (2.0 / orbital_radius - 1.0 / semi_major))
	# Derive tangent from the stored orbit offset so position and velocity remain
	# numerically orthogonal even after float rounding in the placed position.
	var tangent: Vector2 = Vector2(-orbit_offset.y, orbit_offset.x)
	var tangential_scale: float = speed / orbital_radius if orbital_radius > 0.0 else 0.0
	body.velocity = parent.velocity + tangent * tangential_scale
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

static func _kind_for_body_type(body_type: int) -> String:
	match body_type:
		SimBody.BodyType.BLACK_HOLE:
			return "black_hole"
		SimBody.BodyType.STAR:
			return "star"
		SimBody.BodyType.PLANET:
			return "planet"
		SimBody.BodyType.ASTEROID:
			return "asteroid"
		SimBody.BodyType.FRAGMENT:
			return "fragment"
		_:
			return "body"

static func _body_type_for_kind(kind: String) -> int:
	match kind:
		"black_hole":
			return SimBody.BodyType.BLACK_HOLE
		"star":
			return SimBody.BodyType.STAR
		"planet":
			return SimBody.BodyType.PLANET
		"asteroid":
			return SimBody.BodyType.ASTEROID
		"fragment":
			return SimBody.BodyType.FRAGMENT
		_:
			return SimBody.BodyType.ASTEROID

static func _kind_sort_rank(kind: String) -> int:
	match kind:
		"black_hole":
			return 0
		"star":
			return 1
		"planet":
			return 2
		"asteroid":
			return 3
		"fragment":
			return 4
		_:
			return 99

static func _make_cluster_object_id(cluster_id: int, kind: String, index: int) -> String:
	return "cluster_%d:%s_%d" % [cluster_id, kind, index]

static func _make_child_object_id(parent_object_id: String, kind: String, index: int) -> String:
	return "%s:%s_%d" % [parent_object_id, kind, index]

static func _ensure_body_object_id(
		cluster_id: int,
		body: SimBody,
		kind_indices: Dictionary,
		used_object_ids: Dictionary) -> String:
	var kind: String = _kind_for_body_type(body.body_type)
	var next_index: int = int(kind_indices.get(kind, 0))
	if body.persistent_object_id != "":
		used_object_ids[body.persistent_object_id] = true
		kind_indices[kind] = next_index + 1
		return body.persistent_object_id
	var candidate_id: String = _make_cluster_object_id(cluster_id, kind, next_index)
	while used_object_ids.has(candidate_id):
		next_index += 1
		candidate_id = _make_cluster_object_id(cluster_id, kind, next_index)
	kind_indices[kind] = next_index + 1
	body.persistent_object_id = candidate_id
	used_object_ids[body.persistent_object_id] = true
	return body.persistent_object_id

static func _resolve_parent_object_id(body: SimBody, persistent_id_by_sim_id: Dictionary) -> String:
	if body.orbit_parent_id < 0:
		return ""
	return str(persistent_id_by_sim_id.get(body.orbit_parent_id, ""))

static func _derive_runtime_object_seed(cluster_seed: int, object_id: String) -> int:
	return absi((cluster_seed + 1) * 8_191 + object_id.hash())

static func _build_object_state_from_body(
		cluster_state: ClusterState,
		body: SimBody,
		object_id: String,
		residency_state: int,
		persistent_id_by_sim_id: Dictionary = {}) -> ClusterObjectState:
	var object_state := ClusterObjectState.new()
	object_state.object_id = object_id
	object_state.kind = _kind_for_body_type(body.body_type)
	object_state.residency_state = residency_state
	object_state.local_position = body.position
	object_state.local_velocity = body.velocity
	object_state.age = body.age
	var previous_state: ClusterObjectState = cluster_state.get_object(object_id)
	if previous_state != null:
		object_state.seed = previous_state.seed
		object_state.descriptor = previous_state.descriptor.duplicate(true)
	else:
		object_state.seed = _derive_runtime_object_seed(cluster_state.cluster_seed, object_id)
		object_state.descriptor = {}
	object_state.descriptor["body_type"] = body.body_type
	object_state.descriptor["material_type"] = body.material_type
	object_state.descriptor["influence_level"] = body.influence_level
	object_state.descriptor["mass"] = body.mass
	object_state.descriptor["radius"] = body.radius
	object_state.descriptor["temperature"] = body.temperature
	object_state.descriptor["kinematic"] = body.kinematic
	object_state.descriptor["scripted_orbit_enabled"] = body.scripted_orbit_enabled
	object_state.descriptor["orbit_binding_state"] = body.orbit_binding_state
	object_state.descriptor["orbit_radius"] = body.orbit_radius
	object_state.descriptor["orbit_angle"] = body.orbit_angle
	object_state.descriptor["orbit_angular_speed"] = body.orbit_angular_speed
	object_state.descriptor["last_dominant_bh_id"] = body.last_dominant_bh_id
	object_state.descriptor["dominant_bh_handoff_count"] = body.dominant_bh_handoff_count
	object_state.descriptor["pending_host_bh_id"] = body.pending_host_bh_id
	object_state.descriptor["pending_host_time"] = body.pending_host_time
	object_state.descriptor["confirmed_host_handoff_count"] = body.confirmed_host_handoff_count
	object_state.descriptor["debris_mass"] = body.debris_mass
	object_state.descriptor["sleeping"] = body.sleeping
	object_state.descriptor["active"] = body.active
	object_state.descriptor["parent_object_id"] = _resolve_parent_object_id(body, persistent_id_by_sim_id)
	return object_state

static func _build_transit_object_state_from_body(
		cluster_state: ClusterState,
		body: SimBody,
		object_id: String,
		global_position: Vector2):
	var object_state: ClusterObjectState = _build_object_state_from_body(
		cluster_state,
		body,
		object_id,
		ObjectResidencyState.State.IN_TRANSIT
	)
	var transit_state = TRANSIT_OBJECT_STATE_SCRIPT.new()
	transit_state.object_id = object_state.object_id
	transit_state.kind = object_state.kind
	transit_state.residency_state = ObjectResidencyState.State.IN_TRANSIT
	transit_state.source_cluster_id = cluster_state.cluster_id
	transit_state.transfer_group_id = str(object_state.descriptor.get("transfer_group_id", ""))
	transit_state.global_position = global_position
	transit_state.global_velocity = body.velocity
	transit_state.age = object_state.age
	transit_state.seed = object_state.seed
	transit_state.descriptor = object_state.descriptor.duplicate(true)
	return transit_state

static func _build_cluster_object_state_from_transit(
		transit_state,
		cluster_local_position: Vector2,
		residency_state: int) -> ClusterObjectState:
	var object_state := ClusterObjectState.new()
	object_state.object_id = transit_state.object_id
	object_state.kind = transit_state.kind
	object_state.residency_state = residency_state
	object_state.local_position = cluster_local_position
	object_state.local_velocity = transit_state.global_velocity
	object_state.age = transit_state.age
	object_state.seed = transit_state.seed
	object_state.descriptor = transit_state.descriptor.duplicate(true)
	object_state.descriptor["transfer_group_id"] = transit_state.transfer_group_id
	object_state.descriptor["active"] = true
	object_state.descriptor["sleeping"] = false
	return object_state

static func refresh_transit_target_assignment(galaxy_state: GalaxyState, transit_state) -> void:
	if galaxy_state == null or transit_state == null:
		return
	_discover_worldgen_clusters_around_position(galaxy_state, transit_state.global_position)
	var source_cluster: ClusterState = galaxy_state.get_cluster(transit_state.source_cluster_id)
	if source_cluster != null \
			and OBJECT_RESIDENCY_POLICY_SCRIPT.can_import_transit_object_into_cluster(
				transit_state,
				source_cluster
			):
		transit_state.target_cluster_id = source_cluster.cluster_id
		transit_state.arrival_phase = TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.ARRIVING
		return
	var current_target: ClusterState = galaxy_state.get_cluster(transit_state.target_cluster_id)
	if current_target != null and current_target.cluster_id == transit_state.source_cluster_id:
		current_target = null
	var preferred_target: ClusterState = _find_best_non_source_transit_target_cluster_for_position(
		galaxy_state,
		transit_state.global_position,
		transit_state.source_cluster_id
	)
	if current_target != null \
			and OBJECT_RESIDENCY_POLICY_SCRIPT.should_keep_transit_target(
				transit_state,
				current_target,
				preferred_target
			):
		preferred_target = current_target
	if preferred_target == null:
		transit_state.target_cluster_id = -1
		transit_state.arrival_phase = TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.UNASSIGNED
		return
	transit_state.target_cluster_id = preferred_target.cluster_id
	if OBJECT_RESIDENCY_POLICY_SCRIPT.can_import_transit_object_into_cluster(transit_state, preferred_target):
		transit_state.arrival_phase = TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.ARRIVING
	else:
		transit_state.arrival_phase = TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.EN_ROUTE

static func _refresh_transit_group_target_assignment(galaxy_state: GalaxyState, transit_group) -> void:
	if galaxy_state == null or transit_group == null:
		return
	_discover_worldgen_clusters_around_position(galaxy_state, transit_group.global_position)
	var source_cluster: ClusterState = galaxy_state.get_cluster(transit_group.source_cluster_id)
	if source_cluster != null \
			and OBJECT_RESIDENCY_POLICY_SCRIPT.is_position_within_cluster_import_radius(
				transit_group.global_position,
				source_cluster
			):
		transit_group.target_cluster_id = source_cluster.cluster_id
		transit_group.arrival_phase = TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.ARRIVING
		return
	var current_target: ClusterState = galaxy_state.get_cluster(transit_group.target_cluster_id)
	if current_target != null and current_target.cluster_id == transit_group.source_cluster_id:
		current_target = null
	var preferred_target: ClusterState = _find_best_non_source_transit_target_cluster_for_position(
		galaxy_state,
		transit_group.global_position,
		transit_group.source_cluster_id
	)
	if current_target != null \
			and OBJECT_RESIDENCY_POLICY_SCRIPT.should_keep_routing_target_for_position(
				transit_group.global_position,
				current_target,
				preferred_target
			):
		preferred_target = current_target
	if preferred_target == null:
		transit_group.target_cluster_id = -1
		transit_group.arrival_phase = TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.UNASSIGNED
		return
	transit_group.target_cluster_id = preferred_target.cluster_id
	if OBJECT_RESIDENCY_POLICY_SCRIPT.is_position_within_cluster_import_radius(
			transit_group.global_position,
			preferred_target
	):
		transit_group.arrival_phase = TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.ARRIVING
	else:
		transit_group.arrival_phase = TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.EN_ROUTE

static func _find_best_non_source_transit_target_cluster_for_position(
		galaxy_state: GalaxyState,
		global_position: Vector2,
		source_cluster_id: int) -> ClusterState:
	if galaxy_state == null:
		return null
	var matched_cluster: ClusterState = null
	var best_score: float = INF
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id == source_cluster_id:
			continue
		var claim_score: float = OBJECT_RESIDENCY_POLICY_SCRIPT.cluster_claim_score_for_position(
			global_position,
			cluster_state
		)
		if claim_score < best_score:
			best_score = claim_score
			matched_cluster = cluster_state
	return matched_cluster

static func _accept_transit_object_into_cluster(cluster_state: ClusterState, transit_state) -> void:
	if cluster_state == null or transit_state == null:
		return
	var residency_state: int = OBJECT_RESIDENCY_POLICY_SCRIPT.residency_state_for_cluster_activation(
		cluster_state.activation_state
	)
	var cluster_local_position: Vector2 = transit_state.global_position - cluster_state.global_center
	var object_state: ClusterObjectState = _build_cluster_object_state_from_transit(
		transit_state,
		cluster_local_position,
		residency_state
	)
	cluster_state.register_object(object_state)
	var object_radius: float = float(object_state.descriptor.get("radius", 0.0))
	cluster_state.update_runtime_extent(cluster_local_position.length() + object_radius)

static func _is_simplified_analytic_orbiter(object_state: ClusterObjectState) -> bool:
	return bool(object_state.descriptor.get("scripted_orbit_enabled", false)) \
		and int(object_state.descriptor.get(
			"orbit_binding_state",
			SimBody.OrbitBindingState.FREE_DYNAMIC
		)) in [
			SimBody.OrbitBindingState.BOUND_ANALYTIC,
			SimBody.OrbitBindingState.CAPTURED_ANALYTIC,
		]

static func _estimate_runtime_cluster_radius(object_registry: Dictionary) -> float:
	var max_extent: float = 0.0
	for object_state in object_registry.values():
		var object_radius: float = float(object_state.descriptor.get("radius", 0.0))
		max_extent = maxf(max_extent, object_state.local_position.length() + object_radius)
	return max_extent

static func _discover_worldgen_clusters_around_position(
		galaxy_state: GalaxyState,
		global_position: Vector2) -> void:
	if galaxy_state == null or galaxy_state.worldgen_config == null:
		return
	var worldgen := WORLDGEN_SCRIPT.new(galaxy_state.worldgen_config)
	var sector_coord: Vector2i = worldgen.sector_coord_for_global_position(global_position)
	GalaxyBuilder.discover_sector_neighborhood(galaxy_state, worldgen, sector_coord, 1)
