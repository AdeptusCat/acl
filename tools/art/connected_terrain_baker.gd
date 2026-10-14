class_name ConnectedTerrainBaker
extends RefCounted

const TILE_SIZE: int = 128
const COLUMNS: int = 8
const FRINGE: float = 12.0
const DIRECTIONS: Array[Vector3i] = [Vector3i(0, -1, 1), Vector3i(1, -1, 0), Vector3i(1, 0, -1), Vector3i(0, 1, -1), Vector3i(-1, 1, 0), Vector3i(-1, 0, 1)]
const NORMALS: Array[Vector2] = [Vector2(0, -1), Vector2(0.894427, -0.447214), Vector2(0.894427, 0.447214), Vector2(0, 1), Vector2(-0.894427, 0.447214), Vector2(-0.894427, -0.447214)]
const DISTANCES: Array[float] = [64.0, 57.24334, 57.24334, 64.0, 57.24334, 57.24334]


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
	var patterns: Dictionary[String, Image] = {}
	for family: String in ["woods", "wheat", "crops", "orchard"]:
		patterns[family] = (load("res://assets/tiles/connected/" + family + ".png") as Texture2D).get_image()
	var atlas: Image = Image.create(COLUMNS * TILE_SIZE, ceili(float(families.size()) / float(COLUMNS)) * TILE_SIZE, false, Image.FORMAT_RGBA8)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.resource_name = "Connected terrain - " + id
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var cells: Array[Vector2i] = []
	cells.assign(families.keys())
	cells.sort()
	for index: int in range(cells.size()):
		var cell: Vector2i = cells[index]
		var family: String = families[cell]
		var pattern: Image = patterns[family]
		var center: Vector2 = layer.map_to_local(cell)
		var cube: Vector3i = layer.map_to_cube(cell)
		var tile: Vector2i = Vector2i(index % COLUMNS, index / COLUMNS)
		var joins: Array[bool] = []
		for direction: Vector3i in DIRECTIONS:
			joins.append(families.get(layer.cube_to_map(cube + direction), "") == family)
		for y: int in range(TILE_SIZE):
			for x: int in range(TILE_SIZE):
				var local: Vector2 = Vector2(x + 0.5 - 64.0, y + 0.5 - 64.0)
				var world: Vector2 = center + local
				var alpha: float = 1.0
				for side: int in range(6):
					var inset: float = 0.0
					if not joins[side]:
						inset = FRINGE + 2.0 * sin(world.x * 0.13 + world.y * 0.09)
					alpha = minf(alpha, clampf(DISTANCES[side] - NORMALS[side].dot(local) - inset, 0.0, 1.0))
				if alpha <= 0.0:
					continue
				# Sampling in map coordinates keeps tree crowns and crop rows continuous.
				var color: Color = pattern.get_pixel(posmod(floori(world.x), pattern.get_width()), posmod(floori(world.y), pattern.get_height()))
				color.a *= alpha
				atlas.set_pixel(tile.x * TILE_SIZE + x, tile.y * TILE_SIZE + y, color)
	var directory: String = "res://assets/tiles/connected/maps/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path: String = directory + id + ".png"
	assert(atlas.save_png(path) == OK)
	var texture: ImageTexture = ImageTexture.create_from_image(atlas)
	texture.take_over_path(path)
	source.texture = texture
	var source_id: int = layer.tile_set.add_source(source)
	for index: int in range(cells.size()):
		var cell: Vector2i = cells[index]
		var tile: Vector2i = Vector2i(index % COLUMNS, index / COLUMNS)
		source.create_tile(tile)
		var data: TileData = source.get_tile_data(tile, 0)
		for custom: int in range(layer.tile_set.get_custom_data_layers_count()):
			data.set_custom_data_by_layer_id(custom, originals[cell].get_custom_data_by_layer_id(custom))
		data.set_custom_data("art_family", families[cell])
		layer.set_cell(cell, source_id, tile)
	print("Rendered ", cells.size(), " connected 128-pixel terrain tiles for ", id)


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
