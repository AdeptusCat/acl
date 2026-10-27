extends Node

class DisabledRecorder extends EngagementRecorder:
	func _capture_allowed() -> bool:
		return false


class FailedMetadataRecorder extends EngagementRecorder:
	func _save_json(_filename: String, _data: Dictionary) -> bool:
		return false


class HostProbe extends Node2D:
	var time_left_seconds: float = 60.0
	var timer_running: bool = false
	var end_game_handled: bool = false
	var continuing_after_end: bool = false
	signal show_winner(winner: int, outcome: int, timeout: bool)


var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(not SessionSettings.capture_logs, "Capture is off by default, including debug builds")
	_test_preferences()
	_test_menu_and_toggle()
	await _test_gate_and_lifecycle()
	await _test_live_map()
	SessionSettings.capture_logs = false
	print("Engagement capture checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_preferences() -> void:
	var original_path: String = SessionSettings.preferences_path
	var test_path: String = "user://log_capture_preferences.cfg"
	SessionSettings.preferences_path = test_path
	SessionSettings.capture_logs = true
	var config: ConfigFile = ConfigFile.new()
	_check(config.load(test_path) == OK and config.get_value("logging", "capture_logs", false) == true, "Enabling capture saves the preference")
	SessionSettings.preferences_path = ""
	SessionSettings.capture_logs = false
	SessionSettings.preferences_path = test_path
	SessionSettings.load_preferences()
	_check(SessionSettings.capture_logs, "Capture preference survives a reload")
	config.set_value("logging", "capture_logs", "true")
	config.save(test_path)
	SessionSettings.load_preferences()
	_check(not SessionSettings.capture_logs, "Invalid saved values cannot enable capture")
	SessionSettings.preferences_path = original_path
	DirAccess.remove_absolute(test_path)


func _test_menu_and_toggle() -> void:
	var host: HostProbe = HostProbe.new()
	add_child(host)
	Debug.start_engagement_capture(host)
	_check(not is_instance_valid(Debug.engagement_recorder) or not Debug.engagement_recorder.active, "Starting a battle with capture off does not start debug logging")
	var direct: EngagementRecorder = EngagementRecorder.new()
	add_child(direct)
	_check(not direct.start_capture(host, "user://settings_disabled_capture") and not DirAccess.dir_exists_absolute("user://settings_disabled_capture"), "Direct recorder calls cannot bypass the disabled setting")
	direct.free()
	var hud: Control = Control.new()
	hud.size = Vector2(1280.0, 720.0)
	add_child(hud)
	var panel_scene: PackedScene = load("res://scenes/ui/panels/battle_settings_panel.tscn") as PackedScene
	var panel: Control = panel_scene.instantiate() as Control
	var second_panel: Control = panel_scene.instantiate() as Control
	hud.add_child(panel)
	hud.add_child(second_panel)
	var toggle: CheckBox = panel.get_node("Menu/Scroll/Content/CaptureLogs") as CheckBox
	var second_toggle: CheckBox = second_panel.get_node("Menu/Scroll/Content/CaptureLogs") as CheckBox
	_check(not toggle.button_pressed, "The settings checkbox reflects the disabled preference")
	toggle.button_pressed = true
	var recorder: EngagementRecorder = Debug.engagement_recorder
	_check(SessionSettings.capture_logs and second_toggle.button_pressed and is_instance_valid(recorder) and recorder.active, "Enabling the menu checkbox starts capture mid-battle and synchronizes other menus")
	var first: String = recorder.directory
	toggle.button_pressed = false
	_check(not recorder.active and recorder._events == null and recorder._snapshots == null, "Disabling capture immediately closes the log streams")
	_check(_json(first.path_join("summary.json")).reason == "capture_disabled" and bool(_json(first.path_join("summary.json")).complete), "Disabling capture finalizes the saved session")
	var bytes_before: int = FileAccess.get_file_as_bytes(first.path_join("events.jsonl")).size()
	_check(recorder.record_event("disabled", {}) == -1, "Disabled capture rejects further events")
	recorder._process(2.0)
	_check(FileAccess.get_file_as_bytes(first.path_join("events.jsonl")).size() == bytes_before, "Disabled capture cannot append log data")
	toggle.button_pressed = true
	_check(recorder.active and recorder.directory != first, "Re-enabling capture starts a fresh log session")
	Debug.finish_engagement_capture("test_finished")
	SessionSettings.capture_logs = false
	SessionSettings.capture_logs = true
	_check(not recorder.active, "A finished battle is not restarted by a later settings change")
	hud.free()
	host.free()


func _test_gate_and_lifecycle() -> void:
	var host: HostProbe = HostProbe.new()
	add_child(host)
	var disabled: EngagementRecorder = DisabledRecorder.new()
	add_child(disabled)
	_check(not disabled.start_capture(host, "user://disabled_capture"), "Disabled capture gate rejects capture")
	_check(not DirAccess.dir_exists_absolute("user://disabled_capture"), "Disabled capture creates no directory or files")
	_check(disabled.record_event("ignored", {}) == -1, "Disabled capture does not record events")
	disabled.free()
	var failed: EngagementRecorder = FailedMetadataRecorder.new()
	add_child(failed)
	_check(not failed.start_capture(host, "user://failed_capture") and not failed.active, "Metadata write failure disables capture without affecting the match")
	_check(failed._events == null and failed._snapshots == null, "Failed capture closes its streams")
	failed.free()
	var recorder: EngagementRecorder = EngagementRecorder.new()
	add_child(recorder)
	seed(1978)
	var expected_random: float = randf()
	seed(1978)
	_check(recorder.start_capture(host, "user://capture_probes"), "Opted-in capture opens streams")
	var first: String = recorder.directory
	_check(not bool(_json(first.path_join("summary.json")).complete), "A newly started capture has an incomplete manifest for crash recovery")
	recorder.record_event("probe", {"value": 12})
	recorder._process(1.0)
	_check(_json_lines(first.path_join("snapshots.jsonl")).size() >= 2, "Periodic snapshots are readable while capture is active")
	host.show_winner.emit(1, 0, false)
	_check(not bool(_json(first.path_join("summary.json")).complete), "Results flush an intermediate summary and allow continued play")
	recorder.finish("test_finished")
	_check(randf() == expected_random, "Capture does not consume gameplay randomness")
	_check(bool(_json(first.path_join("summary.json")).complete), "Finalization writes a completed manifest")
	_check(_json(first.path_join("metadata.json")).debug_build == true, "Metadata identifies the debug build")
	_check(recorder.start_capture(host, "user://capture_probes"), "A second capture starts")
	var second: String = recorder.directory
	_check(second != first, "Sessions use distinct directories")
	recorder.start_capture(host, "user://capture_probes")
	_check(_json(second.path_join("summary.json")).reason == "replaced", "Replacing capture finalizes the previous streams")
	var third: String = recorder.directory
	host.queue_free()
	await get_tree().process_frame
	_check(not recorder.active and _json(third.path_join("summary.json")).reason == "map_closed", "Owner teardown finalizes capture")
	recorder.free()


func _test_live_map() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	var recorder: EngagementRecorder = Debug.engagement_recorder
	_check(is_instance_valid(recorder) and recorder.active, "Starting an actual map with the setting enabled starts capture")
	if not is_instance_valid(recorder) or not recorder.active:
		main.queue_free()
		await get_tree().process_frame
		return
	var path: String = recorder.directory
	seed(3301)
	var expected_random: float = randf()
	seed(3301)
	recorder._sample()
	_check(randf() == expected_random, "Full live-roster snapshots preserve gameplay randomness")
	var shooter: Unit
	var target: Unit
	for unit: Unit in Globals.get_units():
		if unit.squad_type == Globals.SquadType.Rifle:
			if unit.team == Globals.Team.AXIS and shooter == null:
				shooter = unit
			if unit.team == Globals.Team.ALLIES and target == null:
				target = unit
	_check(shooter != null and target != null, "Fixture supplies complete opposing squads")
	_set_hex(shooter, Vector2i(5, 5))
	_set_hex(target, Vector2i(9, 5))
	LOSHelper.los_lookup[shooter.current_hex] = {target.current_hex: {"target_cover": 2, "hindrance": 0}}
	Globals.unit_visible_enemies[shooter] = [target]
	Globals.unit_enemies_in_los[shooter] = [target]
	Debug.no_damage = false
	Debug.dont_fire_wepaons = false
	shooter.order(Globals.UnitCmd.FIRE_AT_UNIT, target)
	shooter.squad_fire.fire_shot.disconnect(shooter._on_fire_shot)
	var rifleman: Soldier
	for soldier: Soldier in shooter.squad_fire.soldiers:
		if soldier.weapon.type == WeaponSpec.WeaponType.Rifle and not soldier.weapon.can_fire_riflegrenades and soldier.role == RankGrades.Role.SOLDIER:
			rifleman = soldier
			break
	_check(rifleman != null, "An actual rifleman can exercise committed fire")
	rifleman.setup_weapon_task.done = true
	rifleman.reload_task.done = true
	rifleman.aquire_target_task.done = true
	var rounds: int = await shooter.squad_fire._try_fire_soldier(0.1, rifleman, false, 0, 0, 4, 2)
	_check(rounds > 0, "Real firing coroutine produces a committed shot and delayed impact")
	await get_tree().process_frame
	var members_before_ignored: int = target.members_alive
	Debug.no_damage = true
	for volley: int in range(2):
		shooter.squad_fire.fire_at(1, rifleman.weapon, false, target.current_hex, 4, 2, [target])
	await get_tree().process_frame
	Debug.no_damage = false
	_check(target.members_alive == members_before_ignored, "Capture preserves disabled-damage behavior for queued impacts")
	target._apply_casualties(1)
	target.soldiers_changed.emit()
	target.tactical_state.attention_quality = 1.0
	target.tactical_state.attention_stress_rate = 2.0
	target.stress_system._process(0.1)
	target.stress_system._set_state(STATES.MoraleState.PINNED)
	recorder._process(1.0)
	var snapshots: Array[Dictionary] = _json_lines(path.path_join("snapshots.jsonl"))
	var observed: Dictionary = {}
	for state: Dictionary in snapshots.back().units:
		if state.unit == recorder._unit_id(target):
			observed = state
	_check(not observed.is_empty() and observed.soldiers.size() == target.members_alive, "Snapshots retain the full live roster and actual casualties")
	_check(observed.has("attention_gain_since_sample") and not observed.attention_gain_since_sample.is_empty(), "Continuous attention gains are aggregated into snapshots")
	_check(observed.has("attention") and observed.attention.has("required") and observed.attention.has("suppression_activity") and observed.has("command") and observed.has("orders") and observed.stress.has("pressure_rps") and observed.stress.has("time_without_fire_s"), "Snapshots contain attention, HQ, orders and pressure context")
	_test_cover_capture(recorder, target, shooter)
	_test_ai_capture(recorder, world.game_controller, shooter)
	recorder._sample()
	recorder._flush()
	var latest: Dictionary = _json_lines(path.path_join("snapshots.jsonl")).back()
	_check(latest.schema_version == 2 and latest.has("ai") and not latest.objectives.is_empty(), "Versioned snapshots include AI command state and live objective progress")
	_check(not latest.ai.planners.is_empty() and latest.ai.planners[0].mission.has("mode"), "AI snapshots describe the actual mission rather than an empty resource reference")
	var metadata: Dictionary = _json(path.path_join("metadata.json"))
	_check(metadata.recovery_limits.leadership_multiplier == 1.5 and metadata.recovery_limits.hq_personal_multiplier == 1.5, "Metadata records the leadership and personal HQ recovery budgets")
	_check(metadata.map.name == map.map_name and not metadata.rules_sha256.is_empty(), "Metadata identifies the map and exact rule hashes")
	_check(not _json(path.path_join("map.json")).layers.is_empty(), "Terrain layers and their custom data are persisted")
	var events: Array[Dictionary] = _json_lines(path.path_join("events.jsonl"))
	var kinds: Dictionary[String, bool] = {}
	var impact_sequence: int = -1
	var correlated: bool = false
	var impact_order: Array[int] = []
	var applied_order: Array[int] = []
	var ignored: int = 0
	for event: Dictionary in events:
		kinds[str(event.type)] = true
		if event.type == "impact_resolved" and event.data.target == recorder._unit_id(target):
			impact_sequence = int(event.seq)
			impact_order.append(impact_sequence)
		if event.type == "incoming_effect_applied" and event.data.unit == recorder._unit_id(target):
			applied_order.append(int(event.data.impact_seq))
			if event.data.disposition == "ignored_inactive_or_no_damage":
				ignored += 1
		if event.type == "incoming_effect_applied" and int(event.data.impact_seq) == impact_sequence and impact_sequence > 0:
			correlated = true
	for kind: String in ["unit_registered", "weapon_registered", "shot_committed", "impact_resolved", "incoming_effect_applied", "stress_gain", "casualty", "roster_changed", "morale_changed", "order"]:
		_check(kinds.has(kind), "Actual map writes event: " + kind)
	_check(correlated, "Deferred effects correlate with the exact resolved impact")
	_check(impact_order == applied_order and ignored == 2, "Multiple queued and ignored effects preserve impact correlation order")
	var controller: Node = world.game_controller
	controller.time_left_seconds = 0.0
	controller._on_win_condition_timer_timeout()
	_check(recorder.active and _json(path.path_join("summary.json")).has("result"), "Match results flush logs without discarding subsequent play")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not recorder.active and bool(_json(path.path_join("summary.json")).complete), "Closing the map flushes and closes capture")


func _test_cover_capture(recorder: EngagementRecorder, unit: Unit, enemy: Unit) -> void:
	var original_hex: Vector2i = unit.current_hex
	var original_cached: int = unit.terrain_defense_bonus
	var original_legacy: int = unit.current_cover_bonus
	var covered: bool = false
	for cell: Vector2i in LOSHelper.building_layer.get_used_cells():
		var actual: int = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(cell))
		if actual <= 0:
			continue
		_set_hex(unit, cell)
		unit.current_cover_bonus = 0
		unit.terrain_defense_bonus = 0
		var state: Dictionary = recorder._unit_snapshot(unit)
		_check(state.cover == actual and state.cover_context.local_terrain == actual, "Cover capture samples real local terrain even when legacy and cached values are zero")
		covered = true
		break
	_check(covered, "The live cover fixture contains terrain with physical protection")
	_set_hex(unit, original_hex)
	unit.terrain_defense_bonus = original_cached
	unit.current_cover_bonus = original_legacy
	var original_visible: Array = Globals.unit_visible_enemies.get(unit, []).duplicate()
	var original_lanes: Dictionary = LOSHelper.los_lookup.get(unit.current_hex, {}).duplicate(true)
	Globals.unit_visible_enemies[unit] = [enemy]
	LOSHelper.los_lookup[unit.current_hex] = {enemy.current_hex: {"wall_cover": 2, "shooter_cover": 7, "hindrance": 5}}
	var context: Dictionary = recorder._cover_context(unit)
	_check(context.lanes[0].local_wall_cover == 2 and context.lanes[0].observed, "Directional cover excludes distant vegetation and identifies the observed source")
	Globals.unit_visible_enemies[unit] = original_visible
	LOSHelper.los_lookup[unit.current_hex] = original_lanes


func _test_ai_capture(recorder: EngagementRecorder, host: Node, unit: Unit) -> void:
	var planner: PlatoonAI = PlatoonAI.new()
	planner.active = false
	planner.team = unit.team
	planner.squads = [unit]
	planner.influence_map_controller = host.influence_map_controller
	planner.current_order = MissionOrder.new()
	host.add_child(planner)
	var goal: ScenarioGoalTask = ScenarioGoalTask.new()
	goal.kind = ScenarioGoalTask.Kind.OCCUPY
	goal.key = "capture_logging_fixture"
	goal.hex = unit.current_hex
	goal.defend_from_cover = true
	planner.goal_assignments[unit] = goal
	var result: DefensePositionResult = DefensePositionResult.new()
	result.unit = unit
	result.status = PositionResult.Status.NO_CANDIDATE
	result.reason = "No covered position protects the objective"
	result.rejections["cover"] = 7
	result.path = [unit.current_hex, unit.current_hex + Vector2i(1, 0)]
	var alternative: PositionCandidate = PositionCandidate.new()
	alternative.hex = unit.current_hex
	alternative.score = 2.0
	result.alternatives = [alternative]
	planner.squad_assignments[unit] = {"result": result, "role": "scenario_goal"}
	planner._issue_order(unit)
	result.status = PositionResult.Status.ACCEPTED
	result.target_index = 0
	result.profile_mode = PositionProfile.Mode.ADVANCE
	result.position_profile = PositionProfile.for_mode(PositionProfile.Mode.ADVANCE)
	planner.company_requires_support = true
	planner._issue_order(unit)
	planner._planning_requests = [{"query": PositionQuery.new()}]
	planner._cancel_plan("fixture_validation_failed")
	recorder._flush()
	var decisions: Array[Dictionary] = []
	var cancelled: bool = false
	for event: Dictionary in _json_lines(recorder.directory.path_join("events.jsonl")):
		if event.type == "ai_decision" and event.data.unit == recorder._unit_id(unit):
			decisions.append(event.data)
		if event.type == "ai_plan_cancelled" and event.data.reason == "fixture_validation_failed":
			cancelled = true
	_check(decisions.size() >= 2, "The actual AI execution entry point records its decisions")
	if decisions.size() >= 2:
		var rejected: Dictionary = decisions[decisions.size() - 2]
		var blocked: Dictionary = decisions.back()
		_check(rejected.disposition == "executor_rejected_or_no_candidate" and rejected.position.rejections.cover == 7, "No-candidate decisions preserve their rejection counts")
		_check(blocked.disposition == "company_support_unavailable" and blocked.position.status == "ACCEPTED", "A valid proposal blocked during execution is distinguishable from an issued order")
		_check(blocked.goal.defend_from_cover and blocked.goal.kind == "OCCUPY" and blocked.position.path.size() == 2, "AI decisions retain mission duty and the planned route")
		_check(blocked.position.alternatives.size() == 1 and blocked.position.profile.has("travel_weight"), "Decision events preserve alternative scores and the scoring profile")
		_check(rejected.position.score is String, "Non-finite AI scores remain explicit and valid in JSON")
	_check(cancelled, "Aborted AI planning records its cause")
	planner.free()


func _set_hex(unit: Unit, cell: Vector2i) -> void:
	unit.current_hex = cell
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(cell)
	unit.position = LOSHelper.ground_layer.map_to_local(cell)


func _json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if value is Dictionary:
		return value
	_check(false, "Valid JSON file: " + path)
	return {}


func _json_lines(path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var text: String = FileAccess.get_file_as_string(path)
	for line: String in text.split("\n", false):
		var value: Variant = JSON.parse_string(line)
		if value is Dictionary:
			rows.append(value)
		else:
			_check(false, "Valid JSONL line: " + path)
	return rows


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
