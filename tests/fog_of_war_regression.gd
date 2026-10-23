extends Node

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--render"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_run.call_deferred()


func _run() -> void:
	_test_mask_updates()
	if OS.get_cmdline_user_args().has("--render"):
		for hdr: bool in [false, true]:
			for tile_size: int in [64, 128]:
				await _test_render(tile_size, hdr)
	print("Fog of war checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _ground(tile_size: int, parent: Node) -> HexagonTileMapLayer:
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	ground.tile_set.tile_size = Vector2i(tile_size, tile_size)
	parent.add_child(ground)
	return ground


func _cells(size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(size.x):
		for y: int in range(size.y):
			cells.append(Vector2i(x, y))
	return cells


func _test_mask_updates() -> void:
	var ground: HexagonTileMapLayer = _ground(128, self)
	var fog: FogOfWarOverlay = FogOfWarOverlay.new()
	add_child(fog)
	var cells: Array[Vector2i] = _cells(Vector2i(6, 5))
	cells.erase(Vector2i(2, 2))
	fog.configure(ground, Vector2i(6, 5), cells)
	# The headless Dummy renderer does not retain ImageTexture.update uploads.
	# Inspect CPU state here; the GPU cases below check the uploaded texture.
	var image: Image = fog._mask_image
	_check(image.get_size() == Vector2i(6, 5), "Visibility needs only one mask pixel per hex")
	_check(image.get_pixel(1, 1).r == 1.0 and image.get_pixel(1, 1).g == 1.0, "New maps begin obscured")
	_check(image.get_pixel(2, 2).r == 0.0, "Map holes do not acquire fog")
	fog.update_visibility([Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 1), Vector2i(99, 99)])
	image = fog._mask_image
	_check(image.get_pixel(1, 1).g == 0.0 and image.get_pixel(2, 1).g == 0.0 and image.get_pixel(0, 0).g == 1.0, "Only current LOS cells clear")
	var revision: int = fog.mask_revision
	fog.update_visibility([Vector2i(2, 1), Vector2i(1, 1)])
	_check(fog.mask_revision == revision, "Unchanged visibility avoids texture uploads regardless of cell order")
	fog.update_visibility([Vector2i(2, 1)])
	image = fog._mask_image
	_check(image.get_pixel(1, 1).g == 1.0 and image.get_pixel(2, 1).g == 0.0, "Losing LOS immediately restores fog without explored-map memory")
	fog.configure(ground, Vector2i(3, 3), _cells(Vector2i(3, 3)))
	image = fog._mask_image
	_check(image.get_size() == Vector2i(3, 3) and image.get_pixel(2, 1).g == 1.0, "Replacement maps reset mask dimensions and visibility")
	var colors: Array = TerrainPalette.PALETTE.data["families"]["grid_fog"]["colors"]
	var shadow: Color = Color(str(colors[2]))
	_check(fog.fog_material.get_shader_parameter("shadow_color") == Vector4(shadow.r, shadow.g, shadow.b, shadow.a), "Fog uses the approved palette")
	fog.configure(ground, Vector2i.ZERO, [])
	_check(fog.mask_texture == null and fog.material == null, "An empty map releases its fog mask and material")
	fog.free()
	ground.free()


func _test_render(tile_size: int, hdr: bool) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = hdr
	viewport.world_2d = World2D.new()
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var ground: HexagonTileMapLayer = _ground(tile_size, viewport)
	var cells: Array[Vector2i] = _cells(Vector2i(4, 3))
	var hole: Vector2i = Vector2i(3, 2)
	cells.erase(hole)
	var fog: FogOfWarOverlay = FogOfWarOverlay.new()
	viewport.add_child(fog)
	fog.configure(ground, Vector2i(4, 3), cells)
	var linear_output: bool = hdr and RenderingServer.get_rendering_device() != null
	_check(fog.fog_material.get_shader_parameter("hdr_2d") == linear_output, "Fog color conversion matches the active renderer")
	var clear_cell: Vector2i = Vector2i(1, 1)
	fog.update_visibility([clear_cell])
	fog.fog_material.set_shader_parameter("time_override", 0.0)
	var noise: NoiseTexture2D = fog.fog_material.get_shader_parameter("cloud_noise") as NoiseTexture2D
	for frame: int in range(120):
		if noise.get_image() != null:
			break
		await get_tree().process_frame
	var first: Image = await _snapshot(viewport)
	_check(not first.is_empty(), "The GPU renders fog at " + str(tile_size) + " pixels, HDR=" + str(hdr))
	for cell: Vector2i in cells:
		var point: Vector2i = Vector2i(ground.map_to_local(cell))
		var alpha: float = first.get_pixelv(point).a
		if cell == clear_cell:
			_check(alpha < 0.005, "Visible hex centers stay completely clear")
		else:
			_check(alpha > 0.50 and alpha <= 0.77, "Every obscured hex retains bounded mist density")
	_check(first.get_pixelv(Vector2i(ground.map_to_local(hole))).a < 0.005, "Fog stays off holes in the map")
	var seam: Vector2 = ground.map_to_local(Vector2i(0, 0)) + Vector2(0.0, tile_size * 0.5)
	var before: float = first.get_pixelv(Vector2i(seam - Vector2(0.0, 2.0))).a
	var after: float = first.get_pixelv(Vector2i(seam + Vector2(0.0, 2.0))).a
	_check(before > 0.5 and after > 0.5 and absf(before - after) < 0.025, "Adjacent obscured tiles join without faded seams")
	var boundary: Vector2 = ground.map_to_local(clear_cell) + Vector2(0.0, tile_size * 0.5)
	var fringe: float = first.get_pixelv(Vector2i(boundary + Vector2(0.0, 3.0))).a
	var interior: float = first.get_pixelv(Vector2i(boundary + Vector2(0.0, 24.0))).a
	_check(fringe > 0.001 and fringe < interior * 0.3, "Mist feathers smoothly outside the visible region")
	fog.fog_material.set_shader_parameter("time_override", 20.0)
	var later: Image = await _snapshot(viewport)
	var motion: float = 0.0
	for cell: Vector2i in cells:
		var point: Vector2i = Vector2i(ground.map_to_local(cell))
		motion += _difference(first.get_pixelv(point), later.get_pixelv(point))
	_check(motion > 0.04, "Clouds change with time while visibility stays fixed")
	_check(later.get_pixelv(Vector2i(ground.map_to_local(clear_cell))).a < 0.005, "Animated wisps never enter a visible hex center")
	fog.fog_material.set_shader_parameter("time_override", 0.0)
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(256.0, 256.0)
	viewport.add_child(camera)
	var centered: Image = await _snapshot(viewport)
	var pan: Vector2i = Vector2i(23, 17)
	camera.position += Vector2(pan)
	camera.force_update_scroll()
	var panned: Image = await _snapshot(viewport)
	var anchor: Vector2i = Vector2i(ground.map_to_local(Vector2i(2, 1)))
	_check(_difference(centered.get_pixelv(anchor), panned.get_pixelv(anchor - pan)) < 0.01, "Camera panning preserves the fog at the same world point")
	camera.zoom = Vector2(1.25, 1.25)
	camera.force_update_scroll()
	var zoomed: Image = await _snapshot(viewport)
	var zoomed_point: Vector2i = Vector2i(viewport.get_canvas_transform() * Vector2(anchor))
	_check(_difference(centered.get_pixelv(anchor), zoomed.get_pixelv(zoomed_point)) < 0.025, "Camera zoom preserves the world scale of clouds")
	camera.queue_free()
	await get_tree().process_frame
	fog.update_visibility(cells)
	var clear: Image = await _snapshot(viewport)
	var remaining: float = 0.0
	for cell: Vector2i in cells:
		remaining += clear.get_pixelv(Vector2i(ground.map_to_local(cell))).a
	_check(remaining < 0.005, "Revealing the board removes fog from every hex center")
	fog.update_visibility([])
	var hidden: Image = await _snapshot(viewport)
	_check(hidden.get_pixelv(Vector2i(ground.map_to_local(clear_cell))).a > 0.50, "Lost visibility becomes obscured on the next render")
	viewport.queue_free()
	await get_tree().process_frame


func _snapshot(viewport: SubViewport) -> Image:
	for frame: int in range(5):
		await get_tree().process_frame
	RenderingServer.force_draw(false)
	return viewport.get_texture().get_image()


func _difference(first: Color, second: Color) -> float:
	return Vector4(first.r - second.r, first.g - second.g, first.b - second.b, first.a - second.a).length()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
