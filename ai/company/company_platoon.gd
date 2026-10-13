class_name CompanyPlatoon
extends RefCounted

enum Role { DEFEND, SUPPORT, MANEUVER, RESERVE, REINFORCE, WITHDRAW }

var company: Unit.Company
var number: int
var squads: Array[Unit] = []
var planner: PlatoonAI
var role: Role = Role.DEFEND
var objective: Vector2i
var task: ScenarioGoalTask
var support: CompanyPlatoon
var reserve_deployed: bool = false
var quiet_since: float = -INF
var mission_key: String = ""
var reason: String = ""
var staging_hex: Vector2i
var sector_cells: Array[Vector2i] = []


func combat_units() -> Array[Unit]:
	var result: Array[Unit] = []
	for unit: Unit in squads:
		if TacticalPositionExecutor.is_active_defender(unit) and not HqSupportPositionPolicy.is_headquarters(unit):
			result.append(unit)
	return result


func effectiveness() -> float:
	var total: float = 0.0
	var count: int = 0
	for unit: Unit in squads:
		if HqSupportPositionPolicy.is_headquarters(unit):
			continue
		count += 1
		if TacticalPositionExecutor.is_active_defender(unit) and unit.is_good_order():
			total += InfluenceUnitQuery.get_unit_effectiveness(unit)
	return total / float(maxi(count, 1))


func support_firepower() -> float:
	var total: float = 0.0
	for unit: Unit in combat_units():
		if unit.squad_type not in [Globals.SquadType.Rifle, Globals.SquadType.MG] or not PositionQueryService.can_follow_intent(unit):
			continue
		total += InfluenceUnitQuery.get_unit_firepower(unit)
	return total


func can_maneuver() -> bool:
	for unit: Unit in combat_units():
		if unit.squad_type == Globals.SquadType.Rifle and PositionQueryService.can_assault(unit) and PositionQueryService.can_follow_intent(unit):
			return true
	return false


func is_busy() -> bool:
	for unit: Unit in combat_units():
		if PlatoonPositionStability.is_busy(unit) or unit.in_close_combat:
			return true
	return false


func anchor() -> Vector2i:
	var units: Array[Unit] = combat_units()
	if units.is_empty():
		if not squads.is_empty():
			return squads[0].current_hex
		return objective
	var best: Unit = units[0]
	var best_distance: int = 2147483647
	for candidate: Unit in units:
		var distance: int = 0
		for other: Unit in units:
			distance += LOSHelper.get_hex_distance(candidate.current_hex, other.current_hex)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best.current_hex
