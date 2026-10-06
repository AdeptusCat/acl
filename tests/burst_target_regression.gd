extends Node

# Run with: godot --headless --path . res://tests/burst_target_regression.tscn
# Keep real burst timers, signal wiring, and sight-loss target clearing. Probe
# only the visual destination passed to the battlefield view.
class VisualProbe extends UnitUi:
	var destinations: Array[Vector2] = []
	var families: Array[WeaponSpec.Family] = []

	func shoot(_from: Vector2, to: Vector2, _weapon: WeaponSpec) -> void:
		destinations.append(to)
		families.append(WeaponSpec.Family.SMALL_ARM)

	func shoot_rocket_launcher(_from: Vector2, to: Vector2, _weapon: WeaponSpec) -> void:
		destinations.append(to)
		families.append(WeaponSpec.Family.ROCKET_LAUNCHER)

	func shoot_mortar(_from: Vector2, to: Vector2, _weapon: WeaponSpec) -> void:
		destinations.append(to)
		families.append(WeaponSpec.Family.MORTAR)

	func set_ammunition_left(_ammo: int) -> void:
		pass


var failures: int = 0
var shooter: Unit
var enemy: Unit
var visual: VisualProbe
var gunner: Soldier

signal burst_finished


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
	var original_ui: UnitUi = shooter.ui
	var original_soldiers: Array[Soldier] = shooter.squad_fire.soldiers
	visual = VisualProbe.new()
	shooter.ui = visual
	_set_hex(shooter, Vector2i(5, 5))
	shooter.is_moving = false
	shooter.in_close_combat = false
	var weapon: WeaponSpec = WeaponSpec.new()
	weapon.type = WeaponSpec.WeaponType.MG
	weapon.fire_mode = WeaponSpec.FireMode.BURST
	weapon.range_hexes = 100
	weapon.mag_capacity = 30
	gunner = Soldier.new(999, "Burst target probe", RankGrades.Grade.SOLDIER, RankGrades.Role.GUNNER, weapon, shooter, shooter.team)
	shooter.squad_fire.soldiers = [gunner]
	Debug.dont_fire_wepaons = false
	for attack_state: Unit.AttackState in [Unit.AttackState.AUTO, Unit.AttackState.MANUAL_TRACK]:
		await _test_sight_loss(attack_state)
	await _test_visible_movement()
	await _test_retarget()
	await _test_origin_target()
	_test_projectile_families()
	shooter.ui = original_ui
	shooter.squad_fire.soldiers = original_soldiers
	visual.free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Burst target regression failures: ", failures)
	get_tree().quit(failures)


func _test_sight_loss(attack_state: Unit.AttackState) -> void:
	var burst_hex: Vector2i = Vector2i(6, 5)
	var original_los: Dictionary = LOSHelper.los_lookup
	LOSHelper.los_lookup = {shooter.current_hex: {burst_hex: {"target_cover": 0}}}
	_prepare_target(burst_hex, attack_state)
	_fire_burst(burst_hex)
	_check(visual.destinations.size() == 1, "Burst starts before the target leaves sight")
	_set_hex(enemy, Vector2i(7, 5))
	Globals.unit_visible_enemies[shooter] = []
	gunner.setup_weapon_task.done = true
	gunner.reload_task.done = true
	gunner.aquire_target_task.done = true
	var ammunition_before: int = gunner.weapon.ammunition
	var new_shots: int = await shooter.squad_fire._try_fire_soldier(0.1, gunner, false, 0, 0, 0, 0)
	_check(new_shots == 0 and gunner.weapon.ammunition == ammunition_before, "Sight loss prevents a new burst")
	_check(shooter.squad_fire.target_unit == null and not shooter.squad_fire.has_target_hex, "Real sight-loss firing path clears the tracked target")
	_check(shooter.squad_fire.target_hex == Vector2i.ZERO, "Cleared target reproduces the reported origin fallback")
	await burst_finished
	_check_destinations([burst_hex, burst_hex, burst_hex], "Sight loss during attack state %d retains the burst destination" % attack_state)
	LOSHelper.los_lookup = original_los


func _test_visible_movement() -> void:
	var old_hex: Vector2i = Vector2i(6, 5)
	var new_hex: Vector2i = Vector2i(7, 5)
	var original_los: Dictionary = LOSHelper.los_lookup
	LOSHelper.los_lookup = {shooter.current_hex: {old_hex: {"target_cover": 0}, new_hex: {"target_cover": 0}}}
	_prepare_target(old_hex, Unit.AttackState.MANUAL_TRACK)
	_fire_burst(old_hex)
	_set_hex(enemy, new_hex)
	shooter.squad_fire.set_target_unit(enemy)
	await burst_finished
	_check_destinations([old_hex, old_hex, old_hex], "Movement during a burst retains its captured destination")
	await shooter.squad_fire.fire_shots(gunner, 3, 1200.0, false, shooter.squad_fire.target_hex)
	_check_destinations([old_hex, old_hex, old_hex, new_hex, new_hex, new_hex], "The next burst uses the moved target's new hex")
	LOSHelper.los_lookup = original_los


func _test_retarget() -> void:
	var old_hex: Vector2i = Vector2i(6, 5)
	var new_hex: Vector2i = Vector2i(8, 5)
	_prepare_target(old_hex, Unit.AttackState.AUTO)
	_fire_burst(old_hex)
	shooter.setAttackState(Unit.AttackState.MANUAL_GROUND)
	shooter.squad_fire.set_target_hex(new_hex)
	await burst_finished
	_check_destinations([old_hex, old_hex, old_hex], "A new target order cannot redirect an existing burst")
	await shooter.squad_fire.fire_shots(gunner, 1, 1200.0, false, shooter.squad_fire.target_hex)
	_check_destinations([old_hex, old_hex, old_hex, new_hex], "The next shot uses the new ground-fire destination")


func _test_origin_target() -> void:
	visual.destinations.clear()
	shooter.squad_fire.set_target_hex(Vector2i.ZERO)
	_fire_burst(Vector2i.ZERO)
	shooter.squad_fire.set_target_hex(Vector2i(8, 5))
	await burst_finished
	_check_destinations([Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO], "A deliberate burst at (0,0) remains valid after retargeting")


func _test_projectile_families() -> void:
	for family: WeaponSpec.Family in [WeaponSpec.Family.SMALL_ARM, WeaponSpec.Family.ROCKET_LAUNCHER, WeaponSpec.Family.MORTAR]:
		visual.destinations.clear()
		visual.families.clear()
		var weapon: WeaponSpec = WeaponSpec.new()
		weapon.family = family
		shooter.squad_fire.set_target_hex(Vector2i.ZERO)
		shooter._on_fire_shot(weapon, Vector2i(6, 5))
		_check_destinations([Vector2i(6, 5)], "Weapon family %d uses the shot signal's destination" % family)
		_check(visual.families == [family], "The shot reaches the correct weapon-family visual")


func _prepare_target(hex: Vector2i, attack_state: Unit.AttackState) -> void:
	visual.destinations.clear()
	_set_hex(enemy, hex)
	Globals.unit_visible_enemies[shooter] = [enemy]
	shooter.setAttackState(attack_state)
	shooter.squad_fire.set_target_unit(enemy)


func _fire_burst(hex: Vector2i) -> void:
	await shooter.squad_fire.fire_shots(gunner, 3, 1200.0, false, hex)
	burst_finished.emit()


func _set_hex(unit: Unit, hex: Vector2i) -> void:
	unit.current_hex = hex
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(hex)
	unit.position = LOSHelper.ground_layer.map_to_local(hex)


func _check_destinations(hexes: Array[Vector2i], message: String) -> void:
	var expected: Array[Vector2] = []
	for hex: Vector2i in hexes:
		expected.append(LOSHelper.ground_layer.map_to_local(hex))
	_check(visual.destinations == expected, "%s: expected %s, got %s" % [message, expected, visual.destinations])


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		var timer: Timer = node as Timer
		timer.stop()
	for child: Node in node.get_children():
		_freeze(child)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
