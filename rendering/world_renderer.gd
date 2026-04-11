## world_renderer.gd
## Orchestrates all rendering sub-layers.
## Wired to SimWorld signals to add/remove visuals reactively.
## Reads sim state each frame via render_frame(); never writes to simulation.
class_name WorldRenderer
extends Node2D

const GRAVITY_DEBUG_RENDERER_SCRIPT := preload("res://rendering/gravity_debug_renderer.gd")

@onready var _zone_layer: Node2D = $ZoneLayer
@onready var _gravity_debug_layer: Node2D = $GravityDebugLayer
@onready var _trail_layer: Node2D = $TrailLayer
@onready var _body_layer: Node2D = $BodyLayer
@onready var _debris_layer: Node2D = $DebrisLayer

var _body_renderer: BodyRenderer
var _trail_renderer: TrailRenderer
var _zone_renderer: ZoneRenderer
var _gravity_debug_renderer: Node2D
var _debris_renderer: DebrisRenderer

func initialize(world: SimWorld, zones: WorldBuilder.ZoneBoundaries) -> void:
	_clear_layer(_zone_layer)
	_clear_layer(_gravity_debug_layer)
	_clear_layer(_trail_layer)
	_clear_layer(_body_layer)
	_clear_layer(_debris_layer)

	_body_renderer = BodyRenderer.new()
	_trail_renderer = TrailRenderer.new()
	_zone_renderer = ZoneRenderer.new()
	_gravity_debug_renderer = GRAVITY_DEBUG_RENDERER_SCRIPT.new()
	_debris_renderer = DebrisRenderer.new()

	_zone_layer.add_child(_zone_renderer)
	_gravity_debug_layer.add_child(_gravity_debug_renderer)
	_trail_layer.add_child(_trail_renderer)
	_body_layer.add_child(_body_renderer)
	_debris_layer.add_child(_debris_renderer)

	_zone_renderer.setup(zones)
	set_gravity_debug_visible(false)

	# Create visuals for bodies already in the world
	for body in world.bodies:
		_on_body_added(body)

func render_frame(world: SimWorld) -> void:
	if _gravity_debug_renderer != null:
		_gravity_debug_renderer.update_all(world.bodies)
	if _body_renderer != null:
		_body_renderer.update_all(world.bodies)
	if _trail_renderer != null:
		_trail_renderer.update_all(world.bodies)
	if _debris_renderer != null:
		_debris_renderer.update_all(world.debris_fields)

func set_gravity_debug_visible(enabled: bool) -> void:
	if _gravity_debug_renderer != null:
		_gravity_debug_renderer.visible = enabled

func _on_body_added(body: SimBody) -> void:
	_body_renderer.add_body_visual(body)
	_trail_renderer.add_trail(body)

func _on_body_removed(body_id: int) -> void:
	_body_renderer.remove_body_visual(body_id)
	_trail_renderer.remove_trail(body_id)

func _clear_layer(layer: Node2D) -> void:
	for child in layer.get_children():
		child.free()
