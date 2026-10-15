extends Node

var checks: int = 0
var failures: int = 0
var _images: Dictionary[Texture2D, Image] = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var layer: BuildingTileMapLayer = load(BuildingVariations.LAYER_SCENE).instantiate() as BuildingTileMapLayer
	add_child(layer)
	var designs: Array = MultihexBuildings.catalog()
	_check(designs.size() == 30, "The original designs, ASL pack and six three-hex landmarks are available")
	_check(layer.tile_set.get_patterns_count() == 180, "The shared building layer exposes 180 complete rotated patterns")
	var parents: Dictionary[String, Array] = {}
	var asl_counts: Dictionary[String, Array] = {"wood": [], "stone": []}
	var landmark_counts: Dictionary[String, Array] = {"wood": [], "stone": []}
	for design: Dictionary in designs:
		_test_design(layer, design)
		if design.get("pack", "") == "three_hex_landmarks":
			landmark_counts[design["material"]].append(int(design["hexes"]))
			continue
		if design.get("pack", "") == "asl_inspired":
			asl_counts[design["material"]].append(int(design["hexes"]))
			continue
		var parent: String = design["parent"]
		if not parents.has(parent):
			parents[parent] = []
		parents[parent].append(int(design["hexes"]))
	_check(parents.size() == 6, "Wood 01-03 and Stone 01-03 all receive multihex buildings")
	for parent: String in parents:
		parents[parent].sort()
		_check(parents[parent] == [2, 2, 3], "Every parent has two two-hex designs and one three-hex design")
	for material: String in asl_counts:
		asl_counts[material].sort()
		_check(asl_counts[material] == [2, 2, 3], "Each ASL material has two two-hex designs and one three-hex design")
	for material: String in landmark_counts:
		_check(landmark_counts[material] == [3, 3, 3], "Each landmark material has three three-hex designs")
	var copy: TileSet = layer.tile_set.duplicate(true) as TileSet
	var count: int = copy.get_source_count()
	MultihexBuildings.install(copy)
	MultihexBuildings.install(copy)
	_check(copy.get_source_count() == count and copy.get_patterns_count() == 180, "Reinstalling retains source IDs and never duplicates patterns")
	LOSHelper.unload_map()
	layer.free()
	print("Multihex building checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_design(layer: BuildingTileMapLayer, design: Dictionary) -> void:
	var cover: int = 3
	var kind: String = "Stone Building"
	if design["material"] == "wood":
		cover = 2
		kind = "Wood Building"
	for orientation: int in range(6):
		var pattern: TileMapPattern = MultihexBuildings.pattern_for(layer.tile_set, design["id"], orientation)
		_check(pattern != null and pattern.get_used_cells().size() == int(design["hexes"]), "Every rotation paints the complete requested footprint")
		for anchor: Vector2i in [Vector2i(4, 4), Vector2i(5, 4)]:
			layer.clear()
			layer.place_multihex_building(anchor, design["id"], orientation)
			_check(layer.get_used_cells().size() == int(design["hexes"]), "Patterns occupy exactly two or three hexes on even and odd columns")
			if design.get("footprint", "") == "triangle":
				for member: Vector2i in layer.get_used_cells():
					for other: Vector2i in layer.get_used_cells():
						if other != member:
							_check(layer.get_surrounding_cells(member).has(other), "Compact ASL wings occupy three mutually adjacent hexes at every angle")
			var center: Vector2 = Vector2.INF
			for cell: Vector2i in layer.get_used_cells():
				var data: TileData = layer.get_cell_tile_data(cell)
				_check(data.get_custom_data("name") == kind and data.get_custom_data("cover") == cover, "Every occupied hex has its correct material and cover")
				_check(data.get_custom_data("building_id") == design["id"] and data.get_custom_data("building_angle") == orientation * 60, "Fragments retain a common building design and angle")
				_check(data.get_custom_data("building_hexes") == int(design["hexes"]), "Every fragment records the full building footprint")
				var opacity: float = 0.0
				if int(data.get_custom_data("building_part")) == 0:
					opacity = 1.0
				_check(data.modulate.a == opacity, "The complete roof is drawn once to prevent filtering seams")
				var actual_center: Vector2 = layer.map_to_local(cell) - Vector2(data.texture_origin)
				if center == Vector2.INF:
					center = actual_center
				_check(actual_center == center, "Texture origins align every fragment into one continuous building")
				var point: Vector2 = _visible_point(layer, cell)
				_check(point != Vector2.INF and LOSHelper._tile_pixel_is_solid(point, layer, cell), "Every occupied hex contains visible roof pixels and correct cover sampling")
				if point == Vector2.INF:
					continue
				_check(LOSHelper._sprite_entry(point - Vector2(400, 0), point + Vector2(400, 0), layer, cell) != Vector2.INF, "Each fragment blocks rays at its visible roof pixels")
				var corner: Vector2 = center + Vector2(float(design["region_size"]) * 0.5 - 1.0, 0)
				_check(not LOSHelper._tile_pixel_is_solid(corner, layer, cell), "Clear sprite margins add no invisible obstacles")
				_check(data.material == null, "The approved brown and grey roof colors remain intact")
			var before: PackedByteArray = layer.tile_map_data
			BuildingVariations.apply(layer, "multihex regression")
			_check(layer.tile_map_data == before, "Single-house randomization leaves complete multihex orientations intact")
		TerrainPalette.apply(layer)
		for cell: Vector2i in layer.get_used_cells():
			_check(layer.get_cell_tile_data(cell).material == null, "Campaign palettes preserve multihex roof colors")


func _visible_point(layer: BuildingTileMapLayer, cell: Vector2i) -> Vector2:
	var source: TileSetAtlasSource = layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
	if not _images.has(source.texture):
		_images[source.texture] = source.texture.get_image()
	var image: Image = _images[source.texture]
	var region: Rect2i = source.get_tile_texture_region(layer.get_cell_atlas_coords(cell))
	var data: TileData = layer.get_cell_tile_data(cell)
	var origin: Vector2 = layer.map_to_local(cell) - Vector2(data.texture_origin) - Vector2(region.size) * 0.5
	for y: int in range(4, region.size.y, 8):
		for x: int in range(4, region.size.x, 8):
			var point: Vector2 = origin + Vector2(x + 0.5, y + 0.5)
			if image.get_pixelv(region.position + Vector2i(x, y)).a > 0.95 and layer.local_to_map(point) == cell:
				return point
	return Vector2.INF


func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(message)
