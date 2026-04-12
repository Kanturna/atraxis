extends GutTest

const SIM_CAMERA_SCRIPT := preload("res://scenes/main/sim_camera.gd")

func test_focus_transition_arrives_at_target_position_and_zoom() -> void:
	var camera: SimCamera = _make_camera()
	camera.zoom = Vector2.ONE
	var initial_visible_radius: float = camera.get_visible_world_radius()
	assert_gt(initial_visible_radius, 0.0, "camera tests need a live viewport to derive zoom targets")
	var target_position: Vector2 = Vector2(240.0, -120.0)
	var target_visible_radius: float = initial_visible_radius * 0.5

	camera.start_focus_transition(target_position, target_visible_radius)
	for _i in range(180):
		camera._process(1.0 / 60.0)

	assert_false(camera.is_focus_transition_active(), "the camera should finish the fly-to once it reaches the target")
	assert_true(camera.has_focus_transition_arrived(), "the camera should report a completed transition after arrival")
	assert_almost_eq(camera.position.x, target_position.x, 0.5, "focus transition should land on the target x position")
	assert_almost_eq(camera.position.y, target_position.y, 0.5, "focus transition should land on the target y position")
	assert_almost_eq(
		camera.get_visible_world_radius(),
		target_visible_radius,
		maxf(24.0, target_visible_radius * 0.02),
		"focus transition should converge on the requested zoom framing"
	)

	_dispose_camera(camera)

func test_focus_transition_cancels_on_manual_wheel_zoom() -> void:
	var camera: SimCamera = _make_camera()
	camera.zoom = Vector2.ONE
	camera.start_focus_transition(Vector2(400.0, 120.0), camera.get_visible_world_radius() * 0.4)

	var zoom_event := InputEventMouseButton.new()
	zoom_event.pressed = true
	zoom_event.button_index = MOUSE_BUTTON_WHEEL_UP
	zoom_event.position = Vector2(320.0, 180.0)
	camera._input(zoom_event)

	assert_false(camera.is_focus_transition_active(), "manual wheel zoom should cancel an in-progress focus transition")
	assert_false(camera.has_focus_transition_arrived(), "cancelling the transition should not count as arrival")

	_dispose_camera(camera)

func test_rebase_focus_transition_keeps_motion_continuous() -> void:
	var camera: SimCamera = _make_camera()
	camera.zoom = Vector2.ONE
	var initial_visible_radius: float = camera.get_visible_world_radius()
	var target_position: Vector2 = Vector2(360.0, -240.0)
	var target_visible_radius: float = initial_visible_radius * 0.45

	camera.start_focus_transition(target_position, target_visible_radius)
	for _i in range(12):
		camera._process(1.0 / 60.0)
	var rebased_current: Vector2 = camera.position + Vector2(-180.0, 90.0)
	var rebased_target: Vector2 = camera.get_focus_transition_target_world_position() + Vector2(-180.0, 90.0)

	camera.rebase_focus_transition(rebased_current, rebased_target)

	assert_true(camera.is_focus_transition_active(), "rebasing a live transition should keep it active")
	assert_eq(
		camera.get_focus_transition_target_world_position(),
		rebased_target,
		"rebasing should move the transition target into the new local coordinate space"
	)
	for _i in range(180):
		camera._process(1.0 / 60.0)

	assert_false(camera.is_focus_transition_active(), "the rebased transition should still complete normally")
	assert_true(camera.has_focus_transition_arrived(), "rebased transitions should still report arrival")
	assert_almost_eq(camera.position.x, rebased_target.x, 0.5, "rebased transition should land on the rebased x target")
	assert_almost_eq(camera.position.y, rebased_target.y, 0.5, "rebased transition should land on the rebased y target")
	assert_almost_eq(
		camera.get_visible_world_radius(),
		target_visible_radius,
		maxf(24.0, target_visible_radius * 0.02),
		"rebasing should preserve the requested zoom framing"
	)

	_dispose_camera(camera)

func _make_camera() -> SimCamera:
	var camera: SimCamera = SIM_CAMERA_SCRIPT.new()
	add_child(camera)
	return camera

func _dispose_camera(camera: SimCamera) -> void:
	if camera == null:
		return
	if camera.get_parent() != null:
		camera.get_parent().remove_child(camera)
	camera.free()
