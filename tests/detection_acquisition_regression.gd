extends Node

class ObserverProbe extends Unit:
	func _ready() -> void:
		set_process(false)

	func _check_contacts() -> void:
		pass


class SilentAudio extends WeaponAudio:
	func _ready() -> void:
		pass


class VisibilityProbe extends Node2D:
	var last_elapsed: float = -1.0

	func _get_concealment(hex: Vector2i, enemy: Unit) -> int:
		return MatchVisibilityCoordinator.get_concealment(self, hex, enemy)

	func _compute_detect_prob_per_tick(observer: Unit, enemy: Unit, elapsed: float) -> float:
		last_elapsed = elapsed
		return MatchVisibilityCoordinator.compute_detect_prob_per_tick(self, observer, enemy, elapsed)

	func show_visible_units() -> void:
		pass


class MatchProbe extends "res://scenes/game/match_controller.gd":
	func show_visible_units() -> void:
		pass


var failures: int = 0
var checks: int = 0


func _ready() -> void:
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_size = Vector2i(64, 64)
	ground.pathfinding_enabled = false
	add_child(ground)
	LOSHelper.ground_layer = ground
	var observer: Unit = load("res://scenes/game/units/unit.tscn").instantiate()
	observer.set_script(ObserverProbe)
	observer.get_node("WeaponAudio").set_script(SilentAudio)
	observer.process_mode = Node.PROCESS_MODE_DISABLED
	observer.team = Globals.Team.AXIS
	observer.current_hex = Vector2i(2, 2)
	observer.position = ground.map_to_local(observer.current_hex)
	observer.current_cube = ground.map_to_cube(observer.current_hex)
	observer.tactical_state = SquadTacticalState.new()
	add_child(observer)
	observer.add_to_group("units")
	var enemy: Unit = load("res://scenes/game/units/unit.tscn").instantiate()
	enemy.set_script(ObserverProbe)
	enemy.get_node("WeaponAudio").set_script(SilentAudio)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.team = Globals.Team.ALLIES
	enemy.current_hex = Vector2i(2, 4)
	enemy.current_cube = ground.map_to_cube(enemy.current_hex)
	enemy.position = ground.map_to_local(enemy.current_hex)
	enemy.tactical_state = SquadTacticalState.new()
	enemy.is_moving = true
	add_child(enemy)
	enemy.add_to_group("units")
	var controller: VisibilityProbe = VisibilityProbe.new()
	var track: EnemyTrack = EnemyTrack.new(observer, enemy)
	var tracks: Dictionary[Unit, EnemyTrack] = {enemy: track}
	Globals.unit_enemy_tracks[observer] = tracks
	Globals.unit_enemies_in_los[observer] = [enemy]
	Globals.unit_visible_enemies[observer] = []
	LOSHelper.los_lookup = {observer.current_hex: {enemy.current_hex: {"target_concealment": 0, "hindrance": 0}}}
	track.confidence = 0.9
	MatchVisibilityCoordinator.on_unit_visibility_checker_timer_timeout(controller, 0.0)
	_check(not track.is_visible and track.confidence == 0.9, "Old confidence cannot grant acquisition without exposure or a successful roll")
	MatchVisibilityCoordinator.on_unit_shooting(controller, enemy)
	_check(not track.is_visible and track.awareness == 0.0, "Firing cannot bypass normal acquisition")
	track.confidence = 0.0
	MatchVisibilityCoordinator.on_unit_visibility_checker_timer_timeout(controller, 1000.0)
	_check(track.is_visible and Globals.unit_visible_enemies[observer].has(enemy), "One successful acquisition publishes a fresh contact without a confidence gate")
	_check(track.awareness == 1.0 and track.last_known_hex == enemy.current_hex, "Acquisition records awareness and the observed location")
	MatchVisibilityCoordinator.on_unit_visibility_checker_timer_timeout(controller, 0.0)
	_check(Globals.unit_visible_enemies[observer].has(enemy), "An acquired enemy remains visible while LOS holds")
	Globals.unit_enemies_in_los[observer] = []
	MatchVisibilityCoordinator.on_unit_visibility_checker_timer_timeout(controller, 1000.0)
	_check(not track.is_visible and Globals.unit_visible_enemies[observer].is_empty(), "No amount of exposure acquires an enemy outside LOS")
	_test_distance_and_tracking(controller, observer, enemy)
	observer.surrendered = true
	enemy.current_hex = observer.current_hex
	Globals.unit_enemies_in_los[observer] = [enemy]
	MatchVisibilityCoordinator.on_unit_visibility_checker_timer_timeout(controller, 1000.0)
	_check(Globals.unit_visible_enemies[observer].is_empty(), "Surrendered observers cannot use same-hex acquisition")
	observer.surrendered = false
	MatchVisibilityCoordinator.on_unit_visibility_checker_timer_timeout(controller, 0.0)
	_check(Globals.unit_visible_enemies[observer].has(enemy), "An active observer detects same-hex enemies immediately")
	# The real match accumulates elapsed simulation time and consumes it once per refresh.
	var match_controller: MatchProbe = MatchProbe.new()
	observer.remove_from_group("units")
	match_controller.update_los_time(0.04)
	match_controller.update_los_time(0.06)
	_check(is_equal_approx(match_controller._visibility_elapsed_seconds, 0.1), "Visibility exposure accumulates actual simulation time")
	match_controller._on_unit_visibility_checker_timer_timeout()
	_check(match_controller._visibility_elapsed_seconds == 0.0, "Visibility refresh consumes elapsed exposure exactly once")
	match_controller.free()
	Globals.unit_enemy_tracks.clear()
	Globals.unit_enemies_in_los.clear()
	Globals.unit_visible_enemies.clear()
	LOSHelper.los_lookup.clear()
	controller.free()
	observer.squad_fire.calc.free()
	enemy.squad_fire.calc.free()
	observer.free()
	enemy.free()
	LOSHelper.ground_layer = null
	print("Detection acquisition regression failures: ", failures)
	print("Detection acquisition checks: ", checks)
	get_tree().quit(failures)


func _prepare_case(observer: Unit, enemy: Unit, distance: int, concealment: int, hindrance: int) -> void:
	enemy.current_cube = observer.current_cube + Vector3i(0, distance, -distance)
	enemy.current_hex = LOSHelper.ground_layer.cube_to_map(enemy.current_cube)
	enemy.position = LOSHelper.ground_layer.map_to_local(enemy.current_hex)
	enemy.is_moving = false
	enemy.squad_fire.fire_recent = 0.0
	observer.is_moving = false
	observer.members_alive = 10
	observer.original_size = 10
	observer.stress_system.state = STATES.MoraleState.NORMAL
	observer.stress_system.under_fire = false
	observer.stress_system.S_eff = 0.0
	observer.tactical_state.attention_quality = 1.0
	observer.tactical_state.attention_switch_load = 0.0
	observer.tactical_state.focus_direction = observer.position.direction_to(enemy.position)
	observer.tactical_state.focus_strength = 0.6
	observer.tactical_state.attention_width = PI
	LOSHelper.los_lookup = {observer.current_hex: {enemy.current_hex: {"target_concealment": concealment, "hindrance": hindrance}}}
	Globals.unit_enemies_in_los[observer] = [enemy]
	Globals.unit_visible_enemies[observer] = []
	Globals.unit_enemy_tracks[observer] = {} as Dictionary[Unit, EnemyTrack]


func _test_distance_and_tracking(controller: VisibilityProbe, observer: Unit, enemy: Unit) -> void:
	var original_hex: Vector2i = enemy.current_hex
	_prepare_case(observer, enemy, 14, 0, 5)
	var hindered: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, observer, enemy, 30.0)
	_check(hindered > 0.0 and hindered < 0.015, "A quiet stationary unit at 560 m behind five hindrance hexes has less than 1.5% acquisition chance in 30 seconds")
	_check(1.0 - pow(1.0 - hindered, 5.0) < 0.06, "Even five focused squads rarely acquire the heavily obscured distant unit in 30 seconds")
	_prepare_case(observer, enemy, 17, 3, 0)
	var house: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, observer, enemy, 30.0)
	_check(house > 0.0 and house < 0.005, "A quiet stationary unit in a house at 680 m has less than 0.5% acquisition chance in 30 seconds")
	_check(1.0 - pow(1.0 - house, 5.0) < 0.03, "Multiple observers cannot turn a distant concealed house into easy acquisition")
	print("Focused 30-second acquisition, 14 hexes + five hindrances / house at 17 hexes: ", hindered, " / ", house)
	var complement: float = 1.0
	for tick: int in range(300):
		complement *= 1.0 - MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, observer, enemy, 0.1)
	_check(is_equal_approx(1.0 - complement, house), "Rare distant acquisition remains independent of visibility refresh frequency")
	_prepare_case(observer, enemy, 16, 0, 0)
	var quiet: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, observer, enemy, 30.0)
	_check(quiet < 0.1, "An exposed but quiet stationary silhouette at 640 m is not routinely spotted within 30 seconds")
	enemy.is_moving = true
	var moving: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, observer, enemy, 5.0)
	_check(moving > 0.5 and moving < 0.8, "Movement in the open at 640 m remains noticeable within a useful window")
	enemy.is_moving = false
	enemy.squad_fire.fire_recent = 1.0
	var firing: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, observer, enemy, 5.0)
	_check(firing > moving, "Distant muzzle flashes provide a stronger cue than movement")
	_prepare_case(observer, enemy, 1, 0, 0)
	enemy.is_moving = true
	_check(MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, observer, enemy, 1.0) > 0.95, "A close moving target in attention still acquires promptly")
	var previous: float = 1.0
	for distance: int in [4, 8, 12, 16, 17, 24, 32, 64]:
		_prepare_case(observer, enemy, distance, 0, 0)
		var probability: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, observer, enemy, 30.0)
		_check(probability > 0.0 and probability < previous, "Quiet target range attenuation remains smooth and nonzero at " + str(distance) + " hexes")
		previous = probability
	for scenario: Vector3i in [Vector3i(14, 0, 5), Vector3i(17, 3, 0)]:
		_prepare_case(observer, enemy, scenario.x, scenario.y, scenario.z)
		var distant_track: EnemyTrack = EnemyTrack.new(observer, enemy)
		distant_track.acquire_detection()
		var distant_tracks: Dictionary[Unit, EnemyTrack] = {enemy: distant_track}
		Globals.unit_enemy_tracks[observer] = distant_tracks
		Globals.unit_visible_enemies[observer] = [enemy]
		var elapsed: float = 0.0
		for tick: int in range(70):
			# Physics may refresh a known coordinate, but cannot renew tracking evidence.
			distant_track.update_seen(0.1, float(tick) * 0.1)
			MatchVisibilityCoordinator.on_unit_visibility_checker_timer_timeout(controller, 0.1)
			elapsed += 0.1
			if not distant_track.is_visible:
				break
		_check(elapsed >= 4.9 and elapsed <= 6.0 and Globals.unit_visible_enemies[observer].is_empty(), "An acquired distant quiet contact is lost after a short grace even while geometric LOS holds")
		_check(distant_track.awareness > 0.0 and distant_track.currently_in_los, "Losing visual identification preserves remembered awareness and geometric LOS")
		var known_position: Vector2 = distant_track.last_known_global_position
		enemy.position += Vector2(20.0, 0.0)
		distant_track.update_seen(0.1, 10.0)
		_check(distant_track.last_known_global_position == known_position, "A hidden unit's position cannot continue updating through geometric LOS")
	_prepare_case(observer, enemy, 3, 0, 0)
	var close_track: EnemyTrack = EnemyTrack.new(observer, enemy)
	close_track.acquire_detection()
	var close_tracks: Dictionary[Unit, EnemyTrack] = {enemy: close_track}
	Globals.unit_enemy_tracks[observer] = close_tracks
	Globals.unit_visible_enemies[observer] = [enemy]
	for tick: int in range(60):
		MatchVisibilityCoordinator.on_unit_visibility_checker_timer_timeout(controller, 1.0)
	_check(close_track.is_visible and Globals.unit_visible_enemies[observer].has(enemy), "A clearly observable close contact remains stable for a minute without reacquisition flicker")
	close_track.acquire_detection()
	_check(close_track.maintain_detection(0.0, 2.0), "A short observation lull preserves the contact")
	close_track.maintain_detection(0.25, 2.0)
	_check(close_track.visual_contact_remaining_s == EnemyTrack.VISUAL_CONTACT_GRACE_S, "Renewed strong evidence restores tracking allowance")
	var coarse: EnemyTrack = EnemyTrack.new(observer, enemy)
	var fine: EnemyTrack = EnemyTrack.new(observer, enemy)
	coarse.acquire_detection()
	fine.acquire_detection()
	coarse.maintain_detection(0.05, 6.0)
	for tick: int in range(60):
		fine.maintain_detection(0.05, 0.1)
	_check(coarse.is_visible == fine.is_visible and is_equal_approx(coarse.visual_contact_remaining_s, fine.visual_contact_remaining_s), "Tracking allowance depends on elapsed time, not refresh count")
	# LOS loss between publication ticks cannot inherit the old visible dictionary.
	close_track.update_not_seen(0.1)
	MatchVisibilityCoordinator.on_unit_visibility_checker_timer_timeout(controller, 0.0)
	_check(not close_track.is_visible and Globals.unit_visible_enemies[observer].is_empty(), "Returning geometric LOS must reacquire after a real visibility break")
	_prepare_case(observer, enemy, 2, 0, 0)
	enemy.current_hex = original_hex
	enemy.current_cube = LOSHelper.ground_layer.map_to_cube(original_hex)
	enemy.position = LOSHelper.ground_layer.map_to_local(original_hex)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
