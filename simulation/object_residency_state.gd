## Lifecycle state for cluster-owned objects across simulation layers.
class_name ObjectResidencyState
extends RefCounted

enum State {
	RESIDENT = 0,
	ACTIVE = 1,
	SIMPLIFIED = 2,
	IN_TRANSIT = 3,
}

