## Galaxy-wide source-of-truth record for an object currently between clusters.
class_name TransitObjectState
extends RefCounted

enum ArrivalPhase {
	UNASSIGNED = 0,
	EN_ROUTE = 1,
	ARRIVING = 2,
}

var object_id: String = ""
var kind: String = ""
var residency_state: int = ObjectResidencyState.State.IN_TRANSIT
var source_cluster_id: int = -1
var transfer_group_id: String = ""
var target_cluster_id: int = -1
var arrival_phase: int = ArrivalPhase.UNASSIGNED
var global_position: Vector2 = Vector2.ZERO
var global_velocity: Vector2 = Vector2.ZERO
var age: float = 0.0
var seed: int = 0
var descriptor: Dictionary = {}

func copy():
	var duplicate_state = get_script().new()
	duplicate_state.object_id = object_id
	duplicate_state.kind = kind
	duplicate_state.residency_state = residency_state
	duplicate_state.source_cluster_id = source_cluster_id
	duplicate_state.transfer_group_id = transfer_group_id
	duplicate_state.target_cluster_id = target_cluster_id
	duplicate_state.arrival_phase = arrival_phase
	duplicate_state.global_position = global_position
	duplicate_state.global_velocity = global_velocity
	duplicate_state.age = age
	duplicate_state.seed = seed
	duplicate_state.descriptor = descriptor.duplicate(true)
	return duplicate_state
