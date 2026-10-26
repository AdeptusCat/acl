extends Node

var checks: int = 0
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("DefaultMap")
	var scenario: Scenario = map.get_scenario(0)
	scenario.axis_ai_status = Scenario.AIStatus.OFF
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	scenario.offboard_batteries = [load("res://resources/fire_support/example_81mm_battery.tres"), load("res://resources/fire_support/example_105mm_battery.tres")]
	scenario.offboard_batteries[0] = scenario.offboard_batteries[0].duplicate() as OffboardBattery
	scenario.offboard_batteries[0].gun_count = 4
	var mortar: Unit = load("res://scenes/game/units/unit.tscn").instantiate() as Unit
	mortar.team = scenario.player_team
	mortar.squad_type = Globals.SquadType.MORTAR
	mortar.squad_loadout = load("res://resources/squads/united_states/light_mortar_squad.tres") as SquadLoadoutSpec
	for other: Node in scenario.get_units():
		if other is Unit and other.team == mortar.team:
			mortar.current_hex = other.current_hex
			mortar.position = other.position
			break
	scenario.units.add_child(mortar)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	var host: Node2D = world.game_controller
	var support: FireSupportController = host.fire_support
	_check(support.assets.size() == 3, "Onboard mortars and both authored offboard batteries share one tray")
	_check(support.panel.asset_buttons.size() == 3, "Every support asset has its own HUD icon")
	_check(support.panel.asset_buttons[0].icon == load("res://assets/ui/hud/fire_support/m2_60mm_mortar.png") and support.panel.asset_buttons[1].icon == load("res://assets/ui/hud/fire_support/m1_81mm_mortar.png") and support.panel.asset_buttons[2].icon == load("res://assets/ui/hud/fire_support/m2a1_105mm_howitzer.png"), "Support assets display their individual M2, M1 and 105 mm weapon artwork")
	for button: Button in support.panel.asset_buttons:
		var artwork: Image = button.icon.get_image()
		_check(artwork.get_pixel(0, 0).a == 0.0 and artwork.detect_alpha() != Image.ALPHA_NONE, "Weapon artwork retains a transparent background")
	var marked: Vector2i = mortar.current_hex
	world._on_hex_selected(marked, Vector2.ZERO)
	var initial_ammunition: int = support.ammunition(2)
	support.panel.asset_buttons[2].pressed.emit()
	_check(support.panel.tray.visible and support.selected_asset == 2 and support.panel.asset_label.text.contains(support.assets[2]["name"]), "Clicking a howitzer icon opens its battery directly")
	_check(support.has_target and support.target == marked and support.target_cells == [marked], "Opening a support icon uses the marked map hex as its initial point target")
	_check(support.ammunition(2) == initial_ammunition and support.asset_mission(2) == null, "Using the marked hex prepares a preview without firing")
	support.panel.asset_buttons[2].pressed.emit()
	_check(not support.panel.tray.visible and not support.choosing_target, "Clicking the selected support icon again closes the panel")
	world.clear_hex_inspection()
	support.panel.asset_buttons[2].pressed.emit()
	support.panel.asset_buttons[1].pressed.emit()
	_check(support.panel.tray.visible and support.selected_asset == 1, "Clicking a different support icon switches the open panel to that battery")
	_check(support.panel.tray.find_children("*", "OptionButton", true, false).size() == 2, "The support panel exposes independent length and intensity dropdowns")
	_right_click_at(support.panel.tray.get_global_rect().get_center())
	_check(not support.panel.tray.visible and not support.choosing_target, "Right-clicking over the support panel closes it")
	support.panel._close()
	support.selected_asset = 0
	var target: Vector2i = mortar.current_hex
	for cell: Vector2i in host.ground_layer.get_used_cells():
		var distance: int = host.ground_layer.cube_distance(mortar.current_cube, host.ground_layer.map_to_cube(cell))
		if distance == 2 and LOSHelper.find_units_at(cell).is_empty():
			target = cell
			break
	var gunner: Soldier
	for soldier: Soldier in mortar.squad_fire.soldiers:
		if soldier.weapon != null and soldier.weapon.family == WeaponSpec.Family.MORTAR:
			gunner = soldier
			break
	_check(gunner != null, "The onboard fixture uses a real mortar weapon and crew")
	gunner.weapon.projectile_speed = 100000
	gunner.weapon.ammunition = 30
	var selected: Unit = Globals.get_units_for_team(Globals.team_player)[0]
	host.select_and_center_unit(selected)
	support.panel.toggle_tray()
	_check(support.choosing_target, "Opening fire support immediately enters target selection")
	_check(not support.has_target, "Opening support without a marked hex waits for a map target")
	var point: Vector2 = host.ground_layer.get_global_transform_with_canvas() * host.ground_layer.map_to_local(target)
	host._on_mouse_button_left_pressed(point)
	_check(support.dragging and not support.has_target, "Press previews without firing or confirming a target")
	world.input_manager.mouse_button_left_released.emit(point)
	_check(support.has_target and support.target == target and host.selected_unit == selected, "Picking a fire mission hex preserves the selected infantry squad")
	var second_point: Vector2 = host.ground_layer.get_global_transform_with_canvas() * host.ground_layer.map_to_local(mortar.current_hex)
	host._on_mouse_button_left_pressed(second_point)
	support.end_target(second_point)
	_check(support.target == mortar.current_hex and support.choosing_target and host.selected_unit == selected, "A second map click replaces the target while the panel stays open")
	_right_click_at(point)
	_check(not support.panel.tray.visible and not support.choosing_target and not support.has_target and not support.dragging, "Right-clicking the battlefield closes support and clears the target preview")
	_check(host.selected_unit == selected and not world.ui.selection_wheel_alt.is_open() and not world.input_manager._right_button_held, "Dismissing support does not select a different squad or open the command wheel")
	world._on_hex_selected(target, Vector2.ZERO)
	support.panel.toggle_tray()
	_check(support.has_target and support.target == target, "Opening support with its shortcut also uses the marked hex")
	world.clear_hex_inspection()
	host._on_mouse_button_left_pressed(point)
	support.end_target(point)
	_check(support.preview(0, mortar.current_hex).contains("FRIENDLY"), "The preview identifies friendly troops in the struck hex")
	support.panel.fire_button.pressed.emit()
	_check(support.asset_mission(0) != null, "The Fire Mission button issues the prepared onboard mission")
	_check(not support.choosing_target and not support.panel.tray.visible and not support.has_target, "The Fire Mission button closes the panel and exits target selection")
	var short_mission: FireSupportMission = support.asset_mission(0)
	support.panel.toggle_tray()
	_right_click_at(point)
	_check(short_mission.active and support.asset_mission(0) == short_mission, "Right-click dismissal leaves an assigned fire mission running")
	support.panel.toggle_tray()
	_check(not support.request(0, target, 15.0, FireSupportMission.Intensity.INTENSE), "A busy battery rejects overlapping fire missions")
	gunner.setup_weapon_task.done = false
	gunner.setup_weapon_task.start_time_s = 2.0
	short_mission.launch_work_total = 0.0
	var preparing: Dictionary = support.asset_launch_progress(0)
	_check(is_zero_approx(float(preparing["fill"])), "The onboard launch indicator begins empty during preparation")
	gunner.setup_weapon_task.remaining_time_s = 1.0
	var halfway: Dictionary = support.asset_launch_progress(0)
	_check(is_equal_approx(float(halfway["fill"]), 1.0 / float(preparing["seconds"])), "The launch indicator follows real crew setup progress alongside other preparation")
	gunner.setup_weapon_task.remaining_time_s = 2.0
	support.panel._refresh_launch_progress()
	_check(support.panel.launch_bars[0].visible and support.panel.launch_bars[0].mouse_filter == Control.MOUSE_FILTER_IGNORE, "The active icon fill remains visible and cannot intercept icon clicks")
	_check(support.panel.asset_buttons[0].text == "3/3\nAmmo 30", "The icon shows both mission rounds and battery ammunition")
	var blocked: int = await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
	_check(blocked == 0 and short_mission.fired == 0, "Mission requests do not bypass real mortar setup")
	for shot: int in range(3):
		var scheduled: FireSupportMission = support.asset_mission(0)
		scheduled.elapsed = scheduled.next_round
		_ready_gunner(gunner)
		var fired: int = await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
		_check(fired == 1, "Intense missions launch actual mortar rounds")
		support.panel._refresh_launch_progress()
		_check(support.panel.asset_buttons[0].text == "%d/3\nAmmo %d" % [2 - shot, 29 - shot], "Mission rounds and battery ammunition both update after each launch")
		if shot < 2:
			_check(is_zero_approx(float(support.asset_launch_progress(0)["fill"])), "The onboard icon fill resets after each launch")
	_ready_gunner(gunner)
	var extra: int = await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
	_check(short_mission.fired == 3 and not short_mission.active and extra == 0 and gunner.weapon.ammunition == 27, "A 15-second intense mission plans three rounds with no extra shot")
	support.panel._refresh_launch_progress()
	_check(not support.panel.launch_bars[0].visible and not support.panel.launch_clocks[0].visible, "Completed missions hide the next-launch indicator even while shells may be airborne")
	support._process(0.01)
	_check(mortar.squad_fire.fire_support_hold, "A completed battery stays silent until a new fire order")
	_check(support.request(0, target, 60.0, FireSupportMission.Intensity.STEADY), "A completed battery can immediately receive another mission")
	_ready_gunner(gunner)
	await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
	_ready_gunner(gunner)
	var early: int = await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
	_check(early == 0 and support.asset_mission(0).remaining == 5, "A one-minute steady mission spaces launches and plans six rounds")
	support.panel._refresh_launch_progress()
	_check(support.panel.asset_buttons[0].text == "5/6\nAmmo 26", "The mission denominator stays fixed while battery ammunition decreases")
	support.cease(0)
	_check(support.request(0, target, 300.0, FireSupportMission.Intensity.HARASSING), "Harassing fire can replace a ceased mission")
	_ready_gunner(gunner)
	await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
	var harassment: FireSupportMission = support.asset_mission(0)
	_check(is_equal_approx(harassment.next_round, 20.0), "Harassing fire schedules the displayed 20-second interval")
	_ready_gunner(gunner)
	_check(await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0) == 0, "Harassing mortars cannot fire continuously between scheduled rounds")
	support._process(harassment.next_round + 0.01)
	_ready_gunner(gunner)
	_check(await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0) == 1, "The next harassing round uses the normal firing pipeline")
	support.cease(0)
	var enemy: Unit = Globals.get_units_for_team(Globals.get_enemy_team(Globals.team_player))[0]
	_check(support.request(1, enemy.current_hex, 15.0, FireSupportMission.Intensity.INTENSE), "Offboard missions do not require selecting or inventing a map counter")
	var before: int = support.ammunition(1)
	_check(is_zero_approx(float(support.asset_launch_progress(1)["fill"])), "Offboard response progress starts empty")
	support._process(5.0)
	_check(support.ammunition(1) == before, "Offboard batteries honor their authored response delay")
	_check(is_equal_approx(float(support.asset_launch_progress(1)["fill"]), 5.0 / 6.0), "Offboard icon progress follows the authored response countdown")
	support._process(1.0)
	_check(support.ammunition(1) == before - 1 and support.flights.size() == 1, "Offboard launch spends ammunition and creates an in-flight shell")
	_check(is_zero_approx(float(support.asset_launch_progress(1)["fill"])), "Offboard reload starts a fresh icon fill at launch")
	var ground: HexagonTileMapLayer = host.ground_layer
	var finish: Vector2 = ground.to_global(ground.map_to_local(enemy.current_hex))
	var start: Vector2 = ground.to_global(ground.map_to_local(scenario.start_hex[Globals.team_player]))
	var origin: Vector2 = support.flights[0]["origin"]
	_check((origin - finish).normalized().dot((start - finish).normalized()) > 0.999, "Offboard rounds approach from the player start hex direction")
	var board_bounds: Rect2 = Rect2(finish, Vector2.ZERO)
	for cell: Vector2i in ground.get_used_cells():
		board_bounds = board_bounds.expand(ground.to_global(ground.map_to_local(cell)))
	_check(not board_bounds.has_point(origin), "Offboard launch originates beyond the battlefield bounds")
	var near_origin: Vector2 = support._offboard_origin(finish, 1.0)
	_check(not board_bounds.has_point(near_origin), "Even short configured flight distances launch beyond the board")
	_check(support._offboard_origin(start, 1.0).is_finite() and not board_bounds.has_point(support._offboard_origin(start, 1.0)), "Firing at the player start uses a finite offboard fallback direction")
	var effects: BattlefieldEffects = BattlefieldEffects.for_scene(support)
	var timed_effect: bool = false
	for tracer: BattlefieldTracer in effects._all:
		if tracer.active and tracer.origin == origin:
			timed_effect = is_equal_approx(tracer.flight_time, 4.0) and is_equal_approx(tracer.speed * tracer.flight_time, origin.distance_to(finish))
	_check(timed_effect, "Offboard visual flight time stays synchronized with impact after extending the approach")
	support.cease(1)
	_check(support.asset_launch_progress(1).is_empty(), "Ceased missions stop displaying a next-shell countdown")
	support._process(4.0)
	await get_tree().process_frame
	_check(support.flights.is_empty() and enemy.stress_system.under_fire, "Cease fire leaves airborne shells to resolve through the real impact system")
	(support.assets[2]["weapon"] as WeaponSpec).ammunition = 0
	_check(not support.request(2, target, 15.0, FireSupportMission.Intensity.INTENSE), "Empty offboard batteries reject fire requests")
	support.selected_asset = 0
	support.pick_target(point)
	support.panel.refresh()
	_check(not support.panel.fire_button.disabled and host.selected_unit == selected, "The HUD can prepare another fire mission while preserving infantry selection")
	support.panel._close()
	var shortcut: InputEventKey = InputEventKey.new()
	shortcut.pressed = true
	shortcut.keycode = KEY_F
	support.panel._unhandled_key_input(shortcut)
	_check(support.panel.tray.visible and support.choosing_target, "F opens the tray and enters map targeting")
	shortcut.keycode = KEY_ESCAPE
	support.panel._unhandled_key_input(shortcut)
	_check(not support.panel.tray.visible and not support.choosing_target and host.selected_unit == selected, "Escape cancels support targeting without changing infantry selection")
	support.panel.toggle_tray()
	await _test_shapes(support, mortar, gunner, target, selected)
	await _test_timed_settings(support, mortar, gunner, target)
	_test_volleys(support, target)
	support.pick_target(point)
	support.selected_length = 300.0
	support.selected_intensity = FireSupportMission.Intensity.HARASSING
	support.panel.intensity.select(2)
	support.panel.refresh()
	if OS.get_cmdline_user_args().has("--capture"):
		support.cease(1)
		support.panel._open_asset(1)
		support.panel._select_guns(3)
		support.request(1, target, 60.0, FireSupportMission.Intensity.STEADY, [], FireSupportMission.Shape.POINT, target, 1, 3)
		var showcase: FireSupportMission = support.asset_mission(1)
		showcase.elapsed = showcase.next_round * 0.55
		support.panel.refresh()
		point = get_viewport().get_visible_rect().size * Vector2(0.68, 0.35)
		support.select_shape(FireSupportMission.Shape.AREA)
		support.begin_target(point)
		support.end_target(point + Vector2(180, -100))
		world.ui.get_node("Control/OrderFeedback").hide()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/acl-fire-support-hud.png")
	main.queue_free()
	await get_tree().process_frame
	print("Fire support checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)

func _test_shapes(support: FireSupportController, mortar: Unit, gunner: Soldier, start: Vector2i, selected: Unit) -> void:
	var ground: HexagonTileMapLayer = support.host.ground_layer
	var end: Vector2i = start
	for cell: Vector2i in ground.get_surrounding_cells(start):
		if ground.get_cell_source_id(cell) != -1 and LOSHelper.find_units_at(cell).is_empty():
			end = cell
			break
	var a: Vector2 = ground.get_global_transform_with_canvas() * ground.map_to_local(start)
	var b: Vector2 = ground.get_global_transform_with_canvas() * ground.map_to_local(end)
	var ammo: int = support.ammunition(0)
	support.begin_target(a)
	support.update_drag(a + Vector2(3, 0))
	_check(support.target_shape == FireSupportMission.Shape.POINT, "Small pointer jitter retains point fire")
	support.end_target(a)
	_check(support.has_target and support.ammunition(0) == ammo, "Releasing prepares the target without spending ammunition")
	support.begin_target(a)
	support.update_drag(b)
	_check(support.dragging and support.target_shape == FireSupportMission.Shape.LINE and support.target_cells.size() == 2, "Plain dragging previews a line between hexes")
	support.end_target(b)
	var line: Array[Vector2i] = support.target_cells.duplicate()
	_check(line == [start, end] and support.has_target and support.host.selected_unit == selected, "Release keeps ordered line coverage and infantry selection")
	_check(support.build_footprint(end, start, FireSupportMission.Shape.LINE, 1) == [end, start], "Reversing the line reverses its sweep")
	support.begin_target(a, true)
	support.end_target(b)
	_check(support.target_shape == FireSupportMission.Shape.AREA and support.target_cells.size() > 1, "Shift-drag prepares circular area coverage")
	support.select_shape(FireSupportMission.Shape.AREA)
	support.begin_target(a)
	support.end_target(b)
	_check(support.target_shape == FireSupportMission.Shape.AREA, "The Area button enables area drag without Shift")
	var area: Array[Vector2i] = support.build_footprint(start, end, FireSupportMission.Shape.AREA, 3)
	support.target_cells = area.duplicate()
	support.selected_length = 15.0
	support.selected_intensity = FireSupportMission.Intensity.INTENSE
	_check(support.coverage_text().contains("sparse coverage"), "Short intense area missions warn about sparse coverage")
	_check(support.preview(0, start, area).contains("FRIENDLY"), "Area warnings include friendlies away from the center")
	var escape: InputEventKey = InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	support.panel._unhandled_key_input(escape)
	_check(not support.has_target and not support.dragging and support.panel.tray.visible, "Escape cancels the footprint and keeps the panel open")
	support.select_shape(FireSupportMission.Shape.LINE)
	support.begin_target(a)
	support.end_target(b)
	_check(support.target_shape == FireSupportMission.Shape.LINE, "The Line button supports dragging without modifiers")
	var original_range: int = gunner.weapon.range_hexes
	gunner.weapon.range_hexes = 0
	var partly_out_of_range: Array[Vector2i] = [mortar.current_hex, start]
	_check(not support.request(0, mortar.current_hex, 15.0, FireSupportMission.Intensity.INTENSE, partly_out_of_range, FireSupportMission.Shape.LINE, start), "A footprint is rejected if any covered hex exceeds onboard range")
	gunner.weapon.range_hexes = original_range
	_check(support.request(0, start, 15.0, FireSupportMission.Intensity.INTENSE, line, FireSupportMission.Shape.LINE, end), "Onboard mortars accept line missions")
	var impacts: Array[Vector2i] = []
	var record: Callable = func(_weapon: WeaponSpec, cell: Vector2i, _origin: Vector2, _impact: Vector2) -> void: impacts.append(cell)
	mortar.squad_fire.fire_shot.connect(record)
	for shot: int in range(3):
		var scheduled: FireSupportMission = support.asset_mission(0)
		scheduled.elapsed = scheduled.next_round
		_ready_gunner(gunner)
		await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
	mortar.squad_fire.fire_shot.disconnect(record)
	_check(impacts == [start, end, start] and support.ammunition(0) == ammo - 3, "Real onboard rounds sweep the line with only three rounds spent")
	support._process(0.01)
	var pattern: FireSupportMission = FireSupportMission.new()
	pattern.shape = FireSupportMission.Shape.AREA
	pattern.cells.assign(area)
	pattern.intensity = FireSupportMission.Intensity.HARASSING
	pattern.remaining = area.size() * 2
	for cycle: int in range(2):
		var visited: Array[Vector2i] = []
		for shot: int in range(area.size()):
			var cell: Vector2i = pattern.next_target()
			_check(not visited.has(cell) and area.has(cell) and pattern.next_target() == cell, "Area fire covers every hex once per cycle and retains its pending target")
			visited.append(cell)
			pattern.commit_rounds(1)
	var invalid: Array[Vector2i] = [start, Vector2i(-9999, -9999)]
	_check(not support.request(1, start, 15.0, FireSupportMission.Intensity.INTENSE, invalid, FireSupportMission.Shape.LINE, end), "An invalid footprint is rejected atomically")
	var before: int = support.ammunition(1)
	_check(support.request(1, start, 15.0, FireSupportMission.Intensity.INTENSE, area, FireSupportMission.Shape.AREA, end, 3), "Offboard batteries accept area missions")
	var mission: FireSupportMission = support.asset_mission(1)
	var landed_cells: Array[Vector2i] = []
	for shot: int in range(3):
		mission.elapsed = mission.next_round
		support._launch_offboard(support.assets[1], mission)
		var impact: Vector2i = support.flights.back()["target"]
		_check(area.has(impact) and not landed_cells.has(impact), "Offboard shells retain distinct individual impact hexes in their area")
		landed_cells.append(impact)
	_check(not mission.active and mission.fired == 3 and support.ammunition(1) == before - 3, "Area size does not multiply the timed mission ammunition estimate")
	support.select_shape(FireSupportMission.Shape.POINT)

func _test_timed_settings(support: FireSupportController, mortar: Unit, gunner: Soldier, target: Vector2i) -> void:
	_check(support.planned_rounds(0, 60.0, FireSupportMission.Intensity.STEADY) == 6 and support.planned_rounds(0, 60.0, FireSupportMission.Intensity.HARASSING) == 3, "Length and intensity independently determine the planned round count")
	var clock: FireSupportMission = FireSupportMission.new()
	clock.duration_seconds = 15.0
	clock.remaining = 3
	clock.planned_rounds = 3
	clock.elapsed = 30.0
	_check(not clock.time_expired() and clock.seconds_left() == 15.0, "Initial response and preparation do not consume the firing window")
	clock.commit_rounds(1)
	_check(clock.first_launch_at == 30.0 and clock.next_round == 35.0, "The first launch starts the duration and the exact intensity interval")
	clock.elapsed = 45.0
	_check(clock.time_expired() and not clock.ready_to_fire(), "A shell cannot launch at or after the firing deadline")
	clock.stop("Time complete")
	_check(clock.remaining == 0 and clock.planned_rounds == 3, "Ending a window clears pending rounds while preserving the original planned total")
	_check(not support.request(0, target, 0.0, FireSupportMission.Intensity.INTENSE), "Invalid mission lengths are rejected")
	_check(support.request(0, target, 60.0, FireSupportMission.Intensity.STEADY), "A timed onboard mission is accepted")
	_ready_gunner(gunner)
	await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
	var mission: FireSupportMission = support.asset_mission(0)
	var ammo: int = support.ammunition(0)
	gunner.reload_task.done = false
	gunner.reload_task.start_time_s = 4.0
	var early: int = await mortar.squad_fire._try_fire_soldier(0.5, gunner, true, 1, 1, 2, 0)
	_check(early == 0 and gunner.reload_task.remaining_time_s < 4.0, "Crews reload during the scheduled pause without firing early")
	mission.elapsed = mission.first_launch_at + mission.duration_seconds
	_ready_gunner(gunner)
	_check(await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0) == 0, "A ready onboard gunner still respects the time limit")
	support._process(0.0)
	_check(not mission.active and mission.remaining == 0 and support.ammunition(0) == ammo, "Expired onboard missions stop without spending unfired ammunition")
	_check(support.request(1, target, 60.0, FireSupportMission.Intensity.STEADY), "A timed offboard mission is accepted")
	mission = support.asset_mission(1)
	mission.elapsed = mission.next_round
	support._launch_offboard(support.assets[1], mission)
	ammo = support.ammunition(1)
	mission.elapsed = mission.first_launch_at + mission.duration_seconds
	support._process(0.0)
	_check(not mission.active and mission.remaining == 0 and support.ammunition(1) == ammo, "Expired offboard missions cannot launch overdue shells")

func _test_volleys(support: FireSupportController, target: Vector2i) -> void:
	var weapon: WeaponSpec = support.assets[1]["weapon"]
	var stock: int = weapon.ammunition
	support.panel._open_asset(1)
	_check(support.available_guns(1) == 4 and support.panel.guns.max_value == 4.0, "The panel uses the authored battery gun count as its selection limit")
	support.panel._select_guns(3)
	_check(support.selected_guns(1) == 3 and support.panel.intensity.get_item_text(0).contains("volley"), "Selecting several guns changes intensity wording to seconds per volley")
	_check(support.planned_rounds(1, 15.0, FireSupportMission.Intensity.INTENSE, 3) == mini(stock, 9), "Planned ammunition scales with selected guns and remains capped by shared stock")
	_check(not support.request(1, target, 15.0, FireSupportMission.Intensity.INTENSE, [], FireSupportMission.Shape.POINT, target, 1, 5), "A mission cannot select more guns than the battery contains")
	var end: Vector2i = target
	var ground: HexagonTileMapLayer = support.host.ground_layer
	for cell: Vector2i in ground.get_surrounding_cells(target):
		if ground.get_cell_source_id(cell) != -1:
			end = cell
			break
	var line: Array[Vector2i] = [target, end]
	_check(support.request(1, target, 15.0, FireSupportMission.Intensity.INTENSE, line, FireSupportMission.Shape.LINE, end, 1, 3), "A three-gun volley mission is accepted")
	var mission: FireSupportMission = support.asset_mission(1)
	var flights: int = support.flights.size()
	mission.elapsed = mission.next_round
	var first_launch: float = mission.elapsed
	support._process(0.0)
	_check(mission.fired == 1 and mission.pending_guns == 2 and weapon.ammunition == stock - 1, "The first gun launches immediately while the other selected guns prepare staggered shots")
	_check(str(support.asset_launch_progress(1).get("clock", "")) == "Volley", "The launch indicator identifies a volley in progress")
	mission.elapsed = first_launch + 0.10
	support._process(0.0)
	_check(mission.fired == 1, "The volley has a small timing spread rather than perfectly simultaneous shells")
	mission.elapsed = first_launch + 0.60
	support._process(0.0)
	_check(mission.fired == 3 and mission.pending_guns == 0 and support.flights.size() == flights + 3 and weapon.ammunition == stock - 3, "All selected guns launch individual shells within roughly half a second")
	_check(support.flights[flights]["target"] == target and support.flights[flights + 1]["target"] == end and support.flights[flights + 2]["target"] == target, "Individual guns distribute their shells along the mission footprint")
	_check(is_equal_approx(mission.next_round, first_launch + 5.0), "The next volley is scheduled from its first gun, without cadence drift")
	support.panel._select_guns(2)
	_check(mission.guns == 3, "Changing the panel selection does not alter an already assigned mission")
	mission.elapsed = first_launch + 4.99
	support._process(0.0)
	_check(mission.fired == 3, "A second volley cannot begin before the selected intensity interval")
	mission.elapsed = first_launch + 5.0
	support._process(0.0)
	_check(mission.fired == 4 and mission.pending_guns == 2, "The next interval starts another coordinated volley")
	support.cease(1)
	mission.elapsed += 1.0
	support._process(0.0)
	_check(support.pending_volley.is_empty() and mission.pending_guns == 0 and weapon.ammunition == stock - 4 and support.flights.size() == flights + 4, "Cease cancels unlaunched guns without removing airborne shells or spending their ammunition")
	weapon.ammunition = 2
	support.request(1, target, 15.0, FireSupportMission.Intensity.INTENSE, [], FireSupportMission.Shape.POINT, target, 1, 3)
	mission = support.asset_mission(1)
	mission.elapsed = mission.next_round
	support._process(0.0)
	mission.elapsed += 0.6
	support._process(0.0)
	_check(mission.fired == 2 and not mission.active and weapon.ammunition == 0 and support.pending_volley.is_empty(), "A final partial volley uses only the shells actually remaining in the battery")
	weapon.ammunition = 6
	support.request(1, target, 0.1, FireSupportMission.Intensity.INTENSE, [], FireSupportMission.Shape.POINT, target, 1, 3)
	mission = support.asset_mission(1)
	mission.elapsed = mission.next_round
	support._process(0.0)
	mission.elapsed += 0.2
	support._process(0.0)
	_check(not mission.active and mission.fired == 1 and weapon.ammunition == 5 and support.pending_volley.is_empty(), "The duration limit cancels pending volley guns before they can launch late")
	weapon.ammunition = stock
	support.panel._open_asset(0)

func _right_click_at(point: Vector2) -> void:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.position = point
	click.global_position = point
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	get_viewport().push_input(click, true)
	click = click.duplicate() as InputEventMouseButton
	click.pressed = false
	get_viewport().push_input(click, true)

func _ready_gunner(soldier: Soldier) -> void:
	soldier.setup_weapon_task.done = true
	soldier.reload_task.done = true
	soldier.aquire_target_task.done = true
	soldier.rounds_in_mag = 1

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		(node as Timer).stop()
	for child: Node in node.get_children():
		_freeze(child)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
