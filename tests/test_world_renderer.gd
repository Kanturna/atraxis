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
