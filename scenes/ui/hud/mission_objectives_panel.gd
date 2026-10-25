extends PanelContainer
class_name MissionObjectivesPanel

signal objective_focused(hex: Vector2i)

const REFRESH_INTERVAL_S: float = 0.2
const COMPLETE_COLOR: Color = Color(0.65, 0.85, 0.55)
const FAILED_COLOR: Color = Color(1.0, 0.55, 0.45)
const ACTIVE_COLOR: Color = Color(0.9, 0.87, 0.77)
const OBJECTIVE_NAMES: Array[String] = ["Exit", "A", "B", "C"]

@onready var section: FoldableContainer = $Objectives
@onready var scroll: ScrollContainer = $Objectives/Scroll
@onready var rows: VBoxContainer = $Objectives/Scroll/Rows

var conditions: Array[VictoryCondition] = []
var status_labels: Array[Label] = []
var requirement_labels: Array[Label] = []
var time_left_seconds: float = 0.0
var _refresh_elapsed_s: float = 0.0
var _height_limit: float = 200.0


func _ready() -> void:
	minimum_size_changed.connect(_fit_height)
	rows.minimum_size_changed.connect(_fit_height)
	section.folding_changed.connect(_on_folding_changed)
	set_process(false)
	hide()


func _fit_height() -> void:
	var overhead: float = maxf(0.0, get_combined_minimum_size().y - scroll.get_combined_minimum_size().y)
	scroll.custom_minimum_size.y = minf(rows.get_combined_minimum_size().y, maxf(0.0, _height_limit - overhead))
	size.y = get_combined_minimum_size().y


func fit_available_height(height: float) -> void:
	_height_limit = height
	_fit_height()


func _on_folding_changed(_folded: bool) -> void:
	_fit_height.call_deferred()


func setup(scenario_conditions: Array[VictoryCondition], player_team: Globals.Team, remaining_seconds: float) -> void:
	conditions.clear()
	status_labels.clear()
	requirement_labels.clear()
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for level: VictoryCondition.OutcomeLevel in [VictoryCondition.OutcomeLevel.MAJOR, VictoryCondition.OutcomeLevel.MINOR]:
		var heading: Label = null
		for condition: VictoryCondition in scenario_conditions:
			if condition.team != player_team or condition.outcome_level != level:
				continue
			if heading == null:
				heading = Label.new()
				heading.text = "Major victory · meet all"
				if level == VictoryCondition.OutcomeLevel.MINOR:
					heading.text = "Minor victory · meet all"
				heading.theme_type_variation = &"HudHeading"
				heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
				heading.tooltip_text = "Meet every requirement in this group. Major victory takes priority over minor victory."
				rows.add_child(heading)
			conditions.append(condition)
			var card: VBoxContainer = VBoxContainer.new()
			card.add_theme_constant_override("separation", 2)
			rows.add_child(card)
			var requirement: Label = Label.new()
			requirement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			requirement.mouse_filter = Control.MOUSE_FILTER_STOP
			requirement.gui_input.connect(_on_row_input.bind(condition))
			card.add_child(requirement)
			requirement_labels.append(requirement)
			var status: Label = Label.new()
			status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			status.mouse_filter = Control.MOUSE_FILTER_STOP
			status.gui_input.connect(_on_row_input.bind(condition))
			card.add_child(status)
			status_labels.append(status)
	time_left_seconds = remaining_seconds
	_refresh_elapsed_s = 0.0
	section.expand()
	visible = not conditions.is_empty()
	set_process(visible)
	refresh()


func _process(delta: float) -> void:
	_refresh_elapsed_s += delta
	if _refresh_elapsed_s >= REFRESH_INTERVAL_S:
		_refresh_elapsed_s = 0.0
		refresh()


func update_time(remaining_seconds: float) -> void:
	time_left_seconds = remaining_seconds
	if time_left_seconds <= 0.0:
		refresh()


func refresh() -> void:
	var units: Array[Unit] = Globals.get_units()
	for index: int in range(conditions.size()):
		var condition: VictoryCondition = conditions[index]
		var progress: VictoryConditionProgress = VictoryConditionProgress.read(condition)
		var label: Label = status_labels[index]
		var requirement: Label = requirement_labels[index]
		requirement.text = _requirement_text(condition)
		requirement.mouse_default_cursor_shape = Control.CURSOR_ARROW
		label.mouse_default_cursor_shape = Control.CURSOR_ARROW
		var text: String = ""
		var color: Color = ACTIVE_COLOR
		if not progress.valid:
			text = condition.get_description() + " · Unavailable"
			label.tooltip_text = progress.diagnostic
		else:
			label.tooltip_text = condition.get_description()
			if not progress.hexes.is_empty():
				label.tooltip_text += "\nClick to focus objective"
				label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			else:
				label.mouse_default_cursor_shape = Control.CURSOR_ARROW
			match progress.kind:
				VictoryConditionProgress.Kind.OCCUPY:
					text = _occupation_text(condition as OccupyObjectiveCondition, progress, units)
				VictoryConditionProgress.Kind.EXIT:
					var exit_condition: ExitUnitsCondition = condition as ExitUnitsCondition
					text = "Exit squads: %d/%d" % [progress.required_units - progress.remaining_units, progress.required_units]
					if exit_condition.objective_id != ExitUnitsCondition.ObjectiveId.EXIT:
						text += " at " + OBJECTIVE_NAMES[exit_condition.objective_id]
				VictoryConditionProgress.Kind.DESTROY:
					text = "Enemy squads destroyed: %d/%d" % [progress.required_units - progress.remaining_units, progress.required_units]
				VictoryConditionProgress.Kind.PREVENT_EXIT:
					var prevention: PreventEnemyExitCondition = condition as PreventEnemyExitCondition
					text = "Enemy exits: %d/%d allowed" % [prevention.state.units_exited.size(), prevention.max_allowed_enemy_exits]
			# Capture rows distinguish a running hold from a secured objective.
			if progress.kind != VictoryConditionProgress.Kind.OCCUPY:
				if progress.complete:
					if condition.test_at_scenario_end and time_left_seconds > 0.0:
						text += " · On track (at mission end)"
					else:
						text += " · Complete"
						color = COMPLETE_COLOR
				elif progress.kind == VictoryConditionProgress.Kind.PREVENT_EXIT:
					text += " · Failed"
					color = FAILED_COLOR
				elif time_left_seconds <= 0.0:
					text += " · Not met"
					color = FAILED_COLOR
				else:
					text += " · In progress"
		requirement.tooltip_text = label.tooltip_text
		requirement.mouse_default_cursor_shape = label.mouse_default_cursor_shape
		label.text = text
		label.add_theme_color_override("font_color", color)


func _requirement_text(condition: VictoryCondition) -> String:
	var text: String = condition.get_description()
	if condition is OccupyObjectiveCondition:
		var occupy: OccupyObjectiveCondition = condition as OccupyObjectiveCondition
		var squads: String = "good-order squad"
		if occupy.required_unit_count != 1:
			squads = "good-order squads"
		text = "Capture all %s hexes · %d %s/hex · %.0f s continuous" % [OBJECTIVE_NAMES[occupy.objective_id], occupy.required_unit_count, squads, occupy.required_time_s]
	if condition.test_at_scenario_end:
		text += " · Required at mission end"
	return text


func _occupation_text(condition: OccupyObjectiveCondition, progress: VictoryConditionProgress, units: Array[Unit]) -> String:
	var held_hexes: int = 0
	var contested_hexes: int = 0
	var enemy_hexes: int = 0
	var minimum_squads: int = progress.required_units
	var minimum_seconds: float = progress.required_seconds
	for hex: Vector2i in progress.hexes:
		var friendly_count: int = 0
		var enemy_count: int = 0
		for unit: Unit in units:
			if unit.current_hex != hex or not unit.is_good_order():
				continue
			if unit.team == condition.team:
				friendly_count += 1
			else:
				enemy_count += 1
		if not condition.state.victory_conditions_met.get(hex, false):
			minimum_squads = mini(minimum_squads, friendly_count)
		minimum_seconds = minf(minimum_seconds, progress.held_seconds.get(hex, 0.0))
		if friendly_count > 0 and enemy_count > 0 and condition.contested_by_enemy_presence:
			contested_hexes += 1
		elif condition.state.victory_conditions_met.get(hex, false):
			held_hexes += 1
		elif friendly_count > 0 and (not condition.contested_by_enemy_presence or enemy_count == 0):
			held_hexes += 1
		elif enemy_count > 0 or condition.state.controlling_teams.get(hex, -1) == Globals.get_enemy_team(condition.team):
			enemy_hexes += 1
	var status: String = "unoccupied"
	if held_hexes == progress.hexes.size():
		status = "player controlled"
		if minimum_squads < progress.required_units:
			status = "needs %d squads per hex" % progress.required_units
		elif not progress.complete:
			status = "securing · %.0f/%.0f s" % [floorf(minimum_seconds), progress.required_seconds]
	elif contested_hexes > 0:
		status = "contested"
	elif held_hexes > 0:
		status = "partially player controlled"
	elif enemy_hexes == progress.hexes.size():
		status = "enemy controlled"
	elif enemy_hexes > 0:
		status = "enemy present"
	var text: String = "Objective %s: %s" % [OBJECTIVE_NAMES[condition.objective_id], status]
	return text


func _on_row_input(event: InputEvent, condition: VictoryCondition) -> void:
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			var progress: VictoryConditionProgress = VictoryConditionProgress.read(condition)
			if not progress.hexes.is_empty():
				objective_focused.emit(progress.hexes[0])
				accept_event()
