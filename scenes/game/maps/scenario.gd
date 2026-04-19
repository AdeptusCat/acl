extends Node2D
class_name Scenario

@onready var units: Node2D = $Units
@onready var axis: Node2D = $Objectives/Axis
@onready var allies: Node2D = $Objectives/Allies


func get_objectives(team: Globals.Team) -> Array[Node]:
	match team:
		Globals.Team.AXIS:
			return axis.get_children()
		Globals.Team.ALLIES:
			return allies.get_children()
		_:
			return axis.get_children()


func get_units() -> Array[Node]:
	return units.get_children()
