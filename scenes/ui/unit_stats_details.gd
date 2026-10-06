extends Control


func set_details(unit: Unit) -> void:
	$VBoxContainer/HBoxContainer/FirepowerLabel.text = str(unit.firepower)
	$VBoxContainer/HBoxContainer2/RangeLabel.text = str(unit.weapon_range)
	$VBoxContainer/HBoxContainer3/MoraleLabel.text = str(unit.morale)
