## hud.gd
## Minimal heads-up display: elapsed time, body counts, time-scale slider.
class_name HUD
extends CanvasLayer

var _sim: SimWorld = null

@onready var _time_label: Label       = $Panel/VBox/TimeLabel
@onready var _count_label: Label      = $Panel/VBox/CountLabel
@onready var _scale_label: Label      = $Panel/VBox/ScaleLabel
@onready var _scale_slider: HSlider   = $Panel/VBox/ScaleSlider

func initialize(world: SimWorld) -> void:
	_sim = world
	_scale_slider.min_value = SimConstants.MIN_TIME_SCALE
	_scale_slider.max_value = SimConstants.MAX_TIME_SCALE
	_scale_slider.value = 1.0
	_scale_slider.value_changed.connect(_on_scale_changed)

func update_display(world: SimWorld) -> void:
	if _time_label == null:
		return
	var days: float = world.time_elapsed / 86400.0
	_time_label.text = "T+ %.1f days" % days
	_count_label.text = "Bodies: %d  (sleep: %d)  Debris: %d" % [
		world.get_active_body_count(),
		world.get_sleeping_body_count(),
		world.get_active_debris_count()
	]
	_scale_label.text = "Speed: x%.0f" % world.time_scale

func _on_scale_changed(value: float) -> void:
	if _sim:
		_sim.time_scale = value
