extends HBoxContainer
class_name VictoryConditionResult

@onready var check_box: CheckBox = $CheckBox
@onready var label: Label = $Label

func set_victory_condition(is_met: bool, description: String):
	check_box.button_pressed = is_met
	label.text = description
