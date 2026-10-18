# SoldierSaveData.gd
extends Resource
class_name SoldierSaveData

@export var soldier_id: int = -1
@export var soldier_name: String = ""
@export var rank_grade: RankGrades.Grade
@export var role: RankGrades.Role

@export var weapon_resource_path: String = ""

@export var is_alive: bool = true
@export var rounds_in_mag: int = 0
@export var jammed: bool = false

@export var base_attack: float = 1.0
@export var base_defense: float = 1.0
