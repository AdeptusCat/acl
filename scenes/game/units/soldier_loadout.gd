extends Resource
class_name SoldierLoadout

@export var nickname: String = "Soldier"
@export var rank_grade: RankGrades.Grade = RankGrades.Grade.SOLDIER  # use RankGrades.Grade (SOLDIER, ASSISTANT_TEAM_LEADER, …)
@export var role: RankGrades.Role = RankGrades.Role.SOLDIER
@export var weapon: WeaponSpec      # drag a WeaponSpec resource here
@export var is_key_role: bool = false  # for UI badges / AI priority
