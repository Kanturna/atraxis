## Durable source-of-truth record for one galaxy cluster.
class_name ClusterState
extends RefCounted

const CLUSTER_GROUP_STATE_SCRIPT := preload("res://simulation/cluster_group_state.gd")

var cluster_id: int = -1
var global_center: Vector2 = Vector2.ZERO
var radius: float = 0.0
var runtime_extent_radius: float = 0.0
var cluster_seed: int = 0
var classification: String = ""
var activation_state: int = ClusterActivationState.State.UNLOADED
var simulated_time: float = 0.0
var last_activated_runtime_time: float = -1.0
var last_deactivated_runtime_time: float = -1.0
var last_unloaded_runtime_time: float = -1.0
var last_relevance_runtime_time: float = -1.0
var cluster_blueprint: Dictionary = {}
var simulation_profile: Dictionary = {}
var object_registry: Dictionary = {}
var group_registry: Dictionary = {}

func register_object(object_state: ClusterObjectState) -> void:
	object_registry[object_state.object_id] = object_state
	sync_group_registry_from_objects()

func get_object(object_id: String) -> ClusterObjectState:
	return object_registry.get(object_id, null)

func has_object(object_id: String) -> bool:
	return object_registry.has(object_id)

func unregister_object(object_id: String) -> void:
	object_registry.erase(object_id)
	sync_group_registry_from_objects()

func get_objects_by_kind(kind: String) -> Array:
	var matches: Array = []
	for object_state in object_registry.values():
		if object_state.kind == kind:
			matches.append(object_state)
	matches.sort_custom(func(a, b): return a.object_id < b.object_id)
	return matches

func get_primary_black_hole_object_id() -> String:
	return str(cluster_blueprint.get("primary_black_hole_object_id", ""))

func get_authoritative_radius() -> float:
	return maxf(radius, 0.0)

func get_runtime_aware_radius() -> float:
	return maxf(get_authoritative_radius(), runtime_extent_radius)

func update_runtime_extent(next_extent_radius: float) -> void:
	runtime_extent_radius = maxf(get_authoritative_radius(), next_extent_radius)

func get_group(group_id: String):
	return group_registry.get(group_id, null)

func has_group(group_id: String) -> bool:
	return group_registry.has(group_id)

func get_groups() -> Array:
	var group_ids: Array = group_registry.keys()
	group_ids.sort()
	var matches: Array = []
	for group_id in group_ids:
		var group_state = get_group(group_id)
		if group_state != null:
			matches.append(group_state)
	return matches

func replace_object_registry(next_registry: Dictionary) -> void:
	object_registry = next_registry
	sync_group_registry_from_objects()

func set_object_residency_state(next_state: int) -> void:
	for object_state in object_registry.values():
		object_state.residency_state = next_state
	for group_state in group_registry.values():
		group_state.residency_state = next_state

func sync_group_registry_from_objects() -> void:
	var grouped_objects: Dictionary = {}
	for object_state in object_registry.values():
		var group_id: String = str(object_state.descriptor.get("transfer_group_id", ""))
		if group_id == "":
			continue
		if not grouped_objects.has(group_id):
			grouped_objects[group_id] = []
		grouped_objects[group_id].append(object_state)

	var next_group_registry: Dictionary = {}
	var ordered_group_ids: Array = grouped_objects.keys()
	ordered_group_ids.sort()
	for group_id in ordered_group_ids:
		var member_states: Array = grouped_objects[group_id]
		member_states.sort_custom(func(a, b): return a.object_id < b.object_id)
		var previous_group = get_group(group_id)
		var group_state = previous_group if previous_group != null else CLUSTER_GROUP_STATE_SCRIPT.new()
		group_state.group_id = group_id
		group_state.member_object_ids.clear()
		group_state.group_kind = _resolve_group_kind(member_states, previous_group)
		group_state.primary_object_id = _resolve_group_primary_object_id(member_states, previous_group)
		group_state.anchor_object_id = _resolve_group_anchor_object_id(
			member_states,
			previous_group,
			group_state.primary_object_id
		)
		group_state.residency_state = int(member_states[0].residency_state) if not member_states.is_empty() \
			else ObjectResidencyState.State.RESIDENT
		group_state.descriptor["member_count"] = member_states.size()
		group_state.descriptor["group_kind"] = group_state.group_kind
		group_state.descriptor["primary_object_id"] = group_state.primary_object_id
		group_state.descriptor["anchor_object_id"] = group_state.anchor_object_id
		for object_state in member_states:
			group_state.member_object_ids.append(object_state.object_id)
			object_state.descriptor["transfer_group_id"] = group_id
			object_state.descriptor["group_kind"] = group_state.group_kind
			object_state.descriptor["group_primary"] = object_state.object_id == group_state.primary_object_id
			object_state.descriptor["group_anchor"] = object_state.object_id == group_state.anchor_object_id
		next_group_registry[group_id] = group_state

	group_registry = next_group_registry

func mark_relevant(runtime_time: float) -> void:
	last_relevance_runtime_time = runtime_time

func mark_active(runtime_time: float) -> void:
	activation_state = ClusterActivationState.State.ACTIVE
	last_activated_runtime_time = runtime_time
	mark_relevant(runtime_time)
	set_object_residency_state(ObjectResidencyState.State.ACTIVE)

func mark_simplified(runtime_time: float) -> void:
	activation_state = ClusterActivationState.State.SIMPLIFIED
	last_deactivated_runtime_time = runtime_time
	mark_relevant(runtime_time)
	set_object_residency_state(ObjectResidencyState.State.SIMPLIFIED)

func mark_unloaded(runtime_time: float) -> void:
	activation_state = ClusterActivationState.State.UNLOADED
	last_unloaded_runtime_time = runtime_time
	set_object_residency_state(ObjectResidencyState.State.RESIDENT)

func can_unload_from_simplified(runtime_time: float, unload_delay: float) -> bool:
	if activation_state != ClusterActivationState.State.SIMPLIFIED:
		return false
	if last_relevance_runtime_time < 0.0:
		return false
	if not bool(simulation_profile.get("has_runtime_snapshot", false)):
		return false
	return runtime_time - last_relevance_runtime_time >= unload_delay

func copy() -> ClusterState:
	var duplicate_state := ClusterState.new()
	duplicate_state.cluster_id = cluster_id
	duplicate_state.global_center = global_center
	duplicate_state.radius = radius
	duplicate_state.runtime_extent_radius = runtime_extent_radius
	duplicate_state.cluster_seed = cluster_seed
	duplicate_state.classification = classification
	duplicate_state.activation_state = activation_state
	duplicate_state.simulated_time = simulated_time
	duplicate_state.last_activated_runtime_time = last_activated_runtime_time
	duplicate_state.last_deactivated_runtime_time = last_deactivated_runtime_time
	duplicate_state.last_unloaded_runtime_time = last_unloaded_runtime_time
	duplicate_state.last_relevance_runtime_time = last_relevance_runtime_time
	duplicate_state.cluster_blueprint = cluster_blueprint.duplicate(true)
	duplicate_state.simulation_profile = simulation_profile.duplicate(true)
	for object_id in object_registry.keys():
		duplicate_state.object_registry[object_id] = object_registry[object_id].copy()
	for group_id in group_registry.keys():
		duplicate_state.group_registry[group_id] = group_registry[group_id].copy()
	return duplicate_state

func _resolve_group_kind(member_states: Array, previous_group) -> String:
	if previous_group != null and str(previous_group.group_kind) != "":
		return str(previous_group.group_kind)
	for object_state in member_states:
		var group_kind: String = str(object_state.descriptor.get("group_kind", ""))
		if group_kind != "":
			return group_kind
	return "group"

func _resolve_group_primary_object_id(member_states: Array, previous_group) -> String:
	for object_state in member_states:
		if bool(object_state.descriptor.get("group_primary_requested", false)):
			return object_state.object_id
	for object_state in member_states:
		if bool(object_state.descriptor.get("group_primary", false)):
			return object_state.object_id
	if previous_group != null and _group_members_include_object(member_states, str(previous_group.primary_object_id)):
		return str(previous_group.primary_object_id)
	if member_states.is_empty():
		return ""
	return str(member_states[0].object_id)

func _resolve_group_anchor_object_id(
		member_states: Array,
		previous_group,
		fallback_primary_object_id: String) -> String:
	for object_state in member_states:
		if bool(object_state.descriptor.get("group_anchor_requested", false)):
			return object_state.object_id
	for object_state in member_states:
		if bool(object_state.descriptor.get("group_anchor", false)):
			return object_state.object_id
	if previous_group != null and _group_members_include_object(member_states, str(previous_group.anchor_object_id)):
		return str(previous_group.anchor_object_id)
	return fallback_primary_object_id

func _group_members_include_object(member_states: Array, object_id: String) -> bool:
	if object_id == "":
		return false
	for object_state in member_states:
		if object_state.object_id == object_id:
			return true
	return false
