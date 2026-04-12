## Central rules for when objects can move between cluster residency layers.
## Keep this intentionally narrow: only free dynamic non-anchor bodies may
## enter the first IN_TRANSIT pipeline in this phase.
class_name ObjectResidencyPolicy
extends RefCounted

static func supports_active_transit_export(body: SimBody) -> bool:
	if body == null or not body.active:
		return false
	if body.scripted_orbit_enabled or body.is_analytic_orbit_bound():
		return false
	return body.body_type in [
		SimBody.BodyType.PLANET,
		SimBody.BodyType.ASTEROID,
		SimBody.BodyType.FRAGMENT,
	]

static func supports_transit_import(transit_state) -> bool:
	if transit_state == null:
		return false
	return transit_state.kind in ["planet", "asteroid", "fragment"]

static func transit_export_radius(cluster_state: ClusterState) -> float:
	if cluster_state == null:
		return 0.0
	return cluster_state.radius * SimConstants.CLUSTER_TRANSIT_EXPORT_RADIUS_FACTOR

static func transit_import_radius(cluster_state: ClusterState) -> float:
	if cluster_state == null:
		return 0.0
	return cluster_state.radius * SimConstants.CLUSTER_TRANSIT_IMPORT_RADIUS_FACTOR

static func residency_state_for_cluster_activation(activation_state: int) -> int:
	match activation_state:
		ClusterActivationState.State.ACTIVE:
			return ObjectResidencyState.State.ACTIVE
		ClusterActivationState.State.SIMPLIFIED:
			return ObjectResidencyState.State.SIMPLIFIED
		_:
			return ObjectResidencyState.State.RESIDENT

static func should_export_body_from_active_cluster(body: SimBody, cluster_state: ClusterState) -> bool:
	if not supports_active_transit_export(body) or cluster_state == null:
		return false
	return body.position.length() > transit_export_radius(cluster_state)

static func can_import_transit_object_into_cluster(
		transit_state,
		cluster_state: ClusterState) -> bool:
	if not supports_transit_import(transit_state) or cluster_state == null:
		return false
	return transit_state.global_position.distance_to(cluster_state.global_center) <= transit_import_radius(cluster_state)
