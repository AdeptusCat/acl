extends PanelContainer


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
@onready var hud_control: Control = get_parent() as Control
@onready var tile_details: Control = hud_control.get_node("TileDetails") as Control
@onready var mission_objectives: Control = hud_control.get_node("MissionObjectives") as Control

func _ready() -> void:
	if not OS.is_debug_build():
		hide()
	section.fold()
	section.folding_changed.connect(_on_folding_changed)
	minimum_size_changed.connect(_queue_fit)
	hud_control.resized.connect(_queue_fit)
	tile_details.item_rect_changed.connect(_queue_fit)
	tile_details.visibility_changed.connect(_queue_fit)
	mission_objectives.item_rect_changed.connect(_queue_fit)
	mission_objectives.visibility_changed.connect(_queue_fit)
	_queue_fit()
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
	_queue_fit()


func _queue_fit() -> void:
	_fit_panel.call_deferred()


func _fit_panel() -> void:
	if not is_node_ready() or is_queued_for_deletion():
		return
	var bottom: float = hud_control.size.y - 12.0
	if tile_details.visible:
		bottom = minf(bottom, tile_details.position.y - 12.0)
	var top: float = hud_control.get_node("TryAgain").get_rect().end.y + 12.0
	var column: Rect2 = Rect2(12.0, 0.0, 280.0, hud_control.size.y)
	if mission_objectives.visible and column.intersects(mission_objectives.get_rect()):
		top = maxf(top, mission_objectives.get_rect().end.y + 12.0)
	var overhead: float = maxf(0.0, get_combined_minimum_size().y - scroll.get_combined_minimum_size().y)
	scroll.custom_minimum_size.y = minf(270.0, maxf(80.0, bottom - top - overhead))
	size = Vector2(280.0, get_combined_minimum_size().y)
	position = Vector2(12.0, bottom - size.y)


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
