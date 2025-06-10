extends Control


func set_details(unit):
	$VBoxContainer/HBoxContainer/FirepowerLabel.text = str(unit.firepower)
	$VBoxContainer/HBoxContainer2/RangeLabel.text = str(unit.range)
	$VBoxContainer/HBoxContainer3/MoraleLabel.text = str(unit.morale)
