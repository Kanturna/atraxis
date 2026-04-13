## Draws anti-aliased debug markers for registered clusters.
class_name ClusterMarkerRenderer
extends Node2D

var _marker_payload: Dictionary = {}
var _canvas_scale: float = 1.0
var _visible_canvas_rect: Rect2 = Rect2()
var _extent_lines: Array[AntialiasedLine2D] = []
var _marker_rings: Array[AntialiasedLine2D] = []
var _cross_horizontal: Array[AntialiasedLine2D] = []
var _cross_vertical: Array[AntialiasedLine2D] = []
var _unit_circle_template_cache: Dictionary = {}

func update_marker_payload(
		marker_payload: Dictionary,
		canvas_scale: float,
		visible_canvas_rect: Rect2 = Rect2()) -> void:
	_marker_payload = marker_payload
	_canvas_scale = maxf(canvas_scale, 0.001)
	_visible_canvas_rect = visible_canvas_rect
	var markers: Array = _marker_payload.get("markers", [])
	_sync_line_counts(markers.size())
	var viewport_diagonal: float = get_viewport().get_visible_rect().size.length()
	for index in range(markers.size()):
		var marker: Dictionary = markers[index]
		var center: Vector2 = BodyRenderer.snap_screen_point(
			BodyRenderer.sim_to_screen(Vector2(marker.get("local_center", Vector2.ZERO)))
		)
		var cluster_radius_screen: float = BodyRenderer.sim_dist_to_screen(float(marker.get("radius", 0.0)))
		var is_active: bool = bool(marker.get("is_active", false))
		var cluster_color: Color = Color(marker.get("color", Color.WHITE))
		var marker_radius_world: float = WorldRenderer.cluster_debug_marker_world_radius(
			float(marker.get("radius", 0.0)),
			_canvas_scale,
			is_active
		)
		var marker_radius_screen: float = BodyRenderer.sim_dist_to_screen(marker_radius_world)
		var cross_half_extent: float = marker_radius_screen * 0.75
		var extent_width: float = _screen_line_width(2.6 if is_active else 1.5)
		var marker_width: float = _screen_line_width(2.0 if is_active else 1.2)
		var cross_width: float = _screen_line_width(2.0 if is_active else 1.4)
		var marker_visible: bool = _is_marker_visible(
			center,
			cluster_radius_screen,
			marker_radius_screen
		)

		_configure_circle_line(
			_extent_lines[index],
			center,
			cluster_radius_screen,
			cluster_color,
			extent_width,
			marker_visible and WorldRenderer.should_draw_cluster_extent_ring(cluster_radius_screen, viewport_diagonal)
		)
		_configure_circle_line(
			_marker_rings[index],
			center,
			marker_radius_screen,
			cluster_color,
			marker_width,
			marker_visible
		)
		_configure_segment_line(
			_cross_horizontal[index],
			center + Vector2(-cross_half_extent, 0.0),
			center + Vector2(cross_half_extent, 0.0),
			cluster_color,
			cross_width,
			marker_visible
		)
		_configure_segment_line(
			_cross_vertical[index],
			center + Vector2(0.0, -cross_half_extent),
			center + Vector2(0.0, cross_half_extent),
			cluster_color,
			cross_width,
			marker_visible
		)
	queue_redraw()

func _draw() -> void:
	var markers: Array = _marker_payload.get("markers", [])
	if ThemeDB.fallback_font == null:
		return
	for marker in markers:
		var center: Vector2 = BodyRenderer.snap_screen_point(
			BodyRenderer.sim_to_screen(Vector2(marker.get("local_center", Vector2.ZERO)))
		)
		var is_active: bool = bool(marker.get("is_active", false))
		var cluster_color: Color = Color(marker.get("color", Color.WHITE))
		var marker_radius_world: float = WorldRenderer.cluster_debug_marker_world_radius(
			float(marker.get("radius", 0.0)),
			_canvas_scale,
			is_active
		)
		var marker_radius_screen: float = BodyRenderer.sim_dist_to_screen(marker_radius_world)
		if not _is_marker_visible(
			center,
			BodyRenderer.sim_dist_to_screen(float(marker.get("radius", 0.0))),
			marker_radius_screen
		):
			continue
		draw_circle(
			center,
			marker_radius_screen,
			Color(cluster_color.r, cluster_color.g, cluster_color.b, 0.16 if is_active else 0.11)
		)
		var label_text: String = str(marker.get("zone_label", ""))
		if label_text == "":
			label_text = str(marker.get("label_prefix", ""))
		if label_text == "":
			continue
		var label_position: Vector2 = center + Vector2(12.0 / _canvas_scale, -10.0 / _canvas_scale)
		draw_string(
			ThemeDB.fallback_font,
			label_position,
			"%s C%d" % [label_text, int(marker.get("cluster_id", -1))],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			ThemeDB.fallback_font_size,
			cluster_color
		)

func _sync_line_counts(target_count: int) -> void:
	while _extent_lines.size() < target_count:
		_extent_lines.append(_make_line())
		_marker_rings.append(_make_line())
		_cross_horizontal.append(_make_line())
		_cross_vertical.append(_make_line())
	while _extent_lines.size() > target_count:
		_extent_lines.pop_back().queue_free()
		_marker_rings.pop_back().queue_free()
		_cross_horizontal.pop_back().queue_free()
		_cross_vertical.pop_back().queue_free()

func _make_line() -> AntialiasedLine2D:
	var line := AntialiasedLine2D.new()
	add_child(line)
	return line

func _configure_circle_line(
		line: AntialiasedLine2D,
		center: Vector2,
		radius: float,
		color: Color,
		width: float,
		visible: bool) -> void:
	if line == null:
		return
	line.visible = visible and radius > 0.0
	if not line.visible:
		line.points = PackedVector2Array()
		return
	line.width = width
	line.default_color = color
	line.points = _circle_points(center, radius)

func _configure_segment_line(
		line: AntialiasedLine2D,
		from_point: Vector2,
		to_point: Vector2,
		color: Color,
		width: float,
		visible: bool) -> void:
	if line == null:
		return
	line.visible = visible
	if not visible:
		line.points = PackedVector2Array()
		return
	line.width = width
	line.default_color = color
	line.points = PackedVector2Array([from_point, to_point])

func _circle_points(center: Vector2, radius: float, segments: int = 96) -> PackedVector2Array:
	var template: PackedVector2Array = _unit_circle_template(segments)
	var points := PackedVector2Array()
	points.resize(template.size())
	for index in range(template.size()):
		points[index] = center + template[index] * radius
	return points

func _screen_line_width(base_width: float) -> float:
	return maxf(base_width / _canvas_scale, 1.5 / _canvas_scale)

func _unit_circle_template(segments: int) -> PackedVector2Array:
	var cached: PackedVector2Array = _unit_circle_template_cache.get(segments, PackedVector2Array())
	if not cached.is_empty():
		return cached
	var template := PackedVector2Array()
	for index in range(segments + 1):
		var angle: float = (float(index) / float(segments)) * TAU
		template.append(Vector2(cos(angle), sin(angle)))
	_unit_circle_template_cache[segments] = template
	return template

func _is_marker_visible(center: Vector2, cluster_radius_screen: float, marker_radius_screen: float) -> bool:
	if not _visible_canvas_rect.has_area():
		return true
	var extent: float = maxf(cluster_radius_screen, marker_radius_screen) + (24.0 / _canvas_scale)
	var marker_rect := Rect2(
		center - Vector2.ONE * extent,
		Vector2.ONE * extent * 2.0
	)
	return _visible_canvas_rect.intersects(marker_rect)
