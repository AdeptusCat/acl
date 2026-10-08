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
	var index: int = 0 if OS.get_cmdline_user_args().has("--default-map") else 1
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
			var started: int = Time.get_ticks_usec()
			DefensePositionPolicy.prepare(query)
			var prepare_us: int = Time.get_ticks_usec() - started
			var field: PositionRouteField = PositionRouteField.new()
			started = Time.get_ticks_usec()
			field.build(query)
			var flood_us: int = Time.get_ticks_usec() - started
			started = Time.get_ticks_usec()
			var result: PositionResult = PositionQueryService.query_positions(query)
			var query_us: int = Time.get_ticks_usec() - started
			samples.append({"unit": str(unit.name), "policy": policy, "prepare_us": prepare_us, "flood_us": flood_us, "query_us": query_us, "labels": field.labels.size(), "cells": field.labels_by_cell.size(), "target": str(result.target_hex), "valid": result.is_valid()})
			print("Influence performance sample: ", JSON.stringify(samples[-1]))
	print("Influence performance report: ", JSON.stringify({"map": str(map.name), "samples": samples}))
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Influence performance checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)
