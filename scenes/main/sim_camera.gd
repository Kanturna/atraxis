## sim_camera.gd
## Simple pan + zoom camera for the 2D space simulation.
## Pan: middle-mouse drag. Zoom: scroll wheel.
##
## Phase 1 keeps this Camera2D implementation on purpose.
## Phantom Camera stays installed but is intentionally not integrated yet.
extends Camera2D

const MIN_PAN_SPEED: float = 600.0
const PAN_SCREEN_FRACTION_PER_SECOND: float = 0.85
const FAST_PAN_MULTIPLIER: float = 4.0
const ZOOM_SPEED: float = 0.15
const ZOOM_SMOOTHNESS: float = 10.0
const ZOOM_MIN: float = 0.015
const ZOOM_MAX: float = 5.0

var _dragging: bool = false
var _target_zoom: float = 1.0
var _zoom_focus_screen: Vector2 = Vector2.ZERO

func _ready() -> void:
	_target_zoom = zoom.x
	_zoom_focus_screen = get_viewport().get_visible_rect().size * 0.5

func _process(delta: float) -> void:
	_update_keyboard_pan(delta)
	_update_smooth_zoom(delta)

func _input(event: InputEvent) -> void:
	# Middle-mouse pan
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed

	if event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom

	# Scroll-wheel zoom (centered on cursor)
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_request_zoom(event.position, 1.0 - ZOOM_SPEED)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_request_zoom(event.position, 1.0 + ZOOM_SPEED)

func _update_keyboard_pan(delta: float) -> void:
	var input_dir := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if input_dir == Vector2.ZERO:
		return
	# Scale pan speed by the currently visible world span so zoomed-out navigation
	# covers large systems much faster while keeping close-up movement controllable.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var visible_world_span: float = max(viewport_size.x, viewport_size.y) / max(zoom.x, 0.001)
	var speed: float = max(MIN_PAN_SPEED, visible_world_span * PAN_SCREEN_FRACTION_PER_SECOND)
	if Input.is_action_pressed("camera_fast"):
		speed *= FAST_PAN_MULTIPLIER
	position += input_dir.normalized() * speed * delta

func _request_zoom(screen_point: Vector2, factor: float) -> void:
	_zoom_focus_screen = screen_point
	_target_zoom = clamp(_target_zoom * factor, ZOOM_MIN, ZOOM_MAX)

func _update_smooth_zoom(delta: float) -> void:
	var current_zoom: float = zoom.x
	if is_equal_approx(current_zoom, _target_zoom):
		return
	var viewport_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var world_point: Vector2 = get_screen_center_position() + \
			(_zoom_focus_screen - viewport_center) / zoom
	var next_zoom: float = lerpf(current_zoom, _target_zoom, clamp(delta * ZOOM_SMOOTHNESS, 0.0, 1.0))
	zoom = Vector2.ONE * next_zoom
	var new_world_point: Vector2 = get_screen_center_position() + \
			(_zoom_focus_screen - viewport_center) / zoom
	position += world_point - new_world_point
