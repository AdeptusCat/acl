extends "res://tools/campaigns/build_alderbrook_campaign.gd"

# Board 10/12: village fringes; board 6: estate; board 1/20: town blocks.
# Rebuild only mission five. Existing campaign identities and rules are retained.
const VILLAGE_ID: String = "05_battle_for_alderbrook"
const VILLAGE_SCENE: String = MAP_DIRECTORY + VILLAGE_ID + ".tscn"
const VILLAGE_TERRAIN: String = RESOURCE_DIRECTORY + "alderbrook_village_terrain.tres"
const VILLAGE_SIZE: Vector2i = AlderbrookVillageLayout.SIZE
const VILLAGE_ROUTES: Array[Array] = AlderbrookVillageLayout.ROUTES
const VILLAGE_PLAYER: Array[Array] = AlderbrookVillageLayout.PLAYER
const VILLAGE_ENEMY: Array[Array] = AlderbrookVillageLayout.ENEMY
const VILLAGE_ALLIED_MARKERS: Array[Array] = AlderbrookVillageLayout.ALLIED_MARKERS
const VILLAGE_AXIS_MARKERS: Array[Array] = AlderbrookVillageLayout.AXIS_MARKERS
const VILLAGE_BRIEFING: String = AlderbrookVillageLayout.BRIEFING

var village_layout: Dictionary = {}
var village_stone: Array[int] = []
var village_wood: Array[int] = []
var village_road: int = -1


func _run() -> void:
	village_layout = _roads.layout_for_routes(VILLAGE_ROUTES, VILLAGE_SIZE)
	if OS.get_cmdline_user_args().has("--roads-only"):
		_roads.write_assets(VILLAGE_ID, village_layout)
		get_tree().quit()
		return
	for index: int in range(MISSIONS.size()):
		_road_layouts.append(_roads.layout(index, MISSIONS[index]["size"]))
	_road_layouts[4] = village_layout
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.name = "Main"
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.world.fully_freed.disconnect(main._on_fully_freed)
	var map: Map = load(VILLAGE_SCENE).instantiate() as Map
	# Do not serialize palette shaders into the editable source scene.
	map.campaign_name = ""
	map.use_terrain_palette = false
	add_child(map)
	map.process_mode = Node.PROCESS_MODE_DISABLED
	map.campaign_name = "Road to Alderbrook"
	if not OS.get_cmdline_user_args().has("--los-only"):
		_create_village(map)
		if not _validate_village(map):
			get_tree().quit(1)
			return
		ConnectedTerrainBaker.bake(map.get_terrain_layer(), VILLAGE_ID + "_village_terrain")
		var buildings: BuildingTileMapLayer = map.get_building_layer() as BuildingTileMapLayer
		ConnectedTerrainBaker.bake(buildings, VILLAGE_ID + "_village_woods")
		assert(ResourceSaver.save(map.get_terrain_layer().tile_set, VILLAGE_TERRAIN) == OK)
		assert(ResourceSaver.save(map.get_road_layer().tile_set, RoadTiles.TILE_SET_PATH) == OK)
		map.get_terrain_layer().tile_set.take_over_path(VILLAGE_TERRAIN)
		var shared: TileSet = load(BuildingVariations.SHARED_TILE_SET) as TileSet
		share_buildings(buildings, shared)
		assert(ResourceSaver.save(shared, BuildingVariations.SHARED_TILE_SET) == OK)
		var packed: PackedScene = PackedScene.new()
		assert(packed.pack(map) == OK)
		assert(ResourceSaver.save(packed, VILLAGE_SCENE) == OK)
	_export_layout(map, village_spec())
	if not OS.get_cmdline_user_args().has("--skip-los"):
		await _bake_los(map)
	map.queue_free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Built Battle for Alderbrook: farmland, estate, market and timber yards.")
	get_tree().quit()


func village_spec() -> Dictionary:
	var spec: Dictionary = MISSIONS[4].duplicate(true)
	spec["briefing"] = VILLAGE_BRIEFING
	spec["player"] = VILLAGE_PLAYER
	spec["enemy"] = VILLAGE_ENEMY
	spec["allied_markers"] = VILLAGE_ALLIED_MARKERS
	spec["axis_markers"] = VILLAGE_AXIS_MARKERS
	return spec


func _create_village(map: Map) -> void:
	map.grid_size = VILLAGE_SIZE
	for layer: HexagonTileMapLayer in map.get_tilemap_layers():
		layer.clear()
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var terrain: HexagonTileMapLayer = map.get_terrain_layer()
	var buildings: BuildingTileMapLayer = map.get_building_layer() as BuildingTileMapLayer
	buildings.synchronize_buildings()
	_terrain_set = terrain.tile_set.duplicate(true) as TileSet
	_building_set = buildings.tile_set.duplicate(true) as TileSet
	_prune_terrain(_terrain_set)
	_prune_terrain(_building_set)
	terrain.tile_set = _terrain_set
	buildings.tile_set = _building_set
	_woods_sources = _sources_for_images(_terrain_set, WOODS_IMAGES)
	_wood_building_sources = _sources_for_images(_building_set, WOODS_IMAGES)
	_orchard_sources = _sources_for_images(_terrain_set, ORCHARD_IMAGES)
	_wheat_sources = _sources_for_images(_terrain_set, WHEAT_IMAGES)
	_crop_sources = _sources_for_images(_terrain_set, CROP_IMAGES)
	for material: String in ["wood", "stone"]:
		for number: int in range(1, 4):
			var source: int = _sources_for_images(_building_set, [BuildingVariations.texture_path("building_%s_%02d" % [material, number])])[0]
			if material == "wood":
				village_wood.append(source)
			else:
				village_stone.append(source)
	var grasses: Array[int] = _sources_for_images(ground.tile_set, OPEN_GROUND_IMAGES)
	_grass_noise.seed = 57293
	_grass_noise.frequency = 0.18
	for x: int in range(VILLAGE_SIZE.x):
		for y: int in range(VILLAGE_SIZE.y):
			var variation: int = clampi(floori((_grass_noise.get_noise_2d(x, y) + 1.0) * 1.5), 0, 2)
			ground.set_cell(Vector2i(x, y), grasses[variation], Vector2i.ZERO)
	_paint_roads(map.get_road_layer())
	# Irregular woodland pockets screen deployment and interrupt long field views.
	_patch(map, "woods", [Vector2(0, 0), Vector2(7, 0), Vector2(8, 1), Vector2(6, 2), Vector2(2, 2), Vector2(0, 3)])
	_patch(map, "woods", [Vector2(0, 16), Vector2(3, 15), Vector2(5, 16), Vector2(8, 17), Vector2(8, 18), Vector2(0, 18)])
	_patch(map, "woods", [Vector2(5, 6), Vector2(7, 5), Vector2(8, 6), Vector2(7, 8), Vector2(5, 8)])
	_patch(map, "woods", [Vector2(8, 10), Vector2(9, 9), Vector2(10, 10), Vector2(10, 12), Vector2(8, 12)])
	_patch(map, "woods", [Vector2(9, 0), Vector2(12, 0), Vector2(13, 1), Vector2(11, 2), Vector2(9, 2)])
	_patch(map, "woods", [Vector2(22, 16), Vector2(24, 15), Vector2(26, 16), Vector2(26, 18), Vector2(22, 18)])
	_patch(map, "orchard", [Vector2(7, 1), Vector2(10, 1), Vector2(12, 2), Vector2(12, 5), Vector2(10, 6), Vector2(8, 5)])
	_patch(map, "orchard", [Vector2(10, 14), Vector2(13, 14), Vector2(14, 16), Vector2(13, 18), Vector2(10, 17)])
	_patch(map, "orchard", [Vector2(22, 0), Vector2(26, 0), Vector2(26, 3), Vector2(24, 4), Vector2(23, 3)])
	_patch(map, "wheat", [Vector2(1, 4), Vector2(4, 4), Vector2(5, 5), Vector2(4, 7), Vector2(1, 7)])
	_patch(map, "crops", [Vector2(1, 10), Vector2(5, 10), Vector2(6, 12), Vector2(5, 14), Vector2(1, 14)])
	_patch(map, "wheat", [Vector2(5, 9), Vector2(8, 9), Vector2(8, 12), Vector2(6, 13), Vector2(5, 12)])
	_patch(map, "crops", [Vector2(13, 0), Vector2(17, 0), Vector2(18, 1), Vector2(17, 2), Vector2(13, 2)])
	_place_pond(map)
	_place_landmarks(map)
	_place_houses(map)
	_place_boundaries(map)
	var scenario: Scenario = map.get_scenario(0)
	# Keep existing unit identities, loadouts, campaign links and victory resources.
	scenario.scenario_description = VILLAGE_BRIEFING
	for roster: Array in [VILLAGE_PLAYER, VILLAGE_ENEMY]:
		var team: Globals.Team = Globals.Team.ALLIES
		if roster == VILLAGE_ENEMY:
			team = Globals.Team.AXIS
		var units: Array[Unit] = []
		for unit: Unit in scenario.get_units():
			if unit.team == team:
				units.append(unit)
		assert(units.size() == roster.size())
		for index: int in range(units.size()):
			units[index].position = ground.map_to_local(Vector2i(roster[index][2], roster[index][3]))
	_set_markers(scenario.get_node("Objectives/AlliedObjectivesTileMapLayer") as HexagonTileMapLayer, VILLAGE_ALLIED_MARKERS, true)
	_set_markers(scenario.get_node("Objectives/AxisObjectivesTileMapLayer") as HexagonTileMapLayer, VILLAGE_AXIS_MARKERS, false)
	buildings.synchronize_buildings()
	print("Village: ", buildings.get_used_cells().size(), " building/woods cells, ", map.get_wall_layer().get_used_cells().size(), " barrier cells.")


func _prune_terrain(tiles: TileSet) -> void:
	var remove: Array[int] = []
	for index: int in range(tiles.get_source_count()):
		var id: int = tiles.get_source_id(index)
		var label: String = tiles.get_source(id).resource_name
		if label.begins_with("Connected terrain") or label.begins_with("Road -"):
			remove.append(id)
	for id: int in remove:
		tiles.remove_source(id)


func _paint_roads(roads: HexagonTileMapLayer) -> void:
	village_road = RoadTiles.install_curve(roads.tile_set, AlderbrookRoads.ASSET_DIRECTORY + "road_" + VILLAGE_ID + ".svg", "Road - Alderbrook village streets", village_layout["cells"])
	for cell: Vector2i in village_layout["cells"]:
		var atlas: Vector2i = village_layout["cells"][cell]
		roads.set_cell(cell, village_road, atlas)


func _patch(map: Map, family: String, vertices: Array[Vector2]) -> void:
	var terrain: HexagonTileMapLayer = map.get_terrain_layer()
	var sources: Array[int] = _woods_sources
	if family == "orchard":
		sources = _orchard_sources
	elif family == "wheat":
		sources = _wheat_sources
	elif family == "crops":
		sources = _crop_sources
	for x: int in range(VILLAGE_SIZE.x):
		for y: int in range(VILLAGE_SIZE.y):
			var cell: Vector2i = Vector2i(x, y)
			var point: Vector2 = Vector2(x + 0.5, y + 0.5 + (x % 2) * 0.5)
			if village_layout["cells"].has(cell) or not Geometry2D.is_point_in_polygon(point, PackedVector2Array(vertices)):
				continue
			var variant: int = posmod(x / 3 + y / 3, sources.size())
			terrain.set_cell(cell, sources[variant], Vector2i.ZERO)
			if family == "woods":
				map.get_building_layer().set_cell(cell, _wood_building_sources[variant], Vector2i.ZERO)
			else:
				map.get_building_layer().erase_cell(cell)


func _place_pond(map: Map) -> void:
	# Water remains impassable; this pond does not divide the board.
	var water: HexagonTileMapLayer = map.get_node("TileMapLayers/WaterTileMapLayer") as HexagonTileMapLayer
	var cells: Array[Vector2i] = [Vector2i(6, 15), Vector2i(7, 14), Vector2i(7, 15), Vector2i(8, 15)]
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="128"><defs><clipPath id="hex"><path d="M32 0H96L128 64 96 128H32L0 64Z"/></clipPath></defs>'
	for index: int in range(cells.size()):
		var cell: Vector2i = cells[index]
		svg += '<g transform="translate(%d 0)" clip-path="url(#hex)"><rect width="128" height="128" fill="#527d88"/>' % (index * 128)
		for side: int in range(6):
			if cells.has(water.get_neighbor_cell(cell, ConnectedWalls.SIDES[side])):
				continue
			var start: Vector2 = ConnectedWalls.VERTICES[side] + Vector2(64, 64)
			var end: Vector2 = ConnectedWalls.VERTICES[(side + 1) % 6] + Vector2(64, 64)
			svg += '<path d="M%f %fL%f %f" fill="none" stroke="#94a078" stroke-width="12" stroke-linecap="round"/>' % [start.x, start.y, end.x, end.y]
			svg += '<path d="M%f %fL%f %f" fill="none" stroke="#b9ad84" stroke-width="4" stroke-linecap="round"/>' % [start.x, start.y, end.x, end.y]
		# Quiet water ripples are sparse and do not outline internal hex joins.
		for row: int in range(3):
			var y: int = 30 + row * 32
			var x: int = 28 + posmod(cell.x * 13 + row * 19, 30)
			svg += '<path d="M%d %dQ%d %d %d %d" fill="none" stroke="#9db8b7" opacity=".28" stroke-width="1.5"/>' % [x, y, x + 13, y + 3, x + 26, y]
		svg += '</g>'
	svg += '</svg>'
	var path: String = "res://assets/tiles/campaign/alderbrook_pond.svg"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(svg)
	file.close()
	var image: Image = Image.new()
	assert(image.load_svg_from_string(svg) == OK)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/art/water/rasters/"))
	assert(image.save_png("res://docs/art/water/rasters/alderbrook_pond.png") == OK)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	texture.take_over_path(path)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(128, 128)
	source.resource_name = "Connected pond"
	water.tile_set = water.tile_set.duplicate(true) as TileSet
	while water.tile_set.get_source_count() > 0:
		water.tile_set.remove_source(water.tile_set.get_source_id(0))
	water.tile_set.add_source(source, 0)
	for index: int in range(cells.size()):
		var cell: Vector2i = cells[index]
		assert(not village_layout["cells"].has(cell))
		map.get_ground_layer().erase_cell(cell)
		map.get_terrain_layer().erase_cell(cell)
		map.get_building_layer().erase_cell(cell)
		var atlas: Vector2i = Vector2i(index, 0)
		source.create_tile(atlas)
		water.set_cell(cell, 0, atlas)


func _place_landmarks(map: Map) -> void:
	# Multihex footprints are real occupied cells, including LOS and defense.
	_multi(map, Vector2i(14, 5), "building_stone_03_3hex", 0)
	_multi(map, Vector2i(20, 10), "building_stone_03_3hex", 5)
	_multi(map, Vector2i(14, 15), "building_wood_01_3hex", 1)
	_multi(map, Vector2i(10, 6), "building_wood_02_2hex_a", 1)
	_multi(map, Vector2i(12, 10), "building_wood_01_2hex_b", 0)
	_multi(map, Vector2i(17, 1), "building_stone_01_2hex_a", 0)
	_multi(map, Vector2i(23, 6), "building_stone_02_2hex_b", 2)
	_multi(map, Vector2i(21, 15), "building_wood_03_2hex_a", 0)


func _multi(map: Map, anchor: Vector2i, design: String, orientation: int) -> void:
	var buildings: BuildingTileMapLayer = map.get_building_layer() as BuildingTileMapLayer
	var pattern: TileMapPattern = MultihexBuildings.pattern_for(buildings.tile_set, design, orientation)
	assert(pattern != null, "Unknown building: " + design)
	for local: Vector2i in pattern.get_used_cells():
		var cell: Vector2i = buildings.map_pattern(anchor, local, pattern)
		assert(Rect2i(Vector2i.ZERO, VILLAGE_SIZE).has_point(cell) and not village_layout["cells"].has(cell), "Landmark overlaps road: %s %s" % [design, cell])
		assert(map.get_ground_layer().get_cell_source_id(cell) >= 0)
		assert(buildings.get_cell_source_id(cell) < 0, "Landmark overlaps woodland or building")
		map.get_terrain_layer().erase_cell(cell)
	buildings.place_multihex_building(anchor, design, orientation)


func _place_houses(map: Map) -> void:
	var cells: Array[Vector2i] = [
		Vector2i(5, 5), Vector2i(6, 6), Vector2i(7, 4), Vector2i(8, 10), Vector2i(9, 9), Vector2i(11, 7), Vector2i(11, 10), Vector2i(9, 13), Vector2i(10, 15), Vector2i(12, 13), Vector2i(13, 5), Vector2i(13, 10),
		Vector2i(13, 2), Vector2i(15, 4), Vector2i(16, 2), Vector2i(17, 5), Vector2i(18, 4), Vector2i(18, 2), Vector2i(19, 5), Vector2i(19, 1),
		Vector2i(15, 6), Vector2i(16, 7), Vector2i(17, 7), Vector2i(17, 9), Vector2i(18, 7), Vector2i(19, 6), Vector2i(20, 5), Vector2i(20, 7), Vector2i(21, 7), Vector2i(21, 9), Vector2i(22, 9), Vector2i(24, 7), Vector2i(24, 5), Vector2i(25, 6),
		Vector2i(15, 10), Vector2i(16, 11), Vector2i(17, 11), Vector2i(18, 12), Vector2i(19, 12), Vector2i(20, 10), Vector2i(21, 10), Vector2i(22, 11), Vector2i(23, 10), Vector2i(24, 11), Vector2i(25, 10),
		Vector2i(14, 12), Vector2i(14, 14), Vector2i(15, 15), Vector2i(17, 16), Vector2i(18, 15), Vector2i(19, 16), Vector2i(20, 15), Vector2i(21, 14), Vector2i(21, 16), Vector2i(24, 14), Vector2i(25, 15),
	]
	for x: int in range(13, 26):
		for y: int in range(1, 17):
			if posmod(x * 3 + y * 2, 7) <= 3 and not Rect2i(18, 5, 2, 2).has_point(Vector2i(x, y)):
				cells.append(Vector2i(x, y))
	var buildings: HexagonTileMapLayer = map.get_building_layer()
	for cell: Vector2i in cells:
		if village_layout["cells"].has(cell) or buildings.get_cell_source_id(cell) >= 0 or map.get_ground_layer().get_cell_source_id(cell) < 0:
			continue
		var sources: Array[int] = village_wood
		if cell.x >= 17 and posmod(cell.x + cell.y * 3, 4) <= 1:
			sources = village_stone
		var variant: int = posmod(cell.x * 7 + cell.y * 3, sources.size())
		var angle: int = posmod(cell.x * 5 + cell.y * 7, 6)
		buildings.set_cell(cell, sources[variant], Vector2i(angle, 0))
		map.get_terrain_layer().erase_cell(cell)


func _place_boundaries(map: Map) -> void:
	# Parcel perimeters use shared hex sides, with gates facing roads and gardens.
	_enclose(map, Rect2i(1, 4, 4, 3), 1, [Vector2i(4, 5), Vector2i(2, 6)])
	_enclose(map, Rect2i(1, 10, 5, 4), 1, [Vector2i(5, 11), Vector2i(2, 10)])
	_enclose(map, Rect2i(5, 9, 3, 4), 1, [Vector2i(7, 9), Vector2i(5, 11)])
	_enclose(map, Rect2i(8, 1, 4, 5), 1, [Vector2i(8, 3), Vector2i(11, 4)])
	_enclose(map, Rect2i(10, 14, 4, 3), 1, [Vector2i(12, 14), Vector2i(10, 16)])
	_enclose(map, Rect2i(12, 4, 4, 4), 0, [Vector2i(14, 5), Vector2i(15, 7)])
	_enclose(map, Rect2i(19, 10, 3, 3), 0, [Vector2i(20, 10), Vector2i(21, 11)])
	_enclose(map, Rect2i(15, 14, 4, 3), 1, [Vector2i(16, 14), Vector2i(18, 15)])
	_enclose(map, Rect2i(23, 1, 3, 3), 1, [Vector2i(23, 2), Vector2i(25, 3)])


func _enclose(map: Map, parcel: Rect2i, kind: int, gates: Array[Vector2i]) -> void:
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var buildings: BuildingTileMapLayer = map.get_building_layer() as BuildingTileMapLayer
	var walls: WallTileMapLayer = map.get_wall_layer() as WallTileMapLayer
	for x: int in range(parcel.position.x, parcel.end.x):
		for y: int in range(parcel.position.y, parcel.end.y):
			var cell: Vector2i = Vector2i(x, y)
			for side: int in range(6):
				var neighbor: Vector2i = ground.get_neighbor_cell(cell, ConnectedWalls.SIDES[side])
				if parcel.has_point(neighbor) or gates.has(cell) or gates.has(neighbor):
					continue
				if ground.get_cell_source_id(cell) < 0 or ground.get_cell_source_id(neighbor) < 0:
					continue
				# Keep road verges open and avoid slicing through a multihex roof.
				if village_layout["cells"].has(cell) or village_layout["cells"].has(neighbor):
					continue
				if buildings.get_cell_source_id(cell) >= 0 and buildings.get_building_cells(cell).has(neighbor):
					continue
				if (walls.get_edge_mask(neighbor) & (1 << ((side + 3) % 6))) != 0:
					continue
				walls.edit_edge(cell, side, kind)


func _validate_village(map: Map) -> bool:
	var valid: bool = true
	var buildings: BuildingTileMapLayer = map.get_building_layer() as BuildingTileMapLayer
	for cell: Vector2i in village_layout["cells"]:
		if buildings.get_cell_source_id(cell) >= 0 or map.get_ground_layer().get_cell_source_id(cell) < 0:
			push_error("Invalid road corridor: " + str(cell))
			valid = false
	for marker: Array in VILLAGE_ALLIED_MARKERS:
		if marker[0] == 4:
			continue
		var cell: Vector2i = Vector2i(marker[1], marker[2])
		var data: TileData = buildings.get_cell_tile_data(cell)
		if data == null or int(data.get_custom_data("building_hexes")) != 3:
			push_error("Objective needs a covered building: " + str(cell))
			valid = false
	return valid


func share_buildings(buildings: BuildingTileMapLayer, shared: TileSet) -> void:
	# Refresh our generated woods source in place without renumbering other maps.
	for index: int in range(buildings.tile_set.get_source_count()):
		var source: TileSetAtlasSource = buildings.tile_set.get_source(buildings.tile_set.get_source_id(index)) as TileSetAtlasSource
		if source.resource_name != "Connected terrain - " + VILLAGE_ID + "_village_woods":
			continue
		for shared_index: int in range(shared.get_source_count()):
			var id: int = shared.get_source_id(shared_index)
			if shared.get_source(id).resource_name != source.resource_name:
				continue
			var copy: TileSetAtlasSource = source.duplicate(true) as TileSetAtlasSource
			copy.texture = source.texture
			copy.resource_scene_unique_id = shared.get_source(id).resource_scene_unique_id
			shared.remove_source(id)
			shared.add_source(copy, id)
			break
	BuildingVariations.use_shared(buildings, shared)
