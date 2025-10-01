class_name StressController
extends Node

# --- STATES (unchanged) ---
enum MoraleState { NORMAL, CAUTIOUS, PINNED, PANIC, COMBAT_INEFFECTIVE }

# --- TUNABLES (yours, kept) ---
@export var half_life_fast: float = 4.0          # seconds
@export var half_life_slow: float = 28.0         # seconds
@export var w_fast: float = 0.6
@export var w_slow: float = 0.4
@export var refractory_s: float = 1.2            # no flips for this long after a change
@export var leadership_bonus: float = 0.0        # 0..1, leader presence/quality
@export var cohesion: float = 1.0                # 0..1, formation & comms
@export var pin_threshold: float = 35.0          # stress scale is 0..S_CAP
@export var panic_threshold: float = 65.0
@export var recovery_bias: float = 0.85          # easier to climb back up if >0

# --- NEW: caps & scaling ---
@export var S_CAP: float = 100.0                 # hard ceiling on stress
@export var incoming_stress_scale: float = 1.0   # global multiplier on added stress
@export var recovery_scale: float = 1.0          # >1 faster decay, <1 slower decay (global)

# --- NEW: slower recovery while under fire ---
@export var under_fire_window_s: float = 2.0     # seconds considered "under fire" after a volley
@export var pressure_ref_rps: float = 10.0       # rounds/sec counted as "heavy"
@export var slowdown_light: float = 0.4          # decay-rate multiplier at light pressure
@export var slowdown_heavy: float = 0.1         # decay-rate multiplier at heavy pressure
@export var stop_fast_decay_when_heavy: bool = false  # freeze fast-stress decay at heavy pressure

# --- STATE ---
var stress_fast: float = 0.0
var stress_slow: float = 0.0
var S_eff: float = 0.0
var state: int = MoraleState.NORMAL
var _since_change: float = 999.0

# --- RUNTIME (under fire) ---
var _under_fire_t: float = 0.0
var _last_pressure_rps: float = 0.0

# --- SIGNALS ---
signal state_changed(previous: int, next: int)
signal stress_changed(effective_stress: float)

func _physics_process(delta: float) -> void:
	# decay using exponential form so we can scale the *rate* cleanly
	var ln2: float = 0.69314718056
	var lambda_fast: float = 0.0
	var lambda_slow: float = 0.0

	if half_life_fast > 0.0:
		lambda_fast = ln2 * delta / half_life_fast
	if half_life_slow > 0.0:
		lambda_slow = ln2 * delta / half_life_slow

	# global recovery scaling
	if recovery_scale < 0.0:
		recovery_scale = 0.0
	lambda_fast *= recovery_scale
	lambda_slow *= recovery_scale

	# slower decay while under fire
	if _under_fire_t > 0.0:
		var x: float = 0.0
		if pressure_ref_rps > 0.0:
			x = clamp(_last_pressure_rps / pressure_ref_rps, 0.0, 1.0)
		# map pressure to a rate multiplier between light and heavy slowdowns
		var rate_mult: float = lerp(slowdown_light, slowdown_heavy, x)
		if rate_mult < 0.0:
			rate_mult = 0.0
		lambda_fast *= rate_mult
		lambda_slow *= rate_mult
		# optional: freeze fast-stress under heavy pressure
		if stop_fast_decay_when_heavy:
			if _last_pressure_rps >= pressure_ref_rps:
				lambda_fast = 0.0

		_under_fire_t -= delta
		if _under_fire_t < 0.0:
			_under_fire_t = 0.0

	# turn rates into multipliers
	var kf: float = 1.0
	var ks: float = 1.0
	if lambda_fast > 0.0:
		kf = exp(-lambda_fast)
	if lambda_slow > 0.0:
		ks = exp(-lambda_slow)

	# apply decay
	stress_fast *= kf
	stress_slow *= ks
	_clamp_bins()

	# effective stress with leadership & cohesion softening
	var softener: float = 1.0 - clamp(0.5 * leadership_bonus + 0.3 * cohesion, 0.0, 0.6)
	S_eff = (w_fast * stress_fast + w_slow * stress_slow) * softener
	if S_eff < 0.0:
		S_eff = 0.0
	if S_eff > S_CAP:
		S_eff = S_CAP

	_since_change += delta
	_maybe_transition(delta)
	stress_changed.emit(S_eff)

# add stress from events/volleys
func apply_stress(df: float, ds: float) -> void:
	if df < 0.0:
		df = 0.0
	if ds < 0.0:
		ds = 0.0
	var scale: float = incoming_stress_scale
	if scale < 0.0:
		scale = 0.0
	stress_fast += df * scale
	stress_slow += ds * scale
	_clamp_bins()

# casualty shock (kept yours, can be tuned)
func on_casualty_event(n: int, leader_down: bool = false) -> void:
	if n < 0:
		n = 0
	stress_fast += 18.0 * float(n)
	stress_slow += 6.0 * float(n)
	if leader_down:
		stress_fast += 22.0
		stress_slow += 10.0
	_clamp_bins()

# call this whenever rounds crack overhead (per volley)
func mark_under_fire(pressure_rps: float) -> void:
	if pressure_rps < 0.0:
		pressure_rps = 0.0
	_last_pressure_rps = pressure_rps
	_under_fire_t = under_fire_window_s

# state machine (unchanged logic)
func _maybe_transition(delta: float) -> void:
	if _since_change < refractory_s:
		return

	var roll: float = randf()

	match state:
		MoraleState.NORMAL:
			if S_eff >= panic_threshold and roll < _rate_to_prob(0.6, delta):
				_set_state(MoraleState.PANIC)
			elif S_eff >= pin_threshold and roll < _rate_to_prob(0.45, delta):
				_set_state(MoraleState.PINNED)
			elif S_eff >= pin_threshold * 0.7 and roll < _rate_to_prob(0.3, delta):
				_set_state(MoraleState.CAUTIOUS)

		MoraleState.CAUTIOUS:
			if S_eff >= panic_threshold and roll < _rate_to_prob(0.5, delta):
				_set_state(MoraleState.PANIC)
			elif S_eff < pin_threshold * 0.6 and roll < _rate_to_prob(0.35 * recovery_bias, delta):
				_set_state(MoraleState.NORMAL)
			elif S_eff >= pin_threshold and roll < _rate_to_prob(0.4, delta):
				_set_state(MoraleState.PINNED)

		MoraleState.PINNED:
			if S_eff >= panic_threshold and roll < _rate_to_prob(0.45, delta):
				_set_state(MoraleState.PANIC)
			elif S_eff < pin_threshold * 0.6 and roll < _rate_to_prob(0.25 * recovery_bias, delta):
				_set_state(MoraleState.CAUTIOUS)

		MoraleState.PANIC:
			if S_eff < pin_threshold * 0.7 and roll < _rate_to_prob(0.18 * recovery_bias, delta):
				_set_state(MoraleState.CAUTIOUS)

func _rate_to_prob(rate_per_sec: float, dt: float) -> float:
	if rate_per_sec < 0.0:
		rate_per_sec = 0.0
	return 1.0 - exp(-rate_per_sec * dt)

func _set_state(next: int) -> void:
	if next == state:
		return
	var prev: int = state
	state = next
	_since_change = 0.0
	state_changed.emit(prev, next)

func _clamp_bins() -> void:
	if stress_fast < 0.0:
		stress_fast = 0.0
	if stress_slow < 0.0:
		stress_slow = 0.0
	if stress_fast > S_CAP:
		stress_fast = S_CAP
	if stress_slow > S_CAP:
		stress_slow = S_CAP
