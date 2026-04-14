## sim_body.gd
## Data container for a single simulated body.
## Pure RefCounted - no Godot scene tree dependencies.
class_name SimBody
extends RefCounted

# -------------------------------------------------------------------------
# Enums
# -------------------------------------------------------------------------

enum BodyType {
	BLACK_HOLE = 0,
	STAR = 1,
	PLANET = 2,
	ASTEROID = 3,
	FRAGMENT = 4,
	DEBRIS_FIELD = 5,
}

enum MaterialType {
	STELLAR = 0,
	ROCKY = 1,
	ICY = 2,
	METALLIC = 3,
	MIXED = 4,
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

enum OrbitBindingState {
	BOUND_ANALYTIC = 0,
	FREE_DYNAMIC = 1,
	CAPTURED_ANALYTIC = 2,
}

# -------------------------------------------------------------------------
# Identity
# -------------------------------------------------------------------------

var id: int = -1
var persistent_object_id: String = ""
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
# Phase-1 motion model
# -------------------------------------------------------------------------

# kinematic=true skips the generic N-body integrator.
# In Phase 1 the star is fixed and planets can still move analytically through
# scripted_orbit_enabled while remaining outside the N-body integrator.
# kinematic=false means the body moves under gravity and collisions.
#
# Phase 2 upgrade: set kinematic=false on planets and disable scripted orbiting
# to move them into full N-body mutual attraction.
var kinematic: bool = false

## Analytic orbit support for calm reference carriers.
## In the orbital-reference preset, bound core planets are analytically updated
## relative to a moving parent after dynamic bodies have already advanced.
var scripted_orbit_enabled: bool = false
var orbit_binding_state: int = OrbitBindingState.FREE_DYNAMIC
var orbit_parent_id: int = -1
var orbit_center: Vector2 = Vector2.ZERO
var orbit_radius: float = 0.0
var orbit_angle: float = 0.0
var orbit_angular_speed: float = 0.0

## Debug-facing anchor tracking for dynamic orbit diagnostics.
## Persisted so cluster snapshot reloads keep the accumulated handoff history.
var last_dominant_bh_id: int = -1
var dominant_bh_handoff_count: int = 0
var pending_host_bh_id: int = -1
var pending_host_time: float = 0.0
var confirmed_host_handoff_count: int = 0

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

var age: float = 0.0
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

func is_analytic_orbit_bound() -> bool:
	return scripted_orbit_enabled and orbit_binding_state in [
		OrbitBindingState.BOUND_ANALYTIC,
		OrbitBindingState.CAPTURED_ANALYTIC,
	]
