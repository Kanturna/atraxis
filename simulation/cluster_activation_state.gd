## Lifecycle state of a cluster inside the galaxy data model.
class_name ClusterActivationState
extends RefCounted

enum State {
	UNLOADED = 0,
	SIMPLIFIED = 1,
	ACTIVE = 2,
}

