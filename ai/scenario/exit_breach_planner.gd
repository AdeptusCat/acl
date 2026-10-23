class_name ExitBreachPlanner
extends RefCounted


# Frozen callers use the same search to completion; live directors advance it per frame.
static func select(planner: PlatoonAI, exits: Array[Vector2i], escape_policy: EscapeMissionPolicy = null, bypass_units: Dictionary[Unit, bool] = {}) -> InfluenceContact:
	var search: Search = Search.new()
	search.start(planner, exits, escape_policy)
	search.advance(-1)
	bypass_units.clear()
	bypass_units.merge(search.bypass_units)
	return search.result


class Search extends RefCounted:
	enum Phase { CELLS, FLOOD, DISENGAGE, WEIGHTED, PATH }

	var completed: bool = false
	var result: InfluenceContact
	var bypass_units: Dictionary[Unit, bool] = {}
	var snapshot: InfluenceSnapshot
	var planner: PlatoonAI
	var escape_policy: EscapeMissionPolicy
	var escape: bool = false
	var graph: AStar2D
	var ids: Dictionary
	var contacts: Array[InfluenceContact] = []
	var origins: Array[int] = []
	var headquarters: Array[int] = []
	var goals: Array[int] = []
	var blockers: Dictionary[int, Array] = {}
	var costs: Dictionary[int, float] = {}
	var reached: Dictionary[int, bool] = {}
	var frontier: Array[int] = []
	var cursor: int = 0
	var phase: Phase = Phase.CELLS
	var cells: PackedInt64Array
	var contact_cubes: Dictionary[InfluenceContact, Vector3i] = {}
	var suppressed_contacts: Dictionary[InfluenceContact, bool] = {}
	var starting_points: Array[int] = []
	var starting_cursor: int = 0
	var disengage_frontier: Array[int] = []
	var visited: Dictionary[int, bool] = {}
	var distance: Dictionary[int, float] = {}
	var parents: Dictionary[int, int] = {}
	var path: Array[int] = []
	var path_cursor: int = -1
	var _inputs: Array = []
	var _exits: Array[Vector2i] = []


	func start(owner: PlatoonAI, exits: Array[Vector2i], policy: EscapeMissionPolicy = null) -> void:
		planner = owner
		escape_policy = policy
		_exits = exits.duplicate()
		escape = escape_policy != null
		if planner.influence_map_controller == null or planner.influence_map_controller.snapshot == null:
			completed = true
			return
		snapshot = planner.influence_map_controller.snapshot
		if not snapshot.routes.has(planner.team):
			completed = true
			return
		graph = snapshot.routes[planner.team]
		ids = snapshot.point_ids[planner.team]
		contacts = []
		for contact: InfluenceContact in snapshot.get_defensive_contacts(planner.team):
			if contact.confidence < 0.25 or (contact.observed and not TacticalPositionExecutor.is_active_defender(contact.unit)):
				continue
			# Old sightings increase route exposure; they cannot prove a passage is sealed.
			if escape and not contact.observed:
				continue
			contacts.append(contact)
		_inputs = _capture_inputs()
		if contacts.is_empty():
			completed = true
			return
		origins = []
		headquarters = []
		var has_combat_units: bool = false
		for unit: Unit in planner.squads:
			if escape and not escape_policy.allows(unit):
				continue
			if (not escape and HqSupportPositionPolicy.is_headquarters(unit)) or not TacticalPositionExecutor.is_active_defender(unit) or not ids.has(unit.current_hex):
				continue
			var id: int = ids[unit.current_hex]
			if escape:
				if not HqSupportPositionPolicy.is_headquarters(unit):
					has_combat_units = true
				if not unit.is_good_order() or not PositionQueryService.can_follow_intent(unit):
					# Immobility needs recovery, not a company assault on the unit's firing lane.
					continue
			if escape and HqSupportPositionPolicy.is_headquarters(unit):
				if not graph.is_point_disabled(id) and not headquarters.has(id):
					headquarters.append(id)
				continue
			if not graph.is_point_disabled(id) and not origins.has(id):
				origins.append(id)
		if escape and origins.is_empty() and not has_combat_units:
			origins = headquarters
		goals = []
		for hex: Vector2i in exits:
			if ids.has(hex) and not graph.is_point_disabled(ids[hex]):
				goals.append(ids[hex])
		if origins.is_empty() or goals.is_empty():
			completed = true
			return
		cells = graph.get_point_ids()
		for contact: InfluenceContact in contacts:
			contact_cubes[contact] = LOSHelper.ground_layer.map_to_cube(contact.hex)
			suppressed_contacts[contact] = contact.observed and TacticalPositionExecutor.is_sufficiently_suppressed(contact.unit)


	# Snapshot replacement, movement, pinning, casualties and policy edits invalidate old work.
	func matches(owner: PlatoonAI, exits: Array[Vector2i], policy: EscapeMissionPolicy) -> bool:
		return planner == owner and escape_policy == policy and _exits == exits and owner.influence_map_controller.snapshot == snapshot and _inputs == _capture_inputs()


	func _capture_inputs() -> Array:
		var inputs: Array = []
		if escape_policy != null:
			inputs.append([escape_policy.include_headquarters, escape_policy.maximum_bypass_visibility, escape_policy.maximum_bypass_risk])
		for unit: Unit in planner.squads:
			if not is_instance_valid(unit):
				inputs.append(null)
				continue
			inputs.append([unit, unit.current_hex, TacticalPositionExecutor.is_active_defender(unit), unit.is_good_order(), PositionQueryService.can_follow_intent(unit)])
		for contact: InfluenceContact in contacts:
			inputs.append([TacticalPositionExecutor.is_active_defender(contact.unit), TacticalPositionExecutor.is_sufficiently_suppressed(contact.unit)])
		return inputs


	func advance(deadline_usec: int) -> void:
		while not completed and (deadline_usec < 0 or Time.get_ticks_usec() < deadline_usec):
			match phase:
				Phase.CELLS:
					if cursor < cells.size():
						var id: int = cells[cursor]
						_build_cell(id)
						cursor += 1
					else:
						_begin_flood()
				Phase.FLOOD:
					_flood_step()
				Phase.DISENGAGE:
					_disengage_step()
				Phase.WEIGHTED:
					if frontier.is_empty():
						completed = true
					else:
						_weighted_step()
				Phase.PATH:
					_path_step()


	func _build_cell(id: int) -> void:
		var cell: Vector2i = LOSHelper.ground_layer.local_to_map(graph.get_point_position(id))
		var cell_cube: Vector3i = LOSHelper.ground_layer.map_to_cube(cell)
		var pressure: float = 0.0
		blockers[id] = []
		if escape:
			blockers[id] = EscapeCorridorPolicy.blockers(snapshot, planner.team, cell, escape_policy)
		for contact: InfluenceContact in contacts:
			var distance: int = LOSHelper.ground_layer.cube_distance(cell_cube, contact_cubes[contact])
			var suppressed: bool = suppressed_contacts[contact]
			if not escape and (distance == 0 or (distance <= 1 and not suppressed)):
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


	func _begin_flood() -> void:
		frontier = origins.duplicate()
		if escape:
			frontier.clear()
			for id: int in goals:
				if blockers[id].is_empty():
					frontier.append(id)
		for id: int in frontier:
			reached[id] = true
		cursor = 0
		phase = Phase.FLOOD


	func _flood_step() -> void:
		if cursor >= frontier.size():
			if escape:
				starting_points = origins.duplicate()
				starting_points.append_array(headquarters)
				phase = Phase.DISENGAGE
			else:
				_begin_weighted()
			return
		var id: int = frontier[cursor]
		cursor += 1
		if not escape and goals.has(id) and blockers[id].is_empty():
			completed = true
			return
		if escape and not blockers[id].is_empty():
			return
		for neighbor: int in graph.get_point_connections(id):
			if not reached.has(neighbor) and not graph.is_point_disabled(neighbor) and (blockers[neighbor].is_empty() or (escape and (origins.has(neighbor) or headquarters.has(neighbor)))):
				reached[neighbor] = true
				frontier.append(neighbor)


	func _disengage_step() -> void:
		if starting_cursor >= starting_points.size():
			ExitBreachPlanner._capture_bypass_units(planner, reached, ids, bypass_units, escape_policy)
			for id: int in origins.duplicate():
				if reached.has(id):
					origins.erase(id)
			_begin_weighted()
			return
		var origin_id: int = starting_points[starting_cursor]
		if reached.has(origin_id):
			_next_origin()
			return
		if disengage_frontier.is_empty():
			disengage_frontier.append(origin_id)
			visited[origin_id] = true
			cursor = 0
		if cursor >= disengage_frontier.size():
			_next_origin()
			return
		var id: int = disengage_frontier[cursor]
		cursor += 1
		var origin: Vector2i = LOSHelper.ground_layer.local_to_map(graph.get_point_position(origin_id))
		for neighbor: int in graph.get_point_connections(id):
			if visited.has(neighbor) or graph.is_point_disabled(neighbor):
				continue
			visited[neighbor] = true
			var cell: Vector2i = LOSHelper.ground_layer.local_to_map(graph.get_point_position(neighbor))
			if not EscapeCorridorPolicy.step_is_safe(snapshot, planner.team, origin, cell, escape_policy):
				continue
			if goals.has(neighbor) or (reached.has(neighbor) and blockers[neighbor].is_empty()):
				reached[origin_id] = true
				_next_origin()
				return
			disengage_frontier.append(neighbor)


	func _next_origin() -> void:
		starting_cursor += 1
		disengage_frontier.clear()
		visited.clear()


	func _begin_weighted() -> void:
		frontier = origins.duplicate()
		for id: int in origins:
			distance[id] = 0.0
		phase = Phase.WEIGHTED


	func _weighted_step() -> void:
		var best: int = frontier[0]
		for id: int in frontier:
			if distance[id] < distance[best]:
				best = id
		frontier.erase(best)
		if goals.has(best):
			path_cursor = best
			phase = Phase.PATH
			return
		for neighbor: int in graph.get_point_connections(best):
			if graph.is_point_disabled(neighbor):
				continue
			var candidate: float = distance[best] + costs[neighbor]
			if candidate < distance.get(neighbor, INF):
				distance[neighbor] = candidate
				parents[neighbor] = best
				if not frontier.has(neighbor):
					frontier.append(neighbor)


	func _path_step() -> void:
		if path_cursor >= 0:
			path.append(path_cursor)
			path_cursor = parents.get(path_cursor, -1)
			return
		if path.is_empty():
			completed = true
			return
		var id: int = path.pop_back()
		var strength: float = INF
		for contact: InfluenceContact in blockers[id]:
			var value: float = contact.confidence * contact.effectiveness * maxf(0.15, contact.firepower)
			if value < strength:
				result = contact
				strength = value
		if result != null:
			completed = true


static func _capture_bypass_units(planner: PlatoonAI, reached: Dictionary[int, bool], ids: Dictionary, bypass_units: Dictionary[Unit, bool], policy: EscapeMissionPolicy) -> void:
	var headquarters: Array[Unit] = []
	for unit: Unit in planner.squads:
		if not TacticalPositionExecutor.is_active_defender(unit) or not policy.allows(unit):
			continue
		if HqSupportPositionPolicy.is_headquarters(unit):
			headquarters.append(unit)
		elif ids.has(unit.current_hex) and reached.has(ids[unit.current_hex]):
			bypass_units[unit] = true
	for unit: Unit in headquarters:
		if not ids.has(unit.current_hex) or not reached.has(ids[unit.current_hex]):
			continue
		var ready: bool = true
		for subordinate: Unit in planner.squads:
			if HqSupportPositionPolicy.is_headquarters(subordinate) or not TacticalPositionExecutor.is_active_defender(subordinate):
				continue
			if subordinate.company == unit.company and (unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS or subordinate.platoon == unit.platoon) and not bypass_units.has(subordinate):
				ready = false
				break
		if ready:
			bypass_units[unit] = true
