extends PanelContainer


func _ready() -> void:
	if not OS.is_debug_build():
		hide()


func _on_enemy_selectable_toggled(toggled_on: bool) -> void:
	Debug.enemy_selectable = toggled_on


func _on_no_damage_toggled(toggled_on: bool) -> void:
	Debug.no_damage = toggled_on
