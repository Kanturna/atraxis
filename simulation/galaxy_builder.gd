## Builds deterministic galaxy and cluster state from debug/bootstrap config.
class_name GalaxyBuilder
extends RefCounted

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const ANCHOR_FIELD_SCRIPT := preload("res://simulation/anchor_field.gd")

static func build_from_config(start_config) -> GalaxyState:
	var config = start_config if start_config != null else START_CONFIG_SCRIPT.new()
	var safe_config = config.copy()
	safe_config.clamp_values()

	var galaxy_state := GalaxyState.new()
	galaxy_state.galaxy_seed = safe_config.seed

	match safe_config.mode:
		START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW:
			_build_chaos_galaxy(galaxy_state, safe_config)
		START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR:
			_build_dynamic_anchor_galaxy(galaxy_state, safe_config)
		_:
			safe_config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.CENTRAL_BH
			_build_stable_anchor_galaxy(galaxy_state, safe_config)

	return galaxy_state

static func _build_dynamic_anchor_galaxy(galaxy_state: GalaxyState, config) -> void:
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
				true
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
					cluster_spec["is_primary"]
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
				true
			)
			galaxy_state.add_cluster(cluster_state)

static func _build_stable_anchor_galaxy(galaxy_state: GalaxyState, config) -> void:
	var local_specs: Array = ANCHOR_FIELD_SCRIPT.build_local_black_hole_specs(
		1,
		config.field_spacing_au,
		config.black_hole_mass
	)
	var cluster_state: ClusterState = _make_cluster_state(
		config,
		0,
		Vector2.ZERO,
		"stable_anchor_cluster",
		local_specs,
		true
	)
	galaxy_state.add_cluster(cluster_state)

static func _build_chaos_galaxy(galaxy_state: GalaxyState, config) -> void:
	var cluster_state := ClusterState.new()
	cluster_state.cluster_id = 0
	cluster_state.global_center = Vector2.ZERO
	cluster_state.cluster_seed = _derive_cluster_seed(config.seed, 0)
	cluster_state.classification = "chaos_cluster"
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
	cluster_state.simulation_profile = _build_simulation_profile(config, false, 0)
	cluster_state.radius = _estimate_cluster_radius([], cluster_state.simulation_profile)
	galaxy_state.add_cluster(cluster_state)

static func _make_cluster_state(config, cluster_id: int, global_center: Vector2,
		classification: String, local_black_hole_specs: Array, spawn_anchor_content: bool) -> ClusterState:
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
		local_black_hole_specs.size()
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

static func _build_simulation_profile(config, spawn_anchor_content: bool, local_black_hole_count: int) -> Dictionary:
	var star_count: int = config.star_count if spawn_anchor_content else 0
	var planets_per_star: int = config.planets_per_star if spawn_anchor_content else 0
	var disturbance_body_count: int = config.disturbance_body_count if spawn_anchor_content else 0

	return {
		"start_mode": config.mode,
		"anchor_topology": config.anchor_topology,
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

static func _estimate_cluster_radius(local_black_hole_specs: Array, simulation_profile: Dictionary) -> float:
	var max_black_hole_offset: float = 0.0
	for spec in local_black_hole_specs:
		max_black_hole_offset = maxf(max_black_hole_offset, spec["local_position"].length())

	var radius_padding: float = 2.0 * SimConstants.AU
	var start_mode: int = simulation_profile.get("start_mode", START_CONFIG_SCRIPT.StartMode.DYNAMIC_ANCHOR)
	if start_mode == START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW:
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
