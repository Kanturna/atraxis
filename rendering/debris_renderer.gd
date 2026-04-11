## debris_renderer.gd
## Draws debris fields as translucent circles in a single _draw() pass.
## MVP: purely visual, no physics interaction.
class_name DebrisRenderer
extends Node2D

## field_id → DebrisField reference (kept for redraw)
var _fields: Dictionary = {}

func update_all(debris_fields: Array) -> void:
	_fields.clear()
	for field in debris_fields:
		if field.active and field.total_mass > 0.0:
			_fields[field.id] = field
	queue_redraw()

func _draw() -> void:
	for field in _fields.values():
		var screen_pos: Vector2 = BodyRenderer.sim_to_screen(field.position)
		var screen_r: float = BodyRenderer.sim_dist_to_screen(field.radius)
		# Opacity scales with mass density (more mass = more visible)
		var density_factor: float = clamp(field.total_mass / 500.0, 0.05, 0.4)
		draw_circle(screen_pos, max(screen_r, 5.0), Color(0.65, 0.60, 0.52, density_factor))
