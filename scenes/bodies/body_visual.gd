## body_visual.gd
## Unit-circle visual for a SimBody.
## The parent (BodyRenderer) sets position, modulate and scale.
## Scale = radius in pixels, so we draw a unit circle (radius 1.0).
extends Node2D

@export var visual_body_type: int = SimBody.BodyType.ASTEROID:
	set(value):
		visual_body_type = value
		queue_redraw()

func _draw() -> void:
	if visual_body_type == SimBody.BodyType.BLACK_HOLE:
		_draw_black_hole()
		return
	draw_circle(Vector2.ZERO, 1.0, Color.WHITE)  # modulate tints this

func _draw_black_hole() -> void:
	draw_circle(Vector2.ZERO, 1.35, Color(1.0, 1.0, 1.0, 0.14))
	draw_circle(Vector2.ZERO, 1.0, Color(0.98, 0.99, 1.0, 0.92))
	draw_circle(Vector2.ZERO, 0.56, Color(0.04, 0.04, 0.08, 1.0))
	draw_arc(Vector2.ZERO, 1.08, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.45), 0.10)
