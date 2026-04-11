## gravity_debug_renderer.gd
## Draws debug-only gravity threshold rings for active stars.
## These rings visualize practical acceleration thresholds, not hard cutoffs.
class_name GravityDebugRenderer
extends Node2D

const RING_SEGMENTS: int = 128
const DATA_SCRIPT := preload("res://rendering/gravity_debug_data.gd")

var _ring_nodes: Array[AntialiasedLine2D] = []
var _data: RefCounted = DATA_SCRIPT.new()

func _ready() -> void:
	visible = false

func update_all(bodies: Array) -> void:
	var specs: Array = _data.build_ring_specs(bodies)
	_ensure_ring_count(specs.size())

	for i in range(specs.size()):
		var spec: Dictionary = specs[i]
		var line: AntialiasedLine2D = _ring_nodes[i]
		line.visible = true
		line.width = SimConstants.GRAVITY_DEBUG_LINE_WIDTH
		line.default_color = spec["color"]
		line.points = _build_ring_points(spec["center"], spec["screen_radius"])

	for i in range(specs.size(), _ring_nodes.size()):
		_ring_nodes[i].visible = false

func _ensure_ring_count(target_count: int) -> void:
	while _ring_nodes.size() < target_count:
		var line := AntialiasedLine2D.new()
		add_child(line)
		_ring_nodes.append(line)

func _build_ring_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(RING_SEGMENTS + 1):
		var angle: float = float(i) / float(RING_SEGMENTS) * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points
