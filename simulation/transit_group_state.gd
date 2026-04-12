## Galaxy-wide source-of-truth record for a grouped transfer in transit.
## Groups provide a shared routing and ownership envelope for multiple related
## transit objects without forcing full agent/group behavior yet.
class_name TransitGroupState
extends RefCounted

const TRANSIT_OBJECT_STATE_SCRIPT := preload("res://simulation/transit_object_state.gd")

var group_id: String = ""
var source_cluster_id: int = -1
var target_cluster_id: int = -1
var arrival_phase: int = TRANSIT_OBJECT_STATE_SCRIPT.ArrivalPhase.UNASSIGNED
var global_position: Vector2 = Vector2.ZERO
var global_velocity: Vector2 = Vector2.ZERO
var member_object_ids: Array = []
var descriptor: Dictionary = {}

func copy():
	var duplicate_state = get_script().new()
	duplicate_state.group_id = group_id
	duplicate_state.source_cluster_id = source_cluster_id
	duplicate_state.target_cluster_id = target_cluster_id
	duplicate_state.arrival_phase = arrival_phase
	duplicate_state.global_position = global_position
	duplicate_state.global_velocity = global_velocity
	duplicate_state.member_object_ids = member_object_ids.duplicate()
	duplicate_state.descriptor = descriptor.duplicate(true)
	return duplicate_state
