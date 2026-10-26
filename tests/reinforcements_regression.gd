extends Node

var checks: int = 0
var failures: int = 0


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
	_normalize(scenario)
	var candidates: Array[Unit] = []
	for node: Node in scenario.get_units():
		if node is Unit and (node as Unit).team == Globals.Team.AXIS:
			candidates.append(node as Unit)
	var first: Unit = candidates[0]
	var second: Unit = candidates[1]
	var first_position: Vector2 = first.global_position
	var second_position: Vector2 = second.global_position
	var branch: Node = scenario.get_node_or_null("Reinforcements")
	_check(branch != null, "Mission scenes expose the Reinforcements hierarchy")
	var definition: ReinforcementDefinition = ReinforcementDefinition.new()
	definition.reinforcement_id = "arrival-test"
	definition.unit_ids = [first.map_unit_id, second.map_unit_id]
	definition.expected_seconds = 120.0
	definition.variation_seconds = 30.0
	definition.staggered = true
	definition.stagger_min_seconds = 10.0
	definition.stagger_max_seconds = 10.0
	definition.entry_zone = "North road"
	branch.add_child(definition)
	_test_authoring(scenario, definition, candidates[2])
	_test_distribution(definition)
	var immediate: ReinforcementDefinition = ReinforcementDefinition.new()
	immediate.reinforcement_id = "immediate-test"
	immediate.unit_ids = [candidates[2].map_unit_id]
	immediate.expected_seconds = 0.0
	immediate.variation_seconds = 0.0
	immediate.show_to_player = false
	branch.add_child(immediate)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, Globals.Team.AXIS, Globals.GameMode.ATTACK)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var host: Node = world.game_controller
	var runtime: MatchReinforcementController = host.reinforcements
	_check(runtime.pending.size() == 2, "Assigned units are held outside initial deployment")
	_check(not Globals.get_units().has(first) and not Globals.get_units().has(second), "Pending units never join active registries")
	_check(not first.is_processing() or not first.can_process(), "Pending units cannot process combat or movement")
	_check(not first.is_visible_in_tree(), "Pending units stay hidden")
	_check(Globals.get_units().has(candidates[2]), "Zero-time reinforcements activate during initialization")
	_test_pending_strength()
	var state: ReinforcementState = runtime.states[0]
	var rolled: float = state.rolled_arrival_seconds
	_check(rolled >= 90.0 and rolled <= 150.0, "Runtime arrival stays inside the authored window")
	_check(state.player_estimate_seconds == 120.0 and definition.expected_seconds == 120.0, "Authored expected time and player estimate remain independent of the roll")
	_check(runtime.player_briefing(Globals.Team.ALLIES).is_empty(), "Enemy reinforcement estimates remain private")
	_check(runtime.player_briefing(Globals.Team.AXIS).contains("about 2 min"), "Friendly briefing shows approximate ETA")
	var save: MatchSaveData = MatchSaveData.new()
	runtime.advance(30.0)
	runtime.save_to(save)
	_check(ResourceSaver.save(save, "/tmp/acl_reinforcement_test.tres") == OK, "Runtime reinforcement state saves")
	var loaded: MatchSaveData = ResourceLoader.load("/tmp/acl_reinforcement_test.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as MatchSaveData
	runtime.restore_from(loaded)
	_check(runtime.elapsed_seconds == 30.0 and is_equal_approx(runtime.states[0].rolled_arrival_seconds, rolled), "Save/load preserves elapsed time and rolled arrival without rerolling")
	runtime.advance(rolled - 30.01)
	_check(runtime.pending.size() == 2, "Units remain absent until their scheduled arrival")
	runtime.advance(0.02)
	_check(Globals.get_units().has(first) and runtime.pending.size() == 1, "The first staggered unit activates through normal registration")
	_check(first.global_position.is_equal_approx(first_position), "First arrival preserves its authored position")
	_check(first.unit_died.is_connected(host._on_unit_died), "Arrivals use normal combat lifecycle connections")
	_check(first.create_save_data().map_unit_id == first.map_unit_id, "Unit saves retain stable authored identity")
	_check(runtime.player_briefing(Globals.Team.AXIS).contains("Arriving"), "Player briefing reports partial arrival")
	runtime.save_to(save)
	runtime.restore_from(save)
	_check(runtime.states[0].arrived_unit_ids.size() == 1, "Partial arrival survives restoration")
	runtime.advance(10.0)
	_check(Globals.get_units().has(second) and runtime.pending.is_empty(), "Remaining staggered units activate in order")
	_check(second.global_position.is_equal_approx(second_position), "Second arrival preserves its authored position")
	var count: int = Globals.get_units().size()
	runtime.advance(1000.0)
	_check(Globals.get_units().size() == count, "Repeated advances cannot spawn duplicate units")
	_check(runtime.player_briefing(Globals.Team.AXIS).contains("Arrived"), "Completed arrivals update player briefing")
	_check(save.reinforcement_states[0].arrived_unit_ids.size() == 1, "Saved runtime snapshots do not change when later units arrive")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("/tmp/acl_reinforcement_test.tres"))
	main.queue_free()
	await get_tree().process_frame
	print("Reinforcements regression: %d checks, %d failures" % [checks, failures])
	get_tree().quit(failures)


func _normalize(scenario: Scenario) -> void:
	var changes: Array[Dictionary] = []
	ReinforcementAuthoring.collect_changes(scenario, changes)
	for change: Dictionary in changes:
		(change["object"] as Object).set(change["property"], change["value"])


func _test_authoring(scenario: Scenario, definition: ReinforcementDefinition, spare: Unit) -> void:
	var first_id: String = definition.unit_ids[0]
	_normalize(scenario)
	_check(definition.unit_ids[0] == first_id, "Normalizing preserves stable unit identities")
	var duplicate: ReinforcementDefinition = ReinforcementDefinition.new()
	duplicate.unit_ids = definition.unit_ids.duplicate()
	definition.get_parent().add_child(duplicate)
	_normalize(scenario)
	_check(duplicate.unit_ids.is_empty(), "A unit cannot belong to two reinforcement definitions")
	definition.get_parent().remove_child(duplicate)
	duplicate.free()
	definition.unit_ids.append(spare.map_unit_id)
	var parent: Node = spare.get_parent()
	parent.remove_child(spare)
	_normalize(scenario)
	_check(not definition.unit_ids.has(spare.map_unit_id), "Deleting a map unit removes its reinforcement reference")
	parent.add_child(spare)
	var removed: ReinforcementDefinition = ReinforcementDefinition.new()
	removed.unit_ids = [spare.map_unit_id]
	definition.get_parent().add_child(removed)
	definition.get_parent().remove_child(removed)
	removed.free()
	_check(scenario.get_units().has(spare), "Deleting a definition leaves its units in normal initial deployment")
	spare.map_unit_id = first_id
	_normalize(scenario)
	_check(spare.map_unit_id != first_id and definition.unit_ids.has(first_id), "Duplicated unit IDs are repaired without redirecting existing references")
	# Verify authored unit identities and definitions round-trip in a standalone mission scene.
	var fixture: Scenario = Scenario.new()
	var units: Node2D = Node2D.new()
	units.name = "Units"
	fixture.add_child(units)
	units.owner = fixture
	var unit: Unit = Unit.new()
	unit.map_unit_id = first_id
	units.add_child(unit)
	unit.owner = fixture
	var branch: Node = Node.new()
	branch.name = "Reinforcements"
	fixture.add_child(branch)
	branch.owner = fixture
	var copy: ReinforcementDefinition = definition.duplicate() as ReinforcementDefinition
	branch.add_child(copy)
	copy.owner = fixture
	var packed: PackedScene = PackedScene.new()
	_check(packed.pack(fixture) == OK, "Mission definitions serialize with the map scene")
	var restored: Scenario = packed.instantiate() as Scenario
	var restored_definition: ReinforcementDefinition = restored.get_node("Reinforcements").get_child(0) as ReinforcementDefinition
	var restored_unit: Unit = restored.get_node("Units").get_child(0) as Unit
	_check(restored_definition.unit_ids == definition.unit_ids and restored_definition.expected_seconds == 120.0 and restored_unit.map_unit_id == first_id, "Scene serialization preserves stable references and authored timing")
	restored.free()
	fixture.free()


func _test_distribution(definition: ReinforcementDefinition) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var squared: float = 0.0
	var in_bounds: bool = true
	for index: int in range(2000):
		var value: float = definition.roll_arrival(rng)
		in_bounds = in_bounds and value >= 90.0 and value <= 150.0
		squared += pow(value - 120.0, 2.0)
	_check(in_bounds and squared / 2000.0 < 200.0, "Near-expected distribution favors central arrivals within hard bounds")
	definition.expected_seconds = 0.0
	definition.variation_seconds = 0.0
	_check(definition.roll_arrival(rng) == 0.0, "Zero-time arrivals and zero variation are supported")
	definition.expected_seconds = 120.0
	definition.variation_seconds = 30.0
	definition.distribution = ReinforcementDefinition.Distribution.UNIFORM
	var state: ReinforcementState = ReinforcementState.roll(definition, rng)
	_check(state.rolled_arrival_seconds >= 90.0 and state.rolled_arrival_seconds <= 150.0, "Uniform distribution stays inside the authored arrival window")
	_check(is_equal_approx(state.arrival_by_unit[definition.unit_ids[1]] - state.arrival_by_unit[definition.unit_ids[0]], 10.0), "Fixed stagger intervals preserve authored unit order")
	definition.distribution = ReinforcementDefinition.Distribution.NEAR_EXPECTED


func _test_pending_strength() -> void:
	var deployed: Array[Unit] = Globals.get_units_for_team(Globals.Team.AXIS)
	for unit: Unit in deployed:
		unit.surrendered = true
	_check(not MatchVictoryCoordinator._defeated_teams().has(Globals.Team.AXIS), "Pending reinforcements prevent irreversible force defeat")
	var exit: ExitUnitsCondition = ExitUnitsCondition.new()
	exit.team = Globals.Team.AXIS
	exit.required_unit_count = 2
	exit.state = ExitUnitsState.new()
	exit.state.exit_hexes = [Vector2i(1, 1)]
	_check(VictoryConditionProgress.outcome_possible([exit], Globals.Team.AXIS, exit.outcome_level), "Pending reinforcements keep achievable exit objectives possible")
	for unit: Unit in deployed:
		unit.surrendered = false


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
