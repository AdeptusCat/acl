class_name ConnectedWalls
extends RefCounted

const DIRECTORY: String = "res://assets/tiles/walls/connected/"
const TILE_SET_PATH: String = "res://resources/tilesets/walls.tres"
const LAYER_SCENE: String = "res://scenes/world/maps/layers/wall_tile_map_layer.tscn"
const ART_REGION_SIZE: Vector2i = Vector2i(160, 160)
const LABELS: Array[String] = ["Wall", "Hedge"]
const STYLES: Array[String] = ["stone", "hedge"]
const LEGACY_STYLES: Array[String] = ["stone", "stone", "stone", "hedge", "stone", "hedge", "hedge", "hedge", "hedge", "hedge"]
const LEGACY_MASKS: Array[int] = [8, 16, 24, 16, 6, 24, 4, 4, 6, 8]
const EDGES: Array[String] = ["n", "ne", "se", "s", "sw", "nw"]
const VERTICES: Array[Vector2] = [Vector2(-32, -64), Vector2(32, -64), Vector2(64, 0), Vector2(32, 64), Vector2(-32, 64), Vector2(-64, 0)]
const SIDES: Array[TileSet.CellNeighbor] = [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE]


static func is_barrier(data: TileData) -> bool:
	return data != null and data.has_custom_data("barrier_connected") and bool(data.get_custom_data("barrier_connected"))


static func atlas_coords(mask: int) -> Vector2i:
	return Vector2i(mask % 8, mask / 8)


static func edge_mask(data: TileData) -> int:
	if data == null:
		return 0
	var mask: int = 0
	for side: int in range(6):
		if data.has_custom_data(EDGES[side]) and bool(data.get_custom_data(EDGES[side])):
			mask |= 1 << side
	return mask


static func source_for(tiles: TileSet, kind: int) -> int:
	var path: String = DIRECTORY + STYLES[kind] + "_connections.png"
	for index: int in range(tiles.get_source_count()):
		var id: int = tiles.get_source_id(index)
		var source: TileSetAtlasSource = tiles.get_source(id) as TileSetAtlasSource
		if source != null and source.texture.resource_path == path:
			return id
	return -1


static func install(tiles: TileSet) -> void:
	for entry: Array in [["barrier_connected", TYPE_BOOL], ["connections", TYPE_INT]]:
		if tiles.get_custom_data_layer_by_name(entry[0]) < 0:
			var index: int = tiles.get_custom_data_layers_count()
			tiles.add_custom_data_layer()
			tiles.set_custom_data_layer_name(index, entry[0])
			tiles.set_custom_data_layer_type(index, entry[1])
	# These are hex-side barriers, not terrains occupying or linking hex centers.
	while tiles.get_terrain_sets_count() > 0:
		tiles.remove_terrain_set(tiles.get_terrain_sets_count() - 1)
	for kind: int in range(2):
		var id: int = source_for(tiles, kind)
		var source: TileSetAtlasSource = TileSetAtlasSource.new()
		source.resource_name = ["Stone Wall Edges", "Hedge Edges"][kind]
		source.texture = load(DIRECTORY + STYLES[kind] + "_connections.png") as Texture2D
		source.texture_region_size = ART_REGION_SIZE
		if id >= 0:
			source.resource_scene_unique_id = tiles.get_source(id).resource_scene_unique_id
			tiles.remove_source(id)
		tiles.add_source(source, id)
		for mask: int in range(1, 64):
			var atlas: Vector2i = atlas_coords(mask)
			source.create_tile(atlas)
			var data: TileData = source.get_tile_data(atlas, 0)
			for side: int in range(6):
				data.set_custom_data(EDGES[side], bool(mask & (1 << side)))
			data.set_custom_data("name", LABELS[kind])
			data.set_custom_data("cover", 2 - kind)
			data.set_custom_data("barrier_connected", true)
			data.set_custom_data("connections", mask)
	# Keep legacy cell IDs, alternatives and directional cover untouched.
	for id: int in range(10):
		if tiles.has_source(id):
			var source: TileSetAtlasSource = tiles.get_source(id) as TileSetAtlasSource
			source.texture = load(DIRECTORY + "legacy_" + LEGACY_STYLES[id] + "_%02d.png" % id) as Texture2D
			source.texture_region_size = ART_REGION_SIZE
			source.resource_name = "Legacy " + LEGACY_STYLES[id] + " edge " + str(id)
