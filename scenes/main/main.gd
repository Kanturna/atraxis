## main.gd
## Root scene script. Owns the currently active cluster session, drives the
## fixed-timestep loop, and wires the local SimWorld projection to the renderer.
extends Node2D

const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")

# -------------------------------------------------------------------------
# References
# -------------------------------------------------------------------------

@onready var _world_renderer: WorldRenderer = $WorldRenderer
@onready var _debug_overlay: DebugOverlay = $DebugOverlay
@onready var _hud: HUD = $HUD

# -------------------------------------------------------------------------
# Simulation state
# -------------------------------------------------------------------------

var galaxy_state: GalaxyState = null
var active_cluster_session: ActiveClusterSession = null
var sim_world: SimWorld = null
var _current_start_config: RefCounted = START_CONFIG_SCRIPT.new()

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
	restart_simulation(_current_start_config)

# -------------------------------------------------------------------------
# Main loop
# -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if sim_world == null:
		return
	_accumulated_dt += delta
	var steps: int = 0
	while _accumulated_dt >= SimConstants.FIXED_DT and steps < MAX_STEPS_PER_FRAME:
		sim_world.step_sim(SimConstants.FIXED_DT)
		_accumulated_dt -= SimConstants.FIXED_DT
		steps += 1

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
		_world_renderer.set_gravity_debug_visible(_debug_overlay.visible)

	# Body selection by click: convert viewport pixel → 2D world position
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() \
				* event.position
		_debug_overlay.try_select_body_at_screen(world_pos, sim_world)

func restart_simulation(config) -> void:
	var safe_config = config.copy()
	safe_config.clamp_values()
	_current_start_config = safe_config

	var debug_visible: bool = _debug_overlay.visible
	var time_scale: float = _hud.get_current_time_scale()
	_disconnect_world_signals()
	_accumulated_dt = 0.0

	active_cluster_session = WorldBuilder.build_active_session_from_config(_current_start_config)
	galaxy_state = active_cluster_session.galaxy_state
	sim_world = active_cluster_session.sim_world
	if sim_world == null:
		return

	var zones_by_star: Dictionary = {}
	for star in sim_world.get_stars():
		zones_by_star[star.id] = WorldBuilder.compute_zones(star)

	sim_world.body_added.connect(_world_renderer._on_body_added)
	sim_world.body_removed.connect(_world_renderer._on_body_removed)

	_world_renderer.initialize(sim_world, zones_by_star)
	_debug_overlay.initialize(sim_world, _current_start_config, galaxy_state, active_cluster_session)
	_hud.initialize(sim_world, time_scale)
	_debug_overlay.visible = debug_visible
	_world_renderer.set_gravity_debug_visible(debug_visible)
	_world_renderer.render_frame(sim_world)
	_debug_overlay.update_runtime_metrics(0.0, 0)
	_hud.update_display(sim_world)

func _disconnect_world_signals() -> void:
	if sim_world == null:
		return
	if sim_world.body_added.is_connected(_world_renderer._on_body_added):
		sim_world.body_added.disconnect(_world_renderer._on_body_added)
	if sim_world.body_removed.is_connected(_world_renderer._on_body_removed):
		sim_world.body_removed.disconnect(_world_renderer._on_body_removed)

func _on_restart_requested(config) -> void:
	restart_simulation(config)

func _on_black_hole_mass_changed(new_mass: float) -> void:
	_current_start_config.black_hole_mass = new_mass
	_current_start_config.clamp_values()
	if active_cluster_session != null:
		active_cluster_session.set_black_hole_mass(_current_start_config.black_hole_mass)
