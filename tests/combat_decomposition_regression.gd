extends Node

# Exercises the real targeting and impact algorithms. Only the presentation and
# final deferred effect receiver are probes; fire_at() itself is never overridden.
const FIXTURE_PATH: String = "res://tests/fixtures/combat_decomposition_baseline.json"

class TargetProbe extends Unit:
	var events: Array[Dictionary] = []
	var orders: Array[String] = []

	func _make_squad() -> void:
		pass

	func set_cover(value: int) -> void:
		current_cover_bonus = value
		events.append({"cover": value})

	func receive_fire(value: float) -> void:
		events.append({"received": value})

	func order(_command: Globals.UnitCmd, target: Variant) -> void:
		if target == null:
			orders.append("cleared")
		else:
			orders.append(str(target.name))

	func _on_incoming_fire_effect(casualties: int, fast: float, slow: float, source: Node) -> void:
		events.append({
			"casualties": casualties, "fast": snappedf(fast, 0.000001),
			"slow": snappedf(slow, 0.000001), "original_source": source == get_parent().get_node("Shooter").squad_fire,
		})


var failures: int = 0
var main: Node
var shooter: TargetProbe
var targets: Array[TargetProbe] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	for unit: Unit in Globals.get_units():
		unit.remove_from_group("units")
	shooter = _create_unit("Shooter", Globals.Team.AXIS)
	for index: int in range(3):
		var team: Globals.Team = Globals.Team.ALLIES
		if index == 2:
			team = Globals.Team.AXIS
		targets.append(_create_unit("Target%d" % index, team))
	var observations: Dictionary = {"math": _observe_math(), "targeting": _observe_targeting()}
	var impacts: Dictionary = {}
	for variant: int in range(6):
		for reverse_order: bool in [false, true]:
			for random_seed: int in [0, 77]:
				var key: String = "%d/%s/%d" % [variant, reverse_order, random_seed]
				impacts[key] = await _observe_impact(variant, reverse_order, random_seed)
	observations["impacts"] = impacts
	if OS.get_cmdline_user_args().has("--record-baseline"):
		var file: FileAccess = FileAccess.open("user://combat_decomposition_baseline.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(observations, "\t"))
		print("Combat baseline: ", ProjectSettings.globalize_path("user://combat_decomposition_baseline.json"))
	else:
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
		var normalized: Dictionary = JSON.parse_string(JSON.stringify(observations))
		_check(normalized["math"] == expected["math"], "Fire policy boundary behavior")
		_check(normalized["targeting"] == expected["targeting"], "Target order, filtering and cover side effects")
		for key: String in impacts:
			_check(normalized["impacts"][key] == expected["impacts"][key], "Impact effects, deferral and RNG continuation: " + key)
	Globals.unit_visible_enemies.clear()
	Globals.unit_enemy_tracks.clear()
	Globals.unit_enemies_in_los.clear()
	shooter.free()
	for target: TargetProbe in targets:
		target.free()
	targets.clear()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Combat decomposition regression failures: ", failures)
	get_tree().quit(failures)


func _observe_math() -> Dictionary:
	var fire: SquadFireController = shooter.squad_fire
	var cover: Array[float] = []
	for value: float in [-1.0, 0.0, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 7.0]:
		cover.append(fire.cover_multiplier_exp(value))
	return {
		"cover": cover, "mean": fire._get_mean_change_to_hit([0.1, 0.8, 0.3], 3),
		"support": [fire.compute_support_efficiency(0, 0), fire.compute_support_efficiency(0, 2),
			fire.compute_support_efficiency(1, 2), fire.compute_support_efficiency(2, 2), fire.compute_support_efficiency(6, 2)],
	}


func _observe_targeting() -> Dictionary:
	var result: Dictionary = {}
	var rifle: WeaponSpec = WeaponSpec.new()
	rifle.range_hexes = 10
	shooter.squad_fire.set_soldiers([Soldier.new(0, "Rifle", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, rifle, shooter, shooter.team)])
	_set_hex(shooter, Vector2i.ZERO)
	_set_hex(targets[0], Vector2i(2, 0))
	_set_hex(targets[1], Vector2i(4, 0))
	_set_hex(targets[2], Vector2i(9, 0))
	LOSHelper.los_lookup = {Vector2i.ZERO: {Vector2i(2, 0): {"target_cover": 0}, Vector2i(4, 0): {"target_cover": 1}}}
	Globals.unit_visible_enemies = {shooter: [targets[1], targets[0]]}
	result["ranking"] = _choose_target()
	_set_hex(targets[1], targets[0].current_hex)
	result["tie"] = _choose_target()
	_set_hex(targets[1], Vector2i(4, 0))
	_set_hex(targets[2], targets[0].current_hex)
	result["friendly_blocks"] = _choose_target()
	targets[2].surrendered = true
	result["prisoner_allows"] = _choose_target()
	targets[0].alive = false
	result["dead_target"] = _choose_target()
	targets[1].surrendered = true
	shooter.squad_fire.target_unit = targets[0]
	result["clear_invalid"] = _choose_target()
	targets[0].alive = true
	targets[1].surrendered = false
	targets[2].surrendered = false
	_set_hex(targets[0], Vector2i(40, 0))
	_set_hex(targets[1], Vector2i(41, 0))
	result["out_of_range"] = _choose_target()
	return result


func _choose_target() -> Dictionary:
	shooter.orders.clear()
	for target: TargetProbe in targets:
		target.events.clear()
	shooter.squad_fire.fire_timer = 0.0
	shooter.squad_fire.handle_auto_fire(0.1, shooter, shooter.current_hex, 10, 0.75, 1.0)
	return {"orders": shooter.orders.duplicate(), "timer": shooter.squad_fire.fire_timer,
		"cover_effects": [targets[0].events.duplicate(), targets[1].events.duplicate(), targets[2].events.duplicate()]}


func _observe_impact(variant: int, reverse_order: bool, random_seed: int) -> Dictionary:
	var weapon: WeaponSpec = WeaponSpec.new()
	weapon.range_hexes = 12
	weapon.he_burst_radius = 5.0
	weapon.he_suppression_power = 18.0
	var distance: int = 1
	var cover: int = 0
	var rounds: int = 30
	var grenade: bool = false
	if variant == 1:
		distance = 6
		cover = 3
		rounds = 8
	elif variant == 2:
		distance = 18
		cover = 7
		rounds = 8
	elif variant == 3:
		weapon.ammo_type = WeaponSpec.AmmoType.HE
		weapon.family = WeaponSpec.Family.SPIGOT_LAUNCHER
		rounds = 3
	elif variant == 4:
		grenade = true
		distance = 3
		cover = 1
		rounds = 4
	elif variant == 5:
		weapon.ammo_type = WeaponSpec.AmmoType.HE
		weapon.family = WeaponSpec.Family.MORTAR
		distance = 4
		cover = 4
		rounds = 4
	for index: int in range(targets.size()):
		_set_hex(targets[index], Vector2i(11, 10))
		targets[index].events.clear()
		targets[index].members_alive = 5 - 2 * index
		targets[index].stress_system.state = [STATES.MoraleState.NORMAL, STATES.MoraleState.PANIC, STATES.MoraleState.PINNED][index]
	shooter.stress_system.state = STATES.MoraleState.CAUTIOUS
	shooter.stress_system.S_eff = 30.0
	shooter.squad_fire.fire_recent = 0.0
	var batch: Array[Unit] = [targets[0], targets[1]]
	if reverse_order:
		batch.reverse()
	seed(random_seed)
	shooter.squad_fire.fire_at(rounds, weapon, grenade, targets[0].current_hex, distance, cover, batch)
	var tail: float = randf()
	for target: TargetProbe in targets:
		_check(target.events.size() == 2, "Impact suppression/cover runs immediately but casualties remain deferred")
	_check(batch.size() == 3 and batch[2] == targets[2], "Impact appends the current friendly occupant to the original batch")
	await get_tree().process_frame
	var events: Array = []
	for target: TargetProbe in targets:
		events.append(target.events.duplicate(true))
		_check(target.events.size() == 3 and target.events[2]["original_source"], "Deferred effect retains the original controller source")
	return {"events": events, "rng_tail": tail, "fire_recent": shooter.squad_fire.fire_recent,
		"pressure": [targets[0].stress_system._last_pressure_rps, targets[1].stress_system._last_pressure_rps, targets[2].stress_system._last_pressure_rps]}


func _create_unit(label: String, team: Globals.Team) -> TargetProbe:
	var scene: PackedScene = load("res://scenes/game/units/unit.tscn") as PackedScene
	var unit: Unit = scene.instantiate() as Unit
	unit.set_script(TargetProbe)
	var probe: TargetProbe = unit as TargetProbe
	probe.name = label
	probe.team = team
	add_child(probe)
	_freeze(probe)
	probe.add_to_group("units")
	return probe


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
