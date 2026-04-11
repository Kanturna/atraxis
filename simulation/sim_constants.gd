## sim_constants.gd
## Central tuning file. All simulation parameters live here.
## Uses normalized game units — not real SI units.
## Rationale: keeps numbers readable and balanceable without physics knowledge.
class_name SimConstants
extends RefCounted

# --- Gravity ---
# G is tuned so that v_orbit = sqrt(G * M / r) gives plausible speeds
# at the AU distances defined below.
const G: float = 100.0

# --- Mass scale (game units) ---
const STAR_MASS: float        = 1_000_000.0
const BLACK_HOLE_MASS: float  = 4_000_000.0
const PLANET_MASS_MIN: float  = 500.0
const PLANET_MASS_MAX: float  = 3_000.0
const ASTEROID_MASS_MIN: float = 1.0
const ASTEROID_MASS_MAX: float = 50.0

# --- Distance scale ---
# 1 AU = 1000 sim-units. Keep orbital radii as multiples of this.
const AU: float = 1000.0

# --- Zone boundaries (distance from star center) ---
const INNER_ZONE_MAX: float  = 0.5 * AU   # hot / energetic
const MIDDLE_ZONE_MIN: float = 0.5 * AU   # temperate start
const MIDDLE_ZONE_MAX: float = 1.5 * AU   # temperate end
const OUTER_ZONE_MIN: float  = 1.5 * AU   # cold / resource-rich

# --- Collision ---
const RESTITUTION: float             = 0.4   # bounciness (0=inelastic, 1=elastic)
const MERGE_MASS_RATIO: float        = 0.15  # if smaller/larger < this, tend to merge
const FRAGMENT_KE_THRESHOLD: float   = 0.3   # fraction of approach KE that causes fragments
const MIN_FRAGMENT_MASS: float       = 0.5   # below this: goes to debris, not SimBody
const MAX_ACTIVE_FRAGMENTS: int      = 30    # global cap; excess converts to debris
const MAX_DEBRIS_FIELDS: int         = 15    # global cap on debris aggregation zones

# --- Sleep system ---
# Bodies with speed below threshold for SLEEP_CONFIRM_TIME seconds → sleeping
const SLEEP_SPEED_SQ: float      = 0.01   # speed² threshold (= 0.1 units/s)
const SLEEP_CONFIRM_TIME: float  = 2.0    # seconds before confirmed sleep
# Level-A and kinematic bodies never sleep; only B/C eligible

# --- Gravity softening ---
# Prevents division-by-near-zero when bodies overlap before collision fires
const GRAVITY_SOFTENING_SQ: float = 4.0

# --- Fixed timestep ---
const FIXED_DT: float      = 1.0 / 60.0   # 60 Hz physics tick
const MAX_TIME_SCALE: float = 500.0        # max sim speed-up multiplier
const MIN_TIME_SCALE: float = 0.1

# --- Rendering scale ---
# 1 AU in sim-units should map to this many screen pixels from star center.
# Tune this to control how much of the system is visible at default zoom.
const SIM_TO_SCREEN: float = 0.4   # pixels per sim-unit (1 AU = 400 px at default)

# --- Debug gravity rings ---
# Fixed acceleration thresholds used by the debug renderer. These are visual
# reference bands around stars, not physical gravity cutoffs.
const GRAVITY_DEBUG_THRESHOLDS := [300.0, 100.0, 30.0, 10.0]
const GRAVITY_DEBUG_COLORS := [
	Color(1.0, 0.78, 0.26, 0.30),
	Color(0.95, 0.52, 0.22, 0.26),
	Color(0.38, 0.86, 0.92, 0.22),
	Color(0.36, 0.58, 1.0, 0.18),
]
const GRAVITY_DEBUG_LINE_WIDTH: float = 1.0
const GRAVITY_DEBUG_MIN_SCREEN_RADIUS: float = 8.0

# --- Anchor field debug/layout ---
# Practical dominance threshold used for BH field layout and diagnostics.
# This is a read-only helper value, not a hard gravity cutoff.
const ANCHOR_DOMINANCE_THRESHOLD: float = 10.0
const MAX_FIELD_PATCH_BLACK_HOLES: int = 61
const ANCHOR_FIELD_RING_SLOT_SCALE: int = 6

# --- Dominant BH nearfield integration ---
# Phase A is intentionally numerical only: bodies very close to a dominant BH
# are integrated with smaller local timesteps so high speed resolves as
# stronger curvature/orbital steering, not as a coarse-timestep escape spike.
const BH_NEARFIELD_DISTANCE_FACTOR: float = 0.22
const BH_NEARFIELD_SUBSTEPS: int = 8

# --- Body radii (visual, in sim-units) ---
# Real radii span many orders of magnitude; we use stylized sizes for readability.
const STAR_RADIUS: float     = 30.0
const BLACK_HOLE_RADIUS: float = 20.0
const PLANET_RADIUS_MIN: float = 8.0
const PLANET_RADIUS_MAX: float = 16.0
const ASTEROID_RADIUS_MIN: float = 2.0
const ASTEROID_RADIUS_MAX: float = 5.0
const FRAGMENT_RADIUS_MIN: float = 1.0
const FRAGMENT_RADIUS_MAX: float = 2.5

# --- Render exaggeration ---
# Keep simulation radii intact, but draw key bodies slightly larger so they stay
# readable while zoomed out. This affects visuals and debug picking only.
const STAR_VISUAL_SCALE: float = 4.0
const BLACK_HOLE_VISUAL_SCALE: float = 3.0
const PLANET_VISUAL_SCALE: float = 4.4
const ASTEROID_VISUAL_SCALE: float = 6.0
const FRAGMENT_VISUAL_SCALE: float = 3.5

const STAR_MIN_SCREEN_RADIUS: float = 20.0
const BLACK_HOLE_MIN_SCREEN_RADIUS: float = 12.0
const PLANET_MIN_SCREEN_RADIUS: float = 12.0
const ASTEROID_MIN_SCREEN_RADIUS: float = 7.0
const FRAGMENT_MIN_SCREEN_RADIUS: float = 4.0

# --- B-B gravity proximity cutoff ---
# Asteroid-Asteroid gravity only computed within this distance (sim-units).
# Prevents O(n²) cost across spread-out belts.
const B_B_GRAVITY_RADIUS_SQ: float = 300.0 * 300.0

# --- Debris field ---
# Debris within this radius of an existing field gets merged into it
const DEBRIS_MERGE_RADIUS: float = 80.0
