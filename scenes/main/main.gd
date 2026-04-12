## main.gd
## Root scene script. Owns the galaxy runtime, drives the fixed-timestep loop,
## and wires the active local SimWorld projection to the renderer.
extends Node2D

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")
const CLICK_CLUSTER_ACTIVATION_PROGRESS_THRESHOLD: float = 0.55

# -------------------------------------------------------------------------
# References
# -------------------------------------------------------------------------

@onready var _world_renderer: WorldRenderer = $WorldRenderer
@onready var _sim_camera: SimCamera = $Camera2D
@onready var _debug_overlay: DebugOverlay = $DebugOverlay
@onready var _hud: HUD = $HUD

# -------------------------------------------------------------------------
# Simulation state
# -------------------------------------------------------------------------

var galaxy_runtime: GalaxyRuntime = null
var galaxy_state: GalaxyState = null
var active_cluster_session: ActiveClusterSession = null
var sim_world: SimWorld = null
var _current_start_config: RefCounted = START_CONFIG_SCRIPT.new()
var _pending_click_activation_cluster_id: int = -1
var _pending_click_activation_focus_global_position: Vector2 = Vector2.ZERO
var _pending_click_activation_requested: bool = false
var _pending_click_activation_initial_focus_global_position: Vector2 = Vector2.ZERO
var _pending_click_activation_initial_visible_radius_sim: float = 0.0
var _pending_click_activation_target_visible_radius_sim: float = 0.0

## Fixed timestep accumulator. Accumulates real delta time and drains it
## in FIXED_DT chunks so the simulation always advances in equal steps.
var _accumulated_dt: float = 0.0

## Safety cap: if the frame takes too long (e.g., a one-off hitch),
## we skip steps rather than running hundreds to "catch up" (spiral of death).
const MAX_STEPS_PER_FRAME: int = 10

# -------------------------------------------------------------------------
# Initialization
# -------------------------------------------------------------------------

func _ready() -> void:
	if not _debug_overlay.restart_requested.is_connected(_on_restart_requested):
		_debug_overlay.restart_requested.connect(_on_restart_requested)
	if not _debug_overlay.black_hole_mass_changed.is_connected(_on_black_hole_mass_changed):
		_debug_overlay.black_hole_mass_changed.connect(_on_black_hole_mass_changed)
	if not _debug_overlay.cluster_activation_requested.is_connected(_on_cluster_activation_requested):
		_debug_overlay.cluster_activation_requested.connect(_on_cluster_activation_requested)
	if not _debug_overlay.cluster_activation_override_requested.is_connected(_on_cluster_activation_override_requested):
		_debug_overlay.cluster_activation_override_requested.connect(_on_cluster_activation_override_requested)
	if not _debug_overlay.cluster_activation_override_cleared.is_connected(_on_cluster_activation_override_cleared):
		_debug_overlay.cluster_activation_override_cleared.connect(_on_cluster_activation_override_cleared)
	restart_simulation(_current_start_config)

func _exit_tree() -> void:
	_release_runtime_references()

# -------------------------------------------------------------------------
# Main loop
# -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if sim_world == null:
		return
	_update_pending_cluster_transition()
	var preserved_focus_global_position: Vector2 = _camera_focus_global_position()
	_update_runtime_focus_context()
	_accumulated_dt += delta
	var steps: int = 0
	while _accumulated_dt >= SimConstants.FIXED_DT and steps < MAX_STEPS_PER_FRAME:
		galaxy_runtime.step(SimConstants.FIXED_DT)
		_accumulated_dt -= SimConstants.FIXED_DT
		steps += 1
	var previous_world: SimWorld = sim_world
	var world_switched: bool = _sync_runtime_aliases()
	if world_switched:
		if _should_rebase_pending_cluster_transition():
			_rebase_pending_cluster_transition_after_world_switch(preserved_focus_global_position)
		else:
			_restore_camera_focus_global_position(preserved_focus_global_position)
		_rebind_active_world(previous_world, _hud.get_current_time_scale(), _debug_overlay.visible)
		if active_cluster_session != null and active_cluster_session.cluster_id == _pending_click_activation_cluster_id:
			_clear_pending_cluster_transition(false)
		elif _pending_click_activation_requested:
			_clear_pending_cluster_transition(false)

	# Render the current sim state (after all steps for this frame)
	_world_renderer.render_frame(sim_world)
	_debug_overlay.update_runtime_metrics(delta, steps)
	_hud.update_display(sim_world)

# -------------------------------------------------------------------------
# Input
# -------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_overlay.toggle()
		_world_renderer.set_debug_overlays_visible(_debug_overlay.visible)

	# Body selection by click: convert viewport pixel → 2D world position
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() \
				* event.position
		if _debug_overlay.try_select_body_at_screen(world_pos, sim_world):
			return
		var cluster_pick: Dictionary = _world_renderer.pick_remote_cluster_at_canvas_position(world_pos)
		if not cluster_pick.is_empty():
			_start_cluster_activation_transition(cluster_pick)

func restart_simulation(config) -> void:
	var safe_config = config.copy()
	safe_config.clamp_values()
	_current_start_config = safe_config
	_clear_pending_cluster_transition(true)

	var debug_visible: bool = _debug_overlay.visible
	var time_scale: float = _hud.get_current_time_scale()
	var previous_world: SimWorld = sim_world
	_disconnect_world_signals(previous_world)
	_accumulated_dt = 0.0

	galaxy_runtime = WorldBuilder.build_runtime_from_config(_current_start_config)
	_sync_runtime_aliases()
	if sim_world == null:
		return

	_rebind_active_world(previous_world, time_scale, debug_visible)
	_debug_overlay.update_runtime_metrics(0.0, 0)

func _disconnect_world_signals(world: SimWorld = null) -> void:
	if world == null:
		world = sim_world
	if world == null:
		return
	if world.body_added.is_connected(_world_renderer._on_body_added):
		world.body_added.disconnect(_world_renderer._on_body_added)
	if world.body_removed.is_connected(_world_renderer._on_body_removed):
		world.body_removed.disconnect(_world_renderer._on_body_removed)

func _on_restart_requested(config) -> void:
	restart_simulation(config)

func _on_black_hole_mass_changed(new_mass: float) -> void:
	_current_start_config.black_hole_mass = new_mass
	_current_start_config.clamp_values()
	if galaxy_runtime != null:
		galaxy_runtime.set_black_hole_mass(_current_start_config.black_hole_mass)
		_sync_runtime_aliases()

func request_cluster_activation(cluster_id: int) -> void:
	if galaxy_runtime == null:
		return
	galaxy_runtime.request_cluster_activation(cluster_id)

func request_cluster_activation_override(cluster_id: int) -> void:
	if galaxy_runtime == null:
		return
	galaxy_runtime.request_cluster_activation_override(cluster_id)

func clear_cluster_activation_override() -> void:
	if galaxy_runtime == null:
		return
	galaxy_runtime.clear_cluster_activation_override()

func _on_cluster_activation_requested(cluster_id: int) -> void:
	request_cluster_activation(cluster_id)

func _on_cluster_activation_override_requested(cluster_id: int) -> void:
	request_cluster_activation_override(cluster_id)

func _on_cluster_activation_override_cleared() -> void:
	clear_cluster_activation_override()

func _sync_runtime_aliases() -> bool:
	var previous_world: SimWorld = sim_world
	if galaxy_runtime == null:
		galaxy_state = null
		active_cluster_session = null
		sim_world = null
		return previous_world != sim_world
	galaxy_state = galaxy_runtime.galaxy_state
	active_cluster_session = galaxy_runtime.active_cluster_session
	sim_world = galaxy_runtime.get_active_sim_world()
	return previous_world != sim_world

func _rebind_active_world(previous_world: SimWorld, time_scale: float, debug_visible: bool) -> void:
	_disconnect_world_signals(previous_world)
	if sim_world == null:
		return

	var zones_by_star: Dictionary = {}
	for star in sim_world.get_stars():
		zones_by_star[star.id] = WorldBuilder.compute_zones(star)

	sim_world.body_added.connect(_world_renderer._on_body_added)
	sim_world.body_removed.connect(_world_renderer._on_body_removed)

	_world_renderer.initialize(sim_world, zones_by_star, galaxy_state, active_cluster_session)
	_debug_overlay.initialize(sim_world, _current_start_config, galaxy_state, active_cluster_session)
	_hud.initialize(sim_world, time_scale)
	_debug_overlay.visible = debug_visible
	_world_renderer.set_debug_overlays_visible(debug_visible)
	_world_renderer.render_frame(sim_world)
	_hud.update_display(sim_world)
	if previous_world != null and previous_world != sim_world:
		previous_world.dispose()

func _update_runtime_focus_context() -> void:
	if galaxy_runtime == null or _sim_camera == null or active_cluster_session == null:
		return
	galaxy_runtime.update_focus_context(
		_camera_focus_global_position(),
		_sim_camera.get_visible_world_radius() / max(SimConstants.SIM_TO_SCREEN, 0.001)
	)

func _camera_focus_global_position() -> Vector2:
	if _sim_camera == null or active_cluster_session == null:
		return Vector2.ZERO
	return active_cluster_session.to_global(
		_sim_camera.get_focus_world_position() / max(SimConstants.SIM_TO_SCREEN, 0.001)
	)

func _restore_camera_focus_global_position(global_focus_position: Vector2) -> void:
	if _sim_camera == null or active_cluster_session == null:
		return
	_sim_camera.set_focus_world_position(
		active_cluster_session.to_local(global_focus_position) * SimConstants.SIM_TO_SCREEN
	)

func _release_runtime_references() -> void:
	_clear_pending_cluster_transition(true)
	_disconnect_world_signals(sim_world)
	if _debug_overlay != null:
		_debug_overlay.clear_world_reference()
	if _hud != null:
		_hud.clear_world_reference()
	if sim_world != null:
		sim_world.dispose()
	galaxy_runtime = null
	galaxy_state = null
	active_cluster_session = null
	sim_world = null

func _start_cluster_activation_transition(cluster_pick: Dictionary) -> void:
	if _sim_camera == null or active_cluster_session == null:
		return
	var cluster_id: int = int(cluster_pick.get("cluster_id", -1))
	if cluster_id < 0 or cluster_id == active_cluster_session.cluster_id:
		return
	var target_global_position: Vector2 = Vector2(
		cluster_pick.get(
			"clicked_global_focus_position",
			cluster_pick.get("global_center", Vector2.ZERO)
		)
	)
	var target_local_position: Vector2 = active_cluster_session.to_local(target_global_position)
	var current_visible_radius_sim: float = _sim_camera.get_visible_world_radius() / max(SimConstants.SIM_TO_SCREEN, 0.001)
	var target_visible_radius_sim: float = current_visible_radius_sim
	var authoritative_radius: float = maxf(float(cluster_pick.get("authoritative_radius", 0.0)), 0.0)
	if authoritative_radius > 0.0:
		# Land at 1.5× the target cluster radius regardless of current zoom:
		# zooms in from a wide galaxy view and zooms out when already close up,
		# so the destination cluster is always properly framed on arrival.
		target_visible_radius_sim = authoritative_radius * 1.5
	_pending_click_activation_cluster_id = cluster_id
	_pending_click_activation_focus_global_position = target_global_position
	_pending_click_activation_initial_focus_global_position = _camera_focus_global_position()
	_pending_click_activation_initial_visible_radius_sim = current_visible_radius_sim
	_pending_click_activation_target_visible_radius_sim = target_visible_radius_sim
	_pending_click_activation_requested = false
	_sim_camera.start_focus_transition(
		target_local_position * SimConstants.SIM_TO_SCREEN,
		target_visible_radius_sim * SimConstants.SIM_TO_SCREEN
	)

func _update_pending_cluster_transition() -> void:
	if _pending_click_activation_cluster_id < 0 or _sim_camera == null:
		return
	if _pending_click_activation_requested:
		return
	if _should_request_pending_cluster_activation():
		if galaxy_runtime != null and galaxy_runtime.request_cluster_activation(_pending_click_activation_cluster_id):
			_pending_click_activation_requested = true
		else:
			_clear_pending_cluster_transition(false)
		return
	if not _sim_camera.is_focus_transition_active():
		_clear_pending_cluster_transition(false)

func _clear_pending_cluster_transition(cancel_camera: bool) -> void:
	_pending_click_activation_cluster_id = -1
	_pending_click_activation_focus_global_position = Vector2.ZERO
	_pending_click_activation_initial_focus_global_position = Vector2.ZERO
	_pending_click_activation_initial_visible_radius_sim = 0.0
	_pending_click_activation_target_visible_radius_sim = 0.0
	_pending_click_activation_requested = false
	if cancel_camera and _sim_camera != null:
		_sim_camera.cancel_focus_transition()

func _should_request_pending_cluster_activation() -> bool:
	if _pending_click_activation_cluster_id < 0 or _sim_camera == null:
		return false
	if not _sim_camera.is_focus_transition_active():
		return false
	var position_progress: float = _transition_position_progress()
	var zoom_progress: float = _transition_zoom_progress()
	return minf(position_progress, zoom_progress) >= CLICK_CLUSTER_ACTIVATION_PROGRESS_THRESHOLD

func _transition_position_progress() -> float:
	var initial_distance: float = _pending_click_activation_initial_focus_global_position.distance_to(
		_pending_click_activation_focus_global_position
	)
	if initial_distance <= 0.001:
		return 1.0
	var current_distance: float = _camera_focus_global_position().distance_to(
		_pending_click_activation_focus_global_position
	)
	return clampf(1.0 - (current_distance / initial_distance), 0.0, 1.0)

func _transition_zoom_progress() -> float:
	var initial_zoom_delta: float = absf(
		_pending_click_activation_initial_visible_radius_sim - _pending_click_activation_target_visible_radius_sim
	)
	if initial_zoom_delta <= 0.001:
		return 1.0
	var current_visible_radius_sim: float = _sim_camera.get_visible_world_radius() / max(SimConstants.SIM_TO_SCREEN, 0.001)
	var current_zoom_delta: float = absf(
		current_visible_radius_sim - _pending_click_activation_target_visible_radius_sim
	)
	return clampf(1.0 - (current_zoom_delta / initial_zoom_delta), 0.0, 1.0)

func _should_rebase_pending_cluster_transition() -> bool:
	return _pending_click_activation_requested \
		and _sim_camera != null \
		and active_cluster_session != null \
		and active_cluster_session.cluster_id == _pending_click_activation_cluster_id

func _rebase_pending_cluster_transition_after_world_switch(
		current_focus_global_position: Vector2) -> void:
	if _sim_camera == null or active_cluster_session == null:
		return
	var rebased_current_focus: Vector2 = active_cluster_session.to_local(
		current_focus_global_position
	) * SimConstants.SIM_TO_SCREEN
	var rebased_target_focus: Vector2 = active_cluster_session.to_local(
		_pending_click_activation_focus_global_position
	) * SimConstants.SIM_TO_SCREEN
	_sim_camera.rebase_focus_transition(rebased_current_focus, rebased_target_focus)
