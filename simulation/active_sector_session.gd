## Runtime frame for one active rectangular sector.
class_name ActiveSectorSession
extends RefCounted

var galaxy_state = null
var sector_state = null
var active_cluster_session = null
var active_cluster_id: int = -1
var frame_global_origin: Vector2 = Vector2.ZERO

func bind(
		next_galaxy_state,
		next_sector_state,
		next_active_cluster_session = null) -> void:
	galaxy_state = next_galaxy_state
	sector_state = next_sector_state
	active_cluster_session = next_active_cluster_session
	active_cluster_id = next_active_cluster_session.cluster_id if next_active_cluster_session != null else -1
	if next_active_cluster_session != null:
		frame_global_origin = next_active_cluster_session.cluster_global_origin
	elif next_sector_state != null:
		frame_global_origin = next_sector_state.center()
	else:
		frame_global_origin = Vector2.ZERO

func to_global(local_position: Vector2) -> Vector2:
	return frame_global_origin + local_position

func to_local(global_position: Vector2) -> Vector2:
	return global_position - frame_global_origin

func has_active_cluster() -> bool:
	return active_cluster_id >= 0
