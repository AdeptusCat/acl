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
		if OS.get_cmdline_user_args().has("--spread-contacts"):
			_spread_contacts(controller.snapshot)
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
			_check(job.result.target_hex == result.target_hex and job.result.path == result.path and job.result.eligibility == result.eligibility and job.result.cell_states == result.cell_states and job.result.rejection_reasons == result.rejection_reasons, "Budgeted and synchronous pipelines publish the same advice, candidates and per-hex diagnostics")
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
		var slowest_step: Dictionary = {}
		while (planner._area_job != null or planner._planning_job != null) and plan_steps < 10000:
			var tick_started: int = Time.get_ticks_usec()
			controller._process_position_queries()
			plan_max_slice = maxi(plan_max_slice, controller.last_position_slice_usec)
			var phase: String = "start"
			if planner._area_job != null:
				phase = "allocation"
			elif planner._validation_job != null:
				phase = "validation:%d:%d" % [planner._validation_job.index, planner._validation_job.branch_index]
			elif planner._planning_job != null:
				phase = "query:%d" % planner._planning_index
			planner._process(0.0)
			var tick_usec: int = Time.get_ticks_usec() - tick_started
			if tick_usec > plan_max_tick:
				plan_max_tick = tick_usec
				slowest_step = {"phase": phase, "query_slice_us": controller.last_position_slice_usec, "tick_us": tick_usec}
			plan_steps += 1
		_check(planner._area_job == null and planner._planning_job == null, "Expanded sector planning completes through the normal scheduler")
		_check(plan_max_slice < 10000, "Expanded platoon searches keep tactical frame slices below ten milliseconds")
		_check(plan_max_tick < 10000, "Area allocation and final coverage validation also fit the measured tactical tick limit")
		print("Defense area plan sample: ", JSON.stringify({"policy": policy, "slices": plan_steps, "max_slice_us": plan_max_slice, "max_tick_us": plan_max_tick, "covered_positions": planner.defense_area.covered_positions.size(), "approaches": planner.defense_area.approaches.size(), "branches": planner.defense_area.duties().size(), "slowest_step": slowest_step}))
	print("Influence performance report: ", JSON.stringify({"map": str(map.name), "samples": samples}))
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Influence performance checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _spread_contacts(snapshot: InfluenceSnapshot) -> void:
	# Stress the bounded three-branch case on real authored terrain without moving live units.
	for team: int in snapshot.maps:
		var objective: Vector2i = snapshot.objectives[team]
		var sources: Array[Vector2i] = []
		var sector: int = -1
		var cells: Array[Vector2i] = []
		cells.assign(snapshot.maps[team].playable_cells.keys())
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if a.x != b.x:
				return a.x < b.x
			return a.y < b.y)
		for cell: Vector2i in cells:
			var distance: int = LOSHelper.get_hex_distance(cell, objective)
			if distance < 3 or distance > 8 or snapshot.get_path(team, cell, objective).is_empty():
				continue
			var cell_sector: int = DefenseAreaAssessment.sector_for(objective, cell)
			if sector >= 0 and sector != cell_sector:
				continue
			var separate: bool = true
			for source: Vector2i in sources:
				separate = separate and LOSHelper.get_hex_distance(cell, source) >= 3
			if not separate:
				continue
			sector = cell_sector
			sources.append(cell)
			if sources.size() == 3:
				break
		_check(sources.size() == 3, "Authored terrain supplies three separated credible sources in one sector")
		var opponents: Array[Unit] = Globals.get_units_for_team(Globals.get_enemy_team(team))
		var contacts: Array[InfluenceContact] = []
		for index: int in range(sources.size()):
			var contact: InfluenceContact = InfluenceContact.new()
			contact.unit = opponents[index % opponents.size()]
			contact.hex = sources[index]
			contact.firepower = 1.0
			contact.weapon_range = 6
			contact.observed = index != 2
			contact.last_seen_at = snapshot.captured_at
			contacts.append(contact)
		snapshot.defensive_contacts[team] = contacts


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
