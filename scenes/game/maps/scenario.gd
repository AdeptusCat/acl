extends Node2D
class_name Scenario

@onready var units: Node2D = $Units
@onready var objective_axis: Node2D = $Objectives/Axis
@onready var objective_allies: Node2D = $Objectives/Allies
@onready var objectives_tile_map_layer: HexagonTileMapLayer = $Objectives/ObjectivesTileMapLayer

@export var scenario_name: String = "scenario"
@export var duration_s: float = 1800.0

@export var attacker_team: Globals.Team = Globals.Team.ALLIES
@export var defender_team: Globals.Team = Globals.Team.AXIS

@export var victory_conditions: Array[VictoryCondition] = []


func _ready() -> void:
	print(get_objectives(0)[0].display_name)
	
		

#func get_objectives(team: Globals.Team) -> Array[Node]:
	#match team:
		#Globals.Team.AXIS:
			#return objective_axis.get_children()
		#Globals.Team.ALLIES:
			#return objective_allies.get_children()
		#_:
			#return objective_axis.get_children()


func get_objectives_layer() -> HexagonTileMapLayer:
	return objectives_tile_map_layer


func get_objectives(team: Globals.Team) -> Array[ObjectiveDefinition]:
	var objectives: Array[ObjectiveDefinition]
	var used_cells: Array[Vector2i] = objectives_tile_map_layer.get_used_cells()
	for cell in used_cells:
		var tile_data: TileData = objectives_tile_map_layer.get_cell_tile_data(cell)
		if tile_data == null:
			continue
		
		if not tile_data.has_custom_data("objective_id"):
			continue
		
		if tile_data.get_custom_data("team") == team:
			var objective: ObjectiveDefinition = ObjectiveDefinition.new()
			objective.objective_id = tile_data.get_custom_data("objective_id")
			objective.team = tile_data.get_custom_data("team")
			objective.display_name = tile_data.get_custom_data("display_name")
			objective.hex = cell
			objective.cube = objectives_tile_map_layer.map_to_cube(cell)
			objective.position = objectives_tile_map_layer.map_to_local(cell)
			
			objectives.append(objective)
	return objectives

func get_units() -> Array[Node]:
	return units.get_children()
