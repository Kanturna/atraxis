## Durable world-level state for future units, agents, or living beings.
## This intentionally models only identity, ownership bindings and residency,
## not behavior or simulation logic.
class_name WorldEntityState
extends RefCounted

enum AttachmentMode {
	DIRECT_OBJECT = 0,
	GROUP_PRIMARY = 1,
	GROUP_ANCHOR = 2,
}

const ATTACHMENT_DIRECT_OBJECT: int = AttachmentMode.DIRECT_OBJECT
const ATTACHMENT_GROUP_PRIMARY: int = AttachmentMode.GROUP_PRIMARY
const ATTACHMENT_GROUP_ANCHOR: int = AttachmentMode.GROUP_ANCHOR

var entity_id: String = ""
var entity_kind: String = ""
var residency_state: int = ObjectResidencyState.State.RESIDENT
var home_cluster_id: int = -1
var current_cluster_id: int = -1
var attachment_mode: int = AttachmentMode.GROUP_ANCHOR
var bound_group_id: String = ""
var preferred_object_id: String = ""
var current_group_id: String = ""
var current_transit_group_id: String = ""
var resolved_anchor_object_id: String = ""
var descriptor: Dictionary = {}

func copy():
	var duplicate_state = get_script().new()
	duplicate_state.entity_id = entity_id
	duplicate_state.entity_kind = entity_kind
	duplicate_state.residency_state = residency_state
	duplicate_state.home_cluster_id = home_cluster_id
	duplicate_state.current_cluster_id = current_cluster_id
	duplicate_state.attachment_mode = attachment_mode
	duplicate_state.bound_group_id = bound_group_id
	duplicate_state.preferred_object_id = preferred_object_id
	duplicate_state.current_group_id = current_group_id
	duplicate_state.current_transit_group_id = current_transit_group_id
	duplicate_state.resolved_anchor_object_id = resolved_anchor_object_id
	duplicate_state.descriptor = descriptor.duplicate(true)
	return duplicate_state
