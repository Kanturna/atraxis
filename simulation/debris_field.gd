## debris_field.gd
## Aggregated debris abstraction. Represents a cloud of small fragments
## as a single lightweight data object — not a full SimBody.
##
## MVP design: purely passive (no physics, no drift).
## Phase 2 extension: add velocity + gravity response for drifting debris clouds.
class_name DebrisField
extends RefCounted

var id: int = -1
var position: Vector2 = Vector2.ZERO  # mass-weighted centroid
var total_mass: float = 0.0
var radius: float = 40.0              # visual cloud radius in sim-units
var active: bool = true

## Add mass to this field and update the centroid accordingly.
func add_mass(added_mass: float, at_position: Vector2) -> void:
	if added_mass <= 0.0:
		return
	var old_mass := total_mass
	total_mass += added_mass
	# Mass-weighted centroid update
	position = (position * old_mass + at_position * added_mass) / total_mass
	# Expand cloud radius slightly as mass accumulates
	radius = max(radius, SimConstants.DEBRIS_MERGE_RADIUS * sqrt(total_mass / 10.0))
	radius = clamp(radius, 20.0, 200.0)

## Absorb another field into this one (used when two fields drift close).
func absorb(other: DebrisField) -> void:
	add_mass(other.total_mass, other.position)
	other.active = false
