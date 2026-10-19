class_name ExitBreachPlanner
extends RefCounted


# Search captured knowledge only. A safe opening takes precedence over a breach.
static func select(planner: PlatoonAI, exits: Array[Vector2i], escape_policy: EscapeMissionPolicy = null) -> InfluenceContact:
	var escape: bool = escape_policy != null
	if planner.influence_map_controller == null or planner.influence_map_controller.snapshot == null:
		return null
	var snapshot: InfluenceSnapshot = planner.influence_map_controller.snapshot
	if not snapshot.routes.has(planner.team):
		return null
	var graph: AStar2D = snapshot.routes[planner.team]
	var ids: Dictionary = snapshot.point_ids[planner.team]
	var contacts: Array[InfluenceContact] = []
	for contact: InfluenceContact in snapshot.get_defensive_contacts(planner.team):
		if contact.confidence < 0.25 or (contact.observed and not TacticalPositionExecutor.is_active_defender(contact.unit)):
			continue
		# Old sightings increase route exposure; they cannot prove a passage is sealed.
		if escape and not contact.observed:
			continue
		contacts.append(contact)
	if contacts.is_empty():
		return null
	var origins: Array[int] = []
	for unit: Unit in planner.squads:
		if escape and not escape_policy.allows(unit):
			continue
		if (not escape and HqSupportPositionPolicy.is_headquarters(unit)) or not TacticalPositionExecutor.is_active_defender(unit) or not ids.has(unit.current_hex):
			continue
		var id: int = ids[unit.current_hex]
		if not graph.is_point_disabled(id) and not origins.has(id):
			origins.append(id)
	var goals: Array[int] = []
	for hex: Vector2i in exits:
		if ids.has(hex) and not graph.is_point_disabled(ids[hex]):
			goals.append(ids[hex])
	if origins.is_empty() or goals.is_empty():
		return null
	var blockers: Dictionary[int, Array] = {}
	var costs: Dictionary[int, float] = {}
	for id: int in graph.get_point_ids():
		var cell: Vector2i = LOSHelper.ground_layer.local_to_map(graph.get_point_position(id))
		var pressure: float = 0.0
		blockers[id] = []
		for contact: InfluenceContact in contacts:
			var distance: int = LOSHelper.get_hex_distance(cell, contact.hex)
			var suppressed: bool = contact.observed and TacticalPositionExecutor.is_sufficiently_suppressed(contact.unit)
			if distance == 0 or (distance <= 1 and not suppressed):
				blockers[id].append(contact)
			if distance <= 1 or snapshot.los.get(contact.hex, {}).has(cell):
				var strength: float = contact.confidence * contact.effectiveness * maxf(0.15, contact.firepower)
				if suppressed:
					strength *= 0.2
				pressure += strength * 8.0 / float(maxi(1, distance))
		var risk: float = PositionFeatureEvaluator.risk(snapshot.maps[planner.team].get_layer_value(InfluenceMap.Layer.THREAT, cell))
		if not escape and risk > 0.8 and blockers[id].is_empty():
			for contact: InfluenceContact in contacts:
				if snapshot.los.get(contact.hex, {}).has(cell):
					blockers[id].append(contact)
		costs[id] = 1.0 + pressure + risk * 3.0
	# Flood around enemy control before considering any contested route.
	var reached: Dictionary[int, bool] = {}
	var frontier: Array[int] = origins.duplicate()
	for id: int in origins:
		reached[id] = true
	var cursor: int = 0
	while cursor < frontier.size():
		var id: int = frontier[cursor]
		cursor += 1
		if goals.has(id) and blockers[id].is_empty():
			return null
		for neighbor: int in graph.get_point_connections(id):
			if not reached.has(neighbor) and not graph.is_point_disabled(neighbor) and blockers[neighbor].is_empty():
				reached[neighbor] = true
				frontier.append(neighbor)
	# Weighted search compares the complete corridor, including overlapping defenders.
	var distance: Dictionary[int, float] = {}
	var parents: Dictionary[int, int] = {}
	frontier = origins.duplicate()
	for id: int in origins:
		distance[id] = 0.0
	while not frontier.is_empty():
		var best: int = frontier[0]
		for id: int in frontier:
			if distance[id] < distance[best]:
				best = id
		frontier.erase(best)
		if goals.has(best):
			var path: Array[int] = [best]
			while parents.has(path[0]):
				path.push_front(parents[path[0]])
			for id: int in path:
				var weakest: InfluenceContact
				var strength: float = INF
				for contact: InfluenceContact in blockers[id]:
					var value: float = contact.confidence * contact.effectiveness * maxf(0.15, contact.firepower)
					if value < strength:
						weakest = contact
						strength = value
				if weakest != null:
					return weakest
			return null
		for neighbor: int in graph.get_point_connections(best):
			if graph.is_point_disabled(neighbor):
				continue
			var candidate: float = distance[best] + costs[neighbor]
			if candidate < distance.get(neighbor, INF):
				distance[neighbor] = candidate
				parents[neighbor] = best
				if not frontier.has(neighbor):
					frontier.append(neighbor)
	return null
