extends "res://tests/three_hex_landmarks_regression.gd"

const PERSPECTIVE_MANIFEST: String = "res://docs/art/three_hex_landmarks/perspective/export.json"


func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PERSPECTIVE_MANIFEST)) as Dictionary
	var designs: Array = manifest["buildings"]
	var layer: BuildingTileMapLayer = load(BuildingVariations.LAYER_SCENE).instantiate() as BuildingTileMapLayer
	add_child(layer)
	LOSHelper.building_layer = layer
	_check(designs.size() == 6, "Six reference buildings have perspective variants")
	for design: Dictionary in designs:
		_check(design["orientation_method"] == "independently generated world orientations under a fixed camera", "Alternate views originate in independent generated artwork")
		for orientation: int in range(6):
			var pattern: TileMapPattern = MultihexBuildings.pattern_for(layer.tile_set, design["id"], orientation)
			_check(pattern != null, "The shared building layer includes every corrected orientation")
			if pattern == null:
				continue
			var source_id: int = pattern.get_cell_source_id(pattern.get_used_cells()[0])
			var source: TileSetAtlasSource = layer.tile_set.get_source(source_id) as TileSetAtlasSource
			_check(source.texture.resource_path == design["texture"], "The shared layer paints the corrected artwork directly")
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
