extends RefCounted
class_name ExitUnitsState

var exit_hexes: Array[Vector2i]
var units_exited: Array[Unit] = []


func record_units(team: Globals.Team) -> void:
	for unit: Unit in Globals.get_units():
		record_unit_entry(unit, team, unit.current_hex)
	for unit: Unit in Globals.get_exited_units():
		if unit.exit_record != null:
			record_unit_entry(unit, team, unit.exit_record.hex)


func record_unit_entry(unit: Unit, team: Globals.Team, hex: Vector2i) -> void:
	if unit.team != team or not unit.alive or unit.surrendered:
		return
	if exit_hexes.has(hex) and not units_exited.has(unit):
		units_exited.append(unit)
