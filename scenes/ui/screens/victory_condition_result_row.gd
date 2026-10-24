extends HBoxContainer
class_name VictoryConditionResult

@onready var check_box: CheckBox = $CheckBox
@onready var label: Label = $Label

func set_victory_condition(is_met: bool, description: String) -> void:
	check_box.button_pressed = is_met
	label.text = description
	if is_met:
		label.add_theme_color_override("font_color", Color(0.65, 0.85, 0.55))
	else:
		label.add_theme_color_override("font_color", Color(0.9, 0.87, 0.77))
