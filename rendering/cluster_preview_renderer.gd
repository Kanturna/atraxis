## Draws dimmed read-only previews for non-active remote clusters.
class_name ClusterPreviewRenderer
extends Node2D

var _preview_specs: Array = []
var _canvas_scale: float = 1.0
var _visible_canvas_rect: Rect2 = Rect2()

## Minimum on-screen pixel sizes for preview bodies (matches marker-renderer convention).
const MIN_PREVIEW_SCREEN_PX_STAR: float = 4.0
const MIN_PREVIEW_SCREEN_PX_BH: float = 3.5
const MIN_PREVIEW_SCREEN_PX_PLANET: float = 2.5

func update_preview_specs(
		preview_specs: Array,
		canvas_scale: float = 1.0,
		visible_canvas_rect: Rect2 = Rect2()) -> void:
	_preview_specs = preview_specs
	_canvas_scale = maxf(canvas_scale, 0.001)
	_visible_canvas_rect = visible_canvas_rect
	queue_redraw()

func _draw() -> void:
	for spec in _preview_specs:
		var body_type: int = int(spec.get("body_type", SimBody.BodyType.ASTEROID))
		var body_radius: float = float(spec.get("radius", 1.0))
		var screen_position: Vector2 = BodyRenderer.sim_to_screen(
			Vector2(spec.get("local_position", Vector2.ZERO))
		)
		var min_px: float = _min_preview_screen_px(body_type) / _canvas_scale
		var screen_radius: float = maxf(
			BodyRenderer.screen_radius_for_body_traits(body_type, body_radius),
			min_px
		)
		if not _is_preview_body_visible(screen_position, screen_radius):
			continue
		var color: Color = _preview_color(spec)
		match body_type:
			SimBody.BodyType.BLACK_HOLE:
				_draw_black_hole_preview(screen_position, screen_radius, color)
			SimBody.BodyType.STAR:
				draw_circle(screen_position, screen_radius, color)
				draw_arc(
					screen_position,
					screen_radius * 1.12,
					0.0,
					TAU,
					48,
					Color(color.r, color.g, color.b, minf(color.a + 0.08, 0.5)),
					1.5
				)
			_:
				draw_circle(screen_position, screen_radius, color)

func _draw_black_hole_preview(screen_position: Vector2, screen_radius: float, color: Color) -> void:
	draw_circle(
		screen_position,
		screen_radius * 1.24,
		Color(color.r, color.g, color.b, color.a * 0.28)
	)
	draw_circle(screen_position, screen_radius, Color(0.90, 0.95, 1.0, 0.24))
	draw_circle(screen_position, screen_radius * 0.56, Color(0.04, 0.04, 0.08, 0.84))
	draw_arc(
		screen_position,
		screen_radius * 1.06,
		0.0,
		TAU,
		48,
		Color(0.92, 0.96, 1.0, 0.26),
		1.4
	)

func _preview_color(spec: Dictionary) -> Color:
	var body_type: int = int(spec.get("body_type", SimBody.BodyType.ASTEROID))
	var material_type: int = int(spec.get("material_type", SimBody.MaterialType.MIXED))
	match body_type:
		SimBody.BodyType.BLACK_HOLE:
			return Color(0.88, 0.94, 1.0, 0.50)
		SimBody.BodyType.STAR:
			return Color(1.0, 0.92, 0.50, 0.60)
		SimBody.BodyType.PLANET:
			match material_type:
				SimBody.MaterialType.ROCKY:
					return Color(0.72, 0.58, 0.44, 0.45)
				SimBody.MaterialType.ICY:
					return Color(0.74, 0.90, 1.0, 0.45)
				SimBody.MaterialType.METALLIC:
					return Color(0.72, 0.76, 0.82, 0.45)
				_:
					return Color(0.68, 0.68, 0.78, 0.45)
		_:
			return Color(0.70, 0.72, 0.78, 0.35)

static func _min_preview_screen_px(body_type: int) -> float:
	match body_type:
		SimBody.BodyType.STAR:
			return MIN_PREVIEW_SCREEN_PX_STAR
		SimBody.BodyType.BLACK_HOLE:
			return MIN_PREVIEW_SCREEN_PX_BH
		_:
			return MIN_PREVIEW_SCREEN_PX_PLANET

func _is_preview_body_visible(screen_position: Vector2, screen_radius: float) -> bool:
	if not _visible_canvas_rect.has_area():
		return true
	var extent: float = screen_radius + (12.0 / _canvas_scale)
	var preview_rect := Rect2(
		screen_position - Vector2.ONE * extent,
		Vector2.ONE * extent * 2.0
	)
	return _visible_canvas_rect.intersects(preview_rect)
