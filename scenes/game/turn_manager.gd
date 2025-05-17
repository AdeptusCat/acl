extends Node

signal turn_changed(new_team)
var current_team: int = 0

func _ready():
	$"../InputManager".connect("end_turn", self, "_on_end_turn")

func _on_end_turn():
	current_team = 1 - current_team
	emit_signal("turn_changed", current_team)
