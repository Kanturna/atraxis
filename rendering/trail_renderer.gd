## trail_renderer.gd
## Draws orbit trails for bodies.
##
## Strategy:
##   - Star + Planets (Level A): AntialiasedLine2D nodes — smooth, anti-aliased.
##   - Asteroids + Fragments (Level B/C): single _draw() pass — efficient for many bodies.
##
## The two approaches are mixed: AntialiasedLine2D nodes live as children;
## the _draw() call handles the rest in one batched canvas operation.
class_name TrailRenderer
extends Node2D

const MAX_TRAIL_POINTS_A: int = 300   # ~5 seconds at 60fps for key bodies
const MAX_TRAIL_POINTS_BC: int = 90   # ~1.5 seconds for minor bodies

## trail data for _draw() bodies (Level B/C)
## body_id → PackedVector2Array of screen positions
var _trails_bc: Dictionary = {}
var _colors_bc: Dictionary = {}

## AntialiasedLine2D nodes for Level A bodies
## body_id → AntialiasedLine2D
var _lines_a: Dictionary = {}
var _trails_a: Dictionary = {}  # body_id → PackedVector2Array (screen pos)

func add_trail(body: SimBody) -> void:
	if body.influence_level == SimBody.InfluenceLevel.A and \
			body.body_type != SimBody.BodyType.STAR:
		# Planets get AntialiasedLine2D nodes
		var line := AntialiasedLine2D.new()
		line.width = 1.5
		line.default_color = _trail_color(body)
		add_child(line)
		_lines_a[body.id] = line
		_trails_a[body.id] = PackedVector2Array()
	elif body.body_type != SimBody.BodyType.STAR:
		# Asteroids and fragments use _draw()
		_trails_bc[body.id] = PackedVector2Array()
		_colors_bc[body.id] = _trail_color(body)

func remove_trail(body_id: int) -> void:
	if _lines_a.has(body_id):
		_lines_a[body_id].queue_free()
		_lines_a.erase(body_id)
		_trails_a.erase(body_id)
	_trails_bc.erase(body_id)
	_colors_bc.erase(body_id)

func update_all(bodies: Array) -> void:
	for body in bodies:
		if not body.active:
			continue
		var screen_pos: Vector2 = BodyRenderer.sim_to_screen(body.position)

		if _lines_a.has(body.id):
			var trail: PackedVector2Array = _trails_a[body.id]
			trail.append(screen_pos)
			if trail.size() > MAX_TRAIL_POINTS_A:
				trail.remove_at(0)
			_trails_a[body.id] = trail
			_lines_a[body.id].points = trail

		elif _trails_bc.has(body.id):
			var trail: PackedVector2Array = _trails_bc[body.id]
			trail.append(screen_pos)
			if trail.size() > MAX_TRAIL_POINTS_BC:
				trail.remove_at(0)
			_trails_bc[body.id] = trail

	queue_redraw()

func _draw() -> void:
	# Draw all B/C trails in one batched pass
	for body_id in _trails_bc.keys():
		var trail: PackedVector2Array = _trails_bc[body_id]
		if trail.size() < 2:
			continue
		var base_color: Color = _colors_bc[body_id]
		var count: int = trail.size()
		for i in range(1, count):
			var alpha: float = float(i) / float(count) * 0.5
			draw_line(trail[i - 1], trail[i],
					Color(base_color.r, base_color.g, base_color.b, alpha), 1.0)

static func _trail_color(body: SimBody) -> Color:
	match body.body_type:
		SimBody.BodyType.PLANET:
			match body.material_type:
				SimBody.MaterialType.ROCKY: return Color(0.62, 0.47, 0.33, 0.6)
				SimBody.MaterialType.ICY:   return Color(0.72, 0.88, 1.0, 0.6)
				_:                          return Color(0.6, 0.6, 0.7, 0.6)
		SimBody.BodyType.ASTEROID: return Color(0.5, 0.48, 0.44, 0.5)
		SimBody.BodyType.FRAGMENT: return Color(0.7, 0.6, 0.5, 0.4)
		_: return Color(0.6, 0.6, 0.6, 0.4)
