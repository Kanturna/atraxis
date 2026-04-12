## Durable galaxy-wide source of truth for cluster placement and activation.
class_name GalaxyState
extends RefCounted

var galaxy_seed: int = 0
var primary_cluster_id: int = -1
var cluster_order: Array = []
var clusters_by_id: Dictionary = {}
var transit_order: Array = []
var transit_objects_by_id: Dictionary = {}

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
