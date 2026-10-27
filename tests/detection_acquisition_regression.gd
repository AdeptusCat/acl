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
	get_tree().quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
