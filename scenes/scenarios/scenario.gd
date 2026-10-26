extends Node2D
class_name Scenario

enum AIStatus { OFF, ON }
enum AIMode { ATTACK, DEFEND }

@onready var units: Node2D = $Units
@onready var axis_objectives_tile_map_layer: HexagonTileMapLayer = $Objectives/AxisObjectivesTileMapLayer
@onready var allied_objectives_tile_map_layer: HexagonTileMapLayer = $Objectives/AlliedObjectivesTileMapLayer

@export var scenario_name: String = "scenario"
@export var scenario_id: String = ""
@export var campaign_id: String = ""
@export var campaign_mission: int = 0
@export var scenario_description: String = ""
@export var duration_s: float = 180.0
@export var use_authored_duration: bool = false
## Assess the final result once all player capture objectives are secured and no opponent remains.
@export var end_when_objectives_secured_and_enemy_gone: bool = false
@export var released: bool = false
@export var previous_scenario: Scenario
@export var offboard_batteries: Array[OffboardBattery] = []

#@export var attacker_team: Globals.Team = Globals.Team.ALLIES
#@export var defender_team: Globals.Team = Globals.Team.AXIS

@export var player_team: Globals.Team = Globals.Team.AXIS

@export_group("Objectives")
@export var victory_conditions: Array[VictoryCondition] = []

@export_group("AI")
## Explicit strategic links. Without a policy, the director uses ordinary victory priorities.
@export var ai_fallback_policies: Array[HoldToExitFallbackPolicy] = []
## Explicit escape missions take precedence over tactical posture and enemy denial duties.
@export var ai_escape_policies: Array[EscapeMissionPolicy] = []
@export_subgroup("Axis", "axis_ai_")
## Controls automatic Axis orders independently of the selected player side.
@export_enum("OFF", "ON") var axis_ai_status: int = AIStatus.OFF
## Tactical posture. Strategic destinations come from both sides' victory conditions.
@export_enum("ATTACK", "DEFEND") var axis_ai_mode: int = AIMode.DEFEND
@export_subgroup("Allies", "allies_ai_")
## Controls automatic Allied orders independently of the selected player side.
@export_enum("OFF", "ON") var allies_ai_status: int = AIStatus.ON
## Tactical posture. Strategic destinations come from both sides' victory conditions.
@export_enum("ATTACK", "DEFEND") var allies_ai_mode: int = AIMode.DEFEND
@export_group("")

var start_hex: Dictionary[Globals.Team, Vector2i] = {
	Globals.Team.AXIS: Vector2i.ZERO,
	Globals.Team.ALLIES: Vector2i.ZERO
	}


func is_ai_enabled(team: Globals.Team) -> bool:
	if team == Globals.Team.AXIS:
		return axis_ai_status == AIStatus.ON
	return allies_ai_status == AIStatus.ON


func get_save_id() -> String:
	if not scenario_id.is_empty():
		return scenario_id
	return scenario_name.to_lower().replace(" ", "_")


func get_ai_mode(team: Globals.Team) -> PositionProfile.Mode:
	var mode: int = axis_ai_mode
	if team == Globals.Team.ALLIES:
		mode = allies_ai_mode
	if mode == AIMode.ATTACK:
		return PositionProfile.Mode.ASSAULT
	return PositionProfile.Mode.DEFEND


#func get_objectives(team: Globals.Team) -> Array[Node]:
	#match team:
		#Globals.Team.AXIS:
			#return objective_axis.get_children()
		#Globals.Team.ALLIES:
			#return objective_allies.get_children()
		#_:
			#return objective_axis.get_children()


func get_objectives_layer(team: Globals.Team) -> HexagonTileMapLayer:
	match team:
		Globals.Team.AXIS:
			return axis_objectives_tile_map_layer
		Globals.Team.ALLIES:
			return allied_objectives_tile_map_layer
		_:
			return axis_objectives_tile_map_layer



func get_objectives() -> Dictionary[Globals.Team, ObjectivesCollection]:
	var objectives: Dictionary[Globals.Team, ObjectivesCollection]
	objectives[Globals.Team.AXIS] = ObjectivesCollection.new()
	objectives[Globals.Team.ALLIES] = ObjectivesCollection.new()
	
	
	var axis_used_cells: Array[Vector2i] = axis_objectives_tile_map_layer.get_used_cells()
	for cell: Vector2i in axis_used_cells:
		var tile_data: TileData = axis_objectives_tile_map_layer.get_cell_tile_data(cell)
		if tile_data == null:
			continue
		
		if not tile_data.has_custom_data("objective_id"):
			continue
		
		var objective: ObjectiveDefinition = ObjectiveDefinition.new()
		objective.objective_id = tile_data.get_custom_data("objective_id")
		objective.team = tile_data.get_custom_data("team")
		objective.display_name = tile_data.get_custom_data("display_name")
		objective.hex = cell
		objective.cube = axis_objectives_tile_map_layer.map_to_cube(cell)
		objective.position = axis_objectives_tile_map_layer.map_to_local(cell)
		
		if objective.objective_id == 4:
			start_hex[Globals.Team.AXIS] = cell
			axis_objectives_tile_map_layer.set_cell(cell, -1, Vector2i(0, 0))  # Clear hex
		else:
			objectives[objective.team].objectives.append(objective)
	
	var allied_used_cells: Array[Vector2i] = allied_objectives_tile_map_layer.get_used_cells()
	for cell: Vector2i in allied_used_cells:
		var tile_data: TileData = allied_objectives_tile_map_layer.get_cell_tile_data(cell)
		if tile_data == null:
			continue
		
		if not tile_data.has_custom_data("objective_id"):
			continue
		
		var objective: ObjectiveDefinition = ObjectiveDefinition.new()
		objective.objective_id = tile_data.get_custom_data("objective_id")
		objective.team = tile_data.get_custom_data("team")
		objective.display_name = tile_data.get_custom_data("display_name")
		objective.hex = cell
		objective.cube = allied_objectives_tile_map_layer.map_to_cube(cell)
		objective.position = allied_objectives_tile_map_layer.map_to_local(cell)
		
		if objective.objective_id == 4:
			start_hex[Globals.Team.ALLIES] = cell
			allied_objectives_tile_map_layer.set_cell(cell, -1, Vector2i(0, 0))  # Clear hex
		else:
			objectives[objective.team].objectives.append(objective)
	
	return objectives


func get_victory_conditions() -> Dictionary[Globals.Team, VictoryConditionCollection]:
	var victory_condition_collection: Dictionary[Globals.Team, VictoryConditionCollection]
	victory_condition_collection[Globals.Team.AXIS] = VictoryConditionCollection.new()
	victory_condition_collection[Globals.Team.ALLIES] = VictoryConditionCollection.new()
	
	for victory_condition: VictoryCondition in victory_conditions:
		victory_condition_collection[victory_condition.team].victory_conditions.append(victory_condition)
	return victory_condition_collection

func get_units() -> Array[Node]:
	return units.get_children()


func get_reinforcements() -> Array[ReinforcementDefinition]:
	var result: Array[ReinforcementDefinition] = []
	var branch: Node = get_node_or_null("Reinforcements")
	if branch != null:
		for child: Node in branch.get_children():
			if child is ReinforcementDefinition:
				result.append(child as ReinforcementDefinition)
	return result
