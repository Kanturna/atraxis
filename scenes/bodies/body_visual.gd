## body_visual.gd
## Unit-circle visual for a SimBody.
## The parent (BodyRenderer) sets position, modulate and scale.
## Scale = radius in pixels, so we draw a unit circle (radius 1.0).
extends Node2D

func _draw() -> void:
	draw_circle(Vector2.ZERO, 1.0, Color.WHITE)  # modulate tints this
