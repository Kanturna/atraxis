## Deterministic sector-level description of one galaxy region.
class_name GalaxyRegionDescriptor
extends RefCounted

var sector_coord: Vector2i = Vector2i.ZERO
var region_seed: int = 0
var region_archetype: String = "void"
var density: float = 0.0
var void_strength: float = 0.0
var cluster_chance: float = 0.0
var bh_richness: float = 0.0
var star_richness: float = 0.0
var rare_zone_weight: float = 0.0
var scrap_potential: float = 0.0
var life_potential: float = 0.0

func copy():
	var duplicate_descriptor = get_script().new()
	duplicate_descriptor.sector_coord = sector_coord
	duplicate_descriptor.region_seed = region_seed
	duplicate_descriptor.region_archetype = region_archetype
	duplicate_descriptor.density = density
	duplicate_descriptor.void_strength = void_strength
	duplicate_descriptor.cluster_chance = cluster_chance
	duplicate_descriptor.bh_richness = bh_richness
	duplicate_descriptor.star_richness = star_richness
	duplicate_descriptor.rare_zone_weight = rare_zone_weight
	duplicate_descriptor.scrap_potential = scrap_potential
	duplicate_descriptor.life_potential = life_potential
	return duplicate_descriptor
