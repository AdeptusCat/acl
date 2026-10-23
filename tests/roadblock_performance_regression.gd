extends Node

const FRAME_COUNT: int = 720
const MAX_FRAME_USEC: int = 40000
const MAX_BREACH_SLICE_USEC: int = 5000

class FrameStart extends Node:
	var profiler: Node

	func _process(_delta: float) -> void:
		profiler.frame_started = Time.get_ticks_usec()

var failures: int = 0
var checks: int = 0
var measuring: bool = false
var frame_started: int = 0
var samples: Array[int] = []
var max_breach_slice: int = 0
var pending_frames: int = 0
var published_updates: int = 0
var previous_task: ScenarioGoalTask
var director: ScenarioGoalDirector


func _ready() -> void:
	process_priority = 100000
	var begin: FrameStart = FrameStart.new()
	begin.profiler = self
	begin.process_priority = -100000
	add_child(begin)
	_run.call_deferred()


func _process(_delta: float) -> void:
	if not measuring:
		return
	samples.append(Time.get_ticks_usec() - frame_started)
	max_breach_slice = maxi(max_breach_slice, director.last_breach_slice_usec)
	if director._breach_pending:
		pending_frames += 1
		_check(director.tasks.size() == 1 and director.tasks[0] == previous_task, "Pending search retains the published mission")
	elif not director.tasks.is_empty() and director.tasks[0] != previous_task:
		published_updates += 1
		previous_task = director.tasks[0]


func _run() -> void:
	seed(6049)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("Alderbrook3") as Map
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.time = scenario.duration_s / 60.0
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.DEFEND)
	var planner: PlatoonAI = world.game_controller._ai_director_for_team(Globals.Team.AXIS).platoon_ai
	director = planner.goal_director
	# Preserve the authored force and normal AI scheduling while isolating stationary CPU work.
	for unit: Unit in Globals.get_units():
		unit.movement.set_process(false)
		unit.squad_fire.set_process(false)
		unit.stress_system.set_process(false)
	for frame: int in range(180):
		await get_tree().process_frame
	_test_search(planner, scenario.ai_escape_policies[0])
	previous_task = director.tasks[0]
	measuring = true
	while samples.size() < FRAME_COUNT:
		await get_tree().process_frame
	measuring = false
	samples.sort()
	_check(pending_frames > 0 and published_updates >= 3, "Repeated budgeted searches finish and publish fresh missions")
	_check(max_breach_slice < MAX_BREACH_SLICE_USEC, "Breach work stays within a small per-frame slice")
	_check(samples[-1] < MAX_FRAME_USEC, "Roadblock AI has no large periodic CPU stalls")
	print("Roadblock performance: ", JSON.stringify({"frames": samples.size(), "median_ms": samples[FRAME_COUNT / 2] / 1000.0,
		"max_frame_ms": samples[-1] / 1000.0, "max_breach_slice_ms": max_breach_slice / 1000.0,
		"pending_frames": pending_frames, "published_updates": published_updates}))
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Roadblock performance checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_search(planner: PlatoonAI, policy: EscapeMissionPolicy) -> void:
	var exits: Array[Vector2i] = policy.exit_condition.state.exit_hexes
	var expected_bypass: Dictionary[Unit, bool] = {}
	var expected: InfluenceContact = ExitBreachPlanner.select(planner, exits, policy, expected_bypass)
	var search: ExitBreachPlanner.Search = ExitBreachPlanner.Search.new()
	search.start(planner, exits, policy)
	search.advance(Time.get_ticks_usec() - 1)
	_check(search.cursor == 0 and not search.completed, "Expired deadlines perform no cell work")
	var slices: int = 0
	while not search.completed and slices < 10000:
		search.advance(Time.get_ticks_usec() + 250)
		slices += 1
	_check(search.completed and slices > 1, "Search resumes across bounded slices")
	_check(search.result == expected and search.bypass_units == expected_bypass, "Sliced and synchronous breach/bypass results agree")
	_check(search.matches(planner, exits, policy), "Unchanged search inputs remain reusable")
	var unit: Unit = planner.squads[0]
	var origin: Vector2i = unit.current_hex
	unit.current_hex += Vector2i(1, 0)
	_check(not search.matches(planner, exits, policy), "Movement invalidates captured origins")
	unit.current_hex = origin
	var morale: int = unit.stress_system.state
	unit.stress_system.state = STATES.MoraleState.PINNED
	_check(not search.matches(planner, exits, policy), "Pinning invalidates captured mobility")
	unit.stress_system.state = morale
	var risk: float = policy.maximum_bypass_risk
	policy.maximum_bypass_risk += 0.1
	_check(not search.matches(planner, exits, policy), "Policy changes invalidate captured safety rules")
	policy.maximum_bypass_risk = risk
	var snapshot: InfluenceSnapshot = planner.influence_map_controller.snapshot
	planner.influence_map_controller.snapshot = null
	_check(not search.matches(planner, exits, policy), "Snapshot replacement invalidates captured knowledge")
	planner.influence_map_controller.snapshot = snapshot


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
