## sim_body.gd
## Data container for a single simulated body.
## Pure RefCounted — no Godot scene tree dependencies.
class_name SimBody
extends RefCounted

# -------------------------------------------------------------------------
# Enums
# -------------------------------------------------------------------------

enum BodyType {
	STAR         = 0,
	PLANET       = 1,
	ASTEROID     = 2,
	FRAGMENT     = 3,
	DEBRIS_FIELD = 4,
}

enum MaterialType {
	STELLAR  = 0,
	ROCKY    = 1,
	ICY      = 2,
	METALLIC = 3,
	MIXED    = 4,
}

## Gravity hierarchy level.
## A: dominant sources (star, large planets). Affect everything.
## B: medium bodies (asteroids). React to A; limited B-B interaction.
## C: small debris/fragments. Receive gravity only; never source it.
enum InfluenceLevel {
	A = 0,
	B = 1,
	C = 2,
}

# -------------------------------------------------------------------------
# Identity
# -------------------------------------------------------------------------

var id: int = -1
var body_type: int = BodyType.ASTEROID
var material_type: int = MaterialType.ROCKY
var influence_level: int = InfluenceLevel.B

# -------------------------------------------------------------------------
# Physical state
# -------------------------------------------------------------------------

var mass: float = 1.0
var radius: float = 2.0
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO

## Recomputed every step_sim() call. Never persisted between frames.
## External code must not read this value outside of a sim step.
var acceleration: Vector2 = Vector2.ZERO

var temperature: float = 200.0

# -------------------------------------------------------------------------
# MVP extension hook: kinematic bodies are "fixed" this phase
# kinematic=true → _integrate() skips this body (star, planets in MVP)
# kinematic=false → body moves under gravity (default for B/C bodies)
#
# Phase 2 upgrade: simply set kinematic=false on planets to enable
# full N-body mutual attraction without any other changes.
# -------------------------------------------------------------------------
var kinematic: bool = false

# -------------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------------

var active: bool = true

## Sleeping bodies skip gravity and integration (performance optimization).
## Level-A and kinematic bodies are never put to sleep.
var sleeping: bool = false

## Set to true during a sim phase to flag for removal.
## Bodies are actually removed by _flush_removals() after all phases complete.
## This prevents mid-loop array mutation bugs.
var marked_for_removal: bool = false

# -------------------------------------------------------------------------
# Debris aggregation
# -------------------------------------------------------------------------

## Mass of small debris aggregated at this body's location (for planets/asteroids).
## For DEBRIS_FIELD body_type, this IS the primary mass.
var debris_mass: float = 0.0

# -------------------------------------------------------------------------
# Bookkeeping
# -------------------------------------------------------------------------

var age: float = 0.0       # seconds since body was created
var sleep_timer: float = 0.0

# -------------------------------------------------------------------------
# Helper methods
# -------------------------------------------------------------------------

func get_kinetic_energy() -> float:
	return 0.5 * mass * velocity.length_squared()

func is_level_a() -> bool:
	return influence_level == InfluenceLevel.A

func is_level_b() -> bool:
	return influence_level == InfluenceLevel.B

func is_level_c() -> bool:
	return influence_level == InfluenceLevel.C

func check_sleep_eligible() -> bool:
	if kinematic or influence_level == InfluenceLevel.A:
		return false
	return velocity.length_squared() < SimConstants.SLEEP_SPEED_SQ

func reset_sleep_timer() -> void:
	sleep_timer = 0.0
	sleeping = false
