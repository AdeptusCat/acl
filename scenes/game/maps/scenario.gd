extends Node2D
class_name Scenario

@onready var units: Node2D = $Units
@onready var objective_axis: Node2D = $Objectives/Axis
@onready var objective_allies: Node2D = $Objectives/Allies


@export var scenario_name: String = "scenario"


func get_objectives(team: Globals.Team) -> Array[Node]:
	match team:
		Globals.Team.AXIS:
			return objective_axis.get_children()
		Globals.Team.ALLIES:
			return objective_allies.get_children()
		_:
			return objective_axis.get_children()


func get_units() -> Array[Node]:
	return units.get_children()
