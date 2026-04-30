# Soldier.gd (plain class)
class_name Soldier
extends RefCounted


var tasks: Array[SoldierTask]
var target_id: Unit = null
var target_acquired: bool = false

var setup_weapon_task: SoldierTask = SoldierTask.new(SoldierTask.SoldierAction.SETUP_WEAPON)
var aquire_target_task: SoldierTask = SoldierTask.new(SoldierTask.SoldierAction.ACQUIRE_TARGET)
var reload_task: SoldierTask = SoldierTask.new(SoldierTask.SoldierAction.RELOAD)
var fire_weapon_task: SoldierTask = SoldierTask.new(SoldierTask.SoldierAction.FIRE_WEAPON)
var assist_task: SoldierTask = SoldierTask.new(SoldierTask.SoldierAction.ASSIST)
var close_combat_task: SoldierTask = SoldierTask.new(SoldierTask.SoldierAction.CLOSE_COMBAT)

var unit: Unit
var team: Globals.Team

var id: int
var name: String
var rank_grade: RankGrades.Grade
var role: RankGrades.Role
var weapon: WeaponSpec
var is_alive: bool = true

# ammo & readiness
var rounds_in_mag: int
var jammed: bool = false
var next_ready_s: float = 0.0       # simulation time when he can act again
var next_ready_delta_s: float = 0.0
var next_ready_start_s: float = 0.0

# cached multipliers (state/leadership may change these each tick)
var rof_mult: float = 1.0
var acc_mult: float = 1.0

var now_s: float = 0.0
var acquire_start_s: float = 0.0
var acquire_target_s: float = 0.0
var acquire_ready_s: float = 0.0
var last_target_hex: Vector2i = Vector2i(-9999, -9999)

# per-soldier constants (can be exported where your Soldier is created)
var base_acquire_s: float = 0.35      # default settle time for rifles
var aim_jitter_s: float = 2.0        # extra random on each target pick
var cadence_phase_s: float = 0.0      # fixed per-soldier desync in cadence

# close combat
var is_attacker: bool = false
var is_defender: bool = false

var base_attack: float = 1.0
var base_defense: float = 1.0

var weapon_attack: float = 0.0
var weapon_defense: float = 0.0
var weapon_shock: float = 0.0
var attack_interval: float = 0.5

var morale_attack_mult: float = 1.0
var morale_defense_mult: float = 1.0

var location_attack_mult: float = 1.0
var location_defense_mult: float = 1.0

var side_attack_bonus: float = 0.0
var side_defense_bonus: float = 0.0

var cooldown_remaining: float = 0.0
var stunned_time: float = 0.0

func _init(_id: int, _name: String, _rank_grade: RankGrades.Grade, _role: RankGrades.Role, _weapon: WeaponSpec, _unit: Unit, _team: Globals.Team) -> void:
	id = _id
	name = _name
	rank_grade = _rank_grade
	role = _role
	weapon = _weapon
	rounds_in_mag = weapon.mag_capacity
	assist_task.done = true
	unit = _unit
	team = _team
	


func is_weapon_setup_done(delta: float) -> bool:
	if setup_weapon_task.done:
		return true
	if setup_weapon_task.remaining_time_s <= 0:
		setup_weapon_task.done = true
		return true
	setup_weapon_task.remaining_time_s -= delta
	return false


func is_weapon_reload_done(delta: float):
	if reload_task.done:
		return true
	if reload_task.remaining_time_s <= 0:
		reload_task.done = true
		return true
	reload_task.remaining_time_s -= delta
	return false


func is_acquiring_target_done(delta: float):
	if aquire_target_task.done:
		return true
	if aquire_target_task.remaining_time_s <= 0:
		aquire_target_task.done = true
		return true
	aquire_target_task.remaining_time_s -= delta
	return false


func create_save_data() -> SoldierSaveData:
	var data: SoldierSaveData = SoldierSaveData.new()

	#data.id = id
	data.soldier_name = name
	data.rank_grade = rank_grade
	data.role = role

	if weapon != null:
		data.weapon_resource_path = weapon.resource_path
	else:
		data.weapon_resource_path = ""

	data.is_alive = is_alive
	#data.rounds_in_mag = rounds_in_mag
	#data.jammed = jammed

	#data.base_attack = base_attack
	#data.base_defense = base_defense

	return data
