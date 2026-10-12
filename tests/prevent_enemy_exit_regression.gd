extends Node

var checks: int = 0
var failures: int = 0
var controller: Node2D
var friendly: Unit
var enemies: Array[Unit] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("DefaultMap")
	var scenario: Scenario = map.get_scenario(0)
	scenario.axis_ai_status = Scenario.AIStatus.OFF
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	controller = world.game_controller
	_freeze(main)
	friendly = Globals.get_units_for_team(Globals.Team.AXIS)[0]
	enemies = Globals.get_units_for_team(Globals.Team.ALLIES)
	_check(enemies.size() >= 2, "Fixture supplies distinct enemy squads")
	var original_objectives: Dictionary[Globals.Team, ObjectivesCollection] = Globals.objectives
	var original_conditions: Dictionary[Globals.Team, VictoryConditionCollection] = Globals.victory_conditions
	Globals.objectives = {
		Globals.Team.AXIS: _objectives(Globals.Team.AXIS, Vector2i(10, 10), Vector2i(10, 11)),
		Globals.Team.ALLIES: _objectives(Globals.Team.ALLIES, Vector2i(15, 15), Vector2i(15, 14)),
	}
	_test_authoring()
	_test_tracking()
	_test_entry_event()
	_test_evaluation()
	_test_goals()
	Globals.objectives = original_objectives
	Globals.victory_conditions = original_conditions
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Enemy exit prevention checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _objectives(team: Globals.Team, exit_hex: Vector2i, alternate_hex: Vector2i) -> ObjectivesCollection:
	var collection: ObjectivesCollection = ObjectivesCollection.new()
	for id: int in [0, 1]:
		var objective: ObjectiveDefinition = ObjectiveDefinition.new()
		objective.team = team
		objective.objective_id = id
		objective.hex = exit_hex
		if id == 1:
			objective.hex = alternate_hex
		collection.objectives.append(objective)
	return collection


func _set_conditions(conditions: Array[VictoryCondition]) -> void:
	Globals.victory_conditions = {
		Globals.Team.AXIS: VictoryConditionCollection.new(),
		Globals.Team.ALLIES: VictoryConditionCollection.new(),
	}
	for condition: VictoryCondition in conditions:
		Globals.victory_conditions[condition.team].victory_conditions.append(condition)
	controller.set_victory_conditions()


func _test_authoring() -> void:
	var condition: PreventEnemyExitCondition = PreventEnemyExitCondition.new()
	_check(condition.test_at_scenario_end and condition.max_allowed_enemy_exits == 0 and condition.objective_id == PreventEnemyExitCondition.ObjectiveId.EXIT, "New prevention conditions default to zero allowed exits and deadline evaluation")
	_check(condition.get_description().contains("Prevent any enemy unit"), "Zero-exit description explains the denial objective")
	condition.max_allowed_enemy_exits = 2
	_check(condition.get_description().contains("no more than 2"), "Description includes a nonzero allowed-exit count")
	var exported: bool = false
	for property: Dictionary in condition.get_property_list():
		if property["name"] == "max_allowed_enemy_exits":
			exported = (property["usage"] & PROPERTY_USAGE_EDITOR) != 0 and (property["usage"] & PROPERTY_USAGE_STORAGE) != 0
	_check(exported, "Allowed exits are editable and stored by the Godot Inspector")
	var source: Scenario = load("res://scenes/scenarios/scenario.tscn").instantiate()
	condition.team = Globals.Team.ALLIES
	condition.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	condition.objective_id = PreventEnemyExitCondition.ObjectiveId.A
	source.victory_conditions = [condition]
	var packed: PackedScene = PackedScene.new()
	_check(packed.pack(source) == OK, "A Scenario can store the new condition in its victory-condition array")
	var restored: Scenario = packed.instantiate()
	var copy: PreventEnemyExitCondition = restored.victory_conditions[0] as PreventEnemyExitCondition
	_check(copy != null and copy.team == Globals.Team.ALLIES and copy.max_allowed_enemy_exits == 2 and copy.outcome_level == VictoryCondition.OutcomeLevel.MINOR and copy.test_at_scenario_end, "Scene serialization preserves ownership, threshold, outcome, and deadline evaluation")
	restored.free()
	source.free()
	_check(ResourceSaver.save(condition, "user://prevent_enemy_exit_fixture.tres") == OK, "Prevention condition can be saved as a standalone Resource")
	var loaded: PreventEnemyExitCondition = ResourceLoader.load("user://prevent_enemy_exit_fixture.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as PreventEnemyExitCondition
	_check(loaded != null and loaded.test_at_scenario_end and loaded.max_allowed_enemy_exits == 2 and loaded.objective_id == PreventEnemyExitCondition.ObjectiveId.A, "Resource reload preserves inherited and specialized settings")


func _test_tracking() -> void:
	var condition: PreventEnemyExitCondition = PreventEnemyExitCondition.new()
	condition.team = Globals.Team.AXIS
	_set_conditions([condition])
	_check(condition.state.exit_hexes == [Vector2i(15, 15)], "Axis prevention binds Allied exit markers rather than Axis markers")
	_check(Globals.victory_conditions[Globals.Team.ALLIES].victory_conditions.is_empty(), "Prevention tracking works without an enemy exit victory condition")
	var progress: VictoryConditionProgress = VictoryConditionProgress.read(condition)
	_check(progress.valid and progress.kind == VictoryConditionProgress.Kind.PREVENT_EXIT and progress.objective_team == Globals.Team.ALLIES, "Progress identifies the defending side and the opposite marker owner")
	_check(condition.is_condition_met() and condition.state.units_exited.is_empty(), "Reading initial progress does not register exits")
	condition.record_unit_entry(friendly, Vector2i(15, 15))
	condition.record_unit_entry(enemies[0], Vector2i(10, 10))
	_check(condition.state.units_exited.is_empty(), "Friendly units and the opponent's presence on our own exit do not count")
	var surrendered: bool = enemies[0].surrendered
	enemies[0].surrendered = true
	condition.record_unit_entry(enemies[0], Vector2i(15, 15))
	enemies[0].surrendered = surrendered
	var alive: bool = enemies[0].alive
	enemies[0].alive = false
	condition.record_unit_entry(enemies[0], Vector2i(15, 15))
	enemies[0].alive = alive
	_check(condition.state.units_exited.is_empty(), "Dead and surrendered units cannot register a new exit")
	condition.record_unit_entry(enemies[0], Vector2i(15, 15))
	condition.record_unit_entry(enemies[0], Vector2i(15, 15))
	_check(condition.state.units_exited.size() == 1 and not condition.is_condition_met(), "One distinct escaped squad fails zero-exit prevention; repeats count once")
	enemies[0].alive = false
	_check(not condition.is_condition_met(), "Destroying an already escaped squad cannot undo the recorded failure")
	enemies[0].alive = alive
	condition.max_allowed_enemy_exits = 1
	_check(condition.is_condition_met(), "Exactly the configured allowed number of exits still satisfies prevention")
	condition.record_unit_entry(enemies[1], Vector2i(15, 15))
	_check(condition.state.units_exited.size() == 2 and not condition.is_condition_met(), "The first exit above the configured allowance fails prevention")
	_set_conditions([condition])
	_check(condition.state.units_exited.is_empty(), "New match initialization resets the exit ledger")
	var original: Vector2i = enemies[0].current_hex
	enemies[0].current_hex = Vector2i(15, 15)
	condition.advance_time(0.0)
	_check(condition.state.units_exited.is_empty(), "An inactive clock does not advance the ledger")
	condition.advance_time(0.1)
	condition.advance_time(0.1)
	enemies[0].current_hex = original
	_check(condition.state.units_exited.size() == 1, "Clock updates record exits independently and without duplicate counting")
	condition.team = Globals.Team.ALLIES
	condition.objective_id = PreventEnemyExitCondition.ObjectiveId.A
	_set_conditions([condition])
	_check(condition.state.exit_hexes == [Vector2i(10, 11)], "Allied prevention can select an alternate Axis marker ID")
	Globals.objectives[Globals.Team.AXIS].objectives.clear()
	_set_conditions([condition])
	_check(not condition.is_condition_met() and not VictoryConditionProgress.read(condition).valid, "Missing matching enemy markers cannot award victory")
	Globals.objectives[Globals.Team.AXIS] = _objectives(Globals.Team.AXIS, Vector2i(10, 10), Vector2i(10, 11))


func _test_entry_event() -> void:
	var condition: PreventEnemyExitCondition = PreventEnemyExitCondition.new()
	condition.team = Globals.Team.AXIS
	_set_conditions([condition])
	var enemy: Unit = enemies[0]
	var original: Vector2i = enemy.current_hex
	var started: bool = Globals.game_started
	var ended: bool = controller.end_game_handled
	Globals.game_started = true
	controller.end_game_handled = false
	enemy.current_hex = Vector2i(15, 15)
	controller._on_unit_entered_hex(enemy, enemy.current_hex)
	enemy.current_hex = original
	_check(condition.state.units_exited.has(enemy), "The actual match entry event records an exit before the next clock tick")
	condition.advance_time(0.1)
	_check(condition.state.units_exited.size() == 1, "Clock polling preserves an exit after the squad has left the marker")
	Globals.game_started = started
	controller.end_game_handled = ended


func _test_evaluation() -> void:
	var condition: PreventEnemyExitCondition = PreventEnemyExitCondition.new()
	condition.team = Globals.Team.AXIS
	_set_conditions([condition])
	var host: Node2D = load("res://scenes/game/match_controller.gd").new()
	var winners: Array[int] = []
	host.show_winner.connect(func(winner: int, _level: VictoryCondition.OutcomeLevel, _timeout: bool) -> void:
		winners.append(winner)
	)
	host.time_left_seconds = 30.0
	host._on_win_condition_timer_timeout()
	_check(winners.is_empty() and not host.end_game_handled, "An initially empty ledger cannot produce an immediate victory")
	host.time_left_seconds = 0.0
	host._on_win_condition_timer_timeout()
	_check(winners == [Globals.Team.AXIS], "Successful prevention awards the owning side victory at the deadline")
	condition.record_unit_entry(enemies[0], Vector2i(15, 15))
	host.end_game_handled = false
	winners.clear()
	host._on_win_condition_timer_timeout()
	_check(winners == [-1], "Failed prevention cannot award its owner victory or invent an enemy victory condition")
	host.free()


func _test_goals() -> void:
	var condition: PreventEnemyExitCondition = PreventEnemyExitCondition.new()
	condition.team = Globals.Team.AXIS
	_set_conditions([condition])
	var planner: PlatoonAI = controller.platoon_ai
	var goals: ScenarioGoalDirector = ScenarioGoalDirector.new()
	goals.configure(Globals.Team.AXIS, [condition], PositionProfile.Mode.DEFEND)
	var order: MissionOrder = goals.initial_order(planner, MissionOrder.new(), 1200.0)
	_check(goals.primary != null and goals.primary.kind == ScenarioGoalTask.Kind.BLOCK_EXIT and order.objective_hex == Vector2i(15, 15), "An AI's prevention victory condition creates an enemy-exit blocking duty")
	var alternative: ObjectiveDefinition = ObjectiveDefinition.new()
	alternative.team = Globals.Team.ALLIES
	alternative.hex = Vector2i(25, 15)
	Globals.objectives[Globals.Team.ALLIES].objectives.append(alternative)
	_set_conditions([condition])
	goals.assignments[friendly] = goals.primary
	var snapshot: InfluenceSnapshot = planner.influence_map_controller.snapshot
	var observed: InfluenceSnapshot = InfluenceSnapshot.new()
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = enemies[0]
	contact.hex = alternative.hex
	contact.observed = true
	observed.defensive_contacts[Globals.Team.AXIS] = [contact]
	planner.influence_map_controller.snapshot = observed
	order = goals.initial_order(planner, MissionOrder.new(), 1200.0)
	_check(order.objective_hex == alternative.hex, "A materially threatened exit supersedes the nearer quiet exit while small changes retain commitments")
	planner.influence_map_controller.snapshot = snapshot
	Globals.objectives[Globals.Team.ALLIES].objectives.erase(alternative)
	_set_conditions([condition])
	condition.record_unit_entry(enemies[0], Vector2i(15, 15))
	goals.initial_order(planner, MissionOrder.new(), 1200.0)
	_check(goals.tasks.is_empty() and goals.primary == null, "The director does not keep pursuing an irreversibly failed prevention victory")
	condition.team = Globals.Team.ALLIES
	condition.max_allowed_enemy_exits = 1
	_set_conditions([condition])
	goals.configure(Globals.Team.AXIS, [condition], PositionProfile.Mode.ASSAULT)
	order = goals.initial_order(planner, MissionOrder.new(), 1200.0)
	_check(goals.primary != null and goals.primary.kind == ScenarioGoalTask.Kind.EXIT and order.objective_hex == Vector2i(10, 10), "Denying the opponent's prevention condition targets our own exits")
	_check(goals.primary.required_units == 2 and goals.primary.exit_capacity() == 2 and ScenarioGoalTask.exit_state_for(goals.primary.condition) == condition.state, "Counter-exit duties use the correct distinct-unit quota and ledger")
	condition.record_unit_entry(friendly, Vector2i(10, 10))
	goals.initial_order(planner, MissionOrder.new(), 1200.0)
	_check(goals.primary.required_units == 1, "Counter-exit duties subtract squads already recorded")
	var second: Unit = Globals.get_units_for_team(Globals.Team.AXIS)[1]
	condition.record_unit_entry(second, Vector2i(10, 10))
	goals.initial_order(planner, MissionOrder.new(), 1200.0)
	_check(goals.tasks.is_empty(), "Once prevention is denied, the director releases counter-exit duties")


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		(node as Timer).stop()
	for child: Node in node.get_children():
		_freeze(child)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
