extends Node

const RISK_WEIGHT: float = 4.0

var result_ready: bool = false
var current_threat_maps: Dictionary[int, Dictionary] = {
	Globals.Team.AXIS: {},
	Globals.Team.ALLIES: {},
}
var update_interval: float = 0.25
var update_timer: float = 0.0

signal draw_threat(current_threat_maps: Dictionary[int, Dictionary])


func capture_contacts(team: int) -> Array[InfluenceContact]:
	# Manual movement always follows the issuing side's knowledge, including in AI debug modes.
	return InfluenceUnitQuery.capture_contacts(team, InfluenceMapController.KnowledgePolicy.OBSERVED_AND_MEMORY)


func risk_at(cell: Vector2i, contacts: Array[InfluenceContact], lookup: Dictionary) -> float:
	var incoming: float = 0.0
	for contact: InfluenceContact in contacts:
		var distance: int = LOSHelper.get_hex_distance(contact.hex, cell)
		var lanes: Dictionary = lookup.get(contact.hex, {})
		if distance > contact.weapon_range or not lanes.has(cell):
			continue
		var firepower: float = contact.firepower
		if not contact.movement_firepower_by_range.is_empty():
			firepower = 0.0
			if distance < contact.movement_firepower_by_range.size():
				firepower = contact.movement_firepower_by_range[distance]
		var record: Dictionary = lanes[cell]
		incoming += LosInfluenceProjector.calculate_los_fire_threat(firepower * clampf(contact.confidence, 0.0, 1.0),
			contact.effectiveness, float(record.get("target_cover", 0.0)), float(record.get("hindrance", 0.0)), distance)
	return PositionFeatureEvaluator.risk(incoming)


func _process(delta: float) -> void:
	update_timer += delta
	if update_timer < update_interval:
		return
	update_timer = 0.0
	if not is_instance_valid(LOSHelper.ground_layer):
		current_threat_maps = {Globals.Team.AXIS: {}, Globals.Team.ALLIES: {}}
		result_ready = false
		return
	for team: int in Globals.Team.values():
		_refresh_team(team)
	result_ready = true
	draw_threat.emit(current_threat_maps)


func _refresh_team(team: int) -> void:
	var weights: Dictionary = {}
	var contacts: Array[InfluenceContact] = capture_contacts(team)
	if Globals.astars.has(team):
		var graph: AStar2D = Globals.astars[team]
		for id: int in graph.get_point_ids():
			var cell: Vector2i = LOSHelper.ground_layer.local_to_map(graph.get_point_position(id))
			weights[cell] = 1.0 + RISK_WEIGHT * risk_at(cell, contacts, LOSHelper.los_lookup)
	current_threat_maps[team] = weights


func update_astart_for_team(team: Globals.Team) -> void:
	if not is_instance_valid(LOSHelper.ground_layer) or not Globals.astars.has(team):
		return
	_refresh_team(team)
	var graph: AStar2D = Globals.astars[team]
	for id: int in graph.get_point_ids():
		var cell: Vector2i = LOSHelper.ground_layer.local_to_map(graph.get_point_position(id))
		graph.set_point_weight_scale(id, current_threat_maps[team].get(cell, 1.0))
