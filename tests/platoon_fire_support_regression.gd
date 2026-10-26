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
	scenario.offboard_batteries = []
	var deployment: Unit
	for unit: Node in scenario.get_units():
		if unit is Unit and unit.team == scenario.player_team:
			deployment = unit
			break
	var mortars: Array[Unit] = []
	for identity: Vector3i in [Vector3i(0, 9, 1), Vector3i(0, 9, 2), Vector3i(0, 10, 1), Vector3i(1, 9, 1)]:
		var unit: Unit = load("res://scenes/game/units/unit.tscn").instantiate() as Unit
		unit.team = scenario.player_team
		unit.company = identity.x as Unit.Company
		unit.platoon = identity.y
		unit.squad = identity.z
		unit.squad_type = Globals.SquadType.MORTAR
		unit.squad_loadout = load("res://resources/squads/united_states/light_mortar_squad.tres") as SquadLoadoutSpec
		unit.current_hex = deployment.current_hex
		unit.position = deployment.position
		scenario.units.add_child(unit)
		mortars.append(unit)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	var support: FireSupportController = world.game_controller.fire_support
	_check(support.assets.size() == 3, "Four squads form three batteries: same platoon combined, other platoons and companies separate")
	var group: int = -1
	for index: int in range(support.assets.size()):
		if (support.assets[index]["units"] as Array[Unit]).has(mortars[0]):
			group = index
	_check(group >= 0 and (support.assets[group]["units"] as Array[Unit]).size() == 2, "Both guns from Company A Platoon 9 belong to one battery")
	_check(support.assets[group]["name"].contains("Platoon 9") and support.available_guns(group) == 2, "The battery is identified by formation and exposes both guns")
	var gunners: Array[Soldier] = support.eligible_guns(group, [])
	for gunner: Soldier in gunners:
		gunner.weapon.ammunition = 10
		gunner.weapon.projectile_speed = 100000
		_ready_gunner(gunner)
	_check(support.ammunition(group) == 20, "The battery ammunition counter aggregates both real weapons")
	var target: Vector2i = mortars[0].current_hex
	var ground: HexagonTileMapLayer = world.game_controller.ground_layer
	for cell: Vector2i in ground.get_used_cells():
		if ground.cube_distance(mortars[0].current_cube, ground.map_to_cube(cell)) == 2 and LOSHelper.find_units_at(cell).is_empty():
			target = cell
			break
	_check(support.request(group, target, 15.0, FireSupportMission.Intensity.INTENSE, [], FireSupportMission.Shape.POINT, target, 1, 2), "A platoon battery accepts a two-gun mission")
	var mission: FireSupportMission = support.asset_mission(group)
	_check(mortars[0].squad_fire.fire_support_mission == mission and mortars[1].squad_fire.fire_support_mission == mission, "Both native squads share the same battery mission")
	_check(mortars[2].squad_fire.fire_support_mission == null and mortars[3].squad_fire.fire_support_mission == null, "Other formations do not receive the battery order")
	for gunner: Soldier in gunners:
		_ready_gunner(gunner)
	gunners[1].reload_task.done = false
	gunners[1].reload_task.start_time_s = 2.0
	support._process(0.0)
	_check(mission.onboard_due.is_empty(), "The battery waits for both selected crews instead of firing disconnected individual missions")
	_ready_gunner(gunners[1])
	support._process(0.0)
	_check(mission.pending_guns == 2, "Ready crews receive coordinated volley permissions")
	var first: int = await mortars[0].squad_fire._try_fire_soldier(0.1, gunners[0], true, 1, 2, 2, 0)
	var early: int = await mortars[1].squad_fire._try_fire_soldier(0.1, gunners[1], true, 1, 2, 2, 0)
	_check(first == 1 and early == 0, "The first gun fires while the second waits for its short volley offset")
	mission.elapsed = 0.6
	support._process(0.0)
	var second: int = await mortars[1].squad_fire._try_fire_soldier(0.1, gunners[1], true, 1, 2, 2, 0)
	_check(second == 1 and mission.fired == 2 and support.ammunition(group) == 18 and mission.next_round == 5.0, "Both native weapons fire one shell with shared counters and stable volley cadence")
	support.cease(group)
	_check(mortars[0].squad_fire.fire_support_mission == null and mortars[1].squad_fire.fire_support_mission == null, "Cease fire detaches every squad in the battery")
	_check(support.request(group, target, 15.0, FireSupportMission.Intensity.INTENSE), "A battery can assign just one gun")
	mission = support.asset_mission(group)
	_check(mission.onboard_guns.size() == 1 and mortars[1].squad_fire.fire_support_mission == null, "Unselected guns are not included in a one-gun order")
	support.cease(group)
	support.request(group, target, 15.0, FireSupportMission.Intensity.INTENSE, [], FireSupportMission.Shape.POINT, target, 1, 2)
	mission = support.asset_mission(group)
	for gunner: Soldier in gunners:
		_ready_gunner(gunner)
	support._process(0.0)
	mortars[1].broken = true
	support._process(0.0)
	_check(mission.active and mission.onboard_guns.size() == 1 and mission.pending_guns == 1, "An unavailable crew is removed without cancelling the surviving gun's volley")
	mortars[1].broken = false
	support.cease(group)
	support.request(group, target, 15.0, FireSupportMission.Intensity.INTENSE, [], FireSupportMission.Shape.POINT, target, 1, 2)
	mortars[1].fire_mortar(mortars[1].current_hex)
	support._process(0.0)
	_check(mortars[1].squad_fire.fire_support_mission == null and mortars[1].squad_fire.mortar_target_hex == mortars[1].current_hex and mortars[0].squad_fire.fire_support_mission != null, "A replacement order detaches only that squad and preserves its new target")
	support.cease(group)
	await _test_fire_button(support, group, target)
	if OS.get_cmdline_user_args().has("--capture"):
		support.panel._open_asset(group)
		var point: Vector2 = ground.get_global_transform_with_canvas() * ground.map_to_local(target)
		support.pick_target(point)
		world.ui.get_node("Control/OrderFeedback").hide()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/acl-platoon-support-hud.png")
	main.queue_free()
	await get_tree().process_frame
	print("Platoon support checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)

func _test_fire_button(support: FireSupportController, group: int, target: Vector2i) -> void:
	support.panel._close()
	support.panel._open_asset(group)
	var ground: HexagonTileMapLayer = support.host.ground_layer
	support.pick_target(ground.get_global_transform_with_canvas() * ground.map_to_local(target))
	await get_tree().process_frame
	await get_tree().process_frame
	var button: Button = support.panel.fire_button
	_check(not button.disabled, "A prepared valid mission enables the Fire mission button")
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	get_viewport().push_input(press, true)
	_check(button.is_pressed(), "The actual GUI mouse press arms the mission button")
	support.panel.refresh()
	_check(button.is_pressed(), "A polling refresh must not cancel a held Fire mission button")
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.position = point
	release.global_position = point
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	get_viewport().push_input(release, true)
	var mission: FireSupportMission = support.asset_mission(group)
	_check(mission != null and mission.active and not support.has_target, "One press and release starts the mission even when a refresh occurs between them")
	support.cease(group)

func _ready_gunner(gunner: Soldier) -> void:
	gunner.setup_weapon_task.done = true
	gunner.reload_task.done = true
	gunner.aquire_target_task.done = true
	gunner.rounds_in_mag = 1

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
