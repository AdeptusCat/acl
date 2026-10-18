extends Node

class EscapeMovement extends UnitMovement:
	func _get_terrain_multiplier() -> void:
		terrain_mult = 1.0

var failures: int = 0
var failed_routs: int = 0

func _ready() -> void:
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	ground.pathfinding_enabled = false
	ground.tile_set.add_custom_data_layer()
	ground.tile_set.set_custom_data_layer_name(0, "name")
	ground.tile_set.set_custom_data_layer_type(0, TYPE_STRING)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	var image: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(16, 16)
	source.create_tile(Vector2i.ZERO)
	var woods_source: TileSetAtlasSource = TileSetAtlasSource.new()
	woods_source.texture = source.texture
	woods_source.texture_region_size = Vector2i(16, 16)
	woods_source.create_tile(Vector2i.ZERO)
	ground.tile_set.add_source(source, 0)
	source.get_tile_data(Vector2i.ZERO, 0).set_custom_data("name", "Stone Building")
	ground.tile_set.add_source(woods_source, 1)
	woods_source.get_tile_data(Vector2i.ZERO, 0).set_custom_data("name", "Woods")
	add_child(ground)
	var buildings: BuildingTileMapLayer = BuildingTileMapLayer.new()
	buildings.tile_set = ground.tile_set
	add_child(buildings)
	LOSHelper.ground_layer = ground
	LOSHelper.building_layer = buildings
	var unit: Unit = Unit.new()
	unit.team = Globals.Team.AXIS
	var enemy: Unit = Unit.new()
	enemy.team = Globals.Team.ALLIES
	var action: SquadActionController = SquadActionController.new()
	action.unit = unit
	var origin: Vector2i = Vector2i(5, 5)
	var origin_cube: Vector3i = ground.map_to_cube(origin)
	unit.current_hex = origin
	unit.current_cube = origin_cube
	unit.position = ground.map_to_local(origin)
	var movement: EscapeMovement = EscapeMovement.new()
	movement.unit = unit
	unit.movement = movement
	action.rout_failed.connect(_on_rout_failed)
	var direction: Vector3i = ground.cube_direction(TileSet.CELL_NEIGHBOR_TOP_SIDE)
	enemy.current_hex = ground.cube_to_map(origin_cube + direction)
	var side_direction: Vector3i = ground.cube_direction(TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE)
	var side: Vector2i = ground.cube_to_map(origin_cube + side_direction)
	var escape: Vector2i = ground.cube_to_map(origin_cube + side_direction * 2)
	var cells: Array[Vector2i] = [origin, side, escape, enemy.current_hex]
	var graph: AStar2D = AStar2D.new()
	for index: int in range(cells.size()):
		ground.set_cell(cells[index], 0, Vector2i.ZERO)
		graph.add_point(index, ground.map_to_local(cells[index]))
	graph.connect_points(0, 1)
	graph.connect_points(1, 2)
	graph.connect_points(0, 3)
	ground.astar = graph
	Globals.astars[unit.team] = graph
	var enemies: Array[Unit] = [enemy]
	_check(ground.cube_distance(ground.map_to_cube(side), ground.map_to_cube(enemy.current_hex)) == 1, "Fixture starts with an escape step alongside an adjacent enemy")
	_check(action.compute_retreat_hex(origin, enemies, 3) == origin, "A route beside an enemy is rejected even when it leads to safety")
	Globals.unit_visible_enemies[unit] = enemies
	action._start_rout()
	_check(failed_routs == 1 and not movement.is_moving, "A squad fails its rout when its only escape passes beside an enemy")
	failed_routs = 0
	ground.erase_cell(enemy.current_hex)
	enemy.current_hex = ground.cube_to_map(origin_cube - side_direction)
	_check(action.compute_retreat_hex(origin, enemies, 3) == escape, "A squad can rout directly away from an adjacent enemy")
	_check(not action._can_retreat_step(escape, side, enemies), "Retreat steps cannot decrease distance from an enemy")
	var enemy_hex: Vector2i = enemy.current_hex
	enemy.current_hex = ground.cube_to_map(origin_cube + direction * 3)
	_check(not action._can_retreat_step(origin, side, enemies), "Sideways steps at the same enemy distance are rejected even outside adjacency")
	enemy.current_hex = enemy_hex
	var second_enemy: Unit = Unit.new()
	second_enemy.current_hex = ground.cube_to_map(origin_cube + side_direction * 3)
	var opposing_enemies: Array[Unit] = [enemy, second_enemy]
	_check(action.compute_retreat_hex(origin, opposing_enemies, 3) == origin, "Moving away from one enemy cannot move closer to another")
	second_enemy.free()
	action.compute_retreat_hex(origin, enemies, 3)
	var route: AStar2D = action.create_restricted_astar(action.allowed_hexes)
	_check(route.get_id_path(0, 2).size() == 3, "The chosen escape has a connected movement path")
	_check(not route.are_points_connected(2, 1, false), "The movement graph cannot shortcut backwards toward an enemy")
	Globals.unit_visible_enemies[unit] = enemies
	action._start_rout()
	_check(failed_routs == 0 and movement.is_moving and movement.retreating and movement.target_hex == escape, "Routing starts movement instead of surrendering beside an enemy")
	movement.stop()
	graph.set_point_disabled(1, true)
	_check(action.compute_retreat_hex(origin, enemies, 3) == origin, "A blocked escape does not permit retreat through an impassable hex or enemy")
	action._start_rout()
	_check(failed_routs == 1, "A genuinely trapped squad still fails its rout")
	graph.set_point_disabled(1, false)
	graph.disconnect_points(0, 1)
	_check(action.compute_retreat_hex(origin, enemies, 3) == origin, "A disconnected escape is not considered reachable")
	graph.connect_points(0, 1)
	buildings.set_cell(side, 0, Vector2i.ZERO)
	_check(action.compute_retreat_hex(origin, enemies, 3) == side, "An unseen reachable building remains the preferred refuge")
	LOSHelper.los_lookup = {enemy.current_hex: {side: {}}}
	_check(action.compute_retreat_hex(origin, enemies, 3) == side, "Seen buildings outrank unseen open ground")
	buildings.set_cell(escape, 1, Vector2i.ZERO)
	_check(action.compute_retreat_hex(origin, enemies, 3) == escape, "Unseen woods outrank a seen building")
	LOSHelper.los_lookup = {}
	_check(action.compute_retreat_hex(origin, enemies, 3) == side, "Unseen buildings outrank unseen woods")
	buildings.set_cell(side, 1, Vector2i.ZERO)
	buildings.set_cell(escape, 0, Vector2i.ZERO)
	_check(action.compute_retreat_hex(origin, enemies, 3) == escape, "A farther unseen building outranks nearby unseen woods")
	LOSHelper.los_lookup = {enemy.current_hex: {escape: {}}}
	_check(action.compute_retreat_hex(origin, enemies, 3) == side, "Unseen woods outrank a seen building farther away")
	buildings.erase_cell(escape)
	LOSHelper.los_lookup = {enemy.current_hex: {side: {}}}
	_check(action.compute_retreat_hex(origin, enemies, 3) == side, "Seen woods outrank unseen open ground")
	buildings.erase_cell(side)
	LOSHelper.los_lookup = {enemy.current_hex: {escape: {}}}
	_check(action.compute_retreat_hex(origin, enemies, 3) == side, "Unseen open ground outranks seen open ground")
	LOSHelper.los_lookup = {enemy.current_hex: {side: {}, escape: {}}}
	_check(action.compute_retreat_hex(origin, enemies, 3) == escape, "Seen open ground remains an escape of last resort")
	LOSHelper.los_lookup = {}
	Globals.unit_visible_enemies.erase(unit)
	_test_debug_rout_button(unit)
	movement.free()
	action.free()
	unit.free()
	enemy.free()
	print("Rout escape regression failures: ", failures)
	get_tree().quit(failures)

func _test_debug_rout_button(unit: Unit) -> void:
	var panel: PanelContainer = preload("res://scenes/ui/units/unit_details_panel.tscn").instantiate()
	add_child(panel)
	var debug_actions: HFlowContainer = panel.get_node("Scroll/Summary/Details/Content/DebugActions")
	var button: Button = debug_actions.get_node("Rout")
	_check(debug_actions.visible == OS.is_debug_build(), "Force rout uses the same debug visibility as the other debug actions")
	unit.stress_system = StressController.new()
	unit.stress_system.state = STATES.MoraleState.NORMAL
	unit.movement.retreating = false
	panel.unit = unit
	button.pressed.emit()
	if OS.is_debug_build():
		_check(unit.stress_system.state == STATES.MoraleState.PANIC, "Force rout triggers panic without requiring a pinned squad")
	panel.unit = null
	panel.free()
	unit.stress_system.free()
	unit.stress_system = null

func _on_rout_failed() -> void:
	failed_routs += 1

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
