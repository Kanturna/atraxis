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

static func is_position_within_cluster_import_radius(
		global_position: Vector2,
		cluster_state: ClusterState) -> bool:
	if cluster_state == null:
		return false
	return global_position.distance_to(cluster_state.global_center) <= transit_import_radius(cluster_state)

static func cluster_claim_score_for_position(
		global_position: Vector2,
		cluster_state: ClusterState) -> float:
	if cluster_state == null:
		return INF
	var import_radius: float = maxf(transit_import_radius(cluster_state), 1.0)
	var distance_to_center: float = global_position.distance_to(cluster_state.global_center)
	var distance_outside_import: float = maxf(0.0, distance_to_center - import_radius)
	return distance_outside_import / import_radius

static func transit_cluster_claim_score(transit_state, cluster_state: ClusterState) -> float:
	if not supports_transit_import(transit_state) or cluster_state == null:
		return INF
	return cluster_claim_score_for_position(transit_state.global_position, cluster_state)

static func should_keep_routing_target_for_position(
		global_position: Vector2,
		current_target: ClusterState,
		challenger_target: ClusterState) -> bool:
	if current_target == null:
		return false
	if challenger_target == null or challenger_target.cluster_id == current_target.cluster_id:
		return true
	if is_position_within_cluster_import_radius(global_position, current_target):
		return true
	if is_position_within_cluster_import_radius(global_position, challenger_target):
		return false
	var current_lock_radius: float = transit_import_radius(current_target) \
		* SimConstants.CLUSTER_TRANSIT_ROUTING_LOCK_RADIUS_FACTOR
	var distance_to_current: float = global_position.distance_to(current_target.global_center)
	if distance_to_current <= current_lock_radius:
		return true
	var current_score: float = cluster_claim_score_for_position(global_position, current_target)
	var challenger_score: float = cluster_claim_score_for_position(global_position, challenger_target)
	return current_score <= challenger_score + SimConstants.CLUSTER_TRANSIT_ROUTING_SCORE_MARGIN

static func should_keep_transit_target(
		transit_state,
		current_target: ClusterState,
		challenger_target: ClusterState) -> bool:
	if transit_state == null or current_target == null:
		return false
	return should_keep_routing_target_for_position(
		transit_state.global_position,
		current_target,
		challenger_target
	)

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
	return is_position_within_cluster_import_radius(transit_state.global_position, cluster_state)
