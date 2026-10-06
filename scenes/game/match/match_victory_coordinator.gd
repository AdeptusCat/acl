extends RefCounted
class_name MatchVictoryCoordinator

# Synchronous MatchVictoryCoordinator operations; state and scene identity stay on the caller.


static func set_objective_layer(controller: Node2D, team: Globals.Team, tilemap: TileMapLayer) -> void:
	match team:
		Globals.Team.AXIS:
			controller.axis_objective_tilemap = tilemap
		Globals.Team.ALLIES:
			controller.allies_objective_tilemap = tilemap


static func set_objective_cells(controller: Node2D, player_team: Globals.Team) -> void:
	Globals.objective_hexes.clear()
	var player_objective_tilemap: TileMapLayer
	var ai_objective_tilemap: TileMapLayer
	var ai_team: Globals.Team
	if player_team == Globals.Team.AXIS:
		ai_team = Globals.Team.ALLIES
		ai_objective_tilemap = controller.allies_objective_tilemap
		player_objective_tilemap = controller.axis_objective_tilemap
	else:
		ai_team = Globals.Team.AXIS
		ai_objective_tilemap = controller.axis_objective_tilemap
		player_objective_tilemap = controller.allies_objective_tilemap
	player_objective_tilemap.show()
	ai_objective_tilemap.hide()
	#if player_team == Globals.Team.AXIS:
		#match Globals.game_mode:
			#Globals.GameMode.DEFEND:
				#player_objective_tilemap = allies_objective_tilemap
				#ai_objective_tilemap = allies_objective_tilemap
			#Globals.GameMode.ATTACK:
				#player_objective_tilemap = axis_objective_tilemap
				#ai_objective_tilemap = axis_objective_tilemap
	#if player_team == Globals.Team.ALLIES:
		#match Globals.game_mode:
			#Globals.GameMode.DEFEND:
				#player_objective_tilemap = axis_objective_tilemap
				#ai_objective_tilemap = axis_objective_tilemap
			#Globals.GameMode.ATTACK:
				#player_objective_tilemap = allies_objective_tilemap
				#ai_objective_tilemap = allies_objective_tilemap
	#if player_team == Globals.Team.AXIS:
		#match Globals.game_mode:
			#Globals.GameMode.DEFEND:
				#axis_objective_tilemap.visible = false
				#allies_objective_tilemap.visible = true
			#Globals.GameMode.ATTACK:
				#axis_objective_tilemap.visible = true
				#allies_objective_tilemap.visible = false
	#elif player_team == Globals.Team.ALLIES:
		#match Globals.game_mode:
			#Globals.GameMode.DEFEND:
				#axis_objective_tilemap.visible = true
				#allies_objective_tilemap.visible = false
			#Globals.GameMode.ATTACK:
				#axis_objective_tilemap.visible = false
				#allies_objective_tilemap.visible = true
	
	var cells: Array[Vector2i] = player_objective_tilemap.get_used_cells()
	if cells.size() > 0:
		for cell: Vector2i in cells:
			if not Globals.objective_hexes.has(player_team):
				Globals.objective_hexes[player_team] = []
			Globals.objective_hexes[player_team].append(cell)
	#else:
		#push_error("ObjectiveTileMapLayer has no tiles placed!")
	
	cells = ai_objective_tilemap.get_used_cells() 
	if cells.size() > 0:
		for cell: Vector2i in cells:
			if not Globals.objective_hexes.has(ai_team):
				Globals.objective_hexes[ai_team] = []
			Globals.objective_hexes[ai_team].append(cell)
	#else:
		#push_error("ObjectiveTileMapLayer has no tiles placed!")


static func set_victory_conditions(controller: Node2D) -> void:
	for team: int in Globals.victory_conditions:
		var victory_conditions: VictoryConditionCollection = Globals.victory_conditions[team]
		for victory_condition: VictoryCondition in victory_conditions.victory_conditions:
			match victory_condition:
				var condition when condition is OccupyObjectiveCondition:
					victory_condition = victory_condition as OccupyObjectiveCondition
					victory_condition.state = OccupyObjectiveState.new()
					var objectives: ObjectivesCollection = Globals.objectives[team]
					for objective: ObjectiveDefinition in objectives.objectives:
						if objective.objective_id == victory_condition.objective_id:
							victory_condition.state.hexes.append(objective.hex)
							victory_condition.state.required_times_reached_s[objective.hex] = 0.0
							victory_condition.state.units_in_objectives[objective.hex] = UnitsCollection.new()
							victory_condition.state.victory_conditions_met[objective.hex] = false
							#victory_condition.hex = objective.hex
				var condition when condition is ExitUnitsCondition:
					victory_condition = victory_condition as ExitUnitsCondition
					victory_condition.state = ExitUnitsState.new()
					var objectives: ObjectivesCollection = Globals.objectives[team]
					for objective: ObjectiveDefinition in objectives.objectives:
						if objective.objective_id == victory_condition.objective_id:
							victory_condition.state.exit_hexes.append(objective.hex)
				var condition when condition is DestroyUnitsCondition:
					victory_condition = victory_condition as DestroyUnitsCondition
					victory_condition.state = DestroyUnitsState.new()
					pass


static func on_win_condition_timer_timeout(controller: Node2D) -> void:
	if controller.end_game_handled:
		return
	
	var major_victory_conditions_met: Dictionary[Globals.Team, bool] = {
		Globals.Team.AXIS: false,
		Globals.Team.ALLIES: false,
	}
	
	var minor_victory_conditions_met: Dictionary[Globals.Team, bool] = {
		Globals.Team.AXIS: false,
		Globals.Team.ALLIES: false,
	}
	
	var is_met: bool = false
	for team: int in Globals.victory_conditions:
		for victory_condition: VictoryCondition in Globals.victory_conditions[team].victory_conditions:
			match victory_condition.outcome_level:
				VictoryCondition.OutcomeLevel.MAJOR:
					is_met = victory_condition.is_condition_met()
					major_victory_conditions_met[team] = is_met
					if not is_met:
						break
	
	for team: int in Globals.victory_conditions:
		for victory_condition: VictoryCondition in Globals.victory_conditions[team].victory_conditions:
			match victory_condition.outcome_level:
				VictoryCondition.OutcomeLevel.MINOR:
					is_met = victory_condition.is_condition_met()
					minor_victory_conditions_met[team] = is_met
					if not is_met:
						break
	
	if major_victory_conditions_met[Globals.Team.AXIS] and major_victory_conditions_met[Globals.Team.ALLIES]:
		# Its a Draw
		if controller.time_left_seconds <= 0:
			controller.time_left_seconds = 0
			controller.timer_running = false
			controller.show_winner.emit(-1, VictoryCondition.OutcomeLevel.MAJOR, false)
			controller.end_game_handled = true
			return
	else:
		for team: Globals.Team in major_victory_conditions_met:
			if major_victory_conditions_met[team]:
				controller.show_winner.emit(team, VictoryCondition.OutcomeLevel.MAJOR, false)
				controller.timer_running = false
				controller.end_game_handled = true
				return
	
	if minor_victory_conditions_met[Globals.Team.AXIS] and minor_victory_conditions_met[Globals.Team.ALLIES]:
		# Its a Draw
		if controller.time_left_seconds <= 0:
			controller.time_left_seconds = 0
			controller.timer_running = false
			controller.show_winner.emit(-1, VictoryCondition.OutcomeLevel.MINOR, false)
			controller.end_game_handled = true
			return
	else:
		for team: Globals.Team in minor_victory_conditions_met:
			if minor_victory_conditions_met[team]:
				controller.show_winner.emit(team, VictoryCondition.OutcomeLevel.MINOR, false)
				controller.timer_running = false
				controller.end_game_handled = true
				return
	
	if controller.time_left_seconds <= 0:
		controller.show_winner.emit(-1, VictoryCondition.OutcomeLevel.MAJOR, true)
		controller.timer_running = false
		controller.end_game_handled = true
