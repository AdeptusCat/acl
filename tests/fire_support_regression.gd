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
	_check(support.panel.asset_buttons[0].icon == FireSupportPanel.MORTAR_ICON and support.panel.asset_buttons[1].icon == FireSupportPanel.MORTAR_ICON and support.panel.asset_buttons[2].icon == FireSupportPanel.HOWITZER_ICON, "Support icons distinguish actual mortar and howitzer weapon families")
	support.panel.asset_buttons[2].pressed.emit()
	_check(support.panel.tray.visible and support.selected_asset == 2 and support.panel.assets.selected == 2, "Clicking a howitzer icon opens its battery directly")
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
	var point: Vector2 = host.ground_layer.get_global_transform_with_canvas() * host.ground_layer.map_to_local(target)
	host._on_mouse_button_left_pressed(point)
	_check(support.has_target and support.target == target and host.selected_unit == selected, "Picking a fire mission hex preserves the selected infantry squad")
	_check(support.preview(0, mortar.current_hex).contains("FRIENDLY"), "The preview identifies friendly troops in the struck hex")
	_check(support.request(0, target, FireSupportMission.Mode.QUICK), "A quick onboard mission is accepted without an artificial call-in delay")
	var quick: FireSupportMission = support.asset_mission(0)
	_check(not support.request(0, target, FireSupportMission.Mode.QUICK), "A busy battery rejects overlapping fire missions")
	gunner.setup_weapon_task.done = false
	gunner.setup_weapon_task.remaining_time_s = 2.0
	var blocked: int = await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
	_check(blocked == 0 and quick.fired == 0, "Mission requests do not bypass real mortar setup")
	for shot: int in range(3):
		_ready_gunner(gunner)
		var fired: int = await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
		_check(fired == 1, "Quick missions launch actual mortar rounds")
	_ready_gunner(gunner)
	var extra: int = await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
	_check(quick.fired == 3 and not quick.active and extra == 0 and gunner.weapon.ammunition == 27, "Quick missions spend exactly three rounds with no extra shot")
	support._process(0.01)
	_check(mortar.squad_fire.fire_support_hold, "A completed battery stays silent until a new fire order")
	_check(support.request(0, target, FireSupportMission.Mode.STANDARD), "A completed battery can immediately receive another mission")
	_ready_gunner(gunner)
	await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
	_ready_gunner(gunner)
	var early: int = await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
	_check(early == 0 and support.asset_mission(0).remaining == 5, "Standard missions space launches and retain a six-round budget")
	support.cease(0)
	_check(support.request(0, target, FireSupportMission.Mode.HARASSING), "Harassing fire can replace a ceased mission")
	_ready_gunner(gunner)
	await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0)
	var harassment: FireSupportMission = support.asset_mission(0)
	_check(harassment.next_round >= 15.0 and harassment.next_round <= 25.0, "Harassing launches schedule an occasional round 15–25 seconds later")
	_ready_gunner(gunner)
	_check(await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0) == 0, "Harassing mortars cannot fire continuously between scheduled rounds")
	support._process(harassment.next_round + 0.01)
	_ready_gunner(gunner)
	_check(await mortar.squad_fire._try_fire_soldier(0.1, gunner, true, 1, 1, 2, 0) == 1, "The next harassing round uses the normal firing pipeline")
	support.cease(0)
	var enemy: Unit = Globals.get_units_for_team(Globals.get_enemy_team(Globals.team_player))[0]
	_check(support.request(1, enemy.current_hex, FireSupportMission.Mode.QUICK), "Offboard missions do not require selecting or inventing a map counter")
	var before: int = support.ammunition(1)
	support._process(5.0)
	_check(support.ammunition(1) == before, "Offboard batteries honor their authored response delay")
	support._process(1.0)
	_check(support.ammunition(1) == before - 1 and support.flights.size() == 1, "Offboard launch spends ammunition and creates an in-flight shell")
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
	support._process(4.0)
	await get_tree().process_frame
	_check(support.flights.is_empty() and enemy.stress_system.under_fire, "Cease fire leaves airborne shells to resolve through the real impact system")
	(support.assets[2]["weapon"] as WeaponSpec).ammunition = 0
	_check(not support.request(2, target, FireSupportMission.Mode.QUICK), "Empty offboard batteries reject fire requests")
	support.selected_asset = 0
	support.has_target = true
	support.target = target
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
	support.has_target = true
	support.target = target
	support.choosing_target = false
	support.selected_mode = FireSupportMission.Mode.HARASSING
	support.panel.mode.select(2)
	support.panel.refresh()
	if OS.get_cmdline_user_args().has("--capture"):
		world.ui.get_node("Control/OrderFeedback").hide()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/acl-fire-support-hud.png")
	main.queue_free()
	await get_tree().process_frame
	print("Fire support checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)

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
