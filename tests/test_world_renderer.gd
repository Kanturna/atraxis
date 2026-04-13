extends GutTest

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const ACTIVE_MACRO_SECTOR_SESSION_SCRIPT := preload("res://simulation/active_macro_sector_session.gd")
const ACTIVE_SECTOR_SESSION_SCRIPT := preload("res://simulation/active_sector_session.gd")
const CLUSTER_PREVIEW_RENDERER_SCRIPT := preload("res://rendering/cluster_preview_renderer.gd")
const MACRO_SECTOR_DESCRIPTOR_SCRIPT := preload("res://simulation/macro_sector_descriptor.gd")
const MACRO_SECTOR_ZONE_SCRIPT := preload("res://simulation/macro_sector_zone.gd")
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

func test_registered_cluster_debug_markers_encode_macro_sector_zones_and_membership() -> void:
	var galaxy_state := GalaxyState.new()
	var active_cluster: ClusterState = _make_manual_preview_cluster(0, Vector2.ZERO, 100.0)
	var ambient_cluster: ClusterState = _make_manual_preview_cluster(1, Vector2(1_000.0, 0.0), 100.0)
	var far_cluster: ClusterState = _make_manual_preview_cluster(2, Vector2(1_260.0, 0.0), 100.0)
	var outside_cluster: ClusterState = _make_manual_preview_cluster(3, Vector2(1_520.0, 0.0), 100.0)
	galaxy_state.add_cluster(active_cluster)
	galaxy_state.add_cluster(ambient_cluster)
	galaxy_state.add_cluster(far_cluster)
	galaxy_state.add_cluster(outside_cluster)

	var session := ActiveClusterSession.new()
	session.bind(galaxy_state, active_cluster, SimWorld.new())
	var macro_sector_session = _make_manual_macro_sector_session(galaxy_state, session, 0, [1], [2])
	var payload: Dictionary = WORLD_RENDERER_SCRIPT.build_registered_cluster_debug_markers(
		galaxy_state,
		session,
		Rect2(Vector2(-3_000.0, -3_000.0), Vector2(6_000.0, 6_000.0)),
		1.0,
		macro_sector_session
	)
	var markers_by_id: Dictionary = {}
	for marker in payload.get("markers", []):
		markers_by_id[int(marker.get("cluster_id", -1))] = marker

	assert_eq(str(markers_by_id[0].get("macro_sector_zone", "")), "focus", "the active cluster should expose the focus macro-sector zone")
	assert_eq(str(markers_by_id[1].get("macro_sector_zone", "")), "ambient", "ambient neighbors should expose their macro-sector zone")
	assert_eq(str(markers_by_id[2].get("macro_sector_zone", "")), "far", "far members should expose their macro-sector zone")
	assert_eq(str(markers_by_id[3].get("macro_sector_zone", "")), "outside", "non-members should expose the outside macro-sector zone")
	assert_eq(str(markers_by_id[0].get("zone_label", "")), "FOCUS", "focus markers should carry the readable macro-zone label")
	assert_eq(str(markers_by_id[1].get("zone_label", "")), "AMBIENT", "ambient markers should carry the readable macro-zone label")
	assert_eq(str(markers_by_id[2].get("zone_label", "")), "FAR", "far markers should carry the readable macro-zone label")
	assert_eq(str(markers_by_id[3].get("zone_label", "")), "OUTSIDE", "outside markers should carry the readable macro-zone label")
	assert_true(bool(markers_by_id[0].get("is_macro_sector_member", false)), "focus markers should count as macro-sector members")
	assert_true(bool(markers_by_id[1].get("is_macro_sector_member", false)), "ambient markers should count as macro-sector members")
	assert_true(bool(markers_by_id[2].get("is_macro_sector_member", false)), "far markers should count as macro-sector members")
	assert_false(bool(markers_by_id[3].get("is_macro_sector_member", true)), "outside markers should stay outside the active macro-sector")

func test_sector_debug_marker_payload_uses_sector_relation_labels_and_hides_cluster_extent_rings() -> void:
	var galaxy_state := GalaxyState.new()
	var active_cluster: ClusterState = _make_manual_preview_cluster(0, Vector2.ZERO, 100.0)
	var remote_cluster: ClusterState = _make_manual_preview_cluster(1, Vector2(1_000.0, 0.0), 100.0)
	active_cluster.simulation_profile["sector_coord"] = Vector2i(0, 0)
	remote_cluster.simulation_profile["sector_coord"] = Vector2i(1, 0)
	galaxy_state.add_cluster(active_cluster)
	galaxy_state.add_cluster(remote_cluster)

	var cluster_session := ActiveClusterSession.new()
	cluster_session.bind(galaxy_state, active_cluster, SimWorld.new())
	var active_sector_session = ACTIVE_SECTOR_SESSION_SCRIPT.new()
	active_sector_session.bind(galaxy_state, galaxy_state.get_sector_state(Vector2i(0, 0)), cluster_session)
	var payload: Dictionary = WORLD_RENDERER_SCRIPT.build_registered_cluster_debug_markers(
		galaxy_state,
		cluster_session,
		Rect2(Vector2(-8_000.0, -8_000.0), Vector2(16_000.0, 16_000.0)),
		1.0,
		null,
		active_sector_session
	)
	var active_marker: Dictionary = {}
	var remote_marker: Dictionary = {}
	for marker in payload.get("markers", []):
		if bool(marker.get("is_active", false)):
			active_marker = marker
		elif remote_marker.is_empty():
			remote_marker = marker

	assert_false(active_marker.is_empty(), "sector-mode marker payload should still expose the active contained system")
	assert_false(remote_marker.is_empty(), "sector-mode marker payload should still expose remote systems as content markers")
	assert_false(bool(active_marker.get("show_extent_ring", true)), "sector-mode markers should suppress large cluster extent rings to avoid bubble reading")
	assert_false(bool(remote_marker.get("show_extent_ring", true)), "remote sector-mode markers should also suppress large cluster extent rings")
	assert_eq(str(active_marker.get("sector_relation", "")), "active", "the active contained system should expose the active sector relation")
	assert_ne(str(remote_marker.get("sector_relation", "")), "", "remote markers should expose a readable sector relation")
	assert_true(
		str(active_marker.get("debug_label", "")).contains("SYS"),
		"sector-mode markers should use a sector-first system label instead of a macro-zone label"
	)

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

func test_sector_visual_profile_prioritizes_active_tiles_and_quiet_empty_space() -> void:
	var active_occupied: Dictionary = WORLD_RENDERER_SCRIPT.sector_visual_profile("active", true, true)
	var near_occupied: Dictionary = WORLD_RENDERER_SCRIPT.sector_visual_profile("neighbor", true, true)
	var far_empty: Dictionary = WORLD_RENDERER_SCRIPT.sector_visual_profile("far", false, true)
	var remote_empty: Dictionary = WORLD_RENDERER_SCRIPT.sector_visual_profile("remote", false, true)

	assert_gt(
		Color(active_occupied.get("border_color", Color.TRANSPARENT)).a,
		Color(near_occupied.get("border_color", Color.TRANSPARENT)).a,
		"active sector tiles should render with the strongest border so the rectangular top-level space reads first"
	)
	assert_gt(
		Color(far_empty.get("quiet_color", Color.TRANSPARENT)).a,
		Color(remote_empty.get("quiet_color", Color.TRANSPARENT)).a,
		"quiet empty sectors should keep a readable atmospheric treatment instead of disappearing completely"
	)
	assert_gt(
		Color(active_occupied.get("content_hint_color", Color.TRANSPARENT)).a,
		Color(far_empty.get("content_hint_color", Color.TRANSPARENT)).a,
		"occupied active sectors should signal contained systems more strongly than quiet empty space"
	)
	assert_gt(
		Color(active_occupied.get("label_color", Color.TRANSPARENT)).a,
		0.0,
		"debug-visible sector profiles should expose readable tile labels"
	)

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
		1.0,
		visible_canvas_rect.size
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
	var far_visible_canvas_rect := Rect2(Vector2(-4_000.0, -4_000.0), Vector2(8_000.0, 8_000.0))
	var mid_visible_canvas_rect := Rect2(Vector2(-900.0, -675.0), Vector2(1_800.0, 1_350.0))
	var near_visible_canvas_rect := Rect2(Vector2(-430.0, -305.0), Vector2(860.0, 610.0))
	var viewport_size := Vector2(1_600.0, 900.0)

	var far_specs: Array = WORLD_RENDERER_SCRIPT.build_remote_cluster_preview_specs(
		galaxy_state,
		session,
		far_visible_canvas_rect,
		1.0,
		viewport_size
	)
	var mid_specs: Array = WORLD_RENDERER_SCRIPT.build_remote_cluster_preview_specs(
		galaxy_state,
		session,
		mid_visible_canvas_rect,
		1.0,
		viewport_size
	)
	var near_specs: Array = WORLD_RENDERER_SCRIPT.build_remote_cluster_preview_specs(
		galaxy_state,
		session,
		near_visible_canvas_rect,
		1.0,
		viewport_size
	)
	var mid_kinds: Array = mid_specs.map(func(spec): return str(spec.get("kind", "")))
	var near_kinds: Array = near_specs.map(func(spec): return str(spec.get("kind", "")))

	assert_true(far_specs.is_empty(), "marker-only LOD should skip building remote preview specs entirely")
	assert_true(mid_kinds.has("black_hole"), "mid-distance LOD should keep black-hole previews visible")
	assert_true(mid_kinds.has("star"), "mid-distance LOD should keep star previews visible")
	assert_false(mid_kinds.has("planet"), "mid-distance LOD should drop planet previews")
	assert_true(near_kinds.has("planet"), "near LOD should restore full planet previews")

func test_macro_sector_debug_overlay_replaces_discovered_sector_grid_when_session_exists() -> void:
	var galaxy_state := GalaxyState.new()
	var active_cluster: ClusterState = _make_manual_preview_cluster(0, Vector2.ZERO, 100.0)
	var ambient_cluster: ClusterState = _make_manual_preview_cluster(1, Vector2(1_000.0, 0.0), 100.0)
	galaxy_state.add_cluster(active_cluster)
	galaxy_state.add_cluster(ambient_cluster)

	var session := ActiveClusterSession.new()
	session.bind(galaxy_state, active_cluster, SimWorld.new())
	var macro_sector_session = _make_manual_macro_sector_session(galaxy_state, session, 0, [1], [])

	assert_false(
		WORLD_RENDERER_SCRIPT.uses_macro_sector_debug_overlay(null),
		"without an active macro-sector session the renderer should fall back to legacy sector-grid debugging"
	)
	assert_true(
		WORLD_RENDERER_SCRIPT.uses_macro_sector_debug_overlay(macro_sector_session),
		"with an active macro-sector session the renderer should prefer macro-sector debug orientation over sector tiles"
	)

func test_macro_sector_preview_rules_keep_ambient_planets_and_strip_far_planets_from_bh_only_snapshots() -> void:
	var galaxy_state := GalaxyState.new()
	var active_cluster: ClusterState = _make_manual_preview_cluster(0, Vector2.ZERO, 100.0)
	var ambient_cluster: ClusterState = _make_manual_simplified_bh_only_preview_cluster(
		1,
		Vector2(1_000.0, 0.0),
		100.0,
		true
	)
	var far_cluster: ClusterState = _make_manual_simplified_bh_only_preview_cluster(
		2,
		Vector2(1_240.0, 0.0),
		100.0,
		true
	)
	galaxy_state.add_cluster(active_cluster)
	galaxy_state.add_cluster(ambient_cluster)
	galaxy_state.add_cluster(far_cluster)

	var session := ActiveClusterSession.new()
	session.bind(galaxy_state, active_cluster, SimWorld.new())
	var macro_sector_session = _make_manual_macro_sector_session(galaxy_state, session, 0, [1], [2])
	var near_visible_canvas_rect := Rect2(Vector2(-430.0, -305.0), Vector2(860.0, 610.0))
	var preview_specs: Array = WORLD_RENDERER_SCRIPT.build_remote_cluster_preview_specs(
		galaxy_state,
		session,
		near_visible_canvas_rect,
		1.0,
		Vector2(1_600.0, 900.0),
		macro_sector_session
	)
	var ambient_specs: Array = preview_specs.filter(func(spec): return int(spec.get("cluster_id", -1)) == 1)
	var far_specs: Array = preview_specs.filter(func(spec): return int(spec.get("cluster_id", -1)) == 2)
	var ambient_kinds: Array = ambient_specs.map(func(spec): return str(spec.get("kind", "")))
	var far_kinds: Array = far_specs.map(func(spec): return str(spec.get("kind", "")))

	assert_false(ambient_specs.is_empty(), "ambient macro-sector previews should produce visible bodies at full preview LOD")
	assert_false(far_specs.is_empty(), "far macro-sector previews should still produce macro-structure bodies at full preview LOD")
	assert_true(ambient_kinds.has("black_hole"), "ambient previews should keep the black-hole anchor visible")
	assert_true(ambient_kinds.has("star"), "ambient previews should supplement BH-only runtime snapshots with star data")
	assert_true(ambient_kinds.has("planet"), "ambient previews should keep planet silhouettes once the cluster reaches full preview LOD")
	assert_false(ambient_kinds.has("asteroid"), "ambient previews should not render asteroid noise or local clutter")
	assert_false(ambient_kinds.has("fragment"), "ambient previews should not render fragment noise or local clutter")
	assert_true(far_kinds.has("black_hole"), "far previews should keep the black-hole anchor visible")
	assert_true(far_kinds.has("star"), "far previews should still supplement BH-only snapshots with star macro-structure")
	assert_false(far_kinds.has("planet"), "far previews should never restore planets, even at full preview LOD")
	assert_false(far_kinds.has("asteroid"), "far previews should not render asteroid clutter")
	assert_false(far_kinds.has("fragment"), "far previews should not render fragment clutter")
	assert_eq(
		str(ambient_specs[0].get("macro_sector_zone", "")),
		"ambient",
		"ambient preview payloads should expose their macro sector zone for debugging"
	)
	assert_eq(
		str(far_specs[0].get("macro_sector_zone", "")),
		"far",
		"far preview payloads should expose their macro sector zone for debugging"
	)

func test_far_star_preview_style_is_dimmer_tighter_and_without_halo() -> void:
	var ambient_style: Dictionary = CLUSTER_PREVIEW_RENDERER_SCRIPT.preview_visual_profile({
		"body_type": SimBody.BodyType.STAR,
		"macro_sector_zone": "ambient",
	})
	var far_style: Dictionary = CLUSTER_PREVIEW_RENDERER_SCRIPT.preview_visual_profile({
		"body_type": SimBody.BodyType.STAR,
		"macro_sector_zone": "far",
	})
	var outside_style: Dictionary = CLUSTER_PREVIEW_RENDERER_SCRIPT.preview_visual_profile({
		"body_type": SimBody.BodyType.STAR,
		"macro_sector_zone": "outside",
	})
	var ambient_accent: Dictionary = CLUSTER_PREVIEW_RENDERER_SCRIPT.cluster_accent_profile("ambient")
	var far_accent: Dictionary = CLUSTER_PREVIEW_RENDERER_SCRIPT.cluster_accent_profile("far")
	var outside_accent: Dictionary = CLUSTER_PREVIEW_RENDERER_SCRIPT.cluster_accent_profile("outside")

	assert_lt(
		float(far_style.get("radius_scale", 1.0)),
		float(ambient_style.get("radius_scale", 1.0)),
		"far stars should render as tighter points than ambient stars"
	)
	assert_lt(
		float(far_style.get("alpha_scale", 1.0)),
		float(ambient_style.get("alpha_scale", 1.0)),
		"far stars should render dimmer than ambient stars"
	)
	assert_false(
		bool(far_style.get("draw_star_halo", true)),
		"far stars should drop the ambient halo treatment so the layer reads as macro-structure"
	)
	assert_lt(
		float(outside_style.get("alpha_scale", 1.0)),
		float(far_style.get("alpha_scale", 1.0)),
		"outside previews should stay weaker than far macro-structure instead of competing with it"
	)
	assert_gt(
		float(ambient_accent.get("fill_alpha", 0.0)),
		float(far_accent.get("fill_alpha", 0.0)),
		"ambient cluster accents should read stronger than far macro-structure accents"
	)
	assert_gt(
		float(far_accent.get("fill_alpha", 0.0)),
		float(outside_accent.get("fill_alpha", 0.0)),
		"outside cluster accents should stay weaker than far macro-structure accents"
	)

func _make_manual_preview_cluster(
		cluster_id: int,
		global_center: Vector2,
		radius: float,
		include_noise_objects: bool = false) -> ClusterState:
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
	if include_noise_objects:
		cluster_state.cluster_blueprint["preview_object_specs"].append_array([
			{
				"object_id": "cluster_%d:asteroid_0" % cluster_id,
				"kind": "asteroid",
				"body_type": SimBody.BodyType.ASTEROID,
				"material_type": SimBody.MaterialType.ROCKY,
				"local_position": Vector2(96.0, 0.0),
				"radius": 4.0,
				"seed": 40 + cluster_id,
			},
			{
				"object_id": "cluster_%d:fragment_0" % cluster_id,
				"kind": "fragment",
				"body_type": SimBody.BodyType.FRAGMENT,
				"material_type": SimBody.MaterialType.MIXED,
				"local_position": Vector2(102.0, 0.0),
				"radius": 2.0,
				"seed": 50 + cluster_id,
			},
		])
	return cluster_state

func _make_manual_simplified_bh_only_preview_cluster(
		cluster_id: int,
		global_center: Vector2,
		radius: float,
		include_noise_objects: bool = false) -> ClusterState:
	var cluster_state: ClusterState = _make_manual_preview_cluster(
		cluster_id,
		global_center,
		radius,
		include_noise_objects
	)
	cluster_state.mark_simplified(0.0)
	cluster_state.simulation_profile["has_runtime_snapshot"] = true
	cluster_state.object_registry.clear()
	cluster_state.register_object(_make_manual_preview_object_state(
		"cluster_%d:black_hole_0" % cluster_id,
		"black_hole",
		SimBody.BodyType.BLACK_HOLE,
		SimBody.MaterialType.STELLAR,
		Vector2.ZERO,
		SimConstants.BLACK_HOLE_RADIUS
	))
	return cluster_state

func _make_manual_macro_sector_session(
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		focus_cluster_id: int,
		ambient_cluster_ids: Array = [],
		far_cluster_ids: Array = []):
	var descriptor = MACRO_SECTOR_DESCRIPTOR_SCRIPT.new()
	descriptor.anchor_cluster_id = focus_cluster_id
	descriptor.focus_cluster_id = focus_cluster_id
	descriptor.member_cluster_ids = [focus_cluster_id]
	descriptor.zone_by_cluster_id = {
		focus_cluster_id: MACRO_SECTOR_ZONE_SCRIPT.Zone.FOCUS,
	}
	for cluster_id in ambient_cluster_ids:
		var member_id: int = int(cluster_id)
		descriptor.member_cluster_ids.append(member_id)
		descriptor.zone_by_cluster_id[member_id] = MACRO_SECTOR_ZONE_SCRIPT.Zone.AMBIENT
	for cluster_id in far_cluster_ids:
		var member_id: int = int(cluster_id)
		descriptor.member_cluster_ids.append(member_id)
		descriptor.zone_by_cluster_id[member_id] = MACRO_SECTOR_ZONE_SCRIPT.Zone.FAR
	var session = ACTIVE_MACRO_SECTOR_SESSION_SCRIPT.new()
	session.bind(galaxy_state, descriptor, active_cluster_session)
	return session

func _make_manual_preview_object_state(
		object_id: String,
		kind: String,
		body_type: int,
		material_type: int,
		local_position: Vector2,
		radius: float) -> ClusterObjectState:
	var object_state := ClusterObjectState.new()
	object_state.object_id = object_id
	object_state.kind = kind
	object_state.residency_state = ObjectResidencyState.State.SIMPLIFIED
	object_state.local_position = local_position
	object_state.local_velocity = Vector2.ZERO
	object_state.descriptor = {
		"body_type": body_type,
		"material_type": material_type,
		"radius": radius,
	}
	return object_state
