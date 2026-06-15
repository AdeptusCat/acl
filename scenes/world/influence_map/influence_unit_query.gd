class_name InfluenceUnitQuery
extends RefCounted


static func get_config_units(team: int, group_name: String) -> Array[Unit]:
	var result: Array[Unit] = []
	var units: Array[Unit] = Globals.get_units_for_team(team)

	for unit: Unit in units:
		if not is_valid_living_unit(unit):
			continue

		if group_name != "":
			if not unit.is_in_group(group_name):
				continue

		result.append(unit)

	return result


static func is_valid_living_unit(unit: Unit) -> bool:
	if not is_instance_valid(unit):
		return false

	if not unit.alive:
		return false

	return true


static func get_unit_firepower(_unit: Unit) -> float:
	var firepower: float = 1.0
	return firepower


static func get_unit_effectiveness(unit: Unit) -> float:
	var effectiveness: float = remap(unit.stress_system.S_eff, 0.0, 100.0, 1.0, 0.0)
	return effectiveness


static func get_squad_type_priority(squad_type: Globals.SquadType) -> int:
	if squad_type == Globals.SquadType.MG:
		return 0

	if squad_type == Globals.SquadType.Rifle:
		return 1

	if squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
		return 2

	if squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
		return 3

	if squad_type == Globals.SquadType.ANTITANK:
		return 4

	if squad_type == Globals.SquadType.MORTAR:
		return 5

	return 999


static func compare_units_by_squad_type_priority(unit_a: Unit, unit_b: Unit) -> bool:
	var priority_a: int = get_squad_type_priority(unit_a.squad_type)
	var priority_b: int = get_squad_type_priority(unit_b.squad_type)

	if priority_a == priority_b:
		return unit_a.get_instance_id() < unit_b.get_instance_id()

	return priority_a < priority_b
