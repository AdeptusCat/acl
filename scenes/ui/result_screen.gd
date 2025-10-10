extends CanvasLayer

@onready var result_label := $CenterContainer/ResultLabel

signal try_again

func _on_show_winner(team: int):
	if team == -1:
		result_label.text = "No one wins."
	elif team == 0:
		result_label.text = "Team Axis wins!"
	elif team == 1:
		result_label.text = "Team Allies wins!"
	visible = true


func _on_try_again_pressed() -> void:
	try_again.emit()


func _on_keep_playing_pressed() -> void:
	hide()
