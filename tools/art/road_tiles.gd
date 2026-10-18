class_name RoadTiles
extends RefCounted

const TILE_SET_PATH: String = "res://resources/tilesets/roads.tres"
const LAYER_SCENE: String = "res://scenes/world/maps/layers/road_tile_map_layer.tscn"


static func is_road(data: TileData) -> bool:
	return data != null and data.has_custom_data("name") and str(data.get_custom_data("name")) == "Road"


static func install_curve(tiles: TileSet, texture_path: String, label: String, cells: Dictionary) -> int:
	var source_id: int = -1
	for index: int in range(tiles.get_source_count()):
		var id: int = tiles.get_source_id(index)
		var existing: TileSetAtlasSource = tiles.get_source(id) as TileSetAtlasSource
		if existing != null and existing.texture.resource_path == texture_path:
			source_id = id
			break
	var source: TileSetAtlasSource
	if source_id >= 0:
		source = tiles.get_source(source_id) as TileSetAtlasSource
	else:
		source = TileSetAtlasSource.new()
		source.texture = load(texture_path) as Texture2D
		assert(source.texture != null, "Generate and import the road atlas first: " + texture_path)
		source.texture_region_size = Vector2i(128, 128)
		source_id = tiles.add_source(source)
	source.resource_name = label
	for cell: Vector2i in cells:
		var atlas: Vector2i = cells[cell]
		if not source.has_tile(atlas):
			source.create_tile(atlas)
		source.get_tile_data(atlas, 0).set_custom_data("name", "Road")
	return source_id
