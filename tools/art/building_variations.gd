class_name BuildingVariations
extends RefCounted

const DIRECTORY: String = "res://assets/tiles/buildings/rotated/"
const LAYER_SCENE: String = "res://scenes/world/maps/layers/building_tile_map_layer.tscn"
const SHARED_TILE_SET: String = "res://resources/tilesets/buildings.tres"
const ORIENTATION_COUNT: int = 6
const ALIASES: Dictionary[String, String] = {"house": "building_stone_01", "house2": "building_stone_02", "big_building": "building_stone_03"}
const VARIANTS: Dictionary[String, String] = {
	"building_stone_01": "Stone Building 01",
	"building_stone_02": "Stone Building 02",
	"building_stone_03": "Stone Building 03",
	"building_wood_01": "Wood Building 01",
	"building_wood_02": "Wood Building 02",
	"building_wood_03": "Wood Building 03",
}


static func apply(layer: HexagonTileMapLayer, identity: String) -> void:
	install(layer.tile_set)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = identity.hash() + 731947
	var cells: Array[Vector2i] = layer.get_used_cells()
	cells.sort()
	for cell: Vector2i in cells:
		var source_id: int = layer.get_cell_source_id(cell)
		var source: TileSetAtlasSource = layer.tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null or not source.texture.resource_path.begins_with(DIRECTORY):
			continue
		layer.set_cell(cell, source_id, Vector2i(random.randi_range(0, ORIENTATION_COUNT - 1), 0))


static func install(tiles: TileSet) -> void:
	var ids: Array[int] = []
	var available: Dictionary[String, bool] = {}
	var stone: TileSetAtlasSource
	for index: int in range(tiles.get_source_count()):
		ids.append(tiles.get_source_id(index))
	for id: int in ids:
		var original: TileSetAtlasSource = tiles.get_source(id) as TileSetAtlasSource
		if original == null or original.texture == null or not original.has_tile(Vector2i.ZERO):
			continue
		if original.texture.resource_path.begins_with(MultihexBuildings.DIRECTORY):
			continue
		var data: TileData = original.get_tile_data(Vector2i.ZERO, 0)
		if str(data.get_custom_data("name")) not in ["Stone Building", "Wood Building", "Wooden Building"]:
			continue
		var variant: String = original.texture.resource_path.get_file().get_basename()
		variant = ALIASES.get(variant, variant)
		assert(VARIANTS.has(variant), "Unknown building design: " + variant)
		available[variant] = true
		var source: TileSetAtlasSource = original
		if original.texture.resource_path != texture_path(variant) or not original.has_tile(Vector2i(ORIENTATION_COUNT - 1, 0)):
			source = _install_source(tiles, original, variant, id)
		source.resource_name = VARIANTS[variant]
		if str(source.get_tile_data(Vector2i.ZERO, 0).get_custom_data("name")) == "Stone Building":
			stone = source
	if not available.has("building_stone_03"):
		assert(stone != null, "The large building needs stone cover metadata")
		_install_source(tiles, stone, "building_stone_03")


static func _install_source(tiles: TileSet, original: TileSetAtlasSource, variant: String, id: int = -1) -> TileSetAtlasSource:
	var path: String = texture_path(variant)
	assert(ResourceLoader.exists(path), "Missing approved building atlas: " + path)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.resource_name = VARIANTS[variant]
	if id >= 0:
		source.resource_scene_unique_id = original.resource_scene_unique_id
	source.texture = load(path) as Texture2D
	source.texture_region_size = Vector2i(128, 128)
	var data: TileData = original.get_tile_data(Vector2i.ZERO, 0)
	var custom_values: Array = []
	for custom: int in range(tiles.get_custom_data_layers_count()):
		custom_values.append(data.get_custom_data_by_layer_id(custom))
	# Retain source IDs when replacing art; new designs receive an unused ID.
	if id >= 0:
		tiles.remove_source(id)
	tiles.add_source(source, id)
	for orientation: int in range(ORIENTATION_COUNT):
		var tile: Vector2i = Vector2i(orientation, 0)
		source.create_tile(tile)
		var copy: TileData = source.get_tile_data(tile, 0)
		for custom: int in range(tiles.get_custom_data_layers_count()):
			copy.set_custom_data_by_layer_id(custom, custom_values[custom])
	return source


static func use_shared(layer: HexagonTileMapLayer, shared: TileSet) -> void:
	var original: TileSet = layer.tile_set
	var ids: Dictionary[int, int] = {}
	for index: int in range(original.get_source_count()):
		var id: int = original.get_source_id(index)
		var source: TileSetAtlasSource = original.get_source(id) as TileSetAtlasSource
		var key: String = _source_key(source)
		var target: int = -1
		for shared_index: int in range(shared.get_source_count()):
			var shared_id: int = shared.get_source_id(shared_index)
			if _source_key(shared.get_source(shared_id) as TileSetAtlasSource) == key:
				target = shared_id
				break
		if target < 0:
			var copy: TileSetAtlasSource = source.duplicate(true) as TileSetAtlasSource
			copy.resource_scene_unique_id = ""
			copy.texture = source.texture
			target = shared.add_source(copy)
		ids[id] = target
	var cells: Array[Vector2i] = layer.get_used_cells()
	var values: Array[Vector3i] = []
	for cell: Vector2i in cells:
		var atlas: Vector2i = layer.get_cell_atlas_coords(cell)
		values.append(Vector3i(atlas.x, atlas.y, layer.get_cell_alternative_tile(cell)))
	var sources: Array[int] = []
	for cell: Vector2i in cells:
		sources.append(ids[layer.get_cell_source_id(cell)])
	layer.tile_set = shared
	for index: int in range(cells.size()):
		layer.set_cell(cells[index], sources[index], Vector2i(values[index].x, values[index].y), values[index].z)


static func _source_key(source: TileSetAtlasSource) -> String:
	var data: TileData = source.get_tile_data(source.get_tile_id(0), 0)
	var path: String = source.texture.resource_path
	var kind: String = str(data.get_custom_data("name"))
	if kind in ["Stone Building", "Wood Building", "Wooden Building"] and not path.begins_with(MultihexBuildings.DIRECTORY):
		var variant: String = path.get_file().get_basename()
		path = texture_path(ALIASES.get(variant, variant))
	return path + "/" + kind + "/" + str(data.get_custom_data("cover")) + "/" + str(data.get_custom_data("art_family"))


static func texture_path(variant: String) -> String:
	return DIRECTORY + variant + ".png"
