extends Node

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var index: int = 1
	if OS.get_cmdline_user_args().has("--default-map"):
		index = 0
	var map: Map = world.maps.get_child(index)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	for frame: int in range(180):
		await get_tree().process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var controller: InfluenceMapController = world.game_controller.influence_map_controller
	var samples: Array[Dictionary] = []
	for policy: InfluenceMapController.KnowledgePolicy in [InfluenceMapController.KnowledgePolicy.OBSERVED_AND_MEMORY, InfluenceMapController.KnowledgePolicy.OMNISCIENT]:
		controller.knowledge_policy = policy
		for attempt: int in range(2):
			controller.create_maps(0.0)
			while controller.rebuild_pending:
				controller._process_los_rebuild()
				controller._process_budgeted_rebuild()
		for unit: Unit in Globals.get_units():
			var query: PositionQuery = PositionQuery.new()
			query.unit = unit
			query.team = unit.team
			query.snapshot = controller.snapshot
			query.objective_hex = controller.objectives_by_team[unit.team]
			query.forecast_data = query.snapshot.get_forecast_data(query.team, query.objective_hex)
			query.area_job = query.snapshot.defense_area_job(query.team, query.objective_hex, query.defense_radius, 10)
			var area_max_slice: int = 0
			while not query.area_job.completed:
				var area_started: int = Time.get_ticks_usec()
				query.area_job.advance(area_started + InfluenceMapController.POSITION_QUERY_BUDGET_USEC)
				area_max_slice = maxi(area_max_slice, Time.get_ticks_usec() - area_started)
			_check(area_max_slice < 10000, "Shared defense-area fields remain inside the measured frame-slice limit")
			var started: int = Time.get_ticks_usec()
			var result: PositionResult = PositionQueryService.query_positions(query)
			var query_us: int = Time.get_ticks_usec() - started
			var labels: int = 0
			var cells: int = 0
			if query.route_field != null:
				labels = query.route_field.labels.size()
				cells = query.route_field.labels_by_cell.size()
			var job: PositionQueryJob = controller.enqueue_position_query(query)
			var slices: int = 0
			var max_slice_us: int = 0
			while not job.completed and slices < 10000:
				controller._process_position_queries()
				max_slice_us = maxi(max_slice_us, controller.last_position_slice_usec)
				slices += 1
			_check(job.completed, "Budgeted query completes on authored terrain")
			_check(job.result.target_hex == result.target_hex and job.result.path == result.path and job.result.eligibility == result.eligibility, "Budgeted and synchronous pipelines publish the same advice and candidates")
			_check(max_slice_us < 10000, "No tactical query slice blocks a frame for ten milliseconds")
			samples.append({"unit": str(unit.name), "policy": policy, "query_us": query_us, "labels": labels, "cells": cells, "slices": slices, "max_slice_us": max_slice_us, "area_max_slice_us": area_max_slice, "target": str(result.target_hex), "valid": result.is_valid()})
			print("Influence performance sample: ", JSON.stringify(samples[-1]))
		var planner: PlatoonAI = world.game_controller.platoon_ai
		if not planner.active:
			planner = world.game_controller.get_node("PlatoonAi2")
		planner._start_plan(true)
		var plan_max_slice: int = 0
		var plan_max_tick: int = 0
		var plan_steps: int = 0
		while (planner._area_job != null or planner._planning_job != null) and plan_steps < 10000:
			var tick_started: int = Time.get_ticks_usec()
			controller._process_position_queries()
			plan_max_slice = maxi(plan_max_slice, controller.last_position_slice_usec)
			planner._process(0.0)
			plan_max_tick = maxi(plan_max_tick, Time.get_ticks_usec() - tick_started)
			plan_steps += 1
		_check(planner._area_job == null and planner._planning_job == null, "Expanded sector planning completes through the normal scheduler")
		_check(plan_max_slice < 10000, "Expanded platoon searches keep tactical frame slices below ten milliseconds")
		_check(plan_max_tick < 10000, "Area allocation and final coverage validation also fit the measured tactical tick limit")
		print("Defense area plan sample: ", JSON.stringify({"policy": policy, "slices": plan_steps, "max_slice_us": plan_max_slice, "max_tick_us": plan_max_tick, "covered_positions": planner.defense_area.covered_positions.size(), "approaches": planner.defense_area.approaches.size()}))
	print("Influence performance report: ", JSON.stringify({"map": str(map.name), "samples": samples}))
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Influence performance checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
