## Durable source-of-truth record for one galaxy cluster.
class_name ClusterState
extends RefCounted

var cluster_id: int = -1
var global_center: Vector2 = Vector2.ZERO
var radius: float = 0.0
var cluster_seed: int = 0
var classification: String = ""
var activation_state: int = ClusterActivationState.State.UNLOADED
var simulated_time: float = 0.0
var cluster_blueprint: Dictionary = {}
var simulation_profile: Dictionary = {}
var object_registry: Dictionary = {}

func register_object(object_state: ClusterObjectState) -> void:
	object_registry[object_state.object_id] = object_state

func get_object(object_id: String) -> ClusterObjectState:
	return object_registry.get(object_id, null)

func get_objects_by_kind(kind: String) -> Array:
	var matches: Array = []
	for object_state in object_registry.values():
		if object_state.kind == kind:
			matches.append(object_state)
	matches.sort_custom(func(a, b): return a.object_id < b.object_id)
	return matches

func get_primary_black_hole_object_id() -> String:
	return str(cluster_blueprint.get("primary_black_hole_object_id", ""))

func replace_object_registry(next_registry: Dictionary) -> void:
	object_registry = next_registry

func set_object_residency_state(next_state: int) -> void:
	for object_state in object_registry.values():
		object_state.residency_state = next_state

func copy() -> ClusterState:
	var duplicate_state := ClusterState.new()
	duplicate_state.cluster_id = cluster_id
	duplicate_state.global_center = global_center
	duplicate_state.radius = radius
	duplicate_state.cluster_seed = cluster_seed
	duplicate_state.classification = classification
	duplicate_state.activation_state = activation_state
	duplicate_state.simulated_time = simulated_time
	duplicate_state.cluster_blueprint = cluster_blueprint.duplicate(true)
	duplicate_state.simulation_profile = simulation_profile.duplicate(true)
	for object_id in object_registry.keys():
		duplicate_state.object_registry[object_id] = object_registry[object_id].copy()
	return duplicate_state
