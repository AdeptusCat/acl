extends RefCounted
class_name MatchVisibilityCoordinator

const INDIRECT_CONTACT_TINT: Color = Color(0.45, 0.45, 0.45, 0.6)

# Synchronous MatchVisibilityCoordinator operations; state and scene identity stay on the caller.


static func draw_fog(controller: Node2D) -> void:
	controller.fog_of_war_layer.update_visibility(LOSHelper.visible_hexes[Globals.team_player])


static func show_visible_units(controller: Node2D) -> void:
	var observer: Unit = controller.selected_unit
	var inspect_sight: bool = is_instance_valid(observer) and observer.team == Globals.team_player and observer.is_active() and not observer.surrendered
	var inspect_enemy: bool = is_instance_valid(observer) and observer.team != Globals.team_player and observer.is_active() and not observer.surrendered
	var directly_seen: Array = []
	if inspect_sight:
		directly_seen = Globals.unit_visible_enemies.get(observer, [])
	var units: Array[Unit] = Globals.get_units()
	var units_seen: Array = []
	for unit: Unit in units:
		if unit.team != Globals.team_player or unit.surrendered:
			continue
		for enemy: Unit in Globals.unit_visible_enemies.get(unit, []):
			if not units_seen.has(enemy):
				units_seen.append(enemy)
	# Team-wide spotting still controls what can be revealed. Selection only
	# distinguishes this squad's own sightings from contacts supplied by others.
	for unit: Unit in units:
		if unit.team != Globals.team_player:
			unit.visible = Debug.show_enemies or units_seen.has(unit)
		elif Debug.show_enemies:
			unit.show()
		var dimmed: bool = inspect_sight and unit.team != Globals.team_player and not directly_seen.has(unit)
		if inspect_enemy and unit.team == Globals.team_player:
			dimmed = not unit.is_active() or unit.surrendered or not Globals.unit_visible_enemies.get(unit, []).has(observer)
		unit.modulate = Color.WHITE
		if dimmed:
			unit.modulate = INDIRECT_CONTACT_TINT
		unit.ui.set_indirect_contact(dimmed)
	if inspect_enemy and not observer.is_visible_in_tree():
		controller._deselect_unit(observer)
		controller.hide_unit_details_in_ui.emit()


static func update_visible_hexes(controller: Node2D) -> void:
	for array: Array in LOSHelper.visible_hexes.values():
		array.clear()
	for u: Unit in Globals.get_units():
		if not is_instance_valid(u):
			continue
		if u.surrendered:
			continue
		var unit_visible: Dictionary = LOSHelper.los_lookup.get(u.current_hex, {})
		for hex: Vector2i in unit_visible:
			if not LOSHelper.visible_hexes[u.team].has(hex):
				LOSHelper.visible_hexes[u.team].append(hex)
		if not LOSHelper.visible_hexes[u.team].has(u.current_hex):
			LOSHelper.visible_hexes[u.team].append(u.current_hex)


static func update_los_time(controller: Node2D, delta: float) -> void:
	var now_unix: float = Time.get_unix_time_from_system()

	for unit_variant: Unit in Globals.get_units():
		var unit: Unit = unit_variant as Unit
		if unit == null:
			continue

		var track_map: Dictionary[Unit, EnemyTrack] = Globals.unit_enemy_tracks.get(
			unit,
			{} as Dictionary[Unit, EnemyTrack]
		)

		var enemies_in_los: Array = Globals.unit_enemies_in_los.get(unit, [])
		var seen_this_tick: Dictionary[Unit, bool] = {}

		for enemy_variant: Variant in enemies_in_los:
			var enemy: Unit = enemy_variant as Unit
			if enemy == null:
				continue

			seen_this_tick[enemy] = true

			var track: EnemyTrack = track_map.get(enemy, null)
			if track == null:
				track = EnemyTrack.new(unit, enemy)
				track_map[enemy] = track

			track.update_seen(delta, now_unix)

		var tracked_enemies: Array[Unit] = track_map.keys()

		for tracked_enemy: Unit in tracked_enemies:
			if seen_this_tick.has(tracked_enemy):
				continue

			var existing_track: EnemyTrack = track_map.get(tracked_enemy, null)
			if existing_track == null:
				track_map.erase(tracked_enemy)
				continue

			existing_track.update_not_seen(delta)

			if existing_track.should_delete():
				track_map.erase(tracked_enemy)

		Globals.unit_enemy_tracks[unit] = track_map


static func on_unit_visibility_checker_timer_timeout(controller: Node2D) -> void:
	var next_visible: Dictionary = {}

	for unit_variant: Unit in Globals.get_units():
		var unit: Unit = unit_variant as Unit
		if unit == null:
			continue

		if not is_instance_valid(unit):
			continue

		# Refresh once per observer so every candidate uses the same current attention.
		unit.tactical_state.update_attention(unit)
		var units_visible: Array[Unit] = []
		var units_visible_by_this_unit: Array = Globals.unit_visible_enemies.get(unit, [])
		var units_in_los: Array = Globals.unit_enemies_in_los.get(unit, [])

		var track_map: Dictionary[Unit, EnemyTrack] = Globals.unit_enemy_tracks.get(
			unit,
			{} as Dictionary[Unit, EnemyTrack]
		)

		for enemy_variant: Variant in track_map.keys():
			var enemy_tracked: Unit = enemy_variant as Unit
			if enemy_tracked == null:
				continue

			if not is_instance_valid(enemy_tracked):
				continue

			var track: EnemyTrack = track_map.get(enemy_tracked, null)
			if track == null:
				continue

			if units_visible_by_this_unit.has(enemy_tracked) and units_in_los.has(enemy_tracked):
				track.record_detection()
				units_visible.append(enemy_tracked)
				continue

			if not units_in_los.has(enemy_tracked):
				track.is_visible = false
				continue

			var p_tick: float = controller._compute_detect_prob_per_tick(unit, enemy_tracked, 1.0)
			var r: float = randf()

			if r < p_tick:
				track.confidence += 0.35
			else:
				track.confidence -= 0.10

			track.confidence = clamp(track.confidence, 0.0, 1.0)

			if track.confidence >= EnemyTrack.VISIBLE_CONF_THRESHOLD:
				track.record_detection()
				
				units_visible.append(enemy_tracked)
			else:
				track.is_visible = false

		var units_at_current_hex: Array = LOSHelper.find_units_at(unit.current_hex)

		for unit_in_current_hex_variant: Variant in units_at_current_hex:
			var unit_in_current_hex: Unit = unit_in_current_hex_variant as Unit
			if unit_in_current_hex == null:
				continue

			if unit_in_current_hex.team == unit.team:
				continue

			if not units_visible.has(unit_in_current_hex):
				units_visible.append(unit_in_current_hex)

			var same_hex_track: EnemyTrack = track_map.get(unit_in_current_hex, null)
			if same_hex_track == null:
				same_hex_track = EnemyTrack.new(unit, unit_in_current_hex)
				track_map[unit_in_current_hex] = same_hex_track

			same_hex_track.confidence = 1.0
			same_hex_track.record_detection()
			same_hex_track.has_confirmed_lock = true
			same_hex_track.currently_in_los = true

		Globals.unit_enemy_tracks[unit] = track_map
		next_visible[unit] = units_visible

	Globals.unit_visible_enemies = next_visible
	# New contacts pull attention immediately, after every observer finishes its detection roll.
	for unit: Unit in Globals.get_units():
		unit.tactical_state.update_attention(unit)
	controller.show_visible_units()


static func compute_detect_prob_per_tick(controller: Node2D, observer: Unit, enemy: Unit, delta: float) -> float:
	if not observer.is_active() or observer.surrendered or observer.members_alive <= 0:
		return 0.0
	var dist: int = LOSHelper.ground_layer.cube_distance(observer.current_cube, enemy.current_cube)
	if dist < 1:
		dist = 1

	var is_moving: bool = enemy.is_moving

	var conceal: int = controller._get_concealment(observer.current_hex, enemy) # 0..N, higher = harder to see
	#if conceal > 0:
		#conceal = 1

	# score components (tune)
	var score: float = 0.0

	# movement: huge
	if is_moving:
		score += 3.0
	else:
		score += 0.5

	# distance penalty (log-ish)
	score -= 0.25 * float(dist)

	# concealment penalty
	if conceal > 0:
		score -= 0.8 * float(conceal)
	if conceal == 0:
		score += 1
	
	# shooting stimulus (0..1) -> add to score
	var fire_recent: float = enemy.squad_fire.fire_recent
	var fire_recent_mod: float = 10.0 * fire_recent
	score += fire_recent_mod
	# convert score -> hazard rate (lambda >= 0)
	# baseline ensures “sometimes” even if score small
	var lambda: float = 0.00 + 0.15 * max(score, 0.0)
	if observer.tactical_state != null:
		var direction: Vector2 = observer.global_position.direction_to(enemy.global_position)
		lambda *= observer.tactical_state.detection_multiplier(direction)
	var p: float = 1.0 - exp(-lambda * delta)

	return clamp(p, 0.0, 0.95)


static func get_concealment(controller: Node2D, current_hex: Variant, enemy: Node) -> int:
	var cover_map: Variant = LOSHelper.los_lookup.get(current_hex, null)
	if cover_map == null:
		return 0
	if not cover_map.has(enemy.current_hex):
		return 0
	var data: Variant = cover_map[enemy.current_hex]
	if data is Dictionary:
		if data.has("target_conceal"):
			return int(data["target_conceal"])
		if data.has("target_cover"):
			# fallback if you have nothing else
			return int(data["target_cover"])
	return 0


static func on_unit_shooting(controller: Node2D, shooter: Unit) -> void:
	for observer_variant: Unit in Globals.get_units():
		var observer: Unit = observer_variant as Unit
		if observer == null:
			continue

		if not is_instance_valid(observer):
			continue

		var track_map: Dictionary[Unit, EnemyTrack] = Globals.unit_enemy_tracks.get(
			observer,
			{} as Dictionary[Unit, EnemyTrack]
		)

		if not track_map.has(shooter):
			continue

		var track: EnemyTrack = track_map.get(shooter, null)
		if track == null:
			continue

		track.confidence += 0.1
		track.confidence = clamp(track.confidence, 0.0, 1.0)

		if track.confidence >= EnemyTrack.VISIBLE_CONF_THRESHOLD and Globals.unit_enemies_in_los.get(observer, []).has(shooter):
			track.record_detection()

		Globals.unit_enemy_tracks[observer] = track_map


#func _on_unit_shooting(unit: Unit) -> void:
	#for observer_variant in Globals.get_units():
		#var observer: Unit = observer_variant as Unit
		#if observer == null:
			#continue
#
		#if not is_instance_valid(observer):
			#continue
#
		#var track_map: Dictionary[Unit, EnemyTrack] = Globals.unit_enemy_tracks.get(
			#observer,
			#{} as Dictionary[Unit, EnemyTrack]
		#)
#
		#if not track_map.has(unit):
			#continue
#
		#var track: EnemyTrack = track_map.get(unit, null)
		#if track == null:
			#continue
#
		#track.confidence += 0.1
		#track.confidence = clamp(track.confidence, 0.0, 1.0)
#
		#if track.confidence >= EnemyTrack.VISIBLE_CONF_THRESHOLD:
			#track.is_visible = true
#
		#Globals.unit_enemy_tracks[observer] = track_map
