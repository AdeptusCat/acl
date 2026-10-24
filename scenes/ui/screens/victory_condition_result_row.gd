extends HBoxContainer
class_name VictoryConditionResult

const FAILED_ICON: Texture2D = preload("res://assets/ui/hud/checkbox_failed.svg")
const COMPLETED_COLOR: Color = Color(0.65, 0.85, 0.55)
const FAILED_COLOR: Color = Color(1.0, 0.55, 0.45)
const UNKNOWN_COLOR: Color = Color(0.9, 0.87, 0.77)

@onready var check_box: CheckBox = $CheckBox
@onready var label: Label = $Label

func set_victory_condition(is_met: bool, description: String, progress_valid: bool = true) -> void:
	check_box.button_pressed = progress_valid and is_met
	check_box.remove_theme_icon_override("unchecked")
	check_box.remove_theme_icon_override("unchecked_disabled")
	check_box.remove_theme_color_override("checkbox_unchecked_color")
	label.text = description
	if not progress_valid:
		label.add_theme_color_override("font_color", UNKNOWN_COLOR)
	elif is_met:
		label.add_theme_color_override("font_color", COMPLETED_COLOR)
	else:
		check_box.add_theme_icon_override("unchecked", FAILED_ICON)
		check_box.add_theme_icon_override("unchecked_disabled", FAILED_ICON)
		check_box.add_theme_color_override("checkbox_unchecked_color", Color.WHITE)
		label.add_theme_color_override("font_color", FAILED_COLOR)
