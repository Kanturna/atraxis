## sim_camera.gd
## Simple pan + zoom camera for the 2D space simulation.
## Pan: middle-mouse drag. Zoom: scroll wheel.
##
## Phase 1 keeps this Camera2D implementation on purpose.
## Phantom Camera stays installed but is intentionally not integrated yet.
class_name SimCamera
extends Camera2D

const MIN_PAN_SPEED: float = 600.0
const PAN_SCREEN_FRACTION_PER_SECOND: float = 0.85
const FAST_PAN_MULTIPLIER: float = 4.0
const ZOOM_SPEED: float = 0.15
const ZOOM_SMOOTHNESS: float = 10.0
const ZOOM_MIN: float = 0.015
const ZOOM_MAX: float = 5.0
const FOCUS_TRANSITION_POSITION_SMOOTHNESS: float = 8.0
const FOCUS_TRANSITION_ZOOM_SMOOTHNESS: float = 8.0
const FOCUS_TRANSITION_POSITION_EPSILON: float = 12.0
const FOCUS_TRANSITION_VISIBLE_RADIUS_EPSILON: float = 24.0

var _dragging: bool = false
var _target_zoom: float = 1.0
var _zoom_focus_screen: Vector2 = Vector2.ZERO
var _focus_transition_active: bool = false
var _focus_transition_arrived: bool = false
var _focus_transition_target_position: Vector2 = Vector2.ZERO
var _focus_transition_target_visible_world_radius: float = 0.0
var _focus_transition_target_zoom: float = 1.0

func _ready() -> void:
	_target_zoom = zoom.x
	_zoom_focus_screen = get_viewport().get_visible_rect().size * 0.5

func _process(delta: float) -> void:
	_update_keyboard_pan(delta)
	if _focus_transition_active:
		_update_focus_transition(delta)
	else:
		_update_smooth_zoom(delta)

func _input(event: InputEvent) -> void:
	# Middle-mouse pan
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed

	if event is InputEventMouseMotion and _dragging:
		cancel_focus_transition()
		position -= event.relative / zoom

	# Scroll-wheel zoom (centered on cursor)
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cancel_focus_transition()
			_request_zoom(event.position, 1.0 - ZOOM_SPEED)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cancel_focus_transition()
			_request_zoom(event.position, 1.0 + ZOOM_SPEED)

func _update_keyboard_pan(delta: float) -> void:
	var input_dir := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if input_dir == Vector2.ZERO:
		return
	cancel_focus_transition()
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

func start_focus_transition(target_world_position: Vector2, target_visible_world_radius: float) -> void:
	_focus_transition_target_position = target_world_position
	_focus_transition_target_zoom = _zoom_for_visible_world_radius(maxf(target_visible_world_radius, 1.0))
	# Derive the achievable visible radius from the clamped zoom so that
	# _has_reached_focus_transition_target() compares against a value the camera
	# can actually reach. Without this, requests that exceed ZOOM_MIN result in a
	# zoom that is clamped but a target radius that can never be matched, causing
	# _focus_transition_arrived to stay false and cluster activation to never fire.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var viewport_radius: float = 0.5 * maxf(viewport_size.x, viewport_size.y)
	_focus_transition_target_visible_world_radius = viewport_radius / maxf(_focus_transition_target_zoom, 0.001)
	_focus_transition_active = true
	_focus_transition_arrived = false
	_target_zoom = _focus_transition_target_zoom
	_zoom_focus_screen = viewport_size * 0.5

func cancel_focus_transition() -> void:
	if not _focus_transition_active and not _focus_transition_arrived:
		return
	_focus_transition_active = false
	_focus_transition_arrived = false
	_target_zoom = zoom.x

func is_focus_transition_active() -> bool:
	return _focus_transition_active

func has_focus_transition_arrived() -> bool:
	return _focus_transition_arrived

func get_focus_transition_target_world_position() -> Vector2:
	return _focus_transition_target_position

func rebase_focus_transition(
		current_world_position: Vector2,
		target_world_position: Vector2) -> void:
	position = current_world_position
	_focus_transition_target_position = target_world_position
	if _focus_transition_active:
		_target_zoom = _focus_transition_target_zoom
	elif _focus_transition_arrived:
		_target_zoom = zoom.x

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

func _update_focus_transition(delta: float) -> void:
	var position_weight: float = clamp(delta * FOCUS_TRANSITION_POSITION_SMOOTHNESS, 0.0, 1.0)
	var zoom_weight: float = clamp(delta * FOCUS_TRANSITION_ZOOM_SMOOTHNESS, 0.0, 1.0)
	position = position.lerp(_focus_transition_target_position, position_weight)
	zoom = Vector2.ONE * lerpf(zoom.x, _focus_transition_target_zoom, zoom_weight)
	_target_zoom = zoom.x
	_zoom_focus_screen = get_viewport().get_visible_rect().size * 0.5
	if _has_reached_focus_transition_target():
		position = _focus_transition_target_position
		zoom = Vector2.ONE * _focus_transition_target_zoom
		_target_zoom = _focus_transition_target_zoom
		_focus_transition_active = false
		_focus_transition_arrived = true

func _has_reached_focus_transition_target() -> bool:
	var position_error: float = position.distance_to(_focus_transition_target_position)
	var visible_radius_error: float = absf(get_visible_world_radius() - _focus_transition_target_visible_world_radius)
	var visible_radius_epsilon: float = maxf(
		FOCUS_TRANSITION_VISIBLE_RADIUS_EPSILON,
		_focus_transition_target_visible_world_radius * 0.02
	)
	return position_error <= FOCUS_TRANSITION_POSITION_EPSILON \
		and visible_radius_error <= visible_radius_epsilon

func _zoom_for_visible_world_radius(visible_world_radius: float) -> float:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var viewport_radius: float = 0.5 * maxf(viewport_size.x, viewport_size.y)
	if viewport_radius <= 0.0 or visible_world_radius <= 0.0:
		return zoom.x
	return clamp(viewport_radius / visible_world_radius, ZOOM_MIN, ZOOM_MAX)

func get_focus_world_position() -> Vector2:
	return get_screen_center_position()

func get_visible_world_radius() -> float:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	return 0.5 * max(viewport_size.x, viewport_size.y) / max(zoom.x, 0.001)

func set_focus_world_position(world_position: Vector2) -> void:
	_focus_transition_active = false
	_focus_transition_arrived = false
	position = world_position
