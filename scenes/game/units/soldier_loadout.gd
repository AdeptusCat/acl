extends Resource
class_name SoldierLoadout

# roles kept simple; map to your runtime Soldier.Role later
enum Role { RIFLEMAN, GUNNER, LOADER, RADIO, MEDIC, ASSISTANT_TEAM_LEADER, TEAM_LEADER, SQUAD_LEADER }

@export var nickname: String = "Rifleman"
@export var rank_grade: RankGrades.Grade = RankGrades.Grade.RIFLEMAN  # use RankGrades.Grade (RIFLEMAN, ASSISTANT_TEAM_LEADER, …)
@export var role: Role = Role.RIFLEMAN
@export var weapon: WeaponSpec      # drag a WeaponSpec resource here
@export var is_key_role: bool = false  # for UI badges / AI priority
