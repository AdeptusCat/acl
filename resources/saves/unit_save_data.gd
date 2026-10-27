# UnitSaveData.gd
extends Resource
class_name UnitSaveData

@export var map_unit_id: String = ""
@export var unit_id: int = -1
@export var unit_scene_path: String = ""
@export var team: Globals.Team

@export var soldiers: Array[SoldierLoadout] = []
@export var squad_loadout: SquadLoadoutSpec
@export var casualty_records: Array[CasualtyRecord] = []
@export var exited: bool = false
@export var exit_record: UnitExitRecord

@export var stress_fast: float = 0.0
@export var stress_slow: float = 0.0
@export var cohesion: float = 1.0
@export var state: int = 0
@export var movement_stance: int = 0
@export var watch_direction: Vector2 = Vector2.ZERO
@export var watch_width: int = Unit.WatchWidth.NORMAL
@export var fire_discipline: int = Unit.FireDiscipline.FIRE_AT_WILL
