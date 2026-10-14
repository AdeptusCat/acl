extends Node

const FAMILIES: Array[String] = ["open_ground", "woods", "orchard", "wheat", "green_crops", "roads", "water", "bridge", "timber", "stone", "hedges", "stubble", "ploughed", "clay_roofs", "slate_roofs", "grid_fog"]

var checks: int = 0
var failures: int = 0
var palettes: Dictionary = {}


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--render"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_run.call_deferred()


func _run() -> void:
	palettes = (JSON.parse_string(FileAccess.get_file_as_string(TerrainPalette.PALETTE_PATH)) as Dictionary)["families"]
	var proposal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/art/palette-proposals/natural-richness.json")) as Dictionary
	for family: Dictionary in proposal["families"]:
		_check(palettes[family["id"]]["colors"] == family["colors"], "Runtime swatches match the approved palette exactly")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	var template: Node = main.world_scene.instantiate()
	var maps: Node = template.get_node("Maps")
	for packed: PackedScene in template.ALDERBROOK_CAMPAIGN.mission_maps:
		maps.add_child(packed.instantiate())
	var originals: Dictionary[String, TileSet] = {}
	for map: Map in maps.get_children():
		for layer: Node in map.get_node("TileMapLayers").get_children():
			if layer is TileMapLayer:
				var tile_layer: TileMapLayer = layer as TileMapLayer
				originals[str(map.name) + "/" + str(layer.name)] = tile_layer.tile_set
	template.free()
	get_tree().root.add_child(main)
	maps = main.world.maps
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var campaign_maps: int = 0
	var used_families: Dictionary[String, bool] = {}
	for map: Map in maps.get_children():
		var campaign: bool = map.campaign_name == TerrainPalette.CAMPAIGN
		if campaign:
			campaign_maps += 1
		for node: Node in map.get_tilemap_layers():
			var layer: TileMapLayer = node as TileMapLayer
			if layer == null or layer.get_used_cells().is_empty():
				continue
			var original: TileSet = originals[str(map.name) + "/" + str(layer.name)]
			_check(layer.tile_set.tile_size == original.tile_size, "Color changes preserve hex spacing")
			var checked: Dictionary[TileData, bool] = {}
			for cell: Vector2i in layer.get_used_cells():
				var data: TileData = layer.get_cell_tile_data(cell)
				if checked.has(data):
					continue
				checked[data] = true
				if not campaign:
					_check(data.material == null, "Campaign palettes do not affect base maps")
					continue
				var source_id: int = layer.get_cell_source_id(cell)
				var source: TileSetAtlasSource = layer.tile_set.get_source(source_id) as TileSetAtlasSource
				var original_source: TileSetAtlasSource = original.get_source(source_id) as TileSetAtlasSource
				var original_data: TileData = original_source.get_tile_data(layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell))
				var family: String = TerrainPalette.family_for_tile(layer.name, data, source.texture.resource_path)
				_check(not family.is_empty(), "Every used campaign tile has a palette")
				if family.is_empty():
					continue
				used_families[family] = true
				_check(data.material == TerrainPalette.material_for_family(family, layer.get_viewport().use_hdr_2d), "Every connected atlas cell has its correct family material")
				_check(data != original_data and original_data.material == null, "Shared TileData remains unchanged")
				_check(source.texture == original_source.texture, "Original texture pixels and LOS alpha are retained")
	_check(campaign_maps == 5 and used_families.size() == 10, "All five maps and all ten used tile families are covered")
	for family: String in FAMILIES:
		var material: ShaderMaterial = TerrainPalette.material_for_family(family)
		var primary: String = family
		if family == "bridge":
			primary = "timber"
		var colors: PackedVector4Array = material.get_shader_parameter("palette")
		_check(colors.size() == 5, "Every material uses all five approved shading stops")
		_check(colors[2] == _vector(Color(str(palettes[primary]["colors"][2]))), "Dominant colors match approved swatches")
	if OS.get_cmdline_user_args().has("--render"):
		for hdr: bool in [false, true]:
			await _test_render(hdr)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Terrain palette checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_render(hdr: bool) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(FAMILIES.size() * 40, 32)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = hdr
	viewport.world_2d = World2D.new()
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var inputs: Array[Image] = []
	for index: int in range(FAMILIES.size()):
		var family: String = FAMILIES[index]
		var primary: String = family
		if family == "bridge":
			primary = "timber"
		var level: float = float(palettes[primary]["levels"][2])
		var samples: Array[Color] = [Color(level, level, level), Color(0.9, 0.12, 0.08), Color(0.9, 0.65, 0.08), Color(0.95, 0.94, 0.92), Color(0.25, 0.45, 0.55)]
		var input: Image = Image.create(40, 32, false, Image.FORMAT_RGBA8)
		for y: int in range(32):
			for x: int in range(40):
				var color: Color = samples[x / 8]
				color.a = float(y) / 31.0
				input.set_pixel(x, y, color)
		inputs.append(input)
		var sprite: Sprite2D = Sprite2D.new()
		sprite.centered = false
		sprite.texture = ImageTexture.create_from_image(input)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(index * 40, 0)
		sprite.material = TerrainPalette.material_for_family(family, hdr)
		viewport.add_child(sprite)
	for frame: int in range(8):
		await get_tree().process_frame
	RenderingServer.force_draw(false)
	var rendered: Image = viewport.get_texture().get_image()
	_check(not rendered.is_empty(), "The GPU renders the approved palette shader")
	if rendered.is_empty():
		viewport.queue_free()
		return
	var alpha_matches: bool = true
	for y: int in range(32):
		for x: int in range(viewport.size.x):
			if absf(rendered.get_pixel(x, y).a - inputs[x / 40].get_pixel(x % 40, y).a) > 0.005:
				alpha_matches = false
	_check(alpha_matches, "Every soft alpha value survives all materials in HDR and SDR")
	for index: int in range(FAMILIES.size()):
		var family: String = FAMILIES[index]
		var primary: String = family
		if family == "bridge":
			primary = "timber"
		var expected: Color = Color(str(palettes[primary]["colors"][2]))
		var actual: Color = _display_color(rendered, Vector2i(index * 40 + 4, 31), hdr)
		_check(_difference(actual, expected) < 0.025, "GPU dominant swatch matches approved " + family + " color, HDR=" + str(hdr))
	var orchard: int = FAMILIES.find("orchard") * 40
	var fruit: Color = _display_color(rendered, Vector2i(orchard + 12, 31), hdr)
	var pear: Color = _display_color(rendered, Vector2i(orchard + 20, 31), hdr)
	var flower: Color = _display_color(rendered, Vector2i(orchard + 28, 31), hdr)
	_check(fruit.r > fruit.g * 1.5 and fruit.r > fruit.b, "Existing apples remain red")
	_check(pear.r > pear.g and pear.g > pear.b * 1.5, "Existing pears remain amber")
	_check(_difference(flower, Color("#F3DDD0")) < 0.025, "Blossoms use the approved accent")
	var bridge: Color = _display_color(rendered, Vector2i(FAMILIES.find("bridge") * 40 + 36, 31), hdr)
	var water: Color = _display_color(rendered, Vector2i(FAMILIES.find("water") * 40 + 36, 31), hdr)
	_check(_difference(bridge, water) < 0.01, "River pixels in bridges match adjacent water")
	viewport.queue_free()
	await get_tree().process_frame


func _display_color(image: Image, point: Vector2i, hdr: bool) -> Color:
	var color: Color = image.get_pixelv(point)
	if hdr:
		return color.linear_to_srgb()
	return color


func _vector(color: Color) -> Vector4:
	return Vector4(color.r, color.g, color.b, color.a)


func _difference(first: Color, second: Color) -> float:
	return Vector3(first.r - second.r, first.g - second.g, first.b - second.b).length()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
