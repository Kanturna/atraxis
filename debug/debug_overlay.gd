## debug_overlay.gd
## Toggleable debug overlay. Shows live body data for a selected body.
## Toggled by the "toggle_debug" input action (default: Escape).
class_name DebugOverlay
extends CanvasLayer

const COLLISION_WINDOW_SECONDS: float = 3.0
const FRAME_SMOOTHING_ALPHA: float = 0.18
const DEBUG_METRICS_SCRIPT := preload("res://debug/debug_metrics.gd")

var _sim: SimWorld = null
var _selected_id: int = -1
var _metrics: RefCounted = DEBUG_METRICS_SCRIPT.new()
var _collision_timestamps: Array[float] = []
var _last_frame_delta: float = 0.0
var _last_steps_this_frame: int = 0
var _smoothed_frame_ms: float = 0.0

@onready var _inspector: BodyInspector = $Inspector
@onready var _stats_label: RichTextLabel = $StatsPanel/RichTextLabel

func initialize(world: SimWorld) -> void:
	if _sim != null and _sim.collision_occurred.is_connected(_on_collision_occurred):
		_sim.collision_occurred.disconnect(_on_collision_occurred)
	_sim = world
	if _sim != null:
		_sim.collision_occurred.connect(_on_collision_occurred)
	_inspector.display_body(null)
	_update_stats_text()
	visible = false

func toggle() -> void:
	visible = not visible

func update_runtime_metrics(frame_delta: float, steps_this_frame: int) -> void:
	_last_frame_delta = frame_delta
	_last_steps_this_frame = steps_this_frame
	var frame_ms: float = frame_delta * 1000.0
	if _smoothed_frame_ms <= 0.0:
		_smoothed_frame_ms = frame_ms
	else:
		_smoothed_frame_ms = lerpf(_smoothed_frame_ms, frame_ms, FRAME_SMOOTHING_ALPHA)

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
	if _sim == null:
		return

	_prune_collision_timestamps()

	if not visible:
		return

	_update_stats_text()
	_update_inspector()

func _update_inspector() -> void:
	if _selected_id < 0:
		return

	for body in _sim.bodies:
		if body.id == _selected_id:
			_inspector.update_display(body)
			return

	# Body was removed
	_inspector.display_body(null)
	_selected_id = -1

func _update_stats_text() -> void:
	if _stats_label == null or _sim == null:
		return

	var snapshot: Dictionary = _metrics.build_snapshot(_sim, _collision_timestamps.size())
	var sim_stats: Dictionary = snapshot["simulation"]
	var orbit_stats: Dictionary = snapshot["orbit"]
	var chaos_stats: Dictionary = snapshot["chaos"]
	var fps: int = Engine.get_frames_per_second()
	var frame_ms: float = _last_frame_delta * 1000.0

	_stats_label.text = (
		"[code]"
		+ "Performance\n"
		+ "FPS             %d\n" % fps
		+ "Frame ms        %.2f\n" % frame_ms
		+ "Frame ms avg    %.2f\n" % _smoothed_frame_ms
		+ "Sim steps       %d\n" % _last_steps_this_frame
		+ "Time scale      x%.2f\n\n" % _sim.time_scale
		+ "Simulation\n"
		+ "Bodies active   %d\n" % sim_stats["active_bodies"]
		+ "Bodies dynamic  %d\n" % sim_stats["dynamic_bodies"]
		+ "Bodies sleeping %d\n" % sim_stats["sleeping_bodies"]
		+ "Fragments       %d / %d\n" % [sim_stats["fragment_count"], SimConstants.MAX_ACTIVE_FRAGMENTS]
		+ "Debris fields   %d / %d\n\n" % [sim_stats["debris_count"], SimConstants.MAX_DEBRIS_FIELDS]
		+ "Orbit Stability\n"
		+ "Scripted planets %d\n" % orbit_stats["scripted_planets"]
		+ "Radial avg      %.3f\n" % orbit_stats["average_radial_deviation"]
		+ "Radial max      %.3f\n" % orbit_stats["max_radial_deviation"]
		+ "Speed avg       %.3f\n\n" % orbit_stats["average_speed_deviation"]
		+ "Chaos / Unruhe\n"
		+ "Collisions 3s   %d\n" % chaos_stats["collisions_last_3s"]
		+ "Fragment press  %.2f\n" % chaos_stats["fragment_pressure"]
		+ "Debris press    %.2f\n" % chaos_stats["debris_pressure"]
		+ "Awake ratio     %.2f\n" % chaos_stats["awake_dynamic_ratio"]
		+ "Chaos score     %d / 100" % chaos_stats["score"]
		+ "[/code]"
	)

func _on_collision_occurred(_pos: Vector2) -> void:
	_collision_timestamps.append(Time.get_ticks_msec() / 1000.0)
	_prune_collision_timestamps()

func _prune_collision_timestamps() -> void:
	var cutoff: float = Time.get_ticks_msec() / 1000.0 - COLLISION_WINDOW_SECONDS
	while not _collision_timestamps.is_empty() and _collision_timestamps[0] < cutoff:
		_collision_timestamps.remove_at(0)
