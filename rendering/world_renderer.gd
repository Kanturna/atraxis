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
var _zone_renderers: Dictionary = {}
var _gravity_debug_renderer: Node2D
var _debris_renderer: DebrisRenderer
var _galaxy_state: GalaxyState = null
var _active_cluster_session: ActiveClusterSession = null
var _worldgen = null
var _debug_overlays_visible: bool = false

func initialize(
		world: SimWorld,
		zones_by_star: Dictionary,
		galaxy_state: GalaxyState = null,
		active_cluster_session: ActiveClusterSession = null) -> void:
	_clear_layer(_zone_layer)
	_zone_renderers.clear()
	_clear_layer(_gravity_debug_layer)
	_clear_layer(_trail_layer)
	_clear_layer(_body_layer)
	_clear_layer(_debris_layer)
	_galaxy_state = galaxy_state
	_active_cluster_session = active_cluster_session
	_worldgen = GalaxyWorldgen.new(galaxy_state.worldgen_config) \
		if galaxy_state != null and galaxy_state.worldgen_config != null else null

	_body_renderer = BodyRenderer.new()
	_trail_renderer = TrailRenderer.new()
	_gravity_debug_renderer = GRAVITY_DEBUG_RENDERER_SCRIPT.new()
	_debris_renderer = DebrisRenderer.new()

	for star_id in zones_by_star:
		var zr := ZoneRenderer.new()
		_zone_layer.add_child(zr)
		zr.setup(zones_by_star[star_id])
		_zone_renderers[star_id] = zr

	_gravity_debug_layer.add_child(_gravity_debug_renderer)
	_trail_layer.add_child(_trail_renderer)
	_body_layer.add_child(_body_renderer)
	_debris_layer.add_child(_debris_renderer)

	set_debug_overlays_visible(false)

	# Create visuals for bodies already in the world
	for body in world.bodies:
		_on_body_added(body)

func render_frame(world: SimWorld) -> void:
	for star_id in _zone_renderers:
		var star: SimBody = world.get_body_by_id(star_id)
		_zone_renderers[star_id].update_for_star(star)
	if _gravity_debug_renderer != null:
		_gravity_debug_renderer.update_all(world.bodies)
	if _body_renderer != null:
		_body_renderer.update_all(world.bodies)
	if _trail_renderer != null:
		_trail_renderer.update_all(world.bodies)
	if _debris_renderer != null:
		_debris_renderer.update_all(world.debris_fields)
	if _debug_overlays_visible:
		queue_redraw()

func set_debug_overlays_visible(enabled: bool) -> void:
	_debug_overlays_visible = enabled
	if _gravity_debug_renderer != null:
		_gravity_debug_renderer.visible = enabled
	queue_redraw()

func set_gravity_debug_visible(enabled: bool) -> void:
	set_debug_overlays_visible(enabled)

func _on_body_added(body: SimBody) -> void:
	_body_renderer.add_body_visual(body)
	_trail_renderer.add_trail(body)

func _on_body_removed(body_id: int) -> void:
	_body_renderer.remove_body_visual(body_id)
	_trail_renderer.remove_trail(body_id)

func _clear_layer(layer: Node2D) -> void:
	for child in layer.get_children():
		child.free()

func _draw() -> void:
	if not _debug_overlays_visible \
			or _galaxy_state == null \
			or _active_cluster_session == null \
			or _worldgen == null:
		return
	_draw_discovered_sectors()
	_draw_registered_clusters()

func _draw_discovered_sectors() -> void:
	var active_sector_coord_variant = _active_cluster_session.active_cluster_state.simulation_profile.get(
		"sector_coord",
		Vector2i.ZERO
	) if _active_cluster_session.active_cluster_state != null else Vector2i.ZERO
	var active_sector_coord: Vector2i = active_sector_coord_variant \
		if active_sector_coord_variant is Vector2i \
		else Vector2i.ZERO
	var sector_size := Vector2.ONE * _worldgen.config.sector_scale
	for sector_coord in _galaxy_state.get_discovered_sector_coords():
		var sector_origin_local: Vector2 = _active_cluster_session.to_local(_worldgen.sector_origin(sector_coord))
		var is_active_sector: bool = sector_coord == active_sector_coord
		var sector_color: Color = Color(0.36, 0.56, 0.90, 0.32) if is_active_sector else Color(0.36, 0.56, 0.90, 0.12)
		draw_rect(Rect2(sector_origin_local, sector_size), sector_color, false, 1.5 if is_active_sector else 1.0)

func _draw_registered_clusters() -> void:
	var nearest_remote_cluster: ClusterState = null
	var nearest_remote_distance: float = INF
	for cluster_state in _galaxy_state.get_clusters():
		if cluster_state == null:
			continue
		var cluster_local_center: Vector2 = _active_cluster_session.to_local(cluster_state.global_center)
		var cluster_color: Color = _cluster_debug_color(cluster_state)
		var line_width: float = 2.4 if cluster_state.cluster_id == _active_cluster_session.cluster_id else 1.4
		draw_arc(
			cluster_local_center,
			cluster_state.get_authoritative_radius(),
			0.0,
			TAU,
			64,
			cluster_color,
			line_width
		)
		draw_circle(
			cluster_local_center,
			7.0 if cluster_state.cluster_id == _active_cluster_session.cluster_id else 4.0,
			cluster_color
		)
		if cluster_state.cluster_id != _active_cluster_session.cluster_id:
			var center_distance: float = cluster_local_center.length()
			if center_distance < nearest_remote_distance:
				nearest_remote_distance = center_distance
				nearest_remote_cluster = cluster_state
	_draw_cluster_label(_active_cluster_session.active_cluster_state, "ACTIVE")
	if nearest_remote_cluster != null:
		_draw_cluster_label(nearest_remote_cluster, "GHOST")

func _draw_cluster_label(cluster_state: ClusterState, label_prefix: String) -> void:
	if cluster_state == null or ThemeDB.fallback_font == null:
		return
	var label_position: Vector2 = _active_cluster_session.to_local(cluster_state.global_center)
	label_position += Vector2(12.0, -10.0)
	draw_string(
		ThemeDB.fallback_font,
		label_position,
		"%s C%d" % [label_prefix, cluster_state.cluster_id],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		ThemeDB.fallback_font_size,
		_cluster_debug_color(cluster_state)
	)

func _cluster_debug_color(cluster_state: ClusterState) -> Color:
	if cluster_state == null:
		return Color(1.0, 1.0, 1.0, 0.3)
	match cluster_state.activation_state:
		ClusterActivationState.State.ACTIVE:
			return Color(0.98, 0.90, 0.34, 0.72)
		ClusterActivationState.State.SIMPLIFIED:
			return Color(0.36, 0.92, 0.86, 0.46)
		_:
			return Color(0.86, 0.89, 0.98, 0.26)
