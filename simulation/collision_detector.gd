## collision_detector.gd
## Broadphase (spatial grid) + narrowphase (circle-circle) collision detection.
class_name CollisionDetector
extends RefCounted

## Result of a narrowphase check between two bodies.
class CollisionResult:
	var colliding: bool = false
	var body_a: SimBody
	var body_b: SimBody
	var penetration_depth: float = 0.0
	var collision_normal: Vector2 = Vector2.ZERO  # from b toward a
	var relative_velocity: Vector2 = Vector2.ZERO
	var approach_speed: float = 0.0               # positive = approaching

## Returns candidate pairs from broadphase. Each entry is [SimBody, SimBody].
func broadphase(bodies: Array) -> Array:
	var candidates: Array = []
	var grid: Dictionary = {}
	var cell_size: float = _estimate_cell_size(bodies)

	# Insert bodies into grid
	for body in bodies:
		if not body.active or body.sleeping:
			continue
		if body.body_type == SimBody.BodyType.STAR:
			continue  # Star handles impacts differently; skip as broadphase source
		var cell: Vector2i = _cell(body.position, cell_size)
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(body)

	# Check each cell against itself and 8 neighbors
	var checked: Dictionary = {}
	for cell in grid.keys():
		var all_neighbors: Array = _neighbor_cells(cell)
		for neighbor in all_neighbors:
			if not grid.has(neighbor):
				continue
			var list_a: Array = grid[cell]
			var list_b: Array = grid[neighbor]
			for ba in list_a:
				for bb in list_b:
					if ba.id == bb.id:
						continue
					var key: int = _pair_key(ba.id, bb.id)
					if checked.has(key):
						continue
					checked[key] = true
					# Quick radius overlap pre-filter
					var sum_r: float = ba.radius + bb.radius
					if ba.position.distance_squared_to(bb.position) <= sum_r * sum_r:
						candidates.append([ba, bb])

	return candidates

## Full circle-circle narrowphase check.
func narrowphase(body_a: SimBody, body_b: SimBody) -> CollisionResult:
	var result := CollisionResult.new()
	result.body_a = body_a
	result.body_b = body_b

	var delta: Vector2 = body_a.position - body_b.position
	var dist: float = delta.length()
	var sum_r: float = body_a.radius + body_b.radius

	if dist >= sum_r:
		return result  # Not colliding

	result.colliding = true
	result.penetration_depth = sum_r - dist

	if dist < 0.0001:
		result.collision_normal = Vector2(1.0, 0.0)  # Coincident fallback
	else:
		result.collision_normal = delta / dist

	result.relative_velocity = body_a.velocity - body_b.velocity
	result.approach_speed = result.relative_velocity.dot(-result.collision_normal)

	return result

func _estimate_cell_size(bodies: Array) -> float:
	var total_r: float = 0.0
	var count: int = 0
	for body in bodies:
		if body.active and body.body_type != SimBody.BodyType.STAR:
			total_r += body.radius
			count += 1
	if count == 0:
		return 20.0
	return max(4.0 * total_r / count, 10.0)

func _cell(pos: Vector2, cell_size: float) -> Vector2i:
	return Vector2i(int(floor(pos.x / cell_size)), int(floor(pos.y / cell_size)))

func _neighbor_cells(cell: Vector2i) -> Array:
	var result: Array = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			result.append(Vector2i(cell.x + dx, cell.y + dy))
	return result

func _pair_key(id_a: int, id_b: int) -> int:
	var lo: int = min(id_a, id_b)
	var hi: int = max(id_a, id_b)
	return lo * 100_000 + hi
