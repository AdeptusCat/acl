# Soldier.gd (plain class)
class_name Soldier
extends RefCounted


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

func _init(_id: int, _name: String, _rank_grade: int, _role: int, _weapon: WeaponSpec) -> void:
	id = _id
	name = _name
	rank_grade = _rank_grade
	role = _role
	weapon = _weapon
	rounds_in_mag = weapon.mag_capacity
