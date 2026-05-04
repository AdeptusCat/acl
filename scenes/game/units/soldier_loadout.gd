extends Resource
class_name SoldierLoadout

@export var nickname: String = "Soldier"
@export var rank_grade: RankGrades.Grade = RankGrades.Grade.SOLDIER  # use RankGrades.Grade (SOLDIER, ASSISTANT_TEAM_LEADER, …)
@export var role: RankGrades.Role = RankGrades.Role.SOLDIER
@export var weapon: WeaponSpec      # drag a WeaponSpec resource here
@export var is_key_role: bool = false  # for UI badges / AI priority
var weapon_resource_path: String

func copy_runtime() -> SoldierLoadout:
	var result: SoldierLoadout = SoldierLoadout.new()

	result.nickname = nickname
	result.rank_grade = rank_grade
	result.role = role
	result.weapon = weapon
	result.is_key_role = is_key_role

	return result
