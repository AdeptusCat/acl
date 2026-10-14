extends Node

const FIXTURE: String = "res://tests/fixtures/alderbrook_buildings_baseline.json"
const BASE_FIXTURE: String = "res://tests/fixtures/base_buildings_baseline.json"

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.world.fully_freed.disconnect(main._on_fully_freed)
	var maps: Array[Map] = []
	var base_maps: Array[Map] = []
	for map: Map in main.world.maps.get_children():
		if map.campaign_name == "Road to Alderbrook" or map.name == &"WesternApproach":
			maps.append(map)
		else:
			base_maps.append(map)
	if OS.get_cmdline_user_args().has("--record-base"):
		var snapshots: Array[Dictionary] = []
		for map: Map in base_maps:
			snapshots.append(_snapshot(map))
		var file: FileAccess = FileAccess.open(BASE_FIXTURE, FileAccess.WRITE)
		file.store_string(JSON.stringify(snapshots, "\t"))
		file.close()
	elif OS.get_cmdline_user_args().has("--record"):
		var snapshots: Array[Dictionary] = []
		for map: Map in maps:
			snapshots.append(_snapshot(map))
		var file: FileAccess = FileAccess.open(FIXTURE, FileAccess.WRITE)
		file.store_string(JSON.stringify(snapshots, "\t"))
		file.close()
	else:
		_test_catalog()
		var snapshots: Array = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)) as Array
		_check(maps.size() == snapshots.size() and maps.size() == 6, "All five campaign maps and the standalone alternative are covered")
		for index: int in range(maps.size()):
			var map: Map = maps[index]
			var actual: Dictionary = JSON.parse_string(JSON.stringify(_snapshot(map))) as Dictionary
			if actual != snapshots[index]:
				print("Changed building layout in ", map.map_name, ": ", JSON.stringify(actual))
			_check(actual == snapshots[index], map.map_name + ": every building retains its position, wood/stone category, cover and design")
			_test_buildings(map)
			_test_los(map)
		var base_snapshots: Array = JSON.parse_string(FileAccess.get_file_as_string(BASE_FIXTURE)) as Array
		_check(base_maps.size() == base_snapshots.size() and base_maps.size() == 2, "Both base-map building layers are covered")
		for index: int in range(base_maps.size()):
			var map: Map = base_maps[index]
			var actual: Dictionary = JSON.parse_string(JSON.stringify(_snapshot(map))) as Dictionary
			_check(actual == base_snapshots[index], "Base-map buildings retain position, wood/stone category, cover and design")
			_test_buildings(map)
			_test_los(map)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Alderbrook building art checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _snapshot(map: Map) -> Dictionary:
	var cells: Array[Dictionary] = []
	var layer: HexagonTileMapLayer = map.get_building_layer()
	var positions: Array[Vector2i] = layer.get_used_cells()
	positions.sort()
	for cell: Vector2i in positions:
		var data: TileData = layer.get_cell_tile_data(cell)
		var kind: String = str(data.get_custom_data("name"))
		if kind not in ["Stone Building", "Wood Building"]:
			continue
		var source: TileSetAtlasSource = layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
		var variant: String = source.texture.resource_path.get_file().get_basename()
		variant = BuildingVariations.ALIASES.get(variant, variant)
		cells.append({"hex": [cell.x, cell.y], "kind": kind, "cover": int(data.get_custom_data("cover")), "variant": variant})
	return {"id": _identity(map), "cells": cells}


func _identity(map: Map) -> String:
	if map.campaign_name == "Road to Alderbrook" or map.name == &"WesternApproach":
		return map.get_scenario(0).scenario_id
	return map.map_name.to_snake_case()


func _test_catalog() -> void:
	var scene: PackedScene = load(BuildingVariations.LAYER_SCENE) as PackedScene
	var first: HexagonTileMapLayer = scene.instantiate() as HexagonTileMapLayer
	var second: HexagonTileMapLayer = scene.instantiate() as HexagonTileMapLayer
	_check(first.tile_set == second.tile_set and first.tile_set.resource_path == BuildingVariations.SHARED_TILE_SET, "New layer instances inherit the same canonical building catalog")
	_check(first.is_in_group("tilemaplayers") and first.tile_set.tile_size == Vector2i(128, 128), "The shared scene supplies its hex configuration and layer group")
	var large: int = -1
	for index: int in range(first.tile_set.get_source_count()):
		var id: int = first.tile_set.get_source_id(index)
		var source: TileSetAtlasSource = first.tile_set.get_source(id) as TileSetAtlasSource
		if not source.texture.resource_path.begins_with(BuildingVariations.DIRECTORY):
			continue
		_check(source.get_tiles_count() == 6 and source.texture.get_size() == Vector2(768, 128), "All catalog designs contain six complete building views")
		if source.resource_name == "Stone Building 03":
			large = id
		var atlas: Image = source.texture.get_image()
		for orientation: int in range(6):
			var image: Image = atlas.get_region(source.get_tile_texture_region(Vector2i(orientation, 0)))
			var clear: bool = true
			for pixel: int in range(128):
				if image.get_pixel(pixel, 0).a > 0.05 or image.get_pixel(pixel, 127).a > 0.05 or image.get_pixel(0, pixel).a > 0.05 or image.get_pixel(127, pixel).a > 0.05:
					clear = false
			_check(clear, "Every catalog view, including Stone Building 03, has unclipped edges")
	_check(large >= 0, "The reusable layer exposes the large stone building")
	first.set_cell(Vector2i.ONE, large, Vector2i(5, 0))
	_check(first.get_cell_tile_data(Vector2i.ONE).get_custom_data("cover") == 3, "Painting Stone Building 03 gives stone cover")
	_check(second.get_used_cells().is_empty(), "Sharing the scene and tileset keeps each scenario's painted cells independent")
	first.free()
	second.free()


func _test_buildings(map: Map) -> void:
	var layer: HexagonTileMapLayer = map.get_building_layer()
	_check(layer.scene_file_path == BuildingVariations.LAYER_SCENE, "Every map instances the reusable building-layer scene")
	var orientations: Dictionary[int, bool] = {}
	var images: Dictionary[Texture2D, Image] = {}
	var available: Dictionary[String, bool] = {}
	for index: int in range(layer.tile_set.get_source_count()):
		var source: TileSetAtlasSource = layer.tile_set.get_source(layer.tile_set.get_source_id(index)) as TileSetAtlasSource
		if source == null or source.texture == null or not source.texture.resource_path.begins_with(BuildingVariations.DIRECTORY):
			continue
		var variant: String = source.texture.resource_path.get_file().get_basename()
		available[variant] = true
		if variant == "building_stone_03":
			_check(source.resource_name == "Stone Building 03", "The large building is listed as Stone Building 03")
			for orientation: int in range(6):
				var data: TileData = source.get_tile_data(Vector2i(orientation, 0), 0)
				_check(data.get_custom_data("name") == "Stone Building" and data.get_custom_data("cover") == 3, "All large-building views provide stone cover")
	for variant: String in ["building_stone_01", "building_stone_02", "building_stone_03", "building_wood_01", "building_wood_02", "building_wood_03"]:
		_check(available.has(variant), "Every building layer includes all six approved building designs")
	for cell: Vector2i in layer.get_used_cells():
		var data: TileData = layer.get_cell_tile_data(cell)
		var kind: String = str(data.get_custom_data("name"))
		if kind not in ["Stone Building", "Wood Building"]:
			continue
		var source: TileSetAtlasSource = layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
		_check(source.texture.resource_path.begins_with(BuildingVariations.DIRECTORY), "Every house uses the approved generated artwork")
		_check(data.material == null, "Approved brown and grey roofs are not remapped by the terrain palette")
		_check(source.get_tiles_count() == 6 and source.texture_region_size == Vector2i(128, 128), "Building atlases provide six matching 128-pixel views")
		var tile: Vector2i = layer.get_cell_atlas_coords(cell)
		_check(tile.y == 0 and tile.x >= 0 and tile.x < 6, "Randomized orientations select valid atlas regions")
		orientations[tile.x] = true
		if not images.has(source.texture):
			images[source.texture] = source.texture.get_image()
		var image: Image = images[source.texture].get_region(source.get_tile_texture_region(tile))
		var clear_edge: bool = true
		for pixel: int in range(128):
			if image.get_pixel(pixel, 0).a > 0.05 or image.get_pixel(pixel, 127).a > 0.05 or image.get_pixel(0, pixel).a > 0.05 or image.get_pixel(127, pixel).a > 0.05:
				clear_edge = false
		_check(clear_edge, "Whole building silhouettes fit inside the tile without clipping")
	if _snapshot(map)["cells"].size() >= 6:
		_check(orientations.size() >= 3, "Larger settlements visibly mix randomized orientations")
	var before: PackedByteArray = layer.tile_map_data
	BuildingVariations.apply(layer, _identity(map))
	_check(layer.tile_map_data == before, "Randomized orientations are stable across regeneration")


func _test_los(map: Map) -> void:
	LOSHelper.ground_layer = map.get_ground_layer()
	LOSHelper.terrain_layer = map.get_terrain_layer()
	LOSHelper.wall_layer = map.get_wall_layer()
	LOSHelper.building_layer = map.get_building_layer()
	var path: String = map.los_resource_path
	if path.is_empty():
		path = "res://resources/los/" + map.map_name.to_snake_case() + ".tres"
	var lookup: LosLookupData = load(path) as LosLookupData
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	for building: Dictionary in _snapshot(map)["cells"]:
		var cell: Vector2i = Vector2i(building["hex"][0], building["hex"][1])
		for neighbor: Vector2i in ground.get_surrounding_cells(cell):
			if ground.get_cell_source_id(neighbor) < 0:
				continue
			var actual: Dictionary = LOSHelper.check_los(ground.map_to_local(neighbor), ground.map_to_local(cell), 1, 0, 1, 0)
			var saved: Dictionary = lookup.los_lookup[neighbor]
			_check(saved.has(cell) == not bool(actual["blocked"]), "Baked sight agrees with the actual rotated building silhouette")
			if saved.has(cell):
				for key: String in ["shooter_cover", "target_cover", "wall_cover", "hindrance", "target_concealment"]:
					_check(saved[cell][key] == actual[key], "Baked sight retains the correct wood/stone and terrain cover")


func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(message)
