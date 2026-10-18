extends "res://tools/campaigns/build_alderbrook_campaign.gd"

const SCENE_PATH: String = "res://scenes/campaigns/alderbrook/05_battle_for_alderbrook.tscn"
const ORCHARD_GARDENS: Array[Vector2i] = [
	Vector2i(14, 1), Vector2i(15, 2), Vector2i(16, 1), Vector2i(16, 2),
	Vector2i(12, 5), Vector2i(13, 4), Vector2i(13, 5), Vector2i(12, 6), Vector2i(13, 6), Vector2i(13, 7),
	Vector2i(23, 2), Vector2i(23, 3), Vector2i(24, 3),
	Vector2i(23, 6), Vector2i(24, 6), Vector2i(25, 6), Vector2i(25, 7),
	Vector2i(13, 10), Vector2i(14, 10),
	Vector2i(17, 11), Vector2i(18, 10), Vector2i(17, 12), Vector2i(18, 12),
	Vector2i(19, 16), Vector2i(20, 16), Vector2i(19, 17), Vector2i(20, 17),
]
const VILLAGE_COPSES: Array[Vector2i] = [Vector2i(12, 4), Vector2i(22, 4), Vector2i(24, 7), Vector2i(15, 10), Vector2i(16, 12), Vector2i(18, 16)]

var added_orchards: int = 0
var added_woods: int = 0
var added_edges: int = 0


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.world.fully_freed.disconnect(main._on_fully_freed)
	var map: Map = main.world.maps.get_node("Alderbrook5") as Map
	await get_tree().process_frame
	_dump_layout(map, "/tmp/alderbrook-village-current.json")
	if OS.get_cmdline_user_args().has("--manifest-only"):
		_dump_layout(map, IMAGE_DIRECTORY + "05_battle_for_alderbrook.json")
	if OS.get_cmdline_user_args().has("--apply"):
		var before: Dictionary[Vector2i, Array] = _building_snapshot(map)
		_add_details(map)
		_assert_existing_buildings(map, before)
		_save_layer_data(map)
		_dump_layout(map, IMAGE_DIRECTORY + "05_battle_for_alderbrook.json")
		print("Added village detail: ", added_orchards, " orchard hexes, ", added_woods, " single-hex copses, ", added_edges, " wall/hedge edges. Existing building cells preserved: ", before.size())
	if OS.get_cmdline_user_args().has("--bake-los"):
		await _bake_los(map)
		_verify_los(map)
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit()


func _building_snapshot(map: Map) -> Dictionary[Vector2i, Array]:
	var result: Dictionary[Vector2i, Array] = {}
	var layer: HexagonTileMapLayer = map.get_building_layer()
	for cell: Vector2i in layer.get_used_cells():
		result[cell] = [layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)]
	return result


func _assert_existing_buildings(map: Map, before: Dictionary[Vector2i, Array]) -> void:
	var after: Dictionary[Vector2i, Array] = _building_snapshot(map)
	for cell: Vector2i in before:
		assert(after.has(cell) and after[cell] == before[cell], "Existing building or woodland was altered: " + str(cell))


func _add_details(map: Map) -> void:
	var terrain: HexagonTileMapLayer = map.get_terrain_layer()
	var buildings: HexagonTileMapLayer = map.get_building_layer()
	var orchards: Array[int] = _sources_for_images(terrain.tile_set, ORCHARD_IMAGES)
	var trees: Array[int] = _sources_for_images(terrain.tile_set, WOODS_IMAGES)
	var blocking_trees: Array[int] = _sources_for_images(buildings.tile_set, WOODS_IMAGES)
	for cell: Vector2i in ORCHARD_GARDENS:
		if not _empty_garden(map, cell):
			continue
		terrain.set_cell(cell, orchards[posmod(cell.x + cell.y, orchards.size())], Vector2i.ZERO)
		added_orchards += 1
	for cell: Vector2i in VILLAGE_COPSES:
		if not _empty_garden(map, cell):
			continue
		var variant: int = posmod(cell.x + cell.y, trees.size())
		terrain.set_cell(cell, trees[variant], Vector2i.ZERO)
		buildings.set_cell(cell, blocking_trees[variant], Vector2i.ZERO)
		added_woods += 1
	# Garden parcels have open street frontages and explicit pedestrian gates.
	_garden_boundary(map, Rect2i(14, 1, 3, 2), 1, [Vector2i(15, 2)])
	_garden_boundary(map, Rect2i(12, 4, 4, 4), 0, [Vector2i(14, 5), Vector2i(15, 7), Vector2i(12, 6)])
	_garden_boundary(map, Rect2i(23, 1, 3, 3), 1, [Vector2i(23, 2), Vector2i(25, 3)])
	_garden_boundary(map, Rect2i(23, 6, 3, 2), 1, [Vector2i(23, 6), Vector2i(25, 7)])
	_garden_boundary(map, Rect2i(11, 10, 4, 3), 0, [Vector2i(13, 10), Vector2i(12, 11), Vector2i(14, 12)])
	_garden_boundary(map, Rect2i(16, 10, 3, 3), 1, [Vector2i(16, 10), Vector2i(18, 11), Vector2i(17, 12)])
	_garden_boundary(map, Rect2i(19, 9, 4, 4), 0, [Vector2i(21, 10), Vector2i(22, 11), Vector2i(19, 12)])
	_garden_boundary(map, Rect2i(18, 15, 4, 3), 1, [Vector2i(18, 15), Vector2i(21, 16), Vector2i(19, 17)])


func _empty_garden(map: Map, cell: Vector2i) -> bool:
	return map.get_ground_layer().get_cell_source_id(cell) >= 0 and map.get_road_layer().get_cell_source_id(cell) < 0 and map.get_terrain_layer().get_cell_source_id(cell) < 0 and map.get_building_layer().get_cell_source_id(cell) < 0


func _garden_boundary(map: Map, parcel: Rect2i, kind: int, gates: Array[Vector2i]) -> void:
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var roads: HexagonTileMapLayer = map.get_road_layer()
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
				if _is_road(roads, cell) or _is_road(roads, neighbor):
					continue
				if buildings.get_building_cells(cell).has(neighbor):
					continue
				var opposite: int = (side + 3) % 6
				if (walls.get_edge_mask(cell) & (1 << side)) != 0 or (walls.get_edge_mask(neighbor) & (1 << opposite)) != 0:
					continue
				# One cell cannot mix materials; retain every pre-existing barrier.
				if _accepts_edge(walls, cell, kind):
					walls.edit_edge(cell, side, kind)
				elif _accepts_edge(walls, neighbor, kind):
					walls.edit_edge(neighbor, opposite, kind)
				else:
					continue
				added_edges += 1


func _is_road(layer: HexagonTileMapLayer, cell: Vector2i) -> bool:
	var data: TileData = layer.get_cell_tile_data(cell)
	return data != null and str(data.get_custom_data("name")) == "Road"


func _accepts_edge(walls: WallTileMapLayer, cell: Vector2i, kind: int) -> bool:
	var data: TileData = walls.get_cell_tile_data(cell)
	if data == null:
		return true
	return str(data.get_custom_data("name")) == ConnectedWalls.LABELS[kind]


func _save_layer_data(map: Map) -> void:
	# Patch only tile-data lines. Preserve the user's scene, units and resources.
	var layers: Dictionary[String, HexagonTileMapLayer] = {"TerrainTileMapLayer": map.get_terrain_layer(), "WallTileMapLayer": map.get_wall_layer(), "BuildingTileMapLayer": map.get_building_layer()}
	var lines: PackedStringArray = FileAccess.get_file_as_string(SCENE_PATH).split("\n")
	var active: String = ""
	var updated: int = 0
	for index: int in range(lines.size()):
		if lines[index].begins_with("[node name=\""):
			active = lines[index].get_slice("\"", 1)
		elif layers.has(active) and lines[index].begins_with("tile_map_data = "):
			var bytes: PackedByteArray = layers[active].get("tile_map_data")
			lines[index] = 'tile_map_data = PackedByteArray("%s")' % Marshalls.raw_to_base64(bytes)
			updated += 1
	assert(updated == 3)
	var file: FileAccess = FileAccess.open(SCENE_PATH, FileAccess.WRITE)
	file.store_string("\n".join(lines))


func _verify_los(map: Map) -> void:
	var saved: LosLookupData = ResourceLoader.load(map.los_resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LosLookupData
	assert(saved.building_layout_signature == LOSHelper.building_layout_signature())
	assert(saved.wall_layout_signature == LOSHelper.wall_layout_signature())
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var cells: Array[Vector2i] = ground.get_used_cells()
	cells.sort()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 504131
	for index: int in range(1500):
		var origin: Vector2i = cells[random.randi_range(0, cells.size() - 1)]
		var target: Vector2i = cells[random.randi_range(0, cells.size() - 1)]
		if origin == target:
			continue
		var live: Dictionary = LOSHelper.check_los(ground.map_to_local(origin), ground.map_to_local(target), 1, 0, 1, 0)
		assert(saved.los_lookup[origin].has(target) == not bool(live["blocked"]))
		if bool(live["blocked"]):
			continue
		for key: String in ["shooter_cover", "target_cover", "wall_cover", "hindrance", "target_concealment"]:
			assert(saved.los_lookup[origin][target][key] == live[key])
	print("Village detail LOS: 1,500 sampled pairs match the rebuilt cache.")


func _dump_layout(map: Map, path: String) -> void:
	var scenario: Scenario = map.get_scenario(0)
	var result: Dictionary = {"id": "05_battle_for_alderbrook", "title": scenario.scenario_name, "size": [map.grid_size.x, map.grid_size.y], "seconds": 900, "layers": [], "player": [], "enemy": [], "allied_markers": [], "axis_markers": []}
	result["road_centerlines"] = AlderbrookRoads.centerlines(_roads.layout_for_routes(AlderbrookVillageLayout.ROUTES, map.grid_size))
	for layer: HexagonTileMapLayer in map.get_tilemap_layers():
		var cells: Array[Dictionary] = []
		for cell: Vector2i in layer.get_used_cells():
			var source: TileSetAtlasSource = layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
			var data: TileData = layer.get_cell_tile_data(cell)
			var point: Vector2 = layer.map_to_local(cell)
			var region: Rect2i = source.get_tile_texture_region(layer.get_cell_atlas_coords(cell))
			var entry: Dictionary = {"hex": [cell.x, cell.y], "position": [point.x, point.y], "texture": source.texture.resource_path, "source_id": layer.get_cell_source_id(cell), "atlas": [layer.get_cell_atlas_coords(cell).x, layer.get_cell_atlas_coords(cell).y], "alternative": layer.get_cell_alternative_tile(cell), "flip_h": data.flip_h, "flip_v": data.flip_v}
			if data.has_custom_data("name"):
				entry["kind"] = str(data.get_custom_data("name"))
			if data.has_custom_data("building_id"):
				entry["building_id"] = str(data.get_custom_data("building_id"))
			if data.has_custom_data("art_family"):
				entry["art_family"] = str(data.get_custom_data("art_family"))
			if str(entry.get("art_family", "")).is_empty():
				entry["art_family"] = TerrainPalette.family_for_tile(layer.name, data, source.texture.resource_path)
			if data.texture_origin != Vector2i.ZERO:
				entry["texture_origin"] = [data.texture_origin.x, data.texture_origin.y]
			if data.modulate != Color.WHITE:
				entry["modulate"] = [data.modulate.r, data.modulate.g, data.modulate.b, data.modulate.a]
			if region.position != Vector2i.ZERO or region.size != Vector2i(source.texture.get_size()):
				entry["texture_region"] = [region.position.x, region.position.y, region.size.x, region.size.y]
			cells.append(entry)
		result["layers"].append({"name": str(layer.name), "cells": cells})
	for unit: Unit in scenario.get_units():
		var cell: Vector2i = map.get_ground_layer().local_to_map(unit.position)
		var pieces: PackedStringArray = str(unit.name).split("_")
		var platoon: int = pieces[1].trim_prefix("P").to_int()
		var kind: String = "rifle"
		if str(unit.name).ends_with("CompanyHQ"):
			kind = "company_hq"
		elif str(unit.name).ends_with("PlatoonHQ"):
			kind = "hq"
		elif str(unit.name).ends_with("MG"):
			kind = "mg"
		elif str(unit.name).ends_with("Mortar"):
			kind = "light_mortar"
			if unit.team == Globals.Team.AXIS:
				kind = "medium_mortar"
		var roster: String = "player"
		if unit.team == Globals.Team.AXIS:
			roster = "enemy"
		result[roster].append([platoon, kind, cell.x, cell.y])
	for team: Globals.Team in [Globals.Team.ALLIES, Globals.Team.AXIS]:
		var layer: HexagonTileMapLayer = scenario.get_objectives_layer(team)
		var key: String = "allied_markers"
		if team == Globals.Team.AXIS:
			key = "axis_markers"
		for cell: Vector2i in layer.get_used_cells():
			result[key].append([int(layer.get_cell_tile_data(cell).get_custom_data("objective_id")), cell.x, cell.y])
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
