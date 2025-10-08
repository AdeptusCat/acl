# RankGrades.gd (autoload)
extends Node

enum Grade { RIFLEMAN, ASSISTANT_TEAM_LEADER, TEAM_LEADER, SQUAD_LEADER, PLATOON_LEADER, COMPANY_LEADER }
enum Role { RIFLEMAN, GUNNER, LOADER, RADIO, MEDIC, ASSISTANT_TEAM_LEADER, TEAM_LEADER, ASSISTANT_SQUAD_LEADER, SQUAD_LEADER }


const GRADE_PARAMS: Dictionary = {
	Grade.RIFLEMAN:      			{ "lead": 0.00, "rally": 0.00, "radius": 0, "coh_mult": 1.00 },
	Grade.ASSISTANT_TEAM_LEADER: 	{ "lead": 0.03, "rally": 0.015, "radius": 0, "coh_mult": 1.01 },
	Grade.TEAM_LEADER:   			{ "lead": 0.05, "rally": 0.03, "radius": 0, "coh_mult": 1.02 },
	Grade.SQUAD_LEADER:  			{ "lead": 0.10, "rally": 0.05, "radius": 1, "coh_mult": 1.04 },
	Grade.PLATOON_LEADER:			{ "lead": 0.18, "rally": 0.08, "radius": 2, "coh_mult": 1.06 },
	Grade.COMPANY_LEADER:			{ "lead": 0.22, "rally": 0.10, "radius": 3, "coh_mult": 1.08 },
}

const TITLES: Dictionary = {
	"UK": {
		Grade.RIFLEMAN:       "Private",
		Grade.ASSISTANT_TEAM_LEADER: "Acting Lance Corporal",
		Grade.TEAM_LEADER:    "Lance Corporal",
		Grade.SQUAD_LEADER:   "Sergeant",
		Grade.PLATOON_LEADER: "Second Lieutenant",
		Grade.COMPANY_LEADER: "Captain",
	},
	"US": {
		Grade.RIFLEMAN:       "Private",
		Grade.ASSISTANT_TEAM_LEADER: "Private First Class",
		Grade.TEAM_LEADER:    "Corporal",
		Grade.SQUAD_LEADER:   "Sergeant",
		Grade.PLATOON_LEADER: "Second Lieutenant",
		Grade.COMPANY_LEADER: "Captain",
	},
	"DE": {
		Grade.RIFLEMAN:       "Schütze",
		Grade.ASSISTANT_TEAM_LEADER: "Obergefreiter",
		Grade.TEAM_LEADER:    "Gefreiter",
		Grade.SQUAD_LEADER:   "Feldwebel",
		Grade.PLATOON_LEADER: "Leutnant",
		Grade.COMPANY_LEADER: "Hauptmann",
	},
	"SU": {
		Grade.RIFLEMAN:       "Ryadovoy",
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
