# roll_stats.gd
class_name RollStats
extends Node

@export var bins: int = 20
@export var report_every: int = 5000  # print every N samples

var _counts: PackedInt32Array
var _n: int = 0
var _min_v: float = 1.0
var _max_v: float = 0.0
var _mean: float = 0.0
var _m2: float = 0.0  # for Welford variance

func _ready() -> void:
	_counts = PackedInt32Array()
	_counts.resize(bins)
	var i: int = 0
	while i < bins:
		_counts[i] = 0
		i += 1

func sample(v: float) -> void:
	# bounds
	if v < _min_v:
		_min_v = v
	if v > _max_v:
		_max_v = v
	# Welford running mean/variance
	_n += 1
	var delta: float = v - _mean
	_mean += delta / float(_n)
	var delta2: float = v - _mean
	_m2 += delta * delta2
	# histogram bin
	var idx: int = int(floor(v * float(bins)))
	if idx >= bins:
		idx = bins - 1
	_counts[idx] += 1
	# periodic report
	if (_n % report_every) == 0:
		report()

func reset() -> void:
	_n = 0
	_min_v = 1.0
	_max_v = 0.0
	_mean = 0.0
	_m2 = 0.0
	var i: int = 0
	while i < bins:
		_counts[i] = 0
		i += 1

func count() -> int:
	return _n

func mean() -> float:
	return _mean

func variance() -> float:
	if _n < 2:
		return 0.0
	return _m2 / float(_n - 1)

func chi_square_uniform() -> float:
	# goodness-of-fit vs uniform across bins
	if _n == 0:
		return 0.0
	var expected: float = float(_n) / float(bins)
	var chi2: float = 0.0
	var i: int = 0
	while i < bins:
		var o: float = float(_counts[i])
		var diff: float = o - expected
		# guard expected to avoid div-by-zero for tiny samples
		chi2 += (diff * diff) / max(1.0, expected)
		i += 1
	return chi2  # df = bins - 1

func report() -> void:
	var var_uniform: float = 1.0 / 12.0  # ≈ 0.08333
	print("--- RollStats ---")
	print("n=", _n, "  mean=", _mean, "  var=", variance(),
		"  target_var≈", var_uniform, "  min=", _min_v, "  max=", _max_v)
	var chi2: float = chi_square_uniform()
	print("chi2=", chi2, "  df=", bins - 1, "  (bigger sample => more meaningful)")
	# small text hist (0..9 bars max)
	var i: int = 0
	var expected: float = float(_n) / float(bins)
	while i < bins:
		var o: float = float(_counts[i])

		# was: var ratio: float = (expected > 0.0) ? (o / expected) : 0.0
		var ratio: float = 0.0
		if expected > 0.0:
			ratio = o / expected
		
		var bars: int = clamp(int(round(ratio * 5.0)), 0, 9)
		var bars_f: float = round(ratio * 5.0)
		var bars_i: int = int(bars_f)
		if bars_i < 0:
			bars_i = 0
		elif bars_i > 9:
			bars_i = 9
		print(str(i).pad_zeros(2), ": ", "|".repeat(bars), "  (", _counts[i], ")")
		i += 1
