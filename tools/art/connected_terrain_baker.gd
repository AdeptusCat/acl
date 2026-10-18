class_name ConnectedTerrainBaker
extends RefCounted

const TILE_SIZE: int = 128
const COLUMNS: int = 8
const FRINGE: float = 4.0
const DIRECTIONS: Array[Vector3i] = [Vector3i(0, -1, 1), Vector3i(1, -1, 0), Vector3i(1, 0, -1), Vector3i(0, 1, -1), Vector3i(-1, 1, 0), Vector3i(-1, 0, 1)]
const VERTICES: Array[Vector2] = [Vector2(-32, -64), Vector2(32, -64), Vector2(64, 0), Vector2(32, 64), Vector2(-32, 64), Vector2(-64, 0)]


class TerrainRegion extends RefCounted:

	var image: Image
	var origin: Vector2i


static func bake(layer: HexagonTileMapLayer, id: String) -> void:
	var families: Dictionary[Vector2i, String] = {}
	var originals: Dictionary[Vector2i, TileData] = {}
	for cell: Vector2i in layer.get_used_cells():
		var family: String = _family(layer, cell)
		if family != "":
			families[cell] = family
			originals[cell] = layer.get_cell_tile_data(cell)
	if families.is_empty():
		return
	if not originals.values()[0].has_custom_data("art_family"):
		var index: int = layer.tile_set.get_custom_data_layers_count()
		layer.tile_set.add_custom_data_layer()
		layer.tile_set.set_custom_data_layer_name(index, "art_family")
		layer.tile_set.set_custom_data_layer_type(index, TYPE_STRING)
	var regions: Dictionary[String, TerrainRegion] = {}
	for family: String in ["woods", "wheat", "crops", "orchard"]:
		if families.values().has(family):
			regions[family] = render_region(layer, families, family)
	var atlas: Image = Image.create(COLUMNS * TILE_SIZE, ceili(float(families.size()) / float(COLUMNS)) * TILE_SIZE, false, Image.FORMAT_RGBA8)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.resource_name = "Connected terrain - " + id
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var cells: Array[Vector2i] = []
	var custom_data: Dictionary[Vector2i, Array] = {}
	cells.assign(families.keys())
	cells.sort()
	for index: int in range(cells.size()):
		var cell: Vector2i = cells[index]
		var region: TerrainRegion = regions[families[cell]]
		var center: Vector2i = Vector2i(layer.map_to_local(cell))
		var tile: Vector2i = Vector2i(index % COLUMNS, index / COLUMNS)
		var tile_image: Image = region.image.get_region(Rect2i(center - Vector2i(64, 64) - region.origin, Vector2i(TILE_SIZE, TILE_SIZE)))
		for y: int in range(TILE_SIZE):
			for x: int in range(TILE_SIZE):
				# Partition the completed map image here. Never clip individual crowns.
				if not inside_hex(Vector2(x + 0.5 - 64.0, y + 0.5 - 64.0)):
					tile_image.set_pixel(x, y, Color.TRANSPARENT)
		atlas.blit_rect(tile_image, Rect2i(Vector2i.ZERO, tile_image.get_size()), tile * TILE_SIZE)
		var values: Array = []
		for custom: int in range(layer.tile_set.get_custom_data_layers_count()):
			values.append(originals[cell].get_custom_data_by_layer_id(custom))
		custom_data[cell] = values
	var directory: String = "res://assets/tiles/connected/maps/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path: String = directory + id + ".png"
	assert(atlas.save_png(path) == OK)
	var texture: ImageTexture = ImageTexture.create_from_image(atlas)
	texture.take_over_path(path)
	source.texture = texture
	var source_id: int = -1
	for index: int in range(layer.tile_set.get_source_count()):
		var existing_id: int = layer.tile_set.get_source_id(index)
		if layer.tile_set.get_source(existing_id).resource_name == source.resource_name:
			source.resource_scene_unique_id = layer.tile_set.get_source(existing_id).resource_scene_unique_id
			source_id = existing_id
			break
	if source_id >= 0:
		layer.tile_set.remove_source(source_id)
	source_id = layer.tile_set.add_source(source, source_id)
	for index: int in range(cells.size()):
		var cell: Vector2i = cells[index]
		var tile: Vector2i = Vector2i(index % COLUMNS, index / COLUMNS)
		source.create_tile(tile)
		var data: TileData = source.get_tile_data(tile, 0)
		for custom: int in range(layer.tile_set.get_custom_data_layers_count()):
			data.set_custom_data_by_layer_id(custom, custom_data[cell][custom])
		data.set_custom_data("art_family", families[cell])
		layer.set_cell(cell, source_id, tile)
	print("Rendered ", cells.size(), " connected 128-pixel terrain tiles for ", id)


static func inside_hex(point: Vector2) -> bool:
	return absf(point.y) <= 64.0 and absf(point.x) + absf(point.y) * 0.5 <= 64.0


static func render_region(layer: HexagonTileMapLayer, families: Dictionary[Vector2i, String], family: String) -> TerrainRegion:
	var bounds: Rect2 = Rect2()
	var edges: Array[PackedVector2Array] = []
	for cell: Vector2i in families:
		if families[cell] != family:
			continue
		var center: Vector2 = layer.map_to_local(cell)
		var cell_rect: Rect2 = Rect2(center - Vector2(64, 64), Vector2(128, 128))
		if bounds.has_area():
			bounds = bounds.merge(cell_rect)
		else:
			bounds = cell_rect
		var cube: Vector3i = layer.map_to_cube(cell)
		for side: int in range(6):
			if families.get(layer.cube_to_map(cube + DIRECTIONS[side]), "") != family:
				edges.append(PackedVector2Array([center + VERTICES[side], center + VERTICES[(side + 1) % 6]]))
	var region: TerrainRegion = TerrainRegion.new()
	region.origin = Vector2i(bounds.position)
	region.image = Image.create(int(bounds.size.x), int(bounds.size.y), false, Image.FORMAT_RGBA8)
	var crowns: Array[Image] = []
	var crop: Image
	if family == "woods" or family == "orchard":
		var prefix: String = "tree_"
		if family == "orchard":
			prefix = "fruit_"
		for variant: int in range(1, 5):
			crowns.append((load("res://assets/tiles/connected/stamps/" + prefix + "0" + str(variant) + ".png") as Texture2D).get_image())
	else:
		crop = (load("res://assets/tiles/connected/stamps/" + family + ".png") as Texture2D).get_image()
	var along: Vector2 = Vector2.RIGHT
	var across: Vector2 = Vector2.DOWN
	var spacing: Vector2 = Vector2(24, 24)
	if family == "orchard":
		spacing = Vector2(36, 34)
	elif crop != null:
		# Overlapping stands form hand-sown crops without rows or machine lanes.
		spacing = Vector2(14, 14)
	var lattice: Rect2 = Rect2(Vector2(bounds.position.dot(along), bounds.position.dot(across)), Vector2.ZERO)
	for corner: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		lattice = lattice.expand(Vector2(corner.dot(along), corner.dot(across)))
	var cache: Dictionary[Vector2i, Image] = {}
	for row: int in range(floori(lattice.position.y / spacing.y) - 1, ceili(lattice.end.y / spacing.y) + 2):
		for column: int in range(floori(lattice.position.x / spacing.x) - 1, ceili(lattice.end.x / spacing.x) + 2):
			var center: Vector2 = along * column * spacing.x + across * row * spacing.y
			var size: int = 32
			var variant: int = 0
			if crop != null:
				center += Vector2(_noise(column, row, 1) - 0.5, _noise(column, row, 2) - 0.5) * 6.0
			else:
				var jitter: float = 16.0
				if family == "orchard":
					jitter = 8.0
				center += Vector2(_noise(column, row, 1) - 0.5, _noise(column, row, 2) - 0.5) * jitter
				size = 30 + floori(_noise(column, row, 3) * 15.0)
				variant = floori(_noise(column, row, 4) * crowns.size())
				if family == "orchard":
					# Staggered planting remains recognizable across connected orchard hexes.
					center.x += posmod(row, 2) * spacing.x * 0.5
					size = 32 + floori(_noise(column, row, 3) * 9.0)
			center = center.round()
			if families.get(layer.local_to_map(center), "") != family:
				continue
			var distance: float = _edge_distance(center, edges)
			if distance < FRINGE + 3.0:
				continue
			if family == "woods" and distance < size * 0.5 + FRINGE:
				# Saplings taper the fringe without cutting a straight line through foliage.
				size = 18 + floori(_noise(column, row, 5) * 9.0)
			elif family == "orchard" and distance < size * 0.5 + FRINGE:
				size = 24 + floori(_noise(column, row, 5) * 5.0)
			elif crop != null and distance < size * 0.5 + FRINGE:
				size = 16
			if distance < size * 0.5 + FRINGE:
				continue
			var key: Vector2i = Vector2i(variant, size)
			if not cache.has(key):
				var stamp: Image
				if crop != null:
					stamp = crop.duplicate() as Image
				else:
					stamp = crowns[variant].duplicate() as Image
				stamp.resize(size, size, Image.INTERPOLATE_LANCZOS)
				cache[key] = stamp
			var stamp: Image = cache[key]
			var origin: Vector2i = Vector2i(center) - Vector2i(size / 2, size / 2)
			if distance < size * 0.71 and not _stamp_fits(layer, families, family, stamp, origin):
				continue
			region.image.blend_rect(stamp, Rect2i(Vector2i.ZERO, stamp.get_size()), origin - region.origin)
	return region


static func _stamp_fits(layer: HexagonTileMapLayer, families: Dictionary[Vector2i, String], family: String, image: Image, origin: Vector2i) -> bool:
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0 and families.get(layer.local_to_map(Vector2(origin + Vector2i(x, y)) + Vector2(0.5, 0.5)), "") != family:
				return false
	return true


static func _edge_distance(point: Vector2, edges: Array[PackedVector2Array]) -> float:
	var closest_squared: float = INF
	for edge: PackedVector2Array in edges:
		closest_squared = minf(closest_squared, point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point, edge[0], edge[1])))
	return sqrt(closest_squared)


static func _noise(x: int, y: int, salt: int) -> float:
	return float(posmod((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791), 104729)) / 104729.0


static func _family(layer: TileMapLayer, cell: Vector2i) -> String:
	var data: TileData = layer.get_cell_tile_data(cell)
	if data.has_custom_data("art_family") and str(data.get_custom_data("art_family")) != "":
		return str(data.get_custom_data("art_family"))
	if not data.has_custom_data("name"):
		return ""
	var label: String = str(data.get_custom_data("name"))
	if label == "Woods":
		return "woods"
	if label == "Orchard":
		return "orchard"
	if label != "Field":
		return ""
	var source: TileSetAtlasSource = layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
	if "green_rows" in source.texture.resource_path:
		return "crops"
	return "wheat"
