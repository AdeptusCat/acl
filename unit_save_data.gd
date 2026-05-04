# UnitSaveData.gd
extends Resource
class_name UnitSaveData

@export var unit_id: int = -1
@export var unit_scene_path: String = ""
@export var team: Globals.Team

@export var soldiers: Array[SoldierLoadout] = []
@export var squad_loadout: SquadLoadoutSpec

@export var stress_fast: float = 0.0
@export var stress_slow: float = 0.0
@export var cohesion: float = 1.0
@export var state: int = 0
