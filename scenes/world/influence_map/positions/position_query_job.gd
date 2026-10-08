class_name PositionQueryJob
extends RefCounted

enum Phase { INITIALIZE, FILTER, FLOOD, EVALUATE, FINISH }

var query: PositionQuery
var result: PositionResult = PositionResult.new()
var completed: bool = false
var canceled: bool = false
var phase: Phase = Phase.INITIALIZE
var indices: Array[int] = []
var cursor: int = 0
var fallback: bool = false
var candidates: Array[PositionCandidate] = []


func advance(deadline_usec: int) -> void:
	while not completed and not canceled and (deadline_usec < 0 or Time.get_ticks_usec() < deadline_usec):
		match phase:
			Phase.INITIALIZE:
				if not PositionQueryService.initialize(query, result):
					completed = true
				else:
					phase = Phase.FILTER
			Phase.FILTER:
				if cursor < query.snapshot.maps[query.team].cell_count:
					if PositionQueryService.prepare_candidate(query, cursor, fallback, result):
						indices.append(cursor)
					cursor += 1
				else:
					cursor = 0
					phase = Phase.EVALUATE
					if query.profile.mode == PositionProfile.Mode.DEFEND and not indices.is_empty():
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
