extends Resource
class_name MatchSaveData

@export var save_version: int = 5

@export var reinforcement_elapsed_seconds: float = 0.0
@export var reinforcement_states: Array[ReinforcementState] = []

@export var match_id: String = ""
@export var scenario_id: String = ""
@export var battle_id: String = ""
@export var casualty_records: Array[CasualtyRecord] = []
@export var exit_records: Array[UnitExitRecord] = []
@export var exited_units: Array[UnitSaveData] = []

@export var winner_team: int = -1
@export var outcome_level: VictoryCondition.OutcomeLevel = VictoryCondition.OutcomeLevel.MINOR
@export var timeout: bool = false

@export var player_team: Globals.Team
@export var player_units: Array[UnitSaveData] = []

# Completion survives subsequent results without replacing the latest battle data.
@export var completed_player_teams: Array[Globals.Team] = []


func has_player_victory(team: Globals.Team) -> bool:
	# Existing saves have no completion metadata, so their current victory still counts.
	return completed_player_teams.has(team) or (player_team == team and winner_team == team)


func preserve_player_victories(previous: MatchSaveData) -> void:
	if previous != null and previous.scenario_id == scenario_id:
		for team: Globals.Team in Globals.Team.values():
			if previous.has_player_victory(team) and not completed_player_teams.has(team):
				completed_player_teams.append(team)
	if winner_team == player_team and not completed_player_teams.has(player_team):
		completed_player_teams.append(player_team)
