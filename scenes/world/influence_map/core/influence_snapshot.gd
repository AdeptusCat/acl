class_name InfluenceSnapshot
extends RefCounted


class ForecastCache extends RefCounted:
	const MAX_ENTRIES: int = 64

	var entries: Dictionary[Array, PackedFloat32Array] = {}
	var hits: int = 0
	var builds: int = 0


	func store(key: Array, values: PackedFloat32Array) -> void:
		if not entries.has(key) and entries.size() >= MAX_ENTRIES:
			entries.erase(entries.keys()[0])
		entries[key] = values.duplicate()


	func clear() -> void:
		entries.clear()
		hits = 0
		builds = 0


class ForecastJob extends RefCounted:
	enum Phase { PREPARE, VALIDATE, CACHE, PROJECT, FINISH }

	var completed: bool = false
	var reused: bool = false
	var data: PackedFloat32Array = PackedFloat32Array()
	var phase: Phase = Phase.PREPARE
	var projected_cells: int = 0
	var bounds: Rect2i
	var los: Dictionary = {}
	var contacts: Array[InfluenceContact] = []
	var sources: Array[ProjectionSource] = []
	var cache: ForecastCache
	var config: InfluenceProjectionConfig = InfluenceProjectionConfig.new()
	var context: Array = []
	var base_context: Array = []
	var row_hashes: Dictionary[Vector2i, int] = {}
	var observers: Array[Vector2i] = []
	var validation_index: int = 0
	var validated_phase: Phase = Phase.CACHE
	var contact_index: int = 0
	var source_index: int = 0
	var target_index: int = 0
	var targets: Array = []
	var visible: Dictionary = {}
	var source_ready: bool = false
	var cache_key: Array = []


	func start(snapshot: InfluenceSnapshot, team: int, objective: Vector2i) -> void:
		bounds = snapshot.maps[team].bounds
		los = snapshot.los
		cache = snapshot.forecast_cache
		config.objective_hex = objective
		var ground: HexagonTileMapLayer = LOSHelper.ground_layer
		context = [team, objective, bounds, snapshot.terrain_key, ground.get_instance_id(),
			ground.tile_set.tile_layout, ground.tile_set.tile_offset_axis,
			config.projected_line_max_cells, config.los_skip_front, config.los_count]
		base_context = context.duplicate()
		# Keep the job's captured capabilities stable even if a caller edits a contact.
		for captured: InfluenceContact in snapshot.get_contacts(team):
			var contact: InfluenceContact = InfluenceContact.new()
			contact.hex = captured.hex
			contact.confidence = captured.confidence
			contact.firepower = captured.firepower
			contact.effectiveness = captured.effectiveness
			contact.weapon_range = captured.weapon_range
			contacts.append(contact)


	func advance(deadline_usec: int) -> void:
		while not completed and (deadline_usec < 0 or Time.get_ticks_usec() < deadline_usec):
			match phase:
				Phase.PREPARE:
					if contact_index >= contacts.size():
						cache_key = context
						validated_phase = Phase.CACHE
						validation_index = 0
						phase = Phase.VALIDATE
						continue
					var contact: InfluenceContact = contacts[contact_index]
					context.append([contact.hex, contact.confidence, contact.firepower, contact.effectiveness, contact.weapon_range])
					var projected: Array[ProjectionSource] = ProjectionSourceBuilder.build_from_contacts([contact], config)
					for source: ProjectionSource in projected:
						if not row_hashes.has(source.observer_hex):
							row_hashes[source.observer_hex] = hash(los.get(source.observer_hex, {}))
							observers.append(source.observer_hex)
						context.append([source.observer_hex, row_hashes[source.observer_hex]])
						sources.append(source)
					contact_index += 1
				Phase.VALIDATE:
					if validation_index >= observers.size():
						phase = validated_phase
						continue
					var observer: Vector2i = observers[validation_index]
					if hash(los.get(observer, {})) != row_hashes[observer]:
						_restart()
						continue
					validation_index += 1
				Phase.CACHE:
					if cache.entries.has(cache_key):
						data = cache.entries[cache_key].duplicate()
						cache.hits += 1
						reused = true
						completed = true
						continue
					data.resize(bounds.size.x * bounds.size.y)
					cache.builds += 1
					phase = Phase.PROJECT
				Phase.PROJECT:
					if source_index >= sources.size():
						validated_phase = Phase.FINISH
						validation_index = 0
						phase = Phase.VALIDATE
						continue
					var source: ProjectionSource = sources[source_index]
					if not source_ready:
						visible = los.get(source.observer_hex, {})
						targets = visible.keys()
						target_index = 0
						source_ready = true
					if target_index >= targets.size():
						source_index += 1
						source_ready = false
						continue
					var target: Vector2i = targets[target_index]
					target_index += 1
					if not bounds.has_point(target):
						continue
					var distance: int = LOSHelper.get_hex_distance(source.observer_hex, target)
					if distance > source.weapon_range:
						continue
					var record: Dictionary = visible[target]
					var index: int = (target.y - bounds.position.y) * bounds.size.x + target.x - bounds.position.x
					data[index] += LosInfluenceProjector.calculate_los_fire_threat(source.firepower, source.effectiveness,
						record.get("target_cover", 0.0), record.get("hindrance", 0.0), distance)
					projected_cells += 1
				Phase.FINISH:
					cache.store(cache_key, data)
					completed = true


	func _restart() -> void:
		# A LOS edit during projection must not publish mixed inputs under an old key.
		context = base_context.duplicate()
		row_hashes.clear()
		observers.clear()
		sources.clear()
		data = PackedFloat32Array()
		contact_index = 0
		source_index = 0
		source_ready = false
		projected_cells = 0
		phase = Phase.PREPARE



var version: int = 0
var captured_at: float = 0.0
var maps: Dictionary[int, InfluenceMap] = {}
var contacts: Dictionary[int, Array] = {}
var defensive_contacts: Dictionary[int, Array] = {}
var sector_pressure: Dictionary[int, Dictionary] = {}
var positions: Dictionary[Unit, Vector2i] = {}
var teams: Dictionary[Unit, int] = {}
var support_units: Dictionary[Unit, Dictionary] = {}
var routes: Dictionary[int, AStar2D] = {}
var point_ids: Dictionary[int, Dictionary] = {}
var objectives: Dictionary[int, Vector2i] = {}
var los: Dictionary = {}
var _forecast_jobs: Dictionary[int, Dictionary] = {}
var forecast_cache: ForecastCache = ForecastCache.new()
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


func request_forecast(team: int, objective: Vector2i) -> ForecastJob:
	if not _forecast_jobs.has(team):
		_forecast_jobs[team] = {}
	if not _forecast_jobs[team].has(objective):
		var job: ForecastJob = ForecastJob.new()
		if not maps.has(team):
			job.completed = true
		elif objectives.get(team) == objective:
			job.data = maps[team].get_layer_data_copy(InfluenceMap.Layer.FORECAST_THREAT)
			job.completed = true
		else:
			job.start(self, team, objective)
		_forecast_jobs[team][objective] = job
	return _forecast_jobs[team][objective]


func get_forecast_data(team: int, objective: Vector2i) -> PackedFloat32Array:
	# Explicit synchronous callers retain this API; live queries advance the shared job.
	var job: ForecastJob = request_forecast(team, objective)
	job.advance(-1)
	return job.data
