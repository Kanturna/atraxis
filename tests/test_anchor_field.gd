extends GutTest

const FIELD_SCRIPT := preload("res://simulation/anchor_field.gd")

func test_field_patch_specs_keep_single_black_hole_as_center_only() -> void:
	var specs: Array = FIELD_SCRIPT.build_field_patch_specs(1, 9.0, 12_000_000.0)

	assert_eq(specs.size(), 1, "a field patch with one BH should only build the center")
	assert_true(specs[0]["is_central"], "the remaining BH should be the central anchor")
	assert_eq(specs[0]["ring_index"], 0, "the center should stay in ring 0")
	assert_eq(specs[0]["position"], Vector2.ZERO, "the center should stay at the origin")

func test_field_patch_specs_expand_into_concentric_rings() -> void:
	var specs: Array = FIELD_SCRIPT.build_field_patch_specs(9, 9.0, 12_000_000.0)
	var ring_counts: Dictionary = {}

	for spec in specs:
		var ring_index: int = spec["ring_index"]
		ring_counts[ring_index] = ring_counts.get(ring_index, 0) + 1

	assert_eq(ring_counts.get(0, 0), 1, "ring 0 should contain exactly the central BH")
	assert_eq(ring_counts.get(1, 0), 6, "ring 1 should expose six evenly spaced slots")
	assert_eq(ring_counts.get(2, 0), 2, "additional BHs should spill into ring 2 rather than overfilling ring 1")

func test_field_ring_count_matches_total_black_hole_count() -> void:
	assert_eq(FIELD_SCRIPT.field_ring_count_for_total(1), 1, "one BH should use only the center ring")
	assert_eq(FIELD_SCRIPT.field_ring_count_for_total(7), 2, "seven BHs should fill the center plus ring 1")
	assert_eq(FIELD_SCRIPT.field_ring_count_for_total(8), 3, "eight BHs should begin ring 2")

func test_galaxy_cluster_specs_return_correct_total_count() -> void:
	var total: int = 21
	var specs: Array = FIELD_SCRIPT.build_galaxy_cluster_specs(total, 3, 5.0, 4.0, 12_000_000.0)
	assert_eq(specs.size(), total, "galaxy cluster specs must contain exactly the requested BH count")

func test_galaxy_cluster_specs_have_exactly_one_is_central() -> void:
	var specs: Array = FIELD_SCRIPT.build_galaxy_cluster_specs(14, 2, 5.0, 4.0, 12_000_000.0)
	var central_count: int = 0
	for spec in specs:
		if spec["is_central"]:
			central_count += 1
	assert_eq(central_count, 1, "exactly one BH should be marked is_central across the whole galaxy layout")

func test_galaxy_cluster_voids_are_larger_than_cluster_radius() -> void:
	# Cluster centres should be separated by void_scale × cluster_radius_au,
	# which must be strictly larger than cluster_radius_au itself.
	# We verify this by checking that the minimum centre-to-centre distance
	# (approximated via the minimum cross-cluster BH distance) is at least
	# cluster_radius_au × (void_scale - 1) in sim-units.
	var cluster_radius_au: float = 4.0
	var void_scale: float = 4.0
	var specs: Array = FIELD_SCRIPT.build_galaxy_cluster_specs(14, 2, cluster_radius_au, void_scale, 12_000_000.0)

	# Separate BHs by cluster_index.
	var by_cluster: Dictionary = {}
	for spec in specs:
		var ci: int = spec.get("cluster_index", 0)
		if not by_cluster.has(ci):
			by_cluster[ci] = []
		by_cluster[ci].append(spec["position"])

	# Find the minimum distance between any BH in cluster 0 and any BH in cluster 1.
	var min_cross_dist: float = INF
	for pos_a in by_cluster.get(0, []):
		for pos_b in by_cluster.get(1, []):
			min_cross_dist = minf(min_cross_dist, pos_a.distance_to(pos_b))

	var expected_min_gap: float = (void_scale - 1.0) * cluster_radius_au * SimConstants.AU
	assert_true(
		min_cross_dist > expected_min_gap,
		"cross-cluster BH distance should exceed (void_scale - 1) × cluster_radius to ensure real voids"
	)
