extends Node

class UnitProbe extends Unit:
	func set_cover(_value: int) -> void:
		pass

class FireProbe extends SquadFireController:
	var times: Array[float] = []
	var loops_started: int = 0
	var loops_stopped: int = 0

	func _on_fire_weapon(_weapon: WeaponSpec, _position: Vector2, _auto: bool, _id: int, _owner: Node2D) -> void:
		loops_started += 1

	func _on_stop_mg_loop(_weapon: WeaponSpec, _position: Vector2, _id: int, _owner: Node2D) -> void:
		loops_stopped += 1

	func _resolve_airborne_round(_weapon: WeaponSpec, _grenade: bool, _cell: Vector2i, _distance: int, _cover: int, _targets: Array[Unit], _origin: Vector2, _life: float) -> void:
		pass

	func observe_shot(_weapon: WeaponSpec, _cell: Vector2i, _origin: Vector2, _impact: Vector2) -> void:
		times.append(_now_s)

const PATHS: Array[String] = ["res://resources/weapons/mg34.tres", "res://resources/weapons/mg34_heavy.tres", "res://resources/weapons/m1919a4.tres", "res://resources/weapons/m1918a1_bar.tres"]

var checks: int = 0
var failures: int = 0
var ground: HexagonTileMapLayer
var shooter: Unit
var enemy: Unit
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
	shooter = UnitProbe.new()
	shooter.current_hex = Vector2i.ZERO
	shooter.team = Globals.Team.AXIS
	shooter.stress_system = StressController.new()
	shooter.tactical_state = SquadTacticalState.new()
	enemy = UnitProbe.new()
	enemy.team = Globals.Team.ALLIES
	enemy.members_alive = 8
	enemy.stress_system = StressController.new()
	_set_enemy_hex(Vector2i(0, 4))
	fire = FireProbe.new()
	fire.unit = shooter
	fire.stress_controller = shooter.stress_system
	shooter.squad_fire = fire
	add_child(fire)
	fire.set_process(false)
	fire.fire_shot.connect(fire.observe_shot)
	_test_runtime_and_barrels()
	_test_heat_and_handling()
	_test_barrel_change_crew()
	_test_opportunities()
	_test_live_opportunity()
	_test_cadence()
	await get_tree().create_timer(0.2).timeout
	fire.set_soldiers([])
	fire.calc.free()
	fire.free()
	shooter.stress_system.free()
	enemy.stress_system.free()
	shooter.free()
	enemy.free()
	Globals.unit_visible_enemies.clear()
	LOSHelper.los_lookup.clear()
	LOSHelper.ground_layer = null
	print("Automatic fire checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _set_enemy_hex(cell: Vector2i) -> void:
	enemy.current_hex = cell
	enemy.current_cube = ground.map_to_cube(cell)
	enemy.position = ground.map_to_local(cell)
	LOSHelper.los_lookup = {shooter.current_hex: {cell: {"target_cover": 0, "target_concealment": 0, "hindrance": 0}}}
	Globals.unit_visible_enemies = {shooter: [enemy]}


func _soldier(path: String, role: RankGrades.Role = RankGrades.Role.GUNNER, index: int = 0) -> Soldier:
	var weapon: WeaponSpec = (load(path) as WeaponSpec).create_runtime()
	weapon.ammunition = 100000
	var soldier: Soldier = Soldier.new(index, "Fire test " + str(index), RankGrades.Grade.SOLDIER, role, weapon, shooter, shooter.team)
	soldier.setup_weapon_task.done = true
	return soldier


func _prepare(path: String, helpers: bool = true) -> Soldier:
	var gunner: Soldier = _soldier(path)
	var roster: Array[Soldier] = [gunner]
	if helpers:
		roster.append(_soldier("res://resources/weapons/kar98.tres", RankGrades.Role.LOADER, 1))
		for index: int in range(gunner.weapon.support_crew_optimal):
			roster.append(_soldier("res://resources/weapons/kar98.tres", RankGrades.Role.ASSISTANT, index + 2))
	fire.set_soldiers(roster)
	fire.casualties.clear()
	fire.target_unit = null
	shooter.is_moving = false
	shooter.broken = false
	shooter.surrendered = false
	shooter.stress_system.state = STATES.MoraleState.NORMAL
	enemy.is_moving = false
	enemy.stress_system.state = STATES.MoraleState.NORMAL
	enemy.stress_system.S_eff = 0.0
	fire.set_target_unit(enemy)
	gunner.aquire_target_task.done = true
	fire.times.clear()
	fire._now_s = 0.0
	return gunner


func _simulate(duration: float, fps: int = 60) -> void:
	for frame: int in range(int(duration * float(fps))):
		fire._now_s += 1.0 / float(fps)
		fire._tick_soldiers(1.0 / float(fps))


func _test_runtime_and_barrels() -> void:
	var bipod: WeaponSpec = (load(PATHS[0]) as WeaponSpec).create_runtime()
	var tripod: WeaponSpec = (load(PATHS[1]) as WeaponSpec).create_runtime()
	_check(bipod.heat_soft_limit == tripod.heat_soft_limit and bipod.heat_hard_limit == tripod.heat_hard_limit and bipod.barrel_cooling_per_s == tripod.barrel_cooling_per_s, "MG34 mounts share the same barrel thermal properties")
	_check(bipod.automatic_fire.barrel_heat.size() == 3 and tripod.automatic_fire.barrel_heat.size() == 3, "MG34 loadouts each carry two configurable spare barrels")
	var state: AutomaticFireState = bipod.automatic_fire
	state.barrel_heat[0] = bipod.heat_hard_limit
	_check(state.begin_barrel_change(bipod) and state.active_barrel == 0, "Selecting a spare does not instantly replace the barrel")
	_check(not state.advance_barrel_change(4.0, bipod) and state.active_barrel == 0, "Barrel change requires actual handling work")
	_check(state.advance_barrel_change(1.0, bipod) and state.active_barrel == 1 and state.barrel_heat[0] == bipod.heat_hard_limit, "Changing barrels retains the removed barrel's heat")
	state.barrel_heat[1] = bipod.heat_hard_limit
	_check(state.begin_barrel_change(bipod), "The second cold spare can be selected")
	state.advance_barrel_change(bipod.barrel_change_s, bipod)
	state.barrel_heat[2] = bipod.heat_hard_limit
	_check(not state.begin_barrel_change(bipod), "A finite set of hot barrels cannot provide another cold spare")
	state.advance(20.0, bipod)
	_check(state.barrel_heat[0] == bipod.heat_hard_limit - 20.0 and state.barrel_heat[1] == state.barrel_heat[0], "All installed and removed barrels cool independently with elapsed time")
	_check(tripod.automatic_fire.heat() == 0.0 and (load(PATHS[0]) as WeaponSpec).automatic_fire.heat() == 0.0, "Physical guns and cached definitions do not share thermal state")
	for path: String in [PATHS[2], PATHS[3]]:
		var weapon: WeaponSpec = (load(path) as WeaponSpec).create_runtime()
		weapon.automatic_fire.barrel_heat[0] = weapon.heat_hard_limit
		_check(weapon.automatic_fire.barrel_heat.size() == 1 and not weapon.automatic_fire.begin_barrel_change(weapon), weapon.name + " relies on cooling rather than an MG34 quick barrel change")


func _test_heat_and_handling() -> void:
	var gunner: Soldier = _prepare(PATHS[3])
	var weapon: WeaponSpec = gunner.weapon
	var state: AutomaticFireState = weapon.automatic_fire
	state.barrel_heat[0] = weapon.heat_hard_limit - weapon.heat_per_round
	_check(fire._start_burst(gunner, 8, enemy.current_hex, enemy, false, 4, 0, [enemy]) == 1, "The last safe round is emitted at the hard heat limit")
	fire._advance_burst(gunner, 1.0)
	_check(state.heat_locked and not gunner.burst_active and fire.times.size() == 1, "Heat stops a burst before further ammunition is spent")
	gunner.reaim_remaining_s = 0.0
	fire._try_fire_soldier(1.0, gunner, true, 1, 0, 4, 0)
	_check(gunner.weapon_state == Soldier.WeaponState.COOLING and gunner.combat_status() == "Cooling barrel", "A locked gun reports cooling and cannot immediately resume firing")
	gunner.rounds_in_mag = 0
	gunner.start_reload()
	gunner.advance_handling(weapon.reload_s, 1.0)
	_check(state.heat() == weapon.heat_hard_limit and state.heat_locked, "Reloading does not reset weapon heat")
	state.advance((weapon.heat_hard_limit - weapon.heat_resume - 1.0) / weapon.barrel_cooling_per_s, weapon)
	_check(state.heat_locked, "Cooling slightly below the stop threshold cannot bypass thermal hysteresis")
	state.advance(2.0 / weapon.barrel_cooling_per_s, weapon)
	_check(not state.heat_locked, "Firing resumes only after cooling to the lower resume threshold")
	state.barrel_heat[0] = 50.0
	gunner.behavior = Soldier.Behavior.COWERING
	fire._tick_soldiers(2.0)
	_check(is_equal_approx(state.heat(), 50.0 - weapon.barrel_cooling_per_s * 2.0), "Cowering does not suspend physical cooling")
	shooter.is_moving = true
	fire._tick_soldiers(2.0)
	_check(is_equal_approx(state.heat(), 50.0 - weapon.barrel_cooling_per_s * 4.0), "Movement does not suspend physical cooling")
	shooter.is_moving = false
	fire.casualties.append(gunner)
	var before: float = state.heat()
	fire._tick_soldiers(1.0)
	_check(is_equal_approx(state.heat(), before - weapon.barrel_cooling_per_s), "A weapon referenced by both its old and new crew cools only once per update")


func _test_barrel_change_crew() -> void:
	var gunner: Soldier = _prepare(PATHS[0])
	var helper: Soldier = fire.soldiers[1]
	var state: AutomaticFireState = gunner.weapon.automatic_fire
	state.barrel_heat[0] = gunner.weapon.heat_hard_limit
	fire._tick_soldiers(0.1)
	_check(state.swap_barrel == 1 and helper.barrel_change_assisting and helper.combat_status() == "Changing barrel", "The integrated MG34 reserves its available loader during barrel work")
	_check(fire.times.is_empty() and fire._try_fire_soldier(1.0, helper, false, 0, 0, 4, 0) == 0, "Neither gunner nor reserved helper can fire during the change")
	fire._tick_soldiers(1.0)
	_check(is_equal_approx(state.swap_remaining_s, gunner.weapon.barrel_change_s - 1.0), "An available helper gives full barrel change work speed")
	helper.behavior = Soldier.Behavior.COWERING
	fire._tick_soldiers(1.0)
	_check(not helper.barrel_change_assisting and is_equal_approx(state.swap_remaining_s, gunner.weapon.barrel_change_s - 1.0 - 1.0 / gunner.weapon.undercrew_penalty_mult), "A cowering helper slows existing barrel work without restarting it")
	gunner.behavior = Soldier.Behavior.COWERING
	var remaining: float = state.swap_remaining_s
	fire._tick_soldiers(1.0)
	_check(state.swap_remaining_s == remaining, "A cowering gunner suspends barrel handling work")
	gunner.behavior = Soldier.Behavior.ENGAGING
	helper.behavior = Soldier.Behavior.ENGAGING
	fire._tick_soldiers(remaining)
	_check(state.active_barrel == 1 and state.swap_barrel < 0 and state.barrel_heat[0] > 0.0, "The completed crew change installs the spare and preserves hot removed metal")
	_check(gunner.reaim_remaining_s > 0.0 and fire.times.is_empty(), "Completing barrel work cannot spend the same update again on aiming or firing")
	var replacement: Soldier = _soldier("res://resources/weapons/kar98.tres")
	replacement.weapon = gunner.weapon
	_check(replacement.weapon.automatic_fire == state and replacement.weapon.automatic_fire.active_barrel == 1, "A replacement gunner inherits the physical gun's thermal state")


func _test_opportunities() -> void:
	var gunner: Soldier = _prepare(PATHS[0])
	var state: AutomaticFireState = gunner.weapon.automatic_fire
	state.pause_remaining_s = 2.0
	enemy.is_moving = true
	_check(fire._rapid_fire_opportunity(enemy, 4, enemy.current_hex), "A visible moving target in an open sight line is a rapid fire opportunity")
	_check(state.select_rapid(gunner.weapon, true) and state.pause_remaining_s <= gunner.weapon.rapid_pause_s, "A new opportunity shortens an existing observation pause")
	state.advance(gunner.weapon.rapid_window_s + 0.01, gunner.weapon)
	_check(not state.select_rapid(gunner.weapon, true), "An enemy remaining exposed cannot renew rapid fire indefinitely")
	state.advance(gunner.weapon.rapid_recovery_s, gunner.weapon)
	_check(state.select_rapid(gunner.weapon, true), "Rapid fire capacity recovers over time")
	state.barrel_heat[0] = gunner.weapon.heat_soft_limit
	_check(not state.select_rapid(gunner.weapon, true), "Heat reserve prevents another rapid window before a hard stop")
	var lane: Dictionary = LOSHelper.los_lookup[shooter.current_hex][enemy.current_hex]
	lane["target_concealment"] = 1
	_check(not fire._rapid_fire_opportunity(enemy, 4, enemy.current_hex), "Movement in concealment does not trigger exposed target rapid fire")
	lane["target_concealment"] = 0
	lane["hindrance"] = 1
	_check(not fire._rapid_fire_opportunity(enemy, 4, enemy.current_hex), "Intervening concealment also prevents an exposed target rapid window")
	lane["hindrance"] = 0
	enemy.is_moving = false
	_check(fire._rapid_fire_opportunity(enemy, 1, enemy.current_hex), "A close visible threat can trigger rapid fire without moving")
	enemy.stress_system.state = STATES.MoraleState.PINNED
	_check(not fire._rapid_fire_opportunity(enemy, 1, enemy.current_hex), "An already pinned target does not consume a rapid fire window")
	state.barrel_heat[0] = 0.0
	state.finish_burst(gunner.weapon, false, false, 1.0)
	var ordinary_pause: float = state.pause_remaining_s
	state.finish_burst(gunner.weapon, false, true, 1.0)
	_check(state.pause_remaining_s > ordinary_pause, "Maintaining suppression uses longer observation pauses")


func _test_live_opportunity() -> void:
	var gunner: Soldier = _prepare(PATHS[0])
	var state: AutomaticFireState = gunner.weapon.automatic_fire
	state.pause_remaining_s = 2.0
	enemy.is_moving = true
	_simulate(0.5)
	_check(not fire.times.is_empty() and fire.times[0] < 0.5, "The live scheduler interrupts observation in time to use a short exposed target opportunity")
	_check(fire.times.size() >= 2 and absf(fire.times[1] - fire.times[0] - 60.0 / gunner.weapon.rpm) <= 1.0 / 60.0, "Automatic rounds retain the configured cyclic interval inside a burst")
	gunner = _prepare(PATHS[0])
	state = gunner.weapon.automatic_fire
	state.barrel_heat[0] = gunner.weapon.heat_soft_limit
	_check(gunner.automatic_burst_size(false) <= 3, "Soft heat reduces the next controlled MG34 burst")
	state.finish_burst(gunner.weapon, false, false, 1.0)
	var warm_pause: float = state.pause_remaining_s
	state.barrel_heat[0] = lerpf(gunner.weapon.heat_soft_limit, gunner.weapon.heat_hard_limit, 0.5)
	state.finish_burst(gunner.weapon, false, false, 1.0)
	_check(state.pause_remaining_s > warm_pause, "Rising heat lengthens pauses before the hard cooling stop")


func _test_cadence() -> void:
	_set_enemy_hex(Vector2i(0, 4))
	for path: String in PATHS:
		var counts: Array[int] = []
		for fps: int in [30, 60, 120]:
			var gunner: Soldier = _prepare(path)
			_simulate(60.0, fps)
			counts.append(fire.times.size())
			_check(gunner.weapon.ammunition == 100000 - fire.times.size(), gunner.weapon.name + " spends only emitted rounds")
		print(path.get_file(), " controlled rounds/min at 30/60/120 Hz: ", counts)
		_check(counts[1] >= 45 and counts[1] <= 200, path.get_file() + " uses controlled sustained fire rather than cyclic fire between reloads")
		_check(absi(counts[0] - counts[2]) <= 8, path.get_file() + " sustains comparable output across frame rates")
		var controlled: int = counts[1]
		_prepare(path)
		enemy.is_moving = true
		_simulate(60.0)
		_check(fire.times.size() > controlled, path.get_file() + " exploits exposed moving targets with more firepower")
		_check(fire.times.size() < controlled * 2, path.get_file() + " bounds rapid fire over a prolonged engagement")
		var gunner: Soldier = _prepare(path)
		_simulate(300.0)
		_check(fire.times.size() > controlled * 2 and gunner.weapon.automatic_fire.heat() <= gunner.weapon.heat_hard_limit + gunner.weapon.heat_per_round, path.get_file() + " remains operational through a prolonged engagement within thermal limits")
		print(path.get_file(), " five-minute rounds: ", fire.times.size(), "; barrel heat: ", gunner.weapon.automatic_fire.barrel_heat)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
