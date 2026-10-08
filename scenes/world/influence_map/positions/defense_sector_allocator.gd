class_name DefenseSectorAllocator
extends RefCounted


static func select_guard(units: Array[Unit]) -> Unit:
	var best: Unit = units[0]
	var best_cost: float = INF
	for unit: Unit in units:
		var cost: float = 1.0
		if unit.squad_type == Globals.SquadType.MG or unit.squad_type == Globals.SquadType.MORTAR:
			cost = 3.0
		elif unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS or unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
			cost = 2.0
		if InfluenceUnitQuery.get_unit_firepower(unit) <= 0.0:
			cost = 0.25
		if InfluenceUnitQuery.get_unit_effectiveness(unit) < 0.45:
			cost += 4.0
		if cost < best_cost:
			best = unit
			best_cost = cost
	return best


static func priorities(area: DefenseAreaAssessment) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = area.approaches.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a["priority"], b["priority"]):
			return a["priority"] > b["priority"]
		return a["id"] < b["id"])
	return ordered


static func critical_count(area: DefenseAreaAssessment) -> int:
	var count: int = 0
	for approach: Dictionary in area.approaches:
		if approach["priority"] >= area.max_priority * 0.4 and approach["priority"] > 0.2:
			count += 1
	return count


static func assign(area: DefenseAreaAssessment, units: Array[Unit], previous: Dictionary) -> Dictionary[Unit, int]:
	var result: Dictionary[Unit, int] = {}
	var unassigned: Array[Unit] = units.duplicate()
	var counts: Dictionary = {}
	var firepower: Dictionary[Unit, float] = {}
	for unit: Unit in units:
		firepower[unit] = PositionFeatureEvaluator.risk(InfluenceUnitQuery.get_unit_firepower(unit))
	var ordered: Array[Dictionary] = priorities(area)
	while not unassigned.is_empty() and not ordered.is_empty():
		var sector: Dictionary = ordered[0]
		var best_priority: float = -INF
		for approach: Dictionary in ordered:
			# Additional squads contribute less to an already assigned sector.
			var marginal: float = approach["priority"] / pow(3.0, counts.get(approach["id"], 0))
			for unit: Unit in unassigned:
				if previous.get(unit, {}).get("sector", -1) == approach["id"]:
					marginal *= 1.25
					break
			if marginal > best_priority:
				sector = approach
				best_priority = marginal
		var best: Unit = unassigned[0]
		var best_value: float = -INF
		for unit: Unit in unassigned:
			var role: float = 1.0
			if unit.squad_type == Globals.SquadType.MG:
				role = 1.7
			elif unit.squad_type == Globals.SquadType.MORTAR:
				role = 1.3
			var response: float = sector["response_distances"].get(unit.current_hex, INF) * InfluenceUnitQuery.captured_crossing_seconds(unit)
			var value: float = role * firepower[unit] * InfluenceUnitQuery.get_unit_effectiveness(unit) / (1.0 + response / 30.0)
			if previous.get(unit, {}).get("sector", -1) == sector["id"]:
				value *= 1.2
			if value > best_value:
				best = unit
				best_value = value
		result[best] = sector["id"]
		counts[sector["id"]] = counts.get(sector["id"], 0) + 1
		unassigned.erase(best)
	return result
