extends "res://tests/three_hex_landmarks_regression.gd"

const PERSPECTIVE_MANIFEST: String = "res://docs/art/three_hex_landmarks/perspective/export.json"


func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PERSPECTIVE_MANIFEST)) as Dictionary
	var designs: Array = manifest["buildings"]
	var layer: BuildingTileMapLayer = load(BuildingVariations.LAYER_SCENE).instantiate() as BuildingTileMapLayer
	layer.tile_set = layer.tile_set.duplicate(true) as TileSet
	# Test the preview pack in memory without replacing the shared editor palette.
	for index: int in range(layer.tile_set.get_patterns_count() - 1, -1, -1):
		if layer.tile_set.get_pattern(index).has_meta("multihex_building"):
			layer.tile_set.remove_pattern(index)
	for design: Dictionary in designs:
		var source_id: int = MultihexBuildings._install_design(layer.tile_set, design)
		for orientation: int in range(6):
			var pattern: TileMapPattern = TileMapPattern.new()
			var view: Dictionary = design["views"][orientation]
			for part: int in range(3):
				var cell: Array = view["parts"][part]["cell"]
				pattern.set_cell(Vector2i(cell[0], cell[1]), source_id, Vector2i(orientation, part), 0)
			pattern.set_meta("multihex_building", design["id"])
			pattern.set_meta("angle", orientation * 60)
			layer.tile_set.add_pattern(pattern)
	add_child(layer)
	LOSHelper.building_layer = layer
	_check(designs.size() == 6, "Six reference buildings have perspective variants")
	for design: Dictionary in designs:
		_check(design["orientation_method"] == "independently generated world orientations under a fixed camera", "Alternate views originate in independent generated artwork")
		for orientation: int in range(6):
			super._test_view(layer, design, orientation)
			_test_hex_centers(layer, design, orientation)
	LOSHelper.unload_map()
	layer.free()
	print("Landmark perspective checks: ", checks, "; visible pixels checked: ", checked_pixels, "; failures: ", failures)
	get_tree().quit(failures)


func _test_hex_centers(layer: BuildingTileMapLayer, design: Dictionary, orientation: int) -> void:
	for origin: Vector2i in ORIGINS:
		layer.clear()
		layer.place_multihex_building(origin, design["id"], orientation)
		var anchor: Vector2i
		for cell: Vector2i in layer.get_used_cells():
			if layer.get_cell_atlas_coords(cell).y == 0:
				anchor = cell
		var source: TileSetAtlasSource = layer.tile_set.get_source(layer.get_cell_source_id(anchor)) as TileSetAtlasSource
		var atlas: Image = source.texture.get_image()
		var region: Rect2i = source.get_tile_texture_region(Vector2i(orientation, 0))
		var roof: Image = atlas.get_region(region)
		var data: TileData = layer.get_cell_tile_data(anchor)
		var top_left: Vector2 = layer.map_to_local(anchor) - Vector2(data.texture_origin) - Vector2(region.size) * 0.5
		for cell: Vector2i in layer.get_used_cells():
			var center_pixel: Vector2i = Vector2i(layer.map_to_local(cell) - top_left)
			var fragment_region: Rect2i = source.get_tile_texture_region(layer.get_cell_atlas_coords(cell))
			for offset: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var pixel: Vector2i = center_pixel + offset
				var inside: bool = Rect2i(Vector2i.ZERO, roof.get_size()).has_point(pixel)
				_check(inside, "Every hex center is inside the atlas canvas")
				if not inside:
					continue
				_check(roof.get_pixelv(pixel).a >= 128.0 / 255.0, "Visible building artwork covers every exact hex center: " + str(design["id"]) + " / " + str(orientation * 60))
				_check(atlas.get_pixelv(fragment_region.position + pixel).a == roof.get_pixelv(pixel).a, "The LOS fragment contains the same visible center pixels")
