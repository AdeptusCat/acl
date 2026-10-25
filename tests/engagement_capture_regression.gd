extends Node

class DisabledRecorder extends EngagementRecorder:
	func _debug_allowed() -> bool:
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
	await _test_gate_and_lifecycle()
	await _test_live_map()
	print("Engagement capture checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_gate_and_lifecycle() -> void:
	var host: HostProbe = HostProbe.new()
	add_child(host)
	var disabled: EngagementRecorder = DisabledRecorder.new()
	add_child(disabled)
	_check(not disabled.start_capture(host, "user://disabled_capture"), "Disabled debug gate rejects capture")
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
	_check(recorder.start_capture(host, "user://capture_probes"), "Debug capture opens streams")
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
	_check(is_instance_valid(recorder) and recorder.active, "Starting an actual map automatically starts debug capture")
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
