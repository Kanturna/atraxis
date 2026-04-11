## sim_camera.gd
## Simple pan + zoom camera for the 2D space simulation.
## Pan: middle-mouse drag. Zoom: scroll wheel.
##
## Phase 1 keeps this Camera2D implementation on purpose.
## Phantom Camera stays installed but is intentionally not integrated yet.
extends Camera2D

const ZOOM_SPEED: float = 0.15
const ZOOM_MIN: float = 0.05
const ZOOM_MAX: float = 5.0

var _dragging: bool = false
var _drag_origin: Vector2 = Vector2.ZERO

func _input(event: InputEvent) -> void:
	# Middle-mouse pan
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			_drag_origin = event.position

	if event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom

	# Scroll-wheel zoom (centered on cursor)
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.0 + ZOOM_SPEED)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 - ZOOM_SPEED)

func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var old_zoom: float = zoom.x
	var new_zoom: float = clamp(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var world_point: Vector2 = get_screen_center_position() + \
			(screen_point - get_viewport().get_visible_rect().size * 0.5) / zoom
	zoom = Vector2.ONE * new_zoom
	var new_world_point: Vector2 = get_screen_center_position() + \
			(screen_point - get_viewport().get_visible_rect().size * 0.5) / zoom
	position += world_point - new_world_point
