# SquadFireController.gd
extends Node
class_name SquadFireController

# Wiring
@export var unit: Node2D
@export var combat: Node
@export var stress_controller_path: NodePath
@export var ground_map: HexagonTileMapLayer

# Timing
@export var burst_window_s: float = 0.10      # batch rounds within this window per hex
@export var max_shots_per_tick: int = 128

# State influence (from your STATES table)
@export var state_acc_mults: PackedFloat32Array = PackedFloat32Array([1.0, 0.9, 0.5, 0.0, 0.0])
@export var state_rof_mults: PackedFloat32Array = PackedFloat32Array([1.0, 0.85, 0.35, 0.0, 0.0])

# Crew-served behaviour
@export var crew_idle_to_loader: bool = true

# Soldiers
var soldiers: Array[Soldier] = []
var _now_s: float = 0.0
var _accum_window_s: float = 0.0

# Targeting
var target_hex: Vector2i
var _pending_rounds_by_hex: Dictionary = {}    # Vector2i -> int

# Cached refs
var _stress: Node = null

func _ready() -> void:
	if stress_controller_path != NodePath(""):
		_stress = get_node(stress_controller_path)
	# optional sanity
	if combat == null and unit != null:
		if unit.has_node("Combat"):
			combat = unit.get_node("Combat")

func set_soldiers(list: Array[Soldier]) -> void:
	soldiers = list

func set_target_hex(hx: Vector2i) -> void:
	target_hex = hx

func _physics_process(delta: float) -> void:
	_now_s += delta
	_accum_window_s += delta

	_update_state_multipliers()
	_tick_soldiers(delta)

	if _accum_window_s >= burst_window_s:
		_flush_burst_window()

func _update_state_multipliers() -> void:
	var state_idx: int = 0
	if _stress != null:
		if _stress.has_variable("state"):
			state_idx = int(_stress.state)
	var acc_mult: float = 1.0
	var rof_mult: float = 1.0
	if state_idx >= 0 and state_idx < state_acc_mults.size():
		acc_mult = state_acc_mults[state_idx]
	if state_idx >= 0 and state_idx < state_rof_mults.size():
		rof_mult = state_rof_mults[state_idx]

	var i: int = 0
	while i < soldiers.size():
		var s: Soldier = soldiers[i]
		if s.is_alive:
			s.acc_mult = acc_mult
			s.rof_mult = rof_mult
		i += 1

func _tick_soldiers(delta: float) -> void:
	var rounds_emitted: int = 0

	# count available crew for MGs
	var crew_available: int = _count_role(Soldier.Role.LOADER)
	var gunners: Array[int] = _indices_with_role(Soldier.Role.GUNNER)

	# handle gunners first (crew-served)
	var j: int = 0
	while j < gunners.size():
		var idx: int = gunners[j]
		var s: Soldier = soldiers[idx]
		if s.is_alive:
			rounds_emitted += _try_fire_soldier(s, true, crew_available)
			if rounds_emitted >= max_shots_per_tick:
				return
		j += 1

	# then everyone else
	var i: int = 0
	while i < soldiers.size():
		var s2: Soldier = soldiers[i]
		if s2.is_alive:
			if s2.role != Soldier.Role.GUNNER:
				rounds_emitted += _try_fire_soldier(s2, false, 0)
				if rounds_emitted >= max_shots_per_tick:
					return
		i += 1

func _try_fire_soldier(s: Soldier, is_crew_served: bool, crew_available: int) -> int:
	if target_hex == Vector2i():
		return 0
	if s.jammed:
		# simple unjam: use reload time as clear jam delay
		if s.next_ready_s <= _now_s:
			s.jammed = false
			s.next_ready_s = _now_s + s.weapon.reload_s
		return 0

	if s.next_ready_s > _now_s:
		return 0

	# check crew requirement
	var crew_mult: float = 1.0
	if is_crew_served:
		if s.weapon.crew_required > 1:
			var ok: bool = crew_available >= (s.weapon.crew_required - 1)
			if not ok:
				crew_mult = s.weapon.undercrew_penalty_mult

	# determine burst size for this weapon
	var shots: int = s.weapon.burst_rounds
	if shots < 1:
		shots = 1
	if shots > s.rounds_in_mag:
		shots = s.rounds_in_mag

	if shots <= 0:
		# reload
		s.next_ready_s = _now_s + s.weapon.reload_s
		s.rounds_in_mag = s.weapon.mag_capacity
		return 0

	# emit shots immediately into current window
	_add_rounds_to_hex(target_hex, shots)

	# apply jam chance
	var k: int = 0
	var jammed_now: bool = false
	while k < shots:
		var r: float = randf()
		if r < s.weapon.jam_per_shot:
			jammed_now = true
		k += 1
	if jammed_now:
		s.jammed = true

	# spend ammo
	s.rounds_in_mag -= shots

	# compute time to next burst:
	# firing time for shots at cyclic rpm + burst pause, scaled by ROF and crew
	var rps: float = s.weapon.cyclic_rpm / 60.0
	if rps < 1.0:
		rps = 1.0
	var fire_time_s: float = float(shots) / rps
	var pause_s: float = s.weapon.burst_pause_s
	var total_cadence_s: float = (fire_time_s + pause_s) * s.rof_mult * crew_mult

	s.next_ready_s = _now_s + total_cadence_s
	return shots

func _add_rounds_to_hex(hx: Vector2i, n: int) -> void:
	var cur: int = 0
	if _pending_rounds_by_hex.has(hx):
		cur = int(_pending_rounds_by_hex[hx])
	_pending_rounds_by_hex[hx] = cur + n

func _flush_burst_window() -> void:
	_accum_window_s = 0.0
	for hx in _pending_rounds_by_hex.keys():
		var rounds: int = int(_pending_rounds_by_hex[hx])
		if rounds > 0:
			_emit_burst_to_combat(hx, rounds)
	_pending_rounds_by_hex.clear()

func _emit_burst_to_combat(hx: Vector2i, rounds: int) -> void:
	if combat == null:
		return
	# Call your existing burst/volley entrypoint.
	# Expectation from earlier: resolve TOTAL rounds once per volley for that hex.
	if combat.has_method("fire_burst_total_rounds"):
		combat.call("fire_burst_total_rounds", unit, hx, rounds)
		return
	# Fallback: if you only have fire_at(), you can adapt it or add a proper method.


func _count_role(role: int) -> int:
	var c: int = 0
	var i: int = 0
	while i < soldiers.size():
		if soldiers[i].is_alive:
			if int(soldiers[i].role) == role:
				c += 1
		i += 1
	return c

func _indices_with_role(role: int) -> Array[int]:
	var res: Array[int] = []
	var i: int = 0
	while i < soldiers.size():
		if soldiers[i].is_alive:
			if int(soldiers[i].role) == role:
				res.append(i)
		i += 1
	return res
