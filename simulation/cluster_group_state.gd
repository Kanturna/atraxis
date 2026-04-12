## Persistent per-group record stored inside a ClusterState.
## Groups keep a stable ownership identity for composed units even while the
## individual members move between ACTIVE, SIMPLIFIED and RESIDENT states.
class_name ClusterGroupState
extends RefCounted

var group_id: String = ""
var group_kind: String = ""
var primary_object_id: String = ""
var anchor_object_id: String = ""
var residency_state: int = ObjectResidencyState.State.RESIDENT
var member_object_ids: Array = []
var descriptor: Dictionary = {}

func copy():
	var duplicate_state = get_script().new()
	duplicate_state.group_id = group_id
	duplicate_state.group_kind = group_kind
	duplicate_state.primary_object_id = primary_object_id
	duplicate_state.anchor_object_id = anchor_object_id
	duplicate_state.residency_state = residency_state
	duplicate_state.member_object_ids = member_object_ids.duplicate()
	duplicate_state.descriptor = descriptor.duplicate(true)
	return duplicate_state
