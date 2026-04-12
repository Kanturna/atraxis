extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const GALAXY_WORLDGEN_SCRIPT := preload("res://simulation/galaxy_worldgen.gd")

func test_public_worldgen_builder_is_deterministic_for_same_seed() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 42
	config.sector_scale = 180.0 * SimConstants.AU
	config.cluster_density = 0.72
	config.void_strength = 0.28
	config.bh_richness = 0.64
	config.star_richness = 0.48
	config.rare_zone_frequency = 0.35

	var galaxy_a: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var galaxy_b: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)

	assert_eq(galaxy_a.galaxy_seed, galaxy_b.galaxy_seed, "same seed should rebuild the same galaxy seed")
	assert_eq(galaxy_a.primary_cluster_id, galaxy_b.primary_cluster_id, "primary cluster selection should stay deterministic")
	assert_eq(galaxy_a.discovered_sector_order, galaxy_b.discovered_sector_order, "bootstrap sector discovery order should stay deterministic")
	assert_eq(galaxy_a.get_discovered_sector_count(), 9, "public bootstrap should discover the 3x3 origin sector neighborhood")
	assert_eq(galaxy_a.get_discovered_sector_count(), galaxy_b.get_discovered_sector_count(), "same config should discover the same sector count")
	assert_eq(galaxy_a.get_cluster_ids(), galaxy_b.get_cluster_ids(), "same config should register the same cluster ids")
	assert_gt(galaxy_a.get_cluster_count(), 0, "public worldgen should bootstrap at least one startable cluster")

	for sector_coord in galaxy_a.get_discovered_sector_coords():
		_assert_region_descriptors_equivalent(
			galaxy_a.get_region_descriptor(sector_coord),
			galaxy_b.get_region_descriptor(sector_coord)
		)
		var candidates_a: Array = galaxy_a.get_sector_candidate_descriptors(sector_coord)
		var candidates_b: Array = galaxy_b.get_sector_candidate_descriptors(sector_coord)
		assert_eq(candidates_a.size(), candidates_b.size(), "same sector should rebuild the same candidate count")
		for idx in range(candidates_a.size()):
			_assert_candidate_descriptors_equivalent(candidates_a[idx], candidates_b[idx])

	for cluster_id in galaxy_a.get_cluster_ids():
		_assert_clusters_equivalent(galaxy_a.get_cluster(cluster_id), galaxy_b.get_cluster(cluster_id))

func test_public_central_bh_alias_normalizes_into_the_field_patch_worldgen_hint() -> void:
	var central_config = START_CONFIG_SCRIPT.new()
	central_config.seed = 88
	central_config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.CENTRAL_BH
	central_config.black_hole_count = 9

	var field_patch_config = START_CONFIG_SCRIPT.new()
	field_patch_config.seed = 88
	field_patch_config.anchor_topology = START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	field_patch_config.black_hole_count = 1

	var central_galaxy: GalaxyState = WorldBuilder.build_galaxy_state_from_config(central_config)
	var field_patch_galaxy: GalaxyState = WorldBuilder.build_galaxy_state_from_config(field_patch_config)

	assert_not_null(central_galaxy.worldgen_config, "public builder should always carry a worldgen config")
	assert_true(
		central_galaxy.worldgen_config.legacy_generation_hints_enabled,
		"legacy topology aliases should feed the public path only as compatibility hints"
	)
	assert_eq(
		central_galaxy.worldgen_config.legacy_anchor_topology,
		START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH,
		"the public central alias should normalize to the field-patch compatibility hint"
	)
	assert_eq(
		central_galaxy.worldgen_config.legacy_black_hole_count_hint,
		1,
		"the public central alias should collapse to a one-BH compatibility hint"
	)
	assert_eq(
		central_galaxy.primary_cluster_id,
		field_patch_galaxy.primary_cluster_id,
		"normalized central alias and explicit one-BH field patch should land on the same public worldgen path"
	)
	assert_eq(
		central_galaxy.get_cluster_ids(),
		field_patch_galaxy.get_cluster_ids(),
		"normalized central alias and explicit one-BH field patch should register the same cluster ids"
	)
	for cluster_id in central_galaxy.get_cluster_ids():
		_assert_clusters_equivalent(
			central_galaxy.get_cluster(cluster_id),
			field_patch_galaxy.get_cluster(cluster_id)
		)
		assert_eq(
			central_galaxy.get_cluster(cluster_id).simulation_profile.get("topology_role", ""),
			"sector_worldgen_cluster",
			"public startup should route every cluster through the canonical sector-worldgen topology role"
		)

func test_public_galaxy_builder_ignores_internal_fixture_profile_flags() -> void:
	var sandbox_config = START_CONFIG_SCRIPT.new()
	sandbox_config.seed = 57
	sandbox_config.cluster_density = 0.68
	sandbox_config.void_strength = 0.22
	sandbox_config.bh_richness = 0.52
	sandbox_config.star_richness = 0.44
	sandbox_config.rare_zone_frequency = 0.31

	var reference_config = sandbox_config.copy()
	reference_config.world_profile = START_CONFIG_SCRIPT.WorldProfile.ORBITAL_REFERENCE

	var inflow_config = sandbox_config.copy()
	inflow_config.world_profile = START_CONFIG_SCRIPT.WorldProfile.INFLOW_LAB

	var sandbox_galaxy: GalaxyState = WorldBuilder.build_galaxy_state_from_config(sandbox_config)
	var reference_galaxy: GalaxyState = WorldBuilder.build_galaxy_state_from_config(reference_config)
	var inflow_galaxy: GalaxyState = WorldBuilder.build_galaxy_state_from_config(inflow_config)

	assert_eq(sandbox_galaxy.get_cluster_count(), reference_galaxy.get_cluster_count(), "reference fixture flags must not change the public cluster discovery")
	assert_eq(sandbox_galaxy.get_cluster_count(), inflow_galaxy.get_cluster_count(), "inflow fixture flags must not change the public cluster discovery")
	assert_eq(sandbox_galaxy.get_cluster_ids(), reference_galaxy.get_cluster_ids(), "reference fixture flags must not change public cluster ids")
	assert_eq(sandbox_galaxy.get_cluster_ids(), inflow_galaxy.get_cluster_ids(), "inflow fixture flags must not change public cluster ids")
	_assert_clusters_equivalent(sandbox_galaxy.get_primary_cluster(), reference_galaxy.get_primary_cluster())
	_assert_clusters_equivalent(sandbox_galaxy.get_primary_cluster(), inflow_galaxy.get_primary_cluster())

func test_sector_discovery_is_idempotent_and_keeps_cluster_registry_stable() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 99
	config.cluster_density = 0.82
	config.void_strength = 0.18
	config.bh_richness = 0.57
	config.star_richness = 0.46
	config.rare_zone_frequency = 0.66

	var galaxy_state: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var worldgen = GALAXY_WORLDGEN_SCRIPT.new(galaxy_state.worldgen_config)
	var sector_coord := Vector2i(2, -1)
	var sectors_before: int = galaxy_state.get_discovered_sector_count()
	var clusters_before: int = galaxy_state.get_cluster_count()

	var first_descriptor = GalaxyBuilder.discover_sector_into_galaxy(galaxy_state, worldgen, sector_coord)
	var first_candidate_descriptors: Array = galaxy_state.get_sector_candidate_descriptors(sector_coord)
	var first_cluster_ids: Array = galaxy_state.get_cluster_ids_for_sector(sector_coord)
	var sectors_after_first: int = galaxy_state.get_discovered_sector_count()
	var clusters_after_first: int = galaxy_state.get_cluster_count()

	var second_descriptor = GalaxyBuilder.discover_sector_into_galaxy(galaxy_state, worldgen, sector_coord)
	var second_candidate_descriptors: Array = galaxy_state.get_sector_candidate_descriptors(sector_coord)
	var second_cluster_ids: Array = galaxy_state.get_cluster_ids_for_sector(sector_coord)

	assert_eq(sectors_after_first, sectors_before + 1, "discovering a new sector should register it exactly once")
	assert_eq(
		clusters_after_first,
		clusters_before + first_candidate_descriptors.size(),
		"discovering a new sector should register exactly its worldgen candidate count"
	)
	assert_eq(galaxy_state.get_discovered_sector_count(), sectors_after_first, "re-discovering the same sector should not duplicate discovery entries")
	assert_eq(galaxy_state.get_cluster_count(), clusters_after_first, "re-discovering the same sector should not duplicate clusters")
	assert_eq(first_cluster_ids, second_cluster_ids, "re-discovering the same sector should keep the same cluster ids")
	assert_eq(first_candidate_descriptors.size(), second_candidate_descriptors.size(), "re-discovering the same sector should keep the same candidate count")
	_assert_region_descriptors_equivalent(first_descriptor, second_descriptor)
	for idx in range(first_candidate_descriptors.size()):
		var first_candidate = first_candidate_descriptors[idx]
		var second_candidate = second_candidate_descriptors[idx]
		_assert_candidate_descriptors_equivalent(first_candidate, second_candidate)
		assert_true(
			first_candidate.candidate_index >= 0 and first_candidate.candidate_index < GALAXY_WORLDGEN_SCRIPT.MAX_CLUSTER_CANDIDATES_PER_SECTOR_V1,
			"candidate indices should stay inside the explicit V1 0..2 cluster-candidate limit"
		)

func test_cluster_black_holes_start_resident_and_expose_lifecycle_scaffold() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 5
	config.cluster_density = 0.70
	config.void_strength = 0.20

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
	config.seed = 135
	config.cluster_density = 0.85
	config.void_strength = 0.12
	config.bh_richness = 0.76
	config.star_richness = 0.64

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
		int(primary_cluster.simulation_profile.get("star_count", 0)),
		"the active sim world should materialize the cluster's derived star richness"
	)

	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id == galaxy_state.primary_cluster_id:
			continue
		assert_eq(
			cluster_state.activation_state,
			ClusterActivationState.State.UNLOADED,
			"non-active clusters should remain unloaded until explicitly activated"
		)

func test_sector_scale_changes_spatial_granularity_without_changing_region_descriptor_weights() -> void:
	var base_config = START_CONFIG_SCRIPT.new()
	base_config.seed = 211
	base_config.cluster_density = 0.77
	base_config.void_strength = 0.31
	base_config.bh_richness = 0.63
	base_config.star_richness = 0.54
	base_config.rare_zone_frequency = 0.41
	base_config.sector_scale = 140.0 * SimConstants.AU

	var larger_scale_config = base_config.copy()
	larger_scale_config.sector_scale = 280.0 * SimConstants.AU

	var base_worldgen = GALAXY_WORLDGEN_SCRIPT.new(GalaxyBuilder._build_public_worldgen_config(base_config))
	var larger_worldgen = GALAXY_WORLDGEN_SCRIPT.new(GalaxyBuilder._build_public_worldgen_config(larger_scale_config))
	var sector_coord := Vector2i(3, -2)
	var sample_position := Vector2(
		base_config.sector_scale * 1.25,
		-base_config.sector_scale * 0.25
	)

	var base_region = base_worldgen.describe_region(base_config.seed, sector_coord)
	var larger_region = larger_worldgen.describe_region(base_config.seed, sector_coord)
	var base_candidates: Array = base_worldgen.build_cluster_candidates(base_config.seed, base_region)
	var larger_candidates: Array = larger_worldgen.build_cluster_candidates(base_config.seed, larger_region)

	_assert_region_descriptors_equivalent(base_region, larger_region)
	assert_eq(
		base_worldgen.sector_coord_for_global_position(sample_position),
		Vector2i(1, -1),
		"sector coords should be floor(global_position / sector_scale) in world space"
	)
	assert_eq(
		larger_worldgen.sector_coord_for_global_position(sample_position),
		Vector2i(0, -1),
		"larger sector scales should change spatial granularity without changing descriptor weights"
	)
	assert_eq(base_candidates.size(), larger_candidates.size(), "sector scale should not change candidate count for the same sector descriptor")
	for idx in range(base_candidates.size()):
		var base_candidate = base_candidates[idx]
		var larger_candidate = larger_candidates[idx]
		assert_eq(base_candidate.cluster_id, larger_candidate.cluster_id, "sector scale should not change stable cluster ids")
		assert_eq(base_candidate.cluster_seed, larger_candidate.cluster_seed, "sector scale should not change stable cluster seeds")
		assert_eq(base_candidate.classification, larger_candidate.classification, "sector scale should not change candidate archetype classification")
		assert_eq(base_candidate.bh_count, larger_candidate.bh_count, "sector scale should not change BH richness-derived candidate counts")
		assert_false(
			base_candidate.global_center.is_equal_approx(larger_candidate.global_center),
			"sector scale should change the physical spacing of cluster candidates in world space"
		)

func test_worldgen_bootstrap_discovers_origin_neighborhood_and_materializes_only_the_active_cluster_share() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 144
	config.cluster_density = 1.0
	config.void_strength = 0.0
	config.bh_richness = 0.82
	config.star_richness = 0.52
	config.rare_zone_frequency = 0.55

	var galaxy_state: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state)
	var total_black_holes: int = 0
	for cluster_state in galaxy_state.get_clusters():
		total_black_holes += cluster_state.get_objects_by_kind("black_hole").size()

	var visible_black_holes: int = session.sim_world.count_bodies_by_type(SimBody.BodyType.BLACK_HOLE)
	var active_cluster_black_holes: int = session.active_cluster_state.get_objects_by_kind("black_hole").size()

	assert_eq(galaxy_state.get_discovered_sector_count(), 9, "bootstrap should discover exactly the 3x3 origin neighborhood")
	assert_gt(galaxy_state.get_cluster_count(), 1, "dense bootstrap settings should produce multiple registered clusters")
	assert_eq(visible_black_holes, active_cluster_black_holes, "the live sim should materialize exactly the active cluster BH share")
	assert_gt(total_black_holes, visible_black_holes, "registered galaxy truth should contain more BHs than the active local projection")

func test_worldgen_archetypes_produce_distinct_region_characteristics() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 717
	config.cluster_density = 0.55
	config.void_strength = 0.45
	config.bh_richness = 0.50
	config.star_richness = 0.50
	config.rare_zone_frequency = 1.0

	var worldgen = GALAXY_WORLDGEN_SCRIPT.new(GalaxyBuilder._build_public_worldgen_config(config))
	var archetypes: Dictionary = _find_region_descriptors_for_all_archetypes(worldgen, config.seed, 20)

	assert_eq(archetypes.size(), 5, "the snapshot scan should find all five V1 region archetypes")

	var void_region = archetypes["void"]
	var relic_region = archetypes["sparse_relic_cluster"]
	var dense_region = archetypes["dense_bh_knot"]
	var nursery_region = archetypes["star_nursery"]
	var scrap_region = archetypes["scrap_rich_remnant"]

	assert_lt(void_region.cluster_chance, dense_region.cluster_chance, "void regions should advertise a much lower cluster chance than dense BH knots")
	assert_gt(void_region.void_strength, nursery_region.void_strength, "void regions should keep a stronger void tendency than star nurseries")
	assert_lt(void_region.bh_richness, dense_region.bh_richness, "dense BH knots should be richer in BH weight than void regions")
	assert_gt(nursery_region.star_richness, dense_region.star_richness, "star nurseries should advertise stronger star richness than dense BH knots")
	assert_gt(scrap_region.scrap_potential, relic_region.scrap_potential, "scrap-rich remnants should carry more scrap potential than sparse relic clusters")
	assert_gt(nursery_region.life_potential, dense_region.life_potential, "star nurseries should keep higher life potential than dense BH knots")

func test_active_cluster_session_switch_marks_previous_cluster_simplified() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 28
	config.cluster_density = 0.88
	config.void_strength = 0.10

	var galaxy_state: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var first_cluster: ClusterState = galaxy_state.get_primary_cluster()
	var second_cluster: ClusterState = null
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id != first_cluster.cluster_id:
			second_cluster = cluster_state
			break

	assert_not_null(second_cluster, "dense worldgen should expose a second cluster for lifecycle switching")

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
	config.seed = 123
	config.cluster_density = 0.79
	config.void_strength = 0.18
	config.bh_richness = 0.71
	config.star_richness = 0.68
	config.rare_zone_frequency = 0.27

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
	config.seed = 63
	config.cluster_density = 0.76
	config.void_strength = 0.18

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

func _assert_region_descriptors_equivalent(region_a, region_b) -> void:
	assert_not_null(region_a, "region A should exist")
	assert_not_null(region_b, "region B should exist")
	assert_eq(region_a.sector_coord, region_b.sector_coord, "sector coords should match deterministically")
	assert_eq(region_a.region_seed, region_b.region_seed, "region seeds should match deterministically")
	assert_eq(region_a.region_archetype, region_b.region_archetype, "region archetypes should match deterministically")
	assert_almost_eq(region_a.density, region_b.density, 0.0001, "region density should match deterministically")
	assert_almost_eq(region_a.void_strength, region_b.void_strength, 0.0001, "region void strength should match deterministically")
	assert_almost_eq(region_a.cluster_chance, region_b.cluster_chance, 0.0001, "region cluster chance should match deterministically")
	assert_almost_eq(region_a.bh_richness, region_b.bh_richness, 0.0001, "region BH richness should match deterministically")
	assert_almost_eq(region_a.star_richness, region_b.star_richness, 0.0001, "region star richness should match deterministically")
	assert_almost_eq(region_a.rare_zone_weight, region_b.rare_zone_weight, 0.0001, "region rare-zone weight should match deterministically")
	assert_almost_eq(region_a.scrap_potential, region_b.scrap_potential, 0.0001, "region scrap potential should match deterministically")
	assert_almost_eq(region_a.life_potential, region_b.life_potential, 0.0001, "region life potential should match deterministically")

func _assert_candidate_descriptors_equivalent(candidate_a, candidate_b) -> void:
	assert_not_null(candidate_a, "candidate A should exist")
	assert_not_null(candidate_b, "candidate B should exist")
	assert_eq(candidate_a.sector_coord, candidate_b.sector_coord, "candidate sector coords should match deterministically")
	assert_eq(candidate_a.candidate_index, candidate_b.candidate_index, "candidate indices should match deterministically")
	assert_eq(candidate_a.cluster_id, candidate_b.cluster_id, "candidate cluster ids should match deterministically")
	assert_eq(candidate_a.cluster_seed, candidate_b.cluster_seed, "candidate seeds should match deterministically")
	assert_eq(candidate_a.classification, candidate_b.classification, "candidate classifications should match deterministically")
	assert_eq(candidate_a.region_archetype, candidate_b.region_archetype, "candidate region archetypes should match deterministically")
	assert_true(candidate_a.global_center.is_equal_approx(candidate_b.global_center), "candidate centers should match deterministically")
	assert_almost_eq(candidate_a.radius, candidate_b.radius, 0.001, "candidate radii should match deterministically")
	assert_eq(candidate_a.bh_count, candidate_b.bh_count, "candidate BH counts should match deterministically")
	assert_almost_eq(candidate_a.bh_spacing_au, candidate_b.bh_spacing_au, 0.001, "candidate BH spacing should match deterministically")
	assert_almost_eq(candidate_a.bh_richness, candidate_b.bh_richness, 0.0001, "candidate BH richness should match deterministically")
	assert_almost_eq(candidate_a.star_richness, candidate_b.star_richness, 0.0001, "candidate star richness should match deterministically")
	assert_almost_eq(candidate_a.rare_zone_weight, candidate_b.rare_zone_weight, 0.0001, "candidate rare-zone weight should match deterministically")
	assert_almost_eq(candidate_a.scrap_potential, candidate_b.scrap_potential, 0.0001, "candidate scrap potential should match deterministically")
	assert_almost_eq(candidate_a.life_potential, candidate_b.life_potential, 0.0001, "candidate life potential should match deterministically")

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
		cluster_a.simulation_profile.get("sector_coord", Vector2i.ZERO),
		cluster_b.simulation_profile.get("sector_coord", Vector2i(-1, -1)),
		"cluster sector coordinates should be deterministic"
	)
	assert_eq(
		cluster_a.simulation_profile.get("candidate_index", -1),
		cluster_b.simulation_profile.get("candidate_index", -2),
		"cluster candidate indices should be deterministic"
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

func _find_region_descriptors_for_all_archetypes(worldgen, galaxy_seed: int, scan_radius: int) -> Dictionary:
	var found: Dictionary = {}
	for y in range(-scan_radius, scan_radius + 1):
		for x in range(-scan_radius, scan_radius + 1):
			var descriptor = worldgen.describe_region(galaxy_seed, Vector2i(x, y))
			var archetype: String = descriptor.region_archetype
			if not found.has(archetype):
				found[archetype] = descriptor
			if found.size() == 5:
				return found
	return found

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
