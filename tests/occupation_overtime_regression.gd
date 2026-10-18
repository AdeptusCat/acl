extends Node

class UnitProbe extends Unit:
	func _ready() -> void:
		pass


var failures: int = 0
var winners: Array[int] = []
var host: Node2D
var holder: UnitProbe
var enemy: UnitProbe
var occupation: OccupyObjectiveCondition
var other: DestroyUnitsCondition


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(main)
	host = main.world.game_controller
	for connection: Dictionary in host.show_winner.get_connections():
		host.show_winner.disconnect(connection["callable"])
	Globals.scenario_chosen = null
	Globals.objectives.clear()
	Globals.units_destroyed = UnitsCollection.new()
	host.set_process(false)
	host.show_winner.connect(_on_winner)
	holder = _make_unit()
	holder.team = Globals.Team.ALLIES
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(holder)
	holder.add_to_group("units")
	enemy = _make_unit()
	enemy.team = Globals.Team.AXIS
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(enemy)
	enemy.add_to_group("units")
	_reset()
	host._process(0.5)
	_check(host.overtime_active and host.timer_running and not host.end_game_handled and winners.is_empty(), "A running occupation with all other requirements met extends the deadline")
	_check(is_equal_approx(occupation.state.required_times_reached_s[Vector2i.ZERO], 2.5), "The deadline frame advances occupation only by the remaining match time")
	host._process(0.5)
	_check(is_equal_approx(occupation.state.required_times_reached_s[Vector2i.ZERO], 3.0) and is_equal_approx(host.overtime_elapsed_seconds, 0.5), "Occupation and overtime clocks advance after the deadline")
	host._process(1.0)
	_check(winners == [int(Globals.Team.ALLIES)] and host.end_game_handled and not host.timer_running and not host.overtime_active, "Finishing the hold during overtime awards the victory once")
	host._process(1.0)
	MatchVictoryCoordinator.on_win_condition_timer_timeout(host)
	_check(winners.size() == 1, "Overtime cannot emit a duplicate result")
	_reset()
	host._process(0.5)
	holder.current_hex = Vector2i(9, 9)
	host._process(0.1)
	_check(host.end_game_handled and not host.overtime_active and winners == [-1], "Losing occupation ends overtime immediately")
	_reset()
	host._process(0.5)
	enemy.current_hex = holder.current_hex
	host._process(0.1)
	_check(host.end_game_handled and winners == [-1], "Contesting a required objective ends overtime")
	_reset()
	other.required_unit_count = 1
	host._process(0.5)
	_check(host.end_game_handled and not host.overtime_active, "An unmet destruction requirement prevents occupation overtime")
	_reset()
	holder.current_hex = Vector2i(9, 9)
	host._process(0.5)
	_check(host.end_game_handled and not host.overtime_active, "An unoccupied objective cannot start overtime")
	_reset()
	var second_hex: Vector2i = Vector2i(1, 1)
	occupation.state.hexes.append(second_hex)
	occupation.state.required_times_reached_s[second_hex] = 0.0
	occupation.state.units_in_objectives[second_hex] = UnitsCollection.new()
	occupation.state.victory_conditions_met[second_hex] = false
	host._process(0.5)
	_check(host.end_game_handled and not host.overtime_active, "Every required objective marker must already be held at the deadline")
	_reset()
	occupation.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	other.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	host._process(0.5)
	_check(host.overtime_active, "A running minor-victory occupation can also extend the deadline")
	var countdown: PanelContainer = load("res://scenes/ui/hud/battle_hud.tscn").instantiate().get_node("Control/Countdown") as PanelContainer
	var hud: Node = countdown.get_parent().get_parent()
	countdown.get_parent().remove_child(countdown)
	hud.free()
	add_child(countdown)
	countdown.update_overtime_label(65.0)
	_check(countdown.get_node("HBoxContainer/Label2").text == "Overtime: " and countdown.timer_label.text == "+01:05", "The HUD identifies overtime and displays elapsed overtime")
	countdown.update_timer_label(60.0)
	_check(countdown.get_node("HBoxContainer/Label2").text == "Time left: " and countdown.timer_label.text == "01:00", "A new countdown restores the normal timer")
	Globals.victory_conditions.clear()
	holder.squad_fire.calc.free()
	enemy.squad_fire.calc.free()
	holder.free()
	enemy.free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Occupation overtime regression failures: ", failures)
	get_tree().quit(failures)


func _make_unit() -> UnitProbe:
	var unit: Unit = load("res://scenes/game/units/unit.tscn").instantiate()
	unit.set_script(UnitProbe)
	return unit as UnitProbe


func _reset() -> void:
	winners.clear()
	host.time_left_seconds = 0.5
	host.timer_running = true
	host.end_game_handled = false
	host.overtime_active = false
	host.overtime_elapsed_seconds = 0.0
	host.overtime_packages.clear()
	holder.current_hex = Vector2i.ZERO
	enemy.current_hex = Vector2i(10, 10)
	occupation = OccupyObjectiveCondition.new()
	occupation.team = holder.team
	occupation.required_time_s = 4.0
	occupation.test_at_scenario_end = true
	occupation.state = OccupyObjectiveState.new()
	occupation.state.hexes = [holder.current_hex]
	occupation.state.required_times_reached_s[holder.current_hex] = 2.0
	occupation.state.units_in_objectives[holder.current_hex] = UnitsCollection.new()
	occupation.state.victory_conditions_met[holder.current_hex] = false
	other = DestroyUnitsCondition.new()
	other.team = holder.team
	other.required_unit_count = 0
	other.test_at_scenario_end = true
	var collection: VictoryConditionCollection = VictoryConditionCollection.new()
	collection.victory_conditions = [occupation, other]
	Globals.victory_conditions.clear()
	Globals.victory_conditions[holder.team] = collection


func _on_winner(team: int, _level: VictoryCondition.OutcomeLevel, _timeout: bool) -> void:
	winners.append(team)


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
