extends RefCounted

static var _random: RandomNumberGenerator = RandomNumberGenerator.new()
static var _seeded: bool = false


static func create(ground: TileMapLayer, cell: Vector2i, firing_origin: Vector2, rounds: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	if rounds <= 0 or not is_instance_valid(ground) or ground.tile_set == null:
		return points
	if not _seeded:
		_random.randomize()
		_seeded = true
	var center: Vector2 = ground.map_to_local(cell)
	var tile_size: Vector2 = Vector2(ground.tile_set.tile_size)
	if rounds == 1:
		points.append(_to_world(ground, cell, center, tile_size, _disk(0.34)))
		return points
	# Work in tile-relative coordinates so the inset also fits stretched hexes.
	var aim: Vector2 = (center - ground.to_local(firing_origin)) / tile_size
	if aim.is_zero_approx():
		aim = Vector2.RIGHT
	var direction: Vector2 = aim.normalized().orthogonal().rotated(_random.randf_range(-0.6, 0.6))
	if _random.randf() < 0.5:
		direction = -direction
	var middle: Vector2 = _disk(0.08)
	var half_span: float = _random.randf_range(0.16, 0.26)
	var start: Vector2 = middle - direction * half_span
	var end: Vector2 = middle + direction * half_span
	var control: Vector2 = middle
	if _random.randf() < 0.65:
		control += direction.orthogonal() * _random.randf_range(-0.12, 0.12)
	for index: int in range(rounds):
		var fraction: float = float(index) / float(rounds - 1)
		if index > 0 and index < rounds - 1:
			fraction += _random.randf_range(-0.16, 0.16) / float(rounds - 1)
		var offset: Vector2 = bezier_point(start, control, end, fraction)
		points.append(_to_world(ground, cell, center, tile_size, offset))
	return points


static func bezier_point(start: Vector2, control: Vector2, end: Vector2, fraction: float) -> Vector2:
	return start.lerp(control, fraction).lerp(control.lerp(end, fraction), fraction)


static func _disk(radius: float) -> Vector2:
	return Vector2.from_angle(_random.randf_range(0.0, TAU)) * sqrt(_random.randf()) * radius


static func _to_world(ground: TileMapLayer, cell: Vector2i, center: Vector2, tile_size: Vector2, offset: Vector2) -> Vector2:
	var point: Vector2 = center + offset * tile_size
	# Keep the actual TileMap ownership check as the final boundary authority.
	for attempt: int in range(8):
		if ground.local_to_map(point) == cell:
			return ground.to_global(point)
		point = point.lerp(center, 0.5)
	return ground.to_global(center)
