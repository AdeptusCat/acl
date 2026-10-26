extends "res://tools/campaigns/build_alderbrook_campaign.gd"

const PROLOGUE: Dictionary = {
	"id": "00_opening_the_road", "title": "Prologue. Opening the Road", "map": "Alderbrook Forward Road", "size": Vector2i(28, 20), "seconds": 720.0,
	"briefing": "Road to Alderbrook - prologue.\n\nThe company has concentrated its fire support against a thin enemy roadblock. Follow the road north from the southern assembly area. Open the walled outpost at A, then secure the farm at B along the eastern branch. Hedged fields offer covered approaches away from the bends; stone farm courts anchor the defence. Three rifle squads, two machine-gun teams, a light mortar, platoon headquarters and company headquarters are available, with a four-gun 105 mm battery off map.\n\nEstablish machine-gun cover before advancing the rifles. Use the Fire Support tray to order mortar or artillery fire against spotted positions; keep your own troops clear of the target area. The enemy is dispersed between the road and farm, so one bombardment will not clear every position.\n\n[b]Major Victory:[/b] hold A and B for 15 seconds each.\n\n[b]Minor Victory:[/b] hold A for 15 seconds at the deadline. Either victory opens Quiet Approach.\n\n[b]Next assignment:[/b] the company and heavy weapons will continue along the main road. A small rifle patrol with platoon HQ will check the flank toward Alderbrook without fire support.",
	"player": [[0, "company_hq", 4, 18], [1, "hq", 5, 17], [1, "rifle", 6, 15], [1, "rifle", 7, 16], [1, "rifle", 7, 18], [1, "mg", 5, 15], [1, "mg", 6, 18], [2, "light_mortar", 3, 17]],
	"enemy": [[1, "hq", 24, 8], [1, "rifle", 19, 9], [1, "mg", 18, 8], [1, "rifle", 23, 13]],
	"allied_markers": [[1, 19, 9], [2, 23, 13], [4, 5, 17]], "axis_markers": [[1, 19, 9], [2, 23, 13], [4, 24, 8]],
}
const ROUTES: Array[Array] = [
	[Vector3(4, 20.5, -2), Vector3(6, 16, -1.5), Vector3(10, 12, -0.4), Vector3(15, 11.5, 0.4), Vector3(19, 9, -1), Vector3(21, 4, -2), Vector3(23, -1, -2)],
	[Vector3(15, 11.5, 0.4), Vector3(18, 14, 0.9), Vector3(22, 15, 0), Vector3(26, 14.5, -0.3)],
	[Vector3(10, 12, -0.4), Vector3(11, 9.5, -1), Vector3(14, 8.5, 0)],
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
	# Edit the existing mission so unit identities and authored loadouts survive.
	var scene_path: String = MAP_DIRECTORY + "00_opening_the_road.tscn"
	var scene_uid: int = ResourceLoader.get_resource_uid(scene_path)
	var scene_header: String = FileAccess.get_file_as_string(scene_path).get_slice("\n", 0)
	if scene_header.contains('uid="'):
		scene_uid = ResourceUID.text_to_id(scene_header.get_slice('uid="', 1).get_slice('"', 0))
	var map: Map = load(scene_path).instantiate() as Map
	map.campaign_name = ""
	map.use_terrain_palette = false
	add_child(map)
	map.campaign_name = "Road to Alderbrook"
	map.grid_size = PROLOGUE["size"]
	map.get_terrain_layer().tile_set = _terrain_set
	map.get_building_layer().tile_set = _building_set
	map.get_road_layer().tile_set = _road_set
	_create_landscape(map)
	var scenario: Scenario = map.get_scenario(0)
	scenario.scenario_description = PROLOGUE["briefing"]
	scenario.duration_s = PROLOGUE["seconds"]
	_position_roster(map, scenario, PROLOGUE["player"], Globals.Team.ALLIES)
	_position_roster(map, scenario, PROLOGUE["enemy"], Globals.Team.AXIS)
	_set_markers(scenario.get_objectives_layer(Globals.Team.ALLIES), PROLOGUE["allied_markers"], true)
	_set_markers(scenario.get_objectives_layer(Globals.Team.AXIS), PROLOGUE["axis_markers"], false)
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
	assert(ResourceSaver.save(packed, scene_path) == OK)
	if scene_uid != ResourceUID.INVALID_ID:
		assert(ResourceSaver.set_uid(scene_path, scene_uid) == OK)
	_export_layout(map, PROLOGUE)
	if not OS.get_cmdline_user_args().has("--skip-los"):
		await _bake_los(map)
	main.queue_free()
	map.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Built Alderbrook prologue.")
	get_tree().quit()


func _create_landscape(map: Map) -> void:
	for layer: HexagonTileMapLayer in map.get_tilemap_layers():
		layer.clear()
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var grasses: Array[int] = _sources_for_images(ground.tile_set, OPEN_GROUND_IMAGES)
	_grass_noise.seed = 18731
	_grass_noise.frequency = 0.17
	for x: int in range(map.grid_size.x):
		for y: int in range(map.grid_size.y):
			var variation: int = clampi(floori((_grass_noise.get_noise_2d(x, y) + 1.0) * 1.5), 0, 2)
			ground.set_cell(Vector2i(x, y), grasses[variation], Vector2i.ZERO)
	for cell: Vector2i in _road_layouts[0]["cells"]:
		map.get_road_layer().set_cell(cell, _road_sources[0], _road_layouts[0]["cells"][cell])
	# Boards 54/55: hedged pasture compartments, orchard strips and small farm courts.
	# Board 84: separated copses interrupt the fields without forming a forest wall.
	_patch(map, "woods", [Vector2(0, 0), Vector2(4, 0), Vector2(5, 2), Vector2(3, 3), Vector2(0, 2)])
	_patch(map, "woods", [Vector2(0, 14), Vector2(2, 13), Vector2(3, 15), Vector2(2, 17), Vector2(0, 17)])
	_patch(map, "woods", [Vector2(8, 18), Vector2(10, 17), Vector2(11, 19), Vector2(10, 20), Vector2(8, 20)])
	_patch(map, "woods", [Vector2(12, 4), Vector2(14, 3), Vector2(16, 5), Vector2(15, 6), Vector2(13, 6)])
	_patch(map, "woods", [Vector2(25, 0), Vector2(28, 0), Vector2(28, 3), Vector2(26, 4), Vector2(25, 2)])
	_patch(map, "woods", [Vector2(26, 9), Vector2(28, 8), Vector2(28, 12), Vector2(26, 11)])
	_patch(map, "woods", [Vector2(24, 18), Vector2(26, 17), Vector2(28, 19), Vector2(28, 20), Vector2(25, 20)])
	_patch(map, "woods", [Vector2(15, 14), Vector2(16, 13), Vector2(17, 14), Vector2(16, 16), Vector2(15, 16)])
	var parcels: Array[Dictionary] = [
		{"family": "pasture", "shape": [Vector2(1, 10), Vector2(4, 9), Vector2(6, 10), Vector2(6, 13), Vector2(3, 14), Vector2(1, 13)], "gates": [Vector2i(5, 12), Vector2i(2, 10)]},
		{"family": "pasture", "shape": [Vector2(1, 4), Vector2(4, 3), Vector2(6, 4), Vector2(6, 7), Vector2(4, 8), Vector2(1, 7)], "gates": [Vector2i(5, 6), Vector2i(2, 7)]},
		{"family": "wheat", "shape": [Vector2(6, 9), Vector2(9, 8), Vector2(11, 9), Vector2(10, 11), Vector2(8, 12), Vector2(6, 11)], "gates": [Vector2i(9, 10), Vector2i(6, 10)]},
		{"family": "pasture", "shape": [Vector2(10, 0), Vector2(14, 0), Vector2(15, 2), Vector2(14, 4), Vector2(11, 5), Vector2(10, 3)], "gates": [Vector2i(11, 4), Vector2i(14, 2)]},
		{"family": "crops", "shape": [Vector2(16, 1), Vector2(19, 1), Vector2(19, 4), Vector2(17, 5), Vector2(15, 4), Vector2(15, 2)], "gates": [Vector2i(18, 3), Vector2i(16, 4)]},
		{"family": "pasture", "shape": [Vector2(22, 3), Vector2(26, 2), Vector2(27, 4), Vector2(26, 7), Vector2(23, 8), Vector2(22, 6)], "gates": [Vector2i(22, 5), Vector2i(25, 6)]},
		{"family": "pasture", "shape": [Vector2(12, 9), Vector2(15, 8), Vector2(17, 9), Vector2(16, 11), Vector2(14, 12), Vector2(12, 11)], "gates": [Vector2i(14, 11), Vector2i(16, 9)]},
		{"family": "wheat", "shape": [Vector2(10, 14), Vector2(13, 13), Vector2(16, 14), Vector2(15, 16), Vector2(13, 17), Vector2(10, 16)], "gates": [Vector2i(10, 15), Vector2i(14, 14)]},
		{"family": "pasture", "shape": [Vector2(9, 17), Vector2(12, 17), Vector2(14, 19), Vector2(13, 20), Vector2(9, 20), Vector2(8, 19)], "gates": [Vector2i(11, 17), Vector2i(13, 19)]},
		{"family": "crops", "shape": [Vector2(17, 16), Vector2(20, 16), Vector2(22, 17), Vector2(21, 19), Vector2(18, 20), Vector2(16, 18)], "gates": [Vector2i(18, 16), Vector2i(20, 18)]},
		{"family": "pasture", "shape": [Vector2(23, 16), Vector2(26, 16), Vector2(28, 17), Vector2(27, 19), Vector2(24, 20), Vector2(22, 18)], "gates": [Vector2i(24, 16), Vector2i(26, 18)]},
		{"family": "orchard", "shape": [Vector2(6, 4), Vector2(8, 4), Vector2(9, 6), Vector2(8, 9), Vector2(6, 8)], "gates": [Vector2i(8, 7), Vector2i(6, 5)]},
		{"family": "orchard", "shape": [Vector2(21, 9), Vector2(23, 10), Vector2(24, 12), Vector2(23, 13), Vector2(21, 11)], "gates": [Vector2i(22, 12), Vector2i(21, 10)]},
	]
	for parcel: Dictionary in parcels:
		var polygon: Array[Vector2] = []
		polygon.assign(parcel["shape"])
		var gates: Array[Vector2i] = []
		gates.assign(parcel["gates"])
		if parcel["family"] != "pasture":
			_patch(map, str(parcel["family"]), polygon)
		_enclose_polygon(map, polygon, gates)
	for cell: Vector2i in [Vector2i(18, 8), Vector2i(18, 6), Vector2i(23, 13), Vector2i(25, 12), Vector2i(24, 11), Vector2i(10, 7), Vector2i(11, 6), Vector2i(14, 7)]:
		_house(map.get_building_layer(), map.get_terrain_layer(), cell, cell.x < 22)
	BuildingVariations.apply(map.get_building_layer(), "alderbrook_00_opening_the_road")
	_enclose(map, Rect2i(9, 6, 3, 3), 0, [Vector2i(10, 8), Vector2i(11, 7)])
	_enclose(map, Rect2i(17, 6, 4, 5), 0, [Vector2i(19, 10), Vector2i(17, 8)])
	_enclose(map, Rect2i(22, 12, 4, 4), 0, [Vector2i(22, 14), Vector2i(25, 14)])


func _patch(map: Map, family: String, vertices: Array[Vector2]) -> void:
	var sources: Array[int] = _woods_sources
	if family == "orchard":
		sources = _orchard_sources
	elif family == "wheat":
		sources = _wheat_sources
	elif family == "crops":
		sources = _crop_sources
	for x: int in range(map.grid_size.x):
		for y: int in range(map.grid_size.y):
			var cell: Vector2i = Vector2i(x, y)
			var point: Vector2 = Vector2(x + 0.5, y + 0.5 + (x % 2) * 0.5)
			if _road_layouts[0]["cells"].has(cell) or not Geometry2D.is_point_in_polygon(point, PackedVector2Array(vertices)):
				continue
			if family != "woods" and map.get_building_layer().get_cell_source_id(cell) >= 0:
				continue
			var variant: int = posmod(x / 3 + y / 3, sources.size())
			map.get_terrain_layer().set_cell(cell, sources[variant], Vector2i.ZERO)
			if family == "woods":
				map.get_building_layer().set_cell(cell, _wood_building_sources[variant], Vector2i.ZERO)


func _enclose_polygon(map: Map, vertices: Array[Vector2], gates: Array[Vector2i]) -> void:
	var cells: Dictionary[Vector2i, bool] = {}
	for x: int in range(map.grid_size.x):
		for y: int in range(map.grid_size.y):
			var point: Vector2 = Vector2(x + 0.5, y + 0.5 + (x % 2) * 0.5)
			if Geometry2D.is_point_in_polygon(point, PackedVector2Array(vertices)):
				cells[Vector2i(x, y)] = true
	var walls: WallTileMapLayer = map.get_wall_layer() as WallTileMapLayer
	for cell: Vector2i in cells:
		for side: int in range(6):
			var neighbor: Vector2i = walls.get_neighbor_cell(cell, ConnectedWalls.SIDES[side])
			if cells.has(neighbor) or gates.has(cell) or gates.has(neighbor):
				continue
			if map.get_ground_layer().get_cell_source_id(neighbor) < 0 or _road_layouts[0]["cells"].has(cell) or _road_layouts[0]["cells"].has(neighbor):
				continue
			if (walls.get_edge_mask(neighbor) & (1 << ((side + 3) % 6))) == 0:
				walls.edit_edge(cell, side, 1)


func _enclose(map: Map, parcel: Rect2i, kind: int, gates: Array[Vector2i]) -> void:
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var walls: WallTileMapLayer = map.get_wall_layer() as WallTileMapLayer
	for x: int in range(parcel.position.x, parcel.end.x):
		for y: int in range(parcel.position.y, parcel.end.y):
			var cell: Vector2i = Vector2i(x, y)
			for side: int in range(6):
				var neighbor: Vector2i = ground.get_neighbor_cell(cell, ConnectedWalls.SIDES[side])
				if parcel.has_point(neighbor) or gates.has(cell) or gates.has(neighbor):
					continue
				if ground.get_cell_source_id(neighbor) < 0 or _road_layouts[0]["cells"].has(cell) or _road_layouts[0]["cells"].has(neighbor):
					continue
				if (walls.get_edge_mask(neighbor) & (1 << ((side + 3) % 6))) == 0:
					walls.edit_edge(cell, side, kind)


func _position_roster(map: Map, scenario: Scenario, roster: Array, team: Globals.Team) -> void:
	var used: Array[Unit] = []
	var types: Dictionary[String, int] = {"company_hq": Globals.SquadType.COMPANY_HEADQUARTERS, "hq": Globals.SquadType.PLATOON_HEADQUARTERS, "rifle": Globals.SquadType.Rifle, "mg": Globals.SquadType.MG, "light_mortar": Globals.SquadType.MORTAR}
	for entry: Array in roster:
		var found: bool = false
		for unit: Unit in scenario.get_units():
			if unit.team == team and unit.platoon == int(entry[0]) and unit.squad_type == types[str(entry[1])] and not used.has(unit):
				unit.position = map.get_ground_layer().map_to_local(Vector2i(int(entry[2]), int(entry[3])))
				used.append(unit)
				found = true
				break
		assert(found, "The existing force must contain each authored deployment")
