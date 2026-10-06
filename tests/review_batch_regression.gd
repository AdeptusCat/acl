extends Node

class FireProbe extends SquadFireController:
	var impacts: int = 0

	func _on_fire_weapon(_weapon: WeaponSpec, _position: Vector2, _auto: bool, _owner_id: int, _position_node: Node2D) -> void:
		pass

	func fire_at(_rounds: int, _weapon: WeaponSpec, _grenade: bool, _hex: Vector2i, _distance: int, _cover: int, _targets: Array[Unit]) -> void:
		impacts += 1


class RetreatProbe extends SquadActionController:
	var destination: Vector2i = Vector2i.ZERO

	func compute_retreat_hex(origin: Vector2i, _enemies: Array[Unit], _steps: int) -> Vector2i:
		allowed_hexes = [origin, destination]
		return destination


class ClockProbe extends VictoryCondition:
	var elapsed: float = 0.0

	func advance_time(delta: float) -> void:
		elapsed += delta

	func is_condition_met() -> bool:
		return false

	func get_description() -> String:
		return "Clock fixture"


class VisualProbe extends UnitUi:
	var rifle_shots: int = 0
	var mortar_shots: int = 0

	func shoot(_from: Vector2, _to: Vector2, _weapon: WeaponSpec) -> void:
		rifle_shots += 1

	func shoot_mortar(_from: Vector2, _to: Vector2, _weapon: WeaponSpec) -> void:
		mortar_shots += 1

	func set_ammunition_left(_ammo: int) -> void:
		pass


var failures: int = 0
var rout_failures: int = 0


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
	_test_link_history()
	_test_link_visibility()
	await _test_origin_targets()
	_test_occupation()
	_test_match_clock(world.game_controller)
	_test_projection_origin()
	_test_retreat_origin()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Review batch regression failures: ", failures)
	get_tree().quit(failures)


func _test_link_history() -> void:
	var renderer: Node2D = load("res://scenes/game/los_renderer.gd").new()
	add_child(renderer)
	renderer.set_process(false)
	for sample: int in range(600):
		renderer._on_draw_command_link_strength(Globals.Team.AXIS, Vector2i(1, 0), Vector2i.ZERO, 0.5)
		renderer._process(0.1)
	_check(renderer.command_link_strength.size() <= 11, "Command-link samples remain bounded through a simulated minute")
	renderer._process(1.1)
	_check(renderer.command_link_strength.is_empty(), "Command-link samples expire after their duration")
	renderer.queue_free()


func _test_link_visibility() -> void:
	var renderer: Node2D = load("res://scenes/world/command_connectivity_renderer.gd").new()
	add_child(renderer)
	renderer.set_process(false)
	renderer.setup()
	var show_links: bool = SessionSettings.showCmdConnectivity
	var show_enemy: bool = Debug.showEnemyCmdConnectivity
	for enemy_enabled: bool in [false, true]:
		SessionSettings.showCmdConnectivity = false
		Debug.showEnemyCmdConnectivity = enemy_enabled
		renderer._process(0.1)
		for line: MovingDottedDrawLine in renderer.get_children():
			_check(not line.visible, "Disabled command connectivity hides every line, including enemy debug lines")
	SessionSettings.showCmdConnectivity = true
	Debug.showEnemyCmdConnectivity = true
	renderer._process(0.1)
	var visible: int = 0
	for line: MovingDottedDrawLine in renderer.get_children():
		if line.visible:
			visible += 1
	_check(visible > 0, "Re-enabling command connectivity restores eligible lines")
	SessionSettings.showCmdConnectivity = show_links
	Debug.showEnemyCmdConnectivity = show_enemy
	renderer.queue_free()


func _test_origin_targets() -> void:
	var unit: Unit = Globals.get_units()[0]
	var original_fire: SquadFireController = unit.squad_fire
	var probe: FireProbe = FireProbe.new()
	unit.add_child(probe)
	probe.unit = unit
	probe.stress_controller = unit.stress_system
	probe.set_process(false)
	unit.squad_fire = probe
	unit.current_hex = Vector2i(1, 0)
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(unit.current_hex)
	unit.position = LOSHelper.ground_layer.map_to_local(unit.current_hex)
	unit.is_moving = false
	unit.in_close_combat = false
	Globals.unit_visible_enemies[unit] = []
	Debug.dont_fire_wepaons = false
	var rifle: WeaponSpec = (load("res://resources/weapons/m1_garand.tres") as WeaponSpec).create_runtime()
	rifle.projectile_speed = 10000.0
	var soldier: Soldier = Soldier.new(99, "Origin fixture", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, rifle, unit, unit.team)
	probe.soldiers = [soldier]
	_ready_weapon(soldier)
	unit.setAttackState(Unit.AttackState.MANUAL_GROUND)
	_check(await probe._try_fire_soldier(0.1, soldier, false, 0, 0, 1, 0) == 0, "A new controller has no firing target")
	unit.order(Globals.UnitCmd.FIRE_AT_HEX, Vector2i.ZERO)
	_ready_weapon(soldier)
	_check(await probe._try_fire_soldier(0.1, soldier, false, 0, 0, 1, 0) > 0, "Player ground-fire orders reach valid tile (0,0)")
	var enemy: Unit = Globals.get_units()[3]
	enemy.current_hex = Vector2i.ZERO
	enemy.current_cube = LOSHelper.ground_layer.map_to_cube(Vector2i.ZERO)
	unit.setAttackState(Unit.AttackState.MANUAL_TRACK)
	Globals.unit_visible_enemies[unit] = [enemy]
	probe.set_target_unit(enemy)
	_ready_weapon(soldier)
	_check(await probe._try_fire_soldier(0.1, soldier, false, 0, 0, 1, 0) > 0, "Tracked enemy units at (0,0) can be attacked")
	Globals.unit_visible_enemies[unit] = []
	unit.order(Globals.UnitCmd.FIRE_AT_HEX, Vector2i.ZERO)
	_check(unit.attackState == Unit.AttackState.MANUAL_GROUND and probe.target_unit == null, "A ground-fire order replaces tracking at the same tile")
	Globals.unit_visible_enemies[unit] = [enemy]
	unit.setAttackState(Unit.AttackState.MANUAL_GROUND)
	probe.set_target_hex(Vector2i.ZERO)
	var mortar: WeaponSpec = (load("res://resources/weapons/m2_60mm_mortar.tres") as WeaponSpec).create_runtime()
	mortar.projectile_speed = 10000.0
	soldier.weapon = mortar
	soldier.rounds_in_mag = mortar.mag_capacity
	unit.setAttackState(Unit.AttackState.MANUAL_TRACK)
	probe.set_target_unit(enemy)
	_ready_weapon(soldier)
	_check(await probe._try_fire_soldier(0.1, soldier, false, 0, 0, 1, 0) > 0, "Mortars track enemy units at (0,0)")
	unit.fire_mortar(Vector2i.ZERO)
	_ready_weapon(soldier)
	_check(await probe._try_fire_soldier(0.1, soldier, false, 0, 0, 1, 0) > 0, "Mortar orders reach valid tile (0,0)")
	if probe.has_method("clear_target"):
		probe.call("clear_target")
	else:
		probe.set_target_unit(null)
		probe.set_target_hex(Vector2i.ZERO)
	_ready_weapon(soldier)
	_check(await probe._try_fire_soldier(0.1, soldier, false, 0, 0, 1, 0) == 0, "Explicitly cleared targets cannot fire")
	var visual: VisualProbe = VisualProbe.new()
	var visual_unit: Unit = Unit.new()
	visual_unit.ui = visual
	visual_unit.squad_fire = probe
	probe.target_hex = Vector2i.ZERO
	visual_unit._on_fire_shot(rifle, Vector2i.ZERO)
	visual_unit._on_fire_shot(mortar, Vector2i.ZERO)
	_check(visual.rifle_shots == 1 and visual.mortar_shots == 1, "Rifle and mortar shot visuals support tile (0,0)")
	visual_unit.free()
	visual.free()
	var action: SquadActionController = unit.action_controller
	var original_action_fire: SquadFireController = action.squad_fire
	action.squad_fire = probe
	var original_flag: bool = action.has_attack_flag
	var original_hex: Vector2i = action.attack_hex
	action.has_attack_flag = true
	action.attack_hex = Vector2i.ZERO
	action._enter_action_state(0, SquadActionController.SquadActionState.HOLDING_POSITION)
	_check(probe.get("has_target_hex") == true, "Holding an attack order retains target tile (0,0)")
	action.has_attack_flag = false
	action._enter_action_state(0, SquadActionController.SquadActionState.HOLDING_POSITION)
	_check(probe.get("has_target_hex") == false, "Holding without an attack order clears its target")
	action.has_attack_flag = original_flag
	action.attack_hex = original_hex
	action.squad_fire = original_action_fire
	unit.squad_fire = original_fire
	probe.calc.free()
	probe.queue_free()


func _ready_weapon(soldier: Soldier) -> void:
	soldier.setup_weapon_task.done = true
	soldier.reload_task.done = true
	soldier.aquire_target_task.done = true


func _test_occupation() -> void:
	var battle_units: Array[Unit] = Globals.get_units()
	for battle_unit: Unit in battle_units:
		battle_unit.remove_from_group("units")
	var friendly: Unit = battle_units[0]
	var friendly_hex: Vector2i = friendly.current_hex
	friendly.current_hex = Vector2i.ZERO
	friendly.team = Globals.Team.AXIS
	friendly.add_to_group("units")
	var condition: OccupyObjectiveCondition = OccupyObjectiveCondition.new()
	condition.team = Globals.Team.AXIS
	condition.required_time_s = 3.0
	condition.state = OccupyObjectiveState.new()
	condition.state.hexes = [Vector2i.ZERO]
	condition.state.required_times_reached_s[Vector2i.ZERO] = 0.0
	condition.state.units_in_objectives[Vector2i.ZERO] = UnitsCollection.new()
	condition.state.victory_conditions_met[Vector2i.ZERO] = false
	for query: int in range(5):
		_check(not condition.is_condition_met(), "Checking occupation does not satisfy an unmet duration")
	_check(is_zero_approx(condition.state.required_times_reached_s[Vector2i.ZERO]), "Repeated occupation queries leave elapsed time unchanged")
	_advance(condition, 0.25)
	_advance(condition, 0.5)
	_check(is_equal_approx(condition.state.required_times_reached_s[Vector2i.ZERO], 0.75), "Occupation uses elapsed seconds rather than number of queries")
	_advance(condition, 2.25)
	_check(condition.is_condition_met(), "Three active seconds satisfy the occupation requirement")
	var reached: float = condition.state.required_times_reached_s[Vector2i.ZERO]
	for query: int in range(5):
		condition.is_condition_met()
	_check(is_equal_approx(condition.state.required_times_reached_s[Vector2i.ZERO], reached), "Result-screen queries do not add occupation time")
	var enemy: Unit = battle_units[3]
	var enemy_hex: Vector2i = enemy.current_hex
	enemy.team = Globals.Team.ALLIES
	enemy.current_hex = Vector2i.ZERO
	enemy.add_to_group("units")
	_advance(condition, 0.25)
	_check(not condition.is_condition_met() and is_zero_approx(condition.state.required_times_reached_s[Vector2i.ZERO]), "Contested occupation resets continuous elapsed time")
	friendly.current_hex = friendly_hex
	enemy.current_hex = enemy_hex
	friendly.remove_from_group("units")
	enemy.remove_from_group("units")
	for battle_unit: Unit in battle_units:
		battle_unit.add_to_group("units")


func _test_match_clock(controller: Node) -> void:
	var original_conditions: Dictionary[Globals.Team, VictoryConditionCollection] = Globals.victory_conditions.duplicate()
	var original_time: float = controller.time_left_seconds
	var original_running: bool = controller.timer_running
	var original_ended: bool = controller.end_game_handled
	var probe: ClockProbe = ClockProbe.new()
	var second_probe: ClockProbe = ClockProbe.new()
	var collection: VictoryConditionCollection = VictoryConditionCollection.new()
	collection.victory_conditions = [probe, second_probe]
	Globals.victory_conditions.clear()
	Globals.victory_conditions[Globals.Team.AXIS] = collection
	controller.time_left_seconds = 0.75
	controller.timer_running = false
	controller._process(0.2)
	_check(is_zero_approx(probe.elapsed), "Occupation clock does not run before the match starts")
	controller.timer_running = true
	controller._process(0.25)
	_check(is_equal_approx(probe.elapsed, 0.25), "Active match frames advance condition time")
	_check(is_equal_approx(second_probe.elapsed, 0.25), "A failed earlier condition does not prevent later conditions accumulating time")
	controller.timer_running = false
	controller._process(0.2)
	_check(is_equal_approx(probe.elapsed, 0.25), "Stopped matches do not advance condition time")
	controller.timer_running = true
	controller._process(1.0)
	_check(is_equal_approx(probe.elapsed, 0.75), "The final frame counts only the time remaining in the match")
	controller._process(0.2)
	_check(is_equal_approx(probe.elapsed, 0.75), "Condition time stops at match expiry")
	Globals.victory_conditions = original_conditions
	controller.time_left_seconds = original_time
	controller.timer_running = original_running
	controller.end_game_handled = original_ended


func _test_projection_origin() -> void:
	var cells: Array[Vector2i] = ProjectionSourceBuilder.get_projected_line_hexes(Vector2i(1, 0), Vector2i.ZERO, 0, 0, 0)
	_check(cells.has(Vector2i.ZERO), "Influence projection includes the valid origin tile")


func _test_retreat_origin() -> void:
	var unit: Unit = Globals.get_units()[0]
	var probe: RetreatProbe = RetreatProbe.new()
	probe.unit = unit
	probe.destination = Vector2i.ZERO
	probe.rout_failed.connect(_on_rout_failed)
	var failures_before: int = rout_failures
	probe._start_rout()
	_check(rout_failures == failures_before, "A rout destination at (0,0) is accepted")
	_check(unit.movement.target_hex == Vector2i.ZERO and unit.movement.retreating, "Rout orders reach the origin tile")
	unit.movement.stop()
	probe.destination = unit.current_hex
	failures_before = rout_failures
	probe._start_rout()
	_check(rout_failures == failures_before + 1, "No retreat candidate reports failure instead of routing to the current tile")
	probe.free()


func _on_rout_failed() -> void:
	rout_failures += 1


func _advance(condition: OccupyObjectiveCondition, delta: float) -> void:
	if condition.has_method("advance_time"):
		condition.call("advance_time", delta)
	else:
		condition.is_condition_met()


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		var timer: Timer = node as Timer
		timer.stop()
	for child: Node in node.get_children():
		_freeze(child)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
