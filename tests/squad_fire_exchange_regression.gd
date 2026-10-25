extends Node

# Only the clock and observation hooks differ from the production Unit/controller.
# Acquisition, setup, reload, bursts, projectile-delay timers, impacts and damage
# all execute their real code. Visual shot signals are disconnected, not resolved again.
class ObservedUnit extends Unit:
	var simulation_time: float = 0.0
	var incoming_events: int = 0
	var received_fast: float = 0.0
	var received_slow: float = 0.0
	var fired_weapons: Dictionary[int, bool] = {}

	func _now() -> float:
		return simulation_time

	func _on_incoming_fire_effect(casualties: int, fast: float, slow: float, source: Node) -> void:
		incoming_events += 1
		received_fast += fast
		received_slow += slow
		super._on_incoming_fire_effect(casualties, fast, slow, source)

	func observe_shot(weapon: WeaponSpec, _cell: Vector2i, _origin: Vector2, _impact: Vector2) -> void:
		fired_weapons[weapon.get_instance_id()] = true

	func observe_grenade(weapon: WeaponSpec) -> void:
		fired_weapons[weapon.get_instance_id()] = true


# Counterfactual: keep attention geometry/data but omit its four new stress costs.
class NoAttentionCosts extends SquadTacticalState:
	func advance_attention(delta: float) -> Vector2:
		super.advance_attention(delta)
		return Vector2.ZERO

	func register_incoming_fire(direction: Vector2, now_seconds: float) -> Vector2:
		super.register_incoming_fire(direction, now_seconds)
		return Vector2.ZERO


class ObservedFire extends SquadFireController:
	var rounds_resolved: int = 0
	var volleys_resolved: int = 0

	func fire_at(rounds: int, weapon: WeaponSpec, grenade: bool, cell: Vector2i, distance: int, cover: int, targets: Array[Unit], origin: Vector2 = Vector2.INF) -> void:
		rounds_resolved += rounds
		volleys_resolved += 1
		super.fire_at(rounds, weapon, grenade, cell, distance, cover, targets, origin)


const UNIT_SCENE: PackedScene = preload("res://scenes/game/units/unit.tscn")
const STEP: float = 1.0 / 60.0
const FIRE_SECONDS: float = 45.0
const RECOVERY_SECONDS: float = 60.0
const SEEDS: Array[int] = [101, 202, 303, 404]
const CASES: Array[Dictionary] = [
	{"name": "covered_duel", "cover": 2, "distance": 4},
	{"name": "open_duel", "cover": 0, "distance": 4},
	{"name": "hard_cover_duel", "cover": 4, "distance": 4},
	{"name": "close_duel", "cover": 2, "distance": 2},
	{"name": "midrange_duel", "cover": 2, "distance": 3},
	{"name": "midrange_without_attention_costs", "cover": 2, "distance": 3, "no_attention": true},
	{"name": "far_duel", "cover": 2, "distance": 6},
	{"name": "defender_hq", "cover": 2, "distance": 4, "hq": true},
	{"name": "mg_vs_rifle", "cover": 2, "distance": 4, "mg": true},
	{"name": "frontal_2v1", "cover": 2, "distance": 4, "second": true},
	{"name": "crossfire_2v1", "cover": 2, "distance": 4, "second": true, "crossfire": true},
	{"name": "one_way_fire", "cover": 2, "distance": 4, "one_way": true},
]

var checks: int = 0
var failures: int = 0
var alerts: int = 0
var exchanges: int = 0
var ground: HexagonTileMapLayer
var buildings: HexagonTileMapLayer
var units: Array[ObservedUnit] = []
var fighters: Array[ObservedUnit] = []
var metrics: Dictionary[int, Dictionary] = {}
var summary: FileAccess
var timeline: FileAccess
var current_case: String
var current_seed: int
var time_s: float = 0.0
var aggregates: Dictionary[String, Array] = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	name = "Main"
	# SceneTreeTimers must advance by the same delta as the explicitly ticked nodes.
	await get_tree().process_frame
	var correct_fps: bool = is_equal_approx(get_process_delta_time(), STEP)
	_check(correct_fps, "Run this scene with --fixed-fps 60; actual delta=%s" % get_process_delta_time())
	if not correct_fps:
		get_tree().quit(1)
		return
	var world: Node = Node.new()
	world.name = "World"
	add_child(world)
	var audio: AudioPool = AudioPool.new()
	audio.name = "AudioPool"
	world.add_child(audio)
	_setup_ground()
	_open_reports()
	Debug.no_damage = false
	Debug.dont_fire_wepaons = false
	var quick: bool = OS.get_cmdline_user_args().has("--quick")
	var selected_case: String = ""
	var selected_seed: int = -1
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			selected_case = argument.trim_prefix("--case=")
		if argument.begins_with("--seed="):
			selected_seed = argument.trim_prefix("--seed=").to_int()
	for configuration: Dictionary in CASES:
		if not selected_case.is_empty() and configuration.name != selected_case:
			continue
		if quick and configuration.name not in ["covered_duel", "defender_hq"]:
			continue
		for random_seed: int in SEEDS:
			if selected_seed >= 0 and random_seed != selected_seed:
				continue
			if quick and random_seed != SEEDS[0]:
				continue
			await _exchange(configuration, random_seed)
		print("Whole-squad case completed: ", configuration.name)
	for case_name: String in aggregates:
		var totals: Array = aggregates[case_name]
		print("Whole-squad defender mean ", case_name, ": stress10=", snappedf(float(totals[0]) / float(totals[4]), 0.01), "; stress45=", snappedf(float(totals[1]) / float(totals[4]), 0.01), "; pinned_seconds=", snappedf(float(totals[2]) / float(totals[4]), 0.01), "; casualties=", snappedf(float(totals[3]) / float(totals[4]), 0.01))
	if summary != null:
		summary.close()
	if timeline != null:
		timeline.close()
	LOSHelper.ground_layer = null
	LOSHelper.building_layer = null
	_check(exchanges > 0, "Case and seed filters select at least one exchange")
	print("Whole-squad exchanges: ", exchanges)
	print("Whole-squad balance alerts: ", alerts, " (diagnostic; use --strict-balance to fail on alerts)")
	if OS.get_cmdline_user_args().has("--strict-balance"):
		failures += alerts
	print("Whole-squad exchange checks: ", checks, "; failures: ", failures)
	get_tree().quit(mini(failures, 255))


func _setup_ground() -> void:
	var template: HexagonTileMapLayer = load("res://scenes/world/maps/layers/ground_tile_map_layer.tscn").instantiate() as HexagonTileMapLayer
	ground = HexagonTileMapLayer.new()
	ground.pathfinding_enabled = false
	ground.tile_set = template.tile_set
	template.free()
	add_child(ground)
	buildings = HexagonTileMapLayer.new()
	buildings.pathfinding_enabled = false
	buildings.tile_set = ground.tile_set
	add_child(buildings)
	LOSHelper.ground_layer = ground
	LOSHelper.building_layer = buildings
	for x: int in range(-12, 13):
		for y: int in range(-12, 13):
			ground.set_cell(Vector2i(x, y), 1, Vector2i.ZERO)


func _open_reports() -> void:
	var directory: String = "user://"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			directory = argument.trim_prefix("--output=")
	summary = FileAccess.open(directory.path_join("squad_fire_exchange.csv"), FileAccess.WRITE)
	timeline = FileAccess.open(directory.path_join("squad_fire_exchange_timeline.csv"), FileAccess.WRITE)
	_check(summary != null and timeline != null, "Whole-squad CSV reports open")
	if summary != null:
		summary.store_csv_line(PackedStringArray(["case", "seed", "side", "team", "initial_members", "cover", "distance", "rounds_resolved", "volleys", "incoming_events", "stress_5s", "stress_10s", "stress_30s", "stress_45s", "peak_stress", "first_pinned_s", "losses_at_first_pin", "pinned_seconds", "panic_seconds", "casualties", "members", "cohesion", "stress_after_recovery", "recovery_below_caution_s", "weapons_fired", "losses_10s", "balance_alerts"]))
	if timeline != null:
		timeline.store_csv_line(PackedStringArray(["case", "seed", "side", "time_s", "stress", "morale", "members", "casualties", "cohesion", "rounds_resolved", "incoming_rps", "raw_attention_demand_rate", "switching_stress_rate", "surprise", "crossfire_pressure", "recovery_capacity"]))


func _create_unit(team: Globals.Team, type: Globals.SquadType, cube: Vector3i, side: String) -> ObservedUnit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.set_script(ObservedUnit)
	var observed: ObservedUnit = unit as ObservedUnit
	observed.squads_collection = load("res://resources/squads/team_squad_loadout_catalog.tres") as SquadsCollection
	observed.team = team
	observed.squad_type = type
	observed.squad = units.size() + 1
	observed.platoon = 1
	observed.current_cube = cube
	observed.current_hex = ground.cube_to_map(cube)
	observed.position = ground.map_to_local(observed.current_hex)
	observed.get_node("SquadFireController").set_script(ObservedFire)
	add_child(observed)
	observed.add_to_group("units")
	observed.squad_fire.unit = observed
	observed.squad_fire.stress_controller = observed.stress_system
	observed.setup()
	observed.squad_fire.fire_shot.disconnect(observed._on_fire_shot)
	observed.squad_fire.fire_shot.connect(observed.observe_shot)
	observed.squad_fire.fire_riflegrenade.disconnect(observed._on_fire_riflegrenade)
	observed.squad_fire.fire_riflegrenade.connect(observed.observe_grenade)
	observed.weapon_audio.shutdown()
	_freeze(observed)
	observed.hide()
	observed.squad_fire._setup_after_arriving_at_hex()
	observed.setAttackState(Unit.AttackState.MANUAL_TRACK)
	units.append(observed)
	metrics[observed.get_instance_id()] = {"side": side, "initial": observed.members_alive, "peak": 0.0, "pin": -1.0, "losses_at_pin": 0, "pinned": 0.0, "panic": 0.0, "recovery": -1.0, "stress_5": 0.0, "stress_10": 0.0, "stress_30": 0.0, "stress_45": 0.0, "losses_10": 0}
	_check(observed.squad_fire.soldiers.size() == observed.squad_loadout.soldiers.size(), "Full authored roster is present: " + side)
	return observed


func _exchange(configuration: Dictionary, random_seed: int) -> void:
	exchanges += 1
	current_case = configuration.name
	current_seed = random_seed
	seed(random_seed)
	var left_team: Globals.Team = Globals.Team.ALLIES
	if random_seed % 2 == 0:
		left_team = Globals.Team.AXIS
	var right_team: Globals.Team = Globals.get_enemy_team(left_team)
	var distance: int = int(configuration.distance)
	var right_type: Globals.SquadType = Globals.SquadType.Rifle
	if configuration.get("mg", false):
		right_type = Globals.SquadType.MG
	var left: ObservedUnit = _create_unit(left_team, Globals.SquadType.Rifle, Vector3i.ZERO, "left")
	var right: ObservedUnit = _create_unit(right_team, right_type, Vector3i(distance, -distance, 0), "right")
	fighters = [left, right]
	if configuration.get("second", false):
		var cube: Vector3i = Vector3i(distance, -distance + 1, -1)
		if configuration.get("crossfire", false):
			cube = Vector3i(-distance, distance, 0)
		fighters.append(_create_unit(right_team, Globals.SquadType.Rifle, cube, "right_second"))
	if configuration.get("hq", false):
		var hq: ObservedUnit = _create_unit(left_team, Globals.SquadType.PLATOON_HEADQUARTERS, Vector3i(-1, 0, 1), "hq")
		hq.ai_support_only = true
		left.command_squad = hq
	if configuration.get("one_way", false):
		left.ai_support_only = true
	if configuration.get("no_attention", false):
		for fighter: ObservedUnit in fighters:
			fighter.tactical_state = NoAttentionCosts.new()
	_configure_los(int(configuration.cover))
	_refresh_contacts(true)
	for fighter: ObservedUnit in fighters:
		if fighter.team == left_team:
			fighter.squad_fire.set_target_unit(right)
		else:
			fighter.squad_fire.set_target_unit(left)
	for frame: int in range(roundi((FIRE_SECONDS + RECOVERY_SECONDS) / STEP)):
		time_s = float(frame) * STEP
		var firing: bool = frame < roundi(FIRE_SECONDS / STEP)
		if frame == roundi(FIRE_SECONDS / STEP):
			_refresh_contacts(false)
			for fighter: ObservedUnit in fighters:
				fighter.squad_fire.clear_target()
		if frame % 15 == 0:
			if firing:
				_refresh_contacts(true)
			for unit: ObservedUnit in units:
				if unit.is_active():
					unit._on_command_connectivity_timeout()
					unit.leader_aura._update_aura()
					unit.combat_stats.update_stats(0.25)
		for unit: ObservedUnit in units:
			unit.simulation_time = time_s
			if unit.is_active():
				unit.tactical_state.update_attention(unit)
				unit.stress_system._process(STEP)
		if firing:
			# Alternate tick order to avoid permanently favoring one side.
			for offset: int in range(fighters.size()):
				var fighter: ObservedUnit = fighters[(offset + frame % fighters.size()) % fighters.size()]
				fighter.squad_fire._process(STEP)
		await get_tree().process_frame
		_sample(frame + 1)
	for fighter: ObservedUnit in fighters:
		var fire: ObservedFire = fighter.squad_fire as ObservedFire
		_check(fighter.squad_fire.soldiers.size() == fighter.members_alive and fighter.members_alive + fighter.casualties_taken == int(metrics[fighter.get_instance_id()].initial), "Roster conservation after exchange: " + str(metrics[fighter.get_instance_id()].side))
		if not fighter.ai_support_only:
			_check(fire.rounds_resolved > 0, "Every firing squad resolves actual rounds: " + str(metrics[fighter.get_instance_id()].side))
			if current_case == "covered_duel":
				_check(fighter.fired_weapons.size() >= 3, "The covered duel exercises multiple independently firing soldiers per squad")
		else:
			_check(fire.rounds_resolved == 0, "The one-way control does not return fire")
		if fighter == left or (fighter == right and not configuration.get("one_way", false)):
			_check(fighter.incoming_events > 0, "Every deliberately selected target receives actual deferred impacts")
		_write_summary(fighter, configuration)
	for unit: ObservedUnit in units:
		Globals.unit_visible_enemies.erase(unit)
		Globals.unit_enemies_in_los.erase(unit)
		Globals.unit_enemy_tracks.erase(unit)
		unit.leader_aura.shutdown()
	for unit: ObservedUnit in units:
		unit.squad_fire.calc.free()
		unit.free()
	units.clear()
	fighters.clear()
	metrics.clear()
	LOSHelper.los_lookup.clear()
	await get_tree().process_frame


func _configure_los(cover: int) -> void:
	LOSHelper.los_lookup.clear()
	for unit: ObservedUnit in units:
		var row: Dictionary = {}
		for other: ObservedUnit in units:
			if other != unit:
				row[other.current_hex] = {"target_cover": cover, "hindrance": 0}
		LOSHelper.los_lookup[unit.current_hex] = row


func _refresh_contacts(visible: bool) -> void:
	for unit: ObservedUnit in units:
		var enemies: Array[Unit] = []
		if visible:
			for enemy: ObservedUnit in fighters:
				if enemy.team != unit.team and enemy.is_active() and not enemy.surrendered:
					enemies.append(enemy)
		Globals.unit_visible_enemies[unit] = enemies
		Globals.unit_enemies_in_los[unit] = enemies


func _sample(frame: int) -> void:
	var seconds: float = float(frame) * STEP
	for fighter: ObservedUnit in fighters:
		var data: Dictionary = metrics[fighter.get_instance_id()]
		var stress: StressController = fighter.stress_system
		_check(is_finite(stress.S_eff) and stress.S_eff >= 0.0 and stress.S_eff <= stress.S_CAP, "Whole-squad stress stays finite and bounded")
		data.peak = maxf(float(data.peak), stress.S_eff)
		if seconds <= FIRE_SECONDS:
			if stress.state == STATES.MoraleState.PINNED:
				data.pinned = float(data.pinned) + STEP
				if float(data.pin) < 0.0:
					data.pin = seconds
					data.losses_at_pin = fighter.casualties_taken
			if stress.state == STATES.MoraleState.PANIC:
				data.panic = float(data.panic) + STEP
			for checkpoint: int in [5, 10, 30, 45]:
				if frame == checkpoint * 60:
					data["stress_%d" % checkpoint] = stress.S_eff
			if frame == 10 * 60:
				data.losses_10 = fighter.casualties_taken
		elif fighter.is_active() and stress.S_eff < stress.pin_threshold * stress.H_NORMAL_FROM_CAUTION:
			if float(data.recovery) < 0.0:
				data.recovery = seconds - FIRE_SECONDS
		else:
			data.recovery = -1.0
		if frame % 60 == 0 and timeline != null:
			var fire: ObservedFire = fighter.squad_fire as ObservedFire
			_write(timeline, [current_case, current_seed, data.side, seconds, stress.S_eff, stress.state, fighter.members_alive, fighter.casualties_taken, fighter.combat_stats.cohesion_current, fire.rounds_resolved, stress._last_pressure_rps, fighter.tactical_state.attention_stress_rate, fighter.tactical_state.switching_stress_rate, fighter.tactical_state.last_attack_surprise, fighter.tactical_state.multi_direction_pressure, stress.get_recovery_capacity()])


func _write_summary(unit: ObservedUnit, configuration: Dictionary) -> void:
	var data: Dictionary = metrics[unit.get_instance_id()]
	var case_alerts: PackedStringArray = PackedStringArray()
	# Provisional balance gates apply to the ordinary covered 1v1 engagement.
	if current_case in ["covered_duel", "midrange_duel"]:
		if float(data.pin) >= 0.0 and float(data.pin) < 5.0 and int(data.losses_at_pin) == 0:
			case_alerts.append("pinned_before_5s_without_losses")
		if float(data.pinned) > FIRE_SECONDS * 0.7:
			case_alerts.append("pinned_over_70_percent")
		if unit.is_active() and float(data.recovery) < 0.0:
			case_alerts.append("not_recovered_after_60s")
		if float(data.stress_10) >= unit.stress_system.panic_threshold and int(data.losses_10) <= 1:
			case_alerts.append("panic_level_stress_by_10s_with_few_losses")
	alerts += case_alerts.size()
	var fire: ObservedFire = unit.squad_fire as ObservedFire
	_write(summary, [current_case, current_seed, data.side, unit.team, data.initial, configuration.cover, configuration.distance, fire.rounds_resolved, fire.volleys_resolved, unit.incoming_events, data.stress_5, data.stress_10, data.stress_30, data.stress_45, data.peak, data.pin, data.losses_at_pin, data.pinned, data.panic, unit.casualties_taken, unit.members_alive, unit.combat_stats.cohesion_current, unit.stress_system.S_eff, data.recovery, unit.fired_weapons.size(), data.losses_10, ";".join(case_alerts)])
	if str(data.side) != "left":
		return
	if not aggregates.has(current_case):
		aggregates[current_case] = [0.0, 0.0, 0.0, 0.0, 0]
	var aggregate: Array = aggregates[current_case]
	aggregate[0] += float(data.stress_10)
	aggregate[1] += float(data.stress_45)
	aggregate[2] += float(data.pinned)
	aggregate[3] += unit.casualties_taken
	aggregate[4] += 1


func _write(file: FileAccess, values: Array) -> void:
	if file == null:
		return
	var row: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		row.append(str(value))
	file.store_csv_line(row)


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
