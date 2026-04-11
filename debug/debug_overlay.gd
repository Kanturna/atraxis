## debug_overlay.gd
## Toggleable debug overlay. Shows live body data for a selected body.
## Toggled by the "toggle_debug" input action (default: Escape).
class_name DebugOverlay
extends CanvasLayer

const COLLISION_WINDOW_SECONDS: float = 3.0
const FRAME_SMOOTHING_ALPHA: float = 0.18
const DEBUG_METRICS_SCRIPT := preload("res://debug/debug_metrics.gd")
const START_CONFIG_SCRIPT := preload("res://simulation/simulation_start_config.gd")

signal restart_requested(start_config)

var _sim: SimWorld = null
var _selected_id: int = -1
var _metrics: RefCounted = DEBUG_METRICS_SCRIPT.new()
var _collision_timestamps: Array[float] = []
var _last_frame_delta: float = 0.0
var _last_steps_this_frame: int = 0
var _smoothed_frame_ms: float = 0.0

@onready var _inspector: BodyInspector = $Inspector
@onready var _stats_label: RichTextLabel = $StatsPanel/RichTextLabel
@onready var _mode_option: OptionButton = $StartPanel/VBox/SettingsGrid/ModeOption
@onready var _seed_spin: SpinBox = $StartPanel/VBox/SettingsGrid/SeedSpin
@onready var _sun_orbit_radius_label: Label = $StartPanel/VBox/SettingsGrid/SunOrbitRadiusLabel
@onready var _sun_orbit_radius_spin: SpinBox = $StartPanel/VBox/SettingsGrid/SunOrbitRadiusSpin
@onready var _sun_orbit_speed_label: Label = $StartPanel/VBox/SettingsGrid/SunOrbitSpeedLabel
@onready var _sun_orbit_speed_spin: SpinBox = $StartPanel/VBox/SettingsGrid/SunOrbitSpeedSpin
@onready var _core_planet_count_label: Label = $StartPanel/VBox/SettingsGrid/CorePlanetCountLabel
@onready var _core_planet_count_spin: SpinBox = $StartPanel/VBox/SettingsGrid/CorePlanetCountSpin
@onready var _disturbance_count_label: Label = $StartPanel/VBox/SettingsGrid/DisturbanceCountLabel
@onready var _disturbance_count_spin: SpinBox = $StartPanel/VBox/SettingsGrid/DisturbanceCountSpin
@onready var _spawn_radius_spin: SpinBox = $StartPanel/VBox/SettingsGrid/SpawnRadiusSpin
@onready var _spawn_radius_label: Label = $StartPanel/VBox/SettingsGrid/SpawnRadiusLabel
@onready var _spawn_spread_spin: SpinBox = $StartPanel/VBox/SettingsGrid/SpawnSpreadSpin
@onready var _spawn_spread_label: Label = $StartPanel/VBox/SettingsGrid/SpawnSpreadLabel
@onready var _speed_scale_spin: SpinBox = $StartPanel/VBox/SettingsGrid/SpeedScaleSpin
@onready var _speed_scale_label: Label = $StartPanel/VBox/SettingsGrid/SpeedScaleLabel
@onready var _tangential_bias_spin: SpinBox = $StartPanel/VBox/SettingsGrid/TangentialBiasSpin
@onready var _tangential_bias_label: Label = $StartPanel/VBox/SettingsGrid/TangentialBiasLabel
@onready var _chaos_body_count_label: Label = $StartPanel/VBox/SettingsGrid/ChaosBodyCountLabel
@onready var _chaos_body_count_spin: SpinBox = $StartPanel/VBox/SettingsGrid/ChaosBodyCountSpin
@onready var _restart_button: Button = $StartPanel/VBox/RestartButton

func _ready() -> void:
	_mode_option.clear()
	_mode_option.add_item("Stable Anchor", START_CONFIG_SCRIPT.StartMode.STABLE_ANCHOR)
	_mode_option.add_item("Chaos Inflow", START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW)
	if not _mode_option.item_selected.is_connected(_on_mode_selected):
		_mode_option.item_selected.connect(_on_mode_selected)
	if not _restart_button.pressed.is_connected(_on_restart_button_pressed):
		_restart_button.pressed.connect(_on_restart_button_pressed)
	_sync_start_controls(START_CONFIG_SCRIPT.new())

func initialize(world: SimWorld, start_config = null) -> void:
	if _sim != null and _sim.collision_occurred.is_connected(_on_collision_occurred):
		_sim.collision_occurred.disconnect(_on_collision_occurred)
	_sim = world
	if _sim != null:
		_sim.collision_occurred.connect(_on_collision_occurred)
	_selected_id = -1
	_collision_timestamps.clear()
	_last_frame_delta = 0.0
	_last_steps_this_frame = 0
	_smoothed_frame_ms = 0.0
	_inspector.display_body(null)
	_sync_start_controls(start_config if start_config != null else START_CONFIG_SCRIPT.new())
	_update_stats_text()

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
		+ "Analytic planets %d\n" % orbit_stats["analytic_planets"]
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

func _sync_start_controls(config) -> void:
	if _mode_option == null:
		return
	var safe_config = config.copy()
	safe_config.clamp_values()
	_mode_option.select(safe_config.mode)
	_seed_spin.value = safe_config.seed
	_sun_orbit_radius_spin.value = safe_config.sun_orbit_radius_au
	_sun_orbit_speed_spin.value = safe_config.sun_orbit_speed_scale
	_core_planet_count_spin.value = safe_config.core_planet_count
	_disturbance_count_spin.value = safe_config.disturbance_body_count
	_spawn_radius_spin.value = safe_config.spawn_radius_au
	_spawn_spread_spin.value = safe_config.spawn_spread_au
	_speed_scale_spin.value = safe_config.inflow_speed_scale
	_tangential_bias_spin.value = safe_config.tangential_bias
	_chaos_body_count_spin.value = safe_config.chaos_body_count
	_update_mode_specific_inputs()

func _read_start_config():
	var config = START_CONFIG_SCRIPT.new()
	config.mode = _mode_option.get_selected_id()
	config.seed = int(_seed_spin.value)
	config.sun_orbit_radius_au = _sun_orbit_radius_spin.value
	config.sun_orbit_speed_scale = _sun_orbit_speed_spin.value
	config.core_planet_count = int(_core_planet_count_spin.value)
	config.disturbance_body_count = int(_disturbance_count_spin.value)
	config.spawn_radius_au = _spawn_radius_spin.value
	config.spawn_spread_au = _spawn_spread_spin.value
	config.inflow_speed_scale = _speed_scale_spin.value
	config.tangential_bias = _tangential_bias_spin.value
	config.chaos_body_count = int(_chaos_body_count_spin.value)
	config.clamp_values()
	return config

func _update_mode_specific_inputs() -> void:
	var chaos_enabled: bool = _mode_option.get_selected_id() == START_CONFIG_SCRIPT.StartMode.CHAOS_INFLOW
	var stable_nodes: Array[CanvasItem] = [
		_sun_orbit_radius_label,
		_sun_orbit_radius_spin,
		_sun_orbit_speed_label,
		_sun_orbit_speed_spin,
		_core_planet_count_label,
		_core_planet_count_spin,
		_disturbance_count_label,
		_disturbance_count_spin,
	]
	var chaos_nodes: Array[CanvasItem] = [
		_spawn_radius_label,
		_spawn_radius_spin,
		_spawn_spread_label,
		_spawn_spread_spin,
		_speed_scale_label,
		_speed_scale_spin,
		_tangential_bias_label,
		_tangential_bias_spin,
		_chaos_body_count_label,
		_chaos_body_count_spin,
	]
	for node in stable_nodes:
		node.visible = not chaos_enabled
	for node in chaos_nodes:
		node.visible = chaos_enabled

func _on_mode_selected(_index: int) -> void:
	_update_mode_specific_inputs()

func _on_restart_button_pressed() -> void:
	restart_requested.emit(_read_start_config())
