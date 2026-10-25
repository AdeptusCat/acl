extends CanvasLayer

signal game_started(map: Map, scenario: Scenario, team: int, game_mode: Globals.GameMode)
signal hover_start_button(team: int)
signal time_changed(time_minutes: float)

const FORCE_ROW: Script = preload("res://scenes/ui/units/mission_force_row.gd")

@onready var time_spinbox: SpinBox = $Control/Center/Panel/Content/Header/Time/Minutes
@onready var maps_v_box_container: VBoxContainer = $Control/Center/Panel/Content/Body/ScenarioScroll/Maps
@onready var scenario_description: RichTextLabel = $Control/Center/Panel/Content/Body/BriefingScroll/Briefing/Description
@onready var scenario_title: Label = $Control/Center/Panel/Content/Body/BriefingScroll/Briefing/Title
@onready var lock_label: Label = $Control/Center/Panel/Content/Body/BriefingScroll/Briefing/Availability
@onready var team: TextureRect = $Control/Center/Panel/Content/Body/BriefingScroll/Briefing/Faction/Flag
@onready var player_label: Label = $Control/Center/Panel/Content/Body/BriefingScroll/Briefing/Faction/Player
@onready var major_victory_conditions_v_box_container: VBoxContainer = $Control/Center/Panel/Content/Body/BriefingScroll/Briefing/MajorObjectives
@onready var minor_victory_conditions_v_box_container: VBoxContainer = $Control/Center/Panel/Content/Body/BriefingScroll/Briefing/MinorObjectives
@onready var minor_objectives_label: Label = $Control/Center/Panel/Content/Body/BriefingScroll/Briefing/MinorHeading
@onready var start_button: Button = $Control/Center/Panel/Content/Footer/StartMission
@onready var scenario_scroll: ScrollContainer = $Control/Center/Panel/Content/Body/ScenarioScroll
@onready var briefing_scroll: ScrollContainer = $Control/Center/Panel/Content/Body/BriefingScroll
@onready var panel: PanelContainer = $Control/Center/Panel
@onready var force_briefing: VBoxContainer = $Control/Center/Panel/Content/Body/BriefingScroll/Briefing/Forces
@onready var player_roster: VBoxContainer = $Control/Center/Panel/Content/Body/BriefingScroll/Briefing/Forces/PlayerRoster
@onready var enemy_assessment: Label = $Control/Center/Panel/Content/Body/BriefingScroll/Briefing/Forces/EnemyAssessment
@onready var settings: Control = $Control/Settings

var team_texture: Dictionary[Globals.Team, Texture2D] = {
	Globals.Team.AXIS: preload("res://assets/ui/axis_flag.png"),
	Globals.Team.ALLIES: preload("res://assets/ui/us_flag.png"),
}
var selected_map: Map
var selected_scenario: Scenario
var scenario_buttons: Dictionary[Scenario, Button] = {}
var player_roster_rows: Dictionary[Unit, HBoxContainer] = {}
var time: float = 3.0
var _starting: bool = false
var _fit_queued: bool = false


func _ready() -> void:
	start_button.pressed.connect(_on_start_mission_pressed)
	time_spinbox.value_changed.connect(_on_spin_box_value_changed)
	$Control.resized.connect(_queue_fit)
	panel.minimum_size_changed.connect(_queue_fit)
	if SessionSettings.mission_time > 0.0:
		time_spinbox.value = SessionSettings.mission_time
	time = time_spinbox.value
	time_changed.emit.call_deferred(time)
	_queue_fit()


func setup_map_options(maps: Array[Map]) -> void:
	for child: Node in maps_v_box_container.get_children():
		maps_v_box_container.remove_child(child)
		child.queue_free()
	scenario_buttons.clear()
	var group: ButtonGroup = ButtonGroup.new()
	group.allow_unpress = false
	var campaign_heading: String = ""
	for map: Map in maps:
		var heading_text: String = map.map_name
		if not map.campaign_name.is_empty():
			heading_text = map.campaign_name
		if map.campaign_name.is_empty() or campaign_heading != map.campaign_name:
			var heading: Label = Label.new()
			heading.theme_type_variation = &"HudHeading"
			heading.text = heading_text
			maps_v_box_container.add_child(heading)
		campaign_heading = map.campaign_name
		for scenario: Scenario in map.get_scenarios():
			var button: Button = Button.new()
			button.toggle_mode = true
			button.button_group = group
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.clip_text = true
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.text = scenario.scenario_name
			var reason: String = get_lock_reason(scenario)
			button.tooltip_text = scenario.scenario_name
			if not reason.is_empty():
				button.text = "Locked · " + scenario.scenario_name
				button.tooltip_text += "\n" + reason
				button.add_theme_color_override("font_color", Color(0.78, 0.79, 0.7))
			maps_v_box_container.add_child(button)
			scenario_buttons[scenario] = button
			button.pressed.connect(_on_scenario_button_pressed.bind(map, scenario))
	if is_instance_valid(selected_scenario) and scenario_buttons.has(selected_scenario):
		_on_scenario_button_pressed(selected_map, selected_scenario)
	else:
		selected_map = null
		selected_scenario = null
		start_button.disabled = true
		scenario_title.text = "Mission briefing"
		scenario_description.text = "Select a scenario to read its briefing, then press Start mission."
		lock_label.text = ""
		team.hide()
		player_label.text = ""
		_clear_objectives()
		_clear_forces()
	_queue_fit()


func get_lock_reason(scenario: Scenario) -> String:
	if not OS.is_debug_build() and not scenario.released:
		return "This mission is not available in this build."
	if scenario.previous_scenario == null:
		return ""
	var previous: Scenario = scenario.previous_scenario
	var match_id: String = previous.get_save_id()
	var save_path: String = "user://matches/%s.tres" % match_id
	if ResourceLoader.exists(save_path):
		# Inspect progression without importing a previous battle's casualty records.
		var saved: MatchSaveData = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as MatchSaveData
		if saved != null:
			if previous.scenario_id.is_empty():
				for completed_team: Globals.Team in Globals.Team.values():
					if saved.has_player_victory(completed_team):
						return ""
			elif saved.scenario_id == previous.scenario_id and saved.has_player_victory(previous.player_team):
				return ""
	return "Win \"%s\" to unlock this mission." % previous.scenario_name


func _on_scenario_button_pressed(map: Map, scenario: Scenario) -> void:
	if _starting:
		return
	selected_map = map
	selected_scenario = scenario
	scenario_buttons[scenario].set_pressed_no_signal(true)
	scenario_title.text = scenario.scenario_name
	scenario_description.text = scenario.scenario_description
	if scenario.use_authored_duration:
		time_spinbox.value = scenario.duration_s / 60.0
	lock_label.text = get_lock_reason(scenario)
	lock_label.visible = not lock_label.text.is_empty()
	start_button.disabled = not lock_label.text.is_empty()
	team.texture = team_texture[scenario.player_team]
	team.show()
	player_label.text = "Player: Axis"
	if scenario.player_team == Globals.Team.ALLIES:
		player_label.text = "Player: Allies"
	_update_force_briefing(scenario)
	_clear_objectives()
	for condition: VictoryCondition in scenario.victory_conditions:
		if condition.team != scenario.player_team:
			continue
		var label: Label = Label.new()
		label.text = condition.get_description()
		label.tooltip_text = condition.get_details()
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if condition.outcome_level == VictoryCondition.OutcomeLevel.MAJOR:
			major_victory_conditions_v_box_container.add_child(label)
		else:
			minor_victory_conditions_v_box_container.add_child(label)
	minor_objectives_label.visible = minor_victory_conditions_v_box_container.get_child_count() > 0
	briefing_scroll.scroll_vertical = 0
	_queue_fit()


func _update_force_briefing(scenario: Scenario) -> void:
	_clear_forces()
	var friendly_units: Array[Unit] = []
	var enemy_types: Dictionary[Globals.SquadType, bool] = {}
	# Read deployment templates without starting units or creating battle state.
	for node: Node in scenario.get_units():
		if not node is Unit:
			continue
		var unit: Unit = node as Unit
		if not unit.is_active() or unit.is_queued_for_deletion():
			continue
		if unit.team == scenario.player_team:
			friendly_units.append(unit)
		else:
			enemy_types[unit.squad_type] = true
	friendly_units.sort_custom(_roster_less)
	var previous_formation: String = ""
	for unit: Unit in friendly_units:
		var formation: String = unit.get_formation_name()
		if formation != previous_formation:
			previous_formation = formation
			var heading: Label = Label.new()
			heading.text = formation
			heading.theme_type_variation = &"HudSecondary"
			player_roster.add_child(heading)
		var row: HBoxContainer = FORCE_ROW.new()
		player_roster.add_child(row)
		row.setup(unit)
		player_roster_rows[unit] = row
	if friendly_units.is_empty():
		var empty: Label = Label.new()
		empty.text = "No player units assigned."
		player_roster.add_child(empty)
	enemy_assessment.text = _enemy_assessment(enemy_types)
	force_briefing.show()


func _roster_less(left: Unit, right: Unit) -> bool:
	if left.company != right.company:
		return left.company < right.company
	if left.platoon != right.platoon:
		return left.platoon < right.platoon
	if left.squad != right.squad:
		return left.squad < right.squad
	return left.get_instance_id() < right.get_instance_id()


func _enemy_assessment(types: Dictionary[Globals.SquadType, bool]) -> String:
	var infantry: bool = types.has(Globals.SquadType.Rifle)
	var support: bool = types.has(Globals.SquadType.MG) or types.has(Globals.SquadType.MORTAR) or types.has(Globals.SquadType.ANTITANK)
	if infantry and support:
		return "Reports suggest infantry resistance with possible fire support."
	if infantry:
		return "Reports suggest infantry resistance."
	if support:
		return "Enemy fire support may be present."
	return "No reliable intelligence on enemy composition."


func _clear_forces() -> void:
	player_roster_rows.clear()
	for child: Node in player_roster.get_children():
		player_roster.remove_child(child)
		child.queue_free()
	enemy_assessment.text = ""
	force_briefing.hide()


func _clear_objectives() -> void:
	for container: VBoxContainer in [major_victory_conditions_v_box_container, minor_victory_conditions_v_box_container]:
		for child: Node in container.get_children():
			container.remove_child(child)
			child.queue_free()
	minor_objectives_label.hide()


func _on_start_mission_pressed() -> void:
	if _starting or not is_instance_valid(selected_scenario) or not is_instance_valid(selected_map):
		return
	var reason: String = get_lock_reason(selected_scenario)
	if not reason.is_empty():
		lock_label.text = reason
		lock_label.show()
		start_button.disabled = true
		return
	_starting = true
	settings.close_panels()
	start_button.disabled = true
	for button: Button in scenario_buttons.values():
		button.disabled = true
	Globals.map_chosen = selected_map
	Globals.scenario_chosen = selected_scenario
	var fade: Tween = create_tween()
	fade.tween_property($Control, "modulate:a", 0.0, 0.2)
	await fade.finished
	hide()
	game_started.emit(selected_map, selected_scenario, selected_scenario.player_team, Globals.game_mode)


func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_fit_panel.call_deferred()


func _fit_panel() -> void:
	_fit_queued = false
	if not is_node_ready() or is_queued_for_deletion():
		return
	var bounds: Vector2 = $Control.size
	panel.custom_minimum_size.x = minf(960.0, maxf(0.0, bounds.x - 48.0))
	var body: HBoxContainer = $Control/Center/Panel/Content/Body
	var overhead: float = maxf(0.0, panel.get_combined_minimum_size().y - body.get_combined_minimum_size().y)
	var content_height: float = minf(420.0, maxf(120.0, bounds.y - 48.0 - overhead))
	scenario_scroll.custom_minimum_size.y = content_height
	briefing_scroll.custom_minimum_size.y = content_height
	panel.size = Vector2(panel.custom_minimum_size.x, panel.get_combined_minimum_size().y)


func _on_spin_box_value_changed(value: float) -> void:
	time = value
	SessionSettings.mission_time = value
	time_changed.emit(time)
