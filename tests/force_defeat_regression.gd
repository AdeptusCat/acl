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


var failures: int = 0
var winners: Array[Dictionary] = []
var host: ControllerProbe
var friends: Unit
var enemies: Array[Unit] = []
var destroy: DestroyUnitsCondition
var prevent: PreventEnemyExitCondition


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var audio_root: Node = Node.new()
	audio_root.name = "Main"
	get_tree().root.add_child(audio_root)
	var audio_world: Node = Node.new()
	audio_world.name = "World"
	audio_root.add_child(audio_world)
	var audio: AudioPool = AudioPool.new()
	audio.name = "AudioPool"
	audio_world.add_child(audio)
	Globals.scenario_chosen = Scenario.new()
	Globals.team_player = Globals.Team.ALLIES
	host = ControllerProbe.new()
	host.show_winner.connect(_on_winner)
	friends = _unit(Globals.Team.ALLIES)
	enemies = [_unit(Globals.Team.AXIS), _unit(Globals.Team.AXIS)]
	_reset()
	enemies[0].surrendered = true
	enemies[1].broken = true
	_check(not MatchVictoryCoordinator.can_finish_after_force_defeat(), "A living routed unit still prevents elimination scoring")
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.is_empty(), "Partial surrender does not score deadline-only conditions early")
	enemies[1].surrendered = true
	Globals.units_destroyed.units_collection[friends.team].units.assign(enemies)
	host._on_unit_surrendered(enemies[1])
	await get_tree().process_frame
	_check(host.end_game_handled and winners.size() == 1 and winners[0]["team"] == friends.team and winners[0]["level"] == VictoryCondition.OutcomeLevel.MAJOR, "The last surrender ends the match and compares major victory conditions")
	_check(not host.timer_running and host.time_left_seconds == 600.0 and not winners[0]["timeout"], "Elimination ends the clock without pretending the deadline expired")
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1, "Elimination emits only one result")
	_reset()
	for unit: Unit in enemies:
		unit.alive = false
		unit.remove_from_group("units")
		unit.add_to_group("dead_units")
		host._on_unit_died(unit)
	await get_tree().process_frame
	_check(winners.size() == 1 and winners[0]["team"] == friends.team and winners[0]["level"] == VictoryCondition.OutcomeLevel.MAJOR, "The last death scores after the destruction ledger is updated")
	_reset()
	destroy.required_unit_count = 3
	for unit: Unit in enemies:
		unit.surrendered = true
	Globals.units_destroyed.units_collection[friends.team].units.assign(enemies)
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1 and winners[0]["level"] == VictoryCondition.OutcomeLevel.MINOR, "Elimination cannot fabricate an unmet major destruction quota")
	_reset()
	destroy.required_unit_count = 3
	prevent.state.units_exited.assign(enemies)
	for unit: Unit in enemies:
		unit.surrendered = true
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1 and winners[0]["team"] == -1, "Elimination compares both sides and allows a draw when neither outcome is earned")
	_reset()
	friends.alive = false
	Globals.units_destroyed.units_collection[Globals.Team.AXIS].units.append(friends)
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1 and winners[0]["team"] == Globals.Team.AXIS, "Player elimination also compares the opposing victory conditions")
	_reset()
	enemies[0].exited = true
	enemies[1].surrendered = true
	_check(MatchVictoryCoordinator.can_finish_after_force_defeat(), "An earlier escape cannot keep the battle running after the last remaining enemy surrenders")
	Globals.units_destroyed.units_collection[friends.team].units.append(enemies[1])
	prevent.state.units_exited.append(enemies[0])
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1 and winners[0]["level"] == VictoryCondition.OutcomeLevel.MINOR and prevent.state.units_exited.size() == 1, "Mixed exits and surrender preserve exit credit without inventing destroyed squads")
	_reset()
	for unit: Unit in enemies:
		unit.exited = true
	_check(not MatchVictoryCoordinator.can_finish_after_force_defeat(), "A force that only exits retains the authored exit-completion rules")
	_reset()
	var stale: OccupyObjectiveCondition = OccupyObjectiveCondition.new()
	stale.team = Globals.Team.AXIS
	stale.test_at_scenario_end = true
	stale.state = OccupyObjectiveState.new()
	stale.state.hexes = [Vector2i.ZERO]
	stale.state.required_times_reached_s[Vector2i.ZERO] = stale.required_time_s
	stale.state.victory_conditions_met[Vector2i.ZERO] = true
	stale.state.units_in_objectives[Vector2i.ZERO] = UnitsCollection.new()
	Globals.victory_conditions[Globals.Team.AXIS].victory_conditions = [stale]
	for unit: Unit in enemies:
		unit.surrendered = true
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1 and winners[0]["team"] == friends.team and not stale.is_condition_met(), "Final scoring clears a defeated garrison's stale occupation before comparing results")
	_reset()
	var occupation: OccupyObjectiveCondition = OccupyObjectiveCondition.new()
	occupation.team = friends.team
	occupation.test_at_scenario_end = true
	occupation.required_time_s = 10.0
	occupation.state = OccupyObjectiveState.new()
	occupation.state.hexes = [Vector2i.ZERO]
	occupation.state.required_times_reached_s[Vector2i.ZERO] = 2.0
	occupation.state.victory_conditions_met[Vector2i.ZERO] = false
	occupation.state.units_in_objectives[Vector2i.ZERO] = UnitsCollection.new()
	Globals.victory_conditions[friends.team].victory_conditions.append(occupation)
	host.time_left_seconds = 0.0
	host.overtime_active = true
	destroy.required_unit_count = 0
	for unit: Unit in enemies:
		unit.surrendered = true
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(host.end_game_handled and not host.overtime_active and host.overtime_packages.is_empty(), "Elimination ends occupation overtime immediately")
	_check(winners.size() == 1 and winners[0]["level"] == VictoryCondition.OutcomeLevel.MAJOR and occupation.is_condition_met(), "Eliminating the enemy completes an occupation already running during overtime")
	await _test_running_occupation()
	for unit: Unit in [friends, enemies[0], enemies[1]]:
		unit.squad_fire.calc.free()
		unit.free()
	host.free()
	Globals.scenario_chosen.free()
	Globals.scenario_chosen = null
	Globals.victory_conditions.clear()
	Globals.units_destroyed = UnitsCollection.new()
	audio_root.free()
	print("Force defeat regression failures: ", failures)
	get_tree().quit(failures)


func _test_running_occupation() -> void:
	_reset()
	var occupation: OccupyObjectiveCondition = _occupation(friends.team)
	Globals.victory_conditions[friends.team].victory_conditions.append(occupation)
	for unit: Unit in enemies:
		unit.surrendered = true
	Globals.units_destroyed.units_collection[friends.team].units.assign(enemies)
	host._on_unit_surrendered(enemies[1])
	await get_tree().process_frame
	_check(winners.size() == 1 and winners[0]["team"] == friends.team and winners[0]["level"] == VictoryCondition.OutcomeLevel.MAJOR, "The final surrender completes a running capture before comparing victory levels")
	_check(occupation.is_condition_met() and is_equal_approx(occupation.state.required_times_reached_s[Vector2i.ZERO], occupation.required_time_s) and VictoryConditionProgress.read(occupation).complete, "Completed capture time and result display agree after an early finish")
	_check(host.time_left_seconds == 600.0 and not winners[0]["timeout"], "Completing a capture at elimination preserves the remaining battle time")
	_reset()
	occupation = _occupation(friends.team)
	Globals.victory_conditions[friends.team].victory_conditions.append(occupation)
	for unit: Unit in enemies:
		unit.alive = false
		unit.remove_from_group("units")
		unit.add_to_group("dead_units")
		host._on_unit_died(unit)
	await get_tree().process_frame
	_check(winners.size() == 1 and winners[0]["level"] == VictoryCondition.OutcomeLevel.MAJOR and occupation.is_condition_met(), "The final death completes a running capture after updating the destruction ledger")
	_reset()
	occupation = _occupation(friends.team)
	Globals.victory_conditions[friends.team].victory_conditions.append(occupation)
	destroy.required_unit_count = 0
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.is_empty() and not occupation.is_condition_met() and occupation.state.required_times_reached_s[Vector2i.ZERO] == 2.0, "A surviving enemy leaves the normal capture timer running")
	_reset()
	occupation = _occupation(friends.team)
	Globals.victory_conditions[friends.team].victory_conditions.append(occupation)
	destroy.required_unit_count = 0
	friends.current_hex = Vector2i(9, 9)
	for unit: Unit in enemies:
		unit.surrendered = true
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(not occupation.is_condition_met() and occupation.state.required_times_reached_s[Vector2i.ZERO] == 0.0 and winners[0]["level"] == VictoryCondition.OutcomeLevel.MINOR, "An abandoned objective cannot inherit completion from its stale capture timer")
	_reset()
	occupation = _occupation(friends.team, [Vector2i.ZERO], 0.0)
	Globals.victory_conditions[friends.team].victory_conditions.append(occupation)
	destroy.required_unit_count = 0
	for unit: Unit in enemies:
		unit.surrendered = true
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(not occupation.is_condition_met(), "An occupation timer that never started is not awarded at elimination")
	_reset()
	occupation = _occupation(friends.team)
	occupation.required_unit_count = 2
	Globals.victory_conditions[friends.team].victory_conditions.append(occupation)
	destroy.required_unit_count = 0
	for unit: Unit in enemies:
		unit.surrendered = true
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(not occupation.is_condition_met(), "Elimination still requires the authored number of occupying squads")
	_reset()
	occupation = _occupation(friends.team, [Vector2i.ZERO, Vector2i(1, 0)])
	Globals.victory_conditions[friends.team].victory_conditions.append(occupation)
	destroy.required_unit_count = 0
	for unit: Unit in enemies:
		unit.surrendered = true
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(occupation.state.victory_conditions_met[Vector2i.ZERO] and not occupation.state.victory_conditions_met[Vector2i(1, 0)] and not occupation.is_condition_met(), "A capture across several markers only completes the markers still being occupied")
	_reset()
	occupation = _occupation(Globals.Team.AXIS)
	Globals.victory_conditions[Globals.Team.AXIS].victory_conditions.append(occupation)
	friends.alive = false
	Globals.units_destroyed.units_collection[Globals.Team.AXIS].units.append(friends)
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1 and winners[0]["team"] == Globals.Team.AXIS and occupation.is_condition_met(), "Early capture completion applies equally when the player's force is eliminated")


func _occupation(team: Globals.Team, hexes: Array[Vector2i] = [Vector2i.ZERO], held_seconds: float = 2.0) -> OccupyObjectiveCondition:
	var occupation: OccupyObjectiveCondition = OccupyObjectiveCondition.new()
	occupation.team = team
	occupation.required_time_s = 10.0
	occupation.test_at_scenario_end = true
	occupation.state = OccupyObjectiveState.new()
	occupation.state.hexes = hexes.duplicate()
	for hex: Vector2i in hexes:
		occupation.state.required_times_reached_s[hex] = held_seconds
		occupation.state.victory_conditions_met[hex] = false
		occupation.state.units_in_objectives[hex] = UnitsCollection.new()
	return occupation


func _unit(team: Globals.Team) -> Unit:
	var unit: Unit = load("res://scenes/game/units/unit.tscn").instantiate()
	unit.set_script(UnitProbe)
	unit.team = team
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(unit)
	unit.add_to_group("units")
	return unit


func _reset() -> void:
	winners.clear()
	host.end_game_handled = false
	host.timer_running = true
	host.time_left_seconds = 600.0
	host.overtime_active = false
	host.overtime_packages.clear()
	Globals.units_destroyed = UnitsCollection.new()
	for unit: Unit in [friends, enemies[0], enemies[1]]:
		unit.alive = true
		unit.exited = false
		unit.surrendered = false
		unit.broken = false
		unit.current_hex = Vector2i.ZERO
		unit.remove_from_group("dead_units")
		unit.add_to_group("units")
	destroy = DestroyUnitsCondition.new()
	destroy.team = friends.team
	destroy.required_unit_count = 2
	destroy.test_at_scenario_end = true
	prevent = PreventEnemyExitCondition.new()
	prevent.team = friends.team
	prevent.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	prevent.max_allowed_enemy_exits = 1
	prevent.test_at_scenario_end = true
	prevent.state = ExitUnitsState.new()
	prevent.state.exit_hexes = [Vector2i(9, 9)]
	var enemy_destroy: DestroyUnitsCondition = DestroyUnitsCondition.new()
	enemy_destroy.team = Globals.Team.AXIS
	enemy_destroy.test_at_scenario_end = true
	var own: VictoryConditionCollection = VictoryConditionCollection.new()
	own.victory_conditions = [destroy, prevent]
	var opposing: VictoryConditionCollection = VictoryConditionCollection.new()
	opposing.victory_conditions = [enemy_destroy]
	Globals.victory_conditions = {friends.team: own, Globals.Team.AXIS: opposing}


func _on_winner(team: int, level: VictoryCondition.OutcomeLevel, timeout: bool) -> void:
	winners.append({"team": team, "level": level, "timeout": timeout})


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
