extends PanelContainer

signal layout_requested

const PANEL_WIDTH: float = 280.0
const SCROLL_HEIGHT: float = 270.0

@onready var enemy_selectable: CheckBox = $FoldableContainer/Scroll/VBoxContainer/EnemySelectable
@onready var no_damage: CheckBox = $FoldableContainer/Scroll/VBoxContainer/NoDamage
@onready var axis_ai_status: OptionButton = $FoldableContainer/Scroll/VBoxContainer/AxisAI/Status
@onready var axis_ai_mode: OptionButton = $FoldableContainer/Scroll/VBoxContainer/AxisAI/Mode
@onready var allies_ai_status: OptionButton = $FoldableContainer/Scroll/VBoxContainer/AlliesAI/Status
@onready var allies_ai_mode: OptionButton = $FoldableContainer/Scroll/VBoxContainer/AlliesAI/Mode
@onready var thread_map: CheckBox = $FoldableContainer/Scroll/VBoxContainer/HBoxContainer/ThreadMap
@onready var enemy_team: CheckButton = $FoldableContainer/Scroll/VBoxContainer/HBoxContainer/EnemyTeam
@onready var show_enemy_cmd_connectivity: CheckBox = $FoldableContainer/Scroll/VBoxContainer/ShowEnemyCmdConnectivity
@onready var dont_fire_weapons: CheckBox = $FoldableContainer/Scroll/VBoxContainer/DontFireWeapons
@onready var show_los_lines: CheckBox = $FoldableContainer/Scroll/VBoxContainer/ShowLosLines
@onready var show_movement_lines: CheckBox = $FoldableContainer/Scroll/VBoxContainer/ShowMovementLines
@onready var hide_fog_of_war: CheckBox = $FoldableContainer/Scroll/VBoxContainer/HideFogOfWar
@onready var show_enemies: CheckBox = $FoldableContainer/Scroll/VBoxContainer/ShowEnemies
@onready var influence_map_name: Label = $FoldableContainer/Scroll/VBoxContainer/HBoxContainer2/InfluenceMapName
@onready var influence_map_team_name: Label = $FoldableContainer/Scroll/VBoxContainer/HBoxContainer2/InfluenceMapTeamName

var _ai_controller: Node2D
@onready var section: FoldableContainer = $FoldableContainer
@onready var scroll: ScrollContainer = $FoldableContainer/Scroll
@onready var content: VBoxContainer = $FoldableContainer/Scroll/VBoxContainer

func _ready() -> void:
	if not OS.is_debug_build():
		hide()
	section.fold()
	section.folding_changed.connect(_on_folding_changed)
	minimum_size_changed.connect(_request_layout)
	_request_layout()
	enemy_selectable.button_pressed = Debug.enemy_selectable
	no_damage.button_pressed = Debug.no_damage
	thread_map.button_pressed = Debug.draw_thread_map
	enemy_team.button_pressed = Debug.draw_thread_map_enemy
	show_enemy_cmd_connectivity.button_pressed = Debug.showEnemyCmdConnectivity
	dont_fire_weapons.button_pressed = Debug.dont_fire_wepaons
	show_los_lines.button_pressed = Debug.show_los_lines
	show_movement_lines.button_pressed = Debug.show_movement_lines
	hide_fog_of_war.button_pressed = Debug.hide_fog_of_war
	show_enemies.button_pressed = Debug.show_enemies
	


func _on_folding_changed(_folded: bool) -> void:
	_request_layout()


func _request_layout() -> void:
	layout_requested.emit()


func get_minimum_height() -> float:
	if section.folded:
		return get_combined_minimum_size().y
	return maxf(0.0, get_combined_minimum_size().y - scroll.get_combined_minimum_size().y)


func get_preferred_height() -> float:
	if section.folded:
		return get_minimum_height()
	return get_minimum_height() + minf(SCROLL_HEIGHT, content.get_combined_minimum_size().y)


func fit_panel(panel_position: Vector2, max_height: float) -> void:
	if not section.folded:
		scroll.custom_minimum_size.y = minf(SCROLL_HEIGHT, maxf(0.0, max_height - get_minimum_height()))
	size = Vector2(PANEL_WIDTH, get_combined_minimum_size().y)
	position = panel_position


func _process(delta: float) -> void:
	if not OS.is_debug_build():
		return
	influence_map_name.text = Debug.influence_map_name
	influence_map_team_name.text = Debug.influence_map_team_name



func _on_enemy_selectable_toggled(toggled_on: bool) -> void:
	Debug.enemy_selectable = toggled_on


func _on_no_damage_toggled(toggled_on: bool) -> void:
	Debug.no_damage = toggled_on


func bind_ai_controls(controller: Node2D) -> void:
	_ai_controller = controller
	controller.ai_status_changed.connect(_on_ai_status_changed)
	axis_ai_status.item_selected.connect(_on_ai_status_selected.bind(Globals.Team.AXIS))
	axis_ai_mode.item_selected.connect(_on_ai_mode_selected.bind(Globals.Team.AXIS))
	allies_ai_status.item_selected.connect(_on_ai_status_selected.bind(Globals.Team.ALLIES))
	allies_ai_mode.item_selected.connect(_on_ai_mode_selected.bind(Globals.Team.ALLIES))


func _on_ai_status_changed(team: Globals.Team, enabled: bool, mode: PositionProfile.Mode) -> void:
	var status_selector: OptionButton = axis_ai_status
	var mode_selector: OptionButton = axis_ai_mode
	if team == Globals.Team.ALLIES:
		status_selector = allies_ai_status
		mode_selector = allies_ai_mode
	status_selector.disabled = false
	mode_selector.disabled = false
	status_selector.select(status_selector.get_item_index(int(enabled)))
	mode_selector.select(mode_selector.get_item_index(mode))


func _on_ai_status_selected(index: int, team: Globals.Team) -> void:
	if not is_instance_valid(_ai_controller):
		return
	var selector: OptionButton = axis_ai_status
	if team == Globals.Team.ALLIES:
		selector = allies_ai_status
	_ai_controller.set_team_ai_enabled(team, selector.get_item_id(index) == 1)


func _on_ai_mode_selected(index: int, team: Globals.Team) -> void:
	if not is_instance_valid(_ai_controller):
		return
	var selector: OptionButton = axis_ai_mode
	if team == Globals.Team.ALLIES:
		selector = allies_ai_mode
	var mode: PositionProfile.Mode = PositionProfile.Mode.DEFEND
	if selector.get_item_id(index) == PositionProfile.Mode.ASSAULT:
		mode = PositionProfile.Mode.ASSAULT
	_ai_controller.set_team_ai_mode(team, mode)


func _on_thread_map_toggled(toggled_on: bool) -> void:
	Debug.draw_thread_map = toggled_on


func _on_enemy_team_toggled(toggled_on: bool) -> void:
	Debug.draw_thread_map_enemy = toggled_on


func _on_show_enemy_cmd_connectivity_toggled(toggled_on: bool) -> void:
	Debug.showEnemyCmdConnectivity = toggled_on


func _on_dont_fire_weapons_toggled(toggled_on: bool) -> void:
	Debug.dont_fire_wepaons = toggled_on


func _on_show_los_lines_toggled(toggled_on: bool) -> void:
	Debug.show_los_lines = toggled_on


func _on_show_movement_lines_toggled(toggled_on: bool) -> void:
	Debug.show_movement_lines = toggled_on


func _on_hide_fog_of_war_toggled(toggled_on: bool) -> void:
	Debug.hide_fog_of_war = toggled_on


func _on_show_enemies_toggled(toggled_on: bool) -> void:
	Debug.show_enemies = toggled_on
