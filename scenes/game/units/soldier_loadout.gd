extends Resource
class_name SoldierLoadout

@export var nickname: String = "Rifleman"
@export var rank_grade: RankGrades.Grade = RankGrades.Grade.RIFLEMAN  # use RankGrades.Grade (RIFLEMAN, ASSISTANT_TEAM_LEADER, …)
@export var role: RankGrades.Role = RankGrades.Role.RIFLEMAN
@export var weapon: WeaponSpec      # drag a WeaponSpec resource here
@export var is_key_role: bool = false  # for UI badges / AI priority
