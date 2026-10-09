class_name PositionQueryJob
extends RefCounted

enum Phase { AREA, INITIALIZE, SUPPORT, FILTER, FLOOD, EVALUATE, FINISH }

var query: PositionQuery
var result: PositionResult = PositionResult.new()
var completed: bool = false
var canceled: bool = false
var phase: Phase = Phase.AREA
var indices: Array[int] = []
var cursor: int = 0
var fallback: bool = false
var candidates: Array[PositionCandidate] = []
var support_duties: Array[Dictionary] = []
var support_units: Array[Unit] = []
var support_cursor: int = 0
var profile_prepared: bool = false


func advance(deadline_usec: int) -> void:
	while not completed and not canceled and (deadline_usec < 0 or Time.get_ticks_usec() < deadline_usec):
		match phase:
			Phase.AREA:
				if not profile_prepared:
					if HqSupportPositionPolicy.is_headquarters(query.unit):
						HqSupportPositionPolicy.configure(query)
					profile_prepared = true
				if query.area_job != null and (query.snapshot == null or query.area_job.objective != query.objective_hex or query.area_job.result.snapshot_version != query.snapshot.version):
					query.area_job = null
					query.defense_area = null
				if query.defense_area != null and (query.profile.mode != PositionProfile.Mode.DEFEND or query.snapshot == null or query.defense_area.objective_hex != query.objective_hex or query.defense_area.snapshot_version != query.snapshot.version):
					query.defense_area = null
					query.area_job = null
				if query.use_defense_area and query.profile.mode == PositionProfile.Mode.DEFEND and query.defense_area == null and query.area_job == null and query.snapshot != null and query.snapshot.maps.has(query.team) and InfluenceUnitQuery.is_valid_living_unit(query.unit) and query.unit.team == query.team:
					var axes: Array[ThreatAxis] = []
					if query.axis != null:
						axes.append(query.axis)
					query.area_job = query.snapshot.defense_area_job(query.team, query.objective_hex, query.defense_radius, maxi(query.defense_radius + 2, 10), axes)
				if query.area_job != null:
					query.area_job.advance(deadline_usec)
					if not query.area_job.completed:
						return
					query.defense_area = query.area_job.result
				if query.defense_area != null and query.axis != null and query.assigned_sector < 0 and not query.reserve_position and query.defense_responsibility not in [PositionQuery.Responsibility.OCCUPY, PositionQuery.Responsibility.GUARD]:
					query.assigned_sector = query.defense_area.sector_at(query.axis.source_hex)
				phase = Phase.INITIALIZE
			Phase.INITIALIZE:
				if not PositionQueryService.initialize(query, result):
					completed = true
				else:
					phase = Phase.FILTER
					if query.profile.mode == PositionProfile.Mode.DEFEND and query.defense_area != null:
						support_duties = query.defense_area.support_duties(query)
						support_units.assign(query.snapshot.positions.keys())
						phase = Phase.SUPPORT
			Phase.SUPPORT:
				if cursor < support_duties.size():
					var duty: Dictionary = support_duties[cursor]
					if support_cursor < support_units.size():
						query.defense_area.warm_support(query, duty, support_units[support_cursor])
						support_cursor += 1
					else:
						query.defense_area.warm_support(query, duty, null)
						support_cursor = 0
						cursor += 1
				else:
					cursor = 0
					phase = Phase.FILTER
			Phase.FILTER:
				if cursor < query.snapshot.maps[query.team].cell_count:
					if PositionQueryService.prepare_candidate(query, cursor, fallback, result):
						indices.append(cursor)
					cursor += 1
				else:
					cursor = 0
					phase = Phase.EVALUATE
					if query.profile.mode in [PositionProfile.Mode.DEFEND, PositionProfile.Mode.HQ_SUPPORT] and not indices.is_empty():
						var targets: Array[Vector2i] = []
						for index: int in indices:
							targets.append(query.snapshot.maps[query.team].index_to_cell(index))
						query.route_field = PositionRouteField.new()
						query.route_field.start(query, targets)
						phase = Phase.FLOOD
			Phase.FLOOD:
				query.route_field.advance(deadline_usec)
				if query.route_field.completed:
					phase = Phase.EVALUATE
			Phase.EVALUATE:
				if cursor < indices.size():
					var candidate: PositionCandidate = PositionQueryService.evaluate_candidate(query, indices[cursor], result)
					if candidate != null:
						candidates.append(candidate)
					cursor += 1
				else:
					phase = Phase.FINISH
					if candidates.is_empty() and not fallback and not query.fallback_hexes.is_empty():
						fallback = true
						cursor = 0
						indices.clear()
						phase = Phase.FILTER
			Phase.FINISH:
				PositionQueryService.finish(query, result, candidates)
				if query.route_field != null:
					query.route_field.release_query()
				completed = true


func cancel() -> void:
	canceled = true
	if query.route_field != null:
		query.route_field.release_query()
