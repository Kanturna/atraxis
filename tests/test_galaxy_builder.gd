extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")

func test_galaxy_builder_field_patch_is_deterministic_for_same_seed() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	config.seed = 42
	config.black_hole_count = 7
	config.field_spacing_au = 9.0
	config.star_count = 2
	config.planets_per_star = 2
	config.disturbance_body_count = 3

	var galaxy_a: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var galaxy_b: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)

	assert_eq(galaxy_a.galaxy_seed, galaxy_b.galaxy_seed, "same seed should rebuild the same galaxy seed")
	assert_eq(galaxy_a.primary_cluster_id, galaxy_b.primary_cluster_id, "primary cluster selection should be deterministic")
	assert_eq(galaxy_a.get_cluster_count(), 1, "field patch should be represented as one cluster")
	assert_eq(galaxy_b.get_cluster_count(), 1, "field patch should be represented as one cluster")
	_assert_clusters_equivalent(galaxy_a.get_primary_cluster(), galaxy_b.get_primary_cluster())

func test_anchor_topologies_map_to_expected_cluster_counts() -> void:
	var central_config = START_CONFIG_SCRIPT.new()
	central_config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.CENTRAL_BH

	var field_patch_config = START_CONFIG_SCRIPT.new()
	field_patch_config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	field_patch_config.black_hole_count = 6

	var galaxy_cluster_config = START_CONFIG_SCRIPT.new()
	galaxy_cluster_config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	galaxy_cluster_config.black_hole_count = 9
	galaxy_cluster_config.galaxy_cluster_count = 3

	var central_galaxy: GalaxyState = WorldBuilder.build_galaxy_state_from_config(central_config)
	var field_patch_galaxy: GalaxyState = WorldBuilder.build_galaxy_state_from_config(field_patch_config)
	var galaxy_cluster_galaxy: GalaxyState = WorldBuilder.build_galaxy_state_from_config(galaxy_cluster_config)

	assert_eq(central_galaxy.get_cluster_count(), 1, "central BH should be wrapped as a single cluster")
	assert_eq(field_patch_galaxy.get_cluster_count(), 1, "field patch should be wrapped as a single cluster")
	assert_eq(galaxy_cluster_galaxy.get_cluster_count(), 3, "galaxy cluster topology should build multiple clusters")
	assert_eq(
		central_galaxy.get_primary_cluster().get_objects_by_kind("black_hole").size(),
		1,
		"central BH cluster should carry exactly one black hole object"
	)
	assert_eq(
		field_patch_galaxy.get_primary_cluster().get_objects_by_kind("black_hole").size(),
		6,
		"field patch cluster should carry all configured black holes"
	)

func test_public_galaxy_builder_ignores_internal_fixture_profile_flags() -> void:
	var sandbox_config = START_CONFIG_SCRIPT.new()
	sandbox_config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	sandbox_config.black_hole_count = 9
	sandbox_config.galaxy_cluster_count = 3

	var reference_config = sandbox_config.copy()
	reference_config.world_profile = START_CONFIG_SCRIPT.WorldProfile.ORBITAL_REFERENCE

	var inflow_config = sandbox_config.copy()
	inflow_config.world_profile = START_CONFIG_SCRIPT.WorldProfile.INFLOW_LAB

	var sandbox_galaxy: GalaxyState = WorldBuilder.build_galaxy_state_from_config(sandbox_config)
	var reference_galaxy: GalaxyState = WorldBuilder.build_galaxy_state_from_config(reference_config)
	var inflow_galaxy: GalaxyState = WorldBuilder.build_galaxy_state_from_config(inflow_config)

	assert_eq(sandbox_galaxy.get_cluster_count(), reference_galaxy.get_cluster_count(), "reference fixture flags must not change the public cluster topology")
	assert_eq(sandbox_galaxy.get_cluster_count(), inflow_galaxy.get_cluster_count(), "inflow fixture flags must not change the public cluster topology")
	_assert_clusters_equivalent(sandbox_galaxy.get_primary_cluster(), reference_galaxy.get_primary_cluster())
	_assert_clusters_equivalent(sandbox_galaxy.get_primary_cluster(), inflow_galaxy.get_primary_cluster())

func test_galaxy_cluster_keeps_remote_clusters_unloaded_and_data_only() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	config.seed = 99
	config.black_hole_count = 9
	config.galaxy_cluster_count = 3
	config.star_count = 2
	config.planets_per_star = 2
	config.disturbance_body_count = 2

	var galaxy_state: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var total_black_holes: int = 0
	var primary_cluster_count: int = 0

	for cluster_state in galaxy_state.get_clusters():
		total_black_holes += cluster_state.get_objects_by_kind("black_hole").size()
		assert_eq(
			cluster_state.activation_state,
			ClusterActivationState.State.UNLOADED,
			"newly described clusters should start unloaded"
		)
		if cluster_state.cluster_id == galaxy_state.primary_cluster_id:
			primary_cluster_count += 1
			assert_true(
				cluster_state.simulation_profile.get("spawn_anchor_content", false),
				"the primary cluster should keep the spawnable local content"
			)
			assert_eq(
				cluster_state.simulation_profile.get("star_count", 0),
				config.star_count,
				"the primary cluster should preserve the configured star count"
			)
		else:
			assert_false(
				cluster_state.simulation_profile.get("spawn_anchor_content", true),
				"remote clusters should remain data-only in this phase"
			)
			assert_eq(
				cluster_state.simulation_profile.get("star_count", -1),
				0,
				"remote clusters should not eagerly materialize stars yet"
			)
			assert_eq(
				cluster_state.simulation_profile.get("planets_per_star", -1),
				0,
				"remote clusters should not eagerly materialize planets yet"
			)
			assert_eq(
				cluster_state.simulation_profile.get("disturbance_body_count", -1),
				0,
				"remote clusters should not eagerly materialize disturbance bodies yet"
			)

	assert_eq(primary_cluster_count, 1, "exactly one cluster should be the primary active spawn candidate")
	assert_eq(total_black_holes, config.black_hole_count, "cluster registry should preserve the full BH total")

func test_cluster_black_holes_start_resident_and_expose_lifecycle_scaffold() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	config.black_hole_count = 5

	var galaxy_state: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var cluster_state: ClusterState = galaxy_state.get_primary_cluster()
	var supported_states: Array = cluster_state.cluster_blueprint.get("supported_residency_states", [])
	var supported_entity_kinds: Array = cluster_state.cluster_blueprint.get("supported_entity_kinds", [])

	assert_true(
		supported_states.has(ObjectResidencyState.State.RESIDENT),
		"cluster blueprint should advertise resident objects as a supported lifecycle state"
	)
	assert_true(
		supported_states.has(ObjectResidencyState.State.ACTIVE),
		"cluster blueprint should advertise active objects as a supported lifecycle state"
	)
	assert_true(
		supported_states.has(ObjectResidencyState.State.SIMPLIFIED),
		"cluster blueprint should advertise simplified objects as a supported lifecycle state"
	)
	assert_true(
		supported_states.has(ObjectResidencyState.State.IN_TRANSIT),
		"cluster blueprint should advertise in-transit objects as a supported lifecycle state"
	)
	assert_true(
		supported_entity_kinds.has("agent"),
		"cluster blueprint should advertise agents as supported entity kinds for future world-entity binding"
	)
	assert_true(
		supported_entity_kinds.has("unit"),
		"cluster blueprint should advertise units as supported entity kinds for future grouped ownership"
	)

	for object_state in cluster_state.get_objects_by_kind("black_hole"):
		assert_eq(
			object_state.residency_state,
			ObjectResidencyState.State.RESIDENT,
			"black holes should begin as resident source-of-truth objects"
		)

func test_active_cluster_session_activates_primary_cluster_and_maps_local_to_global() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	config.black_hole_count = 9
	config.galaxy_cluster_count = 3
	config.star_count = 2
	config.planets_per_star = 1
	config.disturbance_body_count = 1

	var galaxy_state: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state)
	var local_probe := Vector2(123.0, -45.0)
	var primary_cluster: ClusterState = galaxy_state.get_primary_cluster()

	assert_not_null(session.sim_world, "the active cluster session should own a local sim world")
	assert_eq(session.cluster_id, galaxy_state.primary_cluster_id, "the active session should default to the primary cluster")
	assert_eq(
		primary_cluster.activation_state,
		ClusterActivationState.State.ACTIVE,
		"binding a cluster into a session should mark it active"
	)
	assert_true(
		session.to_local(session.to_global(local_probe)).is_equal_approx(local_probe),
		"the session should provide stable local/global coordinate transforms"
	)
	assert_eq(
		session.sim_world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE),
		primary_cluster.get_objects_by_kind("black_hole").size(),
		"the active sim world should materialize exactly the active cluster's BH registry"
	)
	assert_eq(
		session.sim_world.count_bodies_by_type(SimBody.BodyType.STAR),
		config.star_count,
		"the primary active cluster should materialize its configured star content"
	)

	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id == galaxy_state.primary_cluster_id:
			continue
		assert_eq(
			cluster_state.activation_state,
			ClusterActivationState.State.UNLOADED,
			"non-active clusters should remain unloaded until explicitly activated"
		)

func test_galaxy_cluster_keeps_total_bh_count_above_the_currently_materialized_share() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	config.black_hole_count = 21
	config.galaxy_cluster_count = 7
	config.star_count = 1
	config.planets_per_star = 0
	config.disturbance_body_count = 0

	var galaxy_state: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state)
	var total_black_holes: int = 0
	for cluster_state in galaxy_state.get_clusters():
		total_black_holes += cluster_state.get_objects_by_kind("black_hole").size()
	var active_cluster_black_holes: int = session.active_cluster_state.get_objects_by_kind("black_hole").size()
	var visible_black_holes: int = session.sim_world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE)

	assert_eq(total_black_holes, config.black_hole_count, "galaxy cluster should still describe the full requested BH total across all clusters")
	assert_eq(visible_black_holes, active_cluster_black_holes, "the live sim should materialize exactly the active cluster share of black holes")
	assert_lt(visible_black_holes, total_black_holes, "the active cluster view should expose only part of the galaxy-wide BH total at once")

func test_active_cluster_session_switch_marks_previous_cluster_simplified() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	config.black_hole_count = 9
	config.galaxy_cluster_count = 3

	var galaxy_state: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var first_cluster: ClusterState = galaxy_state.get_primary_cluster()
	var second_cluster: ClusterState = null
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id != first_cluster.cluster_id:
			second_cluster = cluster_state
			break

	assert_not_null(second_cluster, "galaxy cluster topology should expose a second cluster for lifecycle switching")

	var session := ActiveClusterSession.new()
	var first_world := SimWorld.new()
	var second_world := SimWorld.new()
	WorldBuilder.materialize_cluster_into_world(first_world, first_cluster)
	WorldBuilder.materialize_cluster_into_world(second_world, second_cluster)

	session.bind(galaxy_state, first_cluster, first_world)
	session.bind(galaxy_state, second_cluster, second_world)

	assert_eq(
		first_cluster.activation_state,
		ClusterActivationState.State.SIMPLIFIED,
		"switching the active bubble should demote the previous cluster to simplified"
	)
	assert_eq(
		second_cluster.activation_state,
		ClusterActivationState.State.ACTIVE,
		"the newly bound cluster should become active"
	)

func test_compatibility_build_from_config_matches_active_session_projection() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	config.seed = 123
	config.black_hole_count = 5
	config.star_count = 2
	config.planets_per_star = 2
	config.disturbance_body_count = 2

	var compatibility_world := SimWorld.new()
	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_config(config)

	WorldBuilder.build_from_config(compatibility_world, config)

	assert_eq(
		compatibility_world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE),
		session.sim_world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE),
		"legacy build_from_config should still project the same local BH count"
	)
	assert_eq(
		compatibility_world.count_bodies_by_type(SimBody.BodyType.STAR),
		session.sim_world.count_bodies_by_type(SimBody.BodyType.STAR),
		"legacy build_from_config should still project the same star count"
	)
	assert_eq(
		compatibility_world.count_bodies_by_type(SimBody.BodyType.PLANET),
		session.sim_world.count_bodies_by_type(SimBody.BodyType.PLANET),
		"legacy build_from_config should still project the same planet count"
	)
	assert_eq(
		compatibility_world.count_bodies_by_type(SimBody.BodyType.ASTEROID),
		session.sim_world.count_bodies_by_type(SimBody.BodyType.ASTEROID),
		"legacy build_from_config should still project the same asteroid count"
	)
	assert_true(
		_sorted_positions_by_type(compatibility_world, SimBody.BodyType.BLACK_HOLE)
			== _sorted_positions_by_type(session.sim_world, SimBody.BodyType.BLACK_HOLE),
		"legacy build_from_config should materialize the same local BH layout as the session path"
	)

func test_active_cluster_session_black_hole_mass_updates_source_of_truth_and_projection() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	config.black_hole_count = 4

	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_config(config)
	var new_mass: float = config.black_hole_mass * 1.4

	session.set_black_hole_mass(new_mass)

	assert_almost_eq(
		session.active_cluster_state.simulation_profile.get("black_hole_mass", 0.0),
		new_mass,
		0.001,
		"active cluster profile should track live BH mass changes"
	)
	for spec in session.active_cluster_state.cluster_blueprint.get("local_black_hole_specs", []):
		assert_almost_eq(spec["mass"], new_mass, 0.001, "cluster blueprint should stay in sync with live BH mass")
	for object_state in session.active_cluster_state.get_objects_by_kind("black_hole"):
		assert_almost_eq(object_state.descriptor.get("mass", 0.0), new_mass, 0.001, "object registry should stay in sync with live BH mass")
	for black_hole in session.sim_world.get_black_holes():
		assert_almost_eq(black_hole.mass, new_mass, 0.001, "the active local projection should update every live BH mass")

func _assert_clusters_equivalent(cluster_a: ClusterState, cluster_b: ClusterState) -> void:
	assert_not_null(cluster_a, "cluster A should exist")
	assert_not_null(cluster_b, "cluster B should exist")
	assert_eq(cluster_a.cluster_id, cluster_b.cluster_id, "cluster ids should be deterministic")
	assert_true(cluster_a.global_center.is_equal_approx(cluster_b.global_center), "cluster global center should be deterministic")
	assert_almost_eq(cluster_a.radius, cluster_b.radius, 0.001, "cluster radius should be deterministic")
	assert_eq(cluster_a.cluster_seed, cluster_b.cluster_seed, "cluster seed should be deterministic")
	assert_eq(cluster_a.classification, cluster_b.classification, "cluster classification should be deterministic")
	assert_eq(cluster_a.activation_state, cluster_b.activation_state, "cluster activation default should be deterministic")
	assert_eq(
		cluster_a.simulation_profile.get("content_archetype", ""),
		cluster_b.simulation_profile.get("content_archetype", "mismatch"),
		"cluster content archetype should be deterministic"
	)
	assert_eq(
		cluster_a.simulation_profile.get("analytic_star_carriers", true),
		cluster_b.simulation_profile.get("analytic_star_carriers", false),
		"cluster carrier mode flags should be deterministic"
	)
	assert_eq(
		cluster_a.simulation_profile.get("local_black_hole_count", -1),
		cluster_b.simulation_profile.get("local_black_hole_count", -2),
		"cluster local BH count should be deterministic"
	)
	assert_eq(
		cluster_a.get_primary_black_hole_object_id(),
		cluster_b.get_primary_black_hole_object_id(),
		"primary BH object selection should be deterministic"
	)

	var black_holes_a: Array = cluster_a.get_objects_by_kind("black_hole")
	var black_holes_b: Array = cluster_b.get_objects_by_kind("black_hole")
	assert_eq(black_holes_a.size(), black_holes_b.size(), "cluster BH registry size should be deterministic")

	for idx in range(black_holes_a.size()):
		var object_a: ClusterObjectState = black_holes_a[idx]
		var object_b: ClusterObjectState = black_holes_b[idx]
		assert_eq(object_a.object_id, object_b.object_id, "cluster object ids should be deterministic")
		assert_eq(object_a.kind, object_b.kind, "cluster object kinds should be deterministic")
		assert_eq(object_a.residency_state, object_b.residency_state, "cluster object residency should be deterministic")
		assert_true(object_a.local_position.is_equal_approx(object_b.local_position), "cluster object positions should be deterministic")
		assert_eq(object_a.seed, object_b.seed, "cluster object seeds should be deterministic")
		assert_almost_eq(
			object_a.descriptor.get("mass", 0.0),
			object_b.descriptor.get("mass", -1.0),
			0.001,
			"cluster object masses should be deterministic"
		)
		assert_eq(
			object_a.descriptor.get("ring_index", -1),
			object_b.descriptor.get("ring_index", -2),
			"cluster object ring indices should be deterministic"
		)
		assert_eq(
			object_a.descriptor.get("is_primary", false),
			object_b.descriptor.get("is_primary", true),
			"cluster object primary flags should be deterministic"
		)

func _sorted_positions_by_type(world: SimWorld, body_type: int) -> Array:
	var positions: Array = []
	for body in world.bodies:
		if body.active and body.body_type == body_type:
			positions.append(body.position)
	positions.sort_custom(func(a, b):
		if not is_equal_approx(a.x, b.x):
			return a.x < b.x
		return a.y < b.y
	)
	return positions
