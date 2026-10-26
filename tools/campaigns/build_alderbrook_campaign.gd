extends Node

const MAP_DIRECTORY: String = "res://scenes/campaigns/alderbrook/"
const RESOURCE_DIRECTORY: String = "res://resources/campaigns/"
const IMAGE_DIRECTORY: String = "res://docs/campaigns/road_to_alderbrook/maps/"
const OPEN_GROUND_IMAGES: Array[String] = [
	"res://assets/tiles/vegetation/open_ground_green_01.png",
	"res://assets/tiles/vegetation/open_ground_green_02.png",
	"res://assets/tiles/vegetation/open_ground_green_03.png",
]
const WOODS_IMAGES: Array[String] = [
	"res://assets/tiles/vegetation/woods_green_01.png",
	"res://assets/tiles/vegetation/woods_green_02.png",
	"res://assets/tiles/vegetation/woods_green_03.png",
]
const WHEAT_IMAGES: Array[String] = [
	"res://assets/tiles/fields/field_wheat_01.png",
	"res://assets/tiles/fields/field_wheat_02.png",
	"res://assets/tiles/fields/field_wheat_03.png",
]
const CROP_IMAGES: Array[String] = [
	"res://assets/tiles/fields/field_green_rows_01.png",
	"res://assets/tiles/fields/field_green_rows_02.png",
	"res://assets/tiles/fields/field_green_rows_03.png",
]
const ORCHARD_IMAGES: Array[String] = [
	"res://assets/tiles/orchard/orchard_green_01.png",
	"res://assets/tiles/orchard/orchard_green_02.png",
	"res://assets/tiles/orchard/orchard_green_03.png",
]
const FIELD_IMAGES: Dictionary[String, String] = {
	"field_nw_sw_alt.png": WHEAT_IMAGES[0],
	"field_sw_so.png": CROP_IMAGES[2],
	"field_n_s.png": CROP_IMAGES[0],
	"field.png": WHEAT_IMAGES[0],
	"field_nw_no.png": WHEAT_IMAGES[1],
	"field_nw_sw.png": CROP_IMAGES[0],
	"field_no_sw.png": CROP_IMAGES[1],
	"field_sw_s.png": WHEAT_IMAGES[2],
}
const FIELD_PLOTS: Array[Array] = [
	[Rect2i(4, 2, 2, 2), Rect2i(10, 2, 3, 2), Rect2i(4, 6, 2, 2), Rect2i(9, 6, 3, 2)],
	[Rect2i(3, 2, 2, 2), Rect2i(12, 2, 3, 3), Rect2i(3, 8, 2, 2), Rect2i(12, 8, 3, 2)],
	[Rect2i(4, 3, 3, 3), Rect2i(11, 3, 4, 3), Rect2i(3, 9, 3, 3), Rect2i(11, 9, 4, 3)],
	[Rect2i(5, 2, 4, 2), Rect2i(15, 2, 4, 2), Rect2i(5, 6, 4, 2), Rect2i(15, 6, 4, 2), Rect2i(5, 12, 4, 2), Rect2i(15, 12, 4, 2)],
	[Rect2i(4, 2, 4, 2), Rect2i(12, 2, 4, 2), Rect2i(4, 6, 4, 2), Rect2i(12, 6, 4, 2), Rect2i(4, 11, 4, 2), Rect2i(12, 11, 4, 2), Rect2i(4, 15, 4, 1), Rect2i(23, 13, 2, 3)],
]
const ORCHARD_PLOTS: Array[Array] = [
	[Rect2i(10, 3, 2, 2)],
	[Rect2i(5, 3, 6, 7)],
	[Rect2i(9, 10, 3, 2)],
	[Rect2i(17, 6, 3, 2)],
	[Rect2i(15, 5, 2, 2), Rect2i(21, 11, 3, 2)],
]
const MISSIONS: Array[Dictionary] = [
	{
		"id": "01_quiet_approach", "title": "1. Quiet Approach", "map": "Alderbrook Approach", "size": Vector2i(16, 10), "seconds": 600.0,
		"briefing": "Road to Alderbrook - mission 1 of 5.\n\nThe company and its heavy weapons have continued along the main road. Your rifle squad and platoon headquarters must secure a farm on the flank toward Alderbrook. No reinforcements or artillery are available. Use the woodland belt to approach carefully, locate the defenders before committing, and keep headquarters behind the rifle squad. You can withdraw to rally point B if the farm proves too costly.\n\n[b]Major Victory:[/b] occupy the farm at A for 15 seconds.\n\n[b]Minor Victory:[/b] hold the rally point at B when time expires. A minor or major victory opens the next mission.",
		"player": [[1, "hq", 2, 6], [1, "rifle", 2, 5]],
		"enemy": [[1, "hq", 14, 5], [1, "rifle", 12, 5]],
		"allied_markers": [[1, 12, 5], [2, 7, 6], [4, 2, 6]], "axis_markers": [[1, 12, 5], [4, 14, 5]],
	},
	{
		"id": "02_orchard_outpost", "title": "2. Orchard Outpost", "map": "Alderbrook Orchard", "size": Vector2i(18, 12), "seconds": 600.0,
		"briefing": "Road to Alderbrook - mission 2 of 5.\n\nYour full platoon now has a machine-gun team. Clear the orchard outpost before the company moves up. The central lane is quick but exposed; the orchard and northern woodland give covered alternatives. Set up the gun before sending rifle squads forward.\n\n[b]Major Victory:[/b] destroy two enemy units and hold the farmhouse at A for 30 seconds. Both requirements must be met.\n\n[b]Minor Victory:[/b] hold the orchard barn at B when time expires.",
		"player": [[1, "hq", 2, 6], [1, "rifle", 3, 5], [1, "rifle", 3, 6], [1, "rifle", 3, 7], [1, "mg", 2, 8]],
		"enemy": [[1, "hq", 15, 7], [1, "rifle", 13, 6], [1, "rifle", 14, 5], [1, "mg", 12, 4]],
		"allied_markers": [[1, 13, 6], [2, 9, 8], [4, 2, 6]], "axis_markers": [[1, 13, 6], [4, 15, 7]],
	},
	{
		"id": "03_the_roadblock", "title": "3. The Roadblock", "map": "Alderbrook Roadblock", "size": Vector2i(20, 14), "seconds": 540.0,
		"briefing": "Road to Alderbrook - mission 3 of 5.\n\nAn enemy column is trying to pass the roadblock and escape to the west. Your platoon has two machine-gun teams but no reinforcements. Cover the road and its woodland bypass, keep a rifle squad in reserve, and protect the western exits. The enemy starts beyond the wooded bend.\n\n[b]Major Victory:[/b] destroy two enemy units and allow no enemy exits before the deadline.\n\n[b]Minor Victory:[/b] hold A at the deadline while allowing no more than two exits. Three enemy exits give the enemy victory.",
		"player": [[1, "hq", 5, 9], [1, "rifle", 6, 6], [1, "rifle", 7, 6], [1, "rifle", 6, 8], [1, "mg", 7, 7], [1, "mg", 8, 8]],
		"enemy": [[1, "hq", 18, 5], [1, "rifle", 17, 5], [1, "rifle", 17, 6], [2, "hq", 18, 9], [2, "rifle", 17, 8], [2, "rifle", 17, 9], [0, "company_hq", 19, 7]],
		"allied_markers": [[1, 7, 7], [4, 5, 9]], "axis_markers": [[0, 0, 6], [0, 0, 7], [0, 0, 8], [0, 0, 9], [4, 18, 7]],
	},
	{
		"id": "04_two_crossings", "title": "4. Two Crossings", "map": "Alderbrook Crossings", "size": Vector2i(24, 16), "seconds": 720.0,
		"briefing": "Road to Alderbrook - mission 4 of 5.\n\nTwo reinforced platoons must open the river crossings and move a force into the village approaches. The river is impassable away from the two bridges. Assign a platoon to each crossing; leave a garrison on each eastern bank while the remaining squads pass through.\n\n[b]Major Victory:[/b] hold A and B for 20 seconds each and exit three units through the eastern Exit markers. All three requirements must be met together.\n\n[b]Minor Victory:[/b] exit two units by the deadline. Enemy infantry and fire support guard the eastern approaches.",
		"player": [[1, "hq", 2, 4], [1, "rifle", 3, 3], [1, "rifle", 3, 4], [1, "rifle", 3, 5], [1, "mg", 2, 6], [2, "hq", 2, 10], [2, "rifle", 3, 9], [2, "rifle", 3, 10], [2, "rifle", 3, 11], [2, "mg", 2, 12], [0, "company_hq", 1, 7]],
		"enemy": [[1, "hq", 17, 4], [1, "rifle", 14, 3], [1, "rifle", 14, 5], [1, "mg", 16, 4], [2, "hq", 17, 10], [2, "rifle", 14, 9], [2, "rifle", 14, 11], [2, "mg", 16, 10], [0, "company_hq", 20, 7]],
		"allied_markers": [[1, 13, 4], [2, 13, 10], [0, 22, 4], [0, 22, 10], [4, 2, 7]], "axis_markers": [[1, 13, 4], [4, 17, 7]],
	},
	{
		"id": "05_battle_for_alderbrook", "title": "5. Battle for Alderbrook", "map": "Alderbrook Village", "size": AlderbrookVillageLayout.SIZE, "seconds": 900.0,
		"briefing": AlderbrookVillageLayout.BRIEFING,
		"player": AlderbrookVillageLayout.PLAYER, "enemy": AlderbrookVillageLayout.ENEMY,
		"allied_markers": AlderbrookVillageLayout.ALLIED_MARKERS, "axis_markers": AlderbrookVillageLayout.AXIS_MARKERS,
	},
]

var _terrain_set: TileSet
var _road_set: TileSet
var _wall_set: TileSet
var _building_set: TileSet
var _water_set: TileSet
var _building_sources: Dictionary[String, int] = {}
var _woods_sources: Array[int] = []
var _wood_building_sources: Array[int] = []
var _orchard_sources: Array[int] = []
var _wheat_sources: Array[int] = []
var _crop_sources: Array[int] = []
var _grass_noise: FastNoiseLite = FastNoiseLite.new()
var _roads: AlderbrookRoads = AlderbrookRoads.new()
var _road_layouts: Array[Dictionary] = []
var _road_sources: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for index: int in range(MISSIONS.size()):
		_road_layouts.append(_roads.layout(index, MISSIONS[index]["size"]))
	if OS.get_cmdline_user_args().has("--los-only"):
		var bake_main: Node = load("res://scenes/main.tscn").instantiate()
		get_tree().root.add_child(bake_main)
		bake_main.process_mode = Node.PROCESS_MODE_DISABLED
		bake_main.world.fully_freed.disconnect(bake_main._on_fully_freed)
		var selected: int = 0
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--mission="):
				selected = argument.trim_prefix("--mission=").to_int()
		for index: int in range(MISSIONS.size()):
			if selected > 0 and selected != index + 1:
				continue
			var map: Map = bake_main.world.maps.get_node("Alderbrook" + str(index + 1)) as Map
			_export_layout(map, MISSIONS[index])
			await _bake_los(map)
		bake_main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--roads-only"):
		for index: int in range(MISSIONS.size()):
			_roads.write_assets(str(MISSIONS[index]["id"]), _road_layouts[index])
		for kind: String in ["bridge", "river"]:
			var image: Image = Image.new()
			assert(image.load_svg_from_string(FileAccess.get_file_as_string("res://assets/tiles/campaign/" + kind + ".svg")) == OK)
			assert(image.save_png(AlderbrookRoads.PREVIEW_DIRECTORY + kind + ".png") == OK)
		get_tree().quit()
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.name = "Main"
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var template: Node = main.world
	template.fully_freed.disconnect(main._on_fully_freed)
	if OS.get_cmdline_user_args().has("--buildings-only"):
		await _replace_building_art()
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--art-only"):
		for index: int in range(MISSIONS.size()):
			var map: Map = template.maps.get_node("Alderbrook" + str(index + 1)) as Map
			var art_id: String = str(MISSIONS[index]["id"])
			if index == 4:
				art_id += "_village"
			ConnectedTerrainBaker.bake(map.get_terrain_layer(), art_id + "_terrain")
			ConnectedTerrainBaker.bake(map.get_building_layer(), art_id + "_woods")
			if index == 4:
				assert(ResourceSaver.save(map.get_terrain_layer().tile_set, RESOURCE_DIRECTORY + "alderbrook_village_terrain.tres") == OK)
			_export_layout(map, MISSIONS[index])
		var first: Map = template.maps.get_node("Alderbrook1") as Map
		assert(ResourceSaver.save(first.get_terrain_layer().tile_set, RESOURCE_DIRECTORY + "alderbrook_terrain.tres") == OK)
		assert(ResourceSaver.save(first.get_building_layer().tile_set, BuildingVariations.SHARED_TILE_SET) == OK)
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--manifest-only"):
		for index: int in range(MISSIONS.size()):
			_export_layout(template.maps.get_node("Alderbrook" + str(index + 1)) as Map, MISSIONS[index])
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit()
		return
	var base: Map = template.get_node("Maps/DefaultMap") as Map
	_terrain_set = base.get_terrain_layer().tile_set.duplicate(true) as TileSet
	_road_set = load(RoadTiles.TILE_SET_PATH) as TileSet
	_update_field_art()
	_wall_set = load(ConnectedWalls.TILE_SET_PATH) as TileSet
	_building_set = load(BuildingVariations.SHARED_TILE_SET) as TileSet
	_update_woods_art(_terrain_set)
	_update_woods_art(_building_set)
	var woods: TileSetAtlasSource = TileSetAtlasSource.new()
	woods.texture = load(WOODS_IMAGES[0]) as Texture2D
	woods.texture_region_size = Vector2i(128, 128)
	woods.create_tile(Vector2i.ZERO)
	var woods_source: int = _terrain_set.add_source(woods)
	var woods_data: TileData = woods.get_tile_data(Vector2i.ZERO, 0)
	woods_data.set_custom_data("woods", true)
	woods_data.set_custom_data("hindrance", true)
	woods_data.set_custom_data("blocking", true)
	woods_data.set_custom_data("name", "Woods")
	_woods_sources = _visual_sources(_terrain_set, woods_source, WOODS_IMAGES, "Woods")
	_wood_building_sources = _visual_sources(_building_set, _source_for(_building_set, "Woods"), WOODS_IMAGES, "Woods")
	_orchard_sources = _visual_sources(_terrain_set, _source_for(_terrain_set, "Orchard"), ORCHARD_IMAGES, "Orchard")
	_wheat_sources = _sources_for_images(_terrain_set, WHEAT_IMAGES)
	_crop_sources = _sources_for_images(_terrain_set, CROP_IMAGES)
	for index: int in range(MISSIONS.size()):
		_road_sources.append(RoadTiles.install_curve(_road_set, AlderbrookRoads.ASSET_DIRECTORY + "road_" + str(MISSIONS[index]["id"]) + ".svg", "Road - " + str(MISSIONS[index]["title"]), _road_layouts[index]["cells"]))
	ResourceSaver.save(_terrain_set, RESOURCE_DIRECTORY + "alderbrook_terrain.tres")
	ResourceSaver.save(_road_set, RoadTiles.TILE_SET_PATH)
	ResourceSaver.save(_wall_set, ConnectedWalls.TILE_SET_PATH)
	ResourceSaver.save(_building_set, BuildingVariations.SHARED_TILE_SET)
	_terrain_set.take_over_path(RESOURCE_DIRECTORY + "alderbrook_terrain.tres")
	_wall_set.take_over_path(ConnectedWalls.TILE_SET_PATH)
	_building_set.take_over_path(BuildingVariations.SHARED_TILE_SET)
	for label: String in ["Stone Building", "Wood Building", "Woods"]:
		_building_sources[label] = _source_for(_building_set, label)
	_water_set = TileSet.new()
	_water_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	_water_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	_water_set.tile_size = Vector2i(128, 128)
	for kind: String in ["river", "bridge"]:
		var source: TileSetAtlasSource = TileSetAtlasSource.new()
		source.texture = load("res://assets/tiles/campaign/" + kind + ".svg") as Texture2D
		source.texture_region_size = Vector2i(128, 128)
		source.create_tile(Vector2i.ZERO)
		_water_set.add_source(source)
		if kind == "bridge":
			source.create_alternative_tile(Vector2i.ZERO, 1)
			source.get_tile_data(Vector2i.ZERO, 1).flip_v = true
	ResourceSaver.save(_water_set, RESOURCE_DIRECTORY + "alderbrook_water.tres")
	_water_set.take_over_path(RESOURCE_DIRECTORY + "alderbrook_water.tres")
	var maps: Array[PackedScene] = [load(MAP_DIRECTORY + "00_opening_the_road.tscn") as PackedScene]
	for index: int in range(MISSIONS.size()):
		var map: Map = _build_map(MISSIONS[index], index)
		if map == null:
			get_tree().quit(1)
			return
		add_child(map)
		await get_tree().process_frame
		if index == 4:
			var village: Node = load("res://tools/campaigns/build_alderbrook_village.gd").new()
			village.village_layout = _road_layouts[index]
			village._create_village(map)
			if not village._validate_village(map):
				village.free()
				get_tree().quit(1)
				return
			village.free()
		var art_id: String = str(MISSIONS[index]["id"])
		if index == 4:
			art_id += "_village"
		ConnectedTerrainBaker.bake(map.get_terrain_layer(), art_id + "_terrain")
		ConnectedTerrainBaker.bake(map.get_building_layer(), art_id + "_woods")
		if index == 4:
			var village_path: String = RESOURCE_DIRECTORY + "alderbrook_village_terrain.tres"
			assert(ResourceSaver.save(map.get_terrain_layer().tile_set, village_path) == OK)
			map.get_terrain_layer().tile_set.take_over_path(village_path)
			var village: Node = load("res://tools/campaigns/build_alderbrook_village.gd").new()
			village.share_buildings(map.get_building_layer(), _building_set)
			village.free()
		var packed: PackedScene = PackedScene.new()
		var error: Error = packed.pack(map)
		assert(error == OK)
		var path: String = MAP_DIRECTORY + str(MISSIONS[index]["id"]) + ".tscn"
		assert(ResourceSaver.save(packed, path) == OK)
		maps.append(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene)
		_export_layout(map, MISSIONS[index])
		if not OS.get_cmdline_user_args().has("--skip-los"):
			await _bake_los(map)
		map.queue_free()
		await get_tree().process_frame
	var campaign: CampaignDefinition = CampaignDefinition.new()
	assert(ResourceSaver.save(_terrain_set, RESOURCE_DIRECTORY + "alderbrook_terrain.tres") == OK)
	assert(ResourceSaver.save(_building_set, BuildingVariations.SHARED_TILE_SET) == OK)
	campaign.campaign_id = "road_to_alderbrook"
	campaign.title = "Road to Alderbrook"
	campaign.mission_maps = maps
	assert(ResourceSaver.save(campaign, RESOURCE_DIRECTORY + "road_to_alderbrook.tres") == OK)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Built five Alderbrook missions with the existing prologue.")
	get_tree().quit()


func _update_woods_art(tiles: TileSet) -> void:
	for index: int in range(tiles.get_source_count()):
		var source: TileSetAtlasSource = tiles.get_source(tiles.get_source_id(index)) as TileSetAtlasSource
		if source != null and source.texture != null and source.texture.resource_path.get_file() == "woods.png":
			source.texture = load(WOODS_IMAGES[0]) as Texture2D
			source.resource_name = "Woods - Spring Summer"


func _update_field_art() -> void:
	for index: int in range(_terrain_set.get_source_count()):
		var source: TileSetAtlasSource = _terrain_set.get_source(_terrain_set.get_source_id(index)) as TileSetAtlasSource
		if source == null or not source.has_tile(Vector2i.ZERO):
			continue
		if str(source.get_tile_data(Vector2i.ZERO, 0).get_custom_data("name")) != "Field":
			continue
		var path: String = FIELD_IMAGES.get(source.texture.resource_path.get_file(), "")
		if path.is_empty():
			continue
		source.texture = load(path) as Texture2D
		source.resource_name = "Field - " + path.get_file().get_basename().trim_prefix("field_").capitalize()


func _visual_sources(tiles: TileSet, prototype_id: int, images: Array[String], label: String) -> Array[int]:
	var prototype: TileSetAtlasSource = tiles.get_source(prototype_id) as TileSetAtlasSource
	prototype.texture = load(images[0]) as Texture2D
	prototype.resource_name = label + " 1"
	var sources: Array[int] = [prototype_id]
	for index: int in range(1, images.size()):
		var source: TileSetAtlasSource = prototype.duplicate(true) as TileSetAtlasSource
		source.texture = load(images[index]) as Texture2D
		source.resource_name = label + " " + str(index + 1)
		sources.append(tiles.add_source(source))
	return sources


func _sources_for_images(tiles: TileSet, images: Array[String]) -> Array[int]:
	var sources: Array[int] = []
	for path: String in images:
		for index: int in range(tiles.get_source_count()):
			var id: int = tiles.get_source_id(index)
			var source: TileSetAtlasSource = tiles.get_source(id) as TileSetAtlasSource
			if source != null and source.texture.resource_path == path:
				sources.append(id)
				break
	assert(sources.size() == images.size(), "Every visual variant needs a matching atlas source")
	return sources


func _source_for(tiles: TileSet, label: String) -> int:
	for index: int in range(tiles.get_source_count()):
		var id: int = tiles.get_source_id(index)
		var source: TileSetAtlasSource = tiles.get_source(id) as TileSetAtlasSource
		if source == null or not source.has_tile(Vector2i.ZERO):
			continue
		var data: TileData = source.get_tile_data(Vector2i.ZERO, 0)
		if str(data.get_custom_data("name")) == label:
			return id
	push_error("Missing campaign tile: " + label)
	return -1


func _layer(label: String, tiles: TileSet, script_path: String) -> HexagonTileMapLayer:
	var layer: HexagonTileMapLayer = HexagonTileMapLayer.new()
	layer.name = label
	layer.tile_set = tiles
	if not script_path.is_empty():
		layer.set_script(load(script_path))
	return layer


func _build_map(spec: Dictionary, index: int) -> Map:
	var map: Map = load("res://scenes/world/maps/map.tscn").instantiate() as Map
	map.name = "Alderbrook" + str(index + 1)
	map.map_name = spec["map"]
	map.campaign_name = "Road to Alderbrook"
	map.grid_size = spec["size"]
	map.los_resource_path = "res://resources/los/alderbrook_" + str(spec["id"]) + ".res"
	var layers: Node2D = map.get_node("TileMapLayers") as Node2D
	var ground: HexagonTileMapLayer = load("res://scenes/world/maps/layers/ground_tile_map_layer.tscn").instantiate() as HexagonTileMapLayer
	ground.tile_set = ground.tile_set.duplicate(true) as TileSet
	var ground_sources: Array[int] = _visual_sources(ground.tile_set, 1, OPEN_GROUND_IMAGES, "Open Ground")
	_grass_noise.seed = 9413 + index * 239
	_grass_noise.frequency = 0.12
	ground.clear()
	var terrain: HexagonTileMapLayer = _layer("TerrainTileMapLayer", _terrain_set, "res://scenes/world/maps/layers/terrain_tile_map_layer.gd")
	var roads: HexagonTileMapLayer = load(RoadTiles.LAYER_SCENE).instantiate() as HexagonTileMapLayer
	roads.tile_set = _road_set
	var walls: HexagonTileMapLayer = load(ConnectedWalls.LAYER_SCENE).instantiate() as HexagonTileMapLayer
	walls.tile_set = _wall_set
	var buildings: HexagonTileMapLayer = load(BuildingVariations.LAYER_SCENE).instantiate() as HexagonTileMapLayer
	buildings.tile_set = _building_set
	var water: HexagonTileMapLayer = _layer("WaterTileMapLayer", _water_set, "")
	layers.add_child(ground)
	layers.add_child(water)
	layers.add_child(terrain)
	layers.add_child(roads)
	layers.add_child(walls)
	layers.add_child(buildings)
	for layer: Node in layers.get_children():
		layer.owner = map
	var middle: int = map.grid_size.y / 2
	for x: int in range(map.grid_size.x):
		for y: int in range(map.grid_size.y):
			var cell: Vector2i = Vector2i(x, y)
			ground.set_cell(cell, ground_sources[_ground_variation(cell, map.grid_size, index)], Vector2i.ZERO)
			if y <= 1 or y >= map.grid_size.y - 2:
				if x % 4 != 0:
					_woods(terrain, buildings, cell, index)
	var belt: int = 6 + index
	for y: int in range(2, map.grid_size.y - 2):
		if absi(y - middle) > 1:
			_woods(terrain, buildings, Vector2i(belt, y), index)
	if index == 0:
		_house(buildings, terrain, Vector2i(12, 5), false)
	elif index == 1:
		_house(buildings, terrain, Vector2i(13, 6), true)
		_house(buildings, terrain, Vector2i(9, 8), false)
	elif index == 2:
		_house(buildings, terrain, Vector2i(7, 7), true)
		_house(buildings, terrain, Vector2i(8, 9), false)
	elif index == 3:
		var river_x: int = 11
		var crossings: Array[int] = [4, 10]
		var river_width: int = 2
		for x: int in range(river_x, river_x + river_width):
			for y: int in range(map.grid_size.y):
				var cell: Vector2i = Vector2i(x, y)
				terrain.erase_cell(cell)
				buildings.erase_cell(cell)
				water.set_cell(cell, 0, Vector2i.ZERO)
				if crossings.has(y):
					var alternative: int = 0
					if x % 2 == 0:
						alternative = 1
					water.set_cell(cell, 1, Vector2i.ZERO, alternative)
				else:
					ground.erase_cell(cell)
		for cell: Vector2i in [Vector2i(14, 5), Vector2i(14, 11), Vector2i(18, 8)]:
			_house(buildings, terrain, cell, true)
	if not _place_roads(ground, terrain, roads, buildings, water, index, ground_sources[0]):
		map.free()
		return null
	_place_orchards(ground, terrain, buildings, index)
	_place_fields(ground, terrain, buildings, index)
	var scenario: Scenario = Scenario.new()
	scenario.name = "Mission"
	map.get_node("Scenarios").add_child(scenario)
	scenario.owner = map
	var units: Node2D = Node2D.new()
	units.name = "Units"
	scenario.add_child(units)
	units.owner = map
	var objectives: Node2D = Node2D.new()
	objectives.name = "Objectives"
	scenario.add_child(objectives)
	objectives.owner = map
	var marker_template: Scenario = load("res://scenes/scenarios/scenario.tscn").instantiate() as Scenario
	for label: String in ["AxisObjectivesTileMapLayer", "AlliedObjectivesTileMapLayer"]:
		var original: HexagonTileMapLayer = marker_template.get_node("Objectives/" + label) as HexagonTileMapLayer
		var marker_layer: HexagonTileMapLayer = _layer(label, original.tile_set, "")
		objectives.add_child(marker_layer)
		marker_layer.owner = map
	marker_template.free()
	scenario.scenario_name = spec["title"]
	scenario.scenario_id = "alderbrook_" + str(spec["id"])
	scenario.campaign_id = "road_to_alderbrook"
	scenario.campaign_mission = index + 1
	scenario.scenario_description = spec["briefing"]
	scenario.duration_s = spec["seconds"]
	scenario.use_authored_duration = true
	scenario.end_when_objectives_secured_and_enemy_gone = index == 4
	scenario.released = true
	scenario.player_team = Globals.Team.ALLIES
	scenario.axis_ai_status = Scenario.AIStatus.ON
	scenario.axis_ai_mode = Scenario.AIMode.DEFEND
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	if index == 2:
		scenario.axis_ai_mode = Scenario.AIMode.ATTACK
	scenario.victory_conditions = _conditions(index, scenario)
	_add_units(scenario, map, ground, spec["player"], Globals.Team.ALLIES)
	_add_units(scenario, map, ground, spec["enemy"], Globals.Team.AXIS)
	_set_markers(scenario.get_node("Objectives/AlliedObjectivesTileMapLayer") as HexagonTileMapLayer, spec["allied_markers"], true)
	_set_markers(scenario.get_node("Objectives/AxisObjectivesTileMapLayer") as HexagonTileMapLayer, spec["axis_markers"], false)
	BuildingVariations.apply(buildings, scenario.scenario_id)
	return map


func _replace_building_art() -> void:
	var tiles: TileSet = load(BuildingVariations.SHARED_TILE_SET) as TileSet
	BuildingVariations.install(tiles)
	assert(ResourceSaver.save(tiles, BuildingVariations.SHARED_TILE_SET) == OK)
	tiles.take_over_path(BuildingVariations.SHARED_TILE_SET)
	for index: int in range(MISSIONS.size()):
		var path: String = MAP_DIRECTORY + str(MISSIONS[index]["id"]) + ".tscn"
		var scene: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var map: Map = scene.instantiate() as Map
		var original_cells: Dictionary[StringName, PackedByteArray] = {}
		for layer: HexagonTileMapLayer in map.get_node("TileMapLayers").get_children():
			if layer.name != &"BuildingTileMapLayer":
				original_cells[layer.name] = layer.tile_map_data
		# Save source artwork without baking runtime palette materials into the scene.
		var campaign_name: String = map.campaign_name
		map.campaign_name = ""
		add_child(map)
		map.campaign_name = campaign_name
		map.get_building_layer().tile_set = tiles
		BuildingVariations.apply(map.get_building_layer(), map.get_scenario(0).scenario_id)
		for layer: HexagonTileMapLayer in map.get_tilemap_layers():
			if original_cells.has(layer.name):
				layer.tile_map_data = original_cells[layer.name]
		var packed: PackedScene = PackedScene.new()
		assert(packed.pack(map) == OK)
		assert(ResourceSaver.save(packed, path) == OK)
		_export_layout(map, MISSIONS[index])
		if not OS.get_cmdline_user_args().has("--skip-los"):
			await _bake_los(map)
		map.queue_free()
		await get_tree().process_frame
	print("Replaced building artwork in all five Alderbrook campaign maps.")


func _ground_variation(cell: Vector2i, size: Vector2i, index: int) -> int:
	if index >= 3:
		var river: int = 11
		if index == 4:
			river = 10
		if absi(cell.x - river) <= 2:
			return 1
	if cell.y <= 2 or cell.y >= size.y - 3 or absi(cell.x - (6 + index)) <= 1:
		return 2
	var meadow: float = _grass_noise.get_noise_2d(float(cell.x), float(cell.y))
	if meadow < -0.18:
		return 0
	if meadow > 0.18:
		return 2
	return 1


func _woods(terrain: HexagonTileMapLayer, buildings: HexagonTileMapLayer, cell: Vector2i, index: int) -> void:
	var variant: int = posmod(floori(float(cell.x) / 4.0) + floori(float(cell.y) / 3.0) + index, 3)
	terrain.set_cell(cell, _woods_sources[variant], Vector2i.ZERO)
	buildings.set_cell(cell, _wood_building_sources[variant], Vector2i.ZERO)


func _can_plant(ground: HexagonTileMapLayer, terrain: HexagonTileMapLayer, buildings: HexagonTileMapLayer, cell: Vector2i) -> bool:
	if ground.get_cell_source_id(cell) < 0 or buildings.get_cell_source_id(cell) >= 0:
		return false
	var roads: TileMapLayer = ground.get_parent().get_node_or_null("RoadTileMapLayer") as TileMapLayer
	if roads != null and roads.get_cell_source_id(cell) >= 0:
		return false
	var data: TileData = terrain.get_cell_tile_data(cell)
	return data == null or str(data.get_custom_data("name")) == "Field"


func _place_orchards(ground: HexagonTileMapLayer, terrain: HexagonTileMapLayer, buildings: HexagonTileMapLayer, index: int) -> void:
	for plot: Rect2i in ORCHARD_PLOTS[index]:
		for x: int in range(plot.position.x, plot.end.x):
			for y: int in range(plot.position.y, plot.end.y):
				var cell: Vector2i = Vector2i(x, y)
				if _can_plant(ground, terrain, buildings, cell):
					var variant: int = posmod(floori(float(x) / 3.0) + floori(float(y) / 3.0) + index, 3)
					terrain.set_cell(cell, _orchard_sources[variant], Vector2i.ZERO)


func _place_fields(ground: HexagonTileMapLayer, terrain: HexagonTileMapLayer, buildings: HexagonTileMapLayer, index: int) -> void:
	var plot_index: int = 0
	for plot: Rect2i in FIELD_PLOTS[index]:
		var sources: Array[int] = _wheat_sources
		if plot_index % 2 == 1:
			sources = _crop_sources
		var variant: int = posmod(floori(float(plot_index) / 2.0) + index, 3)
		for x: int in range(plot.position.x, plot.end.x):
			for y: int in range(plot.position.y, plot.end.y):
				var cell: Vector2i = Vector2i(x, y)
				if _can_plant(ground, terrain, buildings, cell):
					terrain.set_cell(cell, sources[variant], Vector2i.ZERO)
		plot_index += 1


func _place_roads(ground: HexagonTileMapLayer, terrain: HexagonTileMapLayer, roads: HexagonTileMapLayer, buildings: HexagonTileMapLayer, water: HexagonTileMapLayer, index: int, grass_source: int) -> bool:
	# Validate the complete route before clearing or painting any terrain.
	for cell: Vector2i in _road_layouts[index]["cells"]:
		if water.get_cell_source_id(cell) == 0:
			push_error("Road crosses unbridged water in mission %d at %s" % [index + 1, cell])
			return false
		var building: TileData = buildings.get_cell_tile_data(cell)
		if building != null and str(building.get_custom_data("name")) != "Woods":
			push_error("Road intersects a building in mission %d at %s" % [index + 1, cell])
			return false
	for cell: Vector2i in _road_layouts[index]["cells"]:
		if water.get_cell_source_id(cell) >= 0:
			continue
		buildings.erase_cell(cell)
		ground.set_cell(cell, grass_source, Vector2i.ZERO)
		terrain.erase_cell(cell)
		roads.set_cell(cell, _road_sources[index], _road_layouts[index]["cells"][cell])
	return true


func _house(buildings: HexagonTileMapLayer, terrain: HexagonTileMapLayer, cell: Vector2i, stone: bool) -> void:
	var kind: String = "Wood Building"
	if stone:
		kind = "Stone Building"
	buildings.set_cell(cell, _building_sources[kind], Vector2i.ZERO)
	terrain.erase_cell(cell)


func _add_units(scenario: Scenario, map: Map, ground: HexagonTileMapLayer, roster: Array, team: Globals.Team) -> void:
	var numbers: Dictionary[int, int] = {}
	var faction: String = "germany"
	if team == Globals.Team.ALLIES:
		faction = "united_states"
	for entry: Array in roster:
		var unit: Unit = load("res://scenes/game/units/unit.tscn").instantiate() as Unit
		unit.company = Unit.Company.A
		unit.platoon = int(entry[0])
		unit.team = team
		var kind: String = str(entry[1])
		var loadout: String = "rifle_squad"
		unit.squad_type = Globals.SquadType.Rifle
		if kind == "hq":
			loadout = "platoon_hq"
			unit.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
		elif kind == "company_hq":
			loadout = "company_hq"
			unit.squad_type = Globals.SquadType.COMPANY_HEADQUARTERS
		elif kind == "mg":
			loadout = "lmg_squad"
			unit.squad_type = Globals.SquadType.MG
		elif kind == "light_mortar" or kind == "medium_mortar":
			loadout = kind + "_squad"
			unit.squad_type = Globals.SquadType.MORTAR
		unit.squad = 0
		if kind != "hq" and kind != "company_hq":
			numbers[unit.platoon] = numbers.get(unit.platoon, 0) + 1
			unit.squad = numbers[unit.platoon]
		unit.squad_loadout = load("res://resources/squads/" + faction + "/" + loadout + ".tres") as SquadLoadoutSpec
		unit.loadouts = unit.squad_loadout.soldiers.duplicate()
		unit.formation_id = unit.platoon
		unit.position = ground.map_to_local(Vector2i(int(entry[2]), int(entry[3])))
		unit.name = "%s_P%d_S%d_%s" % [faction, unit.platoon, unit.squad, kind]
		scenario.get_node("Units").add_child(unit)
		unit.owner = map


func _set_markers(layer: HexagonTileMapLayer, markers: Array, allies: bool) -> void:
	layer.clear()
	var sources: Array[int] = [1, 3, 4, 5, 9]
	if allies:
		sources = [0, 6, 7, 8, 2]
	for marker: Array in markers:
		layer.set_cell(Vector2i(int(marker[1]), int(marker[2])), sources[int(marker[0])], Vector2i.ZERO)


func _occupy(team: Globals.Team, objective: OccupyObjectiveCondition.ObjectiveId, seconds: float, major: bool, deadline: bool) -> OccupyObjectiveCondition:
	var condition: OccupyObjectiveCondition = OccupyObjectiveCondition.new()
	condition.team = team
	condition.objective_id = objective
	condition.required_time_s = seconds
	condition.test_at_scenario_end = deadline
	if not major:
		condition.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	return condition


func _destroy(team: Globals.Team, count: int, major: bool, deadline: bool) -> DestroyUnitsCondition:
	var condition: DestroyUnitsCondition = DestroyUnitsCondition.new()
	condition.team = team
	condition.required_unit_count = count
	condition.test_at_scenario_end = deadline
	if not major:
		condition.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	return condition


func _exit(team: Globals.Team, count: int, major: bool, deadline: bool) -> ExitUnitsCondition:
	var condition: ExitUnitsCondition = ExitUnitsCondition.new()
	condition.team = team
	condition.required_unit_count = count
	condition.test_at_scenario_end = deadline
	if not major:
		condition.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	return condition


func _prevent(team: Globals.Team, count: int, major: bool) -> PreventEnemyExitCondition:
	var condition: PreventEnemyExitCondition = PreventEnemyExitCondition.new()
	condition.team = team
	condition.max_allowed_enemy_exits = count
	if not major:
		condition.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	return condition


func _conditions(index: int, scenario: Scenario) -> Array[VictoryCondition]:
	var player: Globals.Team = Globals.Team.ALLIES
	var enemy: Globals.Team = Globals.Team.AXIS
	var a: OccupyObjectiveCondition.ObjectiveId = OccupyObjectiveCondition.ObjectiveId.A
	var b: OccupyObjectiveCondition.ObjectiveId = OccupyObjectiveCondition.ObjectiveId.B
	var c: OccupyObjectiveCondition.ObjectiveId = OccupyObjectiveCondition.ObjectiveId.C
	match index:
		0:
			return [_occupy(player, a, 15.0, true, false), _occupy(player, b, 15.0, false, true), _occupy(enemy, a, 15.0, true, true), _destroy(enemy, 1, true, true)]
		1:
			return [_occupy(player, a, 30.0, true, false), _destroy(player, 2, true, false), _occupy(player, b, 30.0, false, true), _occupy(enemy, a, 30.0, true, true), _destroy(enemy, 3, true, true)]
		2:
			var escape_exit: ExitUnitsCondition = _exit(enemy, 3, true, false)
			var escape: EscapeMissionPolicy = EscapeMissionPolicy.new()
			escape.exit_condition = escape_exit
			scenario.ai_escape_policies = [escape]
			return [_prevent(player, 0, true), _destroy(player, 2, true, true), _prevent(player, 2, false), _occupy(player, a, 30.0, false, true), escape_exit]
		3:
			return [_occupy(player, a, 20.0, true, false), _occupy(player, b, 20.0, true, false), _exit(player, 3, true, false), _exit(player, 2, false, true), _occupy(enemy, a, 30.0, true, true), _prevent(enemy, 1, true)]
		4:
			var hold: OccupyObjectiveCondition = _occupy(enemy, a, 45.0, true, true)
			var fallback: ExitUnitsCondition = _exit(enemy, 2, false, true)
			var policy: HoldToExitFallbackPolicy = HoldToExitFallbackPolicy.new()
			policy.hold_condition = hold
			policy.exit_condition = fallback
			policy.confirmation_seconds = 6.0
			policy.withdrawal_margin_seconds = 20.0
			policy.minimum_combat_squads = 4
			scenario.ai_fallback_policies = [policy]
			return [_occupy(player, a, 45.0, true, true), _occupy(player, b, 45.0, true, true), _occupy(player, c, 45.0, true, true), _destroy(player, 6, true, true), _prevent(player, 1, true), _occupy(player, b, 45.0, false, true), _destroy(player, 3, false, true), hold, _occupy(enemy, b, 45.0, true, true), _occupy(enemy, c, 45.0, true, true), _destroy(enemy, 6, true, true), fallback]
	return []


func _export_layout(map: Map, spec: Dictionary) -> void:
	var layers: Array[Dictionary] = []
	for layer: HexagonTileMapLayer in map.get_tilemap_layers():
		var cells: Array[Dictionary] = []
		for cell: Vector2i in layer.get_used_cells():
			var source: TileSetAtlasSource = layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
			var position: Vector2 = layer.map_to_local(cell)
			var data: TileData = layer.get_cell_tile_data(cell)
			var region: Rect2i = source.get_tile_texture_region(layer.get_cell_atlas_coords(cell))
			var cell_data: Dictionary = {"hex": [cell.x, cell.y], "position": [position.x, position.y], "texture": source.texture.resource_path, "flip_h": data.flip_h, "flip_v": data.flip_v}
			if data.texture_origin != Vector2i.ZERO:
				cell_data["texture_origin"] = [data.texture_origin.x, data.texture_origin.y]
			if data.modulate != Color.WHITE:
				cell_data["modulate"] = [data.modulate.r, data.modulate.g, data.modulate.b, data.modulate.a]
			if data.has_custom_data("art_family"):
				cell_data["art_family"] = str(data.get_custom_data("art_family"))
			if region.position != Vector2i.ZERO or region.size != Vector2i(source.texture.get_size()):
				cell_data["texture_region"] = [region.position.x, region.position.y, region.size.x, region.size.y]
			cells.append(cell_data)
		layers.append({"name": str(layer.name), "cells": cells})
	var centerlines: Array[Array] = AlderbrookRoads.centerlines(_road_layouts[map.get_scenario(0).campaign_mission - 1])
	var data: Dictionary = {"title": spec["title"], "id": spec["id"], "size": [map.grid_size.x, map.grid_size.y], "seconds": spec["seconds"], "player": spec["player"], "enemy": spec["enemy"], "allied_markers": spec["allied_markers"], "axis_markers": spec["axis_markers"], "road_centerlines": centerlines, "layers": layers}
	var file: FileAccess = FileAccess.open(IMAGE_DIRECTORY + str(spec["id"]) + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))


func _bake_los(map: Map) -> void:
	LOSHelper.ground_layer = map.get_ground_layer()
	LOSHelper.terrain_layer = map.get_terrain_layer()
	LOSHelper.building_layer = map.get_building_layer()
	LOSHelper.wall_layer = map.get_wall_layer()
	LOSHelper.road_layer = map.get_road_layer()
	var building_signature: String = LOSHelper.building_layout_signature()
	var wall_signature: String = LOSHelper.wall_layout_signature()
	LOSHelper.grid_size = map.grid_size
	LOSHelper.begin_los_bake()
	var layout_signature: String = LOSHelper.bake_layout_signature()
	var lookup: Dictionary = {}
	for ox: int in range(map.grid_size.x):
		for oy: int in range(map.grid_size.y):
			var origin: Vector2i = Vector2i(ox, oy)
			lookup[origin] = LOSHelper.bake_los_origin(origin)
		if ox % 4 == 0:
			print(map.map_name, ": baked column ", ox + 1, "/", map.grid_size.x)
		await get_tree().process_frame
	LOSHelper.end_los_bake()
	var resource: LosLookupData = LosLookupData.new()
	resource.los_lookup = lookup
	resource.building_layout_signature = building_signature
	resource.wall_layout_signature = wall_signature
	resource.bake_layout_signature = layout_signature
	assert(ResourceSaver.save(resource, map.los_resource_path, ResourceSaver.FLAG_COMPRESS) == OK)
