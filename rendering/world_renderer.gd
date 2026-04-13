## world_renderer.gd
## Orchestrates all rendering sub-layers.
## Wired to SimWorld signals to add/remove visuals reactively.
## Reads sim state each frame via render_frame(); never writes to simulation.
class_name WorldRenderer
extends Node2D

const GRAVITY_DEBUG_RENDERER_SCRIPT := preload("res://rendering/gravity_debug_renderer.gd")
const CLUSTER_PREVIEW_RENDERER_SCRIPT := preload("res://rendering/cluster_preview_renderer.gd")
const CLUSTER_MARKER_RENDERER_SCRIPT := preload("res://rendering/cluster_marker_renderer.gd")
const MACRO_SECTOR_ZONE_SCRIPT := preload("res://simulation/macro_sector_zone.gd")
const REMOTE_CLUSTER_MARKER_CULL_MARGIN_PX: float = 96.0
const REMOTE_CLUSTER_PREVIEW_CULL_MARGIN_PX: float = 96.0
const PREVIEW_LOD_MARKER_ONLY: int = 0
const PREVIEW_LOD_BH_AND_STARS: int = 1
const PREVIEW_LOD_FULL: int = 2
const PREVIEW_LOD_BH_AND_STARS_MAX_SCREEN_RADIUS: float = 32.0
const PREVIEW_LOD_FULL_MIN_SCREEN_RADIUS: float = 72.0
const SECTOR_DRAW_CULL_MARGIN_PX: float = 72.0
const SECTOR_LABEL_FONT_MIN_SIZE: int = 10

@onready var _zone_layer: Node2D = $ZoneLayer
@onready var _gravity_debug_layer: Node2D = $GravityDebugLayer
@onready var _trail_layer: Node2D = $TrailLayer
@onready var _body_layer: Node2D = $BodyLayer
@onready var _debris_layer: Node2D = $DebrisLayer

var _preview_layer: Node2D = null
var _marker_layer: Node2D = null
var _body_renderer: BodyRenderer
var _trail_renderer: TrailRenderer
var _zone_renderers: Dictionary = {}
var _gravity_debug_renderer: Node2D
var _debris_renderer: DebrisRenderer
var _preview_renderer: Node2D = null
var _cluster_marker_renderer: Node2D = null
var _galaxy_state: GalaxyState = null
var _active_sector_session = null
var _active_cluster_session: ActiveClusterSession = null
var _active_macro_sector_session = null
var _worldgen = null
var _debug_overlays_visible: bool = false
var _cached_remote_preview_specs: Array = []
var _cached_marker_payload: Dictionary = {}

func initialize(
		world: SimWorld,
		zones_by_star: Dictionary,
		galaxy_state: GalaxyState = null,
		active_sector_session = null,
		active_cluster_session: ActiveClusterSession = null,
		active_macro_sector_session = null,
		preserve_remote_layers: bool = false) -> void:
	_ensure_overlay_layers()
	_clear_layer(_zone_layer)
	_zone_renderers.clear()
	_clear_layer(_gravity_debug_layer)
	_clear_layer(_trail_layer)
	_clear_layer(_body_layer)
	_clear_layer(_debris_layer)
	if not preserve_remote_layers:
		_clear_layer(_preview_layer)
		_clear_layer(_marker_layer)
	_galaxy_state = galaxy_state
	_active_sector_session = active_sector_session
	_active_cluster_session = active_cluster_session
	_active_macro_sector_session = active_macro_sector_session
	_cached_remote_preview_specs = []
	_cached_marker_payload = {}
	_worldgen = GalaxyWorldgen.new(galaxy_state.worldgen_config) \
		if galaxy_state != null and galaxy_state.worldgen_config != null else null
	_sync_active_world_layer_offsets()

	_body_renderer = BodyRenderer.new()
	_trail_renderer = TrailRenderer.new()
	_gravity_debug_renderer = GRAVITY_DEBUG_RENDERER_SCRIPT.new()
	_debris_renderer = DebrisRenderer.new()
	if not preserve_remote_layers or _preview_renderer == null or not is_instance_valid(_preview_renderer):
		_preview_renderer = CLUSTER_PREVIEW_RENDERER_SCRIPT.new()
	if not preserve_remote_layers or _cluster_marker_renderer == null or not is_instance_valid(_cluster_marker_renderer):
		_cluster_marker_renderer = CLUSTER_MARKER_RENDERER_SCRIPT.new()

	for star_id in zones_by_star:
		var zr := ZoneRenderer.new()
		_zone_layer.add_child(zr)
		zr.setup(zones_by_star[star_id])
		_zone_renderers[star_id] = zr

	_gravity_debug_layer.add_child(_gravity_debug_renderer)
	_trail_layer.add_child(_trail_renderer)
	_body_layer.add_child(_body_renderer)
	_debris_layer.add_child(_debris_renderer)
	if _preview_renderer.get_parent() != _preview_layer:
		_preview_layer.add_child(_preview_renderer)
	if _cluster_marker_renderer.get_parent() != _marker_layer:
		_marker_layer.add_child(_cluster_marker_renderer)

	set_debug_overlays_visible(false)

	for body in world.bodies:
		_on_body_added(body)

func render_frame(world: SimWorld) -> void:
	_sync_active_world_layer_offsets()
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
	var canvas_scale: float = _debug_marker_canvas_scale()
	var visible_canvas_rect: Rect2 = _visible_canvas_rect()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_cached_remote_preview_specs = build_remote_cluster_preview_specs(
		_galaxy_state,
		_active_cluster_session,
		visible_canvas_rect,
		canvas_scale,
		viewport_size,
		_active_macro_sector_session,
		_active_sector_session
	)
	_cached_marker_payload = build_registered_cluster_debug_markers(
		_galaxy_state,
		_active_cluster_session,
		visible_canvas_rect,
		canvas_scale,
		_active_macro_sector_session,
		_active_sector_session
	)
	if _preview_renderer != null:
		_preview_renderer.update_preview_specs(_cached_remote_preview_specs, canvas_scale, visible_canvas_rect)
	if _cluster_marker_renderer != null:
		_cluster_marker_renderer.update_marker_payload(
			_cached_marker_payload,
			canvas_scale,
			visible_canvas_rect
		)
	if _active_sector_session != null or _debug_overlays_visible:
		queue_redraw()

func set_debug_overlays_visible(enabled: bool) -> void:
	_debug_overlays_visible = enabled
	if _gravity_debug_renderer != null:
		_gravity_debug_renderer.visible = enabled
	if _cluster_marker_renderer != null:
		_cluster_marker_renderer.visible = enabled
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
	if layer == null:
		return
	for child in layer.get_children():
		child.free()

func _ensure_overlay_layers() -> void:
	if _preview_layer == null:
		_preview_layer = Node2D.new()
		_preview_layer.name = "PreviewLayer"
		add_child(_preview_layer)
		move_child(_preview_layer, _body_layer.get_index())
	if _marker_layer == null:
		_marker_layer = Node2D.new()
		_marker_layer.name = "MarkerLayer"
		add_child(_marker_layer)
		move_child(_marker_layer, get_child_count() - 1)

func _sync_active_world_layer_offsets() -> void:
	var local_offset: Vector2 = active_world_layer_local_offset(
		_active_sector_session,
		_active_cluster_session
	)
	var screen_offset: Vector2 = BodyRenderer.sim_to_screen(local_offset)
	for layer in [_zone_layer, _gravity_debug_layer, _trail_layer, _body_layer, _debris_layer]:
		if layer != null:
			layer.position = screen_offset
	if _preview_layer != null:
		_preview_layer.position = Vector2.ZERO
	if _marker_layer != null:
		_marker_layer.position = Vector2.ZERO

func _draw() -> void:
	if _galaxy_state == null or (_active_cluster_session == null and _active_sector_session == null):
		return
	if _active_sector_session != null and _worldgen != null:
		_draw_discovered_sectors()
	elif _debug_overlays_visible and uses_macro_sector_debug_overlay(_active_macro_sector_session):
		_draw_active_macro_sector_overlay()
	elif _debug_overlays_visible and _worldgen != null:
		_draw_discovered_sectors()

func _draw_active_macro_sector_overlay() -> void:
	var markers: Array = _cached_marker_payload.get("markers", [])
	if markers.is_empty():
		return
	_draw_macro_sector_cluster_zones(markers)
	_draw_macro_sector_membership_links(markers)

func _draw_macro_sector_cluster_zones(markers: Array) -> void:
	var canvas_scale: float = _debug_marker_canvas_scale()
	var viewport_diagonal: float = get_viewport().get_visible_rect().size.length()
	for marker in markers:
		var cluster_radius_screen: float = BodyRenderer.sim_dist_to_screen(float(marker.get("radius", 0.0)))
		if cluster_radius_screen < 0.5 \
				or not should_draw_cluster_extent_ring(cluster_radius_screen, viewport_diagonal):
			continue
		var center: Vector2 = BodyRenderer.snap_screen_point(
			BodyRenderer.sim_to_screen(Vector2(marker.get("local_center", Vector2.ZERO)))
		)
		var cluster_color: Color = Color(marker.get("color", Color.WHITE))
		var fill_alpha: float = float(marker.get("overlay_fill_alpha", 0.0))
		var ring_alpha: float = float(marker.get("overlay_ring_alpha", 0.0))
		if fill_alpha > 0.0:
			draw_circle(
				center,
				cluster_radius_screen,
				Color(cluster_color.r, cluster_color.g, cluster_color.b, fill_alpha)
			)
		if ring_alpha > 0.0:
			var ring_width: float = maxf(
				float(marker.get("overlay_ring_width", 1.0)) / canvas_scale,
				0.9 / canvas_scale
			)
			draw_arc(
				center,
				cluster_radius_screen,
				0.0,
				TAU,
				80,
				Color(cluster_color.r, cluster_color.g, cluster_color.b, ring_alpha),
				ring_width
			)

func _draw_macro_sector_membership_links(markers: Array) -> void:
	var canvas_scale: float = _debug_marker_canvas_scale()
	var focus_marker: Dictionary = {}
	for marker in markers:
		if int(marker.get("macro_sector_zone_id", MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE)) == MACRO_SECTOR_ZONE_SCRIPT.Zone.FOCUS:
			focus_marker = marker
			break
	if focus_marker.is_empty():
		return
	var focus_center: Vector2 = BodyRenderer.snap_screen_point(
		BodyRenderer.sim_to_screen(Vector2(focus_marker.get("local_center", Vector2.ZERO)))
	)
	for marker in markers:
		if int(marker.get("cluster_id", -1)) == int(focus_marker.get("cluster_id", -1)):
			continue
		if not bool(marker.get("is_macro_sector_member", false)):
			continue
		var link_alpha: float = float(marker.get("link_alpha", 0.0))
		if link_alpha <= 0.0:
			continue
		var center: Vector2 = BodyRenderer.snap_screen_point(
			BodyRenderer.sim_to_screen(Vector2(marker.get("local_center", Vector2.ZERO)))
		)
		var cluster_color: Color = Color(marker.get("color", Color.WHITE))
		var line_width: float = maxf(
			float(marker.get("link_width", 1.0)) / canvas_scale,
			0.9 / canvas_scale
		)
		draw_line(
			focus_center,
			center,
			Color(cluster_color.r, cluster_color.g, cluster_color.b, link_alpha),
			line_width,
			true
		)

func _draw_discovered_sectors() -> void:
	if _active_sector_session == null or _active_sector_session.sector_state == null:
		return
	var visible_canvas_rect: Rect2 = _visible_canvas_rect()
	var active_sector_coord: Vector2i = _active_sector_session.sector_state.sector_coord
	var sector_size_screen_scalar: float = BodyRenderer.sim_dist_to_screen(float(_worldgen.config.sector_scale))
	var sector_size_screen: Vector2 = Vector2.ONE * sector_size_screen_scalar
	var canvas_scale: float = _debug_marker_canvas_scale()
	for sector_coord in _galaxy_state.get_discovered_sector_coords():
		var sector_state = _galaxy_state.get_sector_state(sector_coord)
		var contains_systems: bool = sector_state != null and not sector_state.cluster_ids.is_empty()
		var sector_relation: String = sector_relation_name(sector_coord, active_sector_coord)
		var sector_origin_local: Vector2 = _active_sector_session.to_local(_worldgen.sector_origin(sector_coord))
		var sector_origin_screen: Vector2 = BodyRenderer.snap_screen_point(
			BodyRenderer.sim_to_screen(sector_origin_local)
		)
		var sector_rect := Rect2(sector_origin_screen, sector_size_screen)
		if visible_canvas_rect.has_area() and not visible_canvas_rect.intersects(
				sector_rect.grow(SECTOR_DRAW_CULL_MARGIN_PX / canvas_scale)
		):
			continue
		var visual_profile: Dictionary = sector_visual_profile(
			sector_relation,
			contains_systems,
			_debug_overlays_visible
		)
		_draw_sector_tile(sector_rect, sector_coord, sector_state, visual_profile)

func _draw_sector_tile(
		sector_rect: Rect2,
		sector_coord: Vector2i,
		sector_state,
		visual_profile: Dictionary) -> void:
	var canvas_scale: float = _debug_marker_canvas_scale()
	var fill_color: Color = Color(visual_profile.get("fill_color", Color.TRANSPARENT))
	if fill_color.a > 0.0:
		draw_rect(sector_rect, fill_color, true)
	var border_color: Color = Color(visual_profile.get("border_color", Color.TRANSPARENT))
	var border_width: float = maxf(float(visual_profile.get("border_width", 1.0)) / canvas_scale, 0.9 / canvas_scale)
	if border_color.a > 0.0:
		draw_rect(sector_rect, border_color, false, border_width)
	_draw_sector_corner_brackets(
		sector_rect,
		Color(visual_profile.get("corner_color", border_color)),
		maxf(float(visual_profile.get("corner_width", 1.0)) / canvas_scale, 0.9 / canvas_scale)
	)
	var cluster_ids: Array = sector_state.cluster_ids if sector_state != null else []
	if cluster_ids.is_empty():
		_draw_quiet_sector_atmosphere(
			sector_rect,
			sector_coord,
			Color(visual_profile.get("quiet_color", Color.TRANSPARENT)),
			maxf(float(visual_profile.get("quiet_width", 1.0)) / canvas_scale, 0.7 / canvas_scale)
		)
	else:
		_draw_sector_system_hint(
			sector_rect,
			cluster_ids.size(),
			Color(visual_profile.get("content_hint_color", Color.TRANSPARENT))
		)
	if _debug_overlays_visible:
		_draw_sector_debug_label(
			sector_rect,
			sector_coord,
			sector_relation_name(sector_coord, _active_sector_session.sector_state.sector_coord),
			cluster_ids.size(),
			Color(visual_profile.get("label_color", border_color))
		)

func _draw_sector_corner_brackets(sector_rect: Rect2, color: Color, width: float) -> void:
	if color.a <= 0.0:
		return
	var corner_extent: float = clampf(minf(sector_rect.size.x, sector_rect.size.y) * 0.09, 12.0 / _debug_marker_canvas_scale(), 42.0 / _debug_marker_canvas_scale())
	var top_left: Vector2 = sector_rect.position
	var top_right: Vector2 = sector_rect.position + Vector2(sector_rect.size.x, 0.0)
	var bottom_left: Vector2 = sector_rect.position + Vector2(0.0, sector_rect.size.y)
	var bottom_right: Vector2 = sector_rect.position + sector_rect.size
	draw_line(top_left, top_left + Vector2(corner_extent, 0.0), color, width, true)
	draw_line(top_left, top_left + Vector2(0.0, corner_extent), color, width, true)
	draw_line(top_right, top_right + Vector2(-corner_extent, 0.0), color, width, true)
	draw_line(top_right, top_right + Vector2(0.0, corner_extent), color, width, true)
	draw_line(bottom_left, bottom_left + Vector2(corner_extent, 0.0), color, width, true)
	draw_line(bottom_left, bottom_left + Vector2(0.0, -corner_extent), color, width, true)
	draw_line(bottom_right, bottom_right + Vector2(-corner_extent, 0.0), color, width, true)
	draw_line(bottom_right, bottom_right + Vector2(0.0, -corner_extent), color, width, true)

func _draw_sector_system_hint(sector_rect: Rect2, system_count: int, color: Color) -> void:
	if system_count <= 0 or color.a <= 0.0:
		return
	var safe_count: int = mini(system_count, 3)
	var pip_size: float = maxf(6.0 / _debug_marker_canvas_scale(), 3.0)
	var pip_spacing: float = pip_size * 0.55
	var start_x: float = sector_rect.position.x + sector_rect.size.x - (pip_size * safe_count) - (pip_spacing * maxi(safe_count - 1, 0)) - (14.0 / _debug_marker_canvas_scale())
	var pip_y: float = sector_rect.position.y + (12.0 / _debug_marker_canvas_scale())
	for index in range(safe_count):
		var pip_rect := Rect2(
			Vector2(start_x + float(index) * (pip_size + pip_spacing), pip_y),
			Vector2.ONE * pip_size
		)
		draw_rect(pip_rect, color, true)
		draw_rect(pip_rect, Color(color.r, color.g, color.b, minf(color.a + 0.14, 1.0)), false, maxf(1.1 / _debug_marker_canvas_scale(), 0.8))

func _draw_quiet_sector_atmosphere(
		sector_rect: Rect2,
		sector_coord: Vector2i,
		color: Color,
		line_width: float) -> void:
	if color.a <= 0.0:
		return
	var center: Vector2 = sector_rect.get_center()
	var calm_radius: float = minf(sector_rect.size.x, sector_rect.size.y) * 0.055
	draw_circle(center, calm_radius, Color(color.r, color.g, color.b, color.a * 0.32))
	for index in range(3):
		var hash_a: float = _sector_hash01(sector_coord, index * 13 + 1)
		var hash_b: float = _sector_hash01(sector_coord, index * 13 + 2)
		var hash_c: float = _sector_hash01(sector_coord, index * 13 + 3)
		var point := sector_rect.position + Vector2(
			lerpf(sector_rect.size.x * 0.20, sector_rect.size.x * 0.80, hash_a),
			lerpf(sector_rect.size.y * 0.22, sector_rect.size.y * 0.78, hash_b)
		)
		var direction: Vector2 = Vector2(1.0, -0.55 if hash_c < 0.5 else 0.55).normalized()
		var segment_length: float = lerpf(sector_rect.size.x * 0.04, sector_rect.size.x * 0.08, hash_c)
		draw_line(
			point - direction * segment_length * 0.5,
			point + direction * segment_length * 0.5,
			color,
			line_width,
			true
		)

func _draw_sector_debug_label(
		sector_rect: Rect2,
		sector_coord: Vector2i,
		sector_relation: String,
		system_count: int,
		color: Color) -> void:
	if color.a <= 0.0 or ThemeDB.fallback_font == null:
		return
	var canvas_scale: float = _debug_marker_canvas_scale()
	var font_size: int = maxi(
		int(round(float(ThemeDB.fallback_font_size) / maxf(canvas_scale, 0.9))),
		SECTOR_LABEL_FONT_MIN_SIZE
	)
	var label_position: Vector2 = sector_rect.position + Vector2(
		12.0 / canvas_scale,
		20.0 / canvas_scale
	)
	var occupancy_label: String = "VOID" if system_count <= 0 else "SYS %d" % system_count
	var debug_label: String = "%s  %s  %s" % [
		_format_sector_coord(sector_coord),
		sector_relation_short_label(sector_relation),
		occupancy_label,
	]
	draw_string(
		ThemeDB.fallback_font,
		label_position,
		debug_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)

func _sector_hash01(sector_coord: Vector2i, salt: int) -> float:
	var raw_hash: int = int(sector_coord.x) * 92_821 + int(sector_coord.y) * 68_917 + salt * 1_301 + 19_937
	raw_hash = abs(raw_hash % 9_973)
	return float(raw_hash) / 9_973.0

func _format_sector_coord(sector_coord: Vector2i) -> String:
	return "%d:%d" % [sector_coord.x, sector_coord.y]

func _debug_marker_canvas_scale() -> float:
	var canvas_scale: Vector2 = get_canvas_transform().get_scale()
	return maxf(maxf(absf(canvas_scale.x), absf(canvas_scale.y)), 0.001)

func pick_remote_cluster_at_canvas_position(canvas_position: Vector2) -> Dictionary:
	return pick_remote_cluster_from_payloads(
		_cached_remote_preview_specs,
		_cached_marker_payload,
		_galaxy_state,
		_active_cluster_session,
		canvas_position,
		_debug_marker_canvas_scale(),
		_active_sector_session
	)

func _visible_canvas_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2()
	var visible_rect: Rect2 = viewport.get_visible_rect()
	var inverse_canvas: Transform2D = viewport.get_canvas_transform().affine_inverse()
	var corners := [
		inverse_canvas * visible_rect.position,
		inverse_canvas * Vector2(visible_rect.position.x + visible_rect.size.x, visible_rect.position.y),
		inverse_canvas * Vector2(visible_rect.position.x, visible_rect.position.y + visible_rect.size.y),
		inverse_canvas * (visible_rect.position + visible_rect.size),
	]
	var min_x: float = corners[0].x
	var max_x: float = corners[0].x
	var min_y: float = corners[0].y
	var max_y: float = corners[0].y
	for corner in corners:
		min_x = minf(min_x, corner.x)
		max_x = maxf(max_x, corner.x)
		min_y = minf(min_y, corner.y)
		max_y = maxf(max_y, corner.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

static func build_registered_cluster_debug_markers(
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		visible_canvas_rect: Rect2 = Rect2(),
		canvas_scale: float = 1.0,
		active_macro_sector_session = null,
		active_sector_session = null) -> Dictionary:
	var markers: Array = []
	var nearest_remote_cluster_id: int = -1
	var nearest_remote_distance: float = INF
	var reference_session = active_sector_session if active_sector_session != null else active_cluster_session
	var active_cluster_id: int = active_cluster_session.cluster_id if active_cluster_session != null else -1
	if galaxy_state == null or reference_session == null:
		return {
			"markers": markers,
			"nearest_remote_cluster_id": nearest_remote_cluster_id,
		}
	var safe_canvas_scale: float = maxf(canvas_scale, 0.001)
	var sector_mode: bool = active_sector_session != null and active_sector_session.sector_state != null
	var active_sector_coord: Vector2i = active_sector_session.sector_state.sector_coord if sector_mode else Vector2i.ZERO
	var has_macro_sector_overlay: bool = uses_macro_sector_debug_overlay(active_macro_sector_session)
	var marker_cull_margin: float = REMOTE_CLUSTER_MARKER_CULL_MARGIN_PX / safe_canvas_scale
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state == null:
			continue
		var is_active: bool = cluster_state.cluster_id == active_cluster_id
		var macro_sector_zone: int = _resolve_macro_sector_zone(
			active_macro_sector_session,
			cluster_state.cluster_id
		) if has_macro_sector_overlay else MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE
		var sector_coord: Vector2i = _resolve_cluster_sector_coord(galaxy_state, cluster_state)
		var sector_relation: String = sector_relation_name(sector_coord, active_sector_coord) if sector_mode else ""
		var sector_relevance: String = sector_content_relevance_name(
			sector_relation,
			is_active
		) if sector_mode else sector_relevance_from_macro_zone(macro_sector_zone, is_active)
		var sector_state = galaxy_state.get_sector_state(sector_coord) if sector_mode else null
		var sector_cluster_count: int = sector_state.cluster_ids.size() if sector_state != null else 1
		var zone_profile: Dictionary = sector_marker_debug_profile(
			sector_relation,
			is_active,
			sector_cluster_count
		) if sector_mode else (macro_sector_zone_debug_profile(
			macro_sector_zone,
			is_active
		) if has_macro_sector_overlay else {})
		var local_center: Vector2 = reference_session.to_local(cluster_state.global_center)
		var marker_center: Vector2 = BodyRenderer.sim_to_screen(local_center)
		var marker_radius_world: float = cluster_debug_marker_world_radius(
			cluster_state.get_authoritative_radius(),
			safe_canvas_scale,
			is_active
		)
		var cluster_radius_canvas: float = BodyRenderer.sim_dist_to_screen(cluster_state.get_authoritative_radius())
		var marker_radius_canvas: float = BodyRenderer.sim_dist_to_screen(marker_radius_world)
		var cull_radius: float = maxf(cluster_radius_canvas, marker_radius_canvas)
		if not _is_cluster_visible_in_canvas_rect(
			marker_center,
			cull_radius,
			visible_canvas_rect,
			marker_cull_margin
		):
			continue
		markers.append({
			"cluster_id": cluster_state.cluster_id,
			"local_center": local_center,
			"radius": cluster_state.get_authoritative_radius(),
			"is_active": is_active,
			"state": activation_state_debug_name(cluster_state.activation_state),
			"color": zone_profile.get("marker_color", cluster_debug_color(cluster_state.activation_state)),
			"marker_fill_alpha": float(zone_profile.get("marker_fill_alpha", 0.12 if is_active else 0.08)),
			"show_extent_ring": bool(zone_profile.get("show_extent_ring", true)),
			"macro_sector_zone_id": macro_sector_zone,
			"macro_sector_zone": MACRO_SECTOR_ZONE_SCRIPT.debug_name(macro_sector_zone),
			"is_macro_sector_member": has_macro_sector_overlay and macro_sector_zone != MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE,
			"zone_label": macro_sector_zone_label(macro_sector_zone) if has_macro_sector_overlay else "",
			"sector_coord": sector_coord,
			"sector_relation": sector_relation,
			"sector_relevance": sector_relevance,
			"sector_relevance_label": sector_content_relevance_label(sector_relevance),
			"sector_relation_label": sector_relation_short_label(sector_relation) if sector_mode else "",
			"sector_contains_systems": sector_cluster_count > 0,
			"sector_cluster_count": sector_cluster_count,
			"overlay_fill_alpha": float(zone_profile.get("overlay_fill_alpha", 0.0)),
			"overlay_ring_alpha": float(zone_profile.get("overlay_ring_alpha", 0.0)),
			"overlay_ring_width": float(zone_profile.get("overlay_ring_width", 1.0)),
			"link_alpha": float(zone_profile.get("link_alpha", 0.0)),
			"link_width": float(zone_profile.get("link_width", 1.0)),
		})
		if not is_active:
			var center_distance: float = local_center.length()
			if center_distance < nearest_remote_distance:
				nearest_remote_distance = center_distance
				nearest_remote_cluster_id = cluster_state.cluster_id
	for marker in markers:
		var marker_cluster_id: int = int(marker.get("cluster_id", -1))
		var marker_state: String = str(marker.get("state", ""))
		var label_prefix: String = ""
		if sector_mode:
			label_prefix = "%s SYS" % str(marker.get("sector_relevance_label", "REMOTE"))
		elif has_macro_sector_overlay:
			label_prefix = str(marker.get("zone_label", ""))
		elif bool(marker.get("is_active", false)):
			label_prefix = "ACTIVE"
		elif marker_cluster_id == nearest_remote_cluster_id:
			label_prefix = "PREVIEW" if marker_state == "simplified" else "UNLOADED"
		marker["label_prefix"] = label_prefix
		marker["debug_label"] = label_prefix
	return {
		"markers": markers,
		"nearest_remote_cluster_id": nearest_remote_cluster_id,
	}

static func build_remote_cluster_preview_specs(
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		visible_canvas_rect: Rect2 = Rect2(),
		canvas_scale: float = 1.0,
		viewport_size: Vector2 = Vector2.ZERO,
		active_macro_sector_session = null,
		active_sector_session = null) -> Array:
	var preview_specs: Array = []
	var reference_session = active_sector_session if active_sector_session != null else active_cluster_session
	if galaxy_state == null or reference_session == null:
		return preview_specs
	var safe_canvas_scale: float = maxf(canvas_scale, 0.001)
	var preview_cull_margin: float = REMOTE_CLUSTER_PREVIEW_CULL_MARGIN_PX / safe_canvas_scale
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state == null or (active_cluster_session != null and cluster_state.cluster_id == active_cluster_session.cluster_id):
			continue
		var macro_sector_zone: int = _resolve_macro_sector_zone(
			active_macro_sector_session,
			cluster_state.cluster_id
		)
		var sector_coord: Vector2i = _resolve_cluster_sector_coord(galaxy_state, cluster_state)
		var sector_relation: String = sector_relation_name(
			sector_coord,
			active_sector_session.sector_state.sector_coord
		) if active_sector_session != null and active_sector_session.sector_state != null else ""
		var sector_relevance: String = sector_content_relevance_name(
			sector_relation,
			false
		) if active_sector_session != null and active_sector_session.sector_state != null else sector_relevance_from_macro_zone(macro_sector_zone)
		var local_center: Vector2 = reference_session.to_local(cluster_state.global_center)
		var cluster_center_canvas: Vector2 = BodyRenderer.sim_to_screen(local_center)
		var cluster_radius_canvas: float = BodyRenderer.sim_dist_to_screen(cluster_state.get_authoritative_radius())
		if not _is_cluster_visible_in_canvas_rect(
			cluster_center_canvas,
			cluster_radius_canvas,
			visible_canvas_rect,
			preview_cull_margin
		):
			continue
		var cluster_screen_radius: float = _cluster_canvas_radius_to_screen_radius(
			cluster_radius_canvas,
			visible_canvas_rect,
			viewport_size
		)
		var preview_lod: int = cluster_preview_lod_for_screen_radius(cluster_screen_radius)
		if preview_lod == PREVIEW_LOD_MARKER_ONLY:
			continue
		var source_specs: Array = _remote_cluster_preview_source_specs(
			cluster_state,
			preview_lod,
			macro_sector_zone
		)
		for source_spec in source_specs:
			var source_local_position: Vector2 = Vector2(source_spec.get("local_position", Vector2.ZERO))
			var source_global_position: Vector2 = cluster_state.global_center + source_local_position
			var local_position: Vector2 = reference_session.to_local(source_global_position)
			var preview_spec: Dictionary = {
				"object_id": str(source_spec.get("object_id", "")),
				"kind": str(source_spec.get("kind", "")),
				"body_type": int(source_spec.get("body_type", SimBody.BodyType.ASTEROID)),
				"material_type": int(source_spec.get("material_type", SimBody.MaterialType.MIXED)),
				"local_position": local_position,
				"cluster_local_center": local_center,
				"cluster_radius": cluster_state.get_authoritative_radius(),
				"radius": float(source_spec.get("radius", 1.0)),
				"seed": int(source_spec.get("seed", 0)),
				"cluster_id": cluster_state.cluster_id,
				"state": activation_state_debug_name(cluster_state.activation_state),
				"preview_lod": preview_lod,
				"sector_coord": sector_coord,
				"sector_relation": sector_relation,
				"sector_relevance": sector_relevance,
				"sector_relevance_label": sector_content_relevance_label(sector_relevance),
				"macro_sector_zone": MACRO_SECTOR_ZONE_SCRIPT.debug_name(macro_sector_zone),
				"is_macro_sector_member": macro_sector_zone != MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE,
			}
			preview_specs.append(preview_spec)
	return preview_specs

static func pick_remote_cluster_from_payloads(
		preview_specs: Array,
		marker_payload: Dictionary,
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		canvas_position: Vector2,
		canvas_scale: float = 1.0,
		active_sector_session = null) -> Dictionary:
	var preview_hit: Dictionary = _pick_remote_cluster_from_preview_specs(
		preview_specs,
		galaxy_state,
		active_cluster_session,
		canvas_position,
		canvas_scale,
		active_sector_session
	)
	if not preview_hit.is_empty():
		return preview_hit
	return _pick_remote_cluster_from_marker_payload(
		marker_payload,
		galaxy_state,
		active_cluster_session,
		canvas_position,
		canvas_scale,
		active_sector_session
	)

static func _pick_remote_cluster_from_preview_specs(
		preview_specs: Array,
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		canvas_position: Vector2,
		canvas_scale: float,
		active_sector_session = null) -> Dictionary:
	var reference_session = active_sector_session if active_sector_session != null else active_cluster_session
	if galaxy_state == null or reference_session == null:
		return {}
	var safe_canvas_scale: float = maxf(canvas_scale, 0.001)
	var best_spec: Dictionary = {}
	var best_distance_sq: float = INF
	for preview_spec in preview_specs:
		var cluster_id: int = int(preview_spec.get("cluster_id", -1))
		if cluster_id < 0 or (active_cluster_session != null and cluster_id == active_cluster_session.cluster_id):
			continue
		var body_type: int = int(preview_spec.get("body_type", SimBody.BodyType.ASTEROID))
		var body_radius: float = float(preview_spec.get("radius", 1.0))
		var preview_position: Vector2 = BodyRenderer.sim_to_screen(
			Vector2(preview_spec.get("local_position", Vector2.ZERO))
		)
		var preview_radius: float = maxf(
			BodyRenderer.screen_radius_for_body_traits(body_type, body_radius),
			10.0 / safe_canvas_scale
		)
		var distance_sq: float = preview_position.distance_squared_to(canvas_position)
		if distance_sq > preview_radius * preview_radius or distance_sq >= best_distance_sq:
			continue
		best_distance_sq = distance_sq
		best_spec = preview_spec
	if best_spec.is_empty():
		return {}
	return _remote_cluster_pick_result(
		galaxy_state,
		active_cluster_session,
		int(best_spec.get("cluster_id", -1)),
		canvas_position,
		active_sector_session
	)

static func _pick_remote_cluster_from_marker_payload(
		marker_payload: Dictionary,
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		canvas_position: Vector2,
		canvas_scale: float,
		active_sector_session = null) -> Dictionary:
	var reference_session = active_sector_session if active_sector_session != null else active_cluster_session
	if galaxy_state == null or reference_session == null:
		return {}
	var safe_canvas_scale: float = maxf(canvas_scale, 0.001)
	var best_marker: Dictionary = {}
	var best_distance_sq: float = INF
	for marker in marker_payload.get("markers", []):
		if bool(marker.get("is_active", false)):
			continue
		var marker_position: Vector2 = BodyRenderer.sim_to_screen(
			Vector2(marker.get("local_center", Vector2.ZERO))
		)
		var marker_radius_world: float = cluster_debug_marker_world_radius(
			float(marker.get("radius", 0.0)),
			safe_canvas_scale,
			false
		)
		var marker_radius: float = maxf(
			BodyRenderer.sim_dist_to_screen(marker_radius_world),
			12.0 / safe_canvas_scale
		)
		var distance_sq: float = marker_position.distance_squared_to(canvas_position)
		if distance_sq > marker_radius * marker_radius or distance_sq >= best_distance_sq:
			continue
		best_distance_sq = distance_sq
		best_marker = marker
	if best_marker.is_empty():
		return {}
	return _remote_cluster_pick_result(
		galaxy_state,
		active_cluster_session,
		int(best_marker.get("cluster_id", -1)),
		canvas_position,
		active_sector_session
	)

static func _remote_cluster_pick_result(
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		cluster_id: int,
		canvas_position: Vector2 = Vector2.ZERO,
		active_sector_session = null) -> Dictionary:
	var reference_session = active_sector_session if active_sector_session != null else active_cluster_session
	if galaxy_state == null or reference_session == null or cluster_id < 0:
		return {}
	var cluster_state: ClusterState = galaxy_state.get_cluster(cluster_id)
	if cluster_state == null or (active_cluster_session != null and cluster_id == active_cluster_session.cluster_id):
		return {}
	var clicked_local_focus_position: Vector2 = canvas_position / max(SimConstants.SIM_TO_SCREEN, 0.001)
	return {
		"cluster_id": cluster_id,
		"global_center": cluster_state.global_center,
		"clicked_global_focus_position": reference_session.to_global(clicked_local_focus_position),
		"local_center": reference_session.to_local(cluster_state.global_center),
		"authoritative_radius": cluster_state.get_authoritative_radius(),
		"state": activation_state_debug_name(cluster_state.activation_state),
	}

static func _remote_cluster_preview_source_specs(
		cluster_state: ClusterState,
		preview_lod: int = PREVIEW_LOD_FULL,
		macro_sector_zone: int = MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE) -> Array:
	var preview_specs: Array = []
	if cluster_state == null:
		return preview_specs
	var use_runtime_snapshot: bool = cluster_state.activation_state == ClusterActivationState.State.SIMPLIFIED \
		and bool(cluster_state.simulation_profile.get("has_runtime_snapshot", false))
	if use_runtime_snapshot:
		for object_state in cluster_state.object_registry.values():
			if object_state == null or object_state.residency_state == ObjectResidencyState.State.IN_TRANSIT:
				continue
			var body_type: int = int(object_state.descriptor.get("body_type", -1))
			if body_type not in [
				SimBody.BodyType.BLACK_HOLE,
				SimBody.BodyType.STAR,
				SimBody.BodyType.PLANET,
			]:
				continue
			if not _preview_body_type_allowed_in_lod(body_type, preview_lod, macro_sector_zone):
				continue
			preview_specs.append(_make_preview_source_spec(
				object_state.object_id,
				object_state.kind,
				body_type,
				int(object_state.descriptor.get("material_type", SimBody.MaterialType.MIXED)),
				object_state.local_position,
				float(object_state.descriptor.get("radius", 1.0)),
				int(object_state.seed)
			))
		# step_simplified_cluster() sets has_runtime_snapshot=true after the first BH-only
		# style remote step, before the cluster has ever been ACTIVE. In that case the
		# registry may only hold BHs; supplement from blueprint data so remote zones can
		# still show the content allowed by their current preview policy.
		var registry_has_stars_or_planets: bool = false
		for spec in preview_specs:
			if int(spec.get("body_type", -1)) != SimBody.BodyType.BLACK_HOLE:
				registry_has_stars_or_planets = true
				break
		if not registry_has_stars_or_planets:
			for source_spec in cluster_state.cluster_blueprint.get("preview_object_specs", []):
				var bt: int = int(source_spec.get("body_type", -1))
				if bt == SimBody.BodyType.BLACK_HOLE:
					continue  # BH already present from registry with live positions
				if bt not in [SimBody.BodyType.STAR, SimBody.BodyType.PLANET]:
					continue
				if not _preview_body_type_allowed_in_lod(bt, preview_lod, macro_sector_zone):
					continue
				preview_specs.append(_copy_preview_source_spec(source_spec))
		return preview_specs
	for source_spec in cluster_state.cluster_blueprint.get("preview_object_specs", []):
		var body_type: int = int(source_spec.get("body_type", -1))
		if body_type not in [
			SimBody.BodyType.BLACK_HOLE,
			SimBody.BodyType.STAR,
			SimBody.BodyType.PLANET,
		]:
			continue
		if not _preview_body_type_allowed_in_lod(body_type, preview_lod, macro_sector_zone):
			continue
		preview_specs.append(_copy_preview_source_spec(source_spec))
	return preview_specs

static func cluster_preview_lod_for_screen_radius(cluster_screen_radius: float) -> int:
	if cluster_screen_radius < PREVIEW_LOD_BH_AND_STARS_MAX_SCREEN_RADIUS:
		return PREVIEW_LOD_MARKER_ONLY
	if cluster_screen_radius < PREVIEW_LOD_FULL_MIN_SCREEN_RADIUS:
		return PREVIEW_LOD_BH_AND_STARS
	return PREVIEW_LOD_FULL

static func _preview_body_type_allowed_in_lod(
		body_type: int,
		preview_lod: int,
		macro_sector_zone: int = MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE) -> bool:
	if body_type == SimBody.BodyType.BLACK_HOLE:
		return true
	if macro_sector_zone == MACRO_SECTOR_ZONE_SCRIPT.Zone.FAR:
		return preview_lod in [PREVIEW_LOD_BH_AND_STARS, PREVIEW_LOD_FULL] \
			and body_type == SimBody.BodyType.STAR
	if preview_lod == PREVIEW_LOD_FULL:
		return body_type in [SimBody.BodyType.STAR, SimBody.BodyType.PLANET]
	if preview_lod == PREVIEW_LOD_BH_AND_STARS:
		return body_type == SimBody.BodyType.STAR
	return false

static func _resolve_macro_sector_zone(
		active_macro_sector_session,
		cluster_id: int) -> int:
	if active_macro_sector_session == null:
		return MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE
	return active_macro_sector_session.zone_for_cluster(cluster_id)

static func _copy_preview_source_spec(source_spec: Dictionary) -> Dictionary:
	return _make_preview_source_spec(
		str(source_spec.get("object_id", "")),
		str(source_spec.get("kind", "")),
		int(source_spec.get("body_type", SimBody.BodyType.ASTEROID)),
		int(source_spec.get("material_type", SimBody.MaterialType.MIXED)),
		Vector2(source_spec.get("local_position", Vector2.ZERO)),
		float(source_spec.get("radius", 1.0)),
		int(source_spec.get("seed", 0))
	)

static func _make_preview_source_spec(
		object_id: String,
		kind: String,
		body_type: int,
		material_type: int,
		local_position: Vector2,
		radius: float,
		seed: int) -> Dictionary:
	return {
		"object_id": object_id,
		"kind": kind,
		"body_type": body_type,
		"material_type": material_type,
		"local_position": local_position,
		"radius": radius,
		"seed": seed,
	}

static func _is_cluster_visible_in_canvas_rect(
		local_center: Vector2,
		radius: float,
		visible_canvas_rect: Rect2,
		extra_margin: float = 0.0) -> bool:
	if not visible_canvas_rect.has_area():
		return true
	var extent: float = maxf(radius, 0.0) + maxf(extra_margin, 0.0)
	var cluster_rect := Rect2(
		local_center - Vector2.ONE * extent,
		Vector2.ONE * extent * 2.0
	)
	return visible_canvas_rect.intersects(cluster_rect)

static func _cluster_canvas_radius_to_screen_radius(
		cluster_canvas_radius: float,
		visible_canvas_rect: Rect2,
		viewport_size: Vector2) -> float:
	if cluster_canvas_radius <= 0.0:
		return 0.0
	if not visible_canvas_rect.has_area() or viewport_size == Vector2.ZERO:
		return cluster_canvas_radius
	var px_per_canvas_x: float = viewport_size.x / maxf(visible_canvas_rect.size.x, 0.001)
	var px_per_canvas_y: float = viewport_size.y / maxf(visible_canvas_rect.size.y, 0.001)
	return cluster_canvas_radius * maxf(px_per_canvas_x, px_per_canvas_y)

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

static func active_world_layer_local_offset(
		active_sector_session = null,
		active_cluster_session: ActiveClusterSession = null) -> Vector2:
	if active_sector_session != null and active_sector_session.has_method("cluster_frame_offset"):
		return Vector2(active_sector_session.cluster_frame_offset())
	if active_cluster_session != null:
		return Vector2.ZERO
	return Vector2.ZERO

static func uses_macro_sector_debug_overlay(active_macro_sector_session) -> bool:
	return active_macro_sector_session != null and active_macro_sector_session.descriptor != null

static func sector_relation_name(sector_coord: Vector2i, active_sector_coord: Vector2i) -> String:
	var sector_distance: int = maxi(
		absi(sector_coord.x - active_sector_coord.x),
		absi(sector_coord.y - active_sector_coord.y)
	)
	if sector_distance <= 0:
		return "active"
	if sector_distance == 1:
		return "neighbor"
	if sector_distance == 2:
		return "far"
	return "remote"

static func sector_relation_short_label(sector_relation: String) -> String:
	match sector_relation:
		"active":
			return "LIVE"
		"neighbor":
			return "NEAR"
		"far":
			return "FAR"
		_:
			return "REMOTE"

static func sector_content_relevance_name(sector_relation: String, is_active: bool = false) -> String:
	if is_active:
		return "active"
	match sector_relation:
		"active":
			return "local"
		"neighbor":
			return "neighbor"
		"far":
			return "far"
		_:
			return "remote"

static func sector_content_relevance_label(sector_relevance: String) -> String:
	match sector_relevance:
		"active":
			return "ACTIVE"
		"local":
			return "LOCAL"
		"neighbor":
			return "NEAR"
		"far":
			return "FAR"
		_:
			return "REMOTE"

static func sector_relevance_from_macro_zone(zone: int, is_active: bool = false) -> String:
	if is_active:
		return "active"
	match zone:
		MACRO_SECTOR_ZONE_SCRIPT.Zone.FOCUS:
			return "local"
		MACRO_SECTOR_ZONE_SCRIPT.Zone.AMBIENT:
			return "neighbor"
		MACRO_SECTOR_ZONE_SCRIPT.Zone.FAR:
			return "far"
		_:
			return "remote"

static func sector_visual_profile(
		sector_relation: String,
		contains_systems: bool,
		debug_visible: bool = false) -> Dictionary:
	var profile := {
		"fill_color": Color(0.08, 0.11, 0.16, 0.040),
		"border_color": Color(0.34, 0.44, 0.58, 0.14),
		"border_width": 1.0,
		"corner_color": Color(0.58, 0.69, 0.86, 0.18),
		"corner_width": 1.0,
		"quiet_color": Color(0.64, 0.73, 0.86, 0.10),
		"quiet_width": 1.0,
		"content_hint_color": Color(0.93, 0.82, 0.56, 0.18),
		"label_color": Color(0.84, 0.90, 0.98, 0.0),
	}
	match sector_relation:
		"active":
			profile["fill_color"] = Color(0.10, 0.18, 0.28, 0.14 if contains_systems else 0.10)
			profile["border_color"] = Color(0.72, 0.86, 1.0, 0.40)
			profile["border_width"] = 1.8
			profile["corner_color"] = Color(0.86, 0.95, 1.0, 0.56)
			profile["corner_width"] = 1.8
			profile["quiet_color"] = Color(0.72, 0.83, 0.96, 0.14)
			profile["content_hint_color"] = Color(1.0, 0.88, 0.62, 0.42)
			profile["label_color"] = Color(0.94, 0.98, 1.0, 0.90 if debug_visible else 0.0)
		"neighbor":
			profile["fill_color"] = Color(0.08, 0.13, 0.20, 0.080 if contains_systems else 0.055)
			profile["border_color"] = Color(0.52, 0.68, 0.90, 0.24)
			profile["border_width"] = 1.25
			profile["corner_color"] = Color(0.74, 0.88, 1.0, 0.28)
			profile["quiet_color"] = Color(0.66, 0.76, 0.90, 0.12)
			profile["content_hint_color"] = Color(0.84, 0.90, 1.0, 0.24)
			profile["label_color"] = Color(0.84, 0.92, 1.0, 0.72 if debug_visible else 0.0)
		"far":
			profile["fill_color"] = Color(0.06, 0.10, 0.16, 0.050 if contains_systems else 0.034)
			profile["border_color"] = Color(0.40, 0.54, 0.72, 0.16)
			profile["corner_color"] = Color(0.60, 0.74, 0.92, 0.18)
			profile["quiet_color"] = Color(0.62, 0.72, 0.86, 0.10)
			profile["content_hint_color"] = Color(0.76, 0.86, 0.98, 0.16)
			profile["label_color"] = Color(0.76, 0.86, 0.98, 0.52 if debug_visible else 0.0)
		_:
			profile["fill_color"] = Color(0.05, 0.08, 0.12, 0.028 if contains_systems else 0.020)
			profile["border_color"] = Color(0.28, 0.36, 0.48, 0.10)
			profile["corner_color"] = Color(0.48, 0.58, 0.72, 0.12)
			profile["quiet_color"] = Color(0.58, 0.66, 0.78, 0.08)
			profile["content_hint_color"] = Color(0.70, 0.78, 0.88, 0.12)
			profile["label_color"] = Color(0.72, 0.78, 0.88, 0.40 if debug_visible else 0.0)
	if debug_visible:
		var fill_color: Color = profile["fill_color"]
		profile["fill_color"] = Color(fill_color.r, fill_color.g, fill_color.b, minf(fill_color.a + 0.015, 0.22))
	return profile

static func sector_marker_debug_profile(
		sector_relation: String,
		is_active: bool = false,
		sector_cluster_count: int = 1) -> Dictionary:
	var has_multiple_systems: bool = sector_cluster_count > 1
	var profile := {
		"marker_color": Color(0.72, 0.78, 0.86, 0.56),
		"marker_fill_alpha": 0.08,
		"show_extent_ring": false,
	}
	match sector_relation:
		"active":
			profile["marker_color"] = Color(1.0, 0.86, 0.54, 0.92 if is_active else 0.72)
			profile["marker_fill_alpha"] = 0.20 if is_active else 0.13
		"neighbor":
			profile["marker_color"] = Color(0.56, 0.90, 0.84, 0.74 if is_active else 0.62)
			profile["marker_fill_alpha"] = 0.15 if is_active else 0.10
		"far":
			profile["marker_color"] = Color(0.62, 0.78, 0.98, 0.54 if is_active else 0.44)
			profile["marker_fill_alpha"] = 0.10 if is_active else 0.07
		_:
			profile["marker_color"] = Color(0.72, 0.76, 0.84, 0.40 if is_active else 0.32)
			profile["marker_fill_alpha"] = 0.08 if is_active else 0.05
	if has_multiple_systems:
		var marker_color: Color = profile["marker_color"]
		profile["marker_color"] = Color(marker_color.r, marker_color.g, marker_color.b, minf(marker_color.a + 0.08, 1.0))
	return profile

static func _resolve_cluster_sector_coord(galaxy_state: GalaxyState, cluster_state: ClusterState) -> Vector2i:
	if cluster_state == null:
		return Vector2i.ZERO
	var sector_coord_variant = cluster_state.simulation_profile.get("sector_coord", null)
	if sector_coord_variant is Vector2i:
		return sector_coord_variant
	return galaxy_state.find_sector_for_global_position(cluster_state.global_center) if galaxy_state != null else Vector2i.ZERO

static func macro_sector_zone_label(zone: int) -> String:
	return MACRO_SECTOR_ZONE_SCRIPT.debug_name(zone).to_upper()

static func macro_sector_zone_debug_profile(zone: int, is_active: bool = false) -> Dictionary:
	var profile := {
		"marker_color": Color(0.72, 0.76, 0.84, 0.34),
		"overlay_fill_alpha": 0.020,
		"overlay_ring_alpha": 0.10,
		"overlay_ring_width": 0.9,
		"link_alpha": 0.0,
		"link_width": 0.0,
	}
	match zone:
		MACRO_SECTOR_ZONE_SCRIPT.Zone.FOCUS:
			profile["marker_color"] = Color(1.0, 0.88, 0.34, 0.94)
			profile["overlay_fill_alpha"] = 0.11
			profile["overlay_ring_alpha"] = 0.54
			profile["overlay_ring_width"] = 2.2
		MACRO_SECTOR_ZONE_SCRIPT.Zone.AMBIENT:
			profile["marker_color"] = Color(0.34, 0.94, 0.82, 0.80)
			profile["overlay_fill_alpha"] = 0.075
			profile["overlay_ring_alpha"] = 0.34
			profile["overlay_ring_width"] = 1.7
			profile["link_alpha"] = 0.34
			profile["link_width"] = 2.2
		MACRO_SECTOR_ZONE_SCRIPT.Zone.FAR:
			profile["marker_color"] = Color(0.58, 0.78, 1.0, 0.62)
			profile["overlay_fill_alpha"] = 0.045
			profile["overlay_ring_alpha"] = 0.22
			profile["overlay_ring_width"] = 1.1
			profile["link_alpha"] = 0.18
			profile["link_width"] = 1.2
	if is_active and zone != MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE:
		var marker_color: Color = profile["marker_color"]
		profile["marker_color"] = Color(marker_color.r, marker_color.g, marker_color.b, minf(marker_color.a + 0.08, 1.0))
	return profile

static func should_draw_cluster_extent_ring(cluster_screen_radius: float, viewport_diagonal: float) -> bool:
	if cluster_screen_radius < 0.5:
		return false
	if viewport_diagonal <= 0.0:
		return true
	return cluster_screen_radius <= viewport_diagonal * 1.5

static func activation_state_debug_name(activation_state: int) -> String:
	match activation_state:
		ClusterActivationState.State.ACTIVE:
			return "active"
		ClusterActivationState.State.SIMPLIFIED:
			return "simplified"
		_:
			return "unloaded"

static func cluster_debug_color(activation_state: int) -> Color:
	match activation_state:
		ClusterActivationState.State.ACTIVE:
			return Color(0.98, 0.90, 0.34, 0.82)
		ClusterActivationState.State.SIMPLIFIED:
			return Color(0.36, 0.92, 0.86, 0.60)
		_:
			return Color(0.86, 0.89, 0.98, 0.44)
