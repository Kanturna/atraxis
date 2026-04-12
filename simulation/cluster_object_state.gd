## Persistent per-object record stored inside a ClusterState.
class_name ClusterObjectState
extends RefCounted

var object_id: String = ""
var kind: String = ""
var residency_state: int = ObjectResidencyState.State.RESIDENT
var local_position: Vector2 = Vector2.ZERO
var local_velocity: Vector2 = Vector2.ZERO
var age: float = 0.0
var seed: int = 0
var descriptor: Dictionary = {}

func copy() -> ClusterObjectState:
	var duplicate_state := ClusterObjectState.new()
	duplicate_state.object_id = object_id
	duplicate_state.kind = kind
	duplicate_state.residency_state = residency_state
	duplicate_state.local_position = local_position
	duplicate_state.local_velocity = local_velocity
	duplicate_state.age = age
	duplicate_state.seed = seed
	duplicate_state.descriptor = descriptor.duplicate(true)
	return duplicate_state
