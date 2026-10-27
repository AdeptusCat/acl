extends RefCounted
class_name MatchVisibilityCoordinator

# Rates are per simulation second; distances use the gameplay scale, not sprite pixels.
const METRES_PER_HEX: float = 40.0
const DETECTION_REFERENCE_DISTANCE_METRES: float = 240.0
const DETECTION_DISTANCE_EXPONENT: float = 3.0
const STATIONARY_DETECTION_RATE: float = 1.0
const MOVING_DETECTION_RATE: float = 3.0
const FIRING_DETECTION_RATE: float = 18.0
const TARGET_CONCEALMENT_TRANSMISSION: float = 0.35
const INTERVENING_HEX_TRANSMISSION: float = 0.55
const FIRING_CONCEALMENT_TRANSMISSION: float = 0.7
const FIRING_INTERVENING_HEX_TRANSMISSION: float = 0.7
const MAX_IDENTIFICATION_EVIDENCE_RATE: float = 2.0

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
		if unit.team != Globals.team_player:
			unit.ui.set_contact_report(contact_report(Globals.team_player, unit), not Debug.enemy_selectable)
		else:
			unit.ui.set_contact_report({}, false)
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


static func on_unit_visibility_checker_timer_timeout(controller: Node2D, elapsed_seconds: float) -> void:
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

			if not unit.is_active() or unit.surrendered or unit.members_alive <= 0:
				track.is_visible = false
				continue
			# Same-hex contacts are handled below, including when the LOS table
			# deliberately omits its own origin. Observe them exactly once.
			if enemy_tracked.current_hex == unit.current_hex:
				continue

			if track.is_visible and units_visible_by_this_unit.has(enemy_tracked) and units_in_los.has(enemy_tracked):
				var factors: Dictionary = detection_breakdown(controller, unit, enemy_tracked)
				var rate: float = factors["rate"]
				if track.maintain_detection(rate, elapsed_seconds):
					track.record_detection()
					track.observe_details(factors["identification_rate"], elapsed_seconds)
					units_visible.append(enemy_tracked)
				continue

			if not units_in_los.has(enemy_tracked):
				track.is_visible = false
				continue

			var p_tick: float = controller._compute_detect_prob_per_tick(unit, enemy_tracked, elapsed_seconds)
			# Acquisition is one time-scaled event. Failed rolls do not erase evidence.
			if randf() < p_tick:
				track.reaction_focus_direction = unit.tactical_state.focus_direction
				track.acquired_at_s = unit._now()
				track.confidence = maxf(track.confidence, EnemyTrack.VISIBLE_CONF_THRESHOLD)
				track.acquire_detection()
				units_visible.append(enemy_tracked)
			else:
				track.is_visible = false

		var units_at_current_hex: Array = []
		if unit.is_active() and not unit.surrendered and unit.members_alive > 0:
			units_at_current_hex = LOSHelper.find_units_at(unit.current_hex)

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
			if same_hex_track.is_visible and units_visible_by_this_unit.has(unit_in_current_hex):
				same_hex_track.observe_details(MAX_IDENTIFICATION_EVIDENCE_RATE, elapsed_seconds)

			same_hex_track.confidence = 1.0
			same_hex_track.acquire_detection()
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
	if delta <= 0.0:
		return 0.0
	var rate: float = compute_detect_rate(controller, observer, enemy)
	return clampf(1.0 - exp(-rate * delta), 0.0, 1.0)


static func compute_detect_rate(controller: Node2D, observer: Unit, enemy: Unit) -> float:
	return float(detection_breakdown(controller, observer, enemy).get("rate", 0.0))


static func detection_breakdown(controller: Node2D, observer: Unit, enemy: Unit) -> Dictionary:
	if not observer.is_active() or observer.surrendered or observer.members_alive <= 0:
		return {"rate": 0.0, "eligible": false}
	var distance_hexes: int = LOSHelper.ground_layer.cube_distance(observer.current_cube, enemy.current_cube)
	var distance_metres: float = float(distance_hexes) * METRES_PER_HEX
	var distance_factor: float = 1.0 / (1.0 + pow(distance_metres / DETECTION_REFERENCE_DISTANCE_METRES, DETECTION_DISTANCE_EXPONENT))
	var concealment: int = controller._get_concealment(observer.current_hex, enemy)
	var sight_line: Dictionary = LOSHelper.los_lookup.get(observer.current_hex, {}).get(enemy.current_hex, {})
	var intervening_hexes: int = maxi(int(sight_line.get("hindrance", 0)), 0)
	var terrain_factor: float = pow(TARGET_CONCEALMENT_TRANSMISSION, maxi(concealment, 0))
	terrain_factor *= pow(INTERVENING_HEX_TRANSMISSION, intervening_hexes)
	# A quiet stationary silhouette loses contrast much faster than movement or
	# muzzle flashes. Its passive cue receives a second smooth distance factor.
	var activity_rate: float = STATIONARY_DETECTION_RATE * distance_factor
	var moving: bool = enemy.is_moving
	var motion: float = 1.0
	var exposure: float = target_exposure(enemy)
	if is_instance_valid(enemy.movement):
		moving = moving or enemy.movement.is_moving
		motion = clampf(enemy.movement.visibility_speed_ratio(), 0.1, 2.0)
	if moving:
		activity_rate = MOVING_DETECTION_RATE * motion
	activity_rate *= exposure
	var firing: float = 0.0
	if enemy.squad_fire != null:
		firing = clampf(enemy.squad_fire.fire_recent, 0.0, 1.0)
	# Even one round gives a noticeable flash. Vegetation and target concealment
	# obscure that cue less than a quiet silhouette; blocking LOS still applies.
	var firing_terrain: float = pow(FIRING_CONCEALMENT_TRANSMISSION, maxi(concealment, 0))
	firing_terrain *= pow(FIRING_INTERVENING_HEX_TRANSMISSION, intervening_hexes)
	var firing_rate: float = FIRING_DETECTION_RATE * sqrt(firing) * distance_factor * firing_terrain
	var rate: float = activity_rate * distance_factor * terrain_factor + firing_rate
	var attention: float = 1.0
	if observer.tactical_state != null:
		var direction: Vector2 = observer.global_position.direction_to(enemy.global_position)
		attention = observer.tactical_state.detection_multiplier(direction)
		rate *= attention
	var condition: float = 1.0
	# Movement and suppression affect spotting, without changing the squad's stress capacity.
	if observer.is_moving:
		condition *= 0.65
	if observer.stress_system != null:
		if observer.stress_system.under_fire:
			condition *= 0.85
		if observer.stress_system.state == STATES.MoraleState.PINNED:
			condition *= 0.6
	var search: float = 1.0
	var track: EnemyTrack = Globals.unit_enemy_tracks.get(observer, {}).get(enemy, null) as EnemyTrack
	if track != null:
		search = track.reacquisition_multiplier(enemy.current_hex)
	var tracking_remaining: float = 0.0
	var identification: float = 0.0
	if track != null:
		tracking_remaining = track.visual_contact_remaining_s
		identification = track.identification_evidence
	rate *= condition * search
	firing_rate *= attention * condition * search
	# Recognizing an acquired silhouette depends on the view, rather than on
	# movement, muzzle flashes or a remembered-location acquisition bonus.
	var detail_quality: float = maxf(distance_factor * terrain_factor * exposure * attention * condition, 0.0)
	var identification_rate: float = MAX_IDENTIFICATION_EVIDENCE_RATE * minf(sqrt(detail_quality), 1.0)
	var has_los: bool = observer.current_hex == enemy.current_hex or LOSHelper.los_lookup.get(observer.current_hex, {}).has(enemy.current_hex)
	if not has_los:
		identification_rate = 0.0
		firing_rate = 0.0
	return {"rate": maxf(rate, 0.0), "eligible": true, "distance_hexes": distance_hexes,
		"distance_metres": distance_metres, "distance_factor": distance_factor, "concealment": concealment,
		"hindrances": intervening_hexes, "terrain_factor": terrain_factor, "moving": moving,
		"motion_factor": motion, "exposure": exposure, "firing": firing, "activity_rate": activity_rate,
		"firing_rate": firing_rate,
		"attention": attention, "observer_condition": condition, "search_bonus": search,
		"has_los": has_los,
		"tracking_remaining_s": tracking_remaining, "identification_evidence": identification,
		"identification_rate": identification_rate}


static func target_exposure(enemy: Unit) -> float:
	var posture: float = 1.0
	if is_instance_valid(enemy.movement):
		match enemy.movement.stance:
			UnitMovement.Stance.CROUCHED:
				posture = 0.7
			UnitMovement.Stance.PRONE:
				posture = 0.4
			UnitMovement.Stance.RUNNING:
				posture = 1.1
	var exposed: float = 0.0
	var alive: int = 0
	if enemy.squad_fire != null:
		for soldier: Soldier in enemy.squad_fire.soldiers:
			if not soldier.is_alive:
				continue
			alive += 1
			match soldier.behavior:
				Soldier.Behavior.ENGAGING:
					exposed += 1.0
				Soldier.Behavior.TAKING_COVER:
					exposed += 0.45
				Soldier.Behavior.COWERING:
					exposed += 0.25
				Soldier.Behavior.RECOVERING:
					exposed += 0.6
	if alive > 0:
		posture *= exposed / float(alive)
	return posture


static func contact_report(team: Globals.Team, enemy: Unit) -> Dictionary:
	var best: EnemyTrack
	for observer: Unit in Globals.get_units_for_team(team):
		var track: EnemyTrack = Globals.unit_enemy_tracks.get(observer, {}).get(enemy, null) as EnemyTrack
		if track == null or track.awareness <= 0.0:
			continue
		if best == null or track.identification_evidence > best.identification_evidence:
			best = track
		elif track.identification_evidence == best.identification_evidence:
			if (track.is_visible and not best.is_visible) or (track.is_visible == best.is_visible and track.last_detail_observation_s > best.last_detail_observation_s):
				best = track
	if best != null:
		return best.contact_report()
	return {"title": "Unidentified contact", "status": "Brief sighting", "strength": "Strength unknown",
		"squad_type": -1, "strength_min": 0, "strength_max": 0, "evidence": 0.0}


static func controller_for_unit(unit: Unit) -> Node2D:
	var ancestor: Node = unit.get_parent()
	while is_instance_valid(ancestor):
		if ancestor is Node2D and ancestor.has_method("_get_concealment"):
			return ancestor as Node2D
		ancestor = ancestor.get_parent()
	return null


static func get_concealment(_controller: Node2D, current_hex: Variant, enemy: Node) -> int:
	var sight_line: Dictionary = LOSHelper.los_lookup.get(current_hex, {}).get(enemy.current_hex, {})
	if sight_line.has("target_concealment"):
		return maxi(int(sight_line["target_concealment"]), 0)
	# Legacy LOS rows may lack concealment. Query terrain; bullet cover is not concealment.
	if is_instance_valid(LOSHelper.terrain_layer) and is_instance_valid(LOSHelper.building_layer):
		var target_position: Vector2 = LOSHelper.ground_layer.map_to_local(enemy.current_hex)
		return LOSHelper.get_target_concealment(target_position)
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

		# Firing raises fire_recent, which feeds normal acquisition with all observer modifiers.
		# Only an already acquired contact may refresh its position here.
		if track.is_visible and observer.is_active() and not observer.surrendered and Globals.unit_enemies_in_los.get(observer, []).has(shooter):
			track.confidence = clampf(track.confidence + 0.1, 0.0, 1.0)
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
