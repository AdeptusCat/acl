extends Resource
class_name MatchSaveData

@export var save_version: int = 2

@export var match_id: String = ""
@export var scenario_id: String = ""
@export var battle_id: String = ""
@export var casualty_records: Array[CasualtyRecord] = []

@export var winner_team: int = -1
@export var outcome_level: VictoryCondition.OutcomeLevel = VictoryCondition.OutcomeLevel.MINOR
@export var timeout: bool = false

@export var player_team: Globals.Team
@export var player_units: Array[UnitSaveData] = []
