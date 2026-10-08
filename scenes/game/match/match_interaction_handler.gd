extends RefCounted
class_name MatchInteractionHandler

# Synchronous MatchInteractionHandler operations; state and scene identity stay on the caller.


static func order_via_option_wheel(controller: Node2D, map_hex: Vector2i, option: WheelOption.Option) -> void:
	if not controller.selected_unit:
		return
	
	if controller.selected_unit.in_close_combat:
		return
	
	match option:
		WheelOption.Option.NONE:
			pass
		WheelOption.Option.MOVE_NORMAL:
			if controller.selected_unit.broken or controller.selected_unit.surrendered:
				controller.selected_unit.ui.show_broken()
				return
			if controller.selected_unit.stress_system.state == STATES.MoraleState.PINNED:
				controller.selected_unit.ui.show_pinned()
				return
			controller.selected_unit.order(Globals.UnitCmd.MOVE, map_hex)
		WheelOption.Option.FIRE_AT:
			var can_shoot: bool = false
			if not controller.selected_unit.squad_type == Globals.SquadType.MORTAR:
				var unit_visible_hexes: Dictionary = LOSHelper.los_lookup.get(controller.selected_unit.current_hex, [])
				if unit_visible_hexes.has(map_hex):
					can_shoot = true
			else:
				can_shoot = true
			if can_shoot:
				controller.selected_unit.setAttackState(Unit.AttackState.MANUAL_GROUND)
				controller.selected_unit.order(Globals.UnitCmd.FIRE_AT_HEX, map_hex)
		WheelOption.Option.ASSAULT:
			pass
		WheelOption.Option.STOP:
			controller.selected_unit.order(Globals.UnitCmd.STOP, map_hex)
	
	var local_pos: Vector2 = controller.ground_layer.map_to_local(map_hex)
	controller.hex_glow(local_pos)

#func _on_mouse_button_right_pressed(event_pos: Vector2):
	#event_pos = get_local_mouse_position()
	#var map_hex = ground_layer.local_to_map(event_pos)
	#
	#if selected_unit:
		#if selected_unit.broken:
			#selected_unit.ui.show_failure()
			#return
		#var local_pos: Vector2
		#if selected_unit.squad_type == Globals.SquadType.MORTAR:
			#selected_unit.order(Globals.UnitCmd.ATTACK_GROUND, map_hex)
		#else:
			#var units: Array[Node2D] = _find_units_at(map_hex)
			#for unit in units:
				#if not unit.team == Globals.team_player or Debug.enemy_selectable:
					#var _path: Array[Vector3i] = []
					#selected_unit.order(Globals.UnitCmd.ATTACK_UNIT, unit)
					#local_pos = ground_layer.map_to_local(map_hex)
					#hex_glow(local_pos)
					#return
			#selected_unit.order(Globals.UnitCmd.MOVE, map_hex)
		#local_pos = ground_layer.map_to_local(map_hex)
		#hex_glow(local_pos)


static func on_mouse_button_left_pressed(controller: Node2D, event_pos: Vector2) -> void:
	event_pos = controller.get_local_mouse_position()
	var map_hex: Vector2i = controller.ground_layer.local_to_map(event_pos)
	controller.hex_selected.emit(map_hex, event_pos)
	if controller.previous_selected_hex == map_hex:
		controller.selected_hex_index += 1
	else:
		controller.previous_selected_hex = map_hex
		controller.selected_hex_index = 0
	var units: Array[Unit] = LOSHelper.find_units_at(map_hex)
	if units.is_empty():
		if not controller.selected_unit == null:
			controller._deselect_unit(controller.selected_unit)
			controller.hide_unit_details_in_ui.emit()
		return
	if controller.selected_hex_index >= units.size():
		controller.selected_hex_index = 0
	var unit: Unit = units[controller.selected_hex_index]
	if unit: # and not unit.broken  and not unit.surrendered
		if not unit.team == Globals.team_player and not Debug.enemy_selectable:
			return
		if unit == controller.selected_unit:
			controller._deselect_unit(unit)
			controller.hide_unit_details_in_ui.emit()
		else:
			controller._select_unit(unit)
			controller.show_unit_details_in_ui.emit(unit)
			LOSHelper.clear_los()


# Nullable tile coordinates: Vector2i when present, null when cleared.


static func handle_mouse_event_position_changed(controller: Node2D, event_pos: Vector2) -> void:
	controller.mouse_event_position_changed.emit(event_pos)
	if controller.selected_unit:
		var unit_pos: Vector2 = controller.selected_unit.position
		var local_event_pos: Vector2 = controller.get_local_mouse_position()
		LOSHelper.draw_los(unit_pos, local_event_pos)
		
		var screen_pos: Vector2 = controller.get_viewport().get_mouse_position()
		if (controller.target_hex == LOSHelper.ground_layer.local_to_map(local_event_pos) and controller.origin_hex == controller.selected_unit.current_hex):
			controller.get_parent().ui.show_target_hex_cover_distance(screen_pos, controller.targetCover, controller.distance, controller.firepower)
		else:
			controller.origin_hex = controller.selected_unit.current_hex
			controller.target_hex = LOSHelper.ground_layer.local_to_map(local_event_pos)
			var origin_cube: Vector3i = controller.selected_unit.current_cube
			var target_cube: Vector3i = LOSHelper.ground_layer.local_to_cube(local_event_pos)
			controller.distance = LOSHelper.ground_layer.cube_distance(origin_cube, target_cube)
			# safely grab the inner dict for this shooter-hex
			var cover_map: Dictionary = LOSHelper.los_lookup.get(controller.origin_hex, {})
			if cover_map and cover_map.has(controller.target_hex):
				var data: Dictionary = cover_map[controller.target_hex]
				controller.targetCover 	= data["target_cover"]
			else:
				controller.targetCover = 0  # no LOS or no cover entry
				controller.get_parent().ui.hide_target_hex_cover_distance()
				controller.target_hex = null
				controller.origin_hex = null
				return
			# now display it
			controller.firepower = controller.selected_unit.firepower
			if controller.distance > controller.selected_unit.weapon_range:
				if controller.distance <= controller.selected_unit.weapon_range * 2:
					controller.firepower = controller.firepower / 2
				else:
					controller.firepower = 0
			
			controller.get_parent().ui.show_target_hex_cover_distance(screen_pos, controller.targetCover, controller.distance, controller.firepower)
			#selected_unit.set_cover(targetCover)
	else:
		controller.get_parent().ui.hide_target_hex_cover_distance()


#var last_mouse_position: Vector2
#func _on_camera_moved():
	#var pos = get_local_mouse_position()
	#if abs(pos.x - last_mouse_position.x) > 1 or abs(pos.y - last_mouse_position.y) > 1:
		#handle_mouse_event_position_changed(pos)
		#last_mouse_position = pos


static func hex_glow(controller: Node2D, pos: Vector2) -> void:
	var glow: ColorRect = controller.glow_maker_scene.instantiate()
	glow.position = pos
	controller.add_child(glow)


static func select_unit(controller: Node2D, unit: Unit) -> void:
	if controller.selected_unit:
		controller.selected_unit.deselect()
	controller.selected_unit = unit
	unit.select()
	controller.influence_map_debug_draw.set_selected_unit(unit)


static func deselect_unit(controller: Node2D, unit: Unit) -> void:
	if controller.selected_unit == unit:
		controller.selected_unit.deselect()
		controller.selected_unit = null
		LOSHelper.clear_los()
		controller.influence_map_debug_draw.set_selected_unit(null)


static func get_position_advice(unit: Unit, controller: Node2D) -> PositionResult:
	# Inspection never assigns a mission or invokes the tactical executor.
	var query: PositionQuery = PositionQuery.new()
	query.unit = unit
	query.team = unit.team
	query.objective_hex = controller.influence_map_controller.objectives_by_team.get(unit.team, unit.current_hex)
	var directors: Array[DefenseDirector] = [controller.defense_director, controller.get_node("DefenseDirector2")]
	for director: DefenseDirector in directors:
		var planner: PlatoonAI = director.platoon_ai
		if planner == null or planner.team != unit.team:
			continue
		if planner.active and planner.squad_assignments.has(unit):
			return planner.squad_assignments[unit]["result"]
		var mission: MissionOrder = planner.current_order
		if mission == null:
			mission = director.create_initial_order()
		query.objective_hex = mission.objective_hex
		query.profile = PositionProfile.for_mode(mission.position_mode)
		query.geography = mission.geography
		query.defense_radius = mission.defense_radius
		query.movement_radius = mission.movement_radius
		query.sector_cells = mission.sector_cells
		query.fallback_hexes = mission.fallback_hexes
		query.reservations = planner.reserved_hexes_by_squad.duplicate()
		break
	for friendly: Unit in Globals.get_units_for_team(unit.team):
		if friendly.movement != null and friendly.movement.is_moving:
			query.reservations[friendly] = friendly.movement.target_hex
	return controller.influence_map_controller.query_positions(query)
