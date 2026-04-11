## debug_overlay.gd
## Toggleable debug overlay. Shows live body data for a selected body.
## Toggled by the "toggle_debug" input action (default: Escape).
class_name DebugOverlay
extends CanvasLayer

var _sim: SimWorld = null
var _selected_id: int = -1

@onready var _inspector: BodyInspector = $Inspector

func initialize(world: SimWorld) -> void:
	_sim = world
	visible = false

func toggle() -> void:
	visible = not visible

func try_select_body_at_screen(screen_pos: Vector2, world: SimWorld) -> void:
	# Convert screen position to sim-space
	var sim_pos: Vector2 = screen_pos / SimConstants.SIM_TO_SCREEN
	var best: SimBody = null
	var best_dist_sq: float = INF

	for body in world.bodies:
		if not body.active:
			continue
		var d_sq: float = body.position.distance_squared_to(sim_pos)
		# Click tolerance: 3× body radius in sim-units
		var tol: float = body.radius * 3.0
		if d_sq < tol * tol and d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = body

	if best != null:
		_selected_id = best.id
		_inspector.display_body(best)
		visible = true

func _process(_delta: float) -> void:
	if not visible or _sim == null or _selected_id < 0:
		return
	# Keep inspector updated while visible
	for body in _sim.bodies:
		if body.id == _selected_id:
			_inspector.update_display(body)
			return
	# Body was removed
	_inspector.display_body(null)
	_selected_id = -1
