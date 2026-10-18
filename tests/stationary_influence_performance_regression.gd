extends Node

const FRAME_COUNT: int = 360
const FRAME_DELTA: float = 1.0 / 60.0
const MAX_UPDATE_USEC: int = 10000

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var chosen: Map
	for candidate: Map in world.maps.get_children():
		if candidate.campaign_name == "Road to Alderbrook" and candidate.get_scenario(0).scenario_id == "alderbrook_04_two_crossings":
			chosen = candidate
	_check(chosen != null, "Stationary performance fixture loads Two Crossings")
	if chosen == null:
		get_tree().quit(failures)
		return
	var scenario: Scenario = chosen.get_scenario(0)
	Globals.map_chosen = chosen
	Globals.scenario_chosen = scenario
	world.start_screen.time = scenario.duration_s / 60.0
	world.start_screen.hide()
	await world._on_game_started(chosen, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	# Exercise the normal influence scheduler without movement, combat, rendering or AI.
	main.process_mode = Node.PROCESS_MODE_DISABLED
	ThreatMap.set_process(false)
	var controller: InfluenceMapController = world.game_controller.influence_map_controller
	var objectives: Dictionary[int, Vector2i] = controller.objectives_by_team.duplicate()
	controller.reset_for_match()
	controller.objectives_by_team = objectives
	var positions: Dictionary[Unit, Vector2i] = {}
	for unit: Unit in Globals.get_units():
		positions[unit] = unit.current_hex
	_check(positions.size() == 20, "Two Crossings profiles its full authored force")
	var samples: Array[int] = []
	var slow_frames: Array[Dictionary] = []
	var generations: int = 0
	var start_max_usec: int = 0
	var capture_max_usec: int = 0
	var publish_max_usec: int = 0
	for frame: int in range(FRAME_COUNT):
		var previous: InfluenceSnapshot = controller.snapshot
		var capturing: bool = controller._capture_job != null
		var starting: bool = not controller.rebuild_pending and controller.update_counter + FRAME_DELTA >= controller.update_threshold
		var started: int = Time.get_ticks_usec()
		controller._process(FRAME_DELTA)
		var elapsed: int = Time.get_ticks_usec() - started
		samples.append(elapsed)
		if starting:
			start_max_usec = maxi(start_max_usec, elapsed)
		elif capturing:
			capture_max_usec = maxi(capture_max_usec, elapsed)
		if controller.snapshot != previous:
			generations += 1
			publish_max_usec = maxi(publish_max_usec, elapsed)
			_check(controller.threat_axis_composites_by_team.is_empty(), "Publishing tactical maps does not build unused axis diagnostics")
		if elapsed >= MAX_UPDATE_USEC:
			slow_frames.append({"frame": frame, "usec": elapsed, "capture": capturing, "start": starting, "publication": controller.snapshot != previous})
	samples.sort()
	_check(generations >= 4, "Repeated stationary refreshes publish both teams through the normal scheduler")
	_check(samples[-1] < MAX_UPDATE_USEC, "Stationary influence updates stay below ten milliseconds, including cold capture and publication")
	for unit: Unit in positions:
		_check(unit.current_hex == positions[unit], "Profiling keeps every deployed unit stationary")
	print("Stationary influence performance: ", JSON.stringify({"map": "Two Crossings", "units": positions.size(), "frames": FRAME_COUNT,
		"generations": generations, "median_ms": samples[FRAME_COUNT / 2] / 1000.0, "max_ms": samples[-1] / 1000.0,
		"start_max_ms": start_max_usec / 1000.0, "capture_max_ms": capture_max_usec / 1000.0,
		"publish_max_ms": publish_max_usec / 1000.0, "slow_frames": slow_frames}))
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Stationary influence performance checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
