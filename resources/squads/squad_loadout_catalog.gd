@tool
extends Resource
class_name Squads

@export var squads: Dictionary[Globals.SquadType, SquadLoadoutSpec]

func get_squad(squad_type: Globals.SquadType) -> SquadLoadoutSpec:
	return squads[squad_type]
