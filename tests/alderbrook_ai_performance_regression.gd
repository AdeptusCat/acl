extends Node

const FRAME_COUNT: int = 720
const MAX_FRAME_USEC: int = 40000
const MAX_QUERY_USEC: int = 10000

class FrameStart extends Node:
	var profiler: Node

	func _process(_delta: float) -> void:
		profiler.frame_started = Time.get_ticks_usec()

var checks: int = 0
var failures: int = 0
var main: Node
var controller: InfluenceMapController
var measuring: bool = false
var skip_setup_frame: bool = true
var frame_started: int = 0
var samples: Array[int] = []
var slow_frames: Array[Dictionary] = []
var max_query_usec: int = 0
var objectives_requested: Dictionary[Vector3i, bool] = {}
var generations: Dictionary[int, bool] = {}


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
	if skip_setup_frame:
		skip_setup_frame = false
		return
	var elapsed: int = Time.get_ticks_usec() - frame_started
	samples.append(elapsed)
	max_query_usec = maxi(max_query_usec, controller.last_position_slice_usec)
	if elapsed >= MAX_FRAME_USEC:
		slow_frames.append({"frame": samples.size(), "frame_usec": elapsed, "query_usec": controller.last_position_slice_usec})
	if controller.snapshot == null:
		return
	generations[controller.snapshot.version] = true
	for team: int in controller.snapshot._forecast_jobs:
		for objective: Vector2i in controller.snapshot._forecast_jobs[team]:
			if controller.snapshot.objectives.get(team) != objective:
				objectives_requested[Vector3i(team, objective.x, objective.y)] = true


func _run() -> void:
	seed(6049)
	var previous_max_fps: int = Engine.max_fps
	Engine.max_fps = 60
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var chosen: Map
	for candidate: Map in world.maps.get_children():
		if candidate.campaign_name == "Road to Alderbrook" and candidate.get_scenario(0).scenario_id == "alderbrook_05_battle_for_alderbrook":
			chosen = candidate
	_check(chosen != null, "AI performance fixture loads Battle for Alderbrook")
	if chosen == null:
		get_tree().quit(failures)
		return
	var scenario: Scenario = chosen.get_scenario(0)
	Globals.map_chosen = chosen
	Globals.scenario_chosen = scenario
	world.start_screen.time = scenario.duration_s / 60.0
	world.start_screen.hide()
	await world._on_game_started(chosen, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	controller = world.game_controller.influence_map_controller
	var units: Array[Unit] = Globals.get_units()
	var positions: Dictionary[Unit, Vector2i] = {}
	for unit: Unit in units:
		positions[unit] = unit.current_hex
		# Keep the authored force stationary and alive while normal AI and timers run.
		unit.movement.set_process(false)
		unit.squad_fire.set_process(false)
		unit.stress_system.set_process(false)
	_check(units.size() == 31, "The benchmark includes the complete Alderbrook force")
	var planner: PlatoonAI = world.game_controller.platoon_ai
	_check(planner.active and planner.company_command.uses_hierarchy(), "Company AI stays enabled throughout profiling")
	measuring = true
	while samples.size() < FRAME_COUNT:
		await get_tree().process_frame
	measuring = false
	samples.sort()
	_check(generations.size() >= 3, "AI is profiled across repeated cold and warm snapshot generations")
	var defended_objectives: Dictionary[Vector2i, bool] = {}
	for formation: CompanyPlatoon in planner.company_command.platoons.values():
		if formation.support_firepower() > 0.0:
			defended_objectives[formation.objective] = true
	_check(defended_objectives.size() == 3, "Live defensive platoons retain all three district objectives")
	# The mortar no longer invents a fourth geographic mission by hunting enemy infantry.
	_check(objectives_requested.size() >= defended_objectives.size() - 1, "Live defensive queries exercise every alternate district objective")
	_check(controller.forecast_cache.builds >= 3 and controller.forecast_cache.hits > 0, "Cold forecasts finish and compatible later snapshots reuse them")
	_check(max_query_usec < MAX_QUERY_USEC, "Forecast work respects the tactical query slice limit")
	_check(samples[-1] < MAX_FRAME_USEC, "Stationary AI simulation has no large periodic CPU stalls")
	for unit: Unit in units:
		_check(unit.current_hex == positions[unit], "Every profiled unit remains stationary")
	print("Alderbrook AI performance: ", JSON.stringify({"frames": samples.size(), "units": units.size(), "generations": generations.size(),
		"alternate_objectives": objectives_requested.size(), "forecast_builds": controller.forecast_cache.builds, "forecast_reuses": controller.forecast_cache.hits,
		"median_frame_ms": samples[FRAME_COUNT / 2] / 1000.0, "max_frame_ms": samples[-1] / 1000.0,
		"max_query_ms": max_query_usec / 1000.0, "slow_frames": slow_frames}))
	Engine.max_fps = previous_max_fps
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Alderbrook AI performance checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
