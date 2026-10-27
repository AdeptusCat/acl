class_name PlatoonPositionStability
extends RefCounted

const IMPROVEMENT_SECONDS: float = 3.0
const FOLLOW_SECONDS: float = 2.0
const IMPROVEMENT_ABSOLUTE: float = 1.0
const IMPROVEMENT_RELATIVE: float = 0.25

var orders: Dictionary[Unit, Dictionary] = {}
var optional_mover: Unit
var support_anchor: Unit
var _optional_started: bool = false
var _proposals: Dictionary[Unit, Dictionary] = {}
var _follow_gaps: Dictionary[Unit, Dictionary] = {}
var _idle_support_since: Dictionary[Unit, float] = {}
var _hq_priorities: Dictionary[Unit, Unit] = {}
var _hq_contenders: Dictionary[Unit, Dictionary] = {}
var _screen_objectives: Dictionary[Unit, Vector2i] = {}
var _anchor_contender: Unit
var _anchor_since: float = -INF


func clear() -> void:
	orders.clear()
	_proposals.clear()
	_follow_gaps.clear()
	_idle_support_since.clear()
	_hq_priorities.clear()
	_hq_contenders.clear()
	_screen_objectives.clear()
	optional_mover = null
	support_anchor = null
	_anchor_contender = null
	_optional_started = false


static func is_busy(unit: Unit) -> bool:
	return unit.movement.is_moving or unit.action_controller.action_state == SquadActionController.SquadActionState.ESTABLISHING_POSITION


func observe(units: Array[Unit], now: float) -> void:
	for unit: Unit in _screen_objectives.keys():
		if not units.has(unit):
			_screen_objectives.erase(unit)
	for unit: Unit in orders.keys():
		if not units.has(unit) or not TacticalPositionExecutor.is_active_defender(unit):
			forget(unit)
			continue
		var record: Dictionary = orders[unit]
		if unit.action_controller.action_order_id != record["order_id"]:
			forget(unit)
			continue
		if not is_busy(unit) and unit.current_hex == record["result"].target_hex and unit.action_controller.action_state == SquadActionController.SquadActionState.HOLDING_POSITION:
			if record.get("screen_deployment", false):
				_screen_objectives[unit] = record["result"].objective_hex
			if record["settled_at"] == -INF:
				record["settled_at"] = now
			if optional_mover == unit and _optional_started:
				optional_mover = null
				_optional_started = false


func forget(unit: Unit) -> void:
	orders.erase(unit)
	_proposals.erase(unit)
	_follow_gaps.erase(unit)
	_idle_support_since.erase(unit)
	_hq_priorities.erase(unit)
	_hq_contenders.erase(unit)
	if optional_mover == unit:
		optional_mover = null
		_optional_started = false


func release_unstarted_optional() -> void:
	if not _optional_started:
		optional_mover = null


func accepted(result: PositionResult, now: float) -> void:
	if not result.is_valid():
		return
	var unit: Unit = result.unit
	if result.position_profile == null:
		result.position_profile = PositionProfile.for_mode(result.profile_mode)
	var previous: Dictionary = orders.get(unit, {})
	var settled_at: float = -INF
	if not previous.is_empty() and previous["result"].target_hex == result.target_hex and previous["result"].profile_mode == result.profile_mode:
		settled_at = previous["settled_at"]
	if not is_busy(unit) and unit.current_hex == result.target_hex and unit.action_controller.action_state == SquadActionController.SquadActionState.HOLDING_POSITION and settled_at == -INF:
		settled_at = now
	var screen_deployment: bool = result.profile_mode == PositionProfile.Mode.DEFEND and result.features.get("responsibility", "") == "cover_approach" and not result.features.get("screen_fallback", false)
	if not previous.is_empty() and previous["result"].target_hex == result.target_hex and previous["result"].objective_hex == result.objective_hex and previous["result"].profile_mode == result.profile_mode:
		# Updated approach evidence must not turn a checked, unfinished deployment into another advance.
		screen_deployment = screen_deployment or previous.get("screen_deployment", false)
	orders[unit] = {"result": result, "order_id": unit.action_controller.action_order_id, "settled_at": settled_at, "screen_deployment": screen_deployment}
	if screen_deployment and settled_at != -INF:
		_screen_objectives[unit] = result.objective_hex
	if not HqSupportPositionPolicy.is_headquarters(unit) and result.features.get("movement_kind", "") == "optional" and result.should_move:
		optional_mover = unit
		_optional_started = true
	elif optional_mover == unit and not _optional_started:
		optional_mover = null
	if result.should_move:
		_proposals.erase(unit)


func has_deployed_screen(unit: Unit, objective: Vector2i) -> bool:
	return _screen_objectives.has(unit) and _screen_objectives[unit] == objective


func declined(unit: Unit) -> void:
	if optional_mover == unit and not _optional_started:
		optional_mover = null


func prepare(query: PositionQuery) -> void:
	query.stable_order = null
	query.finish_accepted_order = false
	query.movement_kind = ""
	query.stability_reason = ""
	var record: Dictionary = orders.get(query.unit, {})
	if record.is_empty() or record["order_id"] != query.unit.action_controller.action_order_id:
		return
	# A usable passage releases a firing bound; a new blocker requires a new breach plan.
	if record["result"].features.get("escape", false) != (query.escape_policy != null):
		return
	query.stable_order = record["result"]
	query.has_accepted_target = true
	query.accepted_target = query.stable_order.target_hex
	query.finish_accepted_order = is_busy(query.unit)
	if query.finish_accepted_order:
		# Fire selection may change, but the physical order survives until setup finishes.
		var fire_objective: Vector2i = query.objective_hex
		query.profile = query.stable_order.position_profile.duplicate() as PositionProfile
		query.objective_hex = query.stable_order.objective_hex
		if query.profile.mode == PositionProfile.Mode.SUPPORT_BY_FIRE:
			query.objective_hex = fire_objective
	query.accepted_context = query.context_key()
	query.accepted_at = record["settled_at"]


func minimum_hold_active(query: PositionQuery) -> bool:
	var record: Dictionary = orders.get(query.unit, {})
	if record.is_empty():
		return false
	var seconds: float = 8.0
	if query.unit.squad_type == Globals.SquadType.MG:
		seconds = 16.0
	return record["settled_at"] == -INF or query.stability_time - record["settled_at"] < seconds


func authorize(query: PositionQuery, best: PositionCandidate, retained: PositionCandidate) -> bool:
	query.movement_kind = "necessary"
	query.stability_reason = ""
	if query.stable_order == null or retained == null:
		if query.deliberate_movement:
			query.movement_kind = "attack"
		_proposals.erase(query.unit)
		return true
	var requires_follow: bool = follow_required(query, retained.features)
	if best.hex == retained.hex:
		_proposals.erase(query.unit)
		return true
	if query.deliberate_movement:
		query.movement_kind = "attack"
		_proposals.erase(query.unit)
		return true
	if query.profile.mode == PositionProfile.Mode.DEFEND and DefensePositionPolicy.needs_interception(query, retained.features) and best.features.get("interposition", 0.0) > retained.features.get("interposition", 0.0):
		# Intercepting a confirmed enemy past the screen is a necessary defensive action.
		query.movement_kind = "necessary"
		_proposals.erase(query.unit)
		return true
	if requires_follow:
		query.movement_kind = "follow"
		_proposals.erase(query.unit)
		return true
	query.movement_kind = "optional"
	var margin: float = maxf(IMPROVEMENT_ABSOLUTE, absf(retained.score) * IMPROVEMENT_RELATIVE)
	if best.score <= retained.score + margin:
		_proposals.erase(query.unit)
		query.stability_reason = "Holding a useful position; improvement is too small"
		return false
	var proposal: Dictionary = _proposals.get(query.unit, {})
	if proposal.get("hex") != best.hex or proposal.get("context") != query.context_key():
		proposal = {"hex": best.hex, "context": query.context_key(), "since": query.stability_time}
		_proposals[query.unit] = proposal
	if minimum_hold_active(query):
		query.stability_reason = "Holding after setup; minimum position commitment remains"
		return false
	if query.stability_time - proposal["since"] < IMPROVEMENT_SECONDS:
		query.stability_reason = "Holding a useful position while the improvement persists"
		return false
	if not HqSupportPositionPolicy.is_headquarters(query.unit):
		if is_instance_valid(optional_mover) and optional_mover != query.unit:
			query.stability_reason = "Holding while another combat squad finishes optional repositioning"
			return false
		optional_mover = query.unit
		_optional_started = false
	return true


func follow_required(query: PositionQuery, features: Dictionary) -> bool:
	var target: Unit = null
	var gap: bool = false
	if query.profile.mode == PositionProfile.Mode.HQ_SUPPORT:
		target = features.get("support_priority_squad") as Unit
		gap = features.get("support_priority_need", 0.0) >= 0.35 and not features.get("support_priority_covered", false)
	elif query.has_support_anchor:
		target = query.support_anchor_squad
		gap = LOSHelper.get_hex_distance(query.origin_hex, query.support_anchor_hex) > query.support_anchor_radius
	if not gap or not is_instance_valid(target):
		_follow_gaps.erase(query.unit)
		return false
	var record: Dictionary = _follow_gaps.get(query.unit, {})
	if record.get("unit") != target:
		record = {"unit": target, "since": query.stability_time}
		_follow_gaps[query.unit] = record
	return query.stability_time - record["since"] >= FOLLOW_SECONDS


func support_lane_failed(unit: Unit, objective: Vector2i, now: float) -> bool:
	if not orders.has(unit) or is_busy(unit) or unit.action_controller.action_state != SquadActionController.SquadActionState.HOLDING_POSITION or TacticalPositionExecutor.select_support_target_for_objective(unit, objective) != null:
		_idle_support_since.erase(unit)
		return false
	if not _idle_support_since.has(unit):
		_idle_support_since[unit] = now
	return now - _idle_support_since[unit] >= FOLLOW_SECONDS


func headquarters_priority(query: PositionQuery, candidate: Unit) -> Unit:
	var preferred: Unit = _hq_priorities.get(query.unit)
	if not query.support_targets.has(preferred):
		preferred = candidate
		_hq_priorities[query.unit] = preferred
	if candidate == preferred or candidate == null:
		_hq_contenders.erase(query.unit)
		return preferred
	if is_busy(query.unit) or query.support_targets[candidate]["need"] <= query.support_targets[preferred]["need"] + 0.35:
		_hq_contenders.erase(query.unit)
		return preferred
	var contender: Dictionary = _hq_contenders.get(query.unit, {})
	if contender.get("unit") != candidate:
		contender = {"unit": candidate, "since": query.stability_time}
		_hq_contenders[query.unit] = contender
	if query.stability_time - contender["since"] >= FOLLOW_SECONDS:
		_hq_priorities[query.unit] = candidate
		_hq_contenders.erase(query.unit)
		return candidate
	return preferred


func choose_support_anchor(candidate: Unit, units: Array[Unit], objective: Vector2i, now: float) -> Unit:
	if not units.has(support_anchor) or not TacticalPositionExecutor.is_active_defender(support_anchor):
		support_anchor = candidate
		_anchor_contender = null
		return support_anchor
	for unit: Unit in units:
		if unit.squad_type == Globals.SquadType.Rifle and (is_busy(unit) or unit.in_close_combat):
			return support_anchor
	if candidate == null or candidate == support_anchor or LOSHelper.get_hex_distance(candidate.current_hex, objective) + 1 >= LOSHelper.get_hex_distance(support_anchor.current_hex, objective):
		_anchor_contender = null
		return support_anchor
	if _anchor_contender != candidate:
		_anchor_contender = candidate
		_anchor_since = now
	if now - _anchor_since >= FOLLOW_SECONDS:
		support_anchor = candidate
		_anchor_contender = null
	return support_anchor
