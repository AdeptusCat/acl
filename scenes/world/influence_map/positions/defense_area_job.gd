class_name DefenseAreaJob
extends RefCounted

enum Phase { GEOMETRY, OBJECTIVE_FIELD, RETURN_FIELD, SOURCES, APPROACH_FIELD, CORRIDOR, MARGIN, RESPONSE_FIELD, FINISH }

const MAX_BRANCHES_PER_SECTOR: int = 3
const LATERAL_WEIGHT: float = 0.2

var _snapshot_ref: WeakRef
var snapshot: InfluenceSnapshot:
	get:
		if _snapshot_ref == null:
			return null
		return _snapshot_ref.get_ref() as InfluenceSnapshot
var team: int
var objective: Vector2i
var position_radius: int = 8
var analysis_radius: int = 12
var manual_axes: Array[ThreatAxis] = []
var result: DefenseAreaAssessment
var completed: bool = false
var phase: Phase = Phase.GEOMETRY
var geometry: Dictionary = {"cells": [], "neighbors": {}, "costs": {}, "open_costs": {}, "cover": {}, "covered": [], "edges": [], "boundary": {}, "objective_distances": {}, "return_open_costs": {}, "response_fields": {}}
var field: DefenseTravelField
var cache_key: String
var cursor: int = 0
var seeds: Array[Dictionary] = []
var seed_index: int = 0
var corridor: Dictionary = {}
var response_field: DefenseTravelField
var core_cells: Array[Vector2i] = []
var core_weights: Dictionary = {}


func start(capture: InfluenceSnapshot, own_team: int, target: Vector2i, radius: int, horizon: int, axes: Array[ThreatAxis]) -> void:
	_snapshot_ref = weakref(capture)
	team = own_team
	objective = target
	position_radius = radius
	analysis_radius = maxi(radius + 2, horizon)
	manual_axes = axes
	result = DefenseAreaAssessment.new()
	result.objective_hex = objective
	result.snapshot_version = snapshot.version
	cache_key = str([snapshot.terrain_key, team, objective, position_radius, analysis_radius])
	if snapshot.defense_geometry_cache.has(cache_key):
		geometry = snapshot.defense_geometry_cache[cache_key]
		phase = Phase.SOURCES


func advance(deadline_usec: int) -> void:
	if snapshot == null:
		completed = true
		return
	while not completed and (deadline_usec < 0 or Time.get_ticks_usec() < deadline_usec):
		match phase:
			Phase.GEOMETRY:
				if cursor < snapshot.maps[team].cell_count:
					_capture_cell(snapshot.maps[team].index_to_cell(cursor))
					cursor += 1
				else:
					field = DefenseTravelField.new()
					field.start(geometry, objective, true)
					phase = Phase.OBJECTIVE_FIELD
			Phase.OBJECTIVE_FIELD:
				field.advance(deadline_usec)
				if field.completed:
					geometry["objective_distances"] = field.distances
					var guards: Array[Vector2i] = [objective]
					# Covered adjacent guard positions can protect an open objective without entering it.
					for neighbor: Vector2i in geometry["neighbors"].get(objective, []):
						if geometry["cover"].get(neighbor, 0.0) >= 0.1:
							guards.append(neighbor)
					field = DefenseTravelField.new()
					field.start_sources(geometry, guards, true, "open_costs")
					phase = Phase.RETURN_FIELD
			Phase.RETURN_FIELD:
				field.advance(deadline_usec)
				if field.completed:
					geometry["return_open_costs"] = field.distances
					if snapshot.defense_geometry_cache.size() >= 8:
						snapshot.defense_geometry_cache.erase(snapshot.defense_geometry_cache.keys()[0])
					snapshot.defense_geometry_cache[cache_key] = geometry
					phase = Phase.SOURCES
			Phase.SOURCES:
				_prepare_sources()
				phase = Phase.APPROACH_FIELD
			Phase.APPROACH_FIELD:
				if seed_index >= seeds.size():
					phase = Phase.FINISH
					continue
				if field == null or field.reverse:
					field = DefenseTravelField.new()
					field.start(geometry, seeds[seed_index]["source"])
				field.advance(deadline_usec)
				if field.completed:
					corridor = seeds[seed_index].duplicate()
					corridor["cells"] = []
					corridor["weights"] = {}
					corridor["distances"] = field.distances
					corridor["arrival_seconds"] = field.distances.get(objective, INF) * corridor["crossing_seconds"]
					cursor = 0
					phase = Phase.CORRIDOR
			Phase.CORRIDOR:
				if cursor < geometry["cells"].size():
					_add_corridor_cell(geometry["cells"][cursor])
					cursor += 1
				else:
					core_cells.assign(corridor["cells"])
					core_weights = corridor["weights"].duplicate()
					cursor = 0
					phase = Phase.MARGIN
			Phase.MARGIN:
				if cursor < core_cells.size():
					_add_lateral_margin(core_cells[cursor])
					cursor += 1
				else:
					response_field = null
					if not geometry["response_fields"].has(corridor["id"]):
						var entries: Array[Vector2i] = []
						for cell: Vector2i in geometry["edges"]:
							if result.sector_at(cell) == corridor["id"]:
								entries.append(cell)
						if entries.is_empty():
							for cell: Vector2i in geometry["covered"]:
								if result.sector_at(cell) == corridor["id"]:
									entries.append(cell)
						response_field = DefenseTravelField.new()
						response_field.start_sources(geometry, entries, true)
					phase = Phase.RESPONSE_FIELD
			Phase.RESPONSE_FIELD:
				if response_field != null:
					response_field.advance(deadline_usec)
					if not response_field.completed:
						return
					geometry["response_fields"][corridor["id"]] = response_field.distances
				corridor["response_distances"] = geometry["response_fields"][corridor["id"]]
				if not corridor["cells"].is_empty():
					corridor["priority"] *= 1.0 + 10.0 / (3.0 + corridor["arrival_seconds"])
					_publish_branch()
				seed_index += 1
				field = null
				phase = Phase.APPROACH_FIELD
			Phase.FINISH:
				_limit_inferred_priorities()
				result.geometry = geometry
				result.covered_positions.assign(geometry["covered"])
				result.edge_positions.assign(geometry["edges"])
				completed = true
				# Results contain captured data only; do not retain the snapshot/cache cycle.
				_snapshot_ref = null


func _capture_cell(cell: Vector2i) -> void:
	var map: InfluenceMap = snapshot.maps[team]
	if not map.is_playable_cell(cell) or map.get_layer_value(InfluenceMap.Layer.NO_GO, cell) > 0.0:
		return
	geometry["cells"].append(cell)
	var cover: float = map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell)
	geometry["cover"][cell] = cover
	geometry["costs"][cell] = 1.0 + map.get_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell)
	geometry["open_costs"][cell] = 0.0
	if cover < 0.1:
		geometry["open_costs"][cell] = geometry["costs"][cell]
	var neighbors: Array[Vector2i] = []
	var edge: bool = false
	var ids: Dictionary = snapshot.point_ids.get(team, {})
	for neighbor: Vector2i in LOSHelper.get_hex_neighbors(cell):
		if map.is_playable_cell(neighbor) and map.get_layer_value(InfluenceMap.Layer.NO_GO, neighbor) <= 0.0 and ids.has(cell) and ids.has(neighbor) and snapshot.routes[team].are_points_connected(ids[cell], ids[neighbor]):
			neighbors.append(neighbor)
			if map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, neighbor) < 0.1:
				edge = true
	geometry["neighbors"][cell] = neighbors
	var distance: int = LOSHelper.get_hex_distance(cell, objective)
	if cover >= 0.1 and distance <= position_radius:
		geometry["covered"].append(cell)
		if edge:
			geometry["edges"].append(cell)
	if distance >= 2 and distance <= analysis_radius:
		var sector: int = result.sector_at(cell)
		var previous: Vector2i = geometry["boundary"].get(sector, objective)
		if distance > LOSHelper.get_hex_distance(previous, objective):
			geometry["boundary"][sector] = cell


func _prepare_sources() -> void:
	var grouped: Dictionary = {}
	var contacts: Array[Dictionary] = []
	for contact: InfluenceContact in snapshot.get_defensive_contacts(team):
		if contact.observed and is_instance_valid(contact.unit):
			result.observed_contacts[contact.unit] = contact.hex
		if not geometry["objective_distances"].has(contact.hex):
			continue
		var sector: int = result.sector_at(contact.hex)
		var age: float = maxf(0.0, snapshot.captured_at - contact.last_seen_at)
		var freshness: float = exp(-age / 12.0)
		if contact.observed:
			freshness = 1.0
		var priority: float = clampf(contact.firepower * contact.effectiveness, 0.5, 3.0) * maxf(0.03, freshness) * contact.confidence
		var evidence: String = "remembered"
		if contact.observed:
			evidence = "observed"
		var urgency: float = priority * (1.0 + 10.0 / (3.0 + geometry["objective_distances"][contact.hex] * contact.crossing_seconds))
		var identity: String = str(contact.hex)
		if is_instance_valid(contact.unit):
			identity = str(contact.unit.get_instance_id())
		contacts.append({"id": sector, "key": str(sector) + ":" + identity, "source": contact.hex, "priority": priority,
			"confirmed": contact.observed, "evidence": evidence, "crossing_seconds": contact.crossing_seconds, "source_priority": urgency})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["confirmed"] != b["confirmed"]:
			return a["confirmed"]
		if not is_equal_approx(a["source_priority"], b["source_priority"]):
			return a["source_priority"] > b["source_priority"]
		return a["key"] < b["key"])
	for contact: Dictionary in contacts:
		var sector: int = contact["id"]
		if not grouped.has(sector):
			grouped[sector] = []
		var cluster: Dictionary = {}
		var nearest: int = 999999
		for branch: Dictionary in grouped[sector]:
			var distance: int = LOSHelper.get_hex_distance(contact["source"], branch["source"])
			if distance < nearest:
				nearest = distance
				cluster = branch
		if nearest >= 2 and grouped[sector].size() < MAX_BRANCHES_PER_SECTOR:
			# Distinct groups retain their own approach rather than widening one aggregate duty.
			for branch: Dictionary in grouped[sector]:
				if branch["key"] == contact["key"]:
					contact["key"] += ":" + str(contact["source"])
			grouped[sector].append(contact)
		else:
			cluster["priority"] += contact["priority"]
			# The sorted freshest source anchors nearby contacts; identity remains stable.
			if contact["key"] < cluster["key"]:
				cluster["key"] = contact["key"]
	for axis: ThreatAxis in manual_axes:
		var sector: int = result.sector_at(axis.source_hex)
		if not grouped.has(sector) and geometry["objective_distances"].has(axis.source_hex):
			grouped[sector] = [{"id": sector, "key": str(sector) + ":mission", "source": axis.source_hex, "priority": maxf(0.12, axis.confidence), "confirmed": false, "evidence": "mission", "crossing_seconds": 2.0}]
	for sector: int in geometry["boundary"]:
		if not grouped.has(sector) and geometry["objective_distances"].has(geometry["boundary"][sector]):
			grouped[sector] = [{"id": sector, "key": str(sector) + ":terrain", "source": geometry["boundary"][sector], "priority": 0.08, "confirmed": false, "evidence": "inferred", "crossing_seconds": 2.0}]
	var sectors: Array = grouped.keys()
	sectors.sort()
	for sector: int in sectors:
		for branch: Dictionary in grouped[sector]:
			seeds.append(branch)


func _add_lateral_margin(core: Vector2i) -> void:
	var best: float = field.distances.get(objective, INF)
	for cell: Vector2i in geometry["neighbors"].get(core, []):
		if cell == objective or core_weights.has(cell) or LOSHelper.get_hex_distance(cell, objective) > analysis_radius:
			continue
		var source_cost: float = field.distances.get(cell, INF)
		var objective_cost: float = geometry["objective_distances"].get(cell, INF)
		if source_cost > best or objective_cost > best:
			continue
		# One connected step only; expensive terrain cannot create a broad speculative fan.
		var detour: float = maxf(0.0, source_cost + objective_cost - best)
		if detour > 2.5 + 2.0 * geometry["costs"][cell]:
			continue
		var weight: float = core_weights[core] * LATERAL_WEIGHT / geometry["costs"][cell]
		if not corridor["weights"].has(cell):
			corridor["cells"].append(cell)
		corridor["weights"][cell] = maxf(corridor["weights"].get(cell, 0.0), weight)


func _publish_branch() -> void:
	var parent: Dictionary = result.approach_for_sector(corridor["id"])
	if parent.is_empty():
		parent = corridor.duplicate()
		# Preserve the representative sector summary for legacy queries and diagnostics.
		parent.erase("key")
		parent["cells"] = core_cells.duplicate()
		parent["weights"] = core_weights.duplicate()
		parent["branches"] = []
		parent["priority"] = 0.0
		result.approaches.append(parent)
	parent["priority"] += corridor["priority"]
	parent["branches"].append(corridor)


func _add_corridor_cell(cell: Vector2i) -> void:
	if cell == objective or LOSHelper.get_hex_distance(cell, objective) > analysis_radius:
		return
	var objective_cost: float = geometry["objective_distances"].get(cell, INF)
	var source_cost: float = field.distances.get(cell, INF)
	var best: float = field.distances.get(objective, INF)
	if not is_finite(best) or not is_finite(objective_cost) or not is_finite(source_cost):
		return
	# Do not draw branches reached by first arriving at, then walking away from, the objective.
	if source_cost > best or objective_cost > best:
		return
	var detour: float = maxf(0.0, source_cost + objective_cost - best)
	if detour > 2.5:
		return
	# Near-optimal route alternatives, weighted by exposure time on vulnerable ground.
	var vulnerability: float = 1.0 - clampf(geometry["cover"][cell], 0.0, 1.0)
	corridor["cells"].append(cell)
	corridor["weights"][cell] = exp(-detour) * (1.0 + vulnerability * minf(corridor["crossing_seconds"] * geometry["costs"][cell], 4.0))


func _limit_inferred_priorities() -> void:
	var known_priority: float = 0.0
	for approach: Dictionary in result.approaches:
		if approach["evidence"] != "inferred":
			for branch: Dictionary in approach["branches"]:
				known_priority = maxf(known_priority, branch["priority"])
	result.max_priority = 0.0
	for approach: Dictionary in result.approaches:
		# Aging known pressure does not promote an arbitrary boundary guess above it.
		if known_priority > 0.0 and approach["evidence"] == "inferred":
			approach["priority"] = minf(approach["priority"], known_priority * 0.2)
		result.max_priority = maxf(result.max_priority, approach["priority"])
		var total: float = 0.0
		for branch: Dictionary in approach["branches"]:
			total += branch["priority"]
		for branch: Dictionary in approach["branches"]:
			branch["share"] = branch["priority"] / maxf(total, 0.001)
