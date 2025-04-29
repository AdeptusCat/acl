extends CanvasLayer

@onready var result_label := $CenterContainer/ResultLabel

func show_winner(team: int):
	if team == -1:
		result_label.text = "No one wins."
	elif team == 0:
		result_label.text = "Team Axis wins!"
	elif team == 1:
		result_label.text = "Team Allies wins!"
	visible = true
