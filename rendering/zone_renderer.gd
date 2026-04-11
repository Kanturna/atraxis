## zone_renderer.gd
## Draws zone boundary rings using AntialiasedLine2D for smooth arcs.
## Zones are static in Phase 1 (computed once from star properties).
class_name ZoneRenderer
extends Node2D

var _zones: WorldBuilder.ZoneBoundaries = null

func setup(zones: WorldBuilder.ZoneBoundaries) -> void:
	_zones = zones
	_rebuild_lines()

func _rebuild_lines() -> void:
	# Remove any existing children
	for child in get_children():
		child.queue_free()

	if _zones == null:
		return

	# Build arc point arrays for each zone boundary
	_add_ring(_zones.inner_max,  Color(1.0, 0.35, 0.1,  0.25))
	_add_ring(_zones.middle_min, Color(0.3, 0.9,  0.3,  0.2))
	_add_ring(_zones.middle_max, Color(0.3, 0.9,  0.3,  0.2))
	_add_ring(_zones.outer_min,  Color(0.3, 0.55, 1.0,  0.2))

func _add_ring(sim_radius: float, color: Color) -> void:
	var screen_r: float = BodyRenderer.sim_dist_to_screen(sim_radius)
	if screen_r < 1.0:
		return
	var segments: int = 128
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var angle: float = float(i) / float(segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * screen_r)

	var line := AntialiasedLine2D.new()
	line.width = 1.0
	line.default_color = color
	line.points = points
	add_child(line)
