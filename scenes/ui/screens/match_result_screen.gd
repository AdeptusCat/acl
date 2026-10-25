extends CanvasLayer

@export var victory_condition_result_scene: PackedScene

const VICTORY_COLOR: Color = Color(0.65, 0.85, 0.55)
const DEFEAT_COLOR: Color = Color(1.0, 0.55, 0.45)
const DRAW_COLOR: Color = Color(0.9, 0.87, 0.77)
const SQUAD_RESULT_ROW: Script = preload("res://scenes/ui/units/squad_result_row.gd")

@onready var control: Control = $Control
@onready var panel: PanelContainer = $Control/CenterContainer/PanelContainer
@onready var mission_label: Label = $Control/CenterContainer/PanelContainer/Content/MissionLabel
@onready var result_label: Label = $Control/CenterContainer/PanelContainer/Content/ResultLabel
@onready var result_detail: Label = $Control/CenterContainer/PanelContainer/Content/ResultDetail
@onready var player_heading: Label = $Control/CenterContainer/PanelContainer/Content/Summary/PlayerHeading
@onready var enemy_heading: Label = $Control/CenterContainer/PanelContainer/Content/Summary/EnemyHeading
@onready var player_casualties: Label = $Control/CenterContainer/PanelContainer/Content/Summary/PlayerCasualties
@onready var enemy_casualties: Label = $Control/CenterContainer/PanelContainer/Content/Summary/EnemyCasualties
@onready var player_exits: Label = $Control/CenterContainer/PanelContainer/Content/Summary/PlayerExits
@onready var enemy_exits: Label = $Control/CenterContainer/PanelContainer/Content/Summary/EnemyExits
@onready var player_exited_soldiers: Label = $Control/CenterContainer/PanelContainer/Content/Summary/PlayerExitedSoldiers
@onready var enemy_exited_soldiers: Label = $Control/CenterContainer/PanelContainer/Content/Summary/EnemyExitedSoldiers
@onready var body: TabContainer = $Control/CenterContainer/PanelContainer/Content/Body
@onready var squads_scroll: ScrollContainer = $Control/CenterContainer/PanelContainer/Content/Body/Squads
@onready var player_squads_heading: Label = $Control/CenterContainer/PanelContainer/Content/Body/Squads/Forces/Player/Heading
@onready var enemy_squads_heading: Label = $Control/CenterContainer/PanelContainer/Content/Body/Squads/Forces/Enemy/Heading
@onready var player_squads: VBoxContainer = $Control/CenterContainer/PanelContainer/Content/Body/Squads/Forces/Player/Rows
@onready var enemy_squads: VBoxContainer = $Control/CenterContainer/PanelContainer/Content/Body/Squads/Forces/Enemy/Rows
@onready var no_player_squads: Label = $Control/CenterContainer/PanelContainer/Content/Body/Squads/Forces/Player/Empty
@onready var no_enemy_squads: Label = $Control/CenterContainer/PanelContainer/Content/Body/Squads/Forces/Enemy/Empty
@onready var objectives_scroll: ScrollContainer = $Control/CenterContainer/PanelContainer/Content/Body/Objectives
@onready var objectives: VBoxContainer = $Control/CenterContainer/PanelContainer/Content/Body/Objectives/Rows
@onready var major_objectives_label: Label = $Control/CenterContainer/PanelContainer/Content/Body/Objectives/Rows/MajorObjectivesLabel
@onready var major_victory_conditions_v_box_container: VBoxContainer = $Control/CenterContainer/PanelContainer/Content/Body/Objectives/Rows/MajorVictoryConditionsVBoxContainer
@onready var minor_objectives_label: Label = $Control/CenterContainer/PanelContainer/Content/Body/Objectives/Rows/MinorObjectivesLabel
@onready var minor_victory_conditions_v_box_container: VBoxContainer = $Control/CenterContainer/PanelContainer/Content/Body/Objectives/Rows/MinorVictoryConditionsVBoxContainer

var _fit_queued: bool = false

signal try_again
signal keep_playing


func _ready() -> void:
	control.resized.connect(_queue_fit)
	panel.minimum_size_changed.connect(_queue_fit)
	_queue_fit()


func _on_show_winner(winner_team: int, outcome_level: VictoryCondition.OutcomeLevel = VictoryCondition.OutcomeLevel.MAJOR, timeout: bool = false) -> void:
	_set_outcome(winner_team, outcome_level, timeout)
	_update_summary()
	_update_squads()
	mission_label.text = Globals.scenario_chosen.scenario_name
	for container: VBoxContainer in [major_victory_conditions_v_box_container, minor_victory_conditions_v_box_container]:
		for child: Node in container.get_children():
			container.remove_child(child)
			child.queue_free()
	major_objectives_label.hide()
	minor_objectives_label.hide()
	for condition: VictoryCondition in Globals.scenario_chosen.victory_conditions:
		if condition.team != Globals.team_player:
			continue
		var row: VictoryConditionResult = victory_condition_result_scene.instantiate()
		if condition.outcome_level == VictoryCondition.OutcomeLevel.MAJOR:
			major_victory_conditions_v_box_container.add_child(row)
			major_objectives_label.show()
		else:
			minor_victory_conditions_v_box_container.add_child(row)
			minor_objectives_label.show()
		var progress: VictoryConditionProgress = VictoryConditionProgress.read(condition)
		row.set_victory_condition(progress.complete, condition.get_description() + "\n" + _progress_text(progress), progress.valid)
		row.tooltip_text = condition.get_details()
		if not progress.valid:
			row.tooltip_text = progress.diagnostic
	objectives_scroll.scroll_vertical = 0
	squads_scroll.scroll_vertical = 0
	body.current_tab = 0
	show()
	_queue_fit()


func _set_outcome(winner_team: int, outcome_level: VictoryCondition.OutcomeLevel, timeout: bool) -> void:
	var level: String = "major"
	if outcome_level == VictoryCondition.OutcomeLevel.MINOR:
		level = "minor"
	if winner_team == Globals.team_player:
		result_label.text = level.capitalize() + " Victory"
		result_label.add_theme_color_override("font_color", VICTORY_COLOR)
		result_detail.text = "You achieved a %s victory as %s." % [level, Globals.TEAM_NAMES[Globals.team_player]]
	elif winner_team != -1:
		result_label.text = "Defeat"
		result_label.add_theme_color_override("font_color", DEFEAT_COLOR)
		result_detail.text = "%s achieved a %s victory." % [Globals.TEAM_NAMES[winner_team], level]
	elif timeout:
		result_label.text = "Defeat by Timeout"
		result_label.add_theme_color_override("font_color", DEFEAT_COLOR)
		result_detail.text = "Time expired before either side achieved its victory conditions."
	else:
		result_label.text = "Draw"
		result_label.add_theme_color_override("font_color", DRAW_COLOR)
		result_detail.text = "Neither side earned a decisive result."


func _update_summary() -> void:
	var casualties: Dictionary[int, int] = {Globals.Team.AXIS: 0, Globals.Team.ALLIES: 0}
	var exits: Dictionary[int, int] = {Globals.Team.AXIS: 0, Globals.Team.ALLIES: 0}
	var soldiers: Dictionary[int, int] = {Globals.Team.AXIS: 0, Globals.Team.ALLIES: 0}
	for record: CasualtyRecord in Globals.battle_casualties:
		if record != null and casualties.has(record.team):
			casualties[record.team] += 1
	for record: UnitExitRecord in Globals.battle_exits:
		if record != null and exits.has(record.team):
			exits[record.team] += 1
			soldiers[record.team] += record.members_alive
	var player: Globals.Team = Globals.team_player
	var enemy: Globals.Team = Globals.get_enemy_team(player)
	player_heading.text = "Your force · " + Globals.TEAM_NAMES[player]
	enemy_heading.text = "Enemy · " + Globals.TEAM_NAMES[enemy]
	player_casualties.text = str(casualties[player])
	enemy_casualties.text = str(casualties[enemy])
	player_exits.text = str(exits[player])
	enemy_exits.text = str(exits[enemy])
	player_exited_soldiers.text = str(soldiers[player])
	enemy_exited_soldiers.text = str(soldiers[enemy])


func _update_squads() -> void:
	for container: VBoxContainer in [player_squads, enemy_squads]:
		for child: Node in container.get_children():
			container.remove_child(child)
			child.queue_free()
	player_squads_heading.text = player_heading.text
	enemy_squads_heading.text = enemy_heading.text
	var units: Array[Unit] = []
	var seen: Dictionary[int, bool] = {}
	# Dead and exited squads remain on the battlefield, outside the active group.
	for group: StringName in [&"units", &"dead_units", &"exited_units"]:
		for candidate: Node in get_tree().get_nodes_in_group(group):
			var unit: Unit = candidate as Unit
			if not is_instance_valid(unit) or unit.is_queued_for_deletion():
				continue
			var id: int = unit.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			units.append(unit)
	units.sort_custom(_squad_before)
	for unit: Unit in units:
		var container: VBoxContainer = enemy_squads
		if unit.team == Globals.team_player:
			container = player_squads
		var row: HBoxContainer = SQUAD_RESULT_ROW.new()
		row.setup(unit)
		container.add_child(row)
	no_player_squads.visible = player_squads.get_child_count() == 0
	no_enemy_squads.visible = enemy_squads.get_child_count() == 0


func _squad_before(first: Unit, second: Unit) -> bool:
	if first.company != second.company:
		return first.company < second.company
	if first.platoon != second.platoon:
		return first.platoon < second.platoon
	if first.squad != second.squad:
		return first.squad < second.squad
	if first.squad_type != second.squad_type:
		return first.squad_type < second.squad_type
	return first.get_instance_id() < second.get_instance_id()


func _progress_text(progress: VictoryConditionProgress) -> String:
	if not progress.valid:
		return "Progress unavailable."
	match progress.kind:
		VictoryConditionProgress.Kind.OCCUPY:
			var occupation: OccupyObjectiveCondition = progress.condition as OccupyObjectiveCondition
			var held_seconds: float = progress.required_seconds
			var secured: int = 0
			for hex: Vector2i in progress.hexes:
				held_seconds = minf(held_seconds, progress.held_seconds.get(hex, 0.0))
				if occupation.state.victory_conditions_met.get(hex, false):
					secured += 1
			return "Held: %s/%s s. Secured hexes: %d/%d." % [_seconds_text(held_seconds), _seconds_text(progress.required_seconds), secured, progress.hexes.size()]
		VictoryConditionProgress.Kind.EXIT:
			var exit: ExitUnitsCondition = progress.condition as ExitUnitsCondition
			return "Squads exited: %d/%d." % [exit.state.units_exited.size(), progress.required_units]
		VictoryConditionProgress.Kind.DESTROY:
			return "Enemy units defeated: %d/%d." % [Globals.units_destroyed.units_collection[progress.team].units.size(), progress.required_units]
		VictoryConditionProgress.Kind.PREVENT_EXIT:
			var prevention: PreventEnemyExitCondition = progress.condition as PreventEnemyExitCondition
			return "Enemy exits: %d/%d allowed." % [prevention.state.units_exited.size(), prevention.max_allowed_enemy_exits]
	return "Progress unavailable."


func _seconds_text(seconds: float) -> String:
	if is_equal_approx(seconds, roundf(seconds)):
		return "%.0f" % seconds
	return String.num(seconds, 2)


func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_fit_panel.call_deferred()


func _fit_panel() -> void:
	_fit_queued = false
	panel.custom_minimum_size.x = minf(1020.0, maxf(0.0, control.size.x - 48.0))
	var overhead: float = maxf(0.0, panel.get_combined_minimum_size().y - body.get_combined_minimum_size().y)
	body.custom_minimum_size.y = minf(420.0, maxf(0.0, control.size.y - 48.0 - overhead))


func _on_try_again_pressed() -> void:
	try_again.emit()


func _on_keep_playing_pressed() -> void:
	hide()
	keep_playing.emit()
