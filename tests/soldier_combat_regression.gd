extends Node

class UnitProbe extends Unit:
	func set_cover(_value: int) -> void:
		pass

class FireProbe extends SquadFireController:
	var muzzle_times: Array[float] = []
	var muzzle_weapons: Array[int] = []
	var impacts: int = 0

	func _on_fire_weapon(_weapon: WeaponSpec, _position: Vector2, _auto: bool, _id: int, _owner: Node2D) -> void:
		pass

	func _on_stop_mg_loop(_weapon: WeaponSpec, _position: Vector2, _id: int, _owner: Node2D) -> void:
		pass

	func fire_at(rounds: int, _weapon: WeaponSpec, _grenade: bool, _cell: Vector2i, _distance: int, _cover: int, _targets: Array[Unit], _origin: Vector2 = Vector2.INF) -> void:
		impacts += rounds

	func observe_shot(weapon: WeaponSpec, _cell: Vector2i, _origin: Vector2, _impact: Vector2) -> void:
		muzzle_times.append(_now_s)
		muzzle_weapons.append(weapon.get_instance_id())

var failures: int = 0
var checks: int = 0
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
	enemy.current_hex = Vector2i(0, 1)
	enemy.current_cube = ground.map_to_cube(enemy.current_hex)
	enemy.position = ground.map_to_local(enemy.current_hex)
	fire = FireProbe.new()
	fire.unit = shooter
	fire.stress_controller = shooter.stress_system
	shooter.squad_fire = fire
	add_child(fire)
	fire.set_process(false)
	fire.fire_shot.connect(fire.observe_shot)
	LOSHelper.los_lookup = {shooter.current_hex: {enemy.current_hex: {"target_cover": 0}}}
	Globals.unit_visible_enemies = {shooter: [enemy]}
	_test_reaction_spread()
	await _test_live_reaction()
	_test_readiness_and_progress()
	_test_attention_snapshot()
	_test_behavior()
	_test_weapon_cycles()
	await _test_scheduler()
	_test_selection_wakeup()
	_test_frame_rates()
	await get_tree().create_timer(0.05).timeout
	fire.calc.free()
	fire.free()
	shooter.stress_system.free()
	shooter.free()
	enemy.free()
	Globals.unit_visible_enemies.clear()
	LOSHelper.los_lookup.clear()
	LOSHelper.ground_layer = null
	print("Soldier combat checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)

func _soldier(index: int, path: String = "res://resources/weapons/m1_garand.tres") -> Soldier:
	var weapon: WeaponSpec = (load(path) as WeaponSpec).create_runtime()
	weapon.ammunition = 200
	weapon.projectile_speed = 1000000
	var soldier: Soldier = Soldier.new(index, "Observer " + str(index), RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, weapon, shooter, shooter.team)
	soldier.setup_weapon_task.done = true
	soldier.reload_task.done = true
	return soldier

func _test_reaction_spread() -> void:
	var earliest: float = INF
	var latest: float = 0.0
	var majority: int = 0
	for index: int in range(12):
		var soldier: Soldier = _soldier(index)
		soldier.begin_engagement(enemy, enemy.current_hex, 1, 1.0)
		var delay: float = soldier.aquire_target_task.remaining_time_s
		earliest = minf(earliest, delay)
		latest = maxf(latest, delay)
		if delay <= 1.2:
			majority += 1
	_check(earliest >= 0.2 and earliest <= 0.5 and latest <= 1.8 and latest - earliest > 0.4, "Close contacts produce early individual shots and a bounded, non-synchronous spread")
	_check(majority >= 7, "Most ready soldiers respond within the close-contact opportunity")

func _test_live_reaction() -> void:
	var roster: Array[Soldier] = []
	for index: int in range(12):
		roster.append(_soldier(index))
	fire.set_soldiers(roster)
	fire.target_unit = null
	fire.muzzle_times.clear()
	fire.muzzle_weapons.clear()
	fire._now_s = 0.0
	fire.set_target_unit(enemy)
	for frame: int in range(120):
		fire._now_s += 1.0 / 60.0
		fire._tick_soldiers(1.0 / 60.0)
	var first_shots: Dictionary[int, float] = {}
	for index: int in range(fire.muzzle_times.size()):
		var weapon_id: int = fire.muzzle_weapons[index]
		if not first_shots.has(weapon_id):
			first_shots[weapon_id] = fire.muzzle_times[index]
	var times: Array = first_shots.values()
	times.sort()
	_check(times.size() == 12 and float(times[0]) <= 0.5 and float(times[-1]) <= 1.8 and float(times[-1]) - float(times[0]) > 0.4, "The actual scheduler staggers first muzzle events while preserving the opportunity")
	await get_tree().create_timer(0.03).timeout

func _test_readiness_and_progress() -> void:
	var ready: Soldier = _soldier(10)
	var lowered: Soldier = _soldier(10)
	lowered.lower_weapon()
	ready.reaction_tendency = 0.0
	lowered.reaction_tendency = 0.0
	ready.begin_engagement(enemy, enemy.current_hex, 1, 1.0)
	lowered.begin_engagement(enemy, enemy.current_hex, 1, 1.0)
	_check(lowered.aquire_target_task.remaining_time_s > ready.aquire_target_task.remaining_time_s, "A lowered weapon pays the raise cost while an already ready weapon does not")
	ready.advance_handling(0.1, 1.0)
	var progress: float = ready.aquire_target_task.remaining_time_s
	ready.begin_engagement(enemy, enemy.current_hex, 1, 1.0)
	_check(is_equal_approx(progress, ready.aquire_target_task.remaining_time_s), "Repeated target evaluation cannot reset reaction progress")
	var peripheral: Soldier = _soldier(10)
	peripheral.reaction_tendency = 0.0
	peripheral.begin_engagement(enemy, enemy.current_hex, 1, 0.0)
	_check(peripheral.aquire_target_task.remaining_time_s > ready.aquire_target_task.start_time_s, "Peripheral contacts preserve a separate reaction penalty")
	ready.rounds_in_mag = 0
	ready.start_reload()
	ready.advance_handling(ready.weapon.reload_s / 0.9 + 1.0, 0.9)
	_check(ready.rounds_in_mag == ready.weapon.mag_capacity and ready.reload_task.done, "Reload refills the magazine only when actual work completes, without compounded morale penalties")
	ready.lose_contact()
	_check(not ready.has_engagement and ready.aquire_target_task.target_id == null, "Lost LOS invalidates the firing solution")

func _test_attention_snapshot() -> void:
	var bearing: Vector2 = shooter.position.direction_to(enemy.position)
	shooter.tactical_state.focus_direction = bearing
	var aligned: Soldier = _soldier(10)
	fire._begin_soldier_engagement(aligned, enemy, enemy.current_hex)
	var track: EnemyTrack = EnemyTrack.new(shooter, enemy)
	track.reaction_focus_direction = -bearing
	track.acquired_at_s = shooter._now()
	var tracks: Dictionary[Unit, EnemyTrack] = {enemy: track}
	Globals.unit_enemy_tracks[shooter] = tracks
	var surprised: Soldier = _soldier(10)
	fire._begin_soldier_engagement(surprised, enemy, enemy.current_hex)
	_check(surprised.aquire_target_task.remaining_time_s > aligned.aquire_target_task.remaining_time_s, "Turning focus on detection does not erase the original peripheral reaction penalty")
	Globals.unit_enemy_tracks.clear()
	shooter.tactical_state.focus_direction = Vector2.ZERO

func _test_behavior() -> void:
	var engaging: int = 0
	var sheltering: int = 0
	for index: int in range(24):
		var soldier: Soldier = _soldier(index)
		soldier.update_behavior(0.01, STATES.MoraleState.PINNED, true)
		if soldier.behavior == Soldier.Behavior.ENGAGING:
			engaging += 1
		else:
			sheltering += 1
	_check(engaging > 0 and sheltering > 0, "A pinned squad contains independently engaging and sheltering soldiers")
	var hidden: Soldier = _soldier(1)
	hidden.begin_engagement(enemy, enemy.current_hex, 1, 1.0)
	hidden.behavior = Soldier.Behavior.COWERING
	hidden.behavior_remaining_s = 1.0
	var before: float = hidden.aquire_target_task.remaining_time_s
	_check(not hidden.advance_handling(0.5, 1.0) and hidden.aquire_target_task.remaining_time_s == before, "Cowering blocks firing preparation rather than making aiming arbitrarily slow")
	hidden._behavior_morale = STATES.MoraleState.NORMAL
	hidden.update_behavior(0.25, STATES.MoraleState.NORMAL, false)
	_check(hidden.behavior == Soldier.Behavior.COWERING, "Protective behavior persists across updates")
	hidden.update_behavior(0.76, STATES.MoraleState.NORMAL, false)
	_check(hidden.behavior == Soldier.Behavior.RECOVERING, "Recovery from shelter is an individual transition")
	var coarse: Soldier = _soldier(77)
	var fine: Soldier = _soldier(77)
	coarse.update_behavior(8.0, STATES.MoraleState.PINNED, true)
	for step: int in range(80):
		fine.update_behavior(0.1, STATES.MoraleState.PINNED, true)
	_check(coarse.behavior == fine.behavior and is_equal_approx(coarse.behavior_remaining_s, fine.behavior_remaining_s), "Behavior decisions depend on elapsed time, not frame count")

func _test_weapon_cycles() -> void:
	var bolt: Soldier = _soldier(3, "res://resources/weapons/kar98.tres")
	var garand: Soldier = _soldier(3)
	var mg: Soldier = _soldier(3, "res://resources/weapons/mg34.tres")
	bolt.finish_burst()
	garand.finish_burst()
	mg.finish_burst()
	_check(bolt.cycle_remaining_s > 0.0 and garand.cycle_remaining_s == 0.0, "Bolt-action operation is distinct from semi-automatic aim recovery")
	_check(bolt.cycle_remaining_s + bolt.reaim_remaining_s > garand.reaim_remaining_s, "Garands deliver quicker aimed follow-up shots")
	_check(mg.reaim_remaining_s >= mg.weapon.burst_pause_s and mg.reaim_remaining_s < mg.weapon.burst_pause_s + mg.weapon.reaim_s, "Automatic burst pauses overlap aim correction")

func _prepare_fire(soldier: Soldier) -> void:
	fire.set_soldiers([soldier])
	fire.target_unit = null
	shooter.is_moving = false
	shooter.broken = false
	shooter.surrendered = false
	shooter.stress_system.state = STATES.MoraleState.NORMAL
	Globals.unit_visible_enemies[shooter] = [enemy]
	fire.set_target_unit(enemy)
	soldier.aquire_target_task.done = true
	soldier.reload_task.done = true
	soldier.reaim_remaining_s = 0.0
	soldier.cycle_remaining_s = 0.0
	soldier.behavior = Soldier.Behavior.ENGAGING
	fire.muzzle_times.clear()
	fire.muzzle_weapons.clear()
	fire.impacts = 0

func _test_scheduler() -> void:
	var soldier: Soldier = _soldier(4, "res://resources/weapons/mg34.tres")
	soldier.weapon.burst_rounds = 8
	_prepare_fire(soldier)
	var ammo: int = soldier.weapon.ammunition
	_check(fire._try_fire_soldier(0.0, soldier, false, 0, 0, 1, 0) == 1, "A burst emits its first round without waiting for an impact")
	_check(soldier.weapon.ammunition == ammo - 1 and fire.fire_recent > 0.0, "Only emitted rounds consume ammunition and firing stimulus starts at the muzzle")
	soldier.behavior = Soldier.Behavior.COWERING
	fire._try_fire_soldier(1.0, soldier, false, 0, 0, 1, 0)
	_check(not soldier.burst_active and soldier.weapon.ammunition == ammo - 1, "Taking shelter stops the remaining burst without spending unfired ammunition")
	await get_tree().create_timer(0.03).timeout
	_check(fire.impacts == 1, "A round already airborne lands after its shooter takes cover")
	_prepare_fire(soldier)
	fire._try_fire_soldier(0.0, soldier, false, 0, 0, 1, 0)
	Globals.unit_visible_enemies[shooter] = []
	var after_first: int = soldier.weapon.ammunition
	fire._try_fire_soldier(1.0, soldier, false, 0, 0, 1, 0)
	_check(soldier.weapon.ammunition == after_first and not soldier.burst_active, "LOS/contact loss stops subsequent burst rounds")
	var rifleman: Soldier = _soldier(5)
	_prepare_fire(rifleman)
	var second: Soldier = _soldier(6)
	second.aquire_target_task.done = true
	fire.soldiers.append(second)
	fire._tick_soldiers(0.01)
	_check(fire.muzzle_weapons.has(rifleman.weapon.get_instance_id()) and fire.muzzle_weapons.has(second.weapon.get_instance_id()), "One soldier's projectile flight cannot delay another soldier's update")

func _test_selection_wakeup() -> void:
	var soldier: Soldier = _soldier(8)
	fire.set_soldiers([soldier])
	fire.clear_target()
	fire.fire_timer = 100.0
	fire._last_visible.clear()
	Globals.unit_visible_enemies[shooter] = [enemy]
	fire._process(0.01)
	_check(fire.target_unit == enemy and fire.fire_timer < 100.0, "New detection wakes automatic target selection immediately")
	var remaining: float = soldier.aquire_target_task.remaining_time_s
	fire._process(0.01)
	_check(soldier.aquire_target_task.remaining_time_s <= remaining, "Subsequent squad updates preserve individual reaction progress")

func _test_frame_rates() -> void:
	var counts: Array[int] = []
	for fps: int in [30, 60, 120]:
		var soldier: Soldier = _soldier(9)
		_prepare_fire(soldier)
		fire.set_target_unit(enemy)
		for frame: int in range(fps * 5):
			fire._tick_soldiers(1.0 / float(fps))
		counts.append(fire.muzzle_times.size())
	_check(absi(counts[0] - counts[2]) <= 1 and absi(counts[1] - counts[2]) <= 1, "Weapon scheduling remains consistent across 30, 60 and 120 updates per second")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
