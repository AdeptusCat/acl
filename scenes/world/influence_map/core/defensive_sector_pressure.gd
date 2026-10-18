class_name DefensiveSectorPressure
extends RefCounted

const SAMPLE_SECONDS: float = 4.0
const HIDDEN_WEIGHT: float = 0.25
const SMOOTHING: float = 0.5

var context: String = ""
var sampled_at: float = -INF
var pending: Dictionary[int, Dictionary] = {}
var published: Dictionary[int, Dictionary] = {}


func clear() -> void:
	context = ""
	sampled_at = -INF
	pending.clear()
	published.clear()


func capture_into(snapshot: InfluenceSnapshot, defending_team: int) -> void:
	if not snapshot.objectives.has(defending_team):
		clear()
		return
	var objective: Vector2i = snapshot.objectives[defending_team]
	var next_context: String = str([defending_team, objective])
	if next_context != context:
		clear()
		context = next_context
	if snapshot.captured_at - sampled_at >= SAMPLE_SECONDS:
		if is_finite(sampled_at):
			_publish_pending()
		pending = _sample(snapshot, defending_team, objective)
		sampled_at = snapshot.captured_at
	# Only delayed aggregates leave this sampler: no hidden unit identity, position or weapon.
	snapshot.sector_pressure[defending_team] = published.duplicate(true)


func _sample(snapshot: InfluenceSnapshot, team: int, objective: Vector2i) -> Dictionary[int, Dictionary]:
	var observed: Dictionary[Unit, bool] = {}
	for contact: InfluenceContact in snapshot.get_contacts(team):
		if contact.observed:
			observed[contact.unit] = true
	var result: Dictionary[int, Dictionary] = {}
	for unit: Unit in snapshot.positions:
		if snapshot.teams[unit] == team or observed.has(unit):
			continue
		var hex: Vector2i = snapshot.positions[unit]
		var sector: int = DefenseAreaAssessment.sector_for(objective, hex)
		var distance: int = LOSHelper.get_hex_distance(objective, hex)
		var arrival: float = 40.0
		if distance <= 3:
			arrival = 8.0
		elif distance <= 7:
			arrival = 20.0
		if not result.has(sector):
			result[sector] = {"pressure": 0.0, "arrival_seconds": arrival}
		result[sector]["pressure"] = minf(0.75, result[sector]["pressure"] + HIDDEN_WEIGHT)
		result[sector]["arrival_seconds"] = minf(result[sector]["arrival_seconds"], arrival)
	return result


func _publish_pending() -> void:
	for sector: int in range(6):
		var old: Dictionary = published.get(sector, {})
		var next: Dictionary = pending.get(sector, {})
		var pressure: float = lerpf(old.get("pressure", 0.0), next.get("pressure", 0.0), SMOOTHING)
		if pressure < 0.03:
			published.erase(sector)
			continue
		var arrival: float = lerpf(old.get("arrival_seconds", next.get("arrival_seconds", 40.0)), next.get("arrival_seconds", 40.0), SMOOTHING)
		published[sector] = {"pressure": pressure, "arrival_seconds": arrival}
