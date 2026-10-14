extends Node

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for size: int in [64, 128]:
		_test_size(size)
	LOSHelper.unload_map()
	print("Pixel terrain LOS regression failures: ", failures)
	get_tree().quit(failures)


func _test_size(size: int) -> void:
	var ground: HexagonTileMapLayer = _layer(size, false)
	var terrain: HexagonTileMapLayer = _layer(size, false)
	var buildings: HexagonTileMapLayer = _layer(size, true)
	var walls: HexagonTileMapLayer = _layer(size, false)
	LOSHelper.ground_layer = ground
	LOSHelper.terrain_layer = terrain
	LOSHelper.building_layer = buildings
	LOSHelper.wall_layer = walls
	var cell: Vector2i = Vector2i(2, 3)
	var image: Image = Image.create(size * 2, size, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(size + size / 2, size / 4, size / 4, size / 2), Color.WHITE)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(size, size)
	source.create_tile(Vector2i.ZERO)
	source.create_tile(Vector2i(1, 0))
	var id: int = terrain.tile_set.add_source(source)
	var data: TileData = source.get_tile_data(Vector2i(1, 0), 0)
	data.set_custom_data("hindrance", true)
	data.set_custom_data("blocking", false)
	terrain.set_cell(cell, id, Vector2i(1, 0))
	var origin: Vector2 = ground.map_to_local(Vector2i(2, 1))
	var target: Vector2 = ground.map_to_local(Vector2i(2, 5))
	var shift: Vector2 = Vector2(size * 0.125, 0.0)
	var result: Dictionary = LOSHelper.check_los(origin + shift, target + shift, 1, 0, 1, 0)
	_check(not result.blocked and result.hindrance == 1, "Field pixels hinder the ray once at size " + str(size))
	result = LOSHelper.check_los(origin - shift, target - shift, 1, 0, 1, 0)
	_check(not result.blocked and result.hindrance == 0, "Transparent crop lanes do not hinder LOS at size " + str(size))
	_test_hindrance_crossings(size, terrain, source, id, origin, target, shift)
	data.set_custom_data("blocking", true)
	result = LOSHelper.check_los(origin + shift, target + shift, 1, 0, 1, 0)
	_check(result.blocked and result.block_point != ground.map_to_local(cell), "Woods block at the tree image entry at size " + str(size))
	result = LOSHelper.check_los(origin - shift, target - shift, 1, 0, 1, 0)
	_check(not result.blocked, "A transparent woodland gap preserves LOS at size " + str(size))
	source.create_alternative_tile(Vector2i(1, 0), 1)
	var flipped: TileData = source.get_tile_data(Vector2i(1, 0), 1)
	flipped.flip_h = true
	flipped.set_custom_data("hindrance", true)
	flipped.set_custom_data("blocking", true)
	terrain.set_cell(cell, id, Vector2i(1, 0), 1)
	_check(LOSHelper.check_los(origin - shift, target - shift, 1, 0, 1, 0).blocked, "Flipped woodland pixels match their display at size " + str(size))
	_check(not LOSHelper.check_los(origin + shift, target + shift, 1, 0, 1, 0).blocked, "Flipped clear gaps stay clear at size " + str(size))
	flipped.set_custom_data("blocking", false)
	_check(LOSHelper.get_hindrance_crossings(origin - shift, target - shift).size() == 1, "Flipped hindrance markers follow visible pixels at size " + str(size))
	_check(LOSHelper.get_hindrance_crossings(origin + shift, target + shift).is_empty(), "Flipped transparent margins add no marker at size " + str(size))
	flipped.set_custom_data("blocking", true)
	terrain.clear()
	var building_source: TileSetAtlasSource = source.duplicate(true) as TileSetAtlasSource
	var building_id: int = buildings.tile_set.add_source(building_source)
	buildings.set_cell(cell, building_id, Vector2i(1, 0))
	_check(LOSHelper.check_los(origin + shift, target + shift, 1, 0, 1, 0).blocked, "Building atlas regions block correctly at size " + str(size))
	_check(not LOSHelper.check_los(origin - shift, target - shift, 1, 0, 1, 0).blocked, "Transparent building margins stay clear at size " + str(size))
	# Rays on a hex spine inspect real pixels on both adjacent tiles.
	buildings.clear()
	terrain.set_cell(cell, id, Vector2i(1, 0))
	var spine_target: Vector2 = ground.map_to_local(Vector2i(4, 4))
	var spine_origin: Vector2 = ground.map_to_local(Vector2i(0, 2))
	var expected_hit: bool = LOSHelper._sprite_entry(spine_origin, spine_target, terrain, cell) != Vector2.INF
	_check(LOSHelper.check_los(spine_origin, spine_target, 1, 0, 1, 0).blocked == expected_hit, "Hex-spine LOS follows sprite alpha at size " + str(size))
	data.set_custom_data("blocking", false)
	_check((LOSHelper.get_hindrance_crossings(spine_origin, spine_target).size() == 1) == expected_hit, "Hex-spine hindrance markers inspect both adjacent tiles at size " + str(size))
	LOSHelper.unload_map()
	for layer: HexagonTileMapLayer in [ground, terrain, buildings, walls]:
		layer.free()


func _test_hindrance_crossings(size: int, terrain: HexagonTileMapLayer, source: TileSetAtlasSource, id: int, origin: Vector2, target: Vector2, shift: Vector2) -> void:
	var start: Vector2 = origin + shift
	var finish: Vector2 = target + shift
	var cell: Vector2i = Vector2i(2, 3)
	var entries: PackedVector2Array = LOSHelper.get_hindrance_crossings(start, finish)
	_check(entries.size() == 1 and entries[0].is_equal_approx(LOSHelper._sprite_entry(start, finish, terrain, cell)), "Hindrance marker starts at the actual image entry at size " + str(size))
	_check(LOSHelper.get_hindrance_crossings(origin - shift, target - shift).is_empty(), "Transparent margins add no hindrance marker at size " + str(size))
	# Connected fields accumulate once per hex, including when the ray is reversed.
	for row: int in range(1, 6):
		terrain.set_cell(Vector2i(2, row), id, Vector2i(1, 0))
	entries = LOSHelper.get_hindrance_crossings(start, finish)
	_check(entries.size() == 3, "Connected fields exclude shooter and target hexes at size " + str(size))
	_check(entries.size() == LOSHelper.check_los(start, finish, 1, 0, 1, 0).hindrance, "Preview crossings match the gameplay hindrance count at size " + str(size))
	if entries.size() == 3:
		for index: int in range(3):
			var expected: Vector2 = LOSHelper._sprite_entry(start, finish, terrain, Vector2i(2, index + 2))
			_check(entries[index].is_equal_approx(expected), "Crossings are ordered from shooter to target at size " + str(size))
	entries = LOSHelper.get_hindrance_crossings(finish, start)
	if entries.size() == 3:
		for index: int in range(3):
			var expected: Vector2 = LOSHelper._sprite_entry(finish, start, terrain, Vector2i(2, 4 - index))
			_check(entries[index].is_equal_approx(expected), "Reversing LOS reverses hindrance entry order at size " + str(size))
	else:
		_check(false, "Reverse LOS retains all hindrances at size " + str(size))
	var middle_entry: Vector2 = LOSHelper._sprite_entry(start, finish, terrain, cell)
	entries = LOSHelper.get_hindrance_crossings(start, finish, middle_entry)
	_check(entries.size() == 1, "Hindrance markers stop before a blocking image at size " + str(size))
	var data: TileData = source.get_tile_data(Vector2i(1, 0), 0)
	data.set_custom_data("blocking", true)
	_check(LOSHelper.get_hindrance_crossings(start, finish).is_empty(), "Blocking woods use the obstruction marker at size " + str(size))
	data.set_custom_data("blocking", false)
	_check(LOSHelper.get_hindrance_crossings(start, start).is_empty(), "Same-hex LOS adds no hindrance marker at size " + str(size))
	terrain.clear()
	terrain.set_cell(cell, id, Vector2i(1, 0))


func _layer(size: int, _building: bool) -> HexagonTileMapLayer:
	var layer: HexagonTileMapLayer = HexagonTileMapLayer.new()
	layer.tile_set = TileSet.new()
	layer.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	layer.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	layer.tile_set.tile_size = Vector2i(size, size)
	for label: String in ["hindrance", "blocking", "cover"]:
		var index: int = layer.tile_set.get_custom_data_layers_count()
		layer.tile_set.add_custom_data_layer()
		layer.tile_set.set_custom_data_layer_name(index, label)
		var type: int = TYPE_BOOL
		if label == "cover":
			type = TYPE_INT
		layer.tile_set.set_custom_data_layer_type(index, type)
	add_child(layer)
	return layer


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
