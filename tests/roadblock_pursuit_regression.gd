extends Node

var failures: int = 0
var checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	Engine.max_fps = 0
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("Alderbrook3") as Map
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.time = scenario.duration_s / 60.0
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.DEFEND)
	var planner: PlatoonAI = world.game_controller._ai_director_for_team(Globals.Team.AXIS).platoon_ai
	var attackers: Array[Unit] = Globals.get_units_for_team(Globals.Team.AXIS)
	var defenders: Array[Unit] = Globals.get_units_for_team(Globals.Team.ALLIES)
	var exit: ExitUnitsCondition = scenario.ai_escape_policies[0].exit_condition
	exit.required_unit_count = attackers.size()
	var origins: Dictionary[Unit, Vector2i] = {}
	var members: Dictionary[Unit, int] = {}
	for unit: Unit in Globals.get_units():
		# Isolate seeing the player from damage, pinning, and suppression.
		unit.squad_fire.set_process(false)
		unit.squad_fire.set_physics_process(false)
		unit.stress_system.set_process(false)
		unit.stress_system.set_physics_process(false)
		unit.combat_stats_timer.stop()
		members[unit] = unit.members_alive
	for unit: Unit in attackers:
		origins[unit] = unit.current_hex
	var rows: Array[int] = [0, 1, 2, 11, 12, 13]
	for index: int in range(defenders.size()):
		_set_hex(defenders[index], Vector2i(19, rows[index]))
	var saw_contact: bool = false
	var pursued_player: bool = false
	var moved_player: bool = false
	var escaped_before_move: bool = false
	for frame: int in range(90 * 60):
		if frame == 6 * 60:
			escaped_before_move = exit.is_condition_met()
			var destinations: Array[Vector2i] = [Vector2i(16, 0), Vector2i(17, 0), Vector2i(18, 0), Vector2i(19, 0), Vector2i(18, 1), Vector2i(19, 1)]
			for index: int in range(defenders.size()):
				_set_hex(defenders[index], destinations[index])
			moved_player = true
		if frame >= 5 * 60 and frame % 60 == 0:
			var snapshot: InfluenceSnapshot = planner.influence_map_controller.snapshot
			for contact: InfluenceContact in snapshot.get_contacts(planner.team):
				saw_contact = saw_contact or contact.observed
			for unit: Unit in attackers:
				if unit.exited or HqSupportPositionPolicy.is_headquarters(unit):
					continue
				var advice: PositionResult = unit.position_advice
				if advice != null and advice.is_valid() and not advice.features.get("escape", false):
					pursued_player = true
		if exit.is_condition_met():
			break
		if frame >= 15 * 60 and pursued_player:
			break
		await get_tree().process_frame
	_check(saw_contact and moved_player and not escaped_before_move, "The live reproduction sees the player and then moves the player behind the escaping column")
	_check(not pursued_player, "Seeing a player behind the column never replaces escape with a fighting position or pursuit objective")
	_check(exit.state.units_exited.size() == attackers.size(), "Every rifle and headquarters leaves through the western exits instead of following the player")
	for unit: Unit in attackers:
		_check(unit.current_hex.x < origins[unit].x, "The enemy progresses west toward escape instead of closing east or north on the moving player")
	for unit: Unit in members:
		_check(unit.members_alive == members[unit] and unit.stress_system.state == STATES.MoraleState.NORMAL, "The reproduction keeps damage and pinning out of the sighting response")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Roadblock pursuit checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _set_hex(unit: Unit, cell: Vector2i) -> void:
	unit.movement.is_moving = false
	unit.clear_orders()
	unit.current_hex = cell
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(cell)
	unit.position = LOSHelper.ground_layer.map_to_local(cell)
	unit.movement.target_hex = cell
	unit.movement.target_position = unit.position


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
