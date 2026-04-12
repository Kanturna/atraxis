## world_renderer.gd
## Orchestrates all rendering sub-layers.
## Wired to SimWorld signals to add/remove visuals reactively.
## Reads sim state each frame via render_frame(); never writes to simulation.
class_name WorldRenderer
extends Node2D

const GRAVITY_DEBUG_RENDERER_SCRIPT := preload("res://rendering/gravity_debug_renderer.gd")
const CLUSTER_PREVIEW_RENDERER_SCRIPT := preload("res://rendering/cluster_preview_renderer.gd")
const CLUSTER_MARKER_RENDERER_SCRIPT := preload("res://rendering/cluster_marker_renderer.gd")
const REMOTE_CLUSTER_MARKER_CULL_MARGIN_PX: float = 96.0
const REMOTE_CLUSTER_PREVIEW_CULL_MARGIN_PX: float = 96.0
const PREVIEW_LOD_MARKER_ONLY: int = 0
const PREVIEW_LOD_BH_AND_STARS: int = 1
const PREVIEW_LOD_FULL: int = 2
const PREVIEW_LOD_BH_AND_STARS_MAX_SCREEN_RADIUS: float = 32.0
const PREVIEW_LOD_FULL_MIN_SCREEN_RADIUS: float = 72.0

@onready var _zone_layer: Node2D = $ZoneLayer
@onready var _gravity_debug_layer: Node2D = $GravityDebugLayer
@onready var _trail_layer: Node2D = $TrailLayer
@onready var _body_layer: Node2D = $BodyLayer
@onready var _debris_layer: Node2D = $DebrisLayer

var _preview_layer: Node2D = null
var _marker_layer: Node2D = null
var _body_renderer: BodyRenderer
var _trail_renderer: TrailRenderer
var _zone_renderers: Dictionary = {}
var _gravity_debug_renderer: Node2D
var _debris_renderer: DebrisRenderer
var _preview_renderer: Node2D = null
var _cluster_marker_renderer: Node2D = null
var _galaxy_state: GalaxyState = null
var _active_cluster_session: ActiveClusterSession = null
var _worldgen = null
var _debug_overlays_visible: bool = false
var _cached_remote_preview_specs: Array = []
var _cached_marker_payload: Dictionary = {}

func initialize(
		world: SimWorld,
		zones_by_star: Dictionary,
		galaxy_state: GalaxyState = null,
		active_cluster_session: ActiveClusterSession = null) -> void:
	_ensure_overlay_layers()
	_clear_layer(_zone_layer)
	_zone_renderers.clear()
	_clear_layer(_gravity_debug_layer)
	_clear_layer(_trail_layer)
	_clear_layer(_body_layer)
	_clear_layer(_debris_layer)
	_clear_layer(_preview_layer)
	_clear_layer(_marker_layer)
	_galaxy_state = galaxy_state
	_active_cluster_session = active_cluster_session
	_cached_remote_preview_specs = []
	_cached_marker_payload = {}
	_worldgen = GalaxyWorldgen.new(galaxy_state.worldgen_config) \
		if galaxy_state != null and galaxy_state.worldgen_config != null else null

	_body_renderer = BodyRenderer.new()
	_trail_renderer = TrailRenderer.new()
	_gravity_debug_renderer = GRAVITY_DEBUG_RENDERER_SCRIPT.new()
	_debris_renderer = DebrisRenderer.new()
	_preview_renderer = CLUSTER_PREVIEW_RENDERER_SCRIPT.new()
	_cluster_marker_renderer = CLUSTER_MARKER_RENDERER_SCRIPT.new()

	for star_id in zones_by_star:
		var zr := ZoneRenderer.new()
		_zone_layer.add_child(zr)
		zr.setup(zones_by_star[star_id])
		_zone_renderers[star_id] = zr

	_gravity_debug_layer.add_child(_gravity_debug_renderer)
	_trail_layer.add_child(_trail_renderer)
	_preview_layer.add_child(_preview_renderer)
	_body_layer.add_child(_body_renderer)
	_debris_layer.add_child(_debris_renderer)
	_marker_layer.add_child(_cluster_marker_renderer)

	set_debug_overlays_visible(false)

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
	var canvas_scale: float = _debug_marker_canvas_scale()
	var visible_canvas_rect: Rect2 = _visible_canvas_rect()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_cached_remote_preview_specs = build_remote_cluster_preview_specs(
		_galaxy_state,
		_active_cluster_session,
		visible_canvas_rect,
		canvas_scale,
		viewport_size
	)
	_cached_marker_payload = build_registered_cluster_debug_markers(
		_galaxy_state,
		_active_cluster_session,
		visible_canvas_rect,
		canvas_scale
	)
	if _preview_renderer != null:
		_preview_renderer.update_preview_specs(_cached_remote_preview_specs, canvas_scale, visible_canvas_rect)
	if _cluster_marker_renderer != null:
		_cluster_marker_renderer.update_marker_payload(
			_cached_marker_payload,
			canvas_scale,
			visible_canvas_rect
		)
	if _debug_overlays_visible:
		queue_redraw()

func set_debug_overlays_visible(enabled: bool) -> void:
	_debug_overlays_visible = enabled
	if _gravity_debug_renderer != null:
		_gravity_debug_renderer.visible = enabled
	if _cluster_marker_renderer != null:
		_cluster_marker_renderer.visible = enabled
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
	if layer == null:
		return
	for child in layer.get_children():
		child.free()

func _ensure_overlay_layers() -> void:
	if _preview_layer == null:
		_preview_layer = Node2D.new()
		_preview_layer.name = "PreviewLayer"
		add_child(_preview_layer)
		move_child(_preview_layer, _body_layer.get_index())
	if _marker_layer == null:
		_marker_layer = Node2D.new()
		_marker_layer.name = "MarkerLayer"
		add_child(_marker_layer)
		move_child(_marker_layer, get_child_count() - 1)

func _draw() -> void:
	if not _debug_overlays_visible \
			or _galaxy_state == null \
			or _active_cluster_session == null \
			or _worldgen == null:
		return
	_draw_discovered_sectors()

func _draw_discovered_sectors() -> void:
	var active_sector_coord_variant = _active_cluster_session.active_cluster_state.simulation_profile.get(
		"sector_coord",
		Vector2i.ZERO
	) if _active_cluster_session.active_cluster_state != null else Vector2i.ZERO
	var active_sector_coord: Vector2i = active_sector_coord_variant \
		if active_sector_coord_variant is Vector2i \
		else Vector2i.ZERO
	var sector_size_screen: Vector2 = Vector2.ONE * BodyRenderer.sim_dist_to_screen(
		float(_worldgen.config.sector_scale)
	)
	for sector_coord in _galaxy_state.get_discovered_sector_coords():
		var sector_origin_local: Vector2 = _active_cluster_session.to_local(_worldgen.sector_origin(sector_coord))
		var sector_origin_screen: Vector2 = BodyRenderer.snap_screen_point(
			BodyRenderer.sim_to_screen(sector_origin_local)
		)
		var is_active_sector: bool = sector_coord == active_sector_coord
		var sector_color: Color = Color(0.36, 0.56, 0.90, 0.32) if is_active_sector else Color(0.36, 0.56, 0.90, 0.12)
		draw_rect(
			Rect2(sector_origin_screen, sector_size_screen),
			sector_color,
			false,
			1.5 / _debug_marker_canvas_scale() if is_active_sector else 1.0 / _debug_marker_canvas_scale()
		)

func _debug_marker_canvas_scale() -> float:
	var canvas_scale: Vector2 = get_canvas_transform().get_scale()
	return maxf(maxf(absf(canvas_scale.x), absf(canvas_scale.y)), 0.001)

func pick_remote_cluster_at_canvas_position(canvas_position: Vector2) -> Dictionary:
	return pick_remote_cluster_from_payloads(
		_cached_remote_preview_specs,
		_cached_marker_payload,
		_galaxy_state,
		_active_cluster_session,
		canvas_position,
		_debug_marker_canvas_scale()
	)

func _visible_canvas_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2()
	var visible_rect: Rect2 = viewport.get_visible_rect()
	var inverse_canvas: Transform2D = viewport.get_canvas_transform().affine_inverse()
	var corners := [
		inverse_canvas * visible_rect.position,
		inverse_canvas * Vector2(visible_rect.position.x + visible_rect.size.x, visible_rect.position.y),
		inverse_canvas * Vector2(visible_rect.position.x, visible_rect.position.y + visible_rect.size.y),
		inverse_canvas * (visible_rect.position + visible_rect.size),
	]
	var min_x: float = corners[0].x
	var max_x: float = corners[0].x
	var min_y: float = corners[0].y
	var max_y: float = corners[0].y
	for corner in corners:
		min_x = minf(min_x, corner.x)
		max_x = maxf(max_x, corner.x)
		min_y = minf(min_y, corner.y)
		max_y = maxf(max_y, corner.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

static func build_registered_cluster_debug_markers(
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		visible_canvas_rect: Rect2 = Rect2(),
		canvas_scale: float = 1.0) -> Dictionary:
	var markers: Array = []
	var nearest_remote_cluster_id: int = -1
	var nearest_remote_distance: float = INF
	if galaxy_state == null or active_cluster_session == null:
		return {
			"markers": markers,
			"nearest_remote_cluster_id": nearest_remote_cluster_id,
	}
	var safe_canvas_scale: float = maxf(canvas_scale, 0.001)
	var marker_cull_margin: float = REMOTE_CLUSTER_MARKER_CULL_MARGIN_PX / safe_canvas_scale
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state == null:
			continue
		var is_active: bool = cluster_state.cluster_id == active_cluster_session.cluster_id
		var local_center: Vector2 = active_cluster_session.to_local(cluster_state.global_center)
		var marker_center: Vector2 = BodyRenderer.sim_to_screen(local_center)
		var marker_radius_world: float = cluster_debug_marker_world_radius(
			cluster_state.get_authoritative_radius(),
			safe_canvas_scale,
			is_active
		)
		var cluster_radius_canvas: float = BodyRenderer.sim_dist_to_screen(cluster_state.get_authoritative_radius())
		var marker_radius_canvas: float = BodyRenderer.sim_dist_to_screen(marker_radius_world)
		var cull_radius: float = maxf(cluster_radius_canvas, marker_radius_canvas)
		if not _is_cluster_visible_in_canvas_rect(
			marker_center,
			cull_radius,
			visible_canvas_rect,
			marker_cull_margin
		):
			continue
		markers.append({
			"cluster_id": cluster_state.cluster_id,
			"local_center": local_center,
			"radius": cluster_state.get_authoritative_radius(),
			"is_active": is_active,
			"state": activation_state_debug_name(cluster_state.activation_state),
			"color": cluster_debug_color(cluster_state.activation_state),
		})
		if not is_active:
			var center_distance: float = local_center.length()
			if center_distance < nearest_remote_distance:
				nearest_remote_distance = center_distance
				nearest_remote_cluster_id = cluster_state.cluster_id
	for marker in markers:
		var marker_cluster_id: int = int(marker.get("cluster_id", -1))
		var marker_state: String = str(marker.get("state", ""))
		var label_prefix: String = ""
		if bool(marker.get("is_active", false)):
			label_prefix = "ACTIVE"
		elif marker_cluster_id == nearest_remote_cluster_id:
			label_prefix = "PREVIEW" if marker_state == "simplified" else "UNLOADED"
		marker["label_prefix"] = label_prefix
	return {
		"markers": markers,
		"nearest_remote_cluster_id": nearest_remote_cluster_id,
	}

static func build_remote_cluster_preview_specs(
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		visible_canvas_rect: Rect2 = Rect2(),
		canvas_scale: float = 1.0,
		viewport_size: Vector2 = Vector2.ZERO) -> Array:
	var preview_specs: Array = []
	if galaxy_state == null or active_cluster_session == null:
		return preview_specs
	var safe_canvas_scale: float = maxf(canvas_scale, 0.001)
	var preview_cull_margin: float = REMOTE_CLUSTER_PREVIEW_CULL_MARGIN_PX / safe_canvas_scale
	for cluster_state in galaxy_state.get_clusters():
		if cluster_state == null or cluster_state.cluster_id == active_cluster_session.cluster_id:
			continue
		var local_center: Vector2 = active_cluster_session.to_local(cluster_state.global_center)
		var cluster_center_canvas: Vector2 = BodyRenderer.sim_to_screen(local_center)
		var cluster_radius_canvas: float = BodyRenderer.sim_dist_to_screen(cluster_state.get_authoritative_radius())
		if not _is_cluster_visible_in_canvas_rect(
			cluster_center_canvas,
			cluster_radius_canvas,
			visible_canvas_rect,
			preview_cull_margin
		):
			continue
		var cluster_screen_radius: float = _cluster_canvas_radius_to_screen_radius(
			cluster_radius_canvas,
			visible_canvas_rect,
			viewport_size
		)
		var preview_lod: int = cluster_preview_lod_for_screen_radius(cluster_screen_radius)
		if preview_lod == PREVIEW_LOD_MARKER_ONLY:
			continue
		var source_specs: Array = _remote_cluster_preview_source_specs(cluster_state, preview_lod)
		for source_spec in source_specs:
			var source_local_position: Vector2 = Vector2(source_spec.get("local_position", Vector2.ZERO))
			var source_global_position: Vector2 = cluster_state.global_center + source_local_position
			var local_position: Vector2 = active_cluster_session.to_local(source_global_position)
			var preview_spec: Dictionary = {
				"object_id": str(source_spec.get("object_id", "")),
				"kind": str(source_spec.get("kind", "")),
				"body_type": int(source_spec.get("body_type", SimBody.BodyType.ASTEROID)),
				"material_type": int(source_spec.get("material_type", SimBody.MaterialType.MIXED)),
				"local_position": local_position,
				"radius": float(source_spec.get("radius", 1.0)),
				"seed": int(source_spec.get("seed", 0)),
				"cluster_id": cluster_state.cluster_id,
				"state": activation_state_debug_name(cluster_state.activation_state),
				"preview_lod": preview_lod,
			}
			preview_specs.append(preview_spec)
	return preview_specs

static func pick_remote_cluster_from_payloads(
		preview_specs: Array,
		marker_payload: Dictionary,
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		canvas_position: Vector2,
		canvas_scale: float = 1.0) -> Dictionary:
	var preview_hit: Dictionary = _pick_remote_cluster_from_preview_specs(
		preview_specs,
		galaxy_state,
		active_cluster_session,
		canvas_position,
		canvas_scale
	)
	if not preview_hit.is_empty():
		return preview_hit
	return _pick_remote_cluster_from_marker_payload(
		marker_payload,
		galaxy_state,
		active_cluster_session,
		canvas_position,
		canvas_scale
	)

static func _pick_remote_cluster_from_preview_specs(
		preview_specs: Array,
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		canvas_position: Vector2,
		canvas_scale: float) -> Dictionary:
	if galaxy_state == null or active_cluster_session == null:
		return {}
	var safe_canvas_scale: float = maxf(canvas_scale, 0.001)
	var best_spec: Dictionary = {}
	var best_distance_sq: float = INF
	for preview_spec in preview_specs:
		var cluster_id: int = int(preview_spec.get("cluster_id", -1))
		if cluster_id < 0 or cluster_id == active_cluster_session.cluster_id:
			continue
		var body_type: int = int(preview_spec.get("body_type", SimBody.BodyType.ASTEROID))
		var body_radius: float = float(preview_spec.get("radius", 1.0))
		var preview_position: Vector2 = BodyRenderer.sim_to_screen(
			Vector2(preview_spec.get("local_position", Vector2.ZERO))
		)
		var preview_radius: float = maxf(
			BodyRenderer.screen_radius_for_body_traits(body_type, body_radius),
			10.0 / safe_canvas_scale
		)
		var distance_sq: float = preview_position.distance_squared_to(canvas_position)
		if distance_sq > preview_radius * preview_radius or distance_sq >= best_distance_sq:
			continue
		best_distance_sq = distance_sq
		best_spec = preview_spec
	if best_spec.is_empty():
		return {}
	return _remote_cluster_pick_result(
		galaxy_state,
		active_cluster_session,
		int(best_spec.get("cluster_id", -1)),
		canvas_position
	)

static func _pick_remote_cluster_from_marker_payload(
		marker_payload: Dictionary,
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		canvas_position: Vector2,
		canvas_scale: float) -> Dictionary:
	if galaxy_state == null or active_cluster_session == null:
		return {}
	var safe_canvas_scale: float = maxf(canvas_scale, 0.001)
	var best_marker: Dictionary = {}
	var best_distance_sq: float = INF
	for marker in marker_payload.get("markers", []):
		if bool(marker.get("is_active", false)):
			continue
		var marker_position: Vector2 = BodyRenderer.sim_to_screen(
			Vector2(marker.get("local_center", Vector2.ZERO))
		)
		var marker_radius_world: float = cluster_debug_marker_world_radius(
			float(marker.get("radius", 0.0)),
			safe_canvas_scale,
			false
		)
		var marker_radius: float = maxf(
			BodyRenderer.sim_dist_to_screen(marker_radius_world),
			12.0 / safe_canvas_scale
		)
		var distance_sq: float = marker_position.distance_squared_to(canvas_position)
		if distance_sq > marker_radius * marker_radius or distance_sq >= best_distance_sq:
			continue
		best_distance_sq = distance_sq
		best_marker = marker
	if best_marker.is_empty():
		return {}
	return _remote_cluster_pick_result(
		galaxy_state,
		active_cluster_session,
		int(best_marker.get("cluster_id", -1)),
		canvas_position
	)

static func _remote_cluster_pick_result(
		galaxy_state: GalaxyState,
		active_cluster_session: ActiveClusterSession,
		cluster_id: int,
		canvas_position: Vector2 = Vector2.ZERO) -> Dictionary:
	if galaxy_state == null or active_cluster_session == null or cluster_id < 0:
		return {}
	var cluster_state: ClusterState = galaxy_state.get_cluster(cluster_id)
	if cluster_state == null or cluster_id == active_cluster_session.cluster_id:
		return {}
	var clicked_local_focus_position: Vector2 = canvas_position / max(SimConstants.SIM_TO_SCREEN, 0.001)
	return {
		"cluster_id": cluster_id,
		"global_center": cluster_state.global_center,
		"clicked_global_focus_position": active_cluster_session.to_global(clicked_local_focus_position),
		"local_center": active_cluster_session.to_local(cluster_state.global_center),
		"authoritative_radius": cluster_state.get_authoritative_radius(),
		"state": activation_state_debug_name(cluster_state.activation_state),
	}

static func _remote_cluster_preview_source_specs(
		cluster_state: ClusterState,
		preview_lod: int = PREVIEW_LOD_FULL) -> Array:
	var preview_specs: Array = []
	if cluster_state == null:
		return preview_specs
	var use_runtime_snapshot: bool = cluster_state.activation_state == ClusterActivationState.State.SIMPLIFIED \
		and bool(cluster_state.simulation_profile.get("has_runtime_snapshot", false))
	if use_runtime_snapshot:
		for object_state in cluster_state.object_registry.values():
			if object_state == null or object_state.residency_state == ObjectResidencyState.State.IN_TRANSIT:
				continue
			var body_type: int = int(object_state.descriptor.get("body_type", -1))
			if body_type not in [
				SimBody.BodyType.BLACK_HOLE,
				SimBody.BodyType.STAR,
				SimBody.BodyType.PLANET,
			]:
				continue
			if not _preview_body_type_allowed_in_lod(body_type, preview_lod):
				continue
			preview_specs.append(_make_preview_source_spec(
				object_state.object_id,
				object_state.kind,
				body_type,
				int(object_state.descriptor.get("material_type", SimBody.MaterialType.MIXED)),
				object_state.local_position,
				float(object_state.descriptor.get("radius", 1.0)),
				int(object_state.seed)
			))
		# step_simplified_cluster() sets has_runtime_snapshot=true after the first BH-only
		# step, before the cluster has ever been ACTIVE. In that case the registry only
		# holds BHs; supplement with blueprint preview specs for stars/planets so distant
		# clusters show their full content even before they have been visited.
		var registry_has_stars_or_planets: bool = false
		for spec in preview_specs:
			if int(spec.get("body_type", -1)) != SimBody.BodyType.BLACK_HOLE:
				registry_has_stars_or_planets = true
				break
		if not registry_has_stars_or_planets:
			for source_spec in cluster_state.cluster_blueprint.get("preview_object_specs", []):
				var bt: int = int(source_spec.get("body_type", -1))
				if bt == SimBody.BodyType.BLACK_HOLE:
					continue  # BH already present from registry with live positions
				if bt not in [SimBody.BodyType.STAR, SimBody.BodyType.PLANET]:
					continue
				if not _preview_body_type_allowed_in_lod(bt, preview_lod):
					continue
				preview_specs.append(_copy_preview_source_spec(source_spec))
		return preview_specs
	for source_spec in cluster_state.cluster_blueprint.get("preview_object_specs", []):
		var body_type: int = int(source_spec.get("body_type", -1))
		if body_type not in [
			SimBody.BodyType.BLACK_HOLE,
			SimBody.BodyType.STAR,
			SimBody.BodyType.PLANET,
		]:
			continue
		if not _preview_body_type_allowed_in_lod(body_type, preview_lod):
			continue
		preview_specs.append(_copy_preview_source_spec(source_spec))
	return preview_specs

static func cluster_preview_lod_for_screen_radius(cluster_screen_radius: float) -> int:
	if cluster_screen_radius < PREVIEW_LOD_BH_AND_STARS_MAX_SCREEN_RADIUS:
		return PREVIEW_LOD_MARKER_ONLY
	if cluster_screen_radius < PREVIEW_LOD_FULL_MIN_SCREEN_RADIUS:
		return PREVIEW_LOD_BH_AND_STARS
	return PREVIEW_LOD_FULL

static func _preview_body_type_allowed_in_lod(body_type: int, preview_lod: int) -> bool:
	if body_type == SimBody.BodyType.BLACK_HOLE:
		return true
	if preview_lod == PREVIEW_LOD_FULL:
		return body_type in [SimBody.BodyType.STAR, SimBody.BodyType.PLANET]
	if preview_lod == PREVIEW_LOD_BH_AND_STARS:
		return body_type == SimBody.BodyType.STAR
	return false

static func _copy_preview_source_spec(source_spec: Dictionary) -> Dictionary:
	return _make_preview_source_spec(
		str(source_spec.get("object_id", "")),
		str(source_spec.get("kind", "")),
		int(source_spec.get("body_type", SimBody.BodyType.ASTEROID)),
		int(source_spec.get("material_type", SimBody.MaterialType.MIXED)),
		Vector2(source_spec.get("local_position", Vector2.ZERO)),
		float(source_spec.get("radius", 1.0)),
		int(source_spec.get("seed", 0))
	)

static func _make_preview_source_spec(
		object_id: String,
		kind: String,
		body_type: int,
		material_type: int,
		local_position: Vector2,
		radius: float,
		seed: int) -> Dictionary:
	return {
		"object_id": object_id,
		"kind": kind,
		"body_type": body_type,
		"material_type": material_type,
		"local_position": local_position,
		"radius": radius,
		"seed": seed,
	}

static func _is_cluster_visible_in_canvas_rect(
		local_center: Vector2,
		radius: float,
		visible_canvas_rect: Rect2,
		extra_margin: float = 0.0) -> bool:
	if not visible_canvas_rect.has_area():
		return true
	var extent: float = maxf(radius, 0.0) + maxf(extra_margin, 0.0)
	var cluster_rect := Rect2(
		local_center - Vector2.ONE * extent,
		Vector2.ONE * extent * 2.0
	)
	return visible_canvas_rect.intersects(cluster_rect)

static func _cluster_canvas_radius_to_screen_radius(
		cluster_canvas_radius: float,
		visible_canvas_rect: Rect2,
		viewport_size: Vector2) -> float:
	if cluster_canvas_radius <= 0.0:
		return 0.0
	if not visible_canvas_rect.has_area() or viewport_size == Vector2.ZERO:
		return cluster_canvas_radius
	var px_per_canvas_x: float = viewport_size.x / maxf(visible_canvas_rect.size.x, 0.001)
	var px_per_canvas_y: float = viewport_size.y / maxf(visible_canvas_rect.size.y, 0.001)
	return cluster_canvas_radius * maxf(px_per_canvas_x, px_per_canvas_y)

static func cluster_debug_marker_world_radius(
		cluster_radius: float,
		canvas_scale: float,
		is_active: bool = false) -> float:
	var safe_canvas_scale: float = maxf(canvas_scale, 0.001)
	var min_marker_radius: float = (4.0 if is_active else 3.0) / safe_canvas_scale
	var target_marker_radius: float = (11.0 if is_active else 8.0) / safe_canvas_scale
	var max_marker_radius: float = maxf(
		cluster_radius * (0.09 if is_active else 0.06),
		min_marker_radius
	)
	return clampf(target_marker_radius, min_marker_radius, max_marker_radius)

static func should_draw_cluster_extent_ring(cluster_screen_radius: float, viewport_diagonal: float) -> bool:
	if cluster_screen_radius < 0.5:
		return false
	if viewport_diagonal <= 0.0:
		return true
	return cluster_screen_radius <= viewport_diagonal * 1.5

static func activation_state_debug_name(activation_state: int) -> String:
	match activation_state:
		ClusterActivationState.State.ACTIVE:
			return "active"
		ClusterActivationState.State.SIMPLIFIED:
			return "simplified"
		_:
			return "unloaded"

static func cluster_debug_color(activation_state: int) -> Color:
	match activation_state:
		ClusterActivationState.State.ACTIVE:
			return Color(0.98, 0.90, 0.34, 0.82)
		ClusterActivationState.State.SIMPLIFIED:
			return Color(0.36, 0.92, 0.86, 0.60)
		_:
			return Color(0.86, 0.89, 0.98, 0.44)
