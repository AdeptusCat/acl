extends Node

var checks: int = 0
var failures: int = 0
var artwork: Dictionary[Texture2D, Image] = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var walls: WallTileMapLayer = load(ConnectedWalls.LAYER_SCENE).instantiate() as WallTileMapLayer
	add_child(walls)
	var empty_layers: Array[HexagonTileMapLayer] = []
	for index: int in range(3):
		var layer: HexagonTileMapLayer = HexagonTileMapLayer.new()
		layer.tile_set = walls.tile_set
		add_child(layer)
		empty_layers.append(layer)
	LOSHelper.ground_layer = empty_layers[0]
	LOSHelper.building_layer = empty_layers[1]
	LOSHelper.terrain_layer = empty_layers[2]
	LOSHelper.wall_layer = walls
	_test_catalog(walls)
	for kind: int in range(2):
		for cell: Vector2i in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(-4, -4), Vector2i(-5, -4)]:
			for side: int in range(6):
				_test_edge(walls, kind, cell, side)
	_test_editing(walls)
	_test_cache(walls, empty_layers)
	LOSHelper.unload_map()
	walls.free()
	for layer: HexagonTileMapLayer in empty_layers:
		layer.free()
	print("Connected hex-edge wall checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_catalog(walls: WallTileMapLayer) -> void:
	_check(walls.tile_set.tile_size == Vector2i(128, 128), "Art padding leaves the logical hex grid unchanged")
	_check(walls.tile_set.get_source_count() == 12, "The catalog retains ten legacy sources and two edge atlases")
	_check(walls.tile_set.get_terrain_sets_count() == 0, "Hex-edge barriers expose no center-linking terrain brush")
	for kind: int in range(2):
		var source: TileSetAtlasSource = walls.tile_set.get_source(ConnectedWalls.source_for(walls.tile_set, kind)) as TileSetAtlasSource
		_check(source.texture_region_size == ConnectedWalls.ART_REGION_SIZE, "Padded sprites expose the complete barrier on both sides of the spine")
		_check(source.get_tiles_count() == 63 and not source.has_tile(Vector2i.ZERO), "Each style includes every nonempty combination of six hex sides")
		for mask: int in range(1, 64):
			var atlas: Vector2i = ConnectedWalls.atlas_coords(mask)
			var data: TileData = source.get_tile_data(atlas, 0)
			_check(ConnectedWalls.is_barrier(data) and ConnectedWalls.edge_mask(data) == mask, "Every glyph's directional flags match its visible edges")
			_check(data.get_custom_data("name") == ConnectedWalls.LABELS[kind] and int(data.get_custom_data("cover")) == 2 - kind, "Stone supplies defense 2 and hedges defense 1")
			_check(data.terrain_set == -1, "No piece occupies the hex interior as a terrain")
			walls.clear()
			walls.paint_edges([Vector2i(4, 4)], kind, mask)
			var center: Vector2 = walls.map_to_local(Vector2i(4, 4))
			_check(not LOSHelper._tile_pixel_is_solid(center, walls, Vector2i(4, 4)), "The center of every wall and hedge tile remains completely open")
			for side: int in range(6):
				var midpoint: Vector2 = center + (ConnectedWalls.VERTICES[side] + ConnectedWalls.VERTICES[(side + 1) % 6]) * 0.5
				var point: Vector2 = midpoint + (center - midpoint).normalized() * 2.0
				_check(LOSHelper._tile_pixel_is_solid(point, walls, Vector2i(4, 4)) == bool(mask & (1 << side)), "Only the selected hex edges contain barrier pixels")
	var copy: TileSet = walls.tile_set.duplicate(true) as TileSet
	ConnectedWalls.install(copy)
	ConnectedWalls.install(copy)
	_check(copy.get_source_count() == 12 and copy.get_terrain_sets_count() == 0, "Reinstallation preserves source IDs and the edge-only catalog")
	var legacy: TileSet = load("res://resources/campaigns/alderbrook_walls.tres") as TileSet
	for id: int in range(10):
		var before: TileSetAtlasSource = legacy.get_source(id) as TileSetAtlasSource
		var after: TileSetAtlasSource = walls.tile_set.get_source(id) as TileSetAtlasSource
		for index: int in range(before.get_alternative_tiles_count(Vector2i.ZERO)):
			var alternative: int = before.get_alternative_tile_id(Vector2i.ZERO, index)
			for field: int in range(8):
				_check(before.get_tile_data(Vector2i.ZERO, alternative).get_custom_data_by_layer_id(field) == after.get_tile_data(Vector2i.ZERO, alternative).get_custom_data_by_layer_id(field), "Legacy directional cover remains exact")


func _test_edge(walls: WallTileMapLayer, kind: int, cell: Vector2i, side: int) -> void:
	walls.clear()
	walls.paint_edges([cell], kind, 1 << side)
	var neighbor: Vector2i = walls.get_neighbor_cell(cell, ConnectedWalls.SIDES[side])
	_test_spine_art(walls, kind, cell, neighbor, side)
	var center: Vector2 = walls.map_to_local(cell)
	var incoming: Dictionary = LOSHelper.check_los(walls.map_to_local(neighbor), center, 1, 0, 1, 0)
	var outgoing: Dictionary = LOSHelper.check_los(center, walls.map_to_local(neighbor), 1, 0, 1, 0)
	_check(not incoming["blocked"] and int(incoming["target_cover"]) == 2 - kind, "An edge provides directional target cover on both material types")
	_check(not outgoing["blocked"] and int(outgoing["shooter_cover"]) == 2 - kind, "The same edge provides shooter cover from the opposite side")
	for open_side: int in range(6):
		if open_side == side:
			continue
		var open_neighbor: Vector2i = walls.get_neighbor_cell(cell, ConnectedWalls.SIDES[open_side])
		var open: Dictionary = LOSHelper.check_los(center, walls.map_to_local(open_neighbor), 1, 0, 1, 0)
		_check(not open["blocked"] and int(open["shooter_cover"]) == 0, "Unpainted sides remain open and provide no phantom cover")
	var origin: Vector2i = walls.get_neighbor_cell(cell, ConnectedWalls.SIDES[(side + 3) % 6])
	var target: Vector2i = walls.get_neighbor_cell(neighbor, ConnectedWalls.SIDES[side])
	var blocked: Dictionary = LOSHelper.check_los(walls.map_to_local(origin), walls.map_to_local(target), 1, 0, 1, 0)
	_check(blocked["blocked"], "An intermediate painted edge blocks a crossing ray in every grid orientation")
	walls.edit_edge(cell, side, kind, true)
	_check(walls.get_cell_source_id(cell) == -1, "Erasing the last edge removes its tile")
	_check(not LOSHelper.check_los(walls.map_to_local(origin), walls.map_to_local(target), 1, 0, 1, 0)["blocked"], "Erasing an edge creates a real LOS opening")


func _test_spine_art(walls: WallTileMapLayer, kind: int, cell: Vector2i, neighbor: Vector2i, side: int) -> void:
	var start: Vector2 = walls.map_to_local(cell) + ConnectedWalls.VERTICES[side]
	var end: Vector2 = walls.map_to_local(cell) + ConnectedWalls.VERTICES[(side + 1) % 6]
	var direction: Vector2 = end - start
	var normal: Vector2 = Vector2(direction.y, -direction.x).normalized()
	var points: Array[Vector2] = []
	var colors: Array[Color] = []
	for fraction: float in [0.2, 0.5, 0.8]:
		for distance: float in [-2.0, 0.0, 2.0]:
			var point: Vector2 = start.lerp(end, fraction) + normal * distance
			var color: Color = _art_pixel(walls, cell, point)
			_check(color.a > 0.1, "The visible strip covers the spine and both neighboring hexes")
			points.append(point)
			colors.append(color)
	walls.erase_cell(cell)
	walls.paint_edges([neighbor], kind, 1 << ((side + 3) % 6))
	for index: int in range(points.size()):
		_check(_art_pixel(walls, neighbor, points[index]).is_equal_approx(colors[index]), "Changing the owning hex cannot change the barrier's position, material phase or cross-section")
	walls.erase_cell(neighbor)
	walls.paint_edges([cell], kind, 1 << side)


func _art_pixel(walls: WallTileMapLayer, cell: Vector2i, point: Vector2) -> Color:
	# Inspect the drawn sprite, including padding outside the owner's hex.
	var source: TileSetAtlasSource = walls.tile_set.get_source(walls.get_cell_source_id(cell)) as TileSetAtlasSource
	if not artwork.has(source.texture):
		artwork[source.texture] = source.texture.get_image()
	var region: Rect2i = source.get_tile_texture_region(walls.get_cell_atlas_coords(cell))
	var origin: Vector2i = walls.get_cell_tile_data(cell).texture_origin
	var pixel: Vector2i = Vector2i((point - walls.map_to_local(cell) + Vector2(origin) + Vector2(region.size) * 0.5).floor())
	return artwork[source.texture].get_pixelv(region.position + pixel)


func _test_editing(walls: WallTileMapLayer) -> void:
	walls.clear()
	var cell: Vector2i = Vector2i(5, 4)
	walls.edit_edge(cell, 0, 0)
	walls.edit_edge(cell, 1, 0)
	_check(walls.get_edge_mask(cell) == 3 and walls.get_used_cells().size() == 1, "Drawing a second side selects a joined corner without creating center segments")
	walls.edit_edge(cell, 0, 0, true)
	_check(walls.get_edge_mask(cell) == 2, "The edge eraser retains the other sides of the tile")
	walls.edit_edge(cell, 2, 1)
	_check(walls.get_edge_mask(cell) == 6 and walls.get_cell_tile_data(cell).get_custom_data("name") == "Hedge", "Changing material keeps the selected edge footprint")
	var before: PackedByteArray = walls.tile_map_data
	var saved: PackedScene = PackedScene.new()
	_check(saved.pack(walls) == OK, "An edge layout saves as an ordinary tilemap")
	var restored: WallTileMapLayer = saved.instantiate() as WallTileMapLayer
	add_child(restored)
	_check(restored.tile_map_data == before, "Save/load preserves edge combinations without neighbor-based rewriting")
	restored.free()
	TerrainPalette.apply(walls)
	_check(walls.get_cell_tile_data(cell).material != null, "The edge artwork retains the approved hedge palette")
	walls.clear()
	walls.set_cell(cell, 3, Vector2i.ZERO, 0)
	var legacy: PackedByteArray = walls.tile_map_data
	walls.edit_edge(cell, 0, 1, true)
	_check(walls.tile_map_data == legacy, "Erasing an absent legacy side leaves the original tile unchanged")
	_check(walls.get_edge_mask(cell) == 16, "The brush recognizes older hedge sides even when their original metadata is missing")
	walls.edit_edge(cell, 0, 1)
	_check(walls.get_edge_mask(cell) == 17, "Editing an old hedge preserves its visible original side")
	walls.set_cell(cell, 0, Vector2i.ZERO, 0)
	var signature: String = walls.los_layout_signature()
	walls.edit_edge(cell, 3, 0, true)
	_check(signature != "" and walls.los_layout_signature() == "", "Editing legacy edges also invalidates cached sight")


func _test_cache(walls: WallTileMapLayer, empty_layers: Array[HexagonTileMapLayer]) -> void:
	walls.clear()
	var map: Map = Map.new()
	map.map_name = "Hex Edge Barrier Regression"
	map.grid_size = Vector2i(6, 6)
	map.los_resource_path = "user://hex_edge_walls_los.tres"
	var layers: Node2D = Node2D.new()
	layers.name = "TileMapLayers"
	map.add_child(layers)
	var scenarios: Node2D = Node2D.new()
	scenarios.name = "Scenarios"
	map.add_child(scenarios)
	walls.reparent(layers)
	var names: Array[String] = ["GroundTileMapLayer", "BuildingTileMapLayer", "TerrainTileMapLayer"]
	for index: int in range(3):
		empty_layers[index].name = names[index]
		empty_layers[index].reparent(layers)
	add_child(map)
	var stale: LosLookupData = LosLookupData.new()
	stale.los_lookup = {}
	_check(ResourceSaver.save(stale, map.los_resource_path) == OK, "The stale-cache fixture saves")
	walls.paint_edges([Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)], 0, 6)
	LOSHelper.load_prebaked_los(map)
	_check(LOSHelper.los_lookup.size() == 36, "Changed edge layouts rebuild the full gameplay lookup")
	var fresh: LosLookupData = load(map.los_resource_path) as LosLookupData
	_check(fresh.wall_layout_signature == walls.los_layout_signature(), "Saved visibility records the actual hex-edge layout")
	for origin: Vector2i in LOSHelper.los_lookup:
		for x: int in range(6):
			for y: int in range(6):
				var target: Vector2i = Vector2i(x, y)
				if target == origin:
					continue
				var result: Dictionary = LOSHelper.check_los(walls.map_to_local(origin), walls.map_to_local(target), 1, 0, 1, 0)
				var row: Dictionary = LOSHelper.los_lookup[origin]
				_check(row.has(target) == not bool(result["blocked"]), "Cached visibility agrees with directional edge blocking on every board pair")
				if row.has(target):
					_check(row[target]["target_cover"] == result["target_cover"] and row[target]["shooter_cover"] == result["shooter_cover"], "Cached defense agrees with the visible sides and their materials")
	walls.clear()
	LOSHelper.load_prebaked_los(map)
	_check(LOSHelper.wall_layout_signature() == "" and LOSHelper.los_lookup[Vector2i.ZERO].size() == 35, "Removing the edges clears stale blockers")
	walls.reparent(self)
	for layer: HexagonTileMapLayer in empty_layers:
		layer.reparent(self)
	map.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://hex_edge_walls_los.tres"))


func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(message)
