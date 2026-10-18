extends Resource
class_name SoldierLoadout

@export var nickname: String = "Soldier"
@export var rank_grade: RankGrades.Grade = RankGrades.Grade.SOLDIER  # use RankGrades.Grade (SOLDIER, ASSISTANT_TEAM_LEADER, …)
@export var role: RankGrades.Role = RankGrades.Role.SOLDIER
@export var weapon: WeaponSpec      # drag a WeaponSpec resource here
@export var is_key_role: bool = false  # for UI badges / AI priority
@export_storage var weapon_resource_path: String = ""


func resolve_weapon() -> WeaponSpec:
	if weapon != null:
		return weapon
	if weapon_resource_path.is_empty():
		return null
	if not ResourceLoader.exists(weapon_resource_path):
		push_warning("Saved weapon resource does not exist: %s" % weapon_resource_path)
		return null
	var spec: WeaponSpec = ResourceLoader.load(weapon_resource_path) as WeaponSpec
	if spec == null:
		push_warning("Saved weapon resource is not a WeaponSpec: %s" % weapon_resource_path)
	return spec


func copy_runtime() -> SoldierLoadout:
	var result: SoldierLoadout = SoldierLoadout.new()

	result.nickname = nickname
	result.rank_grade = rank_grade
	result.role = role
	result.weapon = weapon
	result.weapon_resource_path = weapon_resource_path
	result.is_key_role = is_key_role

	return result
