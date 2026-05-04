extends Resource
class_name SquadLoadoutSpec

@export var squad_type: Unit.SquadType = Unit.SquadType.Rifle
@export var team: Globals.Team = Globals.Team.AXIS
@export var soldiers: Array[SoldierLoadout] = []
