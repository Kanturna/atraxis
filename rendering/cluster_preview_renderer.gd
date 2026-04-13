## Draws dimmed read-only previews for non-active remote clusters.
class_name ClusterPreviewRenderer
extends Node2D

var _preview_specs: Array = []
var _canvas_scale: float = 1.0
var _visible_canvas_rect: Rect2 = Rect2()

## Minimum on-screen pixel sizes for preview bodies (matches marker-renderer convention).
const MIN_PREVIEW_SCREEN_PX_STAR: float = 4.0
const MIN_PREVIEW_SCREEN_PX_BH: float = 3.5
const MIN_PREVIEW_SCREEN_PX_PLANET: float = 2.5

func update_preview_specs(
		preview_specs: Array,
		canvas_scale: float = 1.0,
		visible_canvas_rect: Rect2 = Rect2()) -> void:
	_preview_specs = preview_specs
	_canvas_scale = maxf(canvas_scale, 0.001)
	_visible_canvas_rect = visible_canvas_rect
	queue_redraw()

func _draw() -> void:
	_draw_cluster_accents()
	for spec in _preview_specs:
		var body_type: int = int(spec.get("body_type", SimBody.BodyType.ASTEROID))
		var body_radius: float = float(spec.get("radius", 1.0))
		var visual_profile: Dictionary = preview_visual_profile(spec)
		var screen_position: Vector2 = BodyRenderer.sim_to_screen(
			Vector2(spec.get("local_position", Vector2.ZERO))
		)
		var min_px: float = _min_preview_screen_px(body_type) / _canvas_scale
		var screen_radius: float = maxf(
			BodyRenderer.screen_radius_for_body_traits(body_type, body_radius),
			min_px
		) * float(visual_profile.get("radius_scale", 1.0))
		if not _is_preview_body_visible(screen_position, screen_radius):
			continue
		var color: Color = _preview_color(spec)
		color.a *= float(visual_profile.get("alpha_scale", 1.0))
		match body_type:
			SimBody.BodyType.BLACK_HOLE:
				_draw_black_hole_preview(screen_position, screen_radius, color)
			SimBody.BodyType.STAR:
				draw_circle(screen_position, screen_radius, color)
				if bool(visual_profile.get("draw_star_halo", true)):
					draw_arc(
						screen_position,
						screen_radius * 1.12,
						0.0,
						TAU,
						48,
						Color(
							color.r,
							color.g,
							color.b,
							minf(
								(color.a + 0.08) * float(visual_profile.get("halo_alpha_scale", 1.0)),
								0.5
							)
						),
						1.5
					)
			_:
				draw_circle(screen_position, screen_radius, color)

func _draw_cluster_accents() -> void:
	var drawn_cluster_ids: Dictionary = {}
	for spec in _preview_specs:
		var cluster_id: int = int(spec.get("cluster_id", -1))
		if cluster_id < 0 or drawn_cluster_ids.has(cluster_id):
			continue
		drawn_cluster_ids[cluster_id] = true
		var cluster_center: Vector2 = BodyRenderer.sim_to_screen(
			Vector2(spec.get("cluster_local_center", Vector2.ZERO))
		)
		var cluster_radius: float = maxf(
			BodyRenderer.sim_dist_to_screen(float(spec.get("cluster_radius", 0.0))),
			18.0 / _canvas_scale
		)
		var macro_sector_zone: String = str(spec.get("macro_sector_zone", "outside"))
		var accent_profile: Dictionary = cluster_accent_profile(macro_sector_zone)
		var accent_radius: float = cluster_radius * float(accent_profile.get("radius_scale", 0.5))
		if not _is_preview_body_visible(cluster_center, accent_radius):
			continue
		var accent_color: Color = cluster_accent_color(macro_sector_zone)
		var fill_alpha: float = float(accent_profile.get("fill_alpha", 0.0))
		var ring_alpha: float = float(accent_profile.get("ring_alpha", 0.0))
		if fill_alpha > 0.0:
			draw_circle(
				cluster_center,
				accent_radius,
				Color(accent_color.r, accent_color.g, accent_color.b, fill_alpha)
			)
		if ring_alpha > 0.0:
			draw_arc(
				cluster_center,
				accent_radius,
				0.0,
				TAU,
				56,
				Color(accent_color.r, accent_color.g, accent_color.b, ring_alpha),
				maxf(float(accent_profile.get("ring_width", 1.0)) / _canvas_scale, 0.9 / _canvas_scale)
			)

func _draw_black_hole_preview(screen_position: Vector2, screen_radius: float, color: Color) -> void:
	draw_circle(
		screen_position,
		screen_radius * 1.24,
		Color(color.r, color.g, color.b, color.a * 0.28)
	)
	draw_circle(screen_position, screen_radius, Color(0.90, 0.95, 1.0, 0.24))
	draw_circle(screen_position, screen_radius * 0.56, Color(0.04, 0.04, 0.08, 0.84))
	draw_arc(
		screen_position,
		screen_radius * 1.06,
		0.0,
		TAU,
		48,
		Color(0.92, 0.96, 1.0, 0.26),
		1.4
	)

func _preview_color(spec: Dictionary) -> Color:
	var body_type: int = int(spec.get("body_type", SimBody.BodyType.ASTEROID))
	var material_type: int = int(spec.get("material_type", SimBody.MaterialType.MIXED))
	var macro_sector_zone: String = str(spec.get("macro_sector_zone", "outside"))
	match body_type:
		SimBody.BodyType.BLACK_HOLE:
			if macro_sector_zone == "outside":
				return Color(0.74, 0.78, 0.86, 0.34)
			if macro_sector_zone == "far":
				return Color(0.84, 0.90, 1.0, 0.44)
			return Color(0.92, 0.97, 1.0, 0.58)
		SimBody.BodyType.STAR:
			if macro_sector_zone == "outside":
				return Color(0.74, 0.78, 0.84, 0.34)
			if macro_sector_zone == "far":
				return Color(0.84, 0.90, 1.0, 0.46)
			return Color(1.0, 0.94, 0.58, 0.68)
		SimBody.BodyType.PLANET:
			match material_type:
				SimBody.MaterialType.ROCKY:
					return Color(0.72, 0.58, 0.44, 0.45)
				SimBody.MaterialType.ICY:
					return Color(0.74, 0.90, 1.0, 0.45)
				SimBody.MaterialType.METALLIC:
					return Color(0.72, 0.76, 0.82, 0.45)
				_:
					return Color(0.68, 0.68, 0.78, 0.45)
		_:
			return Color(0.70, 0.72, 0.78, 0.35)

static func preview_visual_profile(spec: Dictionary) -> Dictionary:
	var body_type: int = int(spec.get("body_type", SimBody.BodyType.ASTEROID))
	var macro_sector_zone: String = str(spec.get("macro_sector_zone", "outside"))
	var profile := {
		"radius_scale": 1.0,
		"alpha_scale": 1.0,
		"draw_star_halo": body_type == SimBody.BodyType.STAR,
		"halo_alpha_scale": 1.0,
	}
	if macro_sector_zone == "ambient":
		match body_type:
			SimBody.BodyType.BLACK_HOLE:
				profile["alpha_scale"] = 1.08
			SimBody.BodyType.STAR:
				profile["radius_scale"] = 1.08
				profile["alpha_scale"] = 1.10
				profile["halo_alpha_scale"] = 1.25
			SimBody.BodyType.PLANET:
				profile["alpha_scale"] = 1.14
	elif macro_sector_zone == "far":
		match body_type:
			SimBody.BodyType.BLACK_HOLE:
				profile["alpha_scale"] = 0.95
			SimBody.BodyType.STAR:
				profile["radius_scale"] = 0.74
				profile["alpha_scale"] = 0.56
				profile["draw_star_halo"] = false
				profile["halo_alpha_scale"] = 0.0
	elif macro_sector_zone == "outside":
		match body_type:
			SimBody.BodyType.BLACK_HOLE:
				profile["alpha_scale"] = 0.62
			SimBody.BodyType.STAR:
				profile["radius_scale"] = 0.86
				profile["alpha_scale"] = 0.44
				profile["draw_star_halo"] = false
				profile["halo_alpha_scale"] = 0.0
			SimBody.BodyType.PLANET:
				profile["alpha_scale"] = 0.58
	return profile

static func cluster_accent_color(macro_sector_zone: String) -> Color:
	match macro_sector_zone:
		"ambient":
			return Color(0.32, 0.92, 0.78, 1.0)
		"far":
			return Color(0.56, 0.78, 1.0, 1.0)
		_:
			return Color(0.72, 0.76, 0.82, 1.0)

static func cluster_accent_profile(macro_sector_zone: String) -> Dictionary:
	match macro_sector_zone:
		"ambient":
			return {
				"radius_scale": 0.84,
				"fill_alpha": 0.090,
				"ring_alpha": 0.22,
				"ring_width": 1.8,
			}
		"far":
			return {
				"radius_scale": 0.62,
				"fill_alpha": 0.045,
				"ring_alpha": 0.16,
				"ring_width": 1.1,
			}
		_:
			return {
				"radius_scale": 0.48,
				"fill_alpha": 0.018,
				"ring_alpha": 0.08,
				"ring_width": 0.9,
			}

static func _min_preview_screen_px(body_type: int) -> float:
	match body_type:
		SimBody.BodyType.STAR:
			return MIN_PREVIEW_SCREEN_PX_STAR
		SimBody.BodyType.BLACK_HOLE:
			return MIN_PREVIEW_SCREEN_PX_BH
		_:
			return MIN_PREVIEW_SCREEN_PX_PLANET

func _is_preview_body_visible(screen_position: Vector2, screen_radius: float) -> bool:
	if not _visible_canvas_rect.has_area():
		return true
	var extent: float = screen_radius + (12.0 / _canvas_scale)
	var preview_rect := Rect2(
		screen_position - Vector2.ONE * extent,
		Vector2.ONE * extent * 2.0
	)
	return _visible_canvas_rect.intersects(preview_rect)
