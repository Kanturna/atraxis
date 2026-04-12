## Durable galaxy-wide source of truth for cluster placement and activation.
class_name GalaxyState
extends RefCounted

const OBJECT_RESIDENCY_POLICY_SCRIPT := preload("res://simulation/object_residency_policy.gd")
const TRANSIT_GROUP_STATE_SCRIPT := preload("res://simulation/transit_group_state.gd")
const WORLD_ENTITY_STATE_SCRIPT := preload("res://simulation/world_entity_state.gd")

var galaxy_seed: int = 0
var primary_cluster_id: int = -1
var cluster_order: Array = []
var clusters_by_id: Dictionary = {}
var transit_order: Array = []
var transit_objects_by_id: Dictionary = {}
var transit_group_order: Array = []
var transit_groups_by_id: Dictionary = {}
var entity_order: Array = []
var entities_by_id: Dictionary = {}

func add_cluster(cluster_state: ClusterState) -> void:
	clusters_by_id[cluster_state.cluster_id] = cluster_state
	if not cluster_order.has(cluster_state.cluster_id):
		cluster_order.append(cluster_state.cluster_id)
	if primary_cluster_id < 0:
		primary_cluster_id = cluster_state.cluster_id

func get_cluster(cluster_id: int) -> ClusterState:
	return clusters_by_id.get(cluster_id, null)

func has_cluster(cluster_id: int) -> bool:
	return clusters_by_id.has(cluster_id)

func get_clusters() -> Array:
	var ordered: Array = []
	for cluster_id in cluster_order:
		var cluster_state: ClusterState = get_cluster(cluster_id)
		if cluster_state != null:
			ordered.append(cluster_state)
	return ordered

func get_primary_cluster() -> ClusterState:
	return get_cluster(primary_cluster_id)

func get_cluster_count() -> int:
	return cluster_order.size()

func get_cluster_ids() -> Array:
	return cluster_order.duplicate()

func count_clusters_by_activation_state(state: int) -> int:
	var count: int = 0
	for cluster_state in get_clusters():
		if cluster_state.activation_state == state:
			count += 1
	return count

func register_transit_object(transit_state) -> void:
	if transit_state == null:
		return
	transit_objects_by_id[transit_state.object_id] = transit_state
	if not transit_order.has(transit_state.object_id):
		transit_order.append(transit_state.object_id)
	sync_transit_groups_from_objects()

func get_transit_object(object_id: String):
	return transit_objects_by_id.get(object_id, null)

func has_transit_object(object_id: String) -> bool:
	return transit_objects_by_id.has(object_id)

func remove_transit_object(object_id: String):
	var transit_state = get_transit_object(object_id)
	if transit_state == null:
		return null
	transit_objects_by_id.erase(object_id)
	transit_order.erase(object_id)
	sync_transit_groups_from_objects()
	return transit_state

func get_transit_objects() -> Array:
	var ordered: Array = []
	for object_id in transit_order:
		var transit_state = get_transit_object(object_id)
		if transit_state != null:
			ordered.append(transit_state)
	return ordered

func get_transit_object_count() -> int:
	return transit_order.size()

func get_transit_group(group_id: String):
	return transit_groups_by_id.get(group_id, null)

func has_transit_group(group_id: String) -> bool:
	return transit_groups_by_id.has(group_id)

func get_transit_groups() -> Array:
	var ordered: Array = []
	for group_id in transit_group_order:
		var group_state = get_transit_group(group_id)
		if group_state != null:
			ordered.append(group_state)
	return ordered

func get_transit_group_count() -> int:
	return transit_group_order.size()

func register_world_entity(entity_state) -> void:
	if entity_state == null:
		return
	entities_by_id[entity_state.entity_id] = entity_state
	if not entity_order.has(entity_state.entity_id):
		entity_order.append(entity_state.entity_id)
	sync_world_entity_bindings()

func get_world_entity(entity_id: String):
	return entities_by_id.get(entity_id, null)

func get_world_entities() -> Array:
	var ordered: Array = []
	for entity_id in entity_order:
		var entity_state = get_world_entity(entity_id)
		if entity_state != null:
			ordered.append(entity_state)
	return ordered

func get_world_entity_count() -> int:
	return entity_order.size()

func get_world_entities_for_cluster(cluster_id: int, residency_filter: int = -1) -> Array:
	var matches: Array = []
	for entity_state in get_world_entities():
		if entity_state.current_cluster_id != cluster_id:
			continue
		if residency_filter >= 0 and entity_state.residency_state != residency_filter:
			continue
		matches.append(entity_state)
	return matches

func get_world_entities_in_transit() -> Array:
	var matches: Array = []
	for entity_state in get_world_entities():
		if entity_state.residency_state == ObjectResidencyState.State.IN_TRANSIT:
			matches.append(entity_state)
	return matches

func sync_transit_groups_from_objects() -> void:
	var grouped_transit_states: Dictionary = {}
	var next_group_order: Array = []
	for object_id in transit_order:
		var transit_state = get_transit_object(object_id)
		if transit_state == null:
			continue
		var group_id: String = str(transit_state.transfer_group_id)
		if group_id == "":
			continue
		if not grouped_transit_states.has(group_id):
			grouped_transit_states[group_id] = []
			next_group_order.append(group_id)
		grouped_transit_states[group_id].append(transit_state)

	var next_groups_by_id: Dictionary = {}
	for group_id in next_group_order:
		var group_members: Array = grouped_transit_states[group_id]
		group_members.sort_custom(func(a, b): return a.object_id < b.object_id)
		var group_state = get_transit_group(group_id)
		if group_state == null:
			group_state = TRANSIT_GROUP_STATE_SCRIPT.new()
			group_state.group_id = group_id
		group_state.group_kind = _resolve_transit_group_kind(group_members, group_state)
		group_state.primary_object_id = _resolve_transit_group_primary_object_id(group_members, group_state)
		group_state.anchor_object_id = _resolve_transit_group_anchor_object_id(
			group_members,
			group_state,
			group_state.primary_object_id
		)
		group_state.member_object_ids.clear()
		group_state.global_position = Vector2.ZERO
		group_state.global_velocity = Vector2.ZERO
		group_state.source_cluster_id = int(group_members[0].source_cluster_id) if not group_members.is_empty() else -1
		var anchor_member = _find_transit_group_member_by_id(group_members, group_state.anchor_object_id)
		for transit_state in group_members:
			group_state.member_object_ids.append(transit_state.object_id)
			transit_state.transfer_group_id = group_id
			transit_state.descriptor["transfer_group_id"] = group_id
			transit_state.descriptor["group_kind"] = group_state.group_kind
			transit_state.descriptor["group_primary"] = transit_state.object_id == group_state.primary_object_id
			transit_state.descriptor["group_anchor"] = transit_state.object_id == group_state.anchor_object_id
			group_state.global_position += transit_state.global_position
			group_state.global_velocity += transit_state.global_velocity
		if anchor_member != null:
			group_state.global_position = anchor_member.global_position
			group_state.global_velocity = anchor_member.global_velocity
		elif not group_members.is_empty():
			var member_count: float = float(group_members.size())
			group_state.global_position /= member_count
			group_state.global_velocity /= member_count
		group_state.descriptor["member_count"] = group_members.size()
		group_state.descriptor["group_kind"] = group_state.group_kind
		group_state.descriptor["primary_object_id"] = group_state.primary_object_id
		group_state.descriptor["anchor_object_id"] = group_state.anchor_object_id
		next_groups_by_id[group_id] = group_state

	transit_group_order = next_group_order
	transit_groups_by_id = next_groups_by_id

func sync_world_entity_bindings() -> void:
	sync_transit_groups_from_objects()
	for cluster_state in get_clusters():
		cluster_state.sync_group_registry_from_objects()
	for entity_state in get_world_entities():
		_sync_world_entity_binding(entity_state)

func find_cluster_containing_global_position(global_position: Vector2, radius_factor: float = 1.0) -> ClusterState:
	var matched_cluster: ClusterState = null
	var best_distance: float = INF
	for cluster_state in get_clusters():
		var cluster_radius: float = cluster_state.radius * radius_factor
		var distance: float = cluster_state.global_center.distance_to(global_position)
		if distance > cluster_radius:
			continue
		if distance < best_distance:
			best_distance = distance
			matched_cluster = cluster_state
	return matched_cluster

func find_nearest_cluster(global_position: Vector2, excluded_cluster_id: int = -1) -> ClusterState:
	var matched_cluster: ClusterState = null
	var best_distance: float = INF
	for cluster_state in get_clusters():
		if cluster_state.cluster_id == excluded_cluster_id:
			continue
		var distance: float = cluster_state.global_center.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			matched_cluster = cluster_state
	return matched_cluster

func _resolve_transit_group_kind(group_members: Array, previous_group) -> String:
	if previous_group != null and str(previous_group.group_kind) != "":
		return str(previous_group.group_kind)
	for transit_state in group_members:
		var group_kind: String = str(transit_state.descriptor.get("group_kind", ""))
		if group_kind != "":
			return group_kind
	return "group"

func _resolve_transit_group_primary_object_id(group_members: Array, previous_group) -> String:
	for transit_state in group_members:
		if bool(transit_state.descriptor.get("group_primary_requested", false)):
			return transit_state.object_id
	if previous_group != null and _transit_group_members_include_object(group_members, str(previous_group.primary_object_id)):
		return str(previous_group.primary_object_id)
	for transit_state in group_members:
		if bool(transit_state.descriptor.get("group_primary", false)):
			return transit_state.object_id
	if group_members.is_empty():
		return ""
	return str(group_members[0].object_id)

func _resolve_transit_group_anchor_object_id(group_members: Array, previous_group, fallback_primary_object_id: String) -> String:
	for transit_state in group_members:
		if bool(transit_state.descriptor.get("group_anchor_requested", false)):
			return transit_state.object_id
	if previous_group != null and _transit_group_members_include_object(group_members, str(previous_group.anchor_object_id)):
		return str(previous_group.anchor_object_id)
	for transit_state in group_members:
		if bool(transit_state.descriptor.get("group_anchor", false)):
			return transit_state.object_id
	return fallback_primary_object_id

func _find_transit_group_member_by_id(group_members: Array, object_id: String):
	if object_id == "":
		return null
	for transit_state in group_members:
		if transit_state.object_id == object_id:
			return transit_state
	return null

func _transit_group_members_include_object(group_members: Array, object_id: String) -> bool:
	return _find_transit_group_member_by_id(group_members, object_id) != null

func _sync_world_entity_binding(entity_state) -> void:
	if entity_state == null:
		return
	if entity_state.bound_group_id != "":
		if has_transit_group(entity_state.bound_group_id):
			var transit_group = get_transit_group(entity_state.bound_group_id)
			entity_state.current_group_id = transit_group.group_id
			entity_state.current_transit_group_id = transit_group.group_id
			entity_state.current_cluster_id = transit_group.target_cluster_id \
				if transit_group.target_cluster_id >= 0 else transit_group.source_cluster_id
			entity_state.resolved_anchor_object_id = _resolve_entity_anchor_object_id(
				entity_state,
				transit_group.primary_object_id,
				transit_group.anchor_object_id
			)
			entity_state.residency_state = ObjectResidencyState.State.IN_TRANSIT
			if entity_state.home_cluster_id < 0 and transit_group.source_cluster_id >= 0:
				entity_state.home_cluster_id = transit_group.source_cluster_id
			return
		var owner_cluster: ClusterState = _find_cluster_owning_group(entity_state.bound_group_id)
		if owner_cluster != null:
			var cluster_group = owner_cluster.get_group(entity_state.bound_group_id)
			entity_state.current_group_id = cluster_group.group_id
			entity_state.current_transit_group_id = ""
			entity_state.current_cluster_id = owner_cluster.cluster_id
			entity_state.resolved_anchor_object_id = _resolve_entity_anchor_object_id(
				entity_state,
				cluster_group.primary_object_id,
				cluster_group.anchor_object_id
			)
			entity_state.residency_state = cluster_group.residency_state
			if entity_state.home_cluster_id < 0:
				entity_state.home_cluster_id = owner_cluster.cluster_id
			return
	if entity_state.preferred_object_id != "":
		var object_cluster: ClusterState = _find_cluster_owning_object(entity_state.preferred_object_id)
		if object_cluster != null:
			var object_state: ClusterObjectState = object_cluster.get_object(entity_state.preferred_object_id)
			entity_state.current_group_id = ""
			entity_state.current_transit_group_id = ""
			entity_state.current_cluster_id = object_cluster.cluster_id
			entity_state.resolved_anchor_object_id = entity_state.preferred_object_id
			entity_state.residency_state = object_state.residency_state if object_state != null \
				else OBJECT_RESIDENCY_POLICY_SCRIPT.residency_state_for_cluster_activation(object_cluster.activation_state)
			if entity_state.home_cluster_id < 0:
				entity_state.home_cluster_id = object_cluster.cluster_id
			return
	entity_state.current_group_id = ""
	entity_state.current_transit_group_id = ""
	entity_state.current_cluster_id = entity_state.home_cluster_id
	entity_state.resolved_anchor_object_id = entity_state.preferred_object_id
	entity_state.residency_state = ObjectResidencyState.State.RESIDENT \
		if entity_state.home_cluster_id >= 0 else ObjectResidencyState.State.IN_TRANSIT

func _find_cluster_owning_group(group_id: String) -> ClusterState:
	if group_id == "":
		return null
	for cluster_state in get_clusters():
		if cluster_state.has_group(group_id):
			return cluster_state
	return null

func _find_cluster_owning_object(object_id: String) -> ClusterState:
	if object_id == "":
		return null
	for cluster_state in get_clusters():
		if cluster_state.has_object(object_id):
			return cluster_state
	return null

func _resolve_entity_anchor_object_id(entity_state, primary_object_id: String, anchor_object_id: String) -> String:
	if entity_state == null:
		return anchor_object_id if anchor_object_id != "" else primary_object_id
	match int(entity_state.attachment_mode):
		WORLD_ENTITY_STATE_SCRIPT.ATTACHMENT_DIRECT_OBJECT:
			return entity_state.preferred_object_id if entity_state.preferred_object_id != "" \
				else (anchor_object_id if anchor_object_id != "" else primary_object_id)
		WORLD_ENTITY_STATE_SCRIPT.ATTACHMENT_GROUP_PRIMARY:
			return primary_object_id if primary_object_id != "" else anchor_object_id
		_:
			return anchor_object_id if anchor_object_id != "" else primary_object_id
