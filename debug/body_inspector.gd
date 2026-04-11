## body_inspector.gd
## Simple label panel showing live data for a selected SimBody.
class_name BodyInspector
extends PanelContainer

@onready var _label: RichTextLabel = $RichTextLabel

func display_body(body: SimBody) -> void:
	if body == null:
		_label.text = "[i]No body selected[/i]"
		return
	_update_label(body)

func update_display(body: SimBody) -> void:
	if body == null or not body.active:
		_label.text = "[i]Body gone[/i]"
		return
	_update_label(body)

func _update_label(body: SimBody) -> void:
	var type_name: String = _type_str(body.body_type)
	var mat_name: String  = _mat_str(body.material_type)
	var level_name: String = ["A", "B", "C"][body.influence_level]

	_label.text = (
		"[b]%s[/b]  (id %d)\n" % [type_name, body.id] +
		"Level: %s  kinematic: %s\n" % [level_name, str(body.kinematic)] +
		"Mass:  %.2f\n" % body.mass +
		"Rad:   %.2f\n" % body.radius +
		"Pos:   (%.1f, %.1f)\n" % [body.position.x, body.position.y] +
		"Vel:   (%.2f, %.2f)  |v|=%.2f\n" % [body.velocity.x, body.velocity.y, body.velocity.length()] +
		"Temp:  %.1f K\n" % body.temperature +
		"Age:   %.1f s\n" % body.age +
		"Mat:   %s\n" % mat_name +
		"Sleep: %s\n" % str(body.sleeping) +
		"Debris mass: %.2f" % body.debris_mass
	)

static func _type_str(t: int) -> String:
	match t:
		SimBody.BodyType.STAR:         return "Star"
		SimBody.BodyType.PLANET:       return "Planet"
		SimBody.BodyType.ASTEROID:     return "Asteroid"
		SimBody.BodyType.FRAGMENT:     return "Fragment"
		SimBody.BodyType.DEBRIS_FIELD: return "Debris Field"
	return "Unknown"

static func _mat_str(m: int) -> String:
	match m:
		SimBody.MaterialType.STELLAR:  return "Stellar"
		SimBody.MaterialType.ROCKY:    return "Rocky"
		SimBody.MaterialType.ICY:      return "Icy"
		SimBody.MaterialType.METALLIC: return "Metallic"
		SimBody.MaterialType.MIXED:    return "Mixed"
	return "Unknown"
