extends Node

class UnitProbe extends Unit:
	func _ready() -> void:
		pass


class ControllerProbe extends "res://scenes/game/match_controller.gd":
	func update_visible_hexes() -> void:
		pass

	func show_visible_units() -> void:
		pass

	func draw_fog() -> void:
		pass

	func set_close_combat_hexes_and_units() -> void:
		pass


class UnknownCondition extends VictoryCondition:
	func is_condition_met() -> bool:
		return false


var checks: int = 0
var failures: int = 0
var host: ControllerProbe
var scenario: Scenario
var friends: Array[Unit] = []
var enemies: Array[Unit] = []
var winners: Array[Dictionary] = []
var reenter_result: bool = false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = Node.new()
	main.name = "Main"
	get_tree().root.add_child(main)
	var world: Node = Node.new()
	world.name = "World"
	main.add_child(world)
	var audio: AudioPool = AudioPool.new()
	audio.name = "AudioPool"
	world.add_child(audio)
	scenario = Scenario.new()
	scenario.scenario_name = "Objective defeat fixture"
	Globals.scenario_chosen = scenario
	host = ControllerProbe.new()
	host.show_winner.connect(_on_winner)
	for index: int in range(3):
		friends.append(_unit())
		enemies.append(_unit())
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		await _test_exit_losses(team)
		_test_major_still_possible(team)
		await _test_prevention(team)
		await _test_destroy_quota(team)
		await _test_completed_minor(team)
		await _test_capture_routes(team)
		_test_insufficient_garrisons(team)
		_test_uncertain_conditions(team)
		_test_enemy_result(team)
		await _test_deferred_recheck(team)
	Globals.victory_conditions.clear()
	Globals.units_destroyed = UnitsCollection.new()
	Globals.scenario_chosen = null
	for unit: Unit in friends + enemies:
		unit.squad_fire.calc.free()
		unit.free()
	host.free()
	scenario.free()
	main.free()
	print("Objective defeat checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _unit() -> Unit:
	var unit: Unit = load("res://scenes/game/units/unit.tscn").instantiate()
	unit.set_script(UnitProbe)
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(unit)
	unit.add_to_group("units")
	return unit


func _reset(team: Globals.Team) -> void:
	Globals.team_player = team
	Globals.units_destroyed = UnitsCollection.new()
	Globals.victory_conditions = {team: VictoryConditionCollection.new(), Globals.get_enemy_team(team): VictoryConditionCollection.new()}
	winners.clear()
	reenter_result = false
	host.end_game_handled = false
	host.timer_running = true
	host.time_left_seconds = 120.0
	host.overtime_active = false
	host.overtime_packages.clear()
	for unit: Unit in friends + enemies:
		unit.team = Globals.get_enemy_team(team)
		if friends.has(unit):
			unit.team = team
		unit.alive = true
		unit.exited = false
		unit.surrendered = false
		unit.broken = false
		unit.remove_from_group("dead_units")
		unit.remove_from_group("exited_units")
		unit.add_to_group("units")


func _conditions(conditions: Array[VictoryCondition]) -> void:
	scenario.victory_conditions = conditions
	for condition: VictoryCondition in conditions:
		Globals.victory_conditions[condition.team].victory_conditions.append(condition)


func _exit(level: VictoryCondition.OutcomeLevel, count: int) -> ExitUnitsCondition:
	var condition: ExitUnitsCondition = ExitUnitsCondition.new()
	condition.team = Globals.team_player
	condition.outcome_level = level
	condition.required_unit_count = count
	condition.test_at_scenario_end = true
	condition.state = ExitUnitsState.new()
	condition.state.exit_hexes = [Vector2i(9, 9)]
	return condition


func _destroy(level: VictoryCondition.OutcomeLevel, count: int) -> DestroyUnitsCondition:
	var condition: DestroyUnitsCondition = DestroyUnitsCondition.new()
	condition.team = Globals.team_player
	condition.outcome_level = level
	condition.required_unit_count = count
	condition.test_at_scenario_end = true
	return condition


func _prevent(level: VictoryCondition.OutcomeLevel, count: int) -> PreventEnemyExitCondition:
	var condition: PreventEnemyExitCondition = PreventEnemyExitCondition.new()
	condition.team = Globals.team_player
	condition.outcome_level = level
	condition.max_allowed_enemy_exits = count
	condition.state = ExitUnitsState.new()
	condition.state.exit_hexes = [Vector2i(8, 8)]
	return condition


func _occupy(level: VictoryCondition.OutcomeLevel, hexes: Array[Vector2i], count: int = 1) -> OccupyObjectiveCondition:
	var condition: OccupyObjectiveCondition = OccupyObjectiveCondition.new()
	condition.team = Globals.team_player
	condition.outcome_level = level
	condition.required_time_s = 300.0
	condition.required_unit_count = count
	condition.test_at_scenario_end = true
	condition.state = OccupyObjectiveState.new()
	condition.state.hexes = hexes
	for hex: Vector2i in hexes:
		condition.state.required_times_reached_s[hex] = 0.0
		condition.state.victory_conditions_met[hex] = false
		condition.state.units_in_objectives[hex] = UnitsCollection.new()
	return condition


func _retire(unit: Unit) -> void:
	unit.exited = true
	unit.remove_from_group("units")
	unit.add_to_group("exited_units")


func _test_exit_losses(team: Globals.Team) -> void:
	_reset(team)
	var major: ExitUnitsCondition = _exit(VictoryCondition.OutcomeLevel.MAJOR, 3)
	var minor: ExitUnitsCondition = _exit(VictoryCondition.OutcomeLevel.MINOR, 2)
	_conditions([major, minor])
	friends[0].surrendered = true
	host._on_unit_surrendered(friends[0])
	await get_tree().process_frame
	_check(not MatchVictoryCoordinator.can_finish_after_objective_defeat(host) and winners.is_empty(), "Losing major exit victory keeps a reachable minor victory in play")
	friends[1].surrendered = true
	reenter_result = true
	host._on_unit_surrendered(friends[1])
	await get_tree().process_frame
	_check_defeat("Losing enough squads to rule out both exit quotas ends the map")
	_check(friends[2].is_active() and not friends[2].surrendered and not MatchVictoryCoordinator.can_finish_after_force_defeat(), "Objective defeat does not require eliminating the player's last squad")
	_check(major.state.units_exited.is_empty() and minor.state.units_exited.is_empty(), "Ending an impossible mission does not invent objective credit")
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1, "Deferred, repeated and reentrant checks produce one result")
	var screen: CanvasLayer = load("res://scenes/ui/screens/match_result_screen.tscn").instantiate()
	add_child(screen)
	screen._on_show_winner(winners[0]["team"], winners[0]["level"], winners[0]["timeout"])
	_check(screen.result_label.text == "Defeat", "An unreachable player objective produces a clear defeat on the existing result screen")
	screen.free()


func _test_major_still_possible(team: Globals.Team) -> void:
	_reset(team)
	_conditions([_exit(VictoryCondition.OutcomeLevel.MAJOR, 2), _exit(VictoryCondition.OutcomeLevel.MINOR, 4)])
	for unit: Unit in friends:
		unit.broken = true
		unit.stress_system.state = STATES.MoraleState.PINNED
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.is_empty() and host.timer_running, "A reachable major victory prevents defeat even if minor victory is impossible and squads are pinned or routed")


func _test_prevention(team: Globals.Team) -> void:
	_reset(team)
	var major: PreventEnemyExitCondition = _prevent(VictoryCondition.OutcomeLevel.MAJOR, 0)
	var minor: PreventEnemyExitCondition = _prevent(VictoryCondition.OutcomeLevel.MINOR, 1)
	_conditions([major, _destroy(VictoryCondition.OutcomeLevel.MAJOR, 2), minor, _occupy(VictoryCondition.OutcomeLevel.MINOR, [Vector2i.ZERO])])
	for index: int in range(2):
		major.state.units_exited.append(enemies[index])
		minor.state.units_exited.append(enemies[index])
		_retire(enemies[index])
		host._on_unit_exited(enemies[index])
		await get_tree().process_frame
		if index == 0:
			_check(winners.is_empty(), "Breaching the major prevention limit does not end a still-recoverable minor objective package")
	_check_defeat("Exceeding both enemy-exit limits ends the map immediately")
	_check(major.state.units_exited.size() == 2 and minor.state.units_exited.size() == 2, "Defeat preserves actual enemy exit counts")


func _test_destroy_quota(team: Globals.Team) -> void:
	_reset(team)
	_conditions([_destroy(VictoryCondition.OutcomeLevel.MAJOR, 3), _destroy(VictoryCondition.OutcomeLevel.MINOR, 2)])
	enemies[0].alive = false
	enemies[0].remove_from_group("units")
	enemies[0].add_to_group("dead_units")
	host._on_unit_died(enemies[0])
	_retire(enemies[1])
	host._on_unit_exited(enemies[1])
	await get_tree().process_frame
	_check(winners.is_empty(), "Previously defeated enemies count toward the remaining achievable destruction quota")
	_retire(enemies[2])
	host._on_unit_exited(enemies[2])
	await get_tree().process_frame
	_check_defeat("Enemy escapes that make both destruction quotas unreachable end the map")
	_check(Globals.units_destroyed.units_collection[team].units.size() == 1, "Escaped enemies are not falsely credited as destroyed")


func _test_completed_minor(team: Globals.Team) -> void:
	_reset(team)
	var major: ExitUnitsCondition = _exit(VictoryCondition.OutcomeLevel.MAJOR, 4)
	var minor: ExitUnitsCondition = _exit(VictoryCondition.OutcomeLevel.MINOR, 2)
	_conditions([major, minor])
	for index: int in range(2):
		major.state.units_exited.append(friends[index])
		minor.state.units_exited.append(friends[index])
		_retire(friends[index])
	_check(not MatchVictoryCoordinator.can_finish_after_objective_defeat(host), "Completed exits remain an achievable minor result after the squads leave the map")
	friends[2].alive = false
	friends[2].remove_from_group("units")
	friends[2].add_to_group("dead_units")
	host._on_unit_died(friends[2])
	await get_tree().process_frame
	_check(winners.size() == 1 and winners[0]["team"] == team and winners[0]["level"] == VictoryCondition.OutcomeLevel.MINOR, "Losing the rear guard does not erase an already earned minor victory")


func _test_capture_routes(team: Globals.Team) -> void:
	_reset(team)
	var occupation: OccupyObjectiveCondition = _occupy(VictoryCondition.OutcomeLevel.MAJOR, [Vector2i(4, 4), Vector2i(5, 5)], 2)
	_conditions([occupation])
	friends[0].surrendered = true
	friends[1].surrendered = true
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.is_empty(), "Insufficient garrisons and a short clock cannot rule out victory by eliminating the remaining enemy")
	_check(occupation.state.required_times_reached_s[Vector2i(4, 4)] == 0.0, "Feasibility checks do not advance occupation time")
	for unit: Unit in enemies:
		unit.surrendered = true
		Globals.units_destroyed.units_collection[team].units.append(unit)
	host._on_unit_surrendered(enemies[2])
	await get_tree().process_frame
	_check(winners.size() == 1 and winners[0]["team"] == team and occupation.is_condition_met(), "Eliminating the enemy still secures unoccupied objectives before final scoring")


func _test_insufficient_garrisons(team: Globals.Team) -> void:
	_reset(team)
	for unit: Unit in enemies:
		_retire(unit)
	_conditions([_occupy(VictoryCondition.OutcomeLevel.MAJOR, [Vector2i(1, 1), Vector2i(2, 2)], 2)])
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check_defeat("After every enemy escapes, too few squads to hold every required hex makes the mission impossible")


func _test_uncertain_conditions(team: Globals.Team) -> void:
	_reset(team)
	var unknown: UnknownCondition = UnknownCondition.new()
	unknown.team = team
	unknown.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	_conditions([_exit(VictoryCondition.OutcomeLevel.MAJOR, 4), unknown])
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.is_empty(), "Unsupported conditions are not guessed to be impossible")
	_reset(team)
	var incomplete: ExitUnitsCondition = _exit(VictoryCondition.OutcomeLevel.MAJOR, 4)
	incomplete.state = null
	_conditions([incomplete])
	_check(not MatchVictoryCoordinator.can_finish_after_objective_defeat(host), "Missing objective state cannot cause an automatic defeat")
	_reset(team)
	_check(not MatchVictoryCoordinator.can_finish_after_objective_defeat(host), "A scenario without player objectives is not automatically lost")
	_conditions([_exit(VictoryCondition.OutcomeLevel.MAJOR, 4)])
	host.timer_running = false
	_check(not MatchVictoryCoordinator.can_finish_after_objective_defeat(host), "Deployment does not end the map before the battle clock starts")
	host.timer_running = true
	host.time_left_seconds = 0.0
	_check(not MatchVictoryCoordinator.can_finish_after_objective_defeat(host), "The deadline retains its ordinary timeout and overtime scoring")


func _test_enemy_result(team: Globals.Team) -> void:
	_reset(team)
	var enemy_victory: DestroyUnitsCondition = _destroy(VictoryCondition.OutcomeLevel.MAJOR, 0)
	enemy_victory.team = Globals.get_enemy_team(team)
	_conditions([_exit(VictoryCondition.OutcomeLevel.MAJOR, 4), enemy_victory])
	reenter_result = true
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1 and winners[0]["team"] == enemy_victory.team and winners[0]["level"] == VictoryCondition.OutcomeLevel.MAJOR, "An earned enemy major victory takes priority over the fallback defeat result")


func _test_deferred_recheck(team: Globals.Team) -> void:
	_reset(team)
	_conditions([_exit(VictoryCondition.OutcomeLevel.MAJOR, 4), _exit(VictoryCondition.OutcomeLevel.MINOR, 3)])
	friends[0].surrendered = true
	host._on_unit_surrendered(friends[0])
	var reinforcement: Unit = _unit()
	reinforcement.team = team
	await get_tree().process_frame
	_check(winners.is_empty() and host.timer_running, "A deferred loss check re-evaluates newly arrived squads before ending the match")
	reinforcement.squad_fire.calc.free()
	reinforcement.free()


func _check_defeat(description: String) -> void:
	_check(host.end_game_handled and not host.timer_running and winners.size() == 1 and winners[0]["team"] == Globals.get_enemy_team(Globals.team_player) and not winners[0]["timeout"], description)
	_check(host.time_left_seconds == 120.0, "Early defeat preserves the remaining time instead of pretending the deadline expired")


func _on_winner(team: int, level: VictoryCondition.OutcomeLevel, timeout: bool) -> void:
	winners.append({"team": team, "level": level, "timeout": timeout})
	if reenter_result:
		MatchVictoryCoordinator.on_win_condition_timer_timeout(host)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
