extends Node


class UnitProbe extends Unit:
	func _ready() -> void:
		pass

	func _make_squad() -> void:
		pass


class AudioProbe extends WeaponAudio:
	func _ready() -> void:
		pass


class ActionProbe extends SquadActionController:
	var commanded_path: Array[Vector3i] = []
	var commanded_hex: Vector2i

	func give_move_to_hex_order(target: Vector2i, path: Array[Vector3i], _take_and_hold: bool) -> void:
		commanded_hex = target
		commanded_path = path


class RecorderProbe extends EngagementRecorder:
	var recorded: Dictionary = {}

	func tracks(_unit: Unit) -> bool:
		return true

	func record_event(kind: String, data: Dictionary) -> int:
		recorded = {"type": kind, "data": data}
		return 1


var checks: int = 0
var failures: int = 0
var ground: HexagonTileMapLayer
var buildings: HexagonTileMapLayer
var own: UnitProbe
var enemy: UnitProbe
var start: Vector2i = Vector2i(1, 3)
var finish: Vector2i = Vector2i(5, 3)
var direct: Array[Vector2i] = [Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)]
var detour: Array[Vector2i] = [Vector2i(1, 3), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(5, 3)]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	ThreatMap.set_process(false)
	ground = _layer()
	buildings = _layer()
	LOSHelper.ground_layer = ground
	LOSHelper.building_layer = buildings
	LOSHelper.wall_layer = null
	own = _unit(Globals.Team.ALLIES, start)
	enemy = _unit(Globals.Team.AXIS, Vector2i(3, 6))
	enemy.firepower = 16
	enemy.weapon_range = 12
	_test_knowledge()
	_test_capability()
	_test_route_tradeoff()
	_test_crossing_time()
	_test_command_and_topology()
	_test_route_logging()
	_test_large_map()
	Globals.unit_visible_enemies.clear()
	Globals.astars.clear()
	LOSHelper.los_lookup.clear()
	LOSHelper.ground_layer = null
	LOSHelper.building_layer = null
	print("Move path checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _layer() -> HexagonTileMapLayer:
	var layer: HexagonTileMapLayer = HexagonTileMapLayer.new()
	layer.tile_set = TileSet.new()
	layer.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	layer.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	layer.tile_set.tile_size = Vector2i(64, 64)
	layer.pathfinding_enabled = false
	var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(64, 64)
	atlas.create_tile(Vector2i.ZERO)
	layer.tile_set.add_source(atlas, 0)
	add_child(layer)
	return layer


func _unit(team: Globals.Team, cell: Vector2i) -> UnitProbe:
	var node: Node = load("res://scenes/game/units/unit.tscn").instantiate()
	node.set_script(UnitProbe)
	var unit: UnitProbe = node as UnitProbe
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.team = team
	unit.current_hex = cell
	unit.position = ground.map_to_local(cell)
	unit.members_alive = 10
	unit.original_size = 10
	unit.get_node("WeaponAudio").set_script(AudioProbe)
	unit.get_node("SquadActionController").free()
	var action: ActionProbe = ActionProbe.new()
	action.name = "SquadActionController"
	action.unit = unit
	unit.add_child(action)
	add_child(unit)
	unit.add_to_group("units")
	unit.movement.unit = unit
	unit.squad_fire.calc.free()
	unit.squad_fire = null
	return unit


func _graph(paths: Array) -> void:
	ground.astar = AStar2D.new()
	var ids: Dictionary[Vector2i, int] = {}
	for route: Array[Vector2i] in paths:
		for cell: Vector2i in route:
			if not ids.has(cell):
				ids[cell] = ids.size()
				ground.astar.add_point(ids[cell], ground.map_to_local(cell))
				ground.set_cell(cell, 0, Vector2i.ZERO)
		for index: int in range(1, route.size()):
			ground.astar.connect_points(ids[route[index - 1]], ids[route[index]])
	Globals.astars[own.team] = ground.astar
	Globals.astars[enemy.team] = ground.astar
	LOSHelper.los_lookup.clear()
	for cell: Vector2i in ids:
		var lanes: Dictionary = {}
		for other: Vector2i in ids:
			lanes[other] = {"wall_cover": 0, "target_cover": 0, "hindrance": 0}
		LOSHelper.los_lookup[cell] = lanes
	var danger: Dictionary = {}
	for cell: Vector2i in direct.slice(1, -1):
		danger[cell] = {"target_cover": 0, "hindrance": 0}
	LOSHelper.los_lookup[enemy.current_hex] = danger


func _path() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cube: Vector3i in MovementSystem._compute_path(start, finish, own.team, own):
		result.append(ground.cube_to_map(cube))
	return result


func _test_knowledge() -> void:
	_graph([direct, detour])
	Globals.unit_visible_enemies[own] = []
	Globals.unit_visible_enemies[enemy] = [own]
	_check(ThreatMap.capture_contacts(own.team).is_empty() and _path() == direct, "A never-spotted enemy does not affect the route")
	Globals.unit_visible_enemies[own] = [enemy]
	var contacts: Array[InfluenceContact] = ThreatMap.capture_contacts(own.team)
	_check(contacts.size() == 1 and contacts[0].observed and _path() == detour, "Observed effective fire justifies a moderate detour")
	own.remember_enemy(enemy)
	Globals.unit_visible_enemies[own] = []
	var old_hex: Vector2i = enemy.current_hex
	enemy.current_hex = Vector2i(12, 10)
	enemy.firepower = 0
	enemy.stress_system.state = STATES.MoraleState.PANIC
	contacts = ThreatMap.capture_contacts(own.team)
	_check(contacts[0].hex == old_hex and not contacts[0].observed and _path() == detour, "Memory retains the last seen position and capability without tracking hidden movement or suppression")
	enemy.alive = false
	enemy.exited = true
	_check(_path() == detour, "An unseen death or exit does not reveal that a remembered firing lane is clear")
	enemy.alive = true
	enemy.exited = false
	var remembered: float = ThreatMap.risk_at(direct[2], contacts, LOSHelper.los_lookup)
	var memory: Dictionary = own.enemy_memory.get(enemy)
	memory["last_seen_time"] = float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second) - Unit.ENEMY_MEMORY_LIFETIME * 0.75
	contacts = ThreatMap.capture_contacts(own.team)
	_check(ThreatMap.risk_at(direct[2], contacts, LOSHelper.los_lookup) < remembered, "Remembered threat loses confidence with age")
	memory["last_seen_time"] -= Unit.ENEMY_MEMORY_LIFETIME
	_check(ThreatMap.capture_contacts(own.team).is_empty() and _path() == direct, "Expired memory releases the old firing lane")
	enemy.current_hex = old_hex
	enemy.firepower = 16
	enemy.stress_system.state = STATES.MoraleState.NORMAL
	own.enemy_memory.clear()
	Globals.unit_visible_enemies[own] = []
	ThreatMap.update_astart_for_team(own.team)
	_check(is_equal_approx(ThreatMap.current_threat_maps[own.team][direct[2]], 1.0), "The legacy threat overlay also excludes hidden enemies")


func _test_capability() -> void:
	Globals.unit_visible_enemies[own] = [enemy]
	var active_risk: float = ThreatMap.risk_at(direct[2], ThreatMap.capture_contacts(own.team), LOSHelper.los_lookup)
	enemy.stress_system.state = STATES.MoraleState.PINNED
	_check(ThreatMap.risk_at(direct[2], ThreatMap.capture_contacts(own.team), LOSHelper.los_lookup) < active_risk, "Observed suppression reduces movement threat")
	enemy.stress_system.state = STATES.MoraleState.PANIC
	_check(is_zero_approx(ThreatMap.risk_at(direct[2], ThreatMap.capture_contacts(own.team), LOSHelper.los_lookup)), "A panicking observed squad exerts no effective fire threat")
	enemy.stress_system.state = STATES.MoraleState.NORMAL
	enemy.weapon_range = 1
	_check(_path() == direct, "An out-of-range enemy does not impose a detour")
	enemy.weapon_range = 12
	LOSHelper.los_lookup[enemy.current_hex][direct[2]]["target_cover"] = 3
	LOSHelper.los_lookup[enemy.current_hex][direct[2]]["hindrance"] = 2
	_check(ThreatMap.risk_at(direct[2], ThreatMap.capture_contacts(own.team), LOSHelper.los_lookup) < active_risk, "Cover and hindrance reduce incoming danger")
	_graph([direct, detour])
	var fire: SquadFireController = SquadFireController.new()
	var rifle: Soldier = Soldier.new(0, "Rifle", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, WeaponSpec.new(), enemy, enemy.team)
	rifle.weapon.range_hexes = 2
	var machine_gun: Soldier = Soldier.new(1, "MG", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, WeaponSpec.new(), enemy, enemy.team)
	machine_gun.weapon.range_hexes = 8
	fire.soldiers = [rifle, machine_gun]
	enemy.squad_fire = fire
	var contact: InfluenceContact = ThreatMap.capture_contacts(own.team)[0]
	_check(contact.movement_firepower_by_range[1] > contact.movement_firepower_by_range[4], "Range-specific capability excludes short-range weapons at distance")
	machine_gun.weapon.ammunition = 0
	rifle.weapon.ammunition = 0
	_check(is_zero_approx(ThreatMap.risk_at(direct[2], ThreatMap.capture_contacts(own.team), LOSHelper.los_lookup)), "An observed squad without ammunition exerts no fire threat")
	enemy.squad_fire = null
	fire.free()


func _test_route_tradeoff() -> void:
	_graph([direct, detour])
	Globals.unit_visible_enemies[own] = [enemy]
	_check(_path() == detour, "Route selection trades additional travel time for lower exposure")
	enemy.firepower = 1
	enemy.combat_stats.combat_effectiveness = 0.1
	_check(_path() == direct, "A small danger does not justify a large relative detour")
	var route: MoveRoutePlanner = MoveRoutePlanner.new()
	route.build(start, finish, own.team, own.movement, ThreatMap.capture_contacts(own.team), own.position)
	_check(route.travel_seconds > 0.0 and route.exposure_seconds > 0.0 and is_equal_approx(route.cost, route.travel_seconds + MoveRoutePlanner.RISK_WEIGHT * route.exposure_seconds), "Route diagnostics use the same time and exposure cost as the search")
	_graph([direct])
	enemy.firepower = 100
	enemy.combat_stats.combat_effectiveness = 1.0
	_check(_path() == direct, "A dangerous but reachable explicit destination is not rejected by defensive exposure limits")
	enemy.firepower = 16


func _test_crossing_time() -> void:
	_graph([direct, detour])
	Globals.unit_visible_enemies[own] = []
	var baseline: float = own.movement.estimate_crossing_seconds(start, direct[1])
	buildings.set_cell(direct[1], 0, Vector2i.ZERO)
	_check(is_equal_approx(own.movement.estimate_crossing_seconds(start, direct[1]), baseline * 2.0), "Building entry uses the execution movement factor")
	for cell: Vector2i in direct.slice(1, -1):
		buildings.set_cell(cell, 0, Vector2i.ZERO)
	_check(_path() == detour, "A longer open route can arrive sooner than a short slow route through buildings")
	buildings.clear()
	LOSHelper.los_lookup[start][direct[1]]["wall_cover"] = 2
	_check(is_equal_approx(own.movement.estimate_crossing_seconds(start, direct[1]), baseline * 2.0), "Crossing a wall costs the same time in planning and execution")
	own.movement.path_hexes = direct.duplicate()
	own.movement.path_index = 1
	own.movement._get_terrain_multiplier()
	_check(is_equal_approx(own.movement.terrain_mult, 0.5), "Movement execution shares the wall crossing factor")
	own.movement.path_hexes.clear()
	LOSHelper.los_lookup[start][direct[1]]["wall_cover"] = 0
	var partial: Vector2 = ground.map_to_local(start).lerp(ground.map_to_local(direct[1]), 0.4)
	_check(is_equal_approx(own.movement.estimate_crossing_seconds(start, direct[1], partial), baseline * 0.6), "Reissuing a move uses the remaining first crossing from the actual position")


func _test_command_and_topology() -> void:
	_graph([direct, detour])
	Globals.unit_visible_enemies[own] = [enemy]
	own.order(Globals.UnitCmd.MOVE, finish)
	var action: ActionProbe = own.action_controller as ActionProbe
	_check(action.commanded_hex == finish and action.commanded_path.size() == detour.size(), "The player move command uses the balanced route and preserves the clicked destination")
	var blocked: int = ground.pathfinding_get_point_id(finish)
	ground.astar.set_point_disabled(blocked, true)
	_check(_path().is_empty(), "Disabled destinations remain unreachable")
	ground.astar.set_point_disabled(blocked, false)
	_graph([direct])
	var from_id: int = ground.pathfinding_get_point_id(direct[1])
	var to_id: int = ground.pathfinding_get_point_id(direct[2])
	ground.astar.disconnect_points(from_id, to_id)
	_check(_path().is_empty(), "The route planner does not invent connections across disconnected terrain")
	_graph([direct, detour])
	for id: int in ground.astar.get_point_ids():
		ground.astar.set_point_weight_scale(id, 13.0)
	var path: Array[Vector2i] = _path()
	_check(path == detour and is_equal_approx(ground.astar.get_point_weight_scale(0), 13.0), "Per-order travel costs do not mutate the shared graph or inherit stale threat weights")
	_check(MovementSystem._compute_path(start, Vector2i(90, 90), own.team, own).is_empty(), "An absent destination does not snap to the nearest reachable graph point")
	var last: int = ground.pathfinding_get_point_id(finish)
	var penultimate: int = ground.pathfinding_get_point_id(direct[-2])
	ground.astar.disconnect_points(penultimate, last)
	ground.astar.connect_points(penultimate, last, false)
	var route: MoveRoutePlanner = MoveRoutePlanner.new()
	route.build(finish, start, own.team, own.movement, [])
	_check(not route.path.is_empty(), "A reverse route can use a genuinely connected alternate path")
	_graph([direct])
	last = ground.pathfinding_get_point_id(finish)
	penultimate = ground.pathfinding_get_point_id(direct[-2])
	ground.astar.disconnect_points(penultimate, last)
	ground.astar.connect_points(penultimate, last, false)
	route.build(finish, start, own.team, own.movement, [])
	_check(route.path.is_empty(), "The search preserves one-way connections")


func _test_route_logging() -> void:
	_graph([direct, detour])
	var contacts: Array[InfluenceContact] = ThreatMap.capture_contacts(own.team)
	var route: MoveRoutePlanner = MoveRoutePlanner.new()
	route.build(start, finish, own.team, own.movement, contacts, own.position)
	var recorder: RecorderProbe = RecorderProbe.new()
	recorder.record_move_route(own, finish, route, contacts)
	var data: Dictionary = recorder.recorded["data"]
	_check(recorder.recorded["type"] == "move_route" and data["target"] == [finish.x, finish.y] and data["path"][-1] == [finish.x, finish.y], "Move diagnostics record the actual destination and path as map hexes")
	_check(data["cost"] == route.cost and data["contacts"].size() == 1 and data["contacts"][0]["firepower_by_range"] is Array, "Move diagnostics preserve cost and the captured threat capability used by the search")
	recorder.free()


func _test_large_map() -> void:
	var rows: Array = []
	for y: int in range(20):
		var row: Array[Vector2i] = []
		for x: int in range(30):
			row.append(Vector2i(x, y))
		rows.append(row)
	_graph(rows)
	for id: int in ground.astar.get_point_ids():
		var cell: Vector2i = ground.local_to_map(ground.astar.get_point_position(id))
		for neighbor: Vector2i in LOSHelper.get_hex_neighbors(cell):
			var other: int = ground.pathfinding_get_point_id(neighbor)
			if ground.local_to_map(ground.astar.get_point_position(other)) == neighbor:
				ground.astar.connect_points(id, other)
	Globals.unit_visible_enemies[own] = []
	var before: int = Time.get_ticks_usec()
	var path: Array[Vector3i] = MovementSystem._compute_path(start, Vector2i(28, 18), own.team, own)
	var milliseconds: float = float(Time.get_ticks_usec() - before) / 1000.0
	_check(not path.is_empty() and ground.cube_to_map(path[-1]) == Vector2i(28, 18), "A complete route remains available on a 600-hex map")
	print("600-hex move route search: ", milliseconds, " ms")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
