# SoldierSaveData.gd
extends Resource
class_name SoldierSaveData

@export var soldier_id: int = -1
@export var loadout_resource_path: String = ""

@export var soldier_name: String = ""

@export var is_alive: bool = true

@export var experience: float = 0.0
@export var fatigue: float = 0.0
@export var wounded: bool = false

@export var base_attack: float = 1.0
@export var base_defense: float = 1.0
