extends Node

# Controlled impacts exercise the production resolver; no rendering, AI or weapon timers.
class UnitProbe extends Unit:
	var clock_seconds: float = 0.0
	var fast_received: float = 0.0
	var slow_received: float = 0.0
	var casualties_received: int = 0
	var apply_casualty_shock: bool = false

	func _make_squad() -> void:
		pass

	func _now() -> float:
		return clock_seconds

	func set_cover(_value: int) -> void:
		pass

	func receive_fire(_value: float) -> void:
		pass

	func _on_incoming_fire_effect(casualties: int, fast: float, slow: float, _source: Node) -> void:
		fast_received = fast
		slow_received = slow
		casualties_received += casualties
		if Debug.no_damage or not is_active() or surrendered:
			return
		if apply_casualty_shock:
			stress_system.on_casualty_event(casualties)
		stress_system.apply_stress(fast, slow)


const STEP: float = 0.25
const FIRE_SECONDS: float = 30.0
const RECOVERY_SECONDS: float = 60.0
const SEED: int = 1234

var checks: int = 0
var failures: int = 0
var report: FileAccess
var ground: HexagonTileMapLayer
var buildings: HexagonTileMapLayer
var shooter: UnitProbe
var fire: SquadFireController


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var old_ground: HexagonTileMapLayer = LOSHelper.ground_layer
	var old_buildings: HexagonTileMapLayer = LOSHelper.building_layer
	var old_no_damage: bool = Debug.no_damage
	Debug.no_damage = false
	_setup_cover()
	_open_report()
	shooter = _unit()
	fire = SquadFireController.new()
	fire.unit = shooter
	# Isolate suppression comparisons from stochastic casualty stress.
	fire.stress_kill_fast_each = 0.0
	fire.stress_kill_slow_each = 0.0
	await _weapon_matrix()
	await _sustained_matrix()
	await _test_casualty_impacts()
	await _test_mortar_defense()
	_test_recovery_factors()
	_test_attention_capacity()
	fire.free()
	shooter.free()
	LOSHelper.ground_layer = old_ground
	LOSHelper.building_layer = old_buildings
	ground.free()
	buildings.free()
	Debug.no_damage = old_no_damage
	if report != null:
		report.close()
	print("Stress scenario checks: ", checks, "; failures: ", failures)
	get_tree().quit(mini(failures, 255))


func _setup_cover() -> void:
	# Real tile custom data exercises mortar's building-only cover lookup.
	var tiles: TileSet = TileSet.new()
	tiles.tile_size = Vector2i(64, 64)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(0, "cover")
	tiles.set_custom_data_layer_type(0, TYPE_INT)
	var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(Image.create(384, 64, false, Image.FORMAT_RGBA8))
	atlas.texture_region_size = Vector2i(64, 64)
	tiles.add_source(atlas, 0)
	for cover: int in range(6):
		atlas.create_tile(Vector2i(cover, 0))
		atlas.get_tile_data(Vector2i(cover, 0), 0).set_custom_data("cover", cover)
	ground = HexagonTileMapLayer.new()
	ground.tile_set = tiles
	buildings = HexagonTileMapLayer.new()
	buildings.tile_set = tiles
	LOSHelper.ground_layer = ground
	LOSHelper.building_layer = buildings


func _open_report() -> void:
	var path: String = "user://stress_scenarios.csv"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			path = argument.trim_prefix("--report=")
	report = FileAccess.open(path, FileAccess.WRITE)
	_check(report != null, "CSV report opens: " + path)
	if report != null:
		report.store_csv_line(PackedStringArray(["phase", "weapon", "profile", "cover", "range_hexes", "directions", "fast_gain", "slow_gain", "stress_at_30s", "peak_stress", "pin_threshold_seconds", "panic_threshold_seconds", "stress_after_60s_recovery", "seconds_to_below_caution", "casualty_rolls", "rounds_per_volley", "volley_interval_seconds", "morale_state", "seed", "step_seconds"]))
	print("Stress scenario report: ", ProjectSettings.globalize_path(path))


func _unit() -> UnitProbe:
	var unit: UnitProbe = UnitProbe.new()
	unit.squad_type = Globals.SquadType.Rifle
	unit.members_alive = 10
	unit.original_size = 10
	unit.stress_system = StressController.new()
	unit.add_child(unit.stress_system)
	unit.stress_system.refractory_s = 100000.0
	unit.stress_system._since_change = 0.0
	unit.tactical_state = SquadTacticalState.new()
	unit.tactical_state.focus_direction = Vector2.RIGHT
	unit.tactical_state.focus_strength = 1.0
	unit.tactical_state.attention_width = PI / 2.0
	unit.tactical_state.attention_quality = 1.0
	return unit


func _impact(target: UnitProbe, weapon: WeaponSpec, cover: int, distance: int, direction: Vector2, rounds: int, grenade: bool = false, building_cover: int = -1) -> void:
	if building_cover < 0:
		building_cover = cover
	buildings.set_cell(target.current_hex, 0, Vector2i(building_cover, 0))
	fire.base_accuracy = weapon.accuracy_base
	fire.fire_at(rounds, weapon, grenade, target.current_hex, distance, cover, [target], direction * 100.0)
	# Resolve the same deferred callback used by live impacts before sampling.
	await get_tree().process_frame


func _weapon_matrix() -> void:
	var paths: PackedStringArray = DirAccess.get_files_at("res://resources/weapons")
	paths.sort()
	var weapons: int = 0
	for filename: String in paths:
		if not filename.ends_with(".tres"):
			continue
		var weapon: WeaponSpec = load("res://resources/weapons/" + filename) as WeaponSpec
		_check(weapon != null, "Weapon resource loads: " + filename)
		if weapon == null:
			continue
		weapons += 1
		var previous_range: Dictionary[int, float] = {}
		var distances: Array[int] = [1]
		for distance: int in [maxi(2, weapon.range_hexes / 2), roundi(float(weapon.range_hexes) * 0.75), weapon.range_hexes]:
			if not distances.has(distance):
				distances.append(distance)
		distances.sort()
		for distance: int in distances:
			var previous_cover: float = INF
			for cover: int in range(6):
				var front: Vector2 = Vector2.ZERO
				for bearing: int in range(3):
					var target: UnitProbe = _unit()
					var direction: Vector2 = Vector2.RIGHT
					if bearing > 0:
						direction = Vector2.LEFT
					if bearing == 2:
						target.tactical_state.register_incoming_fire(Vector2.RIGHT, 0.0)
					seed(SEED)
					await _impact(target, weapon, cover, distance, direction, maxi(1, weapon.burst_rounds))
					var gain: Vector2 = Vector2(target.fast_received, target.slow_received)
					var label: String = "%s cover=%d range=%d bearing=%d" % [filename, cover, distance, bearing]
					_check(gain.is_finite() and gain.x >= 0.0 and gain.y >= 0.0 and gain.x <= fire.stress_max_per_volley and gain.y <= fire.stress_max_per_volley, label + " has finite bounded suppression")
					if bearing == 0:
						front = gain
						if weapon.family == WeaponSpec.Family.MORTAR and cover == 1:
							_check(target.stress_system.S_eff >= previous_cover - 0.00001, label + " mortar cover-one airburst exception increases apparent accuracy")
						else:
							_check(target.stress_system.S_eff <= previous_cover + 0.00001, label + " stronger cover does not increase stress")
						previous_cover = target.stress_system.S_eff
						if previous_range.has(cover):
							_check(target.stress_system.S_eff <= previous_range[cover] + 0.00001, label + " longer range does not increase stress")
						previous_range[cover] = target.stress_system.S_eff
					else:
						_check(gain.x >= front.x and gain.y >= front.y, label + " surprise/crossfire never reduces suppression")
						if bearing == 1:
							_check(is_equal_approx(gain.y, front.y), label + " surprise affects fast stress only")
					var labels: Array[String] = ["front", "rear", "crossfire"]
					var direction_count: int = 1
					if bearing == 2:
						direction_count = 2
					_write(["impact", filename, labels[bearing], cover, distance, direction_count, gain.x, gain.y, target.stress_system.S_eff, target.stress_system.S_eff, -1, -1, -1, -1, target.casualties_received, maxi(1, weapon.burst_rounds), 0, target.stress_system.state])
					target.free()
		if weapon.can_fire_riflegrenades:
			var target: UnitProbe = _unit()
			await _impact(target, weapon, 2, weapon.riflegrenade_range, Vector2.LEFT, 1, true)
			_check(target.fast_received > 0.0 and target.slow_received > 0.0, filename + " rifle grenade generates both stress bins")
			_write(["impact", filename, "rifle_grenade", 2, weapon.riflegrenade_range, 1, target.fast_received, target.slow_received, target.stress_system.S_eff, target.stress_system.S_eff, -1, -1, -1, -1, target.casualties_received, 1, 0, target.stress_system.state])
			target.free()
	_check(weapons >= 19, "Matrix covers the complete current weapon catalog")


func _sustained_matrix() -> void:
	# Equal controlled volley cadence exposes stress balance independently of aim/reload AI.
	for filename: String in ["m1_garand", "mg34", "m2_60mm_mortar"]:
		var weapon: WeaponSpec = load("res://resources/weapons/" + filename + ".tres") as WeaponSpec
		var reference: Dictionary = {}
		for cover: int in [0, 2, 4]:
			for directions: int in [1, 2, 3]:
				var baseline: Dictionary = await _simulate(weapon, cover, directions, "unsupported")
				var supported: Dictionary = await _simulate(weapon, cover, directions, "nearby_hq")
				_check(float(supported.end) <= float(baseline.end) + 0.00001, "Nearby HQ reduces sustained stress: %s cover=%d directions=%d" % [filename, cover, directions])
				if cover == 2 and directions == 2:
					reference = baseline
		for profile: String in ["radio_hq", "platoon_hq", "company_hq", "pinned", "panic", "poor_cohesion", "casualties", "leader_loss", "overload", "switching", "high_volume", "stressed_shooter"]:
			var result: Dictionary = await _simulate(weapon, 2, 2, profile)
			if profile in ["poor_cohesion", "casualties", "leader_loss", "overload", "switching", "high_volume"]:
				_check(float(result.end) >= float(reference.end), filename + ": adverse influence raises sustained stress: " + profile)
			if profile in ["platoon_hq", "company_hq", "stressed_shooter"]:
				_check(float(result.end) <= float(reference.end), filename + ": protective influence lowers sustained stress: " + profile)
			if profile == "radio_hq":
				_check(float(result.end) < float(reference.end), filename + ": radio presence improves gain protection and recovery even in normal morale")


func _simulate(weapon: WeaponSpec, cover: int, directions: int, profile: String) -> Dictionary:
	var target: UnitProbe = _unit()
	var stress: StressController = target.stress_system
	match profile:
		"nearby_hq":
			stress.leader_presence_strength = _presence(true, true, false)
			stress.add_leadership_source(1, 0.15, 0.1, 1.05)
		"radio_hq":
			stress.leader_presence_strength = _presence(false, false, true)
		"platoon_hq":
			target.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
		"company_hq":
			target.squad_type = Globals.SquadType.COMPANY_HEADQUARTERS
		"pinned":
			stress.state = STATES.MoraleState.PINNED
		"panic":
			stress.state = STATES.MoraleState.PANIC
		"poor_cohesion":
			stress.cohesion = 0.3
		"casualties", "leader_loss":
			target.members_alive = 9
			stress.on_casualty_event(1, profile == "leader_loss")
		"overload":
			target.tactical_state.attention_stress_rate = 4.0
	shooter.stress_system.stress_fast = 0.0
	shooter.stress_system.stress_slow = 0.0
	shooter.stress_system.S_eff = 0.0
	if profile == "stressed_shooter":
		shooter.stress_system.stress_fast = 80.0
		shooter.stress_system.stress_slow = 80.0
		shooter.stress_system.S_eff = 80.0
	var peak: float = 0.0
	var pin_time: float = -1.0
	var panic_time: float = -1.0
	var volley: int = 0
	var interval_steps: int = 8
	if profile == "high_volume":
		interval_steps = 2
	seed(SEED)
	for tick: int in range(roundi(FIRE_SECONDS / STEP)):
		target.clock_seconds = float(tick) * STEP
		target.tactical_state.update_fire_pressure(target.clock_seconds)
		if tick % interval_steps == 0:
			var direction: Vector2 = Vector2.RIGHT.rotated(float(volley % directions) * TAU / float(directions))
			if profile == "switching":
				target.tactical_state.total_directional_demand = 1.0
				target.tactical_state.focus_direction = direction
			await _impact(target, weapon, cover, maxi(2, weapon.range_hexes / 2), direction, maxi(1, weapon.burst_rounds))
			volley += 1
		peak = maxf(peak, stress.S_eff)
		if pin_time < 0.0 and stress.S_eff >= stress.pin_threshold:
			pin_time = target.clock_seconds
		if panic_time < 0.0 and stress.S_eff >= stress.panic_threshold:
			panic_time = target.clock_seconds
		var before: float = stress.S_eff
		stress._process(STEP)
		peak = maxf(peak, stress.S_eff)
		if pin_time < 0.0 and stress.S_eff >= stress.pin_threshold:
			pin_time = target.clock_seconds + STEP
		if panic_time < 0.0 and stress.S_eff >= stress.panic_threshold:
			panic_time = target.clock_seconds + STEP
		_check(is_finite(stress.S_eff) and stress.S_eff >= 0.0 and stress.S_eff <= stress.S_CAP, "Sustained stress stays bounded: " + profile)
		if profile != "overload" and profile != "switching":
			_check(stress.S_eff <= before + 0.00001, "Recovery tick cannot invent stress: " + profile)
	var end: float = stress.S_eff
	target.tactical_state.attention_stress_rate = 0.0
	target.tactical_state.total_directional_demand = 0.0
	target.tactical_state.attention_switch_load = 0.0
	var recovery_time: float = -1.0
	if end < stress.pin_threshold * stress.H_NORMAL_FROM_CAUTION:
		recovery_time = 0.0
	for tick: int in range(roundi(RECOVERY_SECONDS / STEP)):
		var before: float = stress.S_eff
		stress._process(STEP)
		_check(stress.S_eff <= before + 0.00001, "Stress falls after all input stops: " + profile)
		if recovery_time < 0.0 and stress.S_eff < stress.pin_threshold * stress.H_NORMAL_FROM_CAUTION:
			recovery_time = float(tick + 1) * STEP
	_write(["sustained", weapon.resource_path.get_file(), profile, cover, maxi(2, weapon.range_hexes / 2), directions, -1, -1, end, peak, pin_time, panic_time, stress.S_eff, recovery_time, target.casualties_received, maxi(1, weapon.burst_rounds), float(interval_steps) * STEP, stress.state])
	var result: Dictionary = {"end": end, "recovered": stress.S_eff}
	target.free()
	return result


func _presence(sight: bool, voice: bool, radio: bool) -> float:
	var link: CommandConnectivity = CommandConnectivity.new()
	link.command_unit_state = STATES.MoraleState.NORMAL
	link.los_to_leader = sight
	link.voice_range_to_leader = voice
	link.radio_link_to_leader = radio
	var presence: float = link.leader_presence_strength
	link.free()
	return presence


func _test_casualty_impacts() -> void:
	var weapon: WeaponSpec = load("res://resources/weapons/mg34.tres") as WeaponSpec
	shooter.stress_system.S_eff = 0.0
	var suppressed: UnitProbe = _unit()
	seed(SEED)
	await _impact(suppressed, weapon, 0, 1, Vector2.LEFT, 100)
	var defaults: SquadFireController = SquadFireController.new()
	fire.stress_kill_fast_each = defaults.stress_kill_fast_each
	fire.stress_kill_slow_each = defaults.stress_kill_slow_each
	defaults.free()
	var shocked: UnitProbe = _unit()
	shocked.apply_casualty_shock = true
	seed(SEED)
	await _impact(shocked, weapon, 0, 1, Vector2.LEFT, 100)
	_check(shocked.casualties_received > 0 and shocked.casualties_received == suppressed.casualties_received, "Seeded casualty stress leaves casualty rolls unchanged")
	_check(shocked.fast_received > suppressed.fast_received and shocked.slow_received > suppressed.slow_received, "Actual casualties add shock beyond suppression")
	_check(shocked.fast_received <= fire.stress_max_per_volley + fire.stress_kill_max_per_volley and shocked.slow_received <= fire.stress_max_per_volley + fire.stress_kill_max_per_volley, "Real casualty volleys respect separate suppression/shock caps")
	_check(shocked.stress_system.get_recovery_capacity() < suppressed.stress_system.get_recovery_capacity(), "Impact casualties slow subsequent recovery")
	suppressed.free()
	shocked.free()
	fire.stress_kill_fast_each = 0.0
	fire.stress_kill_slow_each = 0.0


func _test_mortar_defense() -> void:
	var weapon: WeaponSpec = load("res://resources/weapons/m2_60mm_mortar.tres") as WeaponSpec
	var exposed: UnitProbe = _unit()
	var terrain: UnitProbe = _unit()
	var building: UnitProbe = _unit()
	var airburst: UnitProbe = _unit()
	for target: UnitProbe in [exposed, terrain, building, airburst]:
		seed(SEED)
		if target == exposed:
			await _impact(target, weapon, 0, 15, Vector2.RIGHT, 1, false, 0)
		elif target == terrain:
			await _impact(target, weapon, 5, 15, Vector2.RIGHT, 1, false, 0)
		elif target == building:
			await _impact(target, weapon, 5, 15, Vector2.RIGHT, 1, false, 5)
		else:
			await _impact(target, weapon, 1, 15, Vector2.RIGHT, 1, false, 1)
	_check(is_equal_approx(exposed.stress_system.S_eff, terrain.stress_system.S_eff), "Mortars ignore ordinary terrain cover when building cover is absent")
	_check(building.stress_system.S_eff < exposed.stress_system.S_eff, "Building cover protects against mortar stress")
	_check(airburst.stress_system.S_eff > exposed.stress_system.S_eff, "Mortar cover-one airburst exception is exercised without accuracy saturation")
	for target: UnitProbe in [exposed, terrain, building, airburst]:
		target.free()


func _test_recovery_factors() -> void:
	var target: UnitProbe = _unit()
	var stress: StressController = target.stress_system
	for state: STATES.MoraleState in [STATES.MoraleState.NORMAL, STATES.MoraleState.CAUTIOUS, STATES.MoraleState.PINNED, STATES.MoraleState.PANIC, STATES.MoraleState.COMBAT_INEFFECTIVE]:
		stress.state = state
		stress.leader_presence_strength = 0.0
		var alone: float = stress.get_recovery_capacity()
		stress.leader_presence_strength = _presence(false, false, true)
		var radio: float = stress.get_recovery_capacity()
		stress.leader_presence_strength = _presence(true, true, false)
		_check(stress.get_recovery_capacity() >= radio and radio >= alone, "HQ presence improves recovery in morale state %d" % state)
	stress.state = STATES.MoraleState.NORMAL
	stress.leader_presence_strength = 0.0
	var baseline: float = stress.get_recovery_capacity()
	stress.on_casualty_event(1)
	var casualty: float = stress.get_recovery_capacity()
	stress.on_casualty_event(0, true)
	_check(stress.get_recovery_capacity() < casualty and casualty < baseline, "Casualties and leader loss compound recovery shock")
	stress._casualty_recovery_t = 0.0
	_check(is_equal_approx(stress.get_recovery_capacity(), baseline), "Expired casualty shock restores recovery")
	stress.mark_under_fire(1.0)
	var light: float = stress.get_recovery_capacity()
	stress.mark_under_fire(stress.pressure_ref_rps)
	_check(stress.get_recovery_capacity() < light and light < baseline, "Volume suppresses recovery")
	stress.recovery_scale = 0.0
	_check(stress.get_recovery_capacity() == 0.0, "Disabled recovery has no capacity")
	target.free()


func _test_attention_capacity() -> void:
	var target: UnitProbe = _unit()
	var enemies: Array[Unit] = []
	for index: int in range(3):
		var enemy: UnitProbe = _unit()
		enemy.team = Globals.get_enemy_team(target.team)
		enemy.position = Vector2.RIGHT.rotated(float(index) * TAU / 3.0) * 100.0
		enemy.squad_fire = SquadFireController.new()
		enemy.add_child(enemy.squad_fire)
		enemy.squad_fire.fire_recent = 1.0
		target.tactical_state.register_incoming_fire(enemy.position, target._now())
		enemies.append(enemy)
	Globals.unit_visible_enemies[target] = enemies
	target.tactical_state.update_attention(target)
	var full_capacity: float = target.tactical_state.attention_capacity
	_check(target.tactical_state.flanked and target.tactical_state.surrounded and target.tactical_state.attention_stress_rate > 0.0, "Real surrounding contacts generate overload and tactical conditions")
	target.members_alive = 3
	target.tactical_state.update_attention(target)
	_check(target.tactical_state.attention_capacity < full_capacity, "Loss of observers reduces attention capacity")
	var reduced_capacity: float = target.tactical_state.attention_capacity
	target.stress_system.state = STATES.MoraleState.PINNED
	target.tactical_state.update_attention(target)
	_check(target.tactical_state.attention_capacity < reduced_capacity, "Pinned morale further reduces attention capacity")
	target.stress_system.state = STATES.MoraleState.NORMAL
	target.combat_stats = UnitCombatStats.new()
	target.add_child(target.combat_stats)
	target.combat_stats.cohesion_current = 0.3
	target.tactical_state.update_attention(target)
	_check(target.tactical_state.attention_capacity < reduced_capacity, "Poor combat cohesion reduces observation capacity")
	var low_cohesion_capacity: float = target.tactical_state.attention_capacity
	target.stress_system.S_eff = 80.0
	target.tactical_state.update_attention(target)
	_check(target.tactical_state.attention_capacity < low_cohesion_capacity, "Existing stress further reduces observation capacity")
	Globals.unit_visible_enemies.erase(target)
	target.free()
	for enemy: Unit in enemies:
		enemy.free()


func _write(values: Array) -> void:
	if report == null:
		return
	var row: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		row.append(str(value))
	row.append(str(SEED))
	row.append(str(STEP))
	report.store_csv_line(row)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
