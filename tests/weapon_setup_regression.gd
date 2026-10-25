extends Node

# Run with: godot --headless --path . tests/weapon_setup_regression.tscn
const DETAILS_SCRIPT: Script = preload("res://scenes/ui/units/unit_details_panel.gd")

class FireProbe extends SquadFireController:
	var shots_fired: int = 0

	func _on_fire_weapon(_weapon: WeaponSpec, _position: Vector2, _auto: bool, _owner_id: int, _owner: Node2D) -> void:
		pass

	func fire_shots(_soldier: Soldier, shots: int, _rpm: float, _auto: bool, _hex: Vector2i) -> void:
		shots_fired += shots

	func fire_at(_rounds: int, _weapon: WeaponSpec, _grenade: bool, _hex: Vector2i, _distance: int, _cover: int, _targets: Array[Unit], _shot_origin: Vector2 = Vector2.INF) -> void:
		pass


var failures: int = 0
var checks: int = 0
var shooter: Unit
var enemy: Unit
var probe: FireProbe
var gunner: Soldier
var details: PanelContainer


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	shooter = Globals.get_units()[1]
	enemy = Globals.get_units()[3]
	for unit: Unit in Globals.get_units():
		unit.remove_from_group("units")
	for panel: Node in main.find_children("*", "PanelContainer", true, false):
		if panel.get_script() == DETAILS_SCRIPT:
			details = panel as PanelContainer
			break
	_check(details != null, "Fixture contains the actual soldier task panel")
	var original_fire: SquadFireController = shooter.squad_fire
	probe = FireProbe.new()
	probe.unit = shooter
	probe.stress_controller = shooter.stress_system
	shooter.add_child(probe)
	probe.set_process(false)
	shooter.squad_fire = probe
	shooter.unit_arrived_at_hex.connect(probe._on_unit_arrived_at_hex)
	_set_hex(enemy, Vector2i(20, 20))
	Debug.dont_fire_wepaons = true
	for weapon_path: String in ["res://resources/weapons/mg34_heavy.tres", "res://resources/weapons/mg34.tres"]:
		_prepare_weapon(weapon_path)
		_test_idle_setup()
		_test_movement_and_ineligibility()
		await _test_setup_under_contact()
	_prepare_weapon("res://resources/weapons/kar98.tres")
	_arrive()
	probe._process(0.0)
	_check(gunner.setup_weapon_task.done, "A rifle with no setup duration is immediately ready")
	shooter.squad_fire = original_fire
	probe.calc.free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Weapon setup regression checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _prepare_weapon(path: String) -> void:
	var weapon: WeaponSpec = (load(path) as WeaponSpec).create_runtime()
	gunner = Soldier.new(999, "Setup probe", RankGrades.Grade.SOLDIER, RankGrades.Role.GUNNER, weapon, shooter, shooter.team)
	probe.soldiers = [gunner]
	shooter.stress_system.state = STATES.MoraleState.NORMAL
	shooter.is_moving = false
	shooter.in_close_combat = false
	shooter.broken = false
	shooter.surrendered = false
	shooter.alive = true
	shooter.setAttackState(Unit.AttackState.AUTO)
	Globals.unit_visible_enemies[shooter] = []
	probe.clear_target()
	if details != null:
		details.show_unit_detail(shooter, false)


func _arrive() -> void:
	_set_hex(shooter, Vector2i.ZERO)
	var path: Array[Vector3i] = [shooter.current_cube, LOSHelper.ground_layer.map_to_cube(Vector2i(1, 0))]
	shooter.movement.follow_cube_path(path)
	shooter.movement._process_movement(100.0)
	_check(not shooter.is_moving and shooter.current_hex == Vector2i(1, 0), "Real movement reaches its destination")
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, gunner.weapon.setup_s), "Arrival starts the weapon's configured setup duration")


func _test_idle_setup() -> void:
	_arrive()
	var duration: float = gunner.weapon.setup_s
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.0), "A stationary gunner advances setup without any detected enemy")
	_check(probe.target_unit == null and not probe.has_target_hex, "Setup requires no firing target")
	if details != null:
		details._process(0.0)
		var entries: Dictionary = details.soldier_entries_by_soldier[gunner]
		var task: Label = entries[DETAILS_SCRIPT.Entry.TASK]
		var progress: ProgressBar = entries[DETAILS_SCRIPT.Entry.PROGRESS_BAR]
		_check(task.text == "Setting Up" and progress.value > 0.0 and absf(progress.value - 1.0 / duration) <= progress.step, "The actual task progress bar advances before contact: %s, %s" % [task.text, progress.value])
	var ammunition: int = gunner.weapon.ammunition
	probe._process(duration - 1.0)
	_check(gunner.setup_weapon_task.done and is_zero_approx(gunner.setup_weapon_task.remaining_time_s), "Setup finishes at its duration without a UI update or firing attempt")
	_check(gunner.weapon.ammunition == ammunition and probe.shots_fired == 0, "Idle setup spends no ammunition and fires no shots")
	probe._process(10.0)
	_check(gunner.setup_weapon_task.done and is_zero_approx(gunner.setup_weapon_task.remaining_time_s), "Idle readiness stays complete")


func _test_movement_and_ineligibility() -> void:
	_arrive()
	var duration: float = gunner.weapon.setup_s
	shooter.movement.move_to_hex(Vector2i.ZERO)
	probe._process(duration * 2.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration), "Moving cannot advance setup even with no visible enemies")
	shooter.movement._process_movement(100.0)
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.0), "Setup resumes at the new destination")
	for flag: String in ["in_close_combat", "broken", "surrendered"]:
		shooter.set(flag, true)
		probe._process(1.0)
		_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.0), "Setup pauses while " + flag)
		shooter.set(flag, false)
	shooter.alive = false
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.0), "A dead squad cannot set up")
	shooter.alive = true
	gunner.is_alive = false
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.0), "A dead gunner cannot set up")
	gunner.is_alive = true
	shooter.stress_system.state = STATES.MoraleState.CAUTIOUS
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.8), "Setup retains the cautious-state speed")
	shooter.stress_system.state = STATES.MoraleState.PANIC
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.8), "Panic pauses setup")
	shooter.stress_system.state = STATES.MoraleState.NORMAL
	_arrive()
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration), "Another move resets partial setup at arrival")


func _test_setup_under_contact() -> void:
	var duration: float = gunner.weapon.setup_s
	probe._process(1.0)
	_set_hex(enemy, Vector2i(2, 0))
	LOSHelper.los_lookup = {shooter.current_hex: {enemy.current_hex: {"target_cover": 0}}}
	Globals.unit_visible_enemies[shooter] = [enemy]
	shooter.setAttackState(Unit.AttackState.MANUAL_TRACK)
	probe.set_target_unit(enemy)
	gunner.reload_task.done = true
	gunner.aquire_target_task.done = true
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 2.0), "Target acquisition preserves earlier progress and advances setup only once per frame")
	var shots: int = await probe._try_fire_soldier(1.0, gunner, true, 1, 0, 1, 0)
	_check(shots == 0 and is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 2.0), "Firing cannot complete or advance an unfinished setup task")
	Globals.unit_visible_enemies[shooter] = []
	probe._process(duration)
	_check(gunner.setup_weapon_task.done and probe.target_unit == null, "Setup completes even if contact is lost")
	Globals.unit_visible_enemies[shooter] = [enemy]
	shooter.setAttackState(Unit.AttackState.MANUAL_TRACK)
	probe.set_target_unit(enemy)
	gunner.reload_task.done = true
	gunner.aquire_target_task.done = true
	gunner.weapon.fire_mode = WeaponSpec.FireMode.SINGLE
	gunner.weapon.projectile_speed = 1000000
	Debug.dont_fire_wepaons = false
	var ammunition: int = gunner.weapon.ammunition
	shots = await probe._try_fire_soldier(0.1, gunner, true, 1, 0, 1, 0)
	_check(shots > 0 and gunner.weapon.ammunition == ammunition - shots, "A gun deployed before contact can fire without another setup delay")
	Debug.dont_fire_wepaons = true
	probe.shots_fired = 0
	Globals.unit_visible_enemies[shooter] = []
	probe.clear_target()
	_set_hex(enemy, Vector2i(20, 20))


func _set_hex(unit: Unit, hex: Vector2i) -> void:
	unit.current_hex = hex
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(hex)
	unit.position = LOSHelper.ground_layer.map_to_local(hex)


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
