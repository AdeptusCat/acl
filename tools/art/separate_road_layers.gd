extends Node

const ROADS: GDScript = preload("res://tools/art/road_tiles.gd")
const WORLD: String = "res://scenes/world/world.tscn"

var shared: TileSet
var source_ids: Dictionary[String, int] = {}
var terrain_updates: Dictionary[String, Dictionary] = {}
var road_sources: Dictionary[String, bool] = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if FileAccess.file_exists(ROADS.TILE_SET_PATH):
		print("The road layer migration is already installed.")
		get_tree().quit()
		return
	var world: Node = load(WORLD).instantiate()
	var scenes: Dictionary[String, Node] = {WORLD: world}
	var maps: Array[Map] = []
	for map: Map in world.get_node("Maps").get_children():
		maps.append(map)
	for scene: PackedScene in world.ALDERBROOK_CAMPAIGN.mission_maps:
		var map: Map = scene.instantiate() as Map
		maps.append(map)
		scenes[scene.resource_path] = map
	var approach: Map = world.WESTERN_APPROACH.instantiate() as Map
	maps.append(approach)
	scenes[world.WESTERN_APPROACH.resource_path] = approach
	shared = (maps[0].get_node("TileMapLayers/TerrainTileMapLayer") as TileMapLayer).tile_set.duplicate(true) as TileSet
	while shared.get_source_count() > 0:
		shared.remove_source(shared.get_source_id(0))
	for map: Map in maps:
		var terrain: TileMapLayer = map.get_node("TileMapLayers/TerrainTileMapLayer") as TileMapLayer
		for index: int in range(terrain.tile_set.get_source_count()):
			var source: TileSetAtlasSource = terrain.tile_set.get_source(terrain.tile_set.get_source_id(index)) as TileSetAtlasSource
			if _is_road_source(source):
				_adopt(source)
	var pending: Dictionary[String, Dictionary] = {}
	for path: String in scenes:
		var updates: Dictionary[String, PackedStringArray] = {}
		var scene: Node = scenes[path]
		if path == WORLD:
			for map: Map in scene.get_node("Maps").get_children():
				updates["Maps/" + str(map.name) + "/TileMapLayers"] = _migrate(map)
		else:
			updates["TileMapLayers"] = _migrate(scene as Map)
		for parent: String in updates:
			if updates[parent].is_empty():
				get_tree().quit(1)
				return
		pending[path] = updates
	for path: String in pending:
		_patch_scene(path, pending[path])
	assert(ResourceSaver.save(shared, ROADS.TILE_SET_PATH) == OK)
	for path: String in terrain_updates:
		var update: Dictionary = terrain_updates[path]
		var tiles: TileSet = update["tiles"]
		for id: int in update["remove"]:
			tiles.remove_source(id)
		var uid: int = ResourceLoader.get_resource_uid(path)
		assert(ResourceSaver.save(tiles, path) == OK)
		if uid >= 0:
			assert(ResourceSaver.set_uid(path, uid) == OK)
	for path: String in scenes:
		scenes[path].free()
	print("Moved roads to eight shared RoadTileMapLayer instances; restored both missing village road pieces.")
	get_tree().quit()


func _is_road_source(source: TileSetAtlasSource) -> bool:
	if source == null or source.get_tiles_count() == 0:
		return false
	for index: int in range(source.get_tiles_count()):
		if not ROADS.is_road(source.get_tile_data(source.get_tile_id(index), 0)):
			return false
	return true


func _adopt(source: TileSetAtlasSource) -> int:
	var key: String = str([source.texture.resource_path, source.texture_region_size, source.margins, source.separation])
	if source_ids.has(key):
		var existing: TileSetAtlasSource = shared.get_source(source_ids[key]) as TileSetAtlasSource
		# The village atlas has more regions than the older campaign copy of this texture.
		if existing.get_tiles_count() < source.get_tiles_count():
			shared.remove_source(source_ids[key])
			shared.add_source(source.duplicate(true), source_ids[key])
		return source_ids[key]
	var id: int = shared.add_source(source.duplicate(true))
	source_ids[key] = id
	return id


func _migrate(map: Map) -> PackedStringArray:
	var terrain: HexagonTileMapLayer = map.get_node("TileMapLayers/TerrainTileMapLayer") as HexagonTileMapLayer
	var roads: HexagonTileMapLayer = HexagonTileMapLayer.new()
	roads.tile_set = shared
	var removed: Array[int] = []
	for index: int in range(terrain.tile_set.get_source_count()):
		var id: int = terrain.tile_set.get_source_id(index)
		var source: TileSetAtlasSource = terrain.tile_set.get_source(id) as TileSetAtlasSource
		if _is_road_source(source):
			removed.append(id)
			road_sources[source.resource_scene_unique_id] = true
	for cell: Vector2i in terrain.get_used_cells():
		if ROADS.is_road(terrain.get_cell_tile_data(cell)):
			var source: TileSetAtlasSource = terrain.tile_set.get_source(terrain.get_cell_source_id(cell)) as TileSetAtlasSource
			roads.set_cell(cell, _adopt(source), terrain.get_cell_atlas_coords(cell), terrain.get_cell_alternative_tile(cell))
			terrain.erase_cell(cell)
	if str(map.name) == "Alderbrook5":
		var layout: Dictionary = AlderbrookRoads.new().layout_for_routes(AlderbrookVillageLayout.ROUTES, map.grid_size)
		var id: int = ROADS.install_curve(shared, AlderbrookRoads.ASSET_DIRECTORY + "road_05_battle_for_alderbrook.svg", "Road - Alderbrook village streets", layout["cells"])
		for cell: Vector2i in layout["cells"]:
			if roads.get_cell_source_id(cell) < 0 and ((map.get_node("TileMapLayers/GroundTileMapLayer") as TileMapLayer).get_cell_source_id(cell) < 0 or (map.get_node("TileMapLayers/BuildingTileMapLayer") as TileMapLayer).get_cell_source_id(cell) >= 0):
				push_error("Cannot restore a missing road through a building or water at " + str(cell))
				roads.free()
				return PackedStringArray()
			roads.set_cell(cell, id, layout["cells"][cell])
	var road_bytes: String = Marshalls.raw_to_base64(roads.tile_map_data)
	roads.free()
	var external: String = terrain.tile_set.resource_path
	var prune_lines: PackedStringArray = PackedStringArray()
	if "::" in external:
		prune_lines.append(terrain.tile_set.resource_scene_unique_id)
		for id: int in removed:
			prune_lines.append(str(id))
	elif not external.is_empty():
		terrain_updates[external] = {"tiles": terrain.tile_set, "remove": removed}
	return PackedStringArray([Marshalls.raw_to_base64(terrain.tile_map_data), road_bytes]) + prune_lines


func _patch_scene(path: String, updates: Dictionary[String, PackedStringArray]) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	var blocks: PackedStringArray = text.split("\n\n")
	var result: PackedStringArray = PackedStringArray()
	var headings: RegEx = RegEx.new()
	assert(headings.compile('^\\[node name="([^"]+)"[^\\n]* parent="([^"]+)"') == OK)
	for block: String in blocks:
		if block.begins_with('[sub_resource type="TileSet"'):
			for parent: String in updates:
				var update: PackedStringArray = updates[parent]
				if update.size() <= 2 or block.get_slice('"', 3) != update[2]:
					continue
				for index: int in range(3, update.size()):
					var lines: PackedStringArray = PackedStringArray()
					for line: String in block.split("\n"):
						if not line.begins_with("sources/" + update[index] + " = "):
							lines.append(line)
					block = "\n".join(lines)
		var heading: RegExMatch = headings.search(block)
		if heading != null and updates.has(heading.get_string(2)):
			var parent: String = heading.get_string(2)
			if heading.get_string(1) == "TerrainTileMapLayer":
				var lines: PackedStringArray = block.split("\n")
				for index: int in range(lines.size()):
					if lines[index].begins_with("tile_map_data = "):
						lines[index] = 'tile_map_data = PackedByteArray("%s")' % updates[parent][0]
				result.append("\n".join(lines))
				var order_attribute: String = ""
				if path == WORLD:
					order_attribute = ' index="2"'
				result.append('[node name="RoadTileMapLayer" parent="%s"%s instance=ExtResource("SharedRoadLayer")]\ntile_map_data = PackedByteArray("%s")' % [parent, order_attribute, updates[parent][1]])
				continue
			if path == WORLD and heading.get_string(1) in ["WallTileMapLayer", "BuildingTileMapLayer"]:
				block = block.replace('index="3"', 'index="4"').replace('index="2"', 'index="3"')
		result.append(block)
	text = "\n\n".join(result)
	# Remove detached road atlas definitions; keep every unrelated scene resource intact.
	result = PackedStringArray()
	for block: String in text.split("\n\n"):
		if block.begins_with('[sub_resource type="TileSetAtlasSource"'):
			var id: String = block.get_slice('"', 3)
			if road_sources.has(id) and not text.contains('SubResource("' + id + '")'):
				continue
		result.append(block)
	text = "\n\n".join(result)
	text = text.insert(text.find("[ext_resource"), '[ext_resource type="PackedScene" path="' + ROADS.LAYER_SCENE + '" id="SharedRoadLayer"]\n')
	FileAccess.open(path, FileAccess.WRITE).store_string(text)
