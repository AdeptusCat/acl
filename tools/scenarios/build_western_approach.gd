extends "res://tools/campaigns/build_alderbrook_campaign.gd"

# Reuse campaign authoring helpers; this builder writes only standalone assets.
const APPROACH_ID: String = "alderbrook_western_approach"
const APPROACH_SCENE: String = "res://scenes/scenarios/standalone/alderbrook_western_approach.tscn"
const APPROACH_RESOURCES: String = "res://resources/scenarios/"
const APPROACH_DOCS: String = "res://docs/scenarios/western_approach/"
const APPROACH_SIZE: Vector2i = Vector2i(28, 18)
const APPROACH_ROUTES: Array[Array] = [
	[Vector3(-1, 8.5, 0), Vector3(5, 8.0, -0.1), Vector3(11, 8.2, 0.12), Vector3(16, 8.1, 0), Vector3(22, 8.1, 0), Vector3(28, 8.1, 0)],
	[Vector3(-1, 4.3, 0), Vector3(5, 4.0, -0.1), Vector3(9, 2.3, 0), Vector3(15, 2.2, 0), Vector3(20, 3.1, 0), Vector3(28, 3.1, 0)],
	[Vector3(-1, 12.8, 0), Vector3(5, 12.6, 0.08), Vector3(10, 14.5, 0.1), Vector3(15, 14.7, -0.05), Vector3(20, 13.2, 0), Vector3(28, 13.1, 0)],
	# Diagonal streets link the approaches before and inside the town.
	[Vector3(9, 2.3, 0.7), Vector3(12, 5.2, 0.8), Vector3(16, 8.1, 0.8), Vector3(20, 13.2, 1.0)],
	[Vector3(20, 3.1, 0.9), Vector3(23, 8.1, 1.0), Vector3(26, 13.1, 0.9)],
]
const APPROACH_PLAYER: Array[Array] = [
	[1, "hq", 2, 3], [1, "rifle", 3, 2], [1, "rifle", 3, 3], [1, "rifle", 3, 5], [1, "mg", 2, 5],
	[2, "hq", 2, 8], [2, "rifle", 3, 7], [2, "rifle", 3, 8], [2, "rifle", 3, 9], [2, "mg", 2, 10],
	[3, "hq", 2, 13], [3, "rifle", 3, 12], [3, "rifle", 3, 13], [3, "rifle", 3, 14], [3, "mg", 2, 15],
	[0, "company_hq", 1, 8], [0, "light_mortar", 1, 10],
]
const APPROACH_ENEMY: Array[Array] = [
	[1, "hq", 17, 5], [1, "rifle", 13, 4], [1, "rifle", 15, 6], [1, "mg", 15, 4],
	[2, "hq", 24, 9], [2, "rifle", 20, 9], [2, "rifle", 22, 7], [2, "mg", 18, 8],
	[3, "hq", 21, 15], [3, "rifle", 16, 14], [3, "rifle", 18, 12], [3, "mg", 18, 14],
	[0, "company_hq", 25, 11], [0, "medium_mortar", 25, 6],
]
const APPROACH_MARKERS: Array[Array] = [[1, 13, 4], [2, 20, 9], [3, 16, 14]]
const APPROACH_BRIEFING: String = "Standalone alternative to Battle for Alderbrook.\n\nYour company has reached the western outskirts. Fields give way to an orchard estate, roadside houses and workshop yards, then tight town blocks. There is no river barrier: move between the approaches and choose where to commit your reserve.\n\n[b]North - Orchard estate (A):[/b] the orchard conceals the approach but hinders fire. Clear its edge and use the estate to turn the market defense.\n[b]Center - Market square (B):[/b] the main road is fast and exposed. Cover the approach from the roadside houses, or enter the square from a flank.\n[b]South - Workshop yard (C):[/b] scattered timber sheds provide stepping stones into town. Take the yard, then use the diagonal street to support the market assault.\n\nThree rifle platoons each have a machine-gun team. Company HQ and a light mortar support the attack. Keep one platoon available until you identify the weaker approach. Enemy infantry and machine guns defend the outskirts, with mortar support deeper in town.\n\n[b]Major Victory:[/b] hold A, B and C simultaneously, each for 30 uninterrupted seconds. This ends the battle immediately.\n[b]Minor Victory:[/b] hold B for 30 uninterrupted seconds at the 15-minute deadline.\n\nObjectives require a unit in good order; enemy presence contests control. There are no destruction or exit quotas. The defenders win by holding all three districts at the deadline, or earn a minor victory by holding B."

var approach_layout: Dictionary = {}
var approach_stone_sources: Array[int] = []
var approach_timber_sources: Array[int] = []


func _run() -> void:
	approach_layout = _roads.layout_for_routes(APPROACH_ROUTES, APPROACH_SIZE)
	if OS.get_cmdline_user_args().has("--roads-only"):
		_roads.write_assets(APPROACH_ID, approach_layout)
		get_tree().quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(APPROACH_SCENE.get_base_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(APPROACH_RESOURCES))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(APPROACH_DOCS))
	# Unit authoring expects the same audio service path as a normal match.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.name = "Main"
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.world.fully_freed.disconnect(main._on_fully_freed)
	var map: Map
	if OS.get_cmdline_user_args().has("--los-only"):
		map = load(APPROACH_SCENE).instantiate() as Map
		add_child(map)
	else:
		map = _create_approach()
		ConnectedTerrainBaker.bake(map.get_terrain_layer(), APPROACH_ID + "_terrain")
		ConnectedTerrainBaker.bake(map.get_building_layer(), APPROACH_ID + "_woods")
		assert(ResourceSaver.save(map.get_terrain_layer().tile_set, APPROACH_RESOURCES + APPROACH_ID + "_terrain.tres") == OK)
		assert(ResourceSaver.save(map.get_building_layer().tile_set, APPROACH_RESOURCES + APPROACH_ID + "_buildings.tres") == OK)
		map.get_terrain_layer().tile_set.take_over_path(APPROACH_RESOURCES + APPROACH_ID + "_terrain.tres")
		map.get_building_layer().tile_set.take_over_path(APPROACH_RESOURCES + APPROACH_ID + "_buildings.tres")
		map.use_terrain_palette = true
		var packed: PackedScene = PackedScene.new()
		assert(packed.pack(map) == OK)
		assert(ResourceSaver.save(packed, APPROACH_SCENE) == OK)
		_export_layout(map, {})
	if not OS.get_cmdline_user_args().has("--skip-los"):
		await _bake_los(map)
	map.queue_free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Built standalone Alderbrook: The Western Approach.")
	get_tree().quit()


func _create_approach() -> Map:
	var map: Map = load("res://scenes/campaigns/alderbrook/05_battle_for_alderbrook.tscn").instantiate() as Map
	map.name = "WesternApproach"
	map.map_name = "Alderbrook Western Approach"
	map.campaign_name = ""
	map.grid_size = APPROACH_SIZE
	map.los_resource_path = "res://resources/los/" + APPROACH_ID + ".res"
	add_child(map)
	map.process_mode = Node.PROCESS_MODE_DISABLED
	for layer: HexagonTileMapLayer in map.get_tilemap_layers():
		layer.clear()
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	ground.tile_set = ground.tile_set.duplicate(true) as TileSet
	var terrain: HexagonTileMapLayer = map.get_terrain_layer()
	var buildings: HexagonTileMapLayer = map.get_building_layer()
	_terrain_set = terrain.tile_set.duplicate(true) as TileSet
	_building_set = buildings.tile_set.duplicate(true) as TileSet
	_prune_generated_sources(_terrain_set)
	_prune_generated_sources(_building_set)
	terrain.tile_set = _terrain_set
	buildings.tile_set = _building_set
	_woods_sources = _sources_for_images(_terrain_set, WOODS_IMAGES)
	_wood_building_sources = _sources_for_images(_building_set, WOODS_IMAGES)
	_orchard_sources = _sources_for_images(_terrain_set, ORCHARD_IMAGES)
	_wheat_sources = _sources_for_images(_terrain_set, WHEAT_IMAGES)
	_crop_sources = _sources_for_images(_terrain_set, CROP_IMAGES)
	for kind: String in ["Stone Building", "Wood Building"]:
		_building_sources[kind] = _source_for(_building_set, kind)
	approach_stone_sources = _sources_for_images(_building_set, ["res://assets/tiles/buildings/building_stone_01.png", "res://assets/tiles/buildings/building_stone_02.png"])
	approach_timber_sources = _sources_for_images(_building_set, ["res://assets/tiles/buildings/building_wood_01.png", "res://assets/tiles/buildings/building_wood_02.png", "res://assets/tiles/buildings/building_wood_03.png"])
	var ground_sources: Array[int] = _sources_for_images(ground.tile_set, OPEN_GROUND_IMAGES)
	_grass_noise.seed = 18731
	_grass_noise.frequency = 0.12
	for x: int in range(APPROACH_SIZE.x):
		for y: int in range(APPROACH_SIZE.y):
			var cell: Vector2i = Vector2i(x, y)
			var variant: int = clampi(floori((_grass_noise.get_noise_2d(x, y) + 1.0) * 1.5), 0, 2)
			ground.set_cell(cell, ground_sources[variant], Vector2i.ZERO)
	# Broken woodland edges screen deployment without dividing the battlefield.
	for plot: Rect2i in [Rect2i(0, 0, 8, 2), Rect2i(0, 16, 12, 2), Rect2i(5, 6, 3, 2), Rect2i(8, 10, 2, 3)]:
		for x: int in range(plot.position.x, plot.end.x):
			for y: int in range(plot.position.y, plot.end.y):
				if posmod(x + y * 2, 5) != 0:
					_woods(terrain, buildings, Vector2i(x, y), 0)
	_plant_plot(ground, terrain, buildings, Rect2i(1, 3, 5, 4), _wheat_sources[1])
	_plant_plot(ground, terrain, buildings, Rect2i(4, 9, 4, 5), _crop_sources[0])
	_plant_plot(ground, terrain, buildings, Rect2i(9, 0, 5, 2), _crop_sources[2])
	_plant_plot(ground, terrain, buildings, Rect2i(6, 2, 8, 4), _orchard_sources[1])
	_plant_plot(ground, terrain, buildings, Rect2i(11, 11, 3, 4), _wheat_sources[2])
	_paint_approach_roads(terrain, buildings)
	# Sparse farm/outskirts buildings become irregular, denser town blocks.
	for cell: Vector2i in [Vector2i(7, 9), Vector2i(10, 7), Vector2i(11, 6), Vector2i(13, 9), Vector2i(14, 10), Vector2i(15, 7), Vector2i(13, 4), Vector2i(14, 4), Vector2i(15, 4), Vector2i(15, 6), Vector2i(17, 5)]:
		var stone: bool = cell.y == 4 and cell.x >= 13 and cell.x <= 15
		_place_approach_house(terrain, buildings, cell, stone)
	for cell: Vector2i in [Vector2i(5, 12), Vector2i(10, 12), Vector2i(12, 13), Vector2i(14, 12), Vector2i(16, 14), Vector2i(17, 14), Vector2i(18, 14), Vector2i(18, 12)]:
		_place_approach_house(terrain, buildings, cell, false)
	for x: int in range(17, 28):
		for y: int in range(1, 17):
			var cell: Vector2i = Vector2i(x, y)
			if posmod(x * 2 + y, 5) <= 2 and not (y == 9 and x >= 19 and x <= 21):
				# Keep occasional stone landmarks among predominantly timber houses.
				var stone: bool = posmod(x + y * 2, 5) == 0
				_place_approach_house(terrain, buildings, cell, stone)
	var walls: HexagonTileMapLayer = map.get_wall_layer()
	var hedge_source: int = _sources_for_images(walls.tile_set, ["res://assets/tiles/walls/hedge_nw.png"])[0]
	for cell: Vector2i in [Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5), Vector2i(10, 6)]:
		if not approach_layout["cells"].has(cell):
			walls.set_cell(cell, hedge_source, Vector2i.ZERO)
	# Objective B is the open market; the other two objectives have building cover.
	terrain.erase_cell(Vector2i(20, 9))
	buildings.erase_cell(Vector2i(20, 9))
	var scenario: Scenario = map.get_scenario(0)
	for unit: Node in scenario.get_units():
		unit.free()
	scenario.scenario_name = "Alderbrook: The Western Approach"
	scenario.scenario_id = APPROACH_ID
	scenario.campaign_id = ""
	scenario.campaign_mission = 0
	scenario.previous_scenario = null
	scenario.scenario_description = APPROACH_BRIEFING
	scenario.duration_s = 900.0
	scenario.use_authored_duration = true
	scenario.released = true
	scenario.player_team = Globals.Team.ALLIES
	scenario.axis_ai_status = Scenario.AIStatus.ON
	scenario.axis_ai_mode = Scenario.AIMode.DEFEND
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	scenario.ai_fallback_policies = []
	scenario.victory_conditions = _approach_conditions()
	_add_units(scenario, map, ground, APPROACH_PLAYER, Globals.Team.ALLIES)
	_add_units(scenario, map, ground, APPROACH_ENEMY, Globals.Team.AXIS)
	var allied: Array[Array] = APPROACH_MARKERS.duplicate(true)
	allied.append([4, 2, 8])
	var axis: Array[Array] = APPROACH_MARKERS.duplicate(true)
	axis.append([4, 24, 9])
	_set_markers(scenario.get_objectives_layer(Globals.Team.ALLIES), allied, true)
	_set_markers(scenario.get_objectives_layer(Globals.Team.AXIS), axis, false)
	# Process disabling is only for generation, never stored in the playable scene.
	map.process_mode = Node.PROCESS_MODE_INHERIT
	return map


func _prune_generated_sources(tiles: TileSet) -> void:
	var remove: Array[int] = []
	for index: int in range(tiles.get_source_count()):
		var id: int = tiles.get_source_id(index)
		var source: TileSetSource = tiles.get_source(id)
		if source.resource_name.begins_with("Connected terrain") or source.resource_name.begins_with("Road -"):
			remove.append(id)
	for id: int in remove:
		tiles.remove_source(id)


func _plant_plot(ground: HexagonTileMapLayer, terrain: HexagonTileMapLayer, buildings: HexagonTileMapLayer, plot: Rect2i, source: int) -> void:
	for x: int in range(plot.position.x, plot.end.x):
		for y: int in range(plot.position.y, plot.end.y):
			var cell: Vector2i = Vector2i(x, y)
			if _can_plant(ground, terrain, buildings, cell):
				terrain.set_cell(cell, source, Vector2i.ZERO)


func _paint_approach_roads(terrain: HexagonTileMapLayer, buildings: HexagonTileMapLayer) -> void:
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.resource_name = "Road - Western Approach"
	source.texture = load(AlderbrookRoads.ASSET_DIRECTORY + "road_" + APPROACH_ID + ".svg") as Texture2D
	assert(source.texture != null, "Generate and import standalone roads before building the scenario")
	source.texture_region_size = Vector2i(128, 128)
	var id: int = terrain.tile_set.add_source(source)
	for cell: Vector2i in approach_layout["cells"]:
		var tile: Vector2i = approach_layout["cells"][cell]
		source.create_tile(tile)
		source.get_tile_data(tile, 0).set_custom_data("name", "Road")
		terrain.set_cell(cell, id, tile)
		buildings.erase_cell(cell)


func _place_approach_house(terrain: HexagonTileMapLayer, buildings: HexagonTileMapLayer, cell: Vector2i, stone: bool) -> void:
	if not approach_layout["cells"].has(cell):
		_house(buildings, terrain, cell, stone)
		var sources: Array[int] = approach_timber_sources
		if stone:
			sources = approach_stone_sources
		buildings.set_cell(cell, sources[posmod(cell.x + cell.y, sources.size())], Vector2i.ZERO)


func _approach_conditions() -> Array[VictoryCondition]:
	var conditions: Array[VictoryCondition] = []
	for team: Globals.Team in [Globals.Team.ALLIES, Globals.Team.AXIS]:
		var deadline: bool = team == Globals.Team.AXIS
		for id: OccupyObjectiveCondition.ObjectiveId in [OccupyObjectiveCondition.ObjectiveId.A, OccupyObjectiveCondition.ObjectiveId.B, OccupyObjectiveCondition.ObjectiveId.C]:
			conditions.append(_occupy(team, id, 30.0, true, deadline))
		conditions.append(_occupy(team, OccupyObjectiveCondition.ObjectiveId.B, 30.0, false, true))
	return conditions


func _export_layout(map: Map, _spec: Dictionary) -> void:
	var layers: Array[Dictionary] = []
	for layer: HexagonTileMapLayer in map.get_tilemap_layers():
		var cells: Array[Dictionary] = []
		for cell: Vector2i in layer.get_used_cells():
			var source: TileSetAtlasSource = layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
			var position: Vector2 = layer.map_to_local(cell)
			var tile: TileData = layer.get_cell_tile_data(cell)
			var region: Rect2i = source.get_tile_texture_region(layer.get_cell_atlas_coords(cell))
			var data: Dictionary = {"hex": [cell.x, cell.y], "position": [position.x, position.y], "texture": source.texture.resource_path, "flip_h": tile.flip_h, "flip_v": tile.flip_v, "texture_region": [region.position.x, region.position.y, region.size.x, region.size.y]}
			if tile.has_custom_data("art_family"):
				data["art_family"] = str(tile.get_custom_data("art_family"))
			cells.append(data)
		layers.append({"name": str(layer.name), "cells": cells})
	var data: Dictionary = {"series": "STANDALONE SCENARIO", "title": map.get_scenario(0).scenario_name, "id": APPROACH_ID, "size": [APPROACH_SIZE.x, APPROACH_SIZE.y], "seconds": 900.0, "force_summary": "Company: 3 platoons + MGs + light mortar", "goal": "Hold orchard estate A, market B and workshop yard C for 30 seconds together.", "player": APPROACH_PLAYER, "enemy": APPROACH_ENEMY, "allied_markers": APPROACH_MARKERS, "axis_markers": APPROACH_MARKERS, "layers": layers}
	var file: FileAccess = FileAccess.open(APPROACH_DOCS + APPROACH_ID + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
