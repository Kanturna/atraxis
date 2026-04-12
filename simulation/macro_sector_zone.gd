## Semantic zone inside the active Makrosektor.
## This is intentionally separate from cluster lifecycle states.
class_name MacroSectorZone
extends RefCounted

enum Zone {
	FOCUS = 0,
	AMBIENT = 1,
	FAR = 2,
	OUTSIDE = 3,
}

static func debug_name(zone: int) -> String:
	match zone:
		Zone.FOCUS:
			return "focus"
		Zone.AMBIENT:
			return "ambient"
		Zone.FAR:
			return "far"
		_:
			return "outside"
