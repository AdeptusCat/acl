extends Node

# Run this scene headlessly for logic checks; add -- --render with a display for HDR previews.
const Effects: Script = preload("res://scenes/game/effects/battlefield_effects.gd")
const Tracer: Script = preload("res://scenes/game/effects/tracer.gd")
const IMPACT_PATTERN: Script = preload("res://scenes/game/effects/burst_impact_pattern.gd")
const TRACER_SCENE: PackedScene = preload("res://scenes/game/effects/tracer.tscn")

class ImpactAudio extends AudioPool:
	var hits: int = 0
	var hit_position: Vector2 = Vector2.ZERO

	func play_one_shot(_stream: AudioStream, point: Vector2, _volume: float = 0.0, _pitch: float = 1.0, _bus: String = "") -> void:
		hits += 1
		hit_position = point


class ViewProbe extends UnitUi:
	var endpoint: Vector2 = Vector2.ZERO
	var origins: Array[Vector2] = []
	var weapons: Array[WeaponSpec] = []
	var impacts: Array[Vector2] = []

	func shoot(_from: Vector2, to: Vector2, _weapon: WeaponSpec, _spawn_offset: Vector2 = Vector2.INF, _impact_offset: Vector2 = Vector2.INF) -> void:
		endpoint = to
		if _spawn_offset.is_finite():
			origins.append(_from + _spawn_offset)
		else:
			origins.append(_from)
		weapons.append(_weapon)
		var impact: Vector2 = to
		if _impact_offset.is_finite():
			impact += _impact_offset
		impacts.append(impact)


class SweepGuide extends Node2D:
	var points: PackedVector2Array = PackedVector2Array()

	func _draw() -> void:
		draw_polyline(points, Color(0.9, 0.75, 0.3, 0.25), 1.0, true)
		for point: Vector2 in points:
			draw_circle(point, 1.5, Color(1.8, 1.0, 0.3))


var failures: int = 0
var checks: int = 0
var arrivals: int = 0
var audio: ImpactAudio
var _completed_bursts: int = 0


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
	var offset: Vector2 = Vector2(-15.0, 9.0)
	tracer.launch(Vector2.ZERO, end, weapon, Tracer.Kind.BULLET, Tracer.Surface.GROUND, true, offset)
	_check(tracer.head == offset and is_equal_approx(tracer.flight_time, 0.2), "Spawn variation keeps the gameplay arrival time")
	tracer.advance(0.1)
	_check(tracer.head.is_equal_approx(offset.lerp(end, 0.5)), "Offset shots travel from their muzzle toward the actual target")
	_check(tracer.head.distance_to(tracer.trail_start()) >= 48.0, "Bullet streaks retain a longer visible body")
	_check(tracer.head.distance_to(tracer.trail_start(0.5)) >= 64.0, "Zooming out preserves a readable tracer length")
	tracer.advance(0.1)
	_check(tracer.head == end and tracer.has_arrived, "Offset shots hit the exact destination on time")
	var impact_offset: Vector2 = Vector2(20.0, -12.0)
	tracer.launch(Vector2.ZERO, end, weapon, Tracer.Kind.BULLET, Tracer.Surface.GROUND, true, offset, impact_offset)
	tracer.advance(0.1)
	_check(tracer.head.is_equal_approx(offset.lerp(end + impact_offset, 0.5)), "Bullets fly straight toward their individual impact points")
	tracer.advance(0.1)
	_check(tracer.destination == end + impact_offset and tracer.head == tracer.destination, "The tracer and impact share the varied destination")
	_check(is_equal_approx(tracer.flight_time, 0.2), "Impact variation preserves nominal shot timing")
	for sample: int in range(32):
		_check(Tracer.sample_spawn_offset().length() <= Tracer.SPAWN_RADIUS + 0.001, "Random spawn points stay within the unit's firing area")
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
	_test_impact_patterns(ground)
	await _test_burst_origins()
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
	var target_cell: Vector2i = ground.local_to_map(ground.to_local(Vector2(320.0, 80.0)))
	_check(ground.local_to_map(ground.to_local(effects._all[0].destination)) == target_cell, "Independent shots randomize the hit point inside the intended target hex")
	var first_impact: Vector2 = effects._all[0].destination
	var first_origin: Vector2 = effects._all[0].origin
	_check(first_origin.distance_to(Vector2(80.0, 80.0)) <= Tracer.SPAWN_RADIUS, "Individual shots randomize their muzzle within the firing area")
	effects.clear()
	ui.shoot(Vector2(80.0, 80.0), Vector2(320.0, 80.0), weapon)
	_check(effects._all[0].origin != first_origin, "Separate individual shots use fresh spawn positions")
	_check(effects._all[0].destination != first_impact, "Separate individual shots use fresh impact positions")
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


func _test_burst_origins() -> void:
	var unit: Unit = Unit.new()
	var view: ViewProbe = ViewProbe.new()
	unit.ui = view
	unit.position = Vector2(200.0, 200.0)
	var controller: SquadFireController = SquadFireController.new()
	controller.unit = unit
	add_child(controller)
	controller.set_process(false)
	var first_weapon: WeaponSpec = WeaponSpec.new()
	first_weapon.type = WeaponSpec.WeaponType.MG
	var second_weapon: WeaponSpec = first_weapon.duplicate() as WeaponSpec
	var first: Soldier = Soldier.new(901, "First MG", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, first_weapon, unit, unit.team)
	var second: Soldier = Soldier.new(902, "Second MG", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, second_weapon, unit, unit.team)
	controller.fire_shot.connect(unit._on_fire_shot)
	controller.fire_shot.connect(func(_weapon: WeaponSpec, _hex: Vector2i, _origin: Vector2, _impact: Vector2) -> void:
		if view.origins.size() == 1:
			unit.position += Vector2(70.0, 0.0)
	)
	_completed_bursts = 0
	_fire_burst(controller, first)
	_fire_burst(controller, second)
	var deadline: int = Time.get_ticks_msec() + 4000
	while _completed_bursts < 2 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_completed_bursts == 2 and view.origins.size() == 6, "Overlapping MG bursts finish through the real shot signal")
	var first_origins: Array[Vector2] = []
	var second_origins: Array[Vector2] = []
	var first_impacts: PackedVector2Array = PackedVector2Array()
	var second_impacts: PackedVector2Array = PackedVector2Array()
	for index: int in range(view.origins.size()):
		if view.weapons[index] == first_weapon:
			first_origins.append(view.origins[index])
			first_impacts.append(view.impacts[index])
		else:
			second_origins.append(view.origins[index])
			second_impacts.append(view.impacts[index])
	_check(first_origins.size() == 3 and first_origins[0] == first_origins[1] and first_origins[0] == first_origins[2], "One MG burst keeps one world origin even if the unit moves")
	_check(second_origins.size() == 3 and second_origins[0] == second_origins[1] and second_origins[0] == second_origins[2], "Another gun's overlapping burst keeps its own origin")
	_check(first_origins[0] != second_origins[0], "Separate guns do not share a burst origin")
	_check_sweep(LOSHelper.ground_layer, Vector2i.ZERO, first_impacts)
	_check_sweep(LOSHelper.ground_layer, Vector2i.ZERO, second_impacts)
	_check(first_impacts != second_impacts, "Overlapping bursts keep independent impact patterns")
	unit.position = Vector2(200.0, 200.0)
	await _fire_burst(controller, first)
	_check(view.origins[-1] != first_origins[0], "A new burst samples a new muzzle position")
	controller.calc.free()
	controller.free()
	unit.free()
	view.free()


func _test_impact_patterns(ground: HexagonTileMapLayer) -> void:
	var original_transform: Transform2D = ground.transform
	var original_size: Vector2i = ground.tile_set.tile_size
	var original_axis: TileSet.TileOffsetAxis = ground.tile_set.tile_offset_axis
	ground.position = Vector2(72.0, 43.0)
	ground.rotation = 0.37
	ground.scale = Vector2(1.2, 0.85)
	for axis: TileSet.TileOffsetAxis in [TileSet.TILE_OFFSET_AXIS_HORIZONTAL, TileSet.TILE_OFFSET_AXIS_VERTICAL]:
		ground.tile_set.tile_offset_axis = axis
		for size: Vector2i in [Vector2i(64, 64), Vector2i(128, 128), Vector2i(160, 96)]:
			ground.tile_set.tile_size = size
			for cell: Vector2i in [Vector2i.ZERO, Vector2i(-3, 2), Vector2i(5, -4)]:
				var origin: Vector2 = ground.to_global(ground.map_to_local(cell) + Vector2(-500.0, -300.0))
				for rounds: int in [1, 3, 8, 24]:
					var impacts: PackedVector2Array = IMPACT_PATTERN.create(ground, cell, origin, rounds)
					_check(impacts.size() == rounds, "Every burst round receives an impact point")
					_check_sweep(ground, cell, impacts)
	ground.tile_set.tile_size = original_size
	ground.tile_set.tile_offset_axis = original_axis
	ground.transform = original_transform
	_check(IMPACT_PATTERN.bezier_point(Vector2(-20.0, 0.0), Vector2.ZERO, Vector2(20.0, 0.0), 0.5) == Vector2.ZERO, "A straight sweep interpolates along its center line")
	_check(IMPACT_PATTERN.bezier_point(Vector2(-20.0, 0.0), Vector2(0.0, 12.0), Vector2(20.0, 0.0), 0.5) == Vector2(0.0, 6.0), "A curved sweep bends smoothly between its endpoints")


func _check_sweep(ground: HexagonTileMapLayer, cell: Vector2i, impacts: PackedVector2Array) -> void:
	var seen: Dictionary[Vector2, bool] = {}
	var tile_size: Vector2 = Vector2(ground.tile_set.tile_size)
	var start: Vector2 = ground.to_local(impacts[0]) / tile_size
	var end: Vector2 = ground.to_local(impacts[-1]) / tile_size
	var direction: Vector2 = (end - start).normalized()
	var previous: float = -INF
	for point: Vector2 in impacts:
		_check(ground.local_to_map(ground.to_local(point)) == cell, "Every impact remains inside the captured target hex")
		_check(not seen.has(point), "Each round has a different impact position")
		seen[point] = true
		var progress: float = (ground.to_local(point) / tile_size - start).dot(direction)
		_check(progress > previous, "Burst impacts advance coherently along the sweep")
		previous = progress


func _fire_burst(controller: SquadFireController, soldier: Soldier) -> void:
	await controller.fire_shots(soldier, 3, 6000.0, false, Vector2i.ZERO)
	_completed_bursts += 1


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
	await _render_mortar_contrast(viewport, camera)
	await _render_burst_sweeps(viewport, camera, ground)
	viewport.free()


func _render_burst_sweeps(viewport: SubViewport, camera: Camera2D, ground: TileMapLayer) -> void:
	for child: Node in viewport.get_children():
		if child is Label:
			child.queue_free()
	var cells: Array[Vector2i] = [Vector2i(5, 1), Vector2i(5, 3)]
	var first_center: Vector2 = ground.to_global(ground.map_to_local(cells[0]))
	var second_center: Vector2 = ground.to_global(ground.map_to_local(cells[1]))
	camera.position = first_center.lerp(second_center, 0.5) - Vector2(100.0, 0.0)
	camera.zoom = Vector2(1.5, 1.5)
	var weapon: WeaponSpec = WeaponSpec.new()
	for index: int in range(cells.size()):
		var center: Vector2 = ground.to_global(ground.map_to_local(cells[index]))
		var origin: Vector2 = center - Vector2(310.0, 0.0)
		var points: PackedVector2Array = IMPACT_PATTERN.create(ground, cells[index], origin, 7)
		var guide: SweepGuide = SweepGuide.new()
		guide.points = points
		viewport.add_child(guide)
		for shot: int in range(points.size()):
			var tracer: Tracer = TRACER_SCENE.instantiate() as Tracer
			viewport.add_child(tracer)
			tracer.launch(origin, center, weapon, Tracer.Kind.BULLET, Tracer.Surface.GROUND, true, Vector2.ZERO, points[shot] - center)
			_seek(tracer, tracer.flight_time + 0.02 + float(shot) * 0.005)
			tracer.set_process(false)
			var label: Label = Label.new()
			label.text = str(shot + 1)
			label.position = points[shot] + Vector2(-3.0, -14.0)
			label.add_theme_font_size_override("font_size", 8)
			viewport.add_child(label)
		var caption: Label = Label.new()
		caption.text = "One muzzle / ordered impacts inside one hex"
		caption.position = center - Vector2(195.0, 65.0)
		caption.add_theme_font_size_override("font_size", 11)
		viewport.add_child(caption)
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var preview: Image = viewport.get_texture().get_image()
	_check(preview.save_png("/tmp/acl-burst-impact-sweeps.png") == OK, "Render ordered impact sweeps inside their target hexes")


func _render_mortar_contrast(viewport: SubViewport, camera: Camera2D) -> void:
	var background: ColorRect = ColorRect.new()
	background.size = Vector2(960.0, 640.0)
	viewport.add_child(background)
	var weapon: WeaponSpec = WeaponSpec.new()
	weapon.projectile_speed = 200
	var shell: Tracer = TRACER_SCENE.instantiate() as Tracer
	viewport.add_child(shell)
	shell.launch(Vector2(420.0, 320.0), Vector2(540.0, 320.0), weapon, Tracer.Kind.MORTAR, Tracer.Surface.GROUND, true)
	_seek(shell, shell.flight_time * 0.5)
	shell.set_process(false)
	for color: Color in [Color(0.24, 0.35, 0.15), Color(0.37, 0.23, 0.10), Color(0.65, 0.65, 0.62)]:
		background.color = color
		for zoom: float in [0.5, 1.0, 2.0]:
			camera.zoom = Vector2(zoom, zoom)
			shell.hide()
			await get_tree().process_frame
			RenderingServer.force_draw(false)
			var baseline: Image = viewport.get_texture().get_image()
			shell.show()
			await get_tree().process_frame
			RenderingServer.force_draw(false)
			var visible: Image = viewport.get_texture().get_image()
			var contrasting_pixels: int = 0
			for x: int in range(470, 491):
				for y: int in range(310, 331):
					var before: Color = baseline.get_pixel(x, y)
					var after: Color = visible.get_pixel(x, y)
					if Vector3(before.r - after.r, before.g - after.g, before.b - after.b).length() > 0.15:
						contrasting_pixels += 1
			_check(contrasting_pixels >= 12, "Mortar bodies remain visible over grass, wood and stone colors at zoom " + str(zoom))
	shell.free()
	background.free()


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
