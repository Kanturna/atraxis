## Draws dimmed read-only previews for non-active remote clusters.
class_name ClusterPreviewRenderer
extends Node2D

var _preview_specs: Array = []

func update_preview_specs(preview_specs: Array) -> void:
	_preview_specs = preview_specs
	queue_redraw()

func _draw() -> void:
	for spec in _preview_specs:
		var body_type: int = int(spec.get("body_type", SimBody.BodyType.ASTEROID))
		var body_radius: float = float(spec.get("radius", 1.0))
		var screen_position: Vector2 = BodyRenderer.sim_to_screen(
			Vector2(spec.get("local_position", Vector2.ZERO))
		)
		var screen_radius: float = BodyRenderer.screen_radius_for_body_traits(body_type, body_radius)
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
			return Color(0.88, 0.94, 1.0, 0.26)
		SimBody.BodyType.STAR:
			return Color(1.0, 0.92, 0.50, 0.28)
		SimBody.BodyType.PLANET:
			match material_type:
				SimBody.MaterialType.ROCKY:
					return Color(0.72, 0.58, 0.44, 0.24)
				SimBody.MaterialType.ICY:
					return Color(0.74, 0.90, 1.0, 0.24)
				SimBody.MaterialType.METALLIC:
					return Color(0.72, 0.76, 0.82, 0.24)
				_:
					return Color(0.68, 0.68, 0.78, 0.24)
		_:
			return Color(0.70, 0.72, 0.78, 0.18)
