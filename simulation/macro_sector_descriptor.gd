## Persistent-free runtime description of the currently active Makrosektor.
class_name MacroSectorDescriptor
extends RefCounted

const MACRO_SECTOR_ZONE_SCRIPT := preload("res://simulation/macro_sector_zone.gd")

var anchor_cluster_id: int = -1
var focus_cluster_id: int = -1
var member_cluster_ids: Array = []
var zone_by_cluster_id: Dictionary = {}
var discovery_radius: int = 1

func has_member(cluster_id: int) -> bool:
	return member_cluster_ids.has(cluster_id)

func zone_for_cluster(cluster_id: int) -> int:
	return int(zone_by_cluster_id.get(cluster_id, MACRO_SECTOR_ZONE_SCRIPT.Zone.OUTSIDE))

func get_cluster_ids_for_zone(zone: int) -> Array:
	var cluster_ids: Array = []
	for cluster_id in member_cluster_ids:
		if zone_for_cluster(int(cluster_id)) == zone:
			cluster_ids.append(int(cluster_id))
	return cluster_ids

func copy():
	var duplicate_descriptor = get_script().new()
	duplicate_descriptor.anchor_cluster_id = anchor_cluster_id
	duplicate_descriptor.focus_cluster_id = focus_cluster_id
	duplicate_descriptor.member_cluster_ids = member_cluster_ids.duplicate()
	duplicate_descriptor.zone_by_cluster_id = zone_by_cluster_id.duplicate(true)
	duplicate_descriptor.discovery_radius = discovery_radius
	return duplicate_descriptor
