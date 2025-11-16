class_name SquadTacticalState
extends Resource

enum FormationRole {
	NONE,
	ASSAULT,
	BASE_OF_FIRE,
	RESERVE
}

var in_contact: bool = false
var formation_role: int = FormationRole.NONE
var allow_maneuver_under_contact: bool = false


func is_free() -> bool:
	if formation_role == FormationRole.NONE or formation_role == FormationRole.RESERVE:
		return true
	else:
		return false
