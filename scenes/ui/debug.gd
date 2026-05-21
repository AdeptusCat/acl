extends PanelContainer


@onready var enemy_selectable: CheckBox = $VBoxContainer/EnemySelectable
@onready var no_damage: CheckBox = $VBoxContainer/NoDamage
@onready var thread_map: CheckBox = $VBoxContainer/HBoxContainer/ThreadMap
@onready var enemy_team: CheckButton = $VBoxContainer/HBoxContainer/EnemyTeam
@onready var show_enemy_cmd_connectivity: CheckBox = $VBoxContainer/ShowEnemyCmdConnectivity
@onready var dont_fire_weapons: CheckBox = $VBoxContainer/DontFireWeapons
@onready var show_los_lines: CheckBox = $VBoxContainer/ShowLosLines
@onready var show_movement_lines: CheckBox = $VBoxContainer/ShowMovementLines
@onready var hide_fog_of_war: CheckBox = $VBoxContainer/HideFogOfWar
@onready var show_enemies: CheckBox = $VBoxContainer/ShowEnemies

enum DebugInfluenceView {
	NONE,
	COMPOSITE,
	TERRAIN_COVER,
	TERRAIN_MOVE_COST,
	ENEMY_VISIBILITY,
	ENEMY_FIRE_THREAT,
	FRIENDLY_SUPPORT,
	OBJECTIVE_PRESSURE,
	KNOWN_ENEMY_POSITION,
	NO_GO
}

func _ready() -> void:
	if not OS.is_debug_build():
		hide()
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
	






func _on_enemy_selectable_toggled(toggled_on: bool) -> void:
	Debug.enemy_selectable = toggled_on


func _on_no_damage_toggled(toggled_on: bool) -> void:
	Debug.no_damage = toggled_on


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
