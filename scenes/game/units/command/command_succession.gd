extends Node
class_name CommandSuccession

const REFRESH_SECONDS: float = 0.25

var formations: Array[FormationCommand] = []
var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		refresh()


static func is_headquarters(unit: Unit) -> bool:
	return unit.squad_type in [Globals.SquadType.PLATOON_HEADQUARTERS, Globals.SquadType.COMPANY_HEADQUARTERS]


static func headquarters_leader(unit: Unit, deputy_only: bool = false) -> Soldier:
	var best: Soldier = null
	if not unit.is_active() or unit.surrendered:
		return null
	for soldier: Soldier in unit.squad_fire.soldiers:
		if not soldier.is_alive or soldier.rank_grade < RankGrades.Grade.SQUAD_LEADER:
			continue
		if soldier.role not in [RankGrades.Role.SQUAD_LEADER, RankGrades.Role.ASSISTANT_SQUAD_LEADER, RankGrades.Role.TEAM_LEADER, RankGrades.Role.ASSISTANT_TEAM_LEADER]:
			continue
		if deputy_only and soldier.role in [RankGrades.Role.SQUAD_LEADER, RankGrades.Role.ASSISTANT_SQUAD_LEADER]:
			continue
		if best == null or soldier.rank_grade > best.rank_grade:
			best = soldier
	return best


static func squad_leader(unit: Unit) -> Soldier:
	if not unit.is_active() or unit.surrendered:
		return null
	if is_headquarters(unit):
		return headquarters_leader(unit)
	for soldier: Soldier in unit.squad_fire.soldiers:
		if soldier.is_alive and soldier.role == RankGrades.Role.SQUAD_LEADER and soldier.rank_grade >= RankGrades.Grade.TEAM_LEADER:
			return soldier
	return null


func refresh() -> void:
	var units: Array[Unit] = Globals.get_units()
	units.sort_custom(_unit_order)
	for unit: Unit in units:
		unit.company_command = _formation(unit, Globals.SquadType.COMPANY_HEADQUARTERS)
		if unit.platoon > 0:
			unit.platoon_command = _formation(unit, Globals.SquadType.PLATOON_HEADQUARTERS)
		else:
			unit.platoon_command = null
		if unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
			unit.company_command.headquarters = unit
			unit.company_command.established = true
		elif unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS and unit.platoon_command != null:
			unit.platoon_command.headquarters = unit
			unit.platoon_command.established = true
	# Resolve platoons first: company successors must already command a platoon.
	for formation: FormationCommand in formations:
		if formation.level == Globals.SquadType.PLATOON_HEADQUARTERS:
			_resolve(formation, units)
	for formation: FormationCommand in formations:
		if formation.level == Globals.SquadType.COMPANY_HEADQUARTERS:
			_resolve(formation, units)
	for unit: Unit in units:
		_assign(unit)
	for unit: Unit in units:
		unit._on_command_connectivity_timeout()


func _formation(unit: Unit, level: Globals.SquadType) -> FormationCommand:
	var platoon: int = 0
	if level == Globals.SquadType.PLATOON_HEADQUARTERS:
		platoon = unit.platoon
	for existing: FormationCommand in formations:
		if existing.team == unit.team and existing.company == unit.company and existing.platoon == platoon and existing.level == level:
			return existing
	var result: FormationCommand = FormationCommand.new()
	result.team = unit.team
	result.company = unit.company
	result.platoon = platoon
	result.level = level
	result.support_link = CommandConnectivity.new()
	add_child(result.support_link)
	formations.append(result)
	return result


func _resolve(formation: FormationCommand, units: Array[Unit]) -> void:
	if not formation.established:
		return
	if is_instance_valid(formation.headquarters) and formation.commander != formation.headquarters:
		var local_leader: Soldier = headquarters_leader(formation.headquarters)
		if local_leader != null:
			formation.commander = formation.headquarters
			formation.leader = local_leader
			formation.reconstituted = false
	if not formation.has_commander():
		formation.commander = null
		formation.leader = null
		formation.reconstituted = false
		if is_instance_valid(formation.headquarters):
			formation.leader = headquarters_leader(formation.headquarters)
			if formation.leader != null:
				formation.commander = formation.headquarters
		if formation.commander == null:
			for candidate: Unit in units:
				if candidate.team != formation.team or candidate.company != formation.company:
					continue
				var leader: Soldier = null
				if formation.level == Globals.SquadType.PLATOON_HEADQUARTERS:
					if candidate.platoon != formation.platoon or is_headquarters(candidate):
						continue
					leader = squad_leader(candidate)
				else:
					var platoon_command: FormationCommand = candidate.platoon_command
					if platoon_command != null and platoon_command.has_commander() and platoon_command.commander == candidate:
						leader = platoon_command.leader
				if leader != null and (formation.leader == null or leader.rank_grade > formation.leader.rank_grade):
					formation.commander = candidate
					formation.leader = leader
	formation.support_link.clear_connectivity()
	if formation.has_commander() and formation.has_remnant() and LOSHelper.ground_layer != null:
		formation.support_link.compute_direct_connectivity(formation.headquarters, formation.commander)
		if formation.headquarters.current_hex == formation.commander.current_hex and not formation.headquarters.is_moving and not formation.commander.is_moving:
			formation.reconstituted = true


func _assign(unit: Unit) -> void:
	var company: FormationCommand = unit.company_command
	var platoon: FormationCommand = unit.platoon_command
	var level: int = -1
	var supported: bool = false
	var reconstituted: bool = false
	var efficiency: float = 1.0
	var commander: Unit = null
	if platoon != null and platoon.has_commander():
		commander = platoon.commander
		if commander == unit and (commander != platoon.headquarters or platoon.leader.rank_grade < RankGrades.Grade.PLATOON_LEADER):
			level = Globals.SquadType.PLATOON_HEADQUARTERS
			supported = commander == platoon.headquarters or platoon.has_support()
			reconstituted = platoon.reconstituted
			efficiency = platoon.efficiency()
	if unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS or unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS or commander == unit or (platoon == null):
		commander = company.commander
		if not company.has_commander():
			commander = null
	if company.has_commander() and company.commander == unit:
		commander = null
		if unit != company.headquarters or company.leader.rank_grade < RankGrades.Grade.COMPANY_LEADER:
			level = Globals.SquadType.COMPANY_HEADQUARTERS
			supported = unit == company.headquarters or company.has_support()
			reconstituted = company.reconstituted
			efficiency = company.efficiency()
	# A leaderless platoon remnant follows its acting platoon commander.
	if unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS and platoon != null and platoon.has_commander() and platoon.commander != unit:
		commander = platoon.commander
	unit.command_squad = commander
	var changed: bool = unit.acting_command_level != level or unit.acting_command_supported != supported or unit.acting_command_reconstituted != reconstituted or not is_equal_approx(unit.command_efficiency, efficiency)
	unit.acting_command_level = level
	unit.acting_command_supported = supported
	unit.acting_command_reconstituted = reconstituted
	unit.command_efficiency = efficiency
	if changed:
		unit._refresh_leader_aura()


static func _unit_order(first: Unit, second: Unit) -> bool:
	if first.team != second.team:
		return first.team < second.team
	if first.company != second.company:
		return first.company < second.company
	if first.platoon != second.platoon:
		return first.platoon < second.platoon
	if first.squad != second.squad:
		return first.squad < second.squad
	return first.name.naturalnocasecmp_to(second.name) < 0
