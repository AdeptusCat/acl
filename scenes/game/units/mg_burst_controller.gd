# mg_burst_controller.gd
class_name MGBurstController
extends Node

signal shoot(from_pos: Vector2, to_pos: Vector2)  # hook your VFX/SFX here

# Plan bursts like a proper fire order: e.g. total 7 with burst_size 4 -> [4,3].
func plan_bursts(total_rounds: int, burst_size: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if total_rounds <= 0:
		return result
	
	var rounds_left: int = total_rounds
	var this_size: int
	while rounds_left > 0:
		if rounds_left >= burst_size:
			this_size = burst_size
		else:
			this_size = rounds_left
		result.append(this_size)
		rounds_left -= this_size
	return result


# Animation runner. You can call this after you’ve computed total MG rounds for the volley.
# Two modes:
#   - resolve_mode == "instant": resolve mechanics up-front; this only animates
#   - resolve_mode == "per_burst": call your resolve per burst count
# If you fancy per-shot, call your resolve logic in the inner loop where the 'shoot' signal fires.
func animate_mg_bursts(
		shooter: Node2D,
		target: Node2D,
		total_rounds: int,
		rpm: float,
		burst_size: int,
		burst_pause_s: float,
		resolve_mode: String,
		unit_visible_enemies: Dictionary
	) -> void:
	
	if total_rounds <= 0:
		return
	
	# timing
	var bullets_per_sec: float = rpm / 60.0
	if bullets_per_sec <= 0.0:
		bullets_per_sec = 1.0   # safety
	var seconds_per_bullet: float = 1.0 / bullets_per_sec
	
	# plan the bursts
	var bursts: PackedInt32Array = plan_bursts(total_rounds, burst_size)
	
	# If resolving instantly, do it before we faff about with timers
	#if resolve_mode == "instant":
		#_resolve_mg_effects(shooter, target, total_rounds)  # your existing resolve function
	
	var hex_pos: Vector2 = Vector2.ZERO
	var from_pos: Vector2 = Vector2.ZERO
	var to_pos: Vector2 = Vector2.ZERO
	
	# Pre-calc positions; if you need per-shot sway, recompute inside the loop
	# Replace with your ground-layer mapping if needed.
	if "current_hex" in shooter:
		hex_pos = shooter.current_hex
		from_pos = LOSHelper.ground_layer.map_to_local(hex_pos)
	else:
		from_pos = shooter.global_position
	
	to_pos = target.global_position
	
	# Work through each burst
	for i in range(0, bursts.size()):
		# Bail early if anything’s gone pear-shaped
		if not is_instance_valid(shooter):
			return
		if not is_instance_valid(target):
			return
		if shooter.broken or shooter.moving or shooter.surrendered:
			return
		
		var interval = bullets_per_sec / burst_size
		# Visibility sanity (cheap check once per burst)
		#var visible_enemies: Array = unit_visible_enemies.get(shooter.get_parent(), [])
		#if not visible_enemies.has(target):
			#return
		
		var shots_this_burst: int = bursts[i]
		
		# If resolving per-burst, do the mechanics now for this chunk
		#if resolve_mode == "per_burst":
			#_resolve_mg_effects(shooter, target, shots_this_burst)
		
		# Animate each shot in the burst
		for s in range(0, shots_this_burst):
			if not is_instance_valid(shooter) or not is_instance_valid(target):
				return
			if shooter.broken or shooter.moving or shooter.surrendered:
				return
			shoot.emit(shooter.global_position, target.global_position)
			# tracer/muzzle flash VFX play on this signal; sound likewise
			await get_tree().create_timer(interval).timeout
		
		# Pause between bursts unless this was the last one
		if i < bursts.size() - 1:
			await get_tree().create_timer(burst_pause_s).timeout
