extends Node2D

@onready var axis_target_area = $AxisTargetArea
@onready var allies_target_area = $AlliesTargetArea

func show_target(team: int):
	if team == 0:
		axis_target_area.show()
		allies_target_area.hide()
	elif team == 1:
		axis_target_area.hide()
		allies_target_area.show()
	elif team == -1:
		axis_target_area.hide()
		allies_target_area.hide()
