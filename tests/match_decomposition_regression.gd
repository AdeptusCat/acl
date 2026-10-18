extends Node

const FIXTURE_PATH: String = "res://tests/fixtures/match_decomposition_baseline.json"

class ConditionProbe extends VictoryCondition:
	var met: bool = false
	var evaluations: int = 0

	func is_condition_met() -> bool:
		evaluations += 1
		return met


class SpawnProbe extends Unit:
	var lifecycle: Array[Dictionary] = []

	# PackedScene.pack orders inherited properties differently from the authored
	# Unit scene. Avoid testing that instrumentation artifact before its catalog loads.
	func _make_squad() -> void:
		if squads_collection != null:
			super._make_squad()

	func _ready() -> void:
		lifecycle.append({"event": "ready", "team": team, "ground_bound": ground_map != null})
		super._ready()

	func _setup_runtime_soldiers(loadout: SquadLoadoutSpec) -> void:
		lifecycle.append({"event": "roster", "team": team, "ground_bound": ground_map != null})
		super._setup_runtime_soldiers(loadout)


var failures: int = 0
var main: Node
var world: Node
var controller: Node2D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	world = main.world
	controller = world.game_controller
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	var original_conditions: Dictionary[Globals.Team, VictoryConditionCollection] = Globals.victory_conditions
	var observations: Dictionary = {"victory": _observe_victory(), "spawning": _observe_spawning()}
	Globals.victory_conditions = original_conditions
	observations["visibility"] = _observe_visibility()
	_test_interaction()
	controller.time_left_seconds = 0.0
	controller.end_game_handled = false
	controller._on_win_condition_timer_timeout()
	_check(world.result_screen.visible and controller.end_game_handled, "Actual World receives the winner result")
	_check(not DirAccess.get_files_at("user://matches").is_empty(), "World retains match-save ownership")
	if OS.get_cmdline_user_args().has("--record-baseline"):
		var file: FileAccess = FileAccess.open("user://match_decomposition_baseline.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(observations, "\t"))
		print("Match baseline: ", ProjectSettings.globalize_path("user://match_decomposition_baseline.json"))
	else:
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
		var normalized: Dictionary = JSON.parse_string(JSON.stringify(observations))
		for section: String in observations:
			_check(normalized[section] == expected[section], "Match state, lifecycle and event order: " + section)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Match decomposition regression failures: ", failures)
	get_tree().quit(failures)


func _observe_victory() -> Dictionary:
	var result: Dictionary = {}
	# AXIS major, ALLIES major, AXIS minor, ALLIES minor, remaining time.
	var cases: Array[Array] = [
		[true, false, false, true, 30.0], [true, true, false, false, 30.0],
		[true, true, false, false, 0.0], [false, false, false, true, 30.0],
		[false, false, true, true, 30.0], [false, false, true, true, 0.0],
		[false, false, false, false, 30.0], [false, false, false, false, 0.0],
	]
	for index: int in range(cases.size()):
		var host: Node2D = load("res://scenes/game/match_controller.gd").new()
		host.time_left_seconds = cases[index][4]
		host.timer_running = true
		var conditions: Array[ConditionProbe] = []
		Globals.victory_conditions = {}
		for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
			var collection: VictoryConditionCollection = VictoryConditionCollection.new()
			for level: VictoryCondition.OutcomeLevel in [VictoryCondition.OutcomeLevel.MAJOR, VictoryCondition.OutcomeLevel.MINOR]:
				var condition: ConditionProbe = ConditionProbe.new()
				condition.team = team
				condition.outcome_level = level
				var offset: int = team
				if level == VictoryCondition.OutcomeLevel.MINOR:
					offset += 2
				condition.met = cases[index][offset]
				conditions.append(condition)
				collection.victory_conditions.append(condition)
			Globals.victory_conditions[team] = collection
		var signals: Array[Dictionary] = []
		host.show_winner.connect(func(team: int, level: VictoryCondition.OutcomeLevel, timeout: bool) -> void:
			signals.append({"team": team, "level": level, "timeout": timeout,
				"running_at_signal": host.timer_running, "handled_at_signal": host.end_game_handled})
		)
		host._on_win_condition_timer_timeout()
		host._on_win_condition_timer_timeout()
		var evaluations: Array[int] = []
		for condition: ConditionProbe in conditions:
			evaluations.append(condition.evaluations)
		result[str(index)] = {"signals": signals, "evaluations": evaluations,
			"running": host.timer_running, "handled": host.end_game_handled}
		host.free()
	return result


func _observe_spawning() -> Dictionary:
	var original_scene: PackedScene = controller.unit_scene
	var root: Unit = original_scene.instantiate() as Unit
	root.set_script(SpawnProbe)
	root.squads_collection = load("res://resources/squads/team_squad_loadout_catalog.tres") as SquadsCollection
	root.company = Unit.Company.F
	root.platoon = 9
	root.squad = 9
	var scene: PackedScene = PackedScene.new()
	_check(scene.pack(root) == OK, "Pack instrumented Unit with its existing children")
	root.free()
	controller.unit_scene = scene
	controller.spawn_unit(Globals.Team.ALLIES, Vector2i(5, 5), Globals.SquadType.Rifle, 321)
	var dynamic: SpawnProbe = controller.unit_container.get_child(-1) as SpawnProbe
	_freeze(dynamic)
	var dynamic_state: Dictionary = _spawn_snapshot(dynamic)
	Globals.unregister_unit(dynamic.team, dynamic.company, dynamic.platoon, dynamic.squad)
	dynamic.free()
	var saved: UnitSaveData = UnitSaveData.new()
	saved.team = Globals.Team.ALLIES
	saved.unit_scene_path = "res://scenes/game/units/unit.tscn"
	saved.squad_loadout = SquadLoadoutSpec.new()
	for index: int in range(3):
		var soldier: SoldierLoadout = SoldierLoadout.new()
		soldier.weapon = load("res://resources/weapons/m1_garand.tres") as WeaponSpec
		saved.squad_loadout.soldiers.append(soldier)
	var match_save: MatchSaveData = MatchSaveData.new()
	match_save.player_units.append(saved)
	controller.spawn_units_from_match_save(match_save)
	var restored: SpawnProbe = controller.unit_container.get_child(-1) as SpawnProbe
	_freeze(restored)
	var restored_state: Dictionary = _spawn_snapshot(restored)
	Globals.unregister_unit(restored.team, restored.company, restored.platoon, restored.squad)
	restored.free()
	controller.unit_scene = original_scene
	return {"dynamic": dynamic_state, "saved": restored_state}


func _spawn_snapshot(unit: SpawnProbe) -> Dictionary:
	var connections: Array[String] = []
	for signal_name: String in ["unit_died", "unit_entered_hex", "unit_arrived_at_hex", "deselect_unit", "started_moving", "unit_surrendered"]:
		for connection: Dictionary in unit.get_signal_connection_list(signal_name):
			var callback: Callable = connection["callable"]
			var receiver: String = "other"
			if callback.get_object() == controller:
				receiver = "match"
			elif callback.get_object() == LOS:
				receiver = "los"
			elif callback.get_object() == MovementSystem:
				receiver = "movement"
			connections.append("%s/%s/%s" % [signal_name, receiver, callback.get_method()])
	return {"lifecycle": unit.lifecycle.duplicate(true), "team": unit.team,
		"hex": [unit.current_hex.x, unit.current_hex.y], "formation": unit.formation_id,
		"members": unit.members_alive, "roster": unit.squad_fire.soldiers.size(), "legacy": unit.loadouts.size(),
		"group": unit.is_in_group("units"), "connections": connections,
		"registered": Globals.get_unit(unit.team, unit.company, unit.platoon, unit.squad) == unit}


func _observe_visibility() -> Dictionary:
	var observer: Unit = Globals.get_units_for_team(Globals.team_player)[0]
	var enemy: Unit = Globals.get_units_for_team(Globals.team_enemy)[0]
	_set_hex(observer, Vector2i(400, 400))
	_set_hex(enemy, Vector2i(403, 400))
	LOSHelper.los_lookup = {observer.current_hex: {enemy.current_hex: {"target_cover": 0, "target_conceal": 0}}}
	Globals.unit_visible_enemies = {observer: []}
	Globals.unit_enemies_in_los = {observer: [enemy]}
	Globals.unit_enemy_tracks.clear()
	controller.update_los_time(0.8)
	var track: EnemyTrack = Globals.unit_enemy_tracks[observer][enemy]
	_check(track.has_confirmed_lock and track.los_time_s == 0.8, "LOS aging establishes the existing lock threshold")
	track.confidence = 0.5
	enemy.squad_fire.fire_recent = 1.0
	var old_dictionary: Dictionary = Globals.unit_visible_enemies
	seed(102)
	controller._on_unit_visibility_checker_timer_timeout()
	var result: Dictionary = {"detected": _track_snapshot(track), "rng_tail": randf()}
	_check(old_dictionary[observer].is_empty(), "Detection replaces the visibility dictionary")
	result["published"] = Globals.unit_visible_enemies[observer].has(enemy)
	Globals.unit_enemies_in_los.clear()
	controller.update_los_time(0.5)
	controller._on_unit_visibility_checker_timer_timeout()
	result["lost"] = _track_snapshot(track)
	controller._on_unit_shooting(enemy)
	result["shooting"] = _track_snapshot(track)
	_check(Globals.unit_visible_enemies[observer].is_empty(), "Shooting confidence does not immediately publish visibility")
	_set_hex(enemy, observer.current_hex)
	controller._on_unit_visibility_checker_timer_timeout()
	result["same_hex"] = _track_snapshot(track)
	_check(track.confidence == 1.0 and Globals.unit_visible_enemies[observer].has(enemy), "Same-hex opponents receive an immediate visible lock")
	var visible_hexes: Array = LOSHelper.visible_hexes[observer.team]
	controller.update_visible_hexes()
	_check(visible_hexes.has(observer.current_hex), "Visible hexes retain their original array identity")
	controller.show_visible_units()
	controller.draw_fog()
	_check(enemy.visible, "Detected enemy is displayed by the actual Match")
	return result


func _track_snapshot(track: EnemyTrack) -> Dictionary:
	return {"confidence": snappedf(track.confidence, 0.000001), "visible": track.is_visible,
		"lock": track.has_confirmed_lock, "los": track.currently_in_los, "los_time": track.los_time_s}


func _test_interaction() -> void:
	var unit: Unit = Globals.get_units_for_team(Globals.team_player)[0]
	controller._select_unit(unit)
	_check(controller.selected_unit == unit and unit.selected, "Selection stays on the Match and Unit")
	_check(controller.influence_map_debug_draw.selected_unit == unit, "Selection updates the existing influence overlay")
	var mouse_hex: Vector2i = controller.ground_layer.local_to_map(controller.get_local_mouse_position())
	LOSHelper.los_lookup = {unit.current_hex: {mouse_hex: {"target_cover": 2}}}
	controller.handle_mouse_event_position_changed(Vector2(333, 22))
	_check(controller.origin_hex == unit.current_hex and controller.target_hex == mouse_hex, "Hover preview keeps the original scene coordinate anchor")
	_check(controller.targetCover == 2, "Hover preview uses the live LOS cover entry")
	controller._deselect_unit(unit)
	_check(controller.selected_unit == null and not unit.selected and controller.influence_map_debug_draw.selected_unit == null, "Deselection clears the existing state owners")
	var position: Vector2 = Vector2(123, 456)
	controller.hex_glow(position)
	var child: Node = controller.get_child(-1)
	_check(child is ColorRect and child.get_parent() == controller, "Glow is parented to the original Match node")
	if child is ColorRect:
		_check((child as ColorRect).position + (child as ColorRect).size / 2.0 == position, "Glow remains centered on the Match-local position")
	child.queue_free()
	controller.handle_mouse_event_position_changed(Vector2.ZERO)


func _set_hex(unit: Unit, hex: Vector2i) -> void:
	unit.current_hex = hex
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(hex)
	unit.position = LOSHelper.ground_layer.map_to_local(hex)


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		(node as Timer).stop()
	for child: Node in node.get_children():
		_freeze(child)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
