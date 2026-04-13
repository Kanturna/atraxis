## Durable top-level rectangle sector record for the procedural universe.
class_name SectorState
extends RefCounted

enum ActivationState {
	REMOTE = 0,
	ACTIVE = 1,
}

var sector_coord: Vector2i = Vector2i.ZERO
var sector_seed: int = 0
var region_archetype: String = "void"
var density: float = 0.0
var void_strength: float = 0.0
var bh_richness: float = 0.0
var star_richness: float = 0.0
var rare_zone_weight: float = 0.0
var global_origin: Vector2 = Vector2.ZERO
var size: float = 0.0
var cluster_ids: Array = []
var activation_state: int = ActivationState.REMOTE
var last_entered_runtime_time: float = -1.0
var last_exited_runtime_time: float = -1.0

func copy():
	var duplicate_state = get_script().new()
	duplicate_state.sector_coord = sector_coord
	duplicate_state.sector_seed = sector_seed
	duplicate_state.region_archetype = region_archetype
	duplicate_state.density = density
	duplicate_state.void_strength = void_strength
	duplicate_state.bh_richness = bh_richness
	duplicate_state.star_richness = star_richness
	duplicate_state.rare_zone_weight = rare_zone_weight
	duplicate_state.global_origin = global_origin
	duplicate_state.size = size
	duplicate_state.cluster_ids = cluster_ids.duplicate()
	duplicate_state.activation_state = activation_state
	duplicate_state.last_entered_runtime_time = last_entered_runtime_time
	duplicate_state.last_exited_runtime_time = last_exited_runtime_time
	return duplicate_state

func bounds() -> Rect2:
	return Rect2(global_origin, Vector2.ONE * size)

func center() -> Vector2:
	return global_origin + Vector2.ONE * (size * 0.5)

func has_cluster(cluster_id: int) -> bool:
	return cluster_ids.has(cluster_id)

func add_cluster(cluster_id: int) -> void:
	if not cluster_ids.has(cluster_id):
		cluster_ids.append(cluster_id)

func mark_active(runtime_time: float) -> void:
	activation_state = ActivationState.ACTIVE
	last_entered_runtime_time = runtime_time

func mark_remote(runtime_time: float) -> void:
	if activation_state == ActivationState.ACTIVE:
		last_exited_runtime_time = runtime_time
	activation_state = ActivationState.REMOTE
