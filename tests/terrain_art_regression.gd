extends Node

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var layer: HexagonTileMapLayer = HexagonTileMapLayer.new()
	layer.tile_set = TileSet.new()
	layer.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	layer.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	layer.tile_set.tile_size = Vector2i(128, 128)
	add_child(layer)
	_test_woods(layer)
	_test_crops(layer)
	await _test_selection()
	layer.free()
	print("Terrain art checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_woods(layer: HexagonTileMapLayer) -> void:
	var families: Dictionary[Vector2i, String] = {}
	for x: int in range(5):
		for y: int in range(5):
			families[Vector2i(x, y)] = "woods"
	var woods: ConnectedTerrainBaker.TerrainRegion = ConnectedTerrainBaker.render_region(layer, families, "woods")
	var reversed: Dictionary[Vector2i, String] = {}
	var cells: Array[Vector2i] = []
	cells.assign(families.keys())
	cells.reverse()
	for cell: Vector2i in cells:
		reversed[cell] = "woods"
	reversed[Vector2i(8, 8)] = "wheat"
	var cover: ConnectedTerrainBaker.TerrainRegion = ConnectedTerrainBaker.render_region(layer, reversed, "woods")
	_check(woods.origin == cover.origin and woods.image.get_data() == cover.image.get_data(), "Woodland terrain and cover render identical crowns regardless of cell order or other crops")
	var center: Vector2 = layer.map_to_local(Vector2i(2, 2))
	var join: Vector2 = (center + layer.map_to_local(Vector2i(2, 3))) * 0.5
	var joined_pixels: int = 0
	for x: int in range(-25, 26):
		if _alpha(woods, join + Vector2(x, 0)) > 0.1:
			joined_pixels += 1
	_check(joined_pixels > 20, "Whole crowns cross the shared woodland edge without an artificial fringe")
	var differences: int = 0
	for y: int in range(100, 250):
		for x: int in range(100, 180):
			if woods.image.get_pixel(x, y) != woods.image.get_pixel(x + 256, y):
				differences += 1
	_check(differences > 8000, "The canopy does not repeat the old chopped 256-pixel square pattern")
	var island: Dictionary[Vector2i, String] = {Vector2i.ZERO: "woods"}
	var fringe: ConnectedTerrainBaker.TerrainRegion = ConnectedTerrainBaker.render_region(layer, island, "woods")
	var soft_pixels: int = 0
	var solid_pixels: int = 0
	var margin_clear: bool = true
	var natural_edge: bool = false
	var row_ends: Dictionary[int, bool] = {}
	for y: int in range(128):
		var last: int = -1
		for x: int in range(128):
			var alpha: float = fringe.image.get_pixel(x, y).a
			if alpha > 0.1:
				solid_pixels += 1
				last = x
				var local: Vector2 = Vector2(x + 0.5 - 64, y + 0.5 - 64)
				if absf(local.y) > 61.0 or absf(local.x) + absf(local.y) * 0.5 > 61.0:
					margin_clear = false
			if alpha > 0.05 and alpha < 0.95:
				soft_pixels += 1
		if y > 35 and y < 90 and last >= 0:
			row_ends[last] = true
	natural_edge = row_ends.size() > 12
	_check(solid_pixels > 2500 and solid_pixels < 10000, "An isolated woodland tile retains clearings around a substantial canopy")
	_check(margin_clear, "Complete trees end before an exposed hex border")
	_check(soft_pixels > 300 and natural_edge, "Woodland fringes retain soft alpha and varied leafy silhouettes")


func _test_crops(layer: HexagonTileMapLayer) -> void:
	for family: String in ["wheat", "crops"]:
		var families: Dictionary[Vector2i, String] = {}
		for x: int in range(3):
			for y: int in range(3):
				families[Vector2i(x, y)] = family
		var region: ConnectedTerrainBaker.TerrainRegion = ConnectedTerrainBaker.render_region(layer, families, family)
		var center: Vector2 = layer.map_to_local(Vector2i(1, 1))
		var rows: int = 0
		var previous_solid: bool = false
		var clear: int = 0
		var across: Vector2 = Vector2(1, 1).normalized()
		for step: int in range(-50, 51):
			var solid: bool = _alpha(region, center + across * step) > 0.1
			if solid and not previous_solid:
				rows += 1
			if not solid:
				clear += 1
			previous_solid = solid
		_check(rows >= 8 and rows <= 15 and clear >= 25, family + " has many small-scale rows and transparent lanes per hex")


func _test_selection() -> void:
	var ui: UnitUi = load("res://scenes/game/units/presentation/unit_battlefield_view.tscn").instantiate() as UnitUi
	add_child(ui)
	ui.position = Vector2(80, 110)
	ui.select()
	await get_tree().process_frame
	var sprite: TextureRect = ui.sprite_node
	var marker: TextureRect = ui.unit_selected_sprite
	_check(marker.visible and marker.size == Vector2(64, 64) and marker.get_global_rect().get_center().is_equal_approx(sprite.get_global_rect().get_center()), "The selection marker is centered on the unit despite its 128-pixel texture")
	ui.position += Vector2(237, -49)
	ui.scale = Vector2(1.7, 1.7)
	_check(marker.get_global_rect().get_center().is_equal_approx(sprite.get_global_rect().get_center()), "The marker follows the unit under movement and scaling")
	ui.deselect()
	_check(not marker.visible, "Deselecting hides the marker")
	ui.free()


func _alpha(region: ConnectedTerrainBaker.TerrainRegion, world: Vector2) -> float:
	var point: Vector2i = Vector2i(world.floor()) - region.origin
	if point.x < 0 or point.y < 0 or point.x >= region.image.get_width() or point.y >= region.image.get_height():
		return 0.0
	return region.image.get_pixelv(point).a


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
