class_name LosBakeCache
extends RefCounted

const VERSION: int = 2

# Immutable for one rebuild. Live combat queries keep using the current layers.
class Sprite extends RefCounted:
	var layer: TileMapLayer
	var cell: Vector2i
	var region: Rect2i
	var center: Vector2
	var bounds: Rect2
	var alpha: BitMap
	var image_size: Vector2i
	var clip_to_cell: bool
	var transpose: bool
	var flip_h: bool
	var flip_v: bool
	var blocks: bool
	var hinders: bool
	var signature: Array

	func entry(origin: Vector2, target: Vector2, step_size: float) -> Vector2:
		if alpha == null:
			return Vector2.INF
		var delta: Vector2 = target - origin
		var near: float = 0.0
		var far: float = 1.0
		for axis: int in range(2):
			if absf(delta[axis]) < 0.000001:
				if origin[axis] < bounds.position[axis] or origin[axis] >= bounds.end[axis]:
					return Vector2.INF
				continue
			var first: float = (bounds.position[axis] - origin[axis]) / delta[axis]
			var last: float = (bounds.end[axis] - origin[axis]) / delta[axis]
			near = maxf(near, minf(first, last))
			far = minf(far, maxf(first, last))
			if near > far:
				return Vector2.INF
		# Keep the original sampling interval and phase, including thin alpha edges.
		var steps: int = maxi(1, ceili(delta.length() * (far - near) / step_size))
		for index: int in range(steps + 1):
			var point: Vector2 = origin.lerp(target, lerpf(near, far, float(index) / float(steps)))
			if clip_to_cell and layer.local_to_map(point) != cell:
				continue
			var offset: Vector2 = point - center
			if transpose:
				offset = Vector2(offset.y, offset.x)
			if flip_h:
				offset.x = -offset.x
			if flip_v:
				offset.y = -offset.y
			var pixel: Vector2i = Vector2i((offset + Vector2(region.size) * 0.5).floor())
			if pixel.x < 0 or pixel.y < 0 or pixel.x >= region.size.x or pixel.y >= region.size.y:
				continue
			pixel += region.position
			if pixel.x < image_size.x and pixel.y < image_size.y and alpha.get_bitv(pixel):
				return point
		return Vector2.INF

var positions: Dictionary[Vector2i, Vector2] = {}
var endpoint_cover: Dictionary[Vector2, int] = {}
var endpoint_concealment: Dictionary[Vector2, int] = {}
var walls: Dictionary[Vector2i, Vector2i] = {}
var buildings: Dictionary[Vector2i, Sprite] = {}
var terrain: Dictionary[Vector2i, Sprite] = {}
var ground_layer: HexagonTileMapLayer
var building_layer: TileMapLayer
var terrain_layer: TileMapLayer
var wall_layer: TileMapLayer
var _masks: Dictionary[Texture2D, BitMap] = {}
var _image_signatures: Dictionary[Texture2D, String] = {}
var _rings: Dictionary[Vector3i, Array] = {}


func setup(ground: HexagonTileMapLayer, building: TileMapLayer, wall: TileMapLayer, plants: TileMapLayer) -> void:
	ground_layer = ground
	building_layer = building
	terrain_layer = plants
	wall_layer = wall
	for cell: Vector2i in building.get_used_cells():
		var sprite: Sprite = _snapshot(building, cell)
		if sprite != null:
			buildings[cell] = sprite
	for cell: Vector2i in plants.get_used_cells():
		var data: TileData = plants.get_cell_tile_data(cell)
		if not (data.has_custom_data("blocking") and bool(data.get_custom_data("blocking"))) and not (data.has_custom_data("hindrance") and bool(data.get_custom_data("hindrance"))):
			continue
		var sprite: Sprite = _snapshot(plants, cell)
		if sprite != null:
			terrain[cell] = sprite
	for cell: Vector2i in wall.get_used_cells():
		var data: TileData = wall.get_cell_tile_data(cell)
		var cover: int = int(data.get_custom_data("cover"))
		walls[cell] = Vector2i(ConnectedWalls.edge_mask(data), cover)


func _snapshot(layer: TileMapLayer, cell: Vector2i) -> Sprite:
	var source: TileSetAtlasSource = layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
	if source == null or source.texture == null:
		return null
	if not _masks.has(source.texture):
		var image: Image = source.texture.get_image()
		var mask: BitMap
		if image != null:
			mask = BitMap.new()
			mask.create_from_image_alpha(image, 0.1)
			var hash: HashingContext = HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(image.get_data())
			_image_signatures[source.texture] = str([image.get_size(), image.get_format(), hash.finish().hex_encode()])
		_masks[source.texture] = mask
	var data: TileData = layer.get_cell_tile_data(cell)
	var sprite: Sprite = Sprite.new()
	sprite.layer = layer
	sprite.cell = cell
	sprite.region = source.get_tile_texture_region(layer.get_cell_atlas_coords(cell))
	sprite.center = layer.map_to_local(cell) - Vector2(data.texture_origin)
	sprite.alpha = _masks[source.texture]
	if sprite.alpha != null:
		sprite.image_size = sprite.alpha.get_size()
	sprite.clip_to_cell = (data.has_custom_data("building_hexes") and int(data.get_custom_data("building_hexes")) >= 2) or ConnectedWalls.is_barrier(data)
	sprite.transpose = data.transpose
	sprite.flip_h = data.flip_h
	sprite.flip_v = data.flip_v
	sprite.blocks = data.has_custom_data("blocking") and bool(data.get_custom_data("blocking"))
	sprite.hinders = data.has_custom_data("hindrance") and bool(data.get_custom_data("hindrance"))
	var size: Vector2 = Vector2(sprite.region.size)
	if sprite.transpose:
		size = Vector2(size.y, size.x)
	sprite.bounds = Rect2(sprite.center - size * 0.5, size)
	var cover: int = 0
	if data.has_custom_data("cover"):
		cover = int(data.get_custom_data("cover"))
	sprite.signature = [cell, sprite.region, sprite.center, sprite.clip_to_cell, sprite.transpose, sprite.flip_h, sprite.flip_v, sprite.blocks, sprite.hinders, cover, _image_signatures.get(source.texture, "")]
	return sprite


func fingerprint(size: Vector2i, step_size: float) -> String:
	# Cover all inputs, including vegetation pixels and directional wall metadata.
	var input: Array = [VERSION, size, step_size, ground_layer.tile_map_data, positions, endpoint_cover, endpoint_concealment]
	for layer: TileMapLayer in [ground_layer, building_layer, terrain_layer, wall_layer]:
		input.append([layer.tile_set.tile_shape, layer.tile_set.tile_layout, layer.tile_set.tile_offset_axis, layer.tile_set.tile_size])
	for sprites: Dictionary[Vector2i, Sprite] in [buildings, terrain]:
		var cells: Array[Vector2i] = sprites.keys()
		cells.sort()
		for cell: Vector2i in cells:
			input.append(sprites[cell].signature)
	var wall_cells: Array[Vector2i] = walls.keys()
	wall_cells.sort()
	for cell: Vector2i in wall_cells:
		input.append([cell, walls[cell]])
	return var_to_bytes(input).hex_encode().sha256_text()


func candidates(hexes: Array[Vector3i]) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	for cube: Vector3i in hexes:
		if not _rings.has(cube):
			var ring: Array[Vector2i] = []
			var neighbors: Array[Vector3i] = [cube]
			neighbors.append_array(ground_layer.cube_neighbors(cube))
			for neighbor: Vector3i in neighbors:
				var cell: Vector2i = ground_layer.cube_to_map(neighbor)
				if buildings.has(cell) or terrain.has(cell):
					ring.append(cell)
			_rings[cube] = ring
		# Preserve first-encounter order: the original ray returns its first blocker.
		for cell: Vector2i in _rings[cube]:
			result[cell] = true
	return result


func check_obstacles(origin: Vector2, target: Vector2, hexes: Array[Vector3i], result: Dictionary, step_size: float) -> Dictionary:
	var origin_cell: Vector2i = ground_layer.local_to_map(origin)
	var target_cell: Vector2i = ground_layer.local_to_map(target)
	for cell: Vector2i in candidates(hexes):
		if cell == origin_cell or cell == target_cell:
			continue
		var building: Sprite = buildings.get(cell)
		if building != null:
			var hit: Vector2 = building.entry(origin, target, step_size)
			if hit != Vector2.INF:
				result.blocked = true
				result.block_point = hit
				return result
		var plant: Sprite = terrain.get(cell)
		if plant == null:
			continue
		var hit: Vector2 = plant.entry(origin, target, step_size)
		if hit == Vector2.INF:
			continue
		if plant.hinders:
			result.hindrance += 1
			result.shooter_cover += 1
			result.target_cover += 1
		if plant.blocks:
			result.blocked = true
			result.block_point = hit
			return result
	return result
