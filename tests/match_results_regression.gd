extends Node

var checks: int = 0
var failures: int = 0
var returns_to_menu: int = 0
var screen: CanvasLayer
var scenario: Scenario
var occupation: OccupyObjectiveCondition
var exiting: ExitUnitsCondition
var prevention: PreventEnemyExitCondition
var units: Array[Unit] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	scenario = Scenario.new()
	scenario.scenario_name = "Battle for Alderbrook"
	Globals.scenario_chosen = scenario
	Globals.team_player = Globals.Team.ALLIES
	Globals.units_destroyed = UnitsCollection.new()
	_build_conditions()
	_build_records()
	screen = load("res://scenes/ui/screens/match_result_screen.tscn").instantiate()
	add_child(screen)
	screen.try_again.connect(_on_return_to_menu)
	screen._on_show_winner(Globals.Team.ALLIES, VictoryCondition.OutcomeLevel.MINOR)
	await _settle()
	_check(screen.result_label.text == "Minor Victory", "The result describes the player's victory level")
	_check(screen.mission_label.text == scenario.scenario_name, "The result identifies the completed mission")
	_check(screen.player_casualties.text == "2" and screen.enemy_casualties.text == "3", "Casualties count individual soldiers for each side")
	_check(screen.player_exits.text == "3" and screen.enemy_exits.text == "1", "Exits count squads rather than individual soldiers")
	_check(screen.player_exited_soldiers.text == "22" and screen.enemy_exited_soldiers.text == "8", "Exited soldier totals use the recorded surviving strength")
	var rows: VBoxContainer = screen.major_victory_conditions_v_box_container
	_check(rows.get_child_count() == 4 and screen.minor_victory_conditions_v_box_container.get_child_count() == 1, "Only player objectives appear, grouped by victory level")
	_check(_text(0).contains("Held: 44/45 s.") and _text(0).contains("Secured hexes: 1/2."), "Occupation reports the least-complete hold and every secured hex")
	_check(not (rows.get_child(0) as VictoryConditionResult).check_box.button_pressed, "An unfinished multi-hex occupation remains unmet")
	_check(_text(1).contains("Enemy units defeated: 3/2."), "Defeat objectives retain actual counts beyond their quota")
	_check(_text(2).contains("Squads exited: 3/2."), "Exit objectives retain actual counts beyond their quota")
	_check(_text(3).contains("Enemy exits: 1/0 allowed."), "Zero-exit prevention shows the breached limit without division by zero")
	_check(not (rows.get_child(3) as VictoryConditionResult).check_box.button_pressed, "Exceeding the enemy exit allowance is shown as unmet")
	_check(occupation.state.required_times_reached_s[Vector2i(1, 1)] == 44.0 and exiting.state.units_exited.size() == 3,
		"Reading results does not advance captures or register additional exits")
	_check_inside()
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		_check(image.save_png("/tmp/acl-battle-results.png") == OK, "The rendered result screen is captured")
	_test_outcomes()
	_test_refresh()
	# Additional rows must scroll while the summary and actions stay on screen.
	for index: int in range(20):
		scenario.victory_conditions.append(occupation)
	screen._on_show_winner(Globals.Team.ALLIES)
	screen.body.current_tab = 1
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		await _settle()
		_check_inside()
		var bar: VScrollBar = screen.objectives_scroll.get_v_scroll_bar()
		_check(bar.max_value > bar.page, "Long objective lists scroll within the result panel")
	screen.get_node("Control/CenterContainer/PanelContainer/Content/Actions/TryAgain").pressed.emit()
	_check(returns_to_menu == 1, "Main Menu retains its existing signal connection")
	screen.get_node("Control/CenterContainer/PanelContainer/Content/Actions/KeepPlaying").pressed.emit()
	_check(not screen.visible, "Keep Playing retains its existing dismiss action")
	screen.free()
	Globals.scenario_chosen = null
	Globals.battle_casualties.clear()
	Globals.battle_exits.clear()
	Globals.units_destroyed = UnitsCollection.new()
	scenario.free()
	for unit: Unit in units:
		unit.free()
	print("Match result checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _build_conditions() -> void:
	occupation = OccupyObjectiveCondition.new()
	occupation.team = Globals.Team.ALLIES
	occupation.required_time_s = 45.0
	occupation.state = OccupyObjectiveState.new()
	occupation.state.hexes.assign([Vector2i(1, 1), Vector2i(2, 2)])
	occupation.state.required_times_reached_s = {Vector2i(1, 1): 44.0, Vector2i(2, 2): 45.0}
	occupation.state.victory_conditions_met = {Vector2i(1, 1): false, Vector2i(2, 2): true}
	var destroyed: DestroyUnitsCondition = DestroyUnitsCondition.new()
	destroyed.team = Globals.Team.ALLIES
	destroyed.required_unit_count = 2
	exiting = ExitUnitsCondition.new()
	exiting.team = Globals.Team.ALLIES
	exiting.required_unit_count = 2
	exiting.state = ExitUnitsState.new()
	exiting.state.exit_hexes.assign([Vector2i(3, 3)])
	for index: int in range(3):
		var unit: Unit = Unit.new()
		units.append(unit)
		exiting.state.units_exited.append(unit)
		Globals.units_destroyed.units_collection[Globals.Team.ALLIES].units.append(unit)
	prevention = PreventEnemyExitCondition.new()
	prevention.team = Globals.Team.ALLIES
	prevention.state = ExitUnitsState.new()
	prevention.state.exit_hexes.assign([Vector2i(4, 4)])
	prevention.state.units_exited.append(units[0])
	var minor: DestroyUnitsCondition = DestroyUnitsCondition.new()
	minor.team = Globals.Team.ALLIES
	minor.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	minor.required_unit_count = 1
	var enemy: DestroyUnitsCondition = DestroyUnitsCondition.new()
	enemy.team = Globals.Team.AXIS
	enemy.required_unit_count = 99
	scenario.victory_conditions.assign([occupation, destroyed, exiting, prevention, minor, enemy])


func _build_records() -> void:
	Globals.battle_casualties.clear()
	Globals.battle_exits.clear()
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.AXIS, Globals.Team.AXIS, Globals.Team.ALLIES, Globals.Team.ALLIES]:
		var casualty: CasualtyRecord = CasualtyRecord.new()
		casualty.team = team
		Globals.battle_casualties.append(casualty)
	for strength: int in [7, 9, 6]:
		var record: UnitExitRecord = UnitExitRecord.new()
		record.team = Globals.Team.ALLIES
		record.members_alive = strength
		Globals.battle_exits.append(record)
	var enemy_exit: UnitExitRecord = UnitExitRecord.new()
	enemy_exit.team = Globals.Team.AXIS
	enemy_exit.members_alive = 8
	Globals.battle_exits.append(enemy_exit)


func _test_outcomes() -> void:
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		Globals.team_player = team
		screen._on_show_winner(team, VictoryCondition.OutcomeLevel.MAJOR)
		_check(screen.result_label.text == "Major Victory", "Both factions see a player-relative major victory")
		screen._on_show_winner(team, VictoryCondition.OutcomeLevel.MINOR)
		_check(screen.result_label.text == "Minor Victory", "Both factions see a player-relative minor victory")
		for level: VictoryCondition.OutcomeLevel in [VictoryCondition.OutcomeLevel.MAJOR, VictoryCondition.OutcomeLevel.MINOR]:
			screen._on_show_winner(Globals.get_enemy_team(team), level)
			_check(screen.result_label.text == "Defeat" and screen.result_detail.text.begins_with(Globals.TEAM_NAMES[Globals.get_enemy_team(team)]), "An enemy victory is clearly a player defeat")
		screen._on_show_winner(-1, VictoryCondition.OutcomeLevel.MAJOR, true)
		_check(screen.result_label.text == "Defeat by Timeout", "Unmet conditions at the deadline remain a timeout defeat")
		screen._on_show_winner(-1, VictoryCondition.OutcomeLevel.MINOR, false)
		_check(screen.result_label.text == "Draw", "A draw is not mislabeled as a player defeat")
	Globals.team_player = Globals.Team.AXIS
	screen._on_show_winner(Globals.Team.AXIS)
	_check(screen.player_casualties.text == "3" and screen.enemy_casualties.text == "2" and screen.player_exited_soldiers.text == "8", "Summary columns follow the player's faction")
	Globals.team_player = Globals.Team.ALLIES


func _test_refresh() -> void:
	Globals.battle_casualties.clear()
	Globals.battle_exits.clear()
	screen._on_show_winner(Globals.Team.ALLIES)
	_check(screen.player_casualties.text == "0" and screen.enemy_casualties.text == "0" and screen.player_exits.text == "0" and screen.enemy_exits.text == "0",
		"Showing another result clears previous casualty and exit totals")
	_check(screen.player_exited_soldiers.text == "0" and screen.enemy_exited_soldiers.text == "0", "Empty exit records clear previous soldier totals")
	_check(screen.major_victory_conditions_v_box_container.get_child_count() == 4, "Repeated results replace rather than duplicate objective rows")
	exiting.state = null
	screen._on_show_winner(Globals.Team.ALLIES)
	_check(_text(2).contains("Progress unavailable.") and not (screen.major_victory_conditions_v_box_container.get_child(2) as VictoryConditionResult).check_box.button_pressed,
		"Missing objective state is reported without inventing numerical progress")


func _text(index: int) -> String:
	return (screen.major_victory_conditions_v_box_container.get_child(index) as VictoryConditionResult).label.text


func _check_inside() -> void:
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(get_tree().root.size))
	_check(bounds.encloses(screen.panel.get_global_rect()), "The result panel fits the viewport")
	var actions: Control = screen.get_node("Control/CenterContainer/PanelContainer/Content/Actions")
	_check(bounds.encloses(actions.get_global_rect()), "Result actions remain visible below the scrollable objectives")


func _settle() -> void:
	for frame: int in range(10):
		await get_tree().process_frame


func _on_return_to_menu() -> void:
	returns_to_menu += 1


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
