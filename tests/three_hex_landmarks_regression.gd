extends Node

const MANIFEST: String = "res://docs/art/three_hex_landmarks/export.json"
const ORIGINS: Array[Vector2i] = [Vector2i(4, 4), Vector2i(5, 4), Vector2i(-4, -4), Vector2i(-5, -4)]
const CORNERS: Array[Vector2] = [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]

var checks: int = 0
var failures: int = 0
var checked_pixels: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary
	var designs: Array = manifest["buildings"]
	var layer: BuildingTileMapLayer = load(BuildingVariations.LAYER_SCENE).instantiate() as BuildingTileMapLayer
	add_child(layer)
	LOSHelper.building_layer = layer
	_check(designs.size() == 6, "The landmark pack contains six designs")
	var materials: Dictionary[String, int] = {"wood": 0, "stone": 0}
	var factories: int = 0
	var churches: int = 0
	for design: Dictionary in designs:
		materials[design["material"]] += 1
		var id: String = design["id"]
		if id.contains("factory"):
			factories += 1
		if id.contains("church"):
			churches += 1
		_check(int(design["hexes"]) == 3 and bool(design["strict_footprint"]), "Every new landmark declares a strict three-hex footprint")
		for orientation: int in range(6):
			_test_view(layer, design, orientation)
	_check(materials["wood"] == 3 and materials["stone"] == 3, "Three wood and three stone buildings are available")
	_check(factories == 2 and churches == 1, "The set includes two factories and one church")
	LOSHelper.unload_map()
	layer.free()
	print("Three-hex landmark checks: ", checks, "; visible pixels checked: ", checked_pixels, "; failures: ", failures)
	get_tree().quit(failures)


func _test_view(layer: BuildingTileMapLayer, design: Dictionary, orientation: int) -> void:
	var pattern: TileMapPattern = MultihexBuildings.pattern_for(layer.tile_set, design["id"], orientation)
	_check(pattern != null and pattern.get_used_cells().size() == 3, "Each orientation exposes exactly three occupied hexes")
	if pattern == null:
		return
	var source_id: int = pattern.get_cell_source_id(pattern.get_used_cells()[0])
	var source: TileSetAtlasSource = layer.tile_set.get_source(source_id) as TileSetAtlasSource
	var atlas: Image = source.texture.get_image()
	var region: Rect2i = source.get_tile_texture_region(Vector2i(orientation, 0))
	var roof: Image = atlas.get_region(region)
	var pixels: Array[Vector2i] = []
	var edges: Array[Vector2i] = []
	for y: int in range(roof.get_height()):
		for x: int in range(roof.get_width()):
			if roof.get_pixel(x, y).a == 0.0:
				continue
			var pixel: Vector2i = Vector2i(x, y)
			pixels.append(pixel)
			if x == 0 or y == 0 or x == roof.get_width() - 1 or y == roof.get_height() - 1:
				edges.append(pixel)
			elif roof.get_pixel(x - 1, y).a == 0.0 or roof.get_pixel(x + 1, y).a == 0.0 or roof.get_pixel(x, y - 1).a == 0.0 or roof.get_pixel(x, y + 1).a == 0.0:
				edges.append(pixel)
	for origin: Vector2i in ORIGINS:
		layer.clear()
		layer.place_multihex_building(origin, design["id"], orientation)
		var occupied: Array[Vector2i] = layer.get_used_cells()
		_check(occupied.size() == 3, "Placement fills exactly three cells on even, odd and negative columns")
		var anchor: Vector2i
		var areas: Dictionary[Vector2i, int] = {}
		for cell: Vector2i in occupied:
			areas[cell] = 0
			if layer.get_cell_atlas_coords(cell).y == 0:
				anchor = cell
		var data: TileData = layer.get_cell_tile_data(anchor)
		var top_left: Vector2 = layer.map_to_local(anchor) - Vector2(data.texture_origin) - Vector2(region.size) * 0.5
		var outside: int = 0
		var mismatched_fragments: int = 0
		for pixel: Vector2i in pixels:
			var point: Vector2 = top_left + Vector2(pixel) + Vector2(0.5, 0.5)
			var cell: Vector2i = layer.local_to_map(point)
			if not areas.has(cell):
				outside += 1
				continue
			areas[cell] += 1
			var tile: Vector2i = layer.get_cell_atlas_coords(cell)
			var fragment_region: Rect2i = source.get_tile_texture_region(tile)
			if atlas.get_pixelv(fragment_region.position + pixel).a != roof.get_pixelv(pixel).a:
				mismatched_fragments += 1
		checked_pixels += pixels.size()
		_check(outside == 0, "Every nontransparent pixel lies in the three declared Godot hexes: " + str(design["id"]) + " / " + str(orientation))
		_check(mismatched_fragments == 0, "Every roof pixel has matching LOS pixels in its actual occupied hex")
		var outside_corners: int = 0
		for pixel: Vector2i in edges:
			var point: Vector2 = top_left + Vector2(pixel) + Vector2(0.5, 0.5)
			for corner: Vector2 in CORNERS:
				if not areas.has(layer.local_to_map(point + corner)):
					outside_corners += 1
		_check(outside_corners == 0, "Antialiased edge pixels stay wholly inside the footprint")
		var cover: int = 3
		if design["material"] == "wood":
			cover = 2
		for cell: Vector2i in occupied:
			_check(areas[cell] >= 512, "Every declared hex contains substantial visible building area")
			_check(LOSHelper.is_sample_point_in_building(layer.map_to_local(cell)) == cover, "Every member supplies the correct wood or stone defense")
			_check(layer.get_building_cells(cell).size() == 3, "Every member identifies the complete three-hex building")


func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(message)
