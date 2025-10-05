# Soldier.gd (plain class)
class_name Soldier
extends RefCounted

enum Role { RIFLEMAN, GUNNER, LOADER, RADIO, MEDIC, LEADER }

var id: int
var name: String
var rank_grade: RankGrades.Grade
var role: Role
var weapon: WeaponSpec
var is_alive: bool = true

# ammo & readiness
var rounds_in_mag: int
var jammed: bool = false
var next_ready_s: float = 0.0       # simulation time when he can act again

# cached multipliers (state/leadership may change these each tick)
var rof_mult: float = 1.0
var acc_mult: float = 1.0

func _init(_id: int, _name: String, _rank_grade: int, _role: int, _weapon: WeaponSpec) -> void:
	id = _id
	name = _name
	rank_grade = _rank_grade
	role = _role
	weapon = _weapon
	rounds_in_mag = weapon.mag_capacity
