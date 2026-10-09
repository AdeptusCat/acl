class_name InfluenceSnapshot
extends RefCounted

var version: int = 0
var captured_at: float = 0.0
var maps: Dictionary[int, InfluenceMap] = {}
var contacts: Dictionary[int, Array] = {}
var defensive_contacts: Dictionary[int, Array] = {}
var sector_pressure: Dictionary[int, Dictionary] = {}
var positions: Dictionary[Unit, Vector2i] = {}
var teams: Dictionary[Unit, int] = {}
var routes: Dictionary[int, AStar2D] = {}
var point_ids: Dictionary[int, Dictionary] = {}
var objectives: Dictionary[int, Vector2i] = {}
var los: Dictionary = {}
var _forecasts: Dictionary[int, Dictionary] = {}
var terrain_key: int = 0
var route_topology_key: int = 0
var defense_geometry_cache: Dictionary = {}
var defense_area_jobs: Dictionary[String, DefenseAreaJob] = {}


func defense_area_job(team: int, objective: Vector2i, radius: int = 8, horizon: int = 12, axes: Array[ThreatAxis] = []) -> DefenseAreaJob:
	var axis_context: Array = []
	for axis: ThreatAxis in axes:
		axis_context.append([axis.source_hex, axis.confidence])
	var key: String = str([team, objective, radius, horizon, axis_context])
	if not defense_area_jobs.has(key):
		var job: DefenseAreaJob = DefenseAreaJob.new()
		job.start(self, team, objective, radius, horizon, axes)
		defense_area_jobs[key] = job
	return defense_area_jobs[key]


func get_contacts(team: int) -> Array[InfluenceContact]:
	var result: Array[InfluenceContact] = []
	for contact: InfluenceContact in contacts.get(team, []):
		result.append(contact)
	return result


func get_defensive_contacts(team: int) -> Array[InfluenceContact]:
	var result: Array[InfluenceContact] = []
	for contact: InfluenceContact in defensive_contacts.get(team, contacts.get(team, [])):
		result.append(contact)
	return result


func get_path(team: int, from_hex: Vector2i, to_hex: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not routes.has(team):
		return result
	var ids: Dictionary = point_ids.get(team, {})
	if not ids.has(from_hex) or not ids.has(to_hex):
		return result
	var graph: AStar2D = routes[team]
	if graph.is_point_disabled(ids[from_hex]) or graph.is_point_disabled(ids[to_hex]):
		return result
	for id: int in graph.get_id_path(ids[from_hex], ids[to_hex]):
		result.append(LOSHelper.ground_layer.local_to_map(graph.get_point_position(id)))
	return result


func get_forecast_data(team: int, objective: Vector2i) -> PackedFloat32Array:
	if not maps.has(team):
		return PackedFloat32Array()
	if not _forecasts.has(team):
		_forecasts[team] = {}
	if not _forecasts[team].has(objective):
		var data: PackedFloat32Array
		if objectives.get(team) == objective:
			data = maps[team].get_layer_data_copy(InfluenceMap.Layer.FORECAST_THREAT)
		else:
			# Mission-specific forecasts share captured knowledge without changing published maps.
			var forecast: InfluenceMap = InfluenceMap.new()
			forecast.configure(maps[team].bounds)
			var config: InfluenceProjectionConfig = InfluenceProjectionConfig.new()
			config.objective_hex = objective
			for source: ProjectionSource in ProjectionSourceBuilder.build_from_contacts(get_contacts(team), config):
				LosInfluenceProjector.project_los_from_source(forecast, source, false, los)
			data = forecast.get_layer_data_copy(InfluenceMap.Layer.FORECAST_THREAT)
		_forecasts[team][objective] = data
	return _forecasts[team][objective]
