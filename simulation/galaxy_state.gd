## Durable galaxy-wide source of truth for cluster placement and activation.
class_name GalaxyState
extends RefCounted

const TRANSIT_GROUP_STATE_SCRIPT := preload("res://simulation/transit_group_state.gd")

var galaxy_seed: int = 0
var primary_cluster_id: int = -1
var cluster_order: Array = []
var clusters_by_id: Dictionary = {}
var transit_order: Array = []
var transit_objects_by_id: Dictionary = {}
var transit_group_order: Array = []
var transit_groups_by_id: Dictionary = {}

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
		group_state.member_object_ids.clear()
		group_state.global_position = Vector2.ZERO
		group_state.global_velocity = Vector2.ZERO
		group_state.source_cluster_id = int(group_members[0].source_cluster_id) if not group_members.is_empty() else -1
		for transit_state in group_members:
			group_state.member_object_ids.append(transit_state.object_id)
			group_state.global_position += transit_state.global_position
			group_state.global_velocity += transit_state.global_velocity
		if not group_members.is_empty():
			var member_count: float = float(group_members.size())
			group_state.global_position /= member_count
			group_state.global_velocity /= member_count
		group_state.descriptor["member_count"] = group_members.size()
		next_groups_by_id[group_id] = group_state

	transit_group_order = next_group_order
	transit_groups_by_id = next_groups_by_id

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
