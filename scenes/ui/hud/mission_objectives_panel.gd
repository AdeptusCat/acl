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

var _reinforcement_team: Globals.Team = Globals.Team.AXIS
var reinforcement_status: Label
var conditions: Array[VictoryCondition] = []
var group_headings: Dictionary[VictoryCondition.OutcomeLevel, Label] = {}
var capture_buttons: Dictionary[int, ObjectiveCaptureButton] = {}
var status_labels: Array[Label] = []
var requirement_labels: Array[Label] = []
var time_left_seconds: float = 0.0
var _refresh_elapsed_s: float = 0.0
var _height_limit: float = 200.0
var _last_focused_hexes: Dictionary[VictoryCondition, Vector2i] = {}
var _metric_rows: Dictionary[int, PanelContainer] = {}


func _ready() -> void:
	rows.add_theme_constant_override("separation", 12)
	var frame: StyleBoxFlat = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	frame.set_border_width_all(1)
	frame.border_color = Color(0.30, 0.33, 0.28)
	add_theme_stylebox_override("panel", frame)
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
	_reinforcement_team = player_team
	reinforcement_status = null
	conditions.clear()
	_last_focused_hexes.clear()
	_metric_rows.clear()
	group_headings.clear()
	capture_buttons.clear()
	status_labels.clear()
	requirement_labels.clear()
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for level: VictoryCondition.OutcomeLevel in [VictoryCondition.OutcomeLevel.MAJOR, VictoryCondition.OutcomeLevel.MINOR]:
		var group: VBoxContainer = null
		for condition: VictoryCondition in scenario_conditions:
			if condition.team != player_team or condition.outcome_level != level:
				continue
			if group == null:
				group = _create_group(level)
			conditions.append(condition)
			var card: VBoxContainer = VBoxContainer.new()
			card.add_theme_constant_override("separation", 2)
			group.add_child(card)
			if condition is OccupyObjectiveCondition:
				var capture_button: ObjectiveCaptureButton = ObjectiveCaptureButton.new()
				card.add_child(capture_button)
				capture_button.setup(condition as OccupyObjectiveCondition)
				capture_button.focus_requested.connect(_focus_next_hex.bind(condition))
				capture_buttons[conditions.size() - 1] = capture_button
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
			status.add_theme_font_size_override("font_size", 14)
			if not condition is OccupyObjectiveCondition:
				var metric: PanelContainer = PanelContainer.new()
				metric.mouse_filter = Control.MOUSE_FILTER_STOP
				metric.gui_input.connect(_on_row_input.bind(condition))
				_metric_rows[conditions.size() - 1] = metric
				var metric_style: StyleBoxFlat = StyleBoxFlat.new()
				metric_style.bg_color = Color(0.035, 0.045, 0.04, 0.65)
				metric_style.content_margin_left = 10.0
				metric_style.content_margin_right = 10.0
				metric_style.content_margin_top = 7.0
				metric_style.content_margin_bottom = 7.0
				metric.add_theme_stylebox_override("panel", metric_style)
				card.add_child(metric)
				metric.add_child(status)
			else:
				card.add_child(status)
			status_labels.append(status)
	if not _reinforcement_briefing().is_empty():
		reinforcement_status = Label.new()
		reinforcement_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(reinforcement_status)
	time_left_seconds = remaining_seconds
	_refresh_elapsed_s = 0.0
	section.expand()
	visible = not conditions.is_empty() or not _reinforcement_briefing().is_empty()
	set_process(visible)
	refresh()


func _create_group(level: VictoryCondition.OutcomeLevel) -> VBoxContainer:
	var accent: Color = Color(0.82, 0.72, 0.48)
	var title: String = "Major victory"
	if level == VictoryCondition.OutcomeLevel.MINOR:
		accent = Color(0.57, 0.69, 0.72)
		title = "Minor victory"
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.12, 0.75)
	style.border_width_left = 2
	style.border_color = accent.darkened(0.3)
	style.content_margin_left = 10.0
	style.content_margin_right = 8.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	panel.add_theme_stylebox_override("panel", style)
	rows.add_child(panel)
	var group: VBoxContainer = VBoxContainer.new()
	group.add_theme_constant_override("separation", 8)
	panel.add_child(group)
	var header: HBoxContainer = HBoxContainer.new()
	group.add_child(header)
	var heading: Label = Label.new()
	heading.text = title
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", accent)
	header.add_child(heading)
	group_headings[level] = heading
	var hint: Label = Label.new()
	hint.text = "ALL REQUIRED"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.53, 0.57, 0.51))
	header.add_child(hint)
	return group


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
	if reinforcement_status != null:
		reinforcement_status.text = _reinforcement_briefing()
		reinforcement_status.visible = not reinforcement_status.text.is_empty()
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
			label.tooltip_text = condition.get_details()
			if not progress.hexes.is_empty():
				label.tooltip_text += "\n" + _focus_hint(progress.hexes.size())
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
						text += " at Objective " + OBJECTIVE_NAMES[exit_condition.objective_id]
				VictoryConditionProgress.Kind.DESTROY:
					text = "Enemy squads destroyed: %d/%d" % [progress.required_units - progress.remaining_units, progress.required_units]
				VictoryConditionProgress.Kind.PREVENT_EXIT:
					var prevention: PreventEnemyExitCondition = condition as PreventEnemyExitCondition
					text = "Enemy exits: %d/%d allowed" % [prevention.state.units_exited.size(), prevention.max_allowed_enemy_exits]
					if prevention.objective_id != PreventEnemyExitCondition.ObjectiveId.EXIT:
						text += " at Objective " + OBJECTIVE_NAMES[prevention.objective_id]
			if progress.kind != VictoryConditionProgress.Kind.OCCUPY:
				if progress.complete:
					if condition.test_at_scenario_end and time_left_seconds > 0.0:
						label.tooltip_text += "\nOn track at mission end."
					else:
						color = COMPLETE_COLOR
						label.tooltip_text += "\nComplete."
				elif progress.kind == VictoryConditionProgress.Kind.PREVENT_EXIT:
					text += " · Failed"
					color = FAILED_COLOR
				elif time_left_seconds <= 0.0:
					color = FAILED_COLOR
					label.tooltip_text += "\nNot met."
				else:
					label.tooltip_text += "\nIn progress."
		requirement.tooltip_text = label.tooltip_text
		requirement.mouse_default_cursor_shape = label.mouse_default_cursor_shape
		label.text = text
		if progress.kind == VictoryConditionProgress.Kind.DESTROY and progress.complete:
			color = COMPLETE_COLOR
		label.add_theme_color_override("font_color", color)
		requirement.hide()
		label.visible = progress.kind != VictoryConditionProgress.Kind.OCCUPY
		if _metric_rows.has(index):
			_metric_rows[index].mouse_default_cursor_shape = label.mouse_default_cursor_shape
			_metric_rows[index].tooltip_text = label.tooltip_text
		if capture_buttons.has(index):
			var capture_button: ObjectiveCaptureButton = capture_buttons[index]
			capture_button.refresh()
			capture_button.tooltip_text = text + "\n" + requirement.text + "\n" + _focus_hint(progress.hexes.size())


func _requirement_text(condition: VictoryCondition) -> String:
	var text: String = condition.get_details()
	if condition is OccupyObjectiveCondition:
		var occupy: OccupyObjectiveCondition = condition as OccupyObjectiveCondition
		var squads: String = "good-order squad"
		if occupy.required_unit_count != 1:
			squads = "good-order squads"
		text = "Capture all %s hexes · %d %s/hex · %.0f s continuous" % [OBJECTIVE_NAMES[occupy.objective_id], occupy.required_unit_count, squads, occupy.required_time_s]
	if condition.test_at_scenario_end and condition is OccupyObjectiveCondition:
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


func _focus_hint(hex_count: int) -> String:
	if hex_count > 1:
		return "Click to cycle through %d objective hexes" % hex_count
	return "Click to focus objective"


func _focus_next_hex(condition: VictoryCondition) -> bool:
	var progress: VictoryConditionProgress = VictoryConditionProgress.read(condition)
	var hexes: Array[Vector2i] = []
	for hex: Vector2i in progress.hexes:
		if not hexes.has(hex):
			hexes.append(hex)
	if hexes.is_empty():
		_last_focused_hexes.erase(condition)
		return false
	var next_index: int = 0
	if _last_focused_hexes.has(condition):
		next_index = (hexes.find(_last_focused_hexes[condition]) + 1) % hexes.size()
	var hex: Vector2i = hexes[next_index]
	_last_focused_hexes[condition] = hex
	objective_focused.emit(hex)
	return true


func _on_row_input(event: InputEvent, condition: VictoryCondition) -> void:
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			if _focus_next_hex(condition):
				accept_event()


func _reinforcement_briefing() -> String:
	var runtime: MatchReinforcementController = get_tree().get_first_node_in_group("reinforcement_runtime") as MatchReinforcementController
	if runtime == null:
		return ""
	return runtime.player_briefing(_reinforcement_team)
