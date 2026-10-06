extends RefCounted
class_name SquadFireMath

# Synchronous SquadFireMath operations; state and scene identity stay on the caller.


static func compute_support_efficiency(support_crew_available: int, support_crew_optimal: int) -> float:
	var ratio: float = 1.0
	if support_crew_optimal > 0:
		ratio = float(support_crew_available) / float(support_crew_optimal)
	
	# clamp ratio to [0, 1]
	if ratio < 0.0:
		ratio = 0.0
	else:
		if ratio > 1.0:
			ratio = 1.0
	
	# 0 helpers -> 0.5, full helpers -> 1.0
	var multiplier: float = 0.5 + 0.5 * ratio
	return multiplier

# Util: returns a single normally-distributed sample (mean 0, stddev 1)


static func get_mean_change_to_hit(chance_to_hit_per_target: Array, n_targets: int) -> float:
	var mean_p_hit: float = 0.0
	var iii: int = 0
	while iii < n_targets:
		mean_p_hit += float(chance_to_hit_per_target[iii])
		iii += 1
	if n_targets > 0:
		mean_p_hit /= float(n_targets)
	else:
		mean_p_hit = 0.0
	return mean_p_hit


static func cover_multiplier_exp(cover_pts: float) -> float:
	match cover_pts:
		0.0:
			return 1.5
		1.0:
			return 0.5
		2.0:
			return 0.4
		3.0:
			return 0.3
		4.0:
			return 0.1
		5.0:
			return 0.05
		_:
			return 0.001
	## Multiplier goes 1.0 → MIN_HIT_MULT with diminishing returns as cover_pts rises
	#var k: float = log(2.0) / HALF_POINT
	#return MIN_HIT_MULT + (1.0 - MIN_HIT_MULT) * exp(-k * max(cover_pts, 0.0))
