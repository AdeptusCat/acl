extends Node

# Run this scene headlessly for logic checks; add -- --render with a display for HDR previews.
const Effects: Script = preload("res://scenes/game/effects/battlefield_effects.gd")
const Tracer: Script = preload("res://scenes/game/effects/tracer.gd")
const TRACER_SCENE: PackedScene = preload("res://scenes/game/effects/tracer.tscn")

class ImpactAudio extends AudioPool:
	var hits: int = 0
	var hit_position: Vector2 = Vector2.ZERO

	func play_one_shot(_stream: AudioStream, point: Vector2, _volume: float = 0.0, _pitch: float = 1.0, _bus: String = "") -> void:
		hits += 1
		hit_position = point


class ViewProbe extends UnitUi:
	var endpoint: Vector2 = Vector2.ZERO

	func shoot(_from: Vector2, to: Vector2, _weapon: WeaponSpec) -> void:
		endpoint = to


var failures: int = 0
var checks: int = 0
var arrivals: int = 0
var audio: ImpactAudio


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--render"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_run.call_deferred()


func _run() -> void:
	var world: Node = Node.new()
	world.name = "World"
	add_child(world)
	audio = ImpactAudio.new()
	audio.name = "AudioPool"
	world.add_child(audio)
	_test_flight()
	_test_pool_and_frequency()
	await _test_map_integration()
	if OS.get_cmdline_user_args().has("--render"):
		await _render_preview()
	print("Projectile effects checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_flight() -> void:
	var weapon: WeaponSpec = WeaponSpec.new()
	weapon.riflegrenade_hit = AudioStreamWAV.new()
	var tracer: Tracer = TRACER_SCENE.instantiate() as Tracer
	add_child(tracer)
	tracer.arrived.connect(func() -> void: arrivals += 1)
	for fps: int in [30, 60, 144]:
		for degrees: float in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]:
			var start: Vector2 = Vector2(33.0, 57.0)
			var target: Vector2 = start + Vector2.from_angle(deg_to_rad(degrees)) * 240.0
			tracer.launch(start, target, weapon, Tracer.Kind.BULLET, Tracer.Surface.GROUND, true)
			_check(tracer.head == start, "Every angle starts at the exact muzzle")
			for frame: int in range(ceili(0.2 * float(fps)) + 1):
				tracer.advance(1.0 / float(fps))
				_check(tracer.head.distance_to(start) <= 240.01, "No frame overshoots the destination")
				_check(absf((tracer.head - start).cross(target - start)) < 0.1, "Movement follows the firing direction")
			_check(tracer.has_arrived and tracer.head == target, "Arrival is frame-rate independent at all six angles")
			_check(tracer.trail_start().distance_to(tracer.head) > 1.0, "A fast shot retains a visible swept trail")
			tracer.advance(1.0)
			_check(not tracer.active, "Completed effects stop processing")
	_check(arrivals == 18, "Each shot arrives exactly once")
	var end: Vector2 = Vector2(240.0, 0.0)
	tracer.launch(Vector2.ZERO, end, weapon, Tracer.Kind.GRENADE, Tracer.Surface.STONE, true)
	tracer.advance(0.2)
	_check(not tracer.has_arrived and audio.hits == 0, "Grenades do not explode at bullet arrival time")
	tracer.advance(0.4)
	_check(tracer.has_arrived and audio.hits == 1 and audio.hit_position == end, "Grenade impact and sound share the exact arrival point")
	tracer.advance(0.1)
	_check(audio.hits == 1, "Impact sound is never repeated by later frames")
	tracer.launch(end, end, weapon, Tracer.Kind.BULLET, Tracer.Surface.GROUND, true)
	tracer.advance(0.0)
	_check(tracer.has_arrived and tracer.head == end, "Same-hex shots resolve without division by zero")
	tracer.advance(1.0)
	_check(not tracer.active, "Same-hex effects also finish")
	tracer.launch(Vector2.ZERO, end, weapon, Tracer.Kind.BULLET, Tracer.Surface.GROUND, false)
	tracer.advance(0.21)
	_check(tracer.has_arrived, "Unlit bullets keep their muzzle and impact timing")
	tracer.free()


func _test_pool_and_frequency() -> void:
	var effects: Effects = Effects.new()
	add_child(effects)
	var weapon: WeaponSpec = WeaponSpec.new()
	for type: WeaponSpec.WeaponType in [WeaponSpec.WeaponType.Rifle, WeaponSpec.WeaponType.MG, WeaponSpec.WeaponType.SMG]:
		weapon.type = type
		var visible: int = 0
		for shot: int in range(12):
			var tracer: Tracer = effects.fire(Vector2.ZERO, Vector2(240.0, 0.0), weapon, Tracer.Kind.BULLET, TRACER_SCENE)
			if tracer.show_streak:
				visible += 1
			tracer.advance(2.0)
		var expected: Array[int] = [6, 4, 3]
		_check(visible == expected[type], "Rifles, MGs and SMGs retain distinct tracer rhythms")
	_check(effects.get_child_count() == 1, "Successive shots reuse the same effect node")
	for shot: int in range(Effects.MAX_EFFECTS):
		effects.fire(Vector2.ZERO, Vector2(120000.0, 0.0), weapon, Tracer.Kind.BULLET, TRACER_SCENE)
	_check(effects.get_child_count() == Effects.MAX_EFFECTS, "Dense fire has a fixed node budget")
	_check(effects.fire(Vector2.ZERO, Vector2.ONE, weapon, Tracer.Kind.ROCKET, TRACER_SCENE) == null, "A saturated pool drops cosmetics immediately")
	var started: int = Time.get_ticks_usec()
	for frame: int in range(180):
		for tracer: Tracer in effects._all:
			tracer.advance(1.0 / 60.0)
	print("192-projectile CPU update average: ", float(Time.get_ticks_usec() - started) / 180000.0, " ms/frame")
	effects.clear()
	var rocket: Tracer = effects.fire(Vector2.ZERO, Vector2(240.0, 0.0), weapon, Tracer.Kind.ROCKET, TRACER_SCENE)
	_check(rocket != null and rocket.show_streak and not rocket.has_arrived, "Pool reuse resets arrival and tracer state for heavy weapons")
	_check(effects.get_child_count() == Effects.MAX_EFFECTS, "A full pool stays bounded after reuse")
	effects.free()


func _layer(names: Array[String]) -> HexagonTileMapLayer:
	var layer: HexagonTileMapLayer = HexagonTileMapLayer.new()
	var tiles: TileSet = TileSet.new()
	tiles.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	tiles.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	tiles.tile_size = Vector2i(128, 128)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(0, "name")
	tiles.set_custom_data_layer_type(0, TYPE_STRING)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(Image.create(4 * names.size(), 4, false, Image.FORMAT_RGBA8))
	source.texture_region_size = Vector2i(4, 4)
	tiles.add_source(source, 0)
	for index: int in range(names.size()):
		var coords: Vector2i = Vector2i(index, 0)
		source.create_tile(coords)
		source.get_tile_data(coords, 0).set_custom_data("name", names[index])
	layer.tile_set = tiles
	add_child(layer)
	return layer


func _test_map_integration() -> void:
	var old_ground: HexagonTileMapLayer = LOSHelper.ground_layer
	var old_buildings: HexagonTileMapLayer = LOSHelper.building_layer
	var old_terrain: HexagonTileMapLayer = LOSHelper.terrain_layer
	var old_roads: HexagonTileMapLayer = LOSHelper.road_layer
	var old_visible: Array = LOSHelper.visible_hexes[Globals.team_player].duplicate()
	var ground: HexagonTileMapLayer = _layer(["Ground"])
	var buildings: HexagonTileMapLayer = _layer(["Wood Building", "Stone Building"])
	var terrain: HexagonTileMapLayer = _layer(["River", "Orchard", "Woods", "Brush"])
	var roads: HexagonTileMapLayer = _layer(["Road"])
	for layer: HexagonTileMapLayer in [ground, buildings, terrain, roads]:
		layer.position = Vector2(72.0, 43.0)
	LOSHelper.ground_layer = ground
	LOSHelper.building_layer = buildings
	LOSHelper.terrain_layer = terrain
	LOSHelper.road_layer = roads
	var effects: Effects = Effects.for_scene(self)
	_check(Effects.for_scene(self) == effects, "All units share one scene-owned pool")
	for index: int in range(2):
		var cell: Vector2i = Vector2i(index, 0)
		buildings.set_cell(cell, 0, Vector2i(index, 0))
		var surfaces: Array[Tracer.Surface] = [Tracer.Surface.WOOD, Tracer.Surface.STONE]
		_check(Effects.surface_at(ground.to_global(ground.map_to_local(cell))) == surfaces[index], "Building material selects the matching impact on transformed maps")
	for index: int in range(4):
		var cell: Vector2i = Vector2i(index, 1)
		terrain.set_cell(cell, 0, Vector2i(index, 0))
		var surfaces: Array[Tracer.Surface] = [Tracer.Surface.WATER, Tracer.Surface.FOLIAGE, Tracer.Surface.FOLIAGE, Tracer.Surface.FOLIAGE]
		_check(Effects.surface_at(ground.to_global(ground.map_to_local(cell))) == surfaces[index], "Water and vegetation choose their own impact styles")
	roads.set_cell(Vector2i(2, 0), 0, Vector2i.ZERO)
	_check(Effects.surface_at(ground.to_global(ground.map_to_local(Vector2i(2, 0)))) == Tracer.Surface.ROAD, "Road overlays choose grit impacts")
	LOSHelper.visible_hexes[Globals.team_player] = [Vector2i.ZERO]
	await get_tree().process_frame
	_check(effects.is_world_position_visible(ground.to_global(ground.map_to_local(Vector2i.ZERO))), "Visible cells allow effects")
	_check(not effects.is_world_position_visible(ground.to_global(ground.map_to_local(Vector2i(1, 0)))), "Hidden cells suppress effects independently of source visibility")
	var view: ViewProbe = ViewProbe.new()
	var unit: Unit = Unit.new()
	unit.ui = view
	var weapon: WeaponSpec = WeaponSpec.new()
	unit._on_fire_shot(weapon, Vector2i.ZERO)
	_check(view.endpoint == ground.to_global(ground.map_to_local(Vector2i.ZERO)), "Unit firing passes world coordinates into the renderer")
	unit.free()
	view.free()
	var ui: UnitUi = (load("res://scenes/game/units/presentation/unit_battlefield_view.tscn") as PackedScene).instantiate() as UnitUi
	add_child(ui)
	ui.shoot(Vector2(80.0, 80.0), Vector2(320.0, 80.0), weapon)
	_check(effects._all.size() == 1 and effects._all[0].active, "The actual battlefield UI launches a pooled projectile")
	ui.shoot_rocket_launcher(Vector2(80.0, 80.0), Vector2(320.0, 80.0), weapon)
	ui.shoot_riflegrenade(Vector2(80.0, 80.0), Vector2(320.0, 80.0), weapon)
	ui.shoot_mortar(Vector2(80.0, 80.0), Vector2(320.0, 80.0), weapon)
	_check(effects._all[1].kind == Tracer.Kind.ROCKET and effects._all[2].kind == Tracer.Kind.GRENADE and effects._all[3].kind == Tracer.Kind.MORTAR, "The firing UI routes each heavy weapon to its own effect profile")
	ui.free()
	_check(effects._all[0].active, "Projectiles survive removal of their firing UI")
	effects.clear()
	LOSHelper.ground_layer = old_ground
	LOSHelper.building_layer = old_buildings
	LOSHelper.terrain_layer = old_terrain
	LOSHelper.road_layer = old_roads
	LOSHelper.visible_hexes[Globals.team_player] = old_visible
	for layer: HexagonTileMapLayer in [ground, buildings, terrain, roads]:
		layer.free()
	effects.free()


func _render_preview() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(960, 640)
	viewport.world_2d = World2D.new()
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CANVAS
	environment.environment.glow_enabled = true
	viewport.add_child(environment)
	var ground_scene: HexagonTileMapLayer = (load("res://scenes/world/maps/layers/ground_tile_map_layer.tscn") as PackedScene).instantiate() as HexagonTileMapLayer
	var ground: TileMapLayer = TileMapLayer.new()
	ground.tile_set = ground_scene.tile_set
	ground_scene.free()
	viewport.add_child(ground)
	for x: int in range(-2, 12):
		for y: int in range(-2, 8):
			ground.set_cell(Vector2i(x, y), 1, Vector2i.ZERO)
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(480.0, 320.0)
	viewport.add_child(camera)
	var title: Label = Label.new()
	title.text = "TRACERS / SIX DIRECTIONS                         TERRAIN IMPACTS"
	title.position = Vector2(28.0, 24.0)
	title.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78))
	viewport.add_child(title)
	var weapon: WeaponSpec = WeaponSpec.new()
	for index: int in range(6):
		var row: int = index / 3
		var column: int = index % 3
		var center: Vector2 = Vector2(110.0 + float(column) * 160.0, 170.0 + float(row) * 220.0)
		var direction: Vector2 = Vector2.from_angle(deg_to_rad(float(index) * 60.0))
		var tracer: Tracer = TRACER_SCENE.instantiate() as Tracer
		viewport.add_child(tracer)
		tracer.launch(center - direction * 65.0, center + direction * 65.0, weapon, Tracer.Kind.BULLET, Tracer.Surface.GROUND, true)
		_seek(tracer, tracer.flight_time * 0.62)
		tracer.set_process(false)
		var label: Label = Label.new()
		label.text = str(index * 60) + " degrees"
		label.position = center + Vector2(-35.0, 65.0)
		viewport.add_child(label)
	var surfaces: Array[Tracer.Surface] = [Tracer.Surface.WOOD, Tracer.Surface.STONE, Tracer.Surface.FOLIAGE, Tracer.Surface.WATER]
	var labels: Array[String] = ["Wood splinters", "Stone chips", "Leaves / brush", "Water splash"]
	for index: int in range(surfaces.size()):
		var end: Vector2 = Vector2(720.0, 135.0 + float(index) * 115.0)
		var tracer: Tracer = TRACER_SCENE.instantiate() as Tracer
		viewport.add_child(tracer)
		tracer.launch(end - Vector2(100.0, 20.0), end, weapon, Tracer.Kind.BULLET, surfaces[index], true)
		tracer.advance(tracer.flight_time + 0.075)
		tracer.set_process(false)
		var label: Label = Label.new()
		label.text = labels[index]
		label.position = end + Vector2(30.0, -10.0)
		viewport.add_child(label)
	var kinds: Array[Tracer.Kind] = [Tracer.Kind.ROCKET, Tracer.Kind.GRENADE, Tracer.Kind.MORTAR]
	var profile_names: Array[String] = ["Rocket exhaust", "Rifle grenade", "Mortar shell"]
	weapon.projectile_speed = 200
	for index: int in range(3):
		var tracer: Tracer = TRACER_SCENE.instantiate() as Tracer
		viewport.add_child(tracer)
		var start: Vector2 = Vector2(80.0 + float(index) * 175.0, 550.0)
		tracer.launch(start, start + Vector2(100.0, 0.0), weapon, kinds[index], Tracer.Surface.STONE, true)
		_seek(tracer, tracer.flight_time * 0.6)
		tracer.set_process(false)
		var label: Label = Label.new()
		label.text = profile_names[index]
		label.position = start + Vector2(0.0, 20.0)
		viewport.add_child(label)
	var muzzle: Tracer = TRACER_SCENE.instantiate() as Tracer
	viewport.add_child(muzzle)
	muzzle.launch(Vector2(80.0, 550.0), Vector2(180.0, 550.0), weapon, Tracer.Kind.ROCKET, Tracer.Surface.STONE, true)
	muzzle.advance(0.015)
	muzzle.set_process(false)
	for hdr: bool in [false, true]:
		viewport.use_hdr_2d = hdr
		for zoom: float in [0.5, 1.0, 2.0]:
			camera.zoom = Vector2(zoom, zoom)
			await get_tree().process_frame
			await get_tree().process_frame
			RenderingServer.force_draw(false)
			var image: Image = viewport.get_texture().get_image()
			_check(not image.is_empty(), "Projectile effects render at zoom " + str(zoom) + ", HDR=" + str(hdr))
			var path: String = "/tmp/acl-projectile-preview-" + str(hdr) + "-" + str(zoom) + ".png"
			_check(image.save_png(path) == OK, "Save the rendered effect preview")
	for child: Node in viewport.get_children():
		if child is Tracer:
			child.queue_free()
	camera.zoom = Vector2.ONE
	await get_tree().process_frame
	await _render_dense(viewport)
	viewport.free()


func _render_dense(viewport: SubViewport) -> void:
	var effects: Effects = Effects.new()
	viewport.add_child(effects)
	effects.set_process(false)
	var weapon: WeaponSpec = WeaponSpec.new()
	weapon.type = WeaponSpec.WeaponType.MG
	for index: int in range(Effects.MAX_EFFECTS):
		var origin: Vector2 = Vector2(40.0 + float(index % 16) * 55.0, 90.0 + float(index / 16) * 40.0)
		var target: Vector2 = origin + Vector2.from_angle(float(index) * 2.399963) * 180.0
		var tracer: Tracer = effects.fire(origin, target, weapon, Tracer.Kind.BULLET, TRACER_SCENE)
		tracer.visibility_test = Callable()
		tracer.screen_test = Callable()
		_seek(tracer, 0.01 + float(index % 12) * 0.03)
		tracer.set_process(false)
	for frame: int in range(3):
		await get_tree().process_frame
	RenderingServer.force_draw(false)
	var dense: Image = viewport.get_texture().get_image()
	_check(dense.save_png("/tmp/acl-projectile-dense.png") == OK, "Render the full 192-effect budget")
	effects.hide()
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var baseline: Image = viewport.get_texture().get_image()
	effects.show()
	for tracer: Tracer in effects._all:
		tracer.visibility_test = func(_point: Vector2) -> bool: return false
		tracer.queue_redraw()
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var obscured: Image = viewport.get_texture().get_image()
	_check(baseline.get_data() == obscured.get_data(), "Hidden muzzle flashes, trails and impacts contribute no rendered pixels")
	_check(dense.get_data() != baseline.get_data(), "Visible effects contribute rendered pixels")
	effects.free()


func _seek(tracer: Tracer, seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.00001:
		var step: float = minf(remaining, 1.0 / 60.0)
		tracer.advance(step)
		remaining -= step


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
