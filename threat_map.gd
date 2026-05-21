extends Node

var thread: Thread
var result_ready := false
var current_threat_maps: Dictionary[int, Dictionary] = {
	Globals.Team.AXIS: {},
	Globals.Team.ALLIES: {},
}

var update_interval := 0.25  # seconds
var update_timer := 0.0

var pending_visible_hexes: Dictionary[int, Array]
var pending_lookup: Dictionary = {}

var threat_weights = {}

signal draw_threat(current_threat_maps: Dictionary[int, Dictionary])


func update_astart_for_team(team: Globals.Team):
	if not Globals.astars.has(team):
		return
	
	for point_id in Globals.astars[team].get_point_ids():
		var world_pos = Globals.astars[team].get_point_position(point_id)
		var hex_map = LOSHelper.ground_layer.local_to_map(world_pos)
		var weight = current_threat_maps[team].get(hex_map, 1.0)
		Globals.astars[team].set_point_weight_scale(point_id, weight)
		


func _exit_tree():
	if thread:
		thread.wait_to_finish()


func thread_done():
	if thread:
		thread.wait_to_finish()
		thread = null


func _process(delta: float) -> void:
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		
		#if Debug.draw_thread_map:
		await _start_threat_map_update()
		
		#var enemy_team = Globals.Team.AXIS if Globals.team_player == Globals.Team.ALLIES else Globals.Team.ALLIES
		#var observers: Array = LOSHelper.visible_hexes.get(enemy_team, [])
		#request_threat_update(observers, LOSHelper.los_lookup)

func _set_threat_map_result(result: Dictionary[int, Dictionary]):
	#current_threat_map = result
	current_threat_maps = result
	draw_threat.emit(current_threat_maps)
	# get_parent().draw_threat(current_threat_maps)
	result_ready = true

var updating_threat := false
func _start_threat_map_update():
	if updating_threat:
		return
	updating_threat = true
	#pending_visible_hexes = LOSHelper.visible_hexes.duplicate(true)
	#pending_lookup = LOSHelper.los_lookup.duplicate(true)
	
	pending_visible_hexes = await _deferred_copy_dict_visible_hexes(LOSHelper.visible_hexes)
	#pending_lookup = await _deferred_copy_dict(LOSHelper.los_lookup)
	pending_lookup = LOSHelper.los_lookup
	await _incremental_threat_map_update()
	updating_threat = false


func _incremental_threat_map_update() -> void:
	# TODO this is only here because the checks start even if the game hasnt started yet
	if not Globals.astars.has(0):
		return
	var temp_threat_maps: Dictionary[int, Dictionary]
	temp_threat_maps[Globals.Team.AXIS] = {}
	temp_threat_maps[Globals.Team.ALLIES] = {}

	for team in Globals.Team.values():
		var points := Globals.astars[team].get_point_ids()
		var index := 0
		while index < points.size():
			var batch_size := 30  # Lower this if still lagging
			for j in range(batch_size):
				if index >= points.size():
					break
				var point_id := points[index]
				var world_pos = Globals.astars[team].get_point_position(point_id)
				# FIXME this thows error if ground_layer is freed on exit
				if not is_instance_valid(LOSHelper.ground_layer):
					break
				var hex_map = LOSHelper.ground_layer.local_to_map(world_pos)
				var weight := _calculate_threat_weight(hex_map, pending_lookup, pending_visible_hexes, team)
				temp_threat_maps[team][hex_map] = weight
				index += 1
			if not is_instance_valid(LOSHelper.ground_layer):
				break
			#await get_tree().create_timer(0.00).timeout  # Yield between small batches
			await get_tree().process_frame
	call_deferred("_set_threat_map_result", temp_threat_maps)


func _deferred_copy_dict_visible_hexes(source: Dictionary[int, Array]) -> Dictionary[int, Array]:
	var copy:Dictionary[int, Array] = {}
	for k in source.keys():
		var v = source[k]
		if typeof(v) == TYPE_DICTIONARY:
			copy[k] = v.duplicate(true)
		elif typeof(v) == TYPE_ARRAY:
			copy[k] = v.duplicate(true)
		else:
			copy[k] = v
		#await get_tree().create_timer(0.0).timeout
		await get_tree().process_frame
	return copy

func _deferred_copy_dict(source: Dictionary) -> Dictionary:
	var copy := {}
	for k in source.keys():
		var v = source[k]
		if typeof(v) == TYPE_DICTIONARY:
			copy[k] = v.duplicate(true)
		elif typeof(v) == TYPE_ARRAY:
			copy[k] = v.duplicate(true)
		else:
			copy[k] = v
		await get_tree().create_timer(0.0).timeout
	return copy


func _calculate_threat_weight(hex: Vector2i, _pending_los_lookup: Dictionary, _pending_visible_hexes: Dictionary[int, Array], team: int) -> float:
	var weight = 1.0  # Start with neutral weight scale

	var enemy_team: int = Globals.Team.ALLIES
	if team == Globals.Team.ALLIES:
		enemy_team = Globals.Team.AXIS
	else:
		enemy_team = Globals.Team.ALLIES
	
	var observed_hexes_by_enemy = _pending_visible_hexes.get(enemy_team, [])
	
	if observed_hexes_by_enemy.has(hex):
		for unit in Globals.get_units():
			if not is_instance_valid(unit):
				continue
			if not unit.alive:
				continue
			if not unit.team == enemy_team:
				continue
			var o_hex = unit.current_hex
			if _pending_los_lookup.has(o_hex) and _pending_los_lookup[o_hex].has(hex):
				var cover = _pending_los_lookup[o_hex][hex].target_cover
				weight += max((6.0 - float(cover)), 1.0) * 0.3  # Adjust scaling if needed
	##for o_hex in observed_hexes_by_enemy:
	#for o_hex in units:
		#var observed_hex = 
		#if pending_los_lookup.has(o_hex) and pending_los_lookup[o_hex].has(hex):
			#var cover = pending_los_lookup[o_hex][hex].target_cover
			##cover = clamp(cover, 0, 5)
			#weight += max((6.0 - float(cover)), 1.0) * 0.1  # Adjust scaling if needed

	return weight
