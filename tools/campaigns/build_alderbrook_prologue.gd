extends "res://tools/campaigns/build_alderbrook_campaign.gd"

const PROLOGUE: Dictionary = {
	"id": "00_opening_the_road", "title": "Prologue. Opening the Road", "map": "Alderbrook Forward Road", "size": Vector2i(20, 12), "seconds": 600.0,
	"briefing": "Road to Alderbrook - prologue.\n\nThe company has concentrated its fire support against a thin enemy roadblock. Open the road at A and secure the farm at B. Three rifle squads, two machine-gun teams, a light mortar, platoon headquarters and company headquarters are available, with a four-gun 105 mm battery off map.\n\nEstablish machine-gun cover before advancing the rifles. Use the Fire Support tray to order mortar or artillery fire against spotted positions; keep your own troops clear of the target area. The enemy is dispersed between the road and farm, so one bombardment will not clear every position.\n\n[b]Major Victory:[/b] hold A and B for 15 seconds each.\n\n[b]Minor Victory:[/b] hold A for 15 seconds at the deadline. Either victory opens Quiet Approach.\n\n[b]Next assignment:[/b] the company and heavy weapons will continue along the main road. A small rifle patrol with platoon HQ will check the flank toward Alderbrook without fire support.",
	"player": [[0, "company_hq", 1, 6], [1, "hq", 2, 6], [1, "rifle", 3, 4], [1, "rifle", 3, 6], [1, "rifle", 3, 8], [1, "mg", 2, 4], [1, "mg", 2, 8], [2, "light_mortar", 1, 8]],
	"enemy": [[1, "hq", 17, 6], [1, "rifle", 13, 6], [1, "mg", 12, 5], [1, "rifle", 15, 8]],
	"allied_markers": [[1, 13, 6], [2, 15, 8], [4, 2, 6]], "axis_markers": [[1, 13, 6], [2, 15, 8], [4, 17, 6]],
}
const ROUTES: Array[Array] = [
	[Vector3(-1, 6.3, 0), Vector3(4, 6.2, -0.1), Vector3(9, 6.1, 0), Vector3(14, 6.7, 0.1), Vector3(20, 6.8, 0)],
]


func _run() -> void:
	_road_layouts.append(_roads.layout_for_routes(ROUTES, PROLOGUE["size"]))
	if OS.get_cmdline_user_args().has("--roads-only"):
		_roads.write_assets(PROLOGUE["id"], _road_layouts[0])
		get_tree().quit()
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.world.fully_freed.disconnect(main._on_fully_freed)
	if OS.get_cmdline_user_args().has("--los-only"):
		await get_tree().process_frame
		await get_tree().process_frame
		LOSHelper.load_prebaked_los(main.world.maps.get_node("AlderbrookPrologue") as Map)
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit()
		return
	var source: Map = main.world.maps.get_node("Alderbrook1") as Map
	_terrain_set = source.get_terrain_layer().tile_set.duplicate(true) as TileSet
	_building_set = source.get_building_layer().tile_set.duplicate(true) as TileSet
	_wall_set = source.get_wall_layer().tile_set
	_water_set = (source.get_node("TileMapLayers/WaterTileMapLayer") as HexagonTileMapLayer).tile_set
	_road_set = source.get_road_layer().tile_set.duplicate(true) as TileSet
	_woods_sources = _sources_for_images(_terrain_set, WOODS_IMAGES)
	_wood_building_sources = _sources_for_images(_building_set, WOODS_IMAGES)
	_orchard_sources = _sources_for_images(_terrain_set, ORCHARD_IMAGES)
	_wheat_sources = _sources_for_images(_terrain_set, WHEAT_IMAGES)
	_crop_sources = _sources_for_images(_terrain_set, CROP_IMAGES)
	for label: String in ["Stone Building", "Wood Building", "Woods"]:
		_building_sources[label] = _source_for(_building_set, label)
	_road_sources.append(RoadTiles.install_curve(_road_set, AlderbrookRoads.ASSET_DIRECTORY + "road_00_opening_the_road.svg", "Road - Opening the Road", _road_layouts[0]["cells"]))
	var map: Map = _build_map(PROLOGUE, 0)
	assert(map != null)
	map.name = "AlderbrookPrologue"
	add_child(map)
	_house(map.get_building_layer(), map.get_terrain_layer(), Vector2i(15, 8), false)
	BuildingVariations.apply(map.get_building_layer(), "alderbrook_00_opening_the_road")
	var scenario: Scenario = map.get_scenario(0)
	scenario.victory_conditions = [
		_occupy(Globals.Team.ALLIES, OccupyObjectiveCondition.ObjectiveId.A, 15.0, true, false),
		_occupy(Globals.Team.ALLIES, OccupyObjectiveCondition.ObjectiveId.B, 15.0, true, false),
		_occupy(Globals.Team.ALLIES, OccupyObjectiveCondition.ObjectiveId.A, 15.0, false, true),
		_occupy(Globals.Team.AXIS, OccupyObjectiveCondition.ObjectiveId.A, 15.0, true, true),
	]
	scenario.offboard_batteries = [load("res://resources/fire_support/alderbrook_prologue_105mm.tres") as OffboardBattery]
	ConnectedTerrainBaker.bake(map.get_terrain_layer(), "00_opening_the_road_terrain")
	ConnectedTerrainBaker.bake(map.get_building_layer(), "00_opening_the_road_woods")
	_terrain_set = map.get_terrain_layer().tile_set
	_building_set = map.get_building_layer().tile_set
	_road_set = map.get_road_layer().tile_set
	# Keep generated resources independent of the five existing maps.
	assert(ResourceSaver.save(_terrain_set, RESOURCE_DIRECTORY + "alderbrook_prologue_terrain.tres") == OK)
	_terrain_set.take_over_path(RESOURCE_DIRECTORY + "alderbrook_prologue_terrain.tres")
	assert(ResourceSaver.save(_building_set, RESOURCE_DIRECTORY + "alderbrook_prologue_buildings.tres") == OK)
	_building_set.take_over_path(RESOURCE_DIRECTORY + "alderbrook_prologue_buildings.tres")
	assert(ResourceSaver.save(_road_set, RESOURCE_DIRECTORY + "alderbrook_prologue_roads.tres") == OK)
	_road_set.take_over_path(RESOURCE_DIRECTORY + "alderbrook_prologue_roads.tres")
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(map) == OK)
	assert(ResourceSaver.save(packed, MAP_DIRECTORY + "00_opening_the_road.tscn") == OK)
	_export_layout(map, PROLOGUE)
	await _bake_los(map)
	main.queue_free()
	map.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Built Alderbrook prologue.")
	get_tree().quit()
