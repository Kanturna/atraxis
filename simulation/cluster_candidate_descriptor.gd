## Deterministic cluster candidate generated from one sector descriptor.
class_name ClusterCandidateDescriptor
extends RefCounted

var sector_coord: Vector2i = Vector2i.ZERO
var candidate_index: int = -1
var cluster_id: int = -1
var cluster_seed: int = 0
var classification: String = ""
var region_archetype: String = "void"
var global_center: Vector2 = Vector2.ZERO
var radius: float = 0.0
var bh_count: int = 0
var bh_spacing_au: float = 0.0
var bh_richness: float = 0.0
var star_richness: float = 0.0
var rare_zone_weight: float = 0.0
var scrap_potential: float = 0.0
var life_potential: float = 0.0
var descriptor: Dictionary = {}

func copy():
	var duplicate_descriptor = get_script().new()
	duplicate_descriptor.sector_coord = sector_coord
	duplicate_descriptor.candidate_index = candidate_index
	duplicate_descriptor.cluster_id = cluster_id
	duplicate_descriptor.cluster_seed = cluster_seed
	duplicate_descriptor.classification = classification
	duplicate_descriptor.region_archetype = region_archetype
	duplicate_descriptor.global_center = global_center
	duplicate_descriptor.radius = radius
	duplicate_descriptor.bh_count = bh_count
	duplicate_descriptor.bh_spacing_au = bh_spacing_au
	duplicate_descriptor.bh_richness = bh_richness
	duplicate_descriptor.star_richness = star_richness
	duplicate_descriptor.rare_zone_weight = rare_zone_weight
	duplicate_descriptor.scrap_potential = scrap_potential
	duplicate_descriptor.life_potential = life_potential
	duplicate_descriptor.descriptor = descriptor.duplicate(true)
	return duplicate_descriptor
