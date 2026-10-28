extends RefCounted
class_name FormationCommand

const ACTING_EFFICIENCY: float = 0.75

var team: Globals.Team
var company: Unit.Company
var platoon: int = 0
var level: Globals.SquadType
var headquarters: Unit
var commander: Unit
var leader: Soldier
var support_link: CommandConnectivity
var reconstituted: bool = false
var established: bool = false


func has_commander() -> bool:
	return is_instance_valid(commander) and commander.is_active() and not commander.surrendered and leader != null and leader.is_alive and commander.squad_fire.soldiers.has(leader)


func has_remnant() -> bool:
	return is_instance_valid(headquarters) and headquarters != commander and headquarters.is_active() and not headquarters.surrendered and headquarters.members_alive > 0


func has_support() -> bool:
	return has_commander() and has_remnant() and is_instance_valid(support_link) and support_link.command_link_strength > 0.0


func efficiency() -> float:
	if not has_commander():
		return 0.0
	if commander == headquarters or (reconstituted and has_support()):
		return 1.0
	return ACTING_EFFICIENCY
