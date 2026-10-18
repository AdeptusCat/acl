extends Node

class UnitProbe extends Unit:
	func _ready() -> void:
		pass


var checks: int = 0
var failures: int = 0
var winners: Array[Dictionary] = []
var friends: Array[Unit] = []
var enemy: Unit
var scenario: Scenario
var host: Node2D
var panel: MissionObjectivesPanel
var result_screen: CanvasLayer


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
	# Use the authored markers and conditions without baking LOS or starting combat.
	var map: Map = load("res://scenes/campaigns/alderbrook/05_battle_for_alderbrook.tscn").instantiate()
	scenario = map.get_node("Scenarios/Mission") as Scenario
	scenario.axis_objectives_tile_map_layer = scenario.get_node("Objectives/AxisObjectivesTileMapLayer") as HexagonTileMapLayer
	scenario.allied_objectives_tile_map_layer = scenario.get_node("Objectives/AlliedObjectivesTileMapLayer") as HexagonTileMapLayer
	Globals.scenario_chosen = scenario
	Globals.team_player = scenario.player_team
	scenario.axis_objectives_tile_map_layer._on_tileset_changed()
	scenario.allied_objectives_tile_map_layer._on_tileset_changed()
	Globals.objectives = scenario.get_objectives()
	Globals.victory_conditions = scenario.get_victory_conditions()
	Globals.units_destroyed = UnitsCollection.new()
	host = load("res://scenes/game/match_controller.gd").new()
	host.time_left_seconds = 600.0
	host.timer_running = true
	host.show_winner.connect(_on_winner)
	MatchVictoryCoordinator.set_victory_conditions(host)
	for objective: ObjectiveDefinition in Globals.objectives[Globals.team_player].objectives:
		var friend: Unit = _make_unit()
		friend.team = Globals.team_player
		friend.current_hex = objective.hex
		add_child(friend)
		friend.add_to_group("units")
		friends.append(friend)
	enemy = _make_unit()
	enemy.team = Globals.get_enemy_team(Globals.team_player)
	enemy.current_hex = Vector2i(-50, -50)
	add_child(enemy)
	enemy.add_to_group("units")
	panel = load("res://scenes/ui/hud/battle_hud.tscn").instantiate().get_node("Control/MissionObjectives") as MissionObjectivesPanel
	# Detach the panel before freeing the unused HUD fixture.
	var hud: Node = panel.get_parent().get_parent()
	panel.get_parent().remove_child(panel)
	hud.free()
	add_child(panel)
	panel.setup(scenario.victory_conditions, Globals.team_player, host.time_left_seconds)
	result_screen = load("res://scenes/ui/screens/match_result_screen.tscn").instantiate()
	add_child(result_screen)
	result_screen.hide()
	_check(scenario.end_when_objectives_secured_and_enemy_gone, "Alderbrook enables secured-objective completion")
	var c: OccupyObjectiveCondition = _capture(OccupyObjectiveCondition.ObjectiveId.C)
	_check(c.state.hexes == [Vector2i(16, 15)], "The authored C condition binds the timber-yard marker")
	_advance(44.0)
	panel.refresh()
	_check((panel.rows.get_child(2) as Label).text == "Objective C: securing · 44/45 s", "C displays its unmet continuous hold requirement")
	_check(not c.is_condition_met(), "Occupation alone cannot bypass the authored 45-second capture")
	_show_result()
	var c_row: VictoryConditionResult = result_screen.major_victory_conditions_v_box_container.get_child(2) as VictoryConditionResult
	_check(not c_row.check_box.button_pressed and c_row.label.text.contains("Held: 44/45 s"), "Unfinished C result explains the missing hold time")
	_advance(1.0)
	panel.refresh()
	_check(c.is_condition_met() and (panel.rows.get_child(2) as Label).text == "Objective C: player controlled", "Secured C agrees with the live capture condition")
	_show_result()
	c_row = result_screen.major_victory_conditions_v_box_container.get_child(2) as VictoryConditionResult
	_check(c_row.check_box.button_pressed and c_row.label.text.contains("Held: 45/45 s"), "Results credit secured C and replace previous rows")
	_check(result_screen.major_victory_conditions_v_box_container.get_child_count() == 5, "Repeated results never retain stale objective checkboxes")
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.is_empty() and host.timer_running, "An active defender prevents early deadline scoring")
	enemy.broken = true
	_check(not MatchVictoryCoordinator.can_finish_after_enemy_departure(), "A routed defender still on the map prevents early completion")
	enemy.exited = true
	_check(MatchVictoryCoordinator.can_finish_after_enemy_departure(), "Escaped last defender allows secured objectives to finish the mission")
	var friend_c: Unit
	for friend: Unit in friends:
		if friend.current_hex == c.state.hexes[0]:
			friend_c = friend
	friend_c.current_hex = Vector2i(-50, -49)
	_advance(0.1)
	_check(not MatchVictoryCoordinator.can_finish_after_enemy_departure() and not c.is_condition_met(), "An empty capture hex prevents early completion and resets the hold")
	friend_c.current_hex = c.state.hexes[0]
	_advance(45.0)
	scenario.end_when_objectives_secured_and_enemy_gone = false
	_check(not MatchVictoryCoordinator.can_finish_after_enemy_departure(), "Other missions retain their deadline unless explicitly enabled")
	scenario.end_when_objectives_secured_and_enemy_gone = true
	_test_outcomes()
	panel.free()
	result_screen.free()
	for friend: Unit in friends:
		friend.squad_fire.calc.free()
		friend.free()
	enemy.squad_fire.calc.free()
	enemy.free()
	host.free()
	Globals.scenario_chosen = null
	Globals.victory_conditions.clear()
	Globals.objectives.clear()
	Globals.units_destroyed = UnitsCollection.new()
	map.free()
	audio_root.free()
	print("Alderbrook completion checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _make_unit() -> Unit:
	var unit: Unit = load("res://scenes/game/units/unit.tscn").instantiate()
	unit.set_script(UnitProbe)
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	return unit


func _capture(id: OccupyObjectiveCondition.ObjectiveId) -> OccupyObjectiveCondition:
	for condition: VictoryCondition in Globals.victory_conditions[Globals.team_player].victory_conditions:
		if condition is OccupyObjectiveCondition and (condition as OccupyObjectiveCondition).objective_id == id:
			return condition as OccupyObjectiveCondition
	return null


func _advance(seconds: float) -> void:
	for team: Globals.Team in Globals.victory_conditions:
		for condition: VictoryCondition in Globals.victory_conditions[team].victory_conditions:
			condition.advance_time(seconds)


func _show_result() -> void:
	result_screen._on_show_winner(-1, VictoryCondition.OutcomeLevel.MAJOR, true)
	result_screen.hide()


func _test_outcomes() -> void:
	var destroyed: Array[Unit] = Globals.units_destroyed.units_collection[Globals.team_player].units
	for index: int in range(6):
		var casualty: UnitProbe = UnitProbe.new()
		casualty.alive = false
		destroyed.append(casualty)
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1 and winners[0]["team"] == Globals.team_player and winners[0]["level"] == VictoryCondition.OutcomeLevel.MAJOR, "Major victory is assessed early with the original destruction quota")
	_check(host.end_game_handled and not host.timer_running and host.time_left_seconds == 600.0, "Early completion stops the clock without inventing a timeout")
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1, "Completion emits only one result")
	var prevention: PreventEnemyExitCondition
	for condition: VictoryCondition in Globals.victory_conditions[Globals.team_player].victory_conditions:
		if condition is PreventEnemyExitCondition:
			prevention = condition as PreventEnemyExitCondition
	prevention.state.units_exited.assign([enemy, destroyed[0]])
	host.end_game_handled = false
	host.timer_running = true
	winners.clear()
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1 and winners[0]["team"] == Globals.team_player and winners[0]["level"] == VictoryCondition.OutcomeLevel.MINOR, "Excess enemy escapes still prevent a major victory after early completion")
	for casualty: Unit in destroyed:
		casualty.free()
	destroyed.clear()
	host.end_game_handled = false
	host.timer_running = true
	winners.clear()
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1 and winners[0]["team"] == -1 and not winners[0]["timeout"], "Securing the town cannot fabricate destroyed squads or a victory")


func _on_winner(team: int, level: VictoryCondition.OutcomeLevel, timeout: bool) -> void:
	winners.append({"team": team, "level": level, "timeout": timeout})


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
