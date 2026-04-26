extends Resource
class_name UnitsCollection

var units_collection: Dictionary[Globals.Team, Units] = {
	Globals.Team.AXIS: Units.new(),
	Globals.Team.ALLIES: Units.new()
}
