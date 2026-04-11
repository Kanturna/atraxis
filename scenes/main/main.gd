## main.gd
## Root scene script. Owns the SimWorld instance, drives the fixed-timestep
## loop, and wires simulation signals to the renderer.
extends Node2D

# -------------------------------------------------------------------------
# References
# -------------------------------------------------------------------------

@onready var _world_renderer: WorldRenderer = $WorldRenderer
@onready var _debug_overlay: CanvasLayer   = $DebugOverlay
@onready var _hud: CanvasLayer             = $HUD

# -------------------------------------------------------------------------
# Simulation state
# -------------------------------------------------------------------------

var sim_world: SimWorld
var _zone_bounds: WorldBuilder.ZoneBoundaries

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
	sim_world = SimWorld.new()
	WorldBuilder.build_mvp(sim_world)

	var star: SimBody = sim_world.get_star()
	if star:
		_zone_bounds = WorldBuilder.compute_zones(star)
	else:
		_zone_bounds = WorldBuilder.ZoneBoundaries.new()

	# Wire sim signals to renderer
	sim_world.body_added.connect(_world_renderer._on_body_added)
	sim_world.body_removed.connect(_world_renderer._on_body_removed)

	# Initialize sub-systems
	_world_renderer.initialize(sim_world, _zone_bounds)
	_debug_overlay.initialize(sim_world)
	_hud.initialize(sim_world)

# -------------------------------------------------------------------------
# Main loop
# -------------------------------------------------------------------------

func _process(delta: float) -> void:
	_accumulated_dt += delta
	var steps: int = 0
	while _accumulated_dt >= SimConstants.FIXED_DT and steps < MAX_STEPS_PER_FRAME:
		sim_world.step_sim(SimConstants.FIXED_DT)
		_accumulated_dt -= SimConstants.FIXED_DT
		steps += 1

	# Render the current sim state (after all steps for this frame)
	_world_renderer.render_frame(sim_world)
	_hud.update_display(sim_world)

# -------------------------------------------------------------------------
# Input
# -------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_overlay.toggle()

	# Body selection by click: convert viewport pixel → 2D world position
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() \
				* event.position
		_debug_overlay.try_select_body_at_screen(world_pos, sim_world)
