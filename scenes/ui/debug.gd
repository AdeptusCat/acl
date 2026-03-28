extends PanelContainer


func _ready() -> void:
	if not OS.is_debug_build():
		hide()


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
	
	
