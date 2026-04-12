## world_renderer.gd
## Orchestrates all rendering sub-layers.
## Wired to SimWorld signals to add/remove visuals reactively.
## Reads sim state each frame via render_frame(); never writes to simulation.
class_name WorldRenderer
extends Node2D

const GRAVITY_DEBUG_RENDERER_SCRIPT := preload("res://rendering/gravity_debug_renderer.gd")

@onready var _zone_layer: Node2D = $ZoneLayer
@onready var _gravity_debug_layer: Node2D = $GravityDebugLayer
@onready var _trail_layer: Node2D = $TrailLayer
@onready var _body_layer: Node2D = $BodyLayer
@onready var _debris_layer: Node2D = $DebrisLayer

var _body_renderer: BodyRenderer
var _trail_renderer: TrailRenderer
var _zone_renderers: Dictionary = {}
var _gravity_debug_renderer: Node2D
var _debris_renderer: DebrisRenderer
var _galaxy_state: GalaxyState = null
var _active_cluster_session: ActiveClusterSession = null
var _worldgen = null
var _debug_overlays_visible: bool = false

func initialize(
		world: SimWorld,
		zones_by_star: Dictionary,
		galaxy_state: GalaxyState = null,
		active_cluster_session: ActiveClusterSession = null) -> void:
	_clear_layer(_zone_layer)
	_zone_renderers.clear()
	_clear_layer(_gravity_debug_layer)
	_clear_layer(_trail_layer)
	_clear_layer(_body_layer)
	_clear_layer(_debris_layer)
	_galaxy_state = galaxy_state
	_active_cluster_session = active_cluster_session
	_worldgen = GalaxyWorldgen.new(galaxy_state.worldgen_config) \
		if galaxy_state != null and galaxy_state.worldgen_config != null else null

	_body_renderer = BodyRenderer.new()
	_trail_renderer = TrailRenderer.new()
	_gravity_debug_renderer = GRAVITY_DEBUG_RENDERER_SCRIPT.new()
	_debris_renderer = DebrisRenderer.new()

	for star_id in zones_by_star:
		var zr := ZoneRenderer.new()
		_zone_layer.add_child(zr)
		zr.setup(zones_by_star[star_id])
		_zone_renderers[star_id] = zr

	_gravity_debug_layer.add_child(_gravity_debug_renderer)
	_trail_layer.add_child(_trail_renderer)
	_body_layer.add_child(_body_renderer)
	_debris_layer.add_child(_debris_renderer)

	set_debug_overlays_visible(false)

	# Create visuals for bodies already in the world
	for body in world.bodies:
		_on_body_added(body)

func render_frame(world: SimWorld) -> void:
	for star_id in _zone_renderers:
		var star: SimBody = world.get_body_by_id(star_id)
		_zone_renderers[star_id].update_for_star(star)
	if _gravity_debug_renderer != null:
		_gravity_debug_renderer.update_all(world.bodies)
	if _body_renderer != null:
		_body_renderer.update_all(world.bodies)
	if _trail_renderer != null:
		_trail_renderer.update_all(world.bodies)
	if _debris_renderer != null:
		_debris_renderer.update_all(world.debris_fields)
	if _debug_overlays_visible:
		queue_redraw()

func set_debug_overlays_visible(enabled: bool) -> void:
	_debug_overlays_visible = enabled
	if _gravity_debug_renderer != null:
		_gravity_debug_renderer.visible = enabled
	queue_redraw()

func set_gravity_debug_visible(enabled: bool) -> void:
	set_debug_overlays_visible(enabled)

func _on_body_added(body: SimBody) -> void:
	_body_renderer.add_body_visual(body)
	_trail_renderer.add_trail(body)

func _on_body_removed(body_id: int) -> void:
	_body_renderer.remove_body_visual(body_id)
	_trail_renderer.remove_trail(body_id)

func _clear_layer(layer: Node2D) -> void:
	for child in layer.get_children():
		child.free()

func _draw() -> void:
	if not _debug_overlays_visible \
			or _galaxy_state == null \
			or _active_cluster_session == null \
			or _worldgen == null:
		return
	_draw_discovered_sectors()
	_draw_registered_clusters()

func _draw_discovered_sectors() -> void:
	var active_sector_coord_variant = _active_cluster_session.active_cluster_state.simulation_profile.get(
		"sector_coord",
		Vector2i.ZERO
	) if _active_cluster_session.active_cluster_state != null else Vector2i.ZERO
	var active_sector_coord: Vector2i = active_sector_coord_variant \
		if active_sector_coord_variant is Vector2i \
		else Vector2i.ZERO
	var sector_size: Vector2 = Vector2.ONE * float(_worldgen.config.sector_scale)
	for sector_coord in _galaxy_state.get_discovered_sector_coords():
		var sector_origin_local: Vector2 = _active_cluster_session.to_local(_worldgen.sector_origin(sector_coord))
		var is_active_sector: bool = sector_coord == active_sector_coord
		var sector_color: Color = Color(0.36, 0.56, 0.90, 0.32) if is_active_sector else Color(0.36, 0.56, 0.90, 0.12)
		draw_rect(Rect2(sector_origin_local, sector_size), sector_color, false, 1.5 if is_active_sector else 1.0)

func _draw_registered_clusters() -> void:
	var cluster_payload: Dictionary = build_registered_cluster_debug_markers(
		_galaxy_state,
		_active_cluster_session
	)
	var marker_radius_scale: float = _debug_marker_canvas_scale()
	for marker in cluster_payload.get("markers", []):
		var cluster_id: int = int(marker.get("cluster_id", -1))
		var cluster_state: ClusterState = _galaxy_state.get_cluster(cluster_id)
		if cluster_state == null:
			continue
		var cluster_local_center: Vector2 = Vector2(marker.get("local_center", Vector2.ZERO))
		var cluster_color: Color = _cluster_debug_color(cluster_state)
		var is_active: bool = bool(marker.get("is_active", false))
		var line_width: float = 2.6 if is_active else 1.5
		var marker_radius: float = cluster_debug_marker_world_radius(
			float(marker.get("radius", cluster_state.get_authoritative_radius())),
			marker_radius_scale,
			is_active
		)
		draw_arc(
			cluster_local_center,
			cluster_state.get_authoritative_radius(),
			0.0,
			TAU,
			64,
			cluster_color,
			line_width
		)
		draw_circle(
			cluster_local_center,
			marker_radius,
			Color(cluster_color.r, cluster_color.g, cluster_color.b, 0.16 if is_active else 0.11)
		)
		draw_arc(
			cluster_local_center,
			marker_radius,
			0.0,
			TAU,
			32,
			cluster_color,
			2.0 if is_active else 1.2
		)
		var cross_half_extent: float = marker_radius * 0.75
		draw_line(
			cluster_local_center + Vector2(-cross_half_extent, 0.0),
			cluster_local_center + Vector2(cross_half_extent, 0.0),
			cluster_color,
			2.0 if is_active else 1.4
		)
		draw_line(
			cluster_local_center + Vector2(0.0, -cross_half_extent),
			cluster_local_center + Vector2(0.0, cross_half_extent),
			cluster_color,
			2.0 if is_active else 1.4
		)
	_draw_cluster_label(_active_cluster_session.active_cluster_state, "ACTIVE")
	var nearest_remote_cluster: ClusterState = _galaxy_state.get_cluster(
		int(cluster_payload.get("nearest_remote_cluster_id", -1))
	)
	if nearest_remote_cluster != null:
		_draw_cluster_label(nearest_remote_cluster, "GHOST")

func _draw_cluster_label(cluster_state: ClusterState, label_prefix: String) -> void:
	if cluster_state == null or ThemeDB.fallback_font == null:
		return
	var label_position: Vector2 = _active_cluster_session.to_local(cluster_state.global_center)
	label_position += Vector2(12.0, -10.0)
	draw_string(
		ThemeDB.fallback_font,
		label_position,
		"%s C%d" % [label_prefix, cluster_state.cluster_id],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		ThemeDB.fallback_font_size,
		_cluster_debug_color(cluster_state)
	)

func _cluster_debug_color(cluster_state: ClusterState) -> Color:
	if cluster_state == null:
		return Color(1.0, 1.0, 1.0, 0.3)
	match cluster_state.activation_state:
		ClusterActivationState.State.ACTIVE:
			return Color(0.98, 0.90, 0.34, 0.82)
		ClusterActivationState.State.SIMPLIFIED:
			return Color(0.36, 0.92, 0.86, 0.60)
		_:
			return Color(0.86, 0.89, 0.98, 0.44)

func _debug_marker_canvas_scale() -> float:
	var canvas_scale: Vector2 = get_canvas_transform().get_scale()
	return maxf(maxf(absf(canvas_scale.x), absf(canvas_scale.y)), 0.001)

static func build_registered_cluster_debug_markers(
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession) -> Dictionary:
	var markers: Array = []
	var nearest_remote_cluster_id: int = -1
	var nearest_remote_distance: float = INF
	if galaxy_state == null or active_cluster_session == null:
		return {
			"markers": markers,
			"nearest_remote_cluster_id": nearest_remote_cluster_id,
		}
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state == null:
			continue
		var is_active: bool = cluster_state.cluster_id == active_cluster_session.cluster_id
		var local_center: Vector2 = active_cluster_session.to_local(cluster_state.global_center)
		markers.append({
			"cluster_id": cluster_state.cluster_id,
			"local_center": local_center,
			"radius": cluster_state.get_authoritative_radius(),
			"is_active": is_active,
			"state": activation_state_debug_name(cluster_state.activation_state),
		})
		if not is_active:
			var center_distance: float = local_center.length()
			if center_distance < nearest_remote_distance:
				nearest_remote_distance = center_distance
				nearest_remote_cluster_id = cluster_state.cluster_id
	return {
		"markers": markers,
		"nearest_remote_cluster_id": nearest_remote_cluster_id,
	}

static func cluster_debug_marker_world_radius(
		cluster_radius: float,
		canvas_scale: float,
		is_active: bool = false) -> float:
	var safe_canvas_scale: float = maxf(canvas_scale, 0.001)
	var min_marker_radius: float = (4.0 if is_active else 3.0) / safe_canvas_scale
	var target_marker_radius: float = (11.0 if is_active else 8.0) / safe_canvas_scale
	var max_marker_radius: float = maxf(
		cluster_radius * (0.09 if is_active else 0.06),
		min_marker_radius
	)
	return clampf(target_marker_radius, min_marker_radius, max_marker_radius)

static func activation_state_debug_name(activation_state: int) -> String:
	match activation_state:
		ClusterActivationState.State.ACTIVE:
			return "active"
		ClusterActivationState.State.SIMPLIFIED:
			return "simplified"
		_:
			return "unloaded"
