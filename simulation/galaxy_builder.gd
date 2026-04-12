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
	var primary_cluster: ClusterState = _find_preferred_spawn_cluster(galaxy_state)
	if primary_cluster == null:
		var fallback_candidate = worldgen.build_starter_fallback_candidate(galaxy_state.galaxy_seed)
		var fallback_cluster: ClusterState = _build_cluster_state_from_candidate(worldgen_config, fallback_candidate)
		if not galaxy_state.has_cluster(fallback_cluster.cluster_id):
			galaxy_state.add_cluster(fallback_cluster)
		primary_cluster = galaxy_state.get_cluster(fallback_cluster.cluster_id)
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
	cluster_state.runtime_extent_radius = cluster_state.radius
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
	cluster_state.runtime_extent_radius = cluster_state.radius

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

	cluster_state.cluster_blueprint["preview_object_specs"] = WorldBuilder.build_cluster_preview_specs(
		cluster_state.cluster_id,
		local_black_hole_specs,
		cluster_state.simulation_profile,
		cluster_state.cluster_seed
	)

	return cluster_state

static func _build_cluster_state_from_candidate(
		worldgen_config,
		candidate_descriptor) -> ClusterState:
	var local_black_hole_specs: Array = ANCHOR_FIELD_SCRIPT.build_local_black_hole_specs(
		candidate_descriptor.bh_count,
		candidate_descriptor.bh_spacing_au,
		worldgen_config.black_hole_mass
	)
	var stored_descriptor: Dictionary = candidate_descriptor.descriptor if candidate_descriptor != null else {}
	var content_profile_variant = stored_descriptor.get("content_profile", null)
	var content_profile: Dictionary = content_profile_variant.duplicate(true) \
		if content_profile_variant is Dictionary \
		else WORLDGEN_MAPPING_SCRIPT.build_cluster_content_profile(worldgen_config, candidate_descriptor)
	var layout_targets_variant = stored_descriptor.get("layout_targets", null)
	var layout_targets: Dictionary = layout_targets_variant.duplicate(true) \
		if layout_targets_variant is Dictionary \
		else WORLDGEN_MAPPING_SCRIPT.build_candidate_layout_targets(
			worldgen_config,
			candidate_descriptor,
			content_profile
		)
	var layout_diagnostics: Dictionary = _build_cluster_layout_diagnostics(
		worldgen_config,
		candidate_descriptor.radius,
		local_black_hole_specs,
		content_profile,
		layout_targets
	)
	var content_markers: Array = WORLDGEN_MAPPING_SCRIPT.build_scrap_markers(
		candidate_descriptor,
		content_profile
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
		"worldgen_radius": candidate_descriptor.radius,
		"content_profile": content_profile.duplicate(true),
		"layout_targets": layout_targets.duplicate(true),
		"layout_diagnostics": layout_diagnostics.duplicate(true),
		"content_markers": content_markers.duplicate(true),
		"descriptor": candidate_descriptor.descriptor.duplicate(true),
	}
	cluster_state.simulation_profile = _build_worldgen_simulation_profile(
		worldgen_config,
		candidate_descriptor,
		local_black_hole_specs.size(),
		content_profile,
		layout_diagnostics
	)
	cluster_state.radius = candidate_descriptor.radius
	cluster_state.runtime_extent_radius = cluster_state.radius

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

	cluster_state.cluster_blueprint["preview_object_specs"] = WorldBuilder.build_cluster_preview_specs(
		cluster_state.cluster_id,
		local_black_hole_specs,
		cluster_state.simulation_profile,
		cluster_state.cluster_seed
	)

	return cluster_state

static func _build_worldgen_simulation_profile(
		worldgen_config,
		candidate_descriptor,
		local_black_hole_count: int,
		content_profile: Dictionary,
		layout_diagnostics: Dictionary = {}) -> Dictionary:
	var profile := {
		"content_archetype": str(content_profile.get("content_archetype", candidate_descriptor.region_archetype)),
		"analytic_star_carriers": false,
		"fixture_profile": "main_universe_worldgen",
		"topology_role": "sector_worldgen_cluster",
		"has_runtime_snapshot": false,
		"spawn_anchor_content": true,
		"seed": candidate_descriptor.cluster_seed,
		"black_hole_mass": worldgen_config.black_hole_mass,
		"local_black_hole_count": local_black_hole_count,
		"star_count": int(content_profile.get("star_count", 0)),
		"planets_per_star": int(content_profile.get("planets_per_star", 0)),
		"disturbance_body_count": int(content_profile.get("disturbance_body_count", 0)),
		"star_inner_orbit_au": float(content_profile.get("star_inner_orbit_au", worldgen_config.star_inner_orbit_au)),
		"star_outer_orbit_au": float(content_profile.get("star_outer_orbit_au", worldgen_config.star_outer_orbit_au)),
		"star_mass_scale_min": float(content_profile.get("star_mass_scale_min", 0.85)),
		"star_mass_scale_max": float(content_profile.get("star_mass_scale_max", 1.15)),
		"planet_temperature_offset": float(content_profile.get("planet_temperature_offset", 0.0)),
		"planet_material_profile": content_profile.get("planet_material_profile", {}).duplicate(true),
		"disturbance_eccentricity_min": float(content_profile.get("disturbance_eccentricity_min", 0.03)),
		"disturbance_eccentricity_max": float(content_profile.get("disturbance_eccentricity_max", 0.18)),
		"disturbance_material_profile": content_profile.get("disturbance_material_profile", {}).duplicate(true),
		"spawn_priority": int(content_profile.get("spawn_priority", 0)),
		"scrap_marker_count": int(content_profile.get("scrap_marker_count", 0)),
		"scrap_marker_layout": str(content_profile.get("scrap_marker_layout", "none")),
		"content_profile": content_profile.duplicate(true),
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
		"worldgen_radius": candidate_descriptor.radius,
		"sector_scale": worldgen_config.sector_scale,
		"cluster_density": worldgen_config.cluster_density,
		"void_strength": worldgen_config.void_strength,
		"bh_richness": worldgen_config.bh_richness,
		"star_richness": worldgen_config.star_richness,
		"rare_zone_frequency": worldgen_config.rare_zone_frequency,
	}
	for key in layout_diagnostics.keys():
		profile[key] = layout_diagnostics[key]
	profile["star_count"] = mini(
		int(profile.get("star_count", 0)),
		WorldBuilder.dynamic_star_safe_capacity(local_black_hole_count, profile)
	)
	return profile

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
	simulation_profile["star_count"] = mini(
		int(simulation_profile.get("star_count", 0)),
		WorldBuilder.dynamic_star_safe_capacity(local_black_hole_count, simulation_profile)
	)
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

static func _build_cluster_layout_diagnostics(
		worldgen_config,
		cluster_radius: float,
		local_black_hole_specs: Array,
		content_profile: Dictionary,
		layout_targets: Dictionary) -> Dictionary:
	var dominance_radius_au: float = float(layout_targets.get(
		"dominance_radius_au",
		WORLDGEN_MAPPING_SCRIPT.dominance_radius_au_for_config(worldgen_config)
	))
	var reserved_start_band_au: float = float(layout_targets.get(
		"reserved_start_band_au",
		maxf(
			worldgen_config.spawn_radius_au + worldgen_config.spawn_spread_au,
			float(content_profile.get("star_inner_orbit_au", worldgen_config.star_inner_orbit_au))
		)
	))
	var spacing_floor_au: float = float(layout_targets.get("spacing_floor_au", dominance_radius_au))
	var cluster_radius_floor_au: float = float(layout_targets.get(
		"cluster_radius_floor_au",
		float(content_profile.get("star_outer_orbit_au", worldgen_config.star_outer_orbit_au)) + 2.0
	))
	var min_bh_distance_au: float = _minimum_local_black_hole_distance_au(local_black_hole_specs)
	var primary_clearance_au: float = _primary_black_hole_clearance_au(local_black_hole_specs)
	var required_primary_clearance_au: float = reserved_start_band_au + dominance_radius_au
	var cluster_radius_au: float = cluster_radius / SimConstants.AU
	var primary_clearance_margin_au: float = required_primary_clearance_au \
		if primary_clearance_au < 0.0 \
		else primary_clearance_au - required_primary_clearance_au
	var cluster_radius_margin_au: float = cluster_radius_au - cluster_radius_floor_au
	var has_primary_clearance_issue: bool = primary_clearance_au >= 0.0 \
		and primary_clearance_margin_au + 0.001 < 0.0
	var has_cluster_radius_issue: bool = cluster_radius_margin_au + 0.001 < 0.0
	var spawn_viable: bool = not has_primary_clearance_issue and not has_cluster_radius_issue
	var spawn_viability_reason: String = "ok"
	if has_primary_clearance_issue and has_cluster_radius_issue:
		spawn_viability_reason = "primary_clearance_and_cluster_radius_below_floor"
	elif has_primary_clearance_issue:
		spawn_viability_reason = "primary_clearance_below_start_band"
	elif has_cluster_radius_issue:
		spawn_viability_reason = "cluster_radius_below_orbit_band"
	return {
		"layout_dominance_radius_au": dominance_radius_au,
		"layout_reserved_start_band_au": reserved_start_band_au,
		"layout_spacing_floor_au": spacing_floor_au,
		"layout_cluster_radius_floor_au": cluster_radius_floor_au,
		"layout_min_bh_distance_au": min_bh_distance_au,
		"layout_primary_clearance_au": primary_clearance_au,
		"layout_required_primary_clearance_au": required_primary_clearance_au,
		"layout_primary_clearance_margin_au": primary_clearance_margin_au,
		"layout_cluster_radius_margin_au": cluster_radius_margin_au,
		"spawn_viable": spawn_viable,
		"spawn_viability_reason": spawn_viability_reason,
	}

static func _minimum_local_black_hole_distance_au(local_black_hole_specs: Array) -> float:
	if local_black_hole_specs.size() < 2:
		return -1.0
	var min_distance: float = INF
	for left_index in range(local_black_hole_specs.size()):
		for right_index in range(left_index + 1, local_black_hole_specs.size()):
			min_distance = minf(
				min_distance,
				Vector2(local_black_hole_specs[left_index]["local_position"]).distance_to(
					Vector2(local_black_hole_specs[right_index]["local_position"])
				)
			)
	return min_distance / SimConstants.AU if min_distance < INF else -1.0

static func _primary_black_hole_clearance_au(local_black_hole_specs: Array) -> float:
	if local_black_hole_specs.size() < 2:
		return -1.0
	var primary_spec: Dictionary = local_black_hole_specs[0]
	for spec in local_black_hole_specs:
		if bool(spec.get("is_primary", false)):
			primary_spec = spec
			break
	var primary_position: Vector2 = Vector2(primary_spec.get("local_position", Vector2.ZERO))
	var primary_id: int = int(primary_spec.get("id", -1))
	var min_distance: float = INF
	for spec in local_black_hole_specs:
		if int(spec.get("id", -2)) == primary_id:
			continue
		min_distance = minf(
			min_distance,
			primary_position.distance_to(Vector2(spec.get("local_position", Vector2.ZERO)))
		)
	return min_distance / SimConstants.AU if min_distance < INF else -1.0

static func _derive_cluster_seed(galaxy_seed: int, cluster_id: int) -> int:
	var derived: int = (galaxy_seed + 1) * 92_821 + (cluster_id + 1) * 68_911
	return absi(derived)

static func _derive_object_seed(cluster_seed: int, local_index: int) -> int:
	var derived: int = (cluster_seed + 1) * 31_337 + (local_index + 1) * 1_003
	return absi(derived)

static func _find_preferred_spawn_cluster(galaxy_state: GalaxyState) -> ClusterState:
	if galaxy_state == null:
		return null
	var matched_cluster: ClusterState = null
	var best_primary_clearance_margin: float = -INF
	var best_cluster_radius_margin: float = -INF
	var best_spawn_priority: int = -9_999
	var best_distance: float = INF
	for cluster_state in galaxy_state.get_clusters():
		if not bool(cluster_state.simulation_profile.get("spawn_viable", false)):
			continue
		var primary_clearance_margin: float = float(cluster_state.simulation_profile.get(
			"layout_primary_clearance_margin_au",
			-INF
		))
		var cluster_radius_margin: float = float(cluster_state.simulation_profile.get(
			"layout_cluster_radius_margin_au",
			-INF
		))
		var spawn_priority: int = int(cluster_state.simulation_profile.get("spawn_priority", 0))
		var distance: float = cluster_state.global_center.length()
		if matched_cluster == null \
				or primary_clearance_margin > best_primary_clearance_margin + 0.001 \
				or (absf(primary_clearance_margin - best_primary_clearance_margin) <= 0.001
					and cluster_radius_margin > best_cluster_radius_margin + 0.001) \
				or (absf(primary_clearance_margin - best_primary_clearance_margin) <= 0.001
					and absf(cluster_radius_margin - best_cluster_radius_margin) <= 0.001
					and spawn_priority > best_spawn_priority) \
				or (absf(primary_clearance_margin - best_primary_clearance_margin) <= 0.001
					and absf(cluster_radius_margin - best_cluster_radius_margin) <= 0.001
					and spawn_priority == best_spawn_priority
					and distance < best_distance) \
				or (absf(primary_clearance_margin - best_primary_clearance_margin) <= 0.001
					and absf(cluster_radius_margin - best_cluster_radius_margin) <= 0.001
					and spawn_priority == best_spawn_priority and is_equal_approx(distance, best_distance)
					and cluster_state.cluster_id < matched_cluster.cluster_id):
			best_primary_clearance_margin = primary_clearance_margin
			best_cluster_radius_margin = cluster_radius_margin
			best_spawn_priority = spawn_priority
			best_distance = distance
			matched_cluster = cluster_state
	return matched_cluster
