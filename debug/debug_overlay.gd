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
signal black_hole_mass_changed(new_mass: float)
signal cluster_activation_requested(cluster_id: int)
signal cluster_activation_override_requested(cluster_id: int)
signal cluster_activation_override_cleared()

var _sim: SimWorld = null
var _galaxy_state: GalaxyState = null
var _active_cluster_session: ActiveClusterSession = null
var _selected_id: int = -1
var _metrics: RefCounted = DEBUG_METRICS_SCRIPT.new()
var _collision_timestamps: Array[float] = []
var _last_frame_delta: float = 0.0
var _last_steps_this_frame: int = 0
var _smoothed_frame_ms: float = 0.0
var _last_dominant_bh_by_star: Dictionary = {}
var _anchor_switch_count: int = 0
var _left_panels_collapsed: bool = false
var _right_panels_collapsed: bool = false

# Galaxy Cluster controls — created programmatically in _ready() so the scene
# file does not need to be modified for each new topology.
var _galaxy_cluster_count_label: Label = null
var _galaxy_cluster_count_spin: SpinBox = null
var _galaxy_cluster_radius_label: Label = null
var _galaxy_cluster_radius_spin: SpinBox = null
var _galaxy_void_scale_label: Label = null
var _galaxy_void_scale_spin: SpinBox = null
var _galaxy_hint_label: Label = null

@onready var _inspector: BodyInspector = $Inspector
@onready var _stats_label: RichTextLabel = $StatsPanel/RichTextLabel
@onready var _stats_panel: PanelContainer = $StatsPanel
@onready var _right_panel_scroll: ScrollContainer = $RightPanelScroll
@onready var _start_panel: PanelContainer = $RightPanelScroll/RightPanelVBox/StartPanel
@onready var _anchor_panel: PanelContainer = $RightPanelScroll/RightPanelVBox/AnchorPanel
@onready var _live_bh_mass_spin: SpinBox = $RightPanelScroll/RightPanelVBox/AnchorPanel/VBox/SettingsGrid/LiveBHMassSpin
@onready var _anchor_diagnostics_panel: PanelContainer = $RightPanelScroll/RightPanelVBox/AnchorDiagnosticsPanel
@onready var _anchor_diagnostics_label: RichTextLabel = $RightPanelScroll/RightPanelVBox/AnchorDiagnosticsPanel/RichTextLabel
@onready var _left_toggle_button: Button = $LeftPanelToggleButton
@onready var _right_toggle_button: Button = $RightPanelToggleButton
@onready var _mode_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/ModeLabel
@onready var _mode_option: OptionButton = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/ModeOption
@onready var _anchor_topology_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/AnchorTopologyLabel
@onready var _anchor_topology_option: OptionButton = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/AnchorTopologyOption
@onready var _seed_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/SeedSpin
@onready var _bh_mass_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/BHMassLabel
@onready var _bh_mass_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/BHMassSpin
@onready var _black_hole_count_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/BlackHoleCountLabel
@onready var _black_hole_count_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/BlackHoleCountSpin
@onready var _star_count_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/StarCountLabel
@onready var _star_count_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/StarCountSpin
@onready var _planets_per_star_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/PlanetsPerStarLabel
@onready var _planets_per_star_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/PlanetsPerStarSpin
@onready var _star_inner_orbit_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/StarInnerOrbitLabel
@onready var _star_inner_orbit_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/StarInnerOrbitSpin
@onready var _star_outer_orbit_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/StarOuterOrbitLabel
@onready var _star_outer_orbit_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/StarOuterOrbitSpin
@onready var _field_spacing_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/FieldSpacingLabel
@onready var _field_spacing_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/FieldSpacingSpin
@onready var _field_patch_hint_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/FieldPatchHintLabel
@onready var _disturbance_count_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/DisturbanceCountLabel
@onready var _disturbance_count_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/DisturbanceCountSpin
@onready var _spawn_radius_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/SpawnRadiusSpin
@onready var _spawn_radius_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/SpawnRadiusLabel
@onready var _spawn_spread_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/SpawnSpreadSpin
@onready var _spawn_spread_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/SpawnSpreadLabel
@onready var _speed_scale_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/SpeedScaleSpin
@onready var _speed_scale_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/SpeedScaleLabel
@onready var _tangential_bias_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/TangentialBiasSpin
@onready var _tangential_bias_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/TangentialBiasLabel
@onready var _chaos_body_count_label: Label = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/ChaosBodyCountLabel
@onready var _chaos_body_count_spin: SpinBox = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid/ChaosBodyCountSpin
@onready var _restart_button: Button = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/RestartButton

func _ready() -> void:
	_mode_label.visible = false
	_mode_option.visible = false
	_anchor_topology_option.clear()
	_anchor_topology_option.add_item("Central BH", START_CONFIG_SCRIPT.AnchorTopology.CENTRAL_BH)
	_anchor_topology_option.add_item("Field Patch", START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH)
	_anchor_topology_option.add_item("Galaxy Cluster", START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER)
	# BH dominance radius ≈ sqrt(G*M/10). For a 12M BH that is ~11 AU, so the
	# field spacing must exceed ~11 AU to avoid gravity-field overlap. Widen the
	# spinbox range to 60 AU so the user can actually reach sensible values.
	_field_spacing_spin.max_value = 60.0
	# Update the hint label text with useful spacing guidance.
	_field_patch_hint_label.text = (
		"Field Patch: multiple BHs shape the gravity field. "
		+ "BH spacing AU controls how far apart each BH is. "
		+ "Dominance radius ≈ sqrt(G·M/10) ≈ 11 AU for 12M BH — "
		+ "set spacing above that value to keep gravity fields separate."
	)
	_create_galaxy_controls()
	if not _anchor_topology_option.item_selected.is_connected(_on_anchor_topology_selected):
		_anchor_topology_option.item_selected.connect(_on_anchor_topology_selected)
	if not _restart_button.pressed.is_connected(_on_restart_button_pressed):
		_restart_button.pressed.connect(_on_restart_button_pressed)
	if not _live_bh_mass_spin.value_changed.is_connected(_on_live_bh_mass_changed):
		_live_bh_mass_spin.value_changed.connect(_on_live_bh_mass_changed)
	if not _left_toggle_button.pressed.is_connected(_on_left_toggle_pressed):
		_left_toggle_button.pressed.connect(_on_left_toggle_pressed)
	if not _right_toggle_button.pressed.is_connected(_on_right_toggle_pressed):
		_right_toggle_button.pressed.connect(_on_right_toggle_pressed)
	_sync_start_controls(START_CONFIG_SCRIPT.new())
	_update_panel_group_visibility()

func initialize(
		world: SimWorld,
		start_config = null,
		galaxy_state: GalaxyState = null,
		active_cluster_session: ActiveClusterSession = null) -> void:
	if _sim != null and _sim.collision_occurred.is_connected(_on_collision_occurred):
		_sim.collision_occurred.disconnect(_on_collision_occurred)
	_sim = world
	_galaxy_state = galaxy_state
	_active_cluster_session = active_cluster_session
	if _sim != null:
		_sim.collision_occurred.connect(_on_collision_occurred)
	_selected_id = -1
	_collision_timestamps.clear()
	_last_frame_delta = 0.0
	_last_steps_this_frame = 0
	_smoothed_frame_ms = 0.0
	_last_dominant_bh_by_star.clear()
	_anchor_switch_count = 0
	_inspector.display_body(null)
	_sync_start_controls(start_config if start_config != null else START_CONFIG_SCRIPT.new())
	_sync_live_anchor_controls(start_config if start_config != null else START_CONFIG_SCRIPT.new())
	_update_stats_text()
	_update_panel_group_visibility()

func toggle() -> void:
	visible = not visible

func request_cluster_activation(cluster_id: int) -> void:
	cluster_activation_requested.emit(cluster_id)

func request_cluster_activation_override(cluster_id: int) -> void:
	cluster_activation_override_requested.emit(cluster_id)

func clear_cluster_activation_override() -> void:
	cluster_activation_override_cleared.emit()

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
		var tol: float = max(body.radius * 3.0, BodyRenderer.selection_radius_in_sim(body) * 1.25)
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
	var anchor_stats: Dictionary = snapshot["anchor"]
	var fps: int = Engine.get_frames_per_second()
	var frame_ms: float = _last_frame_delta * 1000.0
	_update_anchor_switch_tracking(anchor_stats["star_anchor_states"])
	var star_anchor_lines: String = _format_star_anchor_lines(anchor_stats["star_anchor_states"])
	_update_anchor_diagnostics_text(anchor_stats, star_anchor_lines)

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

func _update_anchor_diagnostics_text(anchor_stats: Dictionary, star_anchor_lines: String) -> void:
	if _anchor_diagnostics_label == null:
		return
	_anchor_diagnostics_label.text = (
		"[code]"
		+ "Anchor Diagnostics\n"
		+ _build_cluster_diagnostics_lines()
		+ "BH count        %d\n" % anchor_stats["black_hole_count"]
		+ "Field rings     %d\n" % anchor_stats["field_ring_count"]
		+ "BH mass total   %.0f\n" % anchor_stats["black_hole_mass"]
		+ "Star mass       %.0f\n" % anchor_stats["total_star_mass"]
		+ "Anchor ratio    %.2f\n" % anchor_stats["anchor_ratio"]
		+ "Stars E<0       %d\n" % anchor_stats["negative_specific_energy_stars"]
		+ "Stars E>=0      %d\n" % anchor_stats["non_negative_specific_energy_stars"]
		+ "Min BH-BH       %.0f\n" % anchor_stats["min_black_hole_distance"]
		+ "Min star-star   %.0f\n" % anchor_stats["min_star_star_distance"]
		+ "Min star-BH     %.0f\n" % anchor_stats["min_star_bh_distance"]
		+ "BH switches     %d\n" % _anchor_switch_count
		+ star_anchor_lines
		+ "[/code]"
	)

func _build_cluster_diagnostics_lines() -> String:
	if _galaxy_state == null or _active_cluster_session == null:
		return ""
	return (
		"Galaxy seed     %d\n" % _galaxy_state.galaxy_seed
		+ "Clusters total  %d\n" % _galaxy_state.get_cluster_count()
		+ "Clusters simp   %d\n" % _galaxy_state.count_clusters_by_activation_state(ClusterActivationState.State.SIMPLIFIED)
		+ "Clusters idle   %d\n" % _galaxy_state.count_clusters_by_activation_state(ClusterActivationState.State.UNLOADED)
		+ "Transit objs    %d\n" % _galaxy_state.get_transit_object_count()
		+ "Cluster active  %d\n" % _active_cluster_session.cluster_id
		+ "Cluster global  %.0f, %.0f\n" % [
			_active_cluster_session.cluster_global_origin.x,
			_active_cluster_session.cluster_global_origin.y,
		]
	)

func _on_collision_occurred(_pos: Vector2) -> void:
	_collision_timestamps.append(Time.get_ticks_msec() / 1000.0)
	_prune_collision_timestamps()

func _prune_collision_timestamps() -> void:
	var cutoff: float = Time.get_ticks_msec() / 1000.0 - COLLISION_WINDOW_SECONDS
	while not _collision_timestamps.is_empty() and _collision_timestamps[0] < cutoff:
		_collision_timestamps.remove_at(0)

func _create_galaxy_controls() -> void:
	var settings_grid: GridContainer = $RightPanelScroll/RightPanelVBox/StartPanel/VBox/SettingsGrid

	_galaxy_cluster_count_label = Label.new()
	_galaxy_cluster_count_label.text = "Cluster count"
	settings_grid.add_child(_galaxy_cluster_count_label)
	_galaxy_cluster_count_spin = SpinBox.new()
	_galaxy_cluster_count_spin.min_value = 2
	_galaxy_cluster_count_spin.max_value = 12
	_galaxy_cluster_count_spin.step = 1
	_galaxy_cluster_count_spin.value = SimConstants.DEFAULT_GALAXY_CLUSTER_COUNT
	settings_grid.add_child(_galaxy_cluster_count_spin)

	_galaxy_cluster_radius_label = Label.new()
	_galaxy_cluster_radius_label.text = "Cluster radius AU"
	settings_grid.add_child(_galaxy_cluster_radius_label)
	_galaxy_cluster_radius_spin = SpinBox.new()
	_galaxy_cluster_radius_spin.min_value = 1.0
	_galaxy_cluster_radius_spin.max_value = 8.0
	_galaxy_cluster_radius_spin.step = 0.5
	_galaxy_cluster_radius_spin.value = SimConstants.DEFAULT_GALAXY_CLUSTER_RADIUS_AU
	settings_grid.add_child(_galaxy_cluster_radius_spin)

	_galaxy_void_scale_label = Label.new()
	_galaxy_void_scale_label.text = "Void scale"
	settings_grid.add_child(_galaxy_void_scale_label)
	_galaxy_void_scale_spin = SpinBox.new()
	_galaxy_void_scale_spin.min_value = 2.0
	_galaxy_void_scale_spin.max_value = 6.0
	_galaxy_void_scale_spin.step = 0.5
	_galaxy_void_scale_spin.value = SimConstants.DEFAULT_GALAXY_VOID_SCALE
	settings_grid.add_child(_galaxy_void_scale_spin)

	# Hint label sits below the grid in the VBox, before the restart button.
	_galaxy_hint_label = Label.new()
	_galaxy_hint_label.text = "BHs in compact clusters with large voids between them."
	_galaxy_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var vbox: VBoxContainer = _restart_button.get_parent()
	vbox.add_child(_galaxy_hint_label)
	vbox.move_child(_galaxy_hint_label, _restart_button.get_index())

func _sync_start_controls(config) -> void:
	if _anchor_topology_option == null:
		return
	var safe_config = config.copy()
	safe_config.clamp_values()
	_anchor_topology_option.select(safe_config.anchor_topology)
	_seed_spin.value = safe_config.seed
	_bh_mass_spin.value = safe_config.black_hole_mass
	_black_hole_count_spin.value = safe_config.black_hole_count
	_star_count_spin.value = safe_config.star_count
	_planets_per_star_spin.value = safe_config.planets_per_star
	_star_inner_orbit_spin.value = safe_config.star_inner_orbit_au
	_star_outer_orbit_spin.value = safe_config.star_outer_orbit_au
	_field_spacing_spin.value = safe_config.field_spacing_au
	if _galaxy_cluster_count_spin != null:
		_galaxy_cluster_count_spin.value = safe_config.galaxy_cluster_count
		_galaxy_cluster_radius_spin.value = safe_config.galaxy_cluster_radius_au
		_galaxy_void_scale_spin.value = safe_config.galaxy_void_scale
	_disturbance_count_spin.value = safe_config.disturbance_body_count
	_spawn_radius_spin.value = safe_config.spawn_radius_au
	_spawn_spread_spin.value = safe_config.spawn_spread_au
	_speed_scale_spin.value = safe_config.inflow_speed_scale
	_tangential_bias_spin.value = safe_config.tangential_bias
	_chaos_body_count_spin.value = safe_config.chaos_body_count
	_update_start_inputs()

func _sync_live_anchor_controls(config) -> void:
	var safe_config = config.copy()
	safe_config.clamp_values()
	_live_bh_mass_spin.set_value_no_signal(safe_config.black_hole_mass)
	_update_panel_group_visibility()

func _read_start_config():
	var config = START_CONFIG_SCRIPT.new()
	config.anchor_topology = _anchor_topology_option.get_selected_id()
	config.seed = int(_seed_spin.value)
	config.black_hole_mass = _bh_mass_spin.value
	config.black_hole_count = int(_black_hole_count_spin.value)
	config.star_count = int(_star_count_spin.value)
	config.planets_per_star = int(_planets_per_star_spin.value)
	config.star_inner_orbit_au = _star_inner_orbit_spin.value
	config.star_outer_orbit_au = _star_outer_orbit_spin.value
	config.field_spacing_au = _field_spacing_spin.value
	if _galaxy_cluster_count_spin != null:
		config.galaxy_cluster_count = int(_galaxy_cluster_count_spin.value)
		config.galaxy_cluster_radius_au = _galaxy_cluster_radius_spin.value
		config.galaxy_void_scale = _galaxy_void_scale_spin.value
	config.disturbance_body_count = int(_disturbance_count_spin.value)
	config.spawn_radius_au = _spawn_radius_spin.value
	config.spawn_spread_au = _spawn_spread_spin.value
	config.inflow_speed_scale = _speed_scale_spin.value
	config.tangential_bias = _tangential_bias_spin.value
	config.chaos_body_count = int(_chaos_body_count_spin.value)
	config.clamp_values()
	return config

func _update_start_inputs() -> void:
	var selected_topology: int = _anchor_topology_option.get_selected_id()
	var field_patch_enabled: bool = selected_topology == START_CONFIG_SCRIPT.AnchorTopology.FIELD_PATCH
	var galaxy_cluster_enabled: bool = selected_topology == START_CONFIG_SCRIPT.AnchorTopology.GALAXY_CLUSTER
	var multi_black_hole_enabled: bool = field_patch_enabled or galaxy_cluster_enabled
	var shared_anchor_nodes: Array[CanvasItem] = [
		_bh_mass_label,
		_bh_mass_spin,
		_star_count_label,
		_star_count_spin,
		_planets_per_star_label,
		_planets_per_star_spin,
		_star_inner_orbit_label,
		_star_inner_orbit_spin,
		_star_outer_orbit_label,
		_star_outer_orbit_spin,
		_disturbance_count_label,
		_disturbance_count_spin,
	]
	var dynamic_nodes: Array[CanvasItem] = [
		_anchor_topology_label,
		_anchor_topology_option,
	]
	var multi_black_hole_nodes: Array[CanvasItem] = [
		_black_hole_count_label,
		_black_hole_count_spin,
	]
	var field_patch_nodes: Array[CanvasItem] = [
		_field_spacing_label,
		_field_spacing_spin,
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
	for node in shared_anchor_nodes:
		node.visible = true
	for node in dynamic_nodes:
		node.visible = true
	for node in multi_black_hole_nodes:
		node.visible = multi_black_hole_enabled
	for node in field_patch_nodes:
		node.visible = field_patch_enabled
	var galaxy_nodes: Array = []
	if _galaxy_cluster_count_label != null:
		galaxy_nodes = [
			_galaxy_cluster_count_label,
			_galaxy_cluster_count_spin,
			_galaxy_cluster_radius_label,
			_galaxy_cluster_radius_spin,
			_galaxy_void_scale_label,
			_galaxy_void_scale_spin,
		]
	for node in galaxy_nodes:
		node.visible = galaxy_cluster_enabled
	if _galaxy_hint_label != null:
		_galaxy_hint_label.visible = galaxy_cluster_enabled
	for node in chaos_nodes:
		node.visible = false
	_field_patch_hint_label.visible = field_patch_enabled
	_update_panel_group_visibility()

func _on_anchor_topology_selected(_index: int) -> void:
	_update_start_inputs()

func _on_live_bh_mass_changed(value: float) -> void:
	_bh_mass_spin.set_value_no_signal(value)
	black_hole_mass_changed.emit(value)

func _on_restart_button_pressed() -> void:
	restart_requested.emit(_read_start_config())

func _on_left_toggle_pressed() -> void:
	_left_panels_collapsed = not _left_panels_collapsed
	_update_panel_group_visibility()

func _on_right_toggle_pressed() -> void:
	_right_panels_collapsed = not _right_panels_collapsed
	_update_panel_group_visibility()

func _update_anchor_switch_tracking(star_anchor_states: Array) -> void:
	var active_star_ids: Dictionary = {}
	for state in star_anchor_states:
		var star_id: int = state["star_id"]
		var dominant_bh_id: int = state["dominant_bh_id"]
		active_star_ids[star_id] = true
		if _last_dominant_bh_by_star.has(star_id):
			var previous_bh_id: int = _last_dominant_bh_by_star[star_id]
			if previous_bh_id != dominant_bh_id and previous_bh_id >= 0 and dominant_bh_id >= 0:
				_anchor_switch_count += 1
		_last_dominant_bh_by_star[star_id] = dominant_bh_id

	var known_ids: Array = _last_dominant_bh_by_star.keys()
	for star_id in known_ids:
		if not active_star_ids.has(star_id):
			_last_dominant_bh_by_star.erase(star_id)

func _format_star_anchor_lines(star_anchor_states: Array) -> String:
	if star_anchor_states.is_empty():
		return ""
	var lines: PackedStringArray = []
	for state in star_anchor_states:
		var dominant_text: String = "--" if state["dominant_bh_id"] < 0 else str(state["dominant_bh_id"])
		var secondary_text: String = "--" if state["secondary_bh_id"] < 0 else str(state["secondary_bh_id"])
		var status_text: String = "E<0" if state["negative_specific_energy"] else "E>=0"
		lines.append(
			"Star %d         BH%s>%s  r%.2f %s" % [
				state["star_id"],
				dominant_text,
				secondary_text,
				state["dominance_ratio"],
				status_text,
			]
		)
	return "\n".join(lines) + "\n"

func _update_panel_group_visibility() -> void:
	var has_anchors: bool = _sim != null and not _sim.get_black_holes().is_empty()
	if _stats_panel != null:
		_stats_panel.visible = not _left_panels_collapsed
	if _inspector != null:
		_inspector.visible = not _left_panels_collapsed
	if _start_panel != null:
		_start_panel.visible = not _right_panels_collapsed
	if _right_panel_scroll != null:
		_right_panel_scroll.visible = not _right_panels_collapsed
	if _anchor_panel != null:
		_anchor_panel.visible = has_anchors and not _right_panels_collapsed
	if _anchor_diagnostics_panel != null:
		_anchor_diagnostics_panel.visible = has_anchors and not _right_panels_collapsed
	if _left_toggle_button != null:
		_left_toggle_button.text = ">" if _left_panels_collapsed else "<"
	if _right_toggle_button != null:
		_right_toggle_button.text = "<" if _right_panels_collapsed else ">"
