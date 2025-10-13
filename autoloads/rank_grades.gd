# RankGrades.gd (autoload)
extends Node

enum Grade { SOLDIER, ASSISTANT_TEAM_LEADER, TEAM_LEADER, SQUAD_LEADER, PLATOON_LEADER, COMPANY_LEADER }
enum Role { SOLDIER, GUNNER, LOADER, ASSISTANT, RADIO, MEDIC, ASSISTANT_TEAM_LEADER, TEAM_LEADER, ASSISTANT_SQUAD_LEADER, SQUAD_LEADER }

func get_role_name(role: Role) -> String:
	match role:
		Role.SOLDIER: return "Soldier"
		Role.GUNNER: return "Gunner"
		Role.ASSISTANT: return "Assistant"
		Role.LOADER: return "Loader"
		Role.RADIO: return "Radio Operator"
		Role.MEDIC: return "Medic"
		Role.ASSISTANT_TEAM_LEADER: return "Asst. Team Leader"
		Role.TEAM_LEADER: return "Team Leader"
		Role.ASSISTANT_SQUAD_LEADER: return "Asst. Leader"
		Role.SQUAD_LEADER: return "Squad Leader"
		_: return "Unknown"

const GRADE_PARAMS: Dictionary = {
	Grade.SOLDIER:      			{ "lead": 0.00, "rally": 0.00, "radius": 0, "coh_mult": 1.00 },
	Grade.ASSISTANT_TEAM_LEADER: 	{ "lead": 0.03, "rally": 0.015, "radius": 0, "coh_mult": 1.01 },
	Grade.TEAM_LEADER:   			{ "lead": 0.05, "rally": 0.03, "radius": 0, "coh_mult": 1.02 },
	Grade.SQUAD_LEADER:  			{ "lead": 0.10, "rally": 0.05, "radius": 0, "coh_mult": 1.04 },
	Grade.PLATOON_LEADER:			{ "lead": 0.18, "rally": 0.08, "radius": 1, "coh_mult": 1.06 },
	Grade.COMPANY_LEADER:			{ "lead": 0.22, "rally": 0.10, "radius": 2, "coh_mult": 1.08 },
}

const TITLES: Dictionary = {
	"UK": {
		Grade.SOLDIER:       "Private",
		Grade.ASSISTANT_TEAM_LEADER: "Acting Lance Corporal",
		Grade.TEAM_LEADER:    "Lance Corporal",
		Grade.SQUAD_LEADER:   "Sergeant",
		Grade.PLATOON_LEADER: "Second Lieutenant",
		Grade.COMPANY_LEADER: "Captain",
	},
	"US": {
		Grade.SOLDIER:       "Private",
		Grade.ASSISTANT_TEAM_LEADER: "Private First Class",
		Grade.TEAM_LEADER:    "Corporal",
		Grade.SQUAD_LEADER:   "Sergeant",
		Grade.PLATOON_LEADER: "Second Lieutenant",
		Grade.COMPANY_LEADER: "Captain",
	},
	"DE": {
		Grade.SOLDIER:       "Schütze",
		Grade.ASSISTANT_TEAM_LEADER: "Obergefreiter",
		Grade.TEAM_LEADER:    "Gefreiter",
		Grade.SQUAD_LEADER:   "Feldwebel",
		Grade.PLATOON_LEADER: "Leutnant",
		Grade.COMPANY_LEADER: "Hauptmann",
	},
	"SU": {
		Grade.SOLDIER:       "Ryadovoy",
		Grade.ASSISTANT_TEAM_LEADER: "Yefreytor",
		Grade.TEAM_LEADER:    "Mladshiy Serzhant",
		Grade.SQUAD_LEADER:   "Serzhant",
		Grade.PLATOON_LEADER: "Mladshiy Leytenant",
		Grade.COMPANY_LEADER: "Kapitan",
	},
}

func title_for(faction: String, grade: int) -> String:
	var fm: Dictionary = {}
	if TITLES.has(faction):
		fm = TITLES[faction]
	if fm.has(grade):
		return String(fm[grade])
	return "Leader"
