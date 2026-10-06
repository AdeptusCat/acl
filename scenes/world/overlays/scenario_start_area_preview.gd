extends Node2D

@onready var axis_target_area: Node2D = $AxisTargetArea
@onready var allies_target_area: Node2D = $AlliesTargetArea

func show_target(team: int) -> void:
	if team == 0:
		axis_target_area.show()
		allies_target_area.hide()
	elif team == 1:
		axis_target_area.hide()
		allies_target_area.show()
	elif team == -1:
		axis_target_area.hide()
		allies_target_area.hide()
