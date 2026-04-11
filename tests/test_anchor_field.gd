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
