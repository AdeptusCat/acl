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
				var condition when condition is PreventEnemyExitCondition:
					var prevention: PreventEnemyExitCondition = condition as PreventEnemyExitCondition
					prevention.state = ExitUnitsState.new()
					var enemy_team: Globals.Team = Globals.get_enemy_team(prevention.team)
					var objectives: ObjectivesCollection = Globals.objectives[enemy_team]
					for objective: ObjectiveDefinition in objectives.objectives:
						if objective.objective_id == prevention.objective_id:
							prevention.state.exit_hexes.append(objective.hex)
				var condition when condition is DestroyUnitsCondition:
					victory_condition = victory_condition as DestroyUnitsCondition
					victory_condition.state = DestroyUnitsState.new()
					pass


static func can_finish_after_enemy_departure() -> bool:
	var scenario: Scenario = Globals.scenario_chosen
	if not is_instance_valid(scenario) or not scenario.end_when_objectives_secured_and_enemy_gone:
		return false
	for unit: Unit in Globals.get_units_for_team(Globals.get_enemy_team(Globals.team_player)):
		if unit.is_active() and not unit.surrendered:
			return false
	var collection: VictoryConditionCollection = Globals.victory_conditions.get(Globals.team_player)
	if collection == null:
		return false
	var has_capture_objective: bool = false
	for condition: VictoryCondition in collection.victory_conditions:
		if condition is OccupyObjectiveCondition:
			has_capture_objective = true
			if not condition.is_condition_met():
				return false
	return has_capture_objective


static func can_finish_after_force_defeat() -> bool:
	return not _defeated_teams().is_empty()


static func _defeated_teams() -> Array[Globals.Team]:
	var result: Array[Globals.Team] = []
	if not is_instance_valid(Globals.scenario_chosen):
		return result
	var represented: Dictionary[Globals.Team, bool] = {Globals.Team.AXIS: false, Globals.Team.ALLIES: false}
	var surviving: Dictionary[Globals.Team, bool] = {Globals.Team.AXIS: false, Globals.Team.ALLIES: false}
	var defeated: Dictionary[Globals.Team, bool] = {Globals.Team.AXIS: false, Globals.Team.ALLIES: false}
	var roster: Array[Unit] = Globals.get_units()
	roster.append_array(Globals.get_exited_units())
	for node: Node in Globals.get_tree().get_nodes_in_group("dead_units"):
		if node is Unit:
			roster.append(node as Unit)
	for unit: Unit in roster:
		represented[unit.team] = true
		# Earlier exits remain credited but cannot keep a destroyed rear guard's match running.
		if unit.exited:
			continue
		if unit.alive and not unit.surrendered:
			surviving[unit.team] = true
		else:
			defeated[unit.team] = true
	if not represented[Globals.Team.AXIS] or not represented[Globals.Team.ALLIES]:
		return result
	for team: Globals.Team in represented:
		if defeated[team] and not surviving[team]:
			result.append(team)
	return result


static func _occupation_pending_only(conditions: Array[VictoryCondition]) -> bool:
	var has_occupation: bool = false
	for condition: VictoryCondition in conditions:
		if condition is OccupyObjectiveCondition:
			has_occupation = true
			break
	if not has_occupation:
		return false
	var pending: bool = false
	for condition: VictoryCondition in conditions:
		if condition.is_condition_met():
			continue
		if not condition is OccupyObjectiveCondition:
			return false
		var occupation: OccupyObjectiveCondition = condition as OccupyObjectiveCondition
		if not VictoryConditionProgress.read(occupation).valid:
			return false
		for hex: Vector2i in occupation.state.hexes:
			if occupation.state.required_times_reached_s.get(hex, 0.0) <= 0.0:
				return false
		pending = true
	return pending


static func _continue_overtime(controller: Node2D) -> bool:
	if not controller.overtime_active:
		# Only victory packages already being secured at the deadline qualify.
		for team: Globals.Team in Globals.victory_conditions:
			for level: VictoryCondition.OutcomeLevel in [VictoryCondition.OutcomeLevel.MAJOR, VictoryCondition.OutcomeLevel.MINOR]:
				var package: VictoryConditionCollection = VictoryConditionCollection.new()
				for condition: VictoryCondition in Globals.victory_conditions[team].victory_conditions:
					if condition.outcome_level == level:
						package.victory_conditions.append(condition)
				if _occupation_pending_only(package.victory_conditions):
					controller.overtime_packages.append(package)
	else:
		for package: VictoryConditionCollection in controller.overtime_packages.duplicate():
			var first: VictoryCondition = package.victory_conditions[0]
			if VictoryConditionProgress.outcome_complete(package.victory_conditions, first.team, first.outcome_level, true):
				controller.overtime_packages.clear()
				return false
			if not _occupation_pending_only(package.victory_conditions):
				controller.overtime_packages.erase(package)
	return not controller.overtime_packages.is_empty()


static func on_win_condition_timer_timeout(controller: Node2D) -> void:
	if controller.end_game_handled:
		return
	var defeated_teams: Array[Globals.Team] = _defeated_teams()
	var force_defeated: bool = not defeated_teams.is_empty()
	if force_defeated:
		var capture_all: bool = controller.timer_running and controller.time_left_seconds > 0.0
		controller.overtime_active = false
		controller.overtime_packages.clear()
		for collection: VictoryConditionCollection in Globals.victory_conditions.values():
			for condition: VictoryCondition in collection.victory_conditions:
				if condition is OccupyObjectiveCondition:
					var occupation: OccupyObjectiveCondition = condition as OccupyObjectiveCondition
					if defeated_teams.has(Globals.get_enemy_team(occupation.team)):
						occupation.complete_after_enemy_defeat(capture_all and not defeated_teams.has(occupation.team))
					else:
						occupation.refresh_control()
	elif controller.time_left_seconds <= 0.0:
		controller.overtime_active = _continue_overtime(controller)
		if controller.overtime_active:
			controller.timer_running = true
			return
	var at_end: bool = force_defeated or controller.time_left_seconds <= 0.0 or can_finish_after_enemy_departure()
	
	var major_victory_conditions_met: Dictionary[Globals.Team, bool] = {
		Globals.Team.AXIS: false,
		Globals.Team.ALLIES: false,
	}
	
	var minor_victory_conditions_met: Dictionary[Globals.Team, bool] = {
		Globals.Team.AXIS: false,
		Globals.Team.ALLIES: false,
	}
	
	var conditions: Array[VictoryCondition] = []
	for team: int in Globals.victory_conditions:
		for victory_condition: VictoryCondition in Globals.victory_conditions[team].victory_conditions:
			conditions.append(victory_condition)
	for team: Globals.Team in major_victory_conditions_met:
		major_victory_conditions_met[team] = VictoryConditionProgress.outcome_complete(conditions, team, VictoryCondition.OutcomeLevel.MAJOR, at_end)
		minor_victory_conditions_met[team] = VictoryConditionProgress.outcome_complete(conditions, team, VictoryCondition.OutcomeLevel.MINOR, at_end)
	
	if major_victory_conditions_met[Globals.Team.AXIS] and major_victory_conditions_met[Globals.Team.ALLIES]:
		# Its a Draw
		if at_end:
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
		if at_end:
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
	
	if at_end:
		controller.show_winner.emit(-1, VictoryCondition.OutcomeLevel.MAJOR, controller.time_left_seconds <= 0.0)
		controller.timer_running = false
		controller.end_game_handled = true
