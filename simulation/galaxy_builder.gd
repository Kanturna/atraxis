## Builds deterministic galaxy and cluster state from debug/bootstrap config.
class_name GalaxyBuilder
extends RefCounted

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const ANCHOR_FIELD_SCRIPT := preload("res://simulation/anchor_field.gd")
const WORLDGEN_CONFIG_SCRIPT := preload("res://simulation/galaxy_worldgen_config.gd")
const WORLDGEN_SCRIPT := preload("res://simulation/galaxy_worldgen.gd")
const WORLDGEN_MAPPING_SCRIPT := preload("res://simulation/galaxy_worldgen_mapping.gd")

static func build_from_config(start_config) -> GalaxyState:
	var config = start_config if start_config != null else START_CONFIG_SCRIPT.new()
	var safe_config = config.copy()
	safe_config.clamp_values()
	var public_config = safe_config.canonicalized_public_copy()

	var galaxy_state := GalaxyState.new()
	galaxy_state.galaxy_seed = public_config.seed
	var worldgen_config = _build_public_worldgen_config(public_config)
	galaxy_state.set_worldgen_config(worldgen_config)

	_build_worldgen_main_universe(galaxy_state, worldgen_config)

	return galaxy_state

static func build_fixture_from_config(start_config) -> GalaxyState:
	var config = start_config if start_config != null else START_CONFIG_SCRIPT.new()
	var safe_config = config.copy()
	safe_config.clamp_values()

	var galaxy_state := GalaxyState.new()
	galaxy_state.galaxy_seed = safe_config.seed

	if safe_config.uses_inflow_lab_profile():
		_build_inflow_lab_fixture_galaxy(galaxy_state, safe_config)
	elif safe_config.uses_reference_star_carriers():
		_build_reference_fixture_galaxy(galaxy_state, safe_config)
	else:
		_build_main_universe_galaxy(galaxy_state, safe_config)

	return galaxy_state

static func discover_sector_into_galaxy(
		galaxy_state: GalaxyState,
		worldgen,
		sector_coord: Vector2i):
	if galaxy_state == null or worldgen == null:
		return null
	var region_descriptor = galaxy_state.discover_sector(sector_coord, worldgen)
	for candidate_descriptor in galaxy_state.get_sector_candidate_descriptors(sector_coord):
		if galaxy_state.has_cluster(candidate_descriptor.cluster_id):
			continue
		galaxy_state.add_cluster(_build_cluster_state_from_candidate(
			worldgen.config,
			candidate_descriptor
		))
	return region_descriptor

static func discover_sector_neighborhood(
		galaxy_state: GalaxyState,
		worldgen,
		center_sector_coord: Vector2i,
		radius: int = 1) -> void:
	if galaxy_state == null or worldgen == null:
		return
	for y in range(center_sector_coord.y - radius, center_sector_coord.y + radius + 1):
		for x in range(center_sector_coord.x - radius, center_sector_coord.x + radius + 1):
			discover_sector_into_galaxy(galaxy_state, worldgen, Vector2i(x, y))

static func _build_worldgen_main_universe(
		galaxy_state: GalaxyState,
		worldgen_config) -> void:
	var worldgen := WORLDGEN_SCRIPT.new(worldgen_config)
	discover_sector_neighborhood(galaxy_state, worldgen, Vector2i.ZERO, 1)
	if galaxy_state.get_cluster_count() == 0:
		var fallback_candidate = worldgen.build_starter_fallback_candidate(galaxy_state.galaxy_seed)
		galaxy_state.add_cluster(_build_cluster_state_from_candidate(worldgen_config, fallback_candidate))
	var primary_cluster: ClusterState = _find_nearest_cluster_to_origin(galaxy_state)
	if primary_cluster != null:
		galaxy_state.primary_cluster_id = primary_cluster.cluster_id

static func _build_main_universe_galaxy(galaxy_state: GalaxyState, config) -> void:
	match config.anchor_topology:
		START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH:
			var local_specs: Array = ANCHOR_FIELD_SCRIPT.build_local_black_hole_specs(
				config.black_hole_count,
				config.field_spacing_au,
				config.black_hole_mass
			)
			var cluster_state: ClusterState = _make_cluster_state(
				config,
				0,
				Vector2.ZERO,
				"field_patch_cluster",
				local_specs,
				true,
				{
					"topology_role": "field_patch_local_system",
				}
			)
			galaxy_state.add_cluster(cluster_state)
		START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER:
			for cluster_spec in ANCHOR_FIELD_SCRIPT.build_galaxy_cluster_cluster_specs(
					config.black_hole_count,
					config.galaxy_cluster_count,
					config.galaxy_cluster_radius_au,
					config.galaxy_void_scale,
					config.black_hole_mass):
				var cluster_state: ClusterState = _make_cluster_state(
					config,
					cluster_spec["cluster_id"],
					cluster_spec["global_center"],
					"galaxy_cluster_primary" if cluster_spec["is_primary"] else "galaxy_cluster_remote",
					cluster_spec["local_black_hole_specs"],
					cluster_spec["is_primary"],
					{
						"topology_role": "galaxy_cluster_map",
					}
				)
				galaxy_state.add_cluster(cluster_state)
				if cluster_spec["is_primary"]:
					galaxy_state.primary_cluster_id = cluster_state.cluster_id
		_:
			var central_specs: Array = ANCHOR_FIELD_SCRIPT.build_local_black_hole_specs(
				1,
				config.field_spacing_au,
				config.black_hole_mass
			)
			var cluster_state: ClusterState = _make_cluster_state(
				config,
				0,
				Vector2.ZERO,
				"central_anchor_cluster",
				central_specs,
				true,
				{
					"fixture_profile": "main_universe",
					"topology_role": "central_anchor_dev",
				}
			)
			galaxy_state.add_cluster(cluster_state)

static func _build_public_worldgen_config(start_config):
	var worldgen_config := WORLDGEN_CONFIG_SCRIPT.new()
	worldgen_config.sector_scale = start_config.sector_scale
	worldgen_config.cluster_density = start_config.cluster_density
	worldgen_config.void_strength = start_config.void_strength
	worldgen_config.bh_richness = start_config.bh_richness
	worldgen_config.star_richness = start_config.star_richness
	worldgen_config.rare_zone_frequency = start_config.rare_zone_frequency
	worldgen_config.black_hole_mass = start_config.black_hole_mass
	worldgen_config.star_inner_orbit_au = start_config.star_inner_orbit_au
	worldgen_config.star_outer_orbit_au = start_config.star_outer_orbit_au
	worldgen_config.spawn_radius_au = start_config.spawn_radius_au
	worldgen_config.spawn_spread_au = start_config.spawn_spread_au
	worldgen_config.inflow_speed_scale = start_config.inflow_speed_scale
	worldgen_config.tangential_bias = start_config.tangential_bias
	worldgen_config.chaos_body_count = start_config.chaos_body_count
	worldgen_config.legacy_generation_hints_enabled = start_config.has_legacy_generation_hint_override()
	worldgen_config.legacy_anchor_topology = start_config.anchor_topology
	worldgen_config.legacy_black_hole_count_hint = start_config.black_hole_count
	worldgen_config.legacy_galaxy_cluster_count_hint = start_config.galaxy_cluster_count
	worldgen_config.legacy_field_spacing_au_hint = start_config.field_spacing_au
	worldgen_config.legacy_star_count_hint = start_config.star_count
	worldgen_config.legacy_planets_per_star_hint = start_config.planets_per_star
	worldgen_config.legacy_disturbance_body_count_hint = start_config.disturbance_body_count
	worldgen_config.legacy_galaxy_cluster_radius_au_hint = start_config.galaxy_cluster_radius_au
	worldgen_config.legacy_galaxy_void_scale_hint = start_config.galaxy_void_scale
	worldgen_config.clamp_values()
	return worldgen_config

static func _build_reference_fixture_galaxy(galaxy_state: GalaxyState, config) -> void:
	var local_specs: Array = ANCHOR_FIELD_SCRIPT.build_local_black_hole_specs(
		1,
		config.field_spacing_au,
		config.black_hole_mass
	)
	var cluster_state: ClusterState = _make_cluster_state(
		config,
		0,
		Vector2.ZERO,
		"orbital_reference_fixture",
		local_specs,
		true,
		{
			"analytic_star_carriers": true,
			"fixture_profile": "orbital_reference",
			"topology_role": "central_anchor_dev",
		}
	)
	galaxy_state.add_cluster(cluster_state)

static func _build_inflow_lab_fixture_galaxy(galaxy_state: GalaxyState, config) -> void:
	var cluster_state := ClusterState.new()
	cluster_state.cluster_id = 0
	cluster_state.global_center = Vector2.ZERO
	cluster_state.cluster_seed = _derive_cluster_seed(config.seed, 0)
	cluster_state.classification = "inflow_lab_cluster"
	cluster_state.activation_state = ClusterActivationState.State.UNLOADED
	cluster_state.last_unloaded_runtime_time = 0.0
	cluster_state.last_relevance_runtime_time = 0.0
	cluster_state.cluster_blueprint = {
		"local_black_hole_specs": [],
		"primary_black_hole_object_id": "",
		"supported_object_kinds": ["black_hole", "star", "planet", "asteroid", "agent"],
		"supported_entity_kinds": ["agent", "unit", "creature"],
		"supported_residency_states": [
			ObjectResidencyState.State.RESIDENT,
			ObjectResidencyState.State.ACTIVE,
			ObjectResidencyState.State.SIMPLIFIED,
			ObjectResidencyState.State.IN_TRANSIT,
		],
	}
	cluster_state.simulation_profile = _build_simulation_profile(
		config,
		false,
		0,
		{
			"content_archetype": "inflow_lab",
			"fixture_profile": "inflow_lab",
			"topology_role": "central_anchor_dev",
		}
	)
	cluster_state.radius = _estimate_cluster_radius([], cluster_state.simulation_profile)
	galaxy_state.add_cluster(cluster_state)

static func _make_cluster_state(config, cluster_id: int, global_center: Vector2,
		classification: String, local_black_hole_specs: Array, spawn_anchor_content: bool,
		simulation_profile_overrides: Dictionary = {}) -> ClusterState:
	var cluster_state := ClusterState.new()
	cluster_state.cluster_id = cluster_id
	cluster_state.global_center = global_center
	cluster_state.cluster_seed = _derive_cluster_seed(config.seed, cluster_id)
	cluster_state.classification = classification
	cluster_state.activation_state = ClusterActivationState.State.UNLOADED
	cluster_state.last_unloaded_runtime_time = 0.0
	cluster_state.last_relevance_runtime_time = 0.0
	cluster_state.cluster_blueprint = {
		"local_black_hole_specs": local_black_hole_specs.duplicate(true),
		"primary_black_hole_object_id": "",
		"supported_object_kinds": ["black_hole", "star", "planet", "asteroid", "agent"],
		"supported_entity_kinds": ["agent", "unit", "creature"],
		"supported_residency_states": [
			ObjectResidencyState.State.RESIDENT,
			ObjectResidencyState.State.ACTIVE,
			ObjectResidencyState.State.SIMPLIFIED,
			ObjectResidencyState.State.IN_TRANSIT,
		],
	}
	cluster_state.simulation_profile = _build_simulation_profile(
		config,
		spawn_anchor_content,
		local_black_hole_specs.size(),
		simulation_profile_overrides
	)
	cluster_state.radius = _estimate_cluster_radius(local_black_hole_specs, cluster_state.simulation_profile)

	for spec in local_black_hole_specs:
		var object_state := ClusterObjectState.new()
		object_state.object_id = "cluster_%d:black_hole_%d" % [cluster_id, spec["id"]]
		object_state.kind = "black_hole"
		object_state.residency_state = ObjectResidencyState.State.RESIDENT
		object_state.local_position = spec["local_position"]
		object_state.seed = _derive_object_seed(cluster_state.cluster_seed, spec["id"])
		object_state.descriptor = {
			"mass": spec["mass"],
			"ring_index": spec["ring_index"],
			"is_primary": spec["is_primary"],
		}
		cluster_state.register_object(object_state)
		if spec["is_primary"]:
			cluster_state.cluster_blueprint["primary_black_hole_object_id"] = object_state.object_id

	return cluster_state

static func _build_cluster_state_from_candidate(
		worldgen_config,
		candidate_descriptor) -> ClusterState:
	var local_black_hole_specs: Array = ANCHOR_FIELD_SCRIPT.build_local_black_hole_specs(
		candidate_descriptor.bh_count,
		candidate_descriptor.bh_spacing_au,
		worldgen_config.black_hole_mass
	)
	var cluster_state := ClusterState.new()
	cluster_state.cluster_id = candidate_descriptor.cluster_id
	cluster_state.global_center = candidate_descriptor.global_center
	cluster_state.cluster_seed = candidate_descriptor.cluster_seed
	cluster_state.classification = candidate_descriptor.classification
	cluster_state.activation_state = ClusterActivationState.State.UNLOADED
	cluster_state.last_unloaded_runtime_time = 0.0
	cluster_state.last_relevance_runtime_time = 0.0
	cluster_state.cluster_blueprint = {
		"local_black_hole_specs": local_black_hole_specs.duplicate(true),
		"primary_black_hole_object_id": "",
		"supported_object_kinds": ["black_hole", "star", "planet", "asteroid", "agent"],
		"supported_entity_kinds": ["agent", "unit", "creature"],
		"supported_residency_states": [
			ObjectResidencyState.State.RESIDENT,
			ObjectResidencyState.State.ACTIVE,
			ObjectResidencyState.State.SIMPLIFIED,
			ObjectResidencyState.State.IN_TRANSIT,
		],
		"sector_coord": candidate_descriptor.sector_coord,
		"candidate_index": candidate_descriptor.candidate_index,
		"region_archetype": candidate_descriptor.region_archetype,
		"worldgen_bh_richness": candidate_descriptor.bh_richness,
		"worldgen_star_richness": candidate_descriptor.star_richness,
		"rare_zone_weight": candidate_descriptor.rare_zone_weight,
		"scrap_potential": candidate_descriptor.scrap_potential,
		"life_potential": candidate_descriptor.life_potential,
		"descriptor": candidate_descriptor.descriptor.duplicate(true),
	}
	cluster_state.simulation_profile = _build_worldgen_simulation_profile(
		worldgen_config,
		candidate_descriptor,
		local_black_hole_specs.size()
	)
	cluster_state.radius = _estimate_cluster_radius(local_black_hole_specs, cluster_state.simulation_profile)

	for spec in local_black_hole_specs:
		var object_state := ClusterObjectState.new()
		object_state.object_id = "cluster_%d:black_hole_%d" % [candidate_descriptor.cluster_id, spec["id"]]
		object_state.kind = "black_hole"
		object_state.residency_state = ObjectResidencyState.State.RESIDENT
		object_state.local_position = spec["local_position"]
		object_state.seed = _derive_object_seed(cluster_state.cluster_seed, spec["id"])
		object_state.descriptor = {
			"mass": spec["mass"],
			"ring_index": spec["ring_index"],
			"is_primary": spec["is_primary"],
		}
		cluster_state.register_object(object_state)
		if spec["is_primary"]:
			cluster_state.cluster_blueprint["primary_black_hole_object_id"] = object_state.object_id

	return cluster_state

static func _build_worldgen_simulation_profile(
		worldgen_config,
		candidate_descriptor,
		local_black_hole_count: int) -> Dictionary:
	var star_count: int = WORLDGEN_MAPPING_SCRIPT.candidate_star_count(worldgen_config, candidate_descriptor)
	var planets_per_star: int = WORLDGEN_MAPPING_SCRIPT.candidate_planets_per_star(worldgen_config, candidate_descriptor)
	var disturbance_body_count: int = WORLDGEN_MAPPING_SCRIPT.candidate_disturbance_count(worldgen_config, candidate_descriptor)
	return {
		"content_archetype": "anchor_orbital",
		"analytic_star_carriers": false,
		"fixture_profile": "main_universe_worldgen",
		"topology_role": "sector_worldgen_cluster",
		"has_runtime_snapshot": false,
		"spawn_anchor_content": true,
		"seed": candidate_descriptor.cluster_seed,
		"black_hole_mass": worldgen_config.black_hole_mass,
		"local_black_hole_count": local_black_hole_count,
		"star_count": star_count,
		"planets_per_star": planets_per_star,
		"disturbance_body_count": disturbance_body_count,
		"star_inner_orbit_au": worldgen_config.star_inner_orbit_au,
		"star_outer_orbit_au": worldgen_config.star_outer_orbit_au,
		"spawn_radius_au": worldgen_config.spawn_radius_au,
		"spawn_spread_au": worldgen_config.spawn_spread_au,
		"inflow_speed_scale": worldgen_config.inflow_speed_scale,
		"tangential_bias": worldgen_config.tangential_bias,
		"chaos_body_count": worldgen_config.chaos_body_count,
		"sector_coord": candidate_descriptor.sector_coord,
		"candidate_index": candidate_descriptor.candidate_index,
		"region_archetype": candidate_descriptor.region_archetype,
		"worldgen_bh_richness": candidate_descriptor.bh_richness,
		"worldgen_star_richness": candidate_descriptor.star_richness,
		"rare_zone_weight": candidate_descriptor.rare_zone_weight,
		"scrap_potential": candidate_descriptor.scrap_potential,
		"life_potential": candidate_descriptor.life_potential,
		"sector_scale": worldgen_config.sector_scale,
		"cluster_density": worldgen_config.cluster_density,
		"void_strength": worldgen_config.void_strength,
		"bh_richness": worldgen_config.bh_richness,
		"star_richness": worldgen_config.star_richness,
		"rare_zone_frequency": worldgen_config.rare_zone_frequency,
	}

static func _build_simulation_profile(
		config,
		spawn_anchor_content: bool,
		local_black_hole_count: int,
		overrides: Dictionary = {}) -> Dictionary:
	var star_count: int = config.star_count if spawn_anchor_content else 0
	var planets_per_star: int = config.planets_per_star if spawn_anchor_content else 0
	var disturbance_body_count: int = config.disturbance_body_count if spawn_anchor_content else 0

	var simulation_profile := {
		"content_archetype": "anchor_orbital",
		"analytic_star_carriers": false,
		"fixture_profile": "main_universe",
		"topology_role": "field_patch_local_system",
		"anchor_topology": config.anchor_topology,
		"requested_black_hole_count": config.black_hole_count,
		"requested_galaxy_cluster_count": config.galaxy_cluster_count,
		"has_runtime_snapshot": false,
		"spawn_anchor_content": spawn_anchor_content,
		"seed": config.seed,
		"black_hole_mass": config.black_hole_mass,
		"local_black_hole_count": local_black_hole_count,
		"star_count": star_count,
		"planets_per_star": planets_per_star,
		"disturbance_body_count": disturbance_body_count,
		"star_inner_orbit_au": config.star_inner_orbit_au,
		"star_outer_orbit_au": config.star_outer_orbit_au,
		"spawn_radius_au": config.spawn_radius_au,
		"spawn_spread_au": config.spawn_spread_au,
		"inflow_speed_scale": config.inflow_speed_scale,
		"tangential_bias": config.tangential_bias,
		"chaos_body_count": config.chaos_body_count,
	}
	for key in overrides.keys():
		simulation_profile[key] = overrides[key]
	return simulation_profile

static func _estimate_cluster_radius(local_black_hole_specs: Array, simulation_profile: Dictionary) -> float:
	var max_black_hole_offset: float = 0.0
	for spec in local_black_hole_specs:
		max_black_hole_offset = maxf(max_black_hole_offset, spec["local_position"].length())

	var radius_padding: float = 2.0 * SimConstants.AU
	var content_archetype: String = str(simulation_profile.get("content_archetype", "anchor_orbital"))
	if content_archetype == "inflow_lab":
		radius_padding = (
			simulation_profile.get("spawn_radius_au", 0.0)
			+ simulation_profile.get("spawn_spread_au", 0.0)
			+ 1.0
		) * SimConstants.AU
	else:
		radius_padding = maxf(
			radius_padding,
			simulation_profile.get("star_outer_orbit_au", 0.0) * SimConstants.AU
		)

	return max_black_hole_offset + radius_padding

static func _derive_cluster_seed(galaxy_seed: int, cluster_id: int) -> int:
	var derived: int = (galaxy_seed + 1) * 92_821 + (cluster_id + 1) * 68_911
	return absi(derived)

static func _derive_object_seed(cluster_seed: int, local_index: int) -> int:
	var derived: int = (cluster_seed + 1) * 31_337 + (local_index + 1) * 1_003
	return absi(derived)

static func _find_nearest_cluster_to_origin(galaxy_state: GalaxyState) -> ClusterState:
	if galaxy_state == null:
		return null
	var matched_cluster: ClusterState = null
	var best_distance: float = INF
	for cluster_state in galaxy_state.get_clusters():
		var distance: float = cluster_state.global_center.length()
		if distance < best_distance:
			best_distance = distance
			matched_cluster = cluster_state
	return matched_cluster
