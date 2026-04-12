extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const WORLD_RENDERER_SCRIPT := preload("res://rendering/world_renderer.gd")

func test_registered_cluster_debug_markers_encode_active_simplified_and_unloaded_states() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 314
	config.cluster_density = 1.0
	config.void_strength = 0.0
	config.bh_richness = 0.78
	config.star_richness = 0.60
	config.rare_zone_frequency = 0.55

	var galaxy_state: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	assert_gt(galaxy_state.get_cluster_count(), 2, "dense bootstrap settings should expose enough clusters for active/simplified/unloaded marker states")

	var first_cluster: ClusterState = galaxy_state.get_primary_cluster()
	var second_cluster: ClusterState = null
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state.cluster_id != first_cluster.cluster_id:
			second_cluster = cluster_state
			break
	assert_not_null(second_cluster, "the marker-state test needs a second registered cluster")

	var session := ActiveClusterSession.new()
	session.bind(galaxy_state, first_cluster, SimWorld.new())
	session.bind(galaxy_state, second_cluster, SimWorld.new())

	var payload: Dictionary = WORLD_RENDERER_SCRIPT.build_registered_cluster_debug_markers(galaxy_state, session)
	var markers: Array = payload.get("markers", [])
	var marker_states: Array = markers.map(func(marker): return str(marker.get("state", "")))

	assert_eq(markers.size(), galaxy_state.get_cluster_count(), "the debug marker payload should include every registered cluster")
	assert_true(marker_states.has("active"), "the marker payload should label the active cluster state")
	assert_true(marker_states.has("simplified"), "the marker payload should label simplified remote clusters")
	assert_true(marker_states.has("unloaded"), "the marker payload should keep unloaded remote clusters visible as ghosts")
	assert_true(int(payload.get("nearest_remote_cluster_id", -1)) >= 0, "the marker payload should identify the nearest remote ghost for labeling")

func test_cluster_debug_marker_radius_stays_visible_across_zoom_scales() -> void:
	var cluster_radius: float = 1_200.0
	var zoomed_out_radius: float = WORLD_RENDERER_SCRIPT.cluster_debug_marker_world_radius(cluster_radius, 0.35, false)
	var default_radius: float = WORLD_RENDERER_SCRIPT.cluster_debug_marker_world_radius(cluster_radius, 1.0, false)
	var zoomed_in_radius: float = WORLD_RENDERER_SCRIPT.cluster_debug_marker_world_radius(cluster_radius, 2.0, false)
	var active_radius: float = WORLD_RENDERER_SCRIPT.cluster_debug_marker_world_radius(cluster_radius, 1.0, true)

	assert_gt(zoomed_out_radius, default_radius, "ghost markers should grow in world units when the camera zooms out so they remain visible")
	assert_gt(default_radius, zoomed_in_radius, "ghost markers should shrink in world units when zoomed in instead of ballooning")
	assert_gt(active_radius, default_radius, "the active cluster marker should stay more prominent than remote ghost markers")
	assert_gt(zoomed_in_radius, 0.0, "marker radius should remain positive at tight zoom levels")

func test_remote_cluster_preview_payload_uses_blueprint_specs_for_unloaded_clusters() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 1888
	config.cluster_density = 0.92
	config.void_strength = 0.16
	config.bh_richness = 0.55
	config.star_richness = 0.62
	config.rare_zone_frequency = 1.0

	var galaxy_state: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state)
	var preview_specs: Array = WORLD_RENDERER_SCRIPT.build_remote_cluster_preview_specs(galaxy_state, session)
	var preview_kinds: Array = preview_specs.map(func(spec): return str(spec.get("kind", "")))

	assert_false(preview_specs.is_empty(), "remote preview payload should include read-only bodies for non-active clusters")
	assert_true(preview_kinds.has("black_hole"), "remote previews should include black holes for unloaded clusters")
	assert_true(preview_kinds.has("star"), "remote previews should include stars for unloaded clusters")
	assert_true(preview_kinds.has("planet"), "remote previews should include planets for unloaded clusters")

func test_remote_cluster_pick_prefers_preview_bodies() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 1888
	config.cluster_density = 0.92
	config.void_strength = 0.16
	config.bh_richness = 0.55
	config.star_richness = 0.62
	config.rare_zone_frequency = 1.0

	var galaxy_state: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state)
	var preview_specs: Array = WORLD_RENDERER_SCRIPT.build_remote_cluster_preview_specs(galaxy_state, session)
	var marker_payload: Dictionary = WORLD_RENDERER_SCRIPT.build_registered_cluster_debug_markers(galaxy_state, session)
	assert_false(preview_specs.is_empty(), "preview-body picking needs at least one remote preview spec")
	var preview_spec: Dictionary = preview_specs[0]
	var canvas_position: Vector2 = BodyRenderer.sim_to_screen(
		Vector2(preview_spec.get("local_position", Vector2.ZERO))
	)

	var pick: Dictionary = WORLD_RENDERER_SCRIPT.pick_remote_cluster_from_payloads(
		preview_specs,
		marker_payload,
		galaxy_state,
		session,
		canvas_position,
		1.0
	)

	assert_eq(
		int(pick.get("cluster_id", -1)),
		int(preview_spec.get("cluster_id", -1)),
		"clicking a remote preview body should resolve to that preview's cluster"
	)
	var expected_clicked_global_focus: Vector2 = session.to_global(
		canvas_position / max(SimConstants.SIM_TO_SCREEN, 0.001)
	)
	assert_eq(
		Vector2(pick.get("clicked_global_focus_position", Vector2.ZERO)),
		expected_clicked_global_focus,
		"preview picking should preserve the actual clicked focus point in global space"
	)

func test_remote_cluster_pick_uses_markers_when_no_preview_body_is_hit() -> void:
	var config = START_CONFIG_SCRIPT.new()
	config.seed = 314
	config.cluster_density = 1.0
	config.void_strength = 0.0
	config.bh_richness = 0.78
	config.star_richness = 0.60
	config.rare_zone_frequency = 0.55

	var galaxy_state: GalaxyState = WorldBuilder.build_galaxy_state_from_config(config)
	var session: ActiveClusterSession = WorldBuilder.build_active_session_from_galaxy_state(galaxy_state)
	var marker_payload: Dictionary = WORLD_RENDERER_SCRIPT.build_registered_cluster_debug_markers(galaxy_state, session)
	var remote_marker: Dictionary = {}
	var active_marker: Dictionary = {}
	for marker in marker_payload.get("markers", []):
		if bool(marker.get("is_active", false)):
			active_marker = marker
		elif remote_marker.is_empty():
			remote_marker = marker
	assert_false(remote_marker.is_empty(), "marker-based picking needs a remote cluster marker")
	assert_false(active_marker.is_empty(), "marker-based picking also checks that the active marker is ignored")
	var remote_canvas_position: Vector2 = BodyRenderer.sim_to_screen(
		Vector2(remote_marker.get("local_center", Vector2.ZERO))
	)
	var active_canvas_position: Vector2 = BodyRenderer.sim_to_screen(
		Vector2(active_marker.get("local_center", Vector2.ZERO))
	)

	var remote_pick: Dictionary = WORLD_RENDERER_SCRIPT.pick_remote_cluster_from_payloads(
		[],
		marker_payload,
		galaxy_state,
		session,
		remote_canvas_position,
		1.0
	)
	var active_pick: Dictionary = WORLD_RENDERER_SCRIPT.pick_remote_cluster_from_payloads(
		[],
		marker_payload,
		galaxy_state,
		session,
		active_canvas_position,
		1.0
	)

	assert_eq(
		int(remote_pick.get("cluster_id", -1)),
		int(remote_marker.get("cluster_id", -1)),
		"marker picking should still resolve the remote cluster when no preview body was hit"
	)
	var expected_marker_click_focus: Vector2 = session.to_global(
		remote_canvas_position / max(SimConstants.SIM_TO_SCREEN, 0.001)
	)
	assert_eq(
		Vector2(remote_pick.get("clicked_global_focus_position", Vector2.ZERO)),
		expected_marker_click_focus,
		"marker picking should expose the clicked global focus point for the camera flight"
	)
	assert_true(
		active_pick.is_empty(),
		"the active cluster marker should not masquerade as a remote-click target"
	)

func test_cluster_extent_ring_guard_skips_tiny_and_pathological_radii() -> void:
	assert_false(
		WORLD_RENDERER_SCRIPT.should_draw_cluster_extent_ring(0.3, 2_000.0),
		"extent rings below 0.5 screen pixels should be skipped to avoid sub-pixel noise"
	)
	assert_true(
		WORLD_RENDERER_SCRIPT.should_draw_cluster_extent_ring(1.5, 2_000.0),
		"extent rings at 1.5 screen pixels should now be visible at galaxy-scale zoom"
	)
	assert_false(
		WORLD_RENDERER_SCRIPT.should_draw_cluster_extent_ring(4_000.0, 2_000.0),
		"extent rings that dwarf the viewport should be skipped to avoid unstable giant arcs"
	)
	assert_true(
		WORLD_RENDERER_SCRIPT.should_draw_cluster_extent_ring(240.0, 2_000.0),
		"mid-scale extent rings should remain visible"
	)

func test_offscreen_cluster_payloads_are_culled_before_rendering() -> void:
	var galaxy_state := GalaxyState.new()
	var active_cluster: ClusterState = _make_manual_preview_cluster(0, Vector2.ZERO, 100.0)
	var visible_remote_cluster: ClusterState = _make_manual_preview_cluster(1, Vector2(1_000.0, 0.0), 100.0)
	var offscreen_remote_cluster: ClusterState = _make_manual_preview_cluster(2, Vector2(6_000.0, 0.0), 100.0)
	galaxy_state.add_cluster(active_cluster)
	galaxy_state.add_cluster(visible_remote_cluster)
	galaxy_state.add_cluster(offscreen_remote_cluster)

	var session := ActiveClusterSession.new()
	session.bind(galaxy_state, active_cluster, SimWorld.new())
	visible_remote_cluster.mark_simplified(0.0)
	var visible_canvas_rect := Rect2(Vector2(-600.0, -400.0), Vector2(1_200.0, 800.0))

	var marker_payload: Dictionary = WORLD_RENDERER_SCRIPT.build_registered_cluster_debug_markers(
		galaxy_state,
		session,
		visible_canvas_rect,
		1.0
	)
	var preview_specs: Array = WORLD_RENDERER_SCRIPT.build_remote_cluster_preview_specs(
		galaxy_state,
		session,
		visible_canvas_rect,
		1.0
	)
	var marker_cluster_ids: Array = marker_payload.get("markers", []).map(func(marker): return int(marker.get("cluster_id", -1)))
	var preview_cluster_ids: Array = preview_specs.map(func(spec): return int(spec.get("cluster_id", -1)))

	assert_true(marker_cluster_ids.has(0), "the active cluster marker should remain when it is on screen")
	assert_true(marker_cluster_ids.has(1), "screen-relevant remote clusters should keep their debug marker payload")
	assert_false(marker_cluster_ids.has(2), "offscreen remote clusters should be culled out of the marker payload")
	assert_true(preview_cluster_ids.has(1), "screen-relevant remote clusters should still build preview specs")
	assert_false(preview_cluster_ids.has(2), "offscreen remote clusters should not build preview specs")

func test_remote_preview_lod_scales_from_marker_only_to_full_preview() -> void:
	var galaxy_state := GalaxyState.new()
	var active_cluster: ClusterState = _make_manual_preview_cluster(0, Vector2.ZERO, 100.0)
	var remote_cluster: ClusterState = _make_manual_preview_cluster(1, Vector2(1_000.0, 0.0), 100.0)
	galaxy_state.add_cluster(active_cluster)
	galaxy_state.add_cluster(remote_cluster)

	var session := ActiveClusterSession.new()
	session.bind(galaxy_state, active_cluster, SimWorld.new())
	var visible_canvas_rect := Rect2(Vector2(-4_000.0, -4_000.0), Vector2(8_000.0, 8_000.0))

	var far_specs: Array = WORLD_RENDERER_SCRIPT.build_remote_cluster_preview_specs(
		galaxy_state,
		session,
		visible_canvas_rect,
		0.25
	)
	var mid_specs: Array = WORLD_RENDERER_SCRIPT.build_remote_cluster_preview_specs(
		galaxy_state,
		session,
		visible_canvas_rect,
		1.0
	)
	var near_specs: Array = WORLD_RENDERER_SCRIPT.build_remote_cluster_preview_specs(
		galaxy_state,
		session,
		visible_canvas_rect,
		2.5
	)
	var mid_kinds: Array = mid_specs.map(func(spec): return str(spec.get("kind", "")))
	var near_kinds: Array = near_specs.map(func(spec): return str(spec.get("kind", "")))

	assert_true(far_specs.is_empty(), "marker-only LOD should skip building remote preview specs entirely")
	assert_true(mid_kinds.has("black_hole"), "mid-distance LOD should keep black-hole previews visible")
	assert_true(mid_kinds.has("star"), "mid-distance LOD should keep star previews visible")
	assert_false(mid_kinds.has("planet"), "mid-distance LOD should drop planet previews")
	assert_true(near_kinds.has("planet"), "near LOD should restore full planet previews")

func _make_manual_preview_cluster(cluster_id: int, global_center: Vector2, radius: float) -> ClusterState:
	var cluster_state := ClusterState.new()
	cluster_state.cluster_id = cluster_id
	cluster_state.global_center = global_center
	cluster_state.radius = radius
	cluster_state.cluster_seed = 90_000 + cluster_id
	cluster_state.classification = "test_preview_cluster"
	cluster_state.activation_state = ClusterActivationState.State.UNLOADED
	cluster_state.cluster_blueprint["preview_object_specs"] = [
		{
			"object_id": "cluster_%d:black_hole_0" % cluster_id,
			"kind": "black_hole",
			"body_type": SimBody.BodyType.BLACK_HOLE,
			"material_type": SimBody.MaterialType.STELLAR,
			"local_position": Vector2.ZERO,
			"radius": SimConstants.BLACK_HOLE_RADIUS,
			"seed": 10 + cluster_id,
		},
		{
			"object_id": "cluster_%d:star_0" % cluster_id,
			"kind": "star",
			"body_type": SimBody.BodyType.STAR,
			"material_type": SimBody.MaterialType.STELLAR,
			"local_position": Vector2(50.0, 0.0),
			"radius": SimConstants.STAR_RADIUS,
			"seed": 20 + cluster_id,
		},
		{
			"object_id": "cluster_%d:star_0:planet_0" % cluster_id,
			"kind": "planet",
			"body_type": SimBody.BodyType.PLANET,
			"material_type": SimBody.MaterialType.ROCKY,
			"local_position": Vector2(82.0, 0.0),
			"radius": SimConstants.PLANET_RADIUS_MIN,
			"seed": 30 + cluster_id,
		},
	]
	return cluster_state
