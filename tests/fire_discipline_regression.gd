extends Node

class UnitProbe extends Unit:
	var clock_seconds: float = 100.0

	func _now() -> float:
		return clock_seconds

	func set_cover(_value: int) -> void:
		pass

	func _make_squad() -> void:
		pass

class FireProbe extends SquadFireController:
	var loops_started: int = 0
	var loops_stopped: int = 0
	var impacts: int = 0

	func _on_fire_weapon(_weapon: WeaponSpec, _position: Vector2, automatic: bool, _id: int, _owner: Node2D) -> void:
		if automatic:
			loops_started += 1

	func _on_stop_mg_loop(_weapon: WeaponSpec, _position: Vector2, _id: int, _owner: Node2D) -> void:
		loops_stopped += 1

	func fire_at(rounds: int, _weapon: WeaponSpec, _grenade: bool, _cell: Vector2i, _distance: int, _cover: int, _targets: Array[Unit], _origin: Vector2 = Vector2.INF) -> void:
		impacts += rounds

var checks: int = 0
var failures: int = 0
var ground: HexagonTileMapLayer
var shooter: UnitProbe
var enemy: UnitProbe
var other: UnitProbe
var fire: FireProbe


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	ground = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_size = Vector2i(64, 64)
	ground.pathfinding_enabled = false
	add_child(ground)
	LOSHelper.ground_layer = ground
	Globals.team_player = Globals.Team.AXIS
	shooter = UnitProbe.new()
	shooter.stress_system = StressController.new()
	shooter.team = Globals.Team.AXIS
	shooter.current_cube = ground.map_to_cube(shooter.current_hex)
	enemy = UnitProbe.new()
	enemy.team = Globals.Team.ALLIES
	enemy.stress_system = StressController.new()
	other = UnitProbe.new()
	other.team = Globals.Team.ALLIES
	fire = FireProbe.new()
	fire.unit = shooter
	fire.stress_controller = shooter.stress_system
	shooter.squad_fire = fire
	add_child(fire)
	fire.set_process(false)
	_test_automatic_modes()
	_test_return_fire()
	await _test_burst_interruption()
	_test_explicit_orders()
	_test_personal_defense()
	_test_maintenance_and_morale()
	_test_fire_mission()
	await get_tree().create_timer(0.1).timeout
	fire.set_soldiers([])
	fire.calc.free()
	fire.free()
	shooter.stress_system.free()
	enemy.stress_system.free()
	shooter.free()
	enemy.free()
	other.free()
	Globals.unit_visible_enemies.clear()
	LOSHelper.los_lookup.clear()
	LOSHelper.ground_layer = null
	ground.free()
	await _test_controls_and_save()
	print("Fire discipline checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _prepare(path: String = "res://resources/weapons/m1_garand.tres", role: RankGrades.Role = RankGrades.Role.SOLDIER) -> Soldier:
	fire.set_soldiers([])
	fire.fire_support_mission = null
	fire.fire_support_hold = false
	fire.mission_support_fire = false
	fire.clear_target()
	shooter.fire_discipline = Unit.FireDiscipline.FIRE_AT_WILL
	shooter.setAttackState(Unit.AttackState.AUTO)
	shooter.squad_type = Globals.SquadType.Rifle
	shooter.tactical_state = SquadTacticalState.new()
	shooter.is_moving = false
	shooter.broken = false
	shooter.surrendered = false
	shooter.in_close_combat = false
	shooter.clock_seconds = 100.0
	shooter.stress_system.state = STATES.MoraleState.NORMAL
	_set_hex(enemy, Vector3i(4, -4, 0))
	_set_hex(other, Vector3i(-2, 2, 0))
	Globals.unit_visible_enemies = {shooter: [enemy]}
	LOSHelper.los_lookup = {shooter.current_hex: {
		enemy.current_hex: {"target_cover": 0, "target_concealment": 0, "hindrance": 0},
		other.current_hex: {"target_cover": 0, "target_concealment": 0, "hindrance": 0}
	}}
	var weapon: WeaponSpec = (load(path) as WeaponSpec).create_runtime()
	weapon.ammunition = 200
	weapon.projectile_speed = 1000000.0
	var soldier: Soldier = Soldier.new(0, "Fire discipline probe", RankGrades.Grade.SOLDIER, role, weapon, shooter, shooter.team)
	soldier.setup_weapon_task.done = true
	soldier.reload_task.done = true
	fire.set_soldiers([soldier])
	fire.set_target_unit(enemy)
	_ready_weapon(soldier)
	fire.loops_started = 0
	fire.loops_stopped = 0
	return soldier


func _set_hex(unit: Unit, cube: Vector3i) -> void:
	unit.current_cube = cube
	unit.current_hex = ground.cube_to_map(cube)
	unit.position = ground.map_to_local(unit.current_hex)
	var row: Dictionary = LOSHelper.los_lookup.get(shooter.current_hex, {})
	row[unit.current_hex] = {"target_cover": 0, "target_concealment": 0, "hindrance": 0}
	LOSHelper.los_lookup[shooter.current_hex] = row


func _ready_weapon(soldier: Soldier) -> void:
	soldier.aquire_target_task.done = true
	soldier.cycle_remaining_s = 0.0
	soldier.reaim_remaining_s = 0.0
	soldier.weapon_raised = true


func _simulate(seconds: float) -> void:
	for frame: int in range(ceili(seconds * 60.0)):
		shooter.clock_seconds += 1.0 / 60.0
		fire._process(1.0 / 60.0)


func _receive_fire(source: Unit, age: float = 0.0) -> void:
	shooter.tactical_state.register_incoming_fire(source.global_position - shooter.global_position, shooter._now() - age)


func _test_automatic_modes() -> void:
	var soldier: Soldier = _prepare()
	_check(shooter.fire_discipline == Unit.FireDiscipline.FIRE_AT_WILL, "New squads default to fire at will")
	_simulate(0.1)
	_check(soldier.weapon.ammunition < 200, "Fire at will retains automatic fire against visible enemies")
	soldier = _prepare()
	shooter.set_watch_direction(enemy.position)
	shooter.set_fire_discipline(Unit.FireDiscipline.HOLD_FIRE)
	_simulate(3.0)
	_check(soldier.weapon.ammunition == 200 and not soldier.burst_active, "Hold fire prevents automatic ammunition use")
	_check(fire._can_track_target(enemy) and Globals.unit_visible_enemies[shooter].has(enemy) and shooter.has_watch_order(), "Holding fire preserves observed contacts and watch assignments")
	fire.set_target_unit(enemy)
	_ready_weapon(soldier)
	_simulate(0.1)
	_check(soldier.weapon.ammunition == 200, "An automatic target assigned by another system cannot bypass hold fire")
	shooter.set_fire_discipline(Unit.FireDiscipline.FIRE_AT_WILL)
	_simulate(3.0)
	_check(soldier.weapon.ammunition < 200, "Restoring fire at will wakes selection and allows normal individual preparation")


func _test_return_fire() -> void:
	var soldier: Soldier = _prepare()
	Globals.unit_visible_enemies[shooter] = [enemy, other]
	shooter.set_fire_discipline(Unit.FireDiscipline.RETURN_FIRE)
	_simulate(1.0)
	_check(soldier.weapon.ammunition == 200, "Return fire does not initiate an engagement from a sighting alone")
	_receive_fire(enemy)
	_check(fire.automatic_fire_allowed(enemy) and not fire.automatic_fire_allowed(other), "Incoming fire authorizes the matching visible bearing without authorizing an unrelated contact")
	fire.fire_timer = 0.0
	fire.handle_auto_fire(0.0, shooter, shooter.current_hex, shooter.weapon_range, shooter.fire_rate, shooter.firepower)
	_check(fire.target_unit == enemy, "Target selection chooses the attacker bearing even when another contact is closer")
	_ready_weapon(soldier)
	_simulate(0.1)
	_check(soldier.weapon.ammunition < 200, "The actual scheduler emits return fire once handling is ready")
	shooter.clock_seconds += SquadTacticalState.RETURN_FIRE_WINDOW_SECONDS
	var ammo: int = soldier.weapon.ammunition
	_ready_weapon(soldier)
	_simulate(1.0)
	_check(soldier.weapon.ammunition == ammo and not fire.automatic_fire_allowed(enemy), "Return-fire permission expires without renewed incoming fire")
	_receive_fire(enemy)
	Globals.unit_visible_enemies[shooter] = [other]
	_check(not fire.automatic_fire_allowed(enemy), "Incoming fire cannot authorize a target the squad cannot currently see")
	_simulate(1.0)
	_check(soldier.weapon.ammunition == ammo, "A hidden shooter cannot cause fire at another observed enemy")
	Globals.unit_visible_enemies[shooter] = [enemy]
	LOSHelper.los_lookup[shooter.current_hex].erase(enemy.current_hex)
	_check(not fire.automatic_fire_allowed(enemy), "A stale visible contact behind blocked geometry cannot receive return fire")
	var state: SquadTacticalState = SquadTacticalState.new()
	state.register_incoming_fire(Vector2.RIGHT, 10.0)
	_check(state.has_recent_fire_from(Vector2.from_angle(deg_to_rad(29.0)), 12.0) and not state.has_recent_fire_from(Vector2.from_angle(deg_to_rad(31.0)), 12.0), "Return fire uses a bounded thirty-degree half-angle")
	_check(not state.has_recent_fire_from(Vector2.RIGHT, 18.0) and not state.has_recent_fire_from(Vector2.RIGHT, 9.0), "Expired and future incoming-fire evidence cannot authorize shooting")


func _test_burst_interruption() -> void:
	var soldier: Soldier = _prepare("res://resources/weapons/mg34.tres", RankGrades.Role.GUNNER)
	_check(fire._start_burst(soldier, 8, enemy.current_hex, enemy, false, 4, 0, [enemy]) == 1 and fire.loops_started == 1, "A live automatic burst begins with one emitted round and owned audio")
	shooter.set_fire_discipline(Unit.FireDiscipline.HOLD_FIRE)
	_check(not soldier.burst_active and fire.loops_stopped == 1, "Hold fire immediately stops an automatic burst and its sound")
	var ammo: int = soldier.weapon.ammunition
	_simulate(0.2)
	_check(soldier.weapon.ammunition == ammo, "Interrupted bursts spend no further ammunition")
	var impacts_before: int = fire.impacts
	await get_tree().create_timer(0.05).timeout
	_check(fire.impacts > impacts_before, "Rounds already airborne still land after hold fire")
	soldier = _prepare("res://resources/weapons/mg34.tres", RankGrades.Role.GUNNER)
	shooter.set_fire_discipline(Unit.FireDiscipline.RETURN_FIRE)
	_receive_fire(enemy)
	fire.set_target_unit(enemy)
	fire._start_burst(soldier, 8, enemy.current_hex, enemy, false, 4, 0, [enemy])
	shooter.clock_seconds += SquadTacticalState.RETURN_FIRE_WINDOW_SECONDS
	_check(fire._advance_burst(soldier, 0.2) == 0 and not soldier.burst_active, "Return-fire expiry stops subsequent rounds of an active burst")


func _test_explicit_orders() -> void:
	var soldier: Soldier = _prepare()
	shooter.set_fire_discipline(Unit.FireDiscipline.HOLD_FIRE)
	shooter.order(Globals.UnitCmd.FIRE_AT_HEX, enemy.current_hex)
	_ready_weapon(soldier)
	_simulate(0.1)
	_check(shooter.attackState == Unit.AttackState.MANUAL_TRACK and soldier.weapon.ammunition < 200 and shooter.fire_discipline == Unit.FireDiscipline.HOLD_FIRE, "An explicit tracked Fire order overrides hold fire without changing the persistent setting")
	Globals.unit_visible_enemies[shooter] = [other]
	var ammo: int = soldier.weapon.ammunition
	_simulate(1.0)
	_check(shooter.attackState == Unit.AttackState.AUTO and soldier.weapon.ammunition == ammo, "Losing the ordered target restores hold fire instead of engaging another contact")
	soldier = _prepare()
	shooter.set_fire_discipline(Unit.FireDiscipline.HOLD_FIRE)
	var cell: Vector2i = ground.cube_to_map(Vector3i(0, -3, 3))
	shooter.order(Globals.UnitCmd.FIRE_AT_HEX, cell)
	shooter.attack_ground_rounds_budget = 1
	_ready_weapon(soldier)
	_simulate(0.1)
	_check(soldier.weapon.ammunition == 199 and shooter.attackState == Unit.AttackState.AUTO and not fire.has_fire_order_override(), "Completing the ground-fire budget ends the override and resumes hold fire")
	soldier = _prepare("res://resources/weapons/mg34.tres", RankGrades.Role.GUNNER)
	shooter.setAttackState(Unit.AttackState.MANUAL_TRACK)
	fire._start_burst(soldier, 8, enemy.current_hex, enemy, false, 4, 0, [enemy])
	shooter.set_fire_discipline(Unit.FireDiscipline.HOLD_FIRE)
	_check(soldier.burst_active and fire._advance_burst(soldier, 0.15) > 0, "Changing the persistent setting does not cancel an explicit tracked Fire order")
	shooter.setAttackState(Unit.AttackState.AUTO)
	_check(fire._advance_burst(soldier, 0.2) == 0 and not soldier.burst_active, "Cancelling the Fire order removes its burst override")


func _test_personal_defense() -> void:
	for squad_type: Globals.SquadType in [Globals.SquadType.MG, Globals.SquadType.MORTAR, Globals.SquadType.ANTITANK]:
		var soldier: Soldier = _prepare()
		shooter.squad_type = squad_type
		_set_hex(enemy, Vector3i(1, -1, 0))
		shooter.set_fire_discipline(Unit.FireDiscipline.HOLD_FIRE)
		_simulate(2.0)
		_check(soldier.weapon.ammunition == 200, "Hold fire blocks personal defence in support squad type " + str(squad_type))
		shooter.set_fire_discipline(Unit.FireDiscipline.RETURN_FIRE)
		_receive_fire(other)
		_simulate(1.0)
		_check(soldier.weapon.ammunition == 200, "Support sidearms cannot retaliate at a close enemy on an unrelated bearing")
		_receive_fire(enemy)
		_simulate(3.0)
		_check(soldier.weapon.ammunition < 200, "Support sidearms can return fire at a visible close enemy on the received bearing")
	var soldier: Soldier = _prepare()
	shooter.squad_type = Globals.SquadType.MG
	_set_hex(other, Vector3i(-1, 1, 0))
	Globals.unit_visible_enemies[shooter] = [enemy, other]
	shooter.set_fire_discipline(Unit.FireDiscipline.HOLD_FIRE)
	shooter.order(Globals.UnitCmd.FIRE_AT_HEX, enemy.current_hex)
	_simulate(2.0)
	_check(soldier.weapon.ammunition == 200, "An explicit distant target does not authorize support sidearms to shoot another close enemy")


func _test_maintenance_and_morale() -> void:
	var soldier: Soldier = _prepare()
	shooter.set_fire_discipline(Unit.FireDiscipline.HOLD_FIRE)
	soldier.rounds_in_mag = 0
	soldier.start_reload()
	_simulate(soldier.weapon.reload_s + 0.5)
	_check(soldier.reload_task.done and soldier.rounds_in_mag > 0 and soldier.weapon.ammunition == 200, "Reloading continues while the squad holds fire")
	soldier = _prepare("res://resources/weapons/m1918a1_bar.tres")
	shooter.set_fire_discipline(Unit.FireDiscipline.HOLD_FIRE)
	soldier.weapon.automatic_fire.barrel_heat[0] = 50.0
	_simulate(1.0)
	_check(soldier.weapon.automatic_fire.heat() < 50.0 and soldier.weapon.ammunition == 200, "Automatic weapons cool without firing under hold fire")
	shooter.in_close_combat = true
	_check(not shooter.set_fire_discipline(Unit.FireDiscipline.FIRE_AT_WILL), "Close combat prevents discipline changes")
	shooter.in_close_combat = false
	shooter.broken = true
	_check(not shooter.set_fire_discipline(Unit.FireDiscipline.FIRE_AT_WILL), "Routed squads reject discipline changes")
	shooter.broken = false
	shooter.surrendered = true
	_check(not shooter.set_fire_discipline(Unit.FireDiscipline.FIRE_AT_WILL), "Surrendered squads reject discipline changes")
	shooter.surrendered = false
	shooter.stress_system.state = STATES.MoraleState.PINNED
	_check(shooter.set_fire_discipline(Unit.FireDiscipline.RETURN_FIRE), "Pinned squads may change discipline without bypassing protective soldier behaviour")
	_check(not shooter.set_fire_discipline(99 as Unit.FireDiscipline), "Invalid discipline values are rejected")


func _test_fire_mission() -> void:
	var soldier: Soldier = _prepare("res://resources/weapons/m2_60mm_mortar.tres", RankGrades.Role.GUNNER)
	shooter.squad_type = Globals.SquadType.MORTAR
	shooter.set_fire_discipline(Unit.FireDiscipline.HOLD_FIRE)
	shooter.fire_mortar(enemy.current_hex)
	var mission: FireSupportMission = FireSupportMission.new()
	mission.target = other.current_hex
	mission.remaining = 2
	mission.onboard_guns = [soldier]
	fire.fire_support_mission = mission
	_ready_weapon(soldier)
	fire._tick_soldiers(0.1)
	_check(soldier.weapon.ammunition == 199 and mission.fired == 1, "An explicitly assigned mortar mission overrides hold fire at its scheduled target")
	mission.stop()
	_check(not fire.has_fire_order_override(), "A stopped fire mission releases its discipline override")


func _test_controls_and_save() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	scenario.axis_ai_status = Scenario.AIStatus.OFF
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	var controller: Node2D = world.game_controller
	var friendly: Unit = Globals.get_units_for_team(Globals.team_player)[1]
	var hostile: Unit = Globals.get_units_for_team(Globals.team_enemy)[0]
	controller._select_unit(friendly)
	var details: PanelContainer = world.ui.unit_details
	details.show_unit_detail(friendly, false)
	details.fire_discipline.item_selected.emit(details.fire_discipline.get_item_index(Unit.FireDiscipline.HOLD_FIRE))
	_check(friendly.fire_discipline == Unit.FireDiscipline.HOLD_FIRE and details.fire_discipline_row.visible and not details.fire_discipline.disabled, "The squad details control changes friendly fire discipline")
	_check(details.fire_discipline_status.text == "Observe without automatic fire", "The details panel explains the active discipline")
	friendly.setAttackState(Unit.AttackState.MANUAL_GROUND)
	friendly.squad_fire.set_target_hex(hostile.current_hex)
	details._refresh_summary()
	_check(details.fire_discipline_status.text == "Explicit Fire order overrides discipline", "The panel explains an active explicit-order override")
	_check(controller.order_via_option_wheel(friendly.current_hex, WheelOption.Option.STOP) and friendly.fire_discipline == Unit.FireDiscipline.HOLD_FIRE, "Stop cancels firing without resetting discipline")
	var moved: bool = false
	for neighbor: Vector2i in world.ground_layer.get_surrounding_cells(friendly.current_hex):
		if MatchInteractionHandler.command_restriction(controller, neighbor, WheelOption.Option.MOVE_NORMAL).is_empty():
			moved = controller.order_via_option_wheel(neighbor, WheelOption.Option.MOVE_NORMAL)
			break
	_check(moved and friendly.fire_discipline == Unit.FireDiscipline.HOLD_FIRE, "A movement order preserves the squad's discipline")
	controller.order_via_option_wheel(friendly.current_hex, WheelOption.Option.STOP)
	friendly.set_watch_direction(Vector2.RIGHT)
	friendly.set_watch_width(Unit.WatchWidth.WIDE)
	var saved: UnitSaveData = friendly.create_save_data()
	DirAccess.make_dir_recursive_absolute("user://tests")
	_check(ResourceSaver.save(saved, "user://tests/fire_discipline.tres") == OK, "Discipline can be serialized to disk")
	var loaded: UnitSaveData = ResourceLoader.load("user://tests/fire_discipline.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as UnitSaveData
	friendly.set_fire_discipline(Unit.FireDiscipline.FIRE_AT_WILL)
	friendly.apply_save_data(loaded)
	_check(friendly.fire_discipline == Unit.FireDiscipline.HOLD_FIRE and friendly.watch_direction == Vector2.RIGHT and friendly.watch_width == Unit.WatchWidth.WIDE, "Loading restores fire discipline alongside the existing watch order")
	loaded.fire_discipline = Unit.FireDiscipline.RETURN_FIRE
	friendly.apply_save_data(loaded)
	_check(friendly.fire_discipline == Unit.FireDiscipline.RETURN_FIRE, "Loading also restores return fire")
	loaded.fire_discipline = 99
	friendly.apply_save_data(loaded)
	_check(friendly.fire_discipline == Unit.FireDiscipline.FIRE_AT_WILL and UnitSaveData.new().fire_discipline == Unit.FireDiscipline.FIRE_AT_WILL, "Invalid values and older saves default to fire at will")
	controller.end_game_handled = true
	details._refresh_summary()
	details._on_fire_discipline_selected(details.fire_discipline.get_item_index(Unit.FireDiscipline.HOLD_FIRE))
	_check(details.fire_discipline.disabled and friendly.fire_discipline == Unit.FireDiscipline.FIRE_AT_WILL, "Mission completion disables discipline changes even through a stale UI signal")
	controller.end_game_handled = false
	Debug.enemy_selectable = false
	Globals.unit_visible_enemies[friendly] = [hostile]
	controller.show_visible_units()
	details.show_unit_detail(hostile, false)
	var previous: Unit.FireDiscipline = hostile.fire_discipline
	details._on_fire_discipline_selected(details.fire_discipline.get_item_index(Unit.FireDiscipline.HOLD_FIRE))
	_check(not details.fire_discipline_row.visible and hostile.fire_discipline == previous, "Enemy inspection hides discipline and cannot modify it")
	details.show_unit_detail(friendly, false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(details.fire_discipline.get_rect().end.x <= details.fire_discipline_row.size.x, "The discipline controls fit inside the squad panel")
	friendly.tactical_state = SquadTacticalState.new()
	friendly.set_fire_discipline(Unit.FireDiscipline.RETURN_FIRE)
	Globals.unit_visible_enemies[friendly] = [hostile]
	LOSHelper.los_lookup[friendly.current_hex] = {hostile.current_hex: {"target_cover": 0, "target_concealment": 0, "hindrance": 0}}
	_check(not friendly.squad_fire.automatic_fire_allowed(hostile), "A real match squad waits for incoming-fire evidence")
	var rifle: WeaponSpec = (load("res://resources/weapons/m1_garand.tres") as WeaponSpec).create_runtime()
	hostile.squad_fire.fire_at(1, rifle, false, friendly.current_hex, 4, 0, [friendly], hostile.global_position)
	_check(friendly.squad_fire.automatic_fire_allowed(hostile), "An actual resolved incoming round opens return fire against a currently observed source bearing")
	Globals.unit_visible_enemies[friendly] = []
	_check(not friendly.squad_fire.automatic_fire_allowed(hostile), "Actual incoming fire still cannot expose a hidden shooter")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


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
