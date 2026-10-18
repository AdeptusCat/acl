@tool
extends Resource
class_name SquadsCollection

@export var squads_collection: Dictionary[Globals.Team, Squads]

func get_squad(team: Globals.Team) -> Squads:
	return squads_collection[team]
