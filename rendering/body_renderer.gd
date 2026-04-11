## body_renderer.gd
## Manages one visual Node2D per SimBody.
## Reads simulation state each frame; never writes back to simulation.
class_name BodyRenderer
extends Node2D

## Maps body id → visual Node2D child
var _visuals: Dictionary = {}

const BODY_VISUAL_SCENE: String = "res://scenes/bodies/body_visual.tscn"
var _body_visual_packed: PackedScene = null

func _ready() -> void:
	_body_visual_packed = load(BODY_VISUAL_SCENE) as PackedScene

func add_body_visual(body: SimBody) -> void:
	if _body_visual_packed == null:
		return
	var node: Node2D = _body_visual_packed.instantiate()
	node.position = sim_to_screen(body.position)
	node.modulate = color_for_body(body)
	node.scale = Vector2.ONE * _screen_radius(body)
	add_child(node)
	_visuals[body.id] = node

func remove_body_visual(body_id: int) -> void:
	if _visuals.has(body_id):
		_visuals[body_id].queue_free()
		_visuals.erase(body_id)

func update_all(bodies: Array) -> void:
	for body in bodies:
		if not _visuals.has(body.id):
			continue
		var vis: Node2D = _visuals[body.id]
		if not body.active:
			vis.visible = false
			continue
		vis.visible = true
		vis.position = sim_to_screen(body.position)
		vis.modulate = color_for_body(body)
		vis.scale = Vector2.ONE * _screen_radius(body)

# -------------------------------------------------------------------------
# Coordinate transform — centralized here, used by all other renderers
# -------------------------------------------------------------------------

## Convert a simulation position (sim-units) to screen pixels.
## All renderers call this static-style method to ensure one consistent scale.
static func sim_to_screen(sim_pos: Vector2) -> Vector2:
	return sim_pos * SimConstants.SIM_TO_SCREEN

## Convert a sim-unit distance (e.g. a radius or zone boundary) to pixels.
static func sim_dist_to_screen(sim_dist: float) -> float:
	return sim_dist * SimConstants.SIM_TO_SCREEN

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

static func color_for_body(body: SimBody) -> Color:
	match body.body_type:
		SimBody.BodyType.STAR:
			return Color(1.0, 0.92, 0.4, 1.0)
		SimBody.BodyType.PLANET:
			match body.material_type:
				SimBody.MaterialType.ROCKY:   return Color(0.62, 0.47, 0.33, 1.0)
				SimBody.MaterialType.ICY:     return Color(0.72, 0.88, 1.0, 1.0)
				_:                            return Color(0.55, 0.55, 0.65, 1.0)
		SimBody.BodyType.ASTEROID:
			return Color(0.56, 0.53, 0.49, 1.0)
		SimBody.BodyType.FRAGMENT:
			return Color(0.72, 0.62, 0.50, 1.0)
		_:
			return Color.WHITE

static func _screen_radius(body: SimBody) -> float:
	# Body radius in sim-units → screen pixels, minimum 2px so tiny bodies stay visible
	return max(body.radius * SimConstants.SIM_TO_SCREEN, 2.0)
