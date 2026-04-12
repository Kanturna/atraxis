## Runtime container that binds one active cluster session into a larger Makrosektor frame.
class_name ActiveMacroSectorSession
extends RefCounted

const MACRO_SECTOR_ZONE_SCRIPT := preload("res://simulation/macro_sector_zone.gd")

var galaxy_state: GalaxyState = null
var descriptor = null
var active_cluster_session: ActiveClusterSession = null

func bind(
		next_galaxy_state: GalaxyState,
		next_descriptor,
		next_active_cluster_session: ActiveClusterSession) -> void:
	galaxy_state = next_galaxy_state
	descriptor = next_descriptor.copy() if next_descriptor != null else null
	active_cluster_session = next_active_cluster_session

func has_member_cluster(cluster_id: int) -> bool:
	return descriptor != null and descriptor.has_member(cluster_id)

func zone_for_cluster(cluster_id: int) -> int:
	if descriptor == null:
		return MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE
	return descriptor.zone_for_cluster(cluster_id)

func get_cluster_ids_for_zone(zone: int) -> Array:
	if descriptor == null:
		return []
	return descriptor.get_cluster_ids_for_zone(zone)
