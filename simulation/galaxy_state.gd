## Durable galaxy-wide source of truth for cluster placement and activation.
class_name GalaxyState
extends RefCounted

var galaxy_seed: int = 0
var primary_cluster_id: int = -1
var cluster_order: Array = []
var clusters_by_id: Dictionary = {}

func add_cluster(cluster_state: ClusterState) -> void:
	clusters_by_id[cluster_state.cluster_id] = cluster_state
	if not cluster_order.has(cluster_state.cluster_id):
		cluster_order.append(cluster_state.cluster_id)
	if primary_cluster_id < 0:
		primary_cluster_id = cluster_state.cluster_id

func get_cluster(cluster_id: int) -> ClusterState:
	return clusters_by_id.get(cluster_id, null)

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

