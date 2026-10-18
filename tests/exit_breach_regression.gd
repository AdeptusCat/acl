extends Node

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	ground.tile_set.tile_size = Vector2i(128, 128)
	add_child(ground)
	LOSHelper.ground_layer = ground
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = Globals.Team.AXIS
	planner.influence_map_controller = InfluenceMapController.new()
	var snapshot: InfluenceSnapshot = InfluenceSnapshot.new()
	planner.influence_map_controller.snapshot = snapshot
	var graph: AStar2D = AStar2D.new()
	var cells: Array[Vector2i] = [Vector2i(8, 5), Vector2i(6, 2), Vector2i(4, 2), Vector2i(2, 2), Vector2i(0, 5), Vector2i(6, 8), Vector2i(4, 8), Vector2i(2, 8)]
	var ids: Dictionary = {}
	for index: int in range(cells.size()):
		graph.add_point(index, ground.map_to_local(cells[index]))
		ids[cells[index]] = index
	for edge: Vector2i in [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4), Vector2i(0, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4)]:
		graph.connect_points(edge.x, edge.y)
	snapshot.routes[planner.team] = graph
	snapshot.point_ids[planner.team] = ids
	var map: InfluenceMap = InfluenceMap.new()
	map.configure(Rect2i(0, 0, 10, 10))
	for cell: Vector2i in cells:
		map.playable_cells[cell] = true
	snapshot.maps[planner.team] = map
	var friendly: Unit = _unit(planner.team, cells[0], 1.0)
	planner.squads = [friendly]
	var strong: Unit = _unit(Globals.Team.ALLIES, cells[2], 1.0)
	var weak: Unit = _unit(Globals.Team.ALLIES, cells[6], 0.1)
	var strong_contact: InfluenceContact = _contact(strong)
	var weak_contact: InfluenceContact = _contact(weak)
	snapshot.defensive_contacts[planner.team] = [strong_contact, weak_contact]
	var exits: Array[Vector2i] = [cells[4]]
	_check(ExitBreachPlanner.select(planner, exits) == weak_contact, "A blocked exit chooses the weaker defended corridor")
	snapshot.defensive_contacts[planner.team] = [strong_contact]
	_check(ExitBreachPlanner.select(planner, exits) == null, "An open bypass takes precedence over fighting")
	snapshot.contacts[planner.team] = [strong_contact]
	var movement: UnitMovement = UnitMovement.new()
	movement.unit = friendly
	friendly.movement = movement
	var query: PositionQuery = PositionQuery.new()
	query.unit = friendly
	query.team = planner.team
	query.snapshot = snapshot
	query.origin_hex = friendly.current_hex
	query.objective_hex = exits[0]
	query.profile = PositionProfile.for_mode(PositionProfile.Mode.ADVANCE)
	query.profile.avoid_unsuppressed_defenders = true
	var field: PositionRouteField = PositionRouteField.new()
	field.build(query)
	var bypass: Array[Vector2i] = field.path_to(exits[0])
	_check(not bypass.is_empty() and not bypass.has(strong.current_hex) and bypass.has(weak.current_hex), "The tactical route search finds the open bypass around enemy control")
	movement.free()
	friendly.movement = null
	snapshot.defensive_contacts[planner.team] = [strong_contact, weak_contact]
	weak.alive = false
	_check(ExitBreachPlanner.select(planner, exits) == null, "A destroyed blocker releases the exit route")
	weak.alive = true
	graph.set_point_disabled(6, true)
	_check(ExitBreachPlanner.select(planner, exits) == strong_contact, "A terrain-blocked corridor is never treated as a breach route")
	graph.set_point_disabled(6, false)
	weak_contact.observed = false
	weak_contact.hex = cells[6]
	weak.current_hex = Vector2i(99, 99)
	_check(ExitBreachPlanner.select(planner, exits) != null, "Remembered blockers use captured positions without consulting hidden movement")
	for unit: Unit in [friendly, strong, weak]:
		unit.stress_system.free()
		unit.combat_stats.free()
		unit.free()
	planner.influence_map_controller.free()
	planner.free()
	LOSHelper.unload_map()
	ground.free()
	print("Exit breach regression failures: ", failures)
	get_tree().quit(failures)


func _unit(team: Globals.Team, hex: Vector2i, effectiveness: float) -> Unit:
	var unit: Unit = Unit.new()
	unit.team = team
	unit.current_hex = hex
	unit.stress_system = StressController.new()
	unit.combat_stats = UnitCombatStats.new()
	unit.combat_stats.combat_effectiveness = effectiveness
	return unit


func _contact(unit: Unit) -> InfluenceContact:
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = unit
	contact.hex = unit.current_hex
	contact.observed = true
	contact.effectiveness = InfluenceUnitQuery.get_unit_effectiveness(unit)
	contact.firepower = InfluenceUnitQuery.get_unit_firepower(unit)
	return contact


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
