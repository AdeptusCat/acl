extends RefCounted
class_name MatchInteractionHandler

# Synchronous MatchInteractionHandler operations; state and scene identity stay on the caller.


static func can_command_unit(unit: Unit) -> bool:
	return is_instance_valid(unit) and (unit.team == Globals.team_player or Debug.enemy_selectable)


static func command_name(option: WheelOption.Option) -> String:
	return str(WheelOption.COMMAND_NAMES.get(option, "Cancel"))


static func command_restriction(controller: Node2D, map_hex: Vector2i, option: WheelOption.Option) -> String:
	if option == WheelOption.Option.NONE:
		return ""
	if controller.end_game_handled and not controller.continuing_after_end:
		return "The mission has ended."
	var unit: Unit = controller.selected_unit
	if not is_instance_valid(unit) or not unit.is_active():
		return "Select an active squad."
	if not can_command_unit(unit):
		return "Enemy squads can only be inspected."
	if option == WheelOption.Option.ROUT:
		return unit.get_rout_restriction()
	if unit.surrendered:
		return "This squad has surrendered."
	if unit.broken:
		return "This squad is routed."
	if unit.in_close_combat:
		return "Cannot issue orders during close combat."
	if option == WheelOption.Option.STOP:
		return ""
	if controller.ground_layer.get_cell_source_id(map_hex) == -1:
		return "Choose a hex on the battlefield."
	match option:
		WheelOption.Option.MOVE_NORMAL:
			if unit.stress_system.state == STATES.MoraleState.PINNED:
				return "Pinned: use Rout to attempt escape."
			if map_hex == unit.current_hex:
				if unit.movement.is_moving or unit.position.distance_to(controller.ground_layer.map_to_local(map_hex)) > 0.1:
					return ""
				return "The squad is already at this hex."
			var pathfinder: AStar2D = Globals.astars.get(unit.team)
			var from_id: int = controller.ground_layer.pathfinding_get_point_id(unit.current_hex)
			var to_id: int = controller.ground_layer.pathfinding_get_point_id(map_hex)
			if pathfinder == null or not pathfinder.has_point(from_id) or not pathfinder.has_point(to_id):
				return "No route to this hex."
			if pathfinder.is_point_disabled(to_id) or pathfinder.get_id_path(from_id, to_id).is_empty():
				return "No route to this hex."
		WheelOption.Option.FIRE_AT:
			if unit.ai_support_only:
				return "This squad cannot fire."
			if InfluenceUnitQuery.get_unit_firepower(unit) <= 0.0:
				return "No usable weapons or ammunition."
			var data: Dictionary = target_feedback(controller, map_hex)
			if not bool(data["in_range"]):
				return "Out of range."
			if not bool(data["sight_clear"]) and not bool(data["indirect"]):
				return "Line of sight blocked."
		_:
			return "This command is unavailable."
	return ""


static func target_feedback(controller: Node2D, target: Vector2i) -> Dictionary:
	var unit: Unit = controller.selected_unit
	var distance: int = controller.ground_layer.cube_distance(unit.current_cube, controller.ground_layer.map_to_cube(target))
	var cover_map: Dictionary = LOSHelper.los_lookup.get(unit.current_hex, {})
	var sight_clear: bool = cover_map.has(target)
	var cover: int = 0
	if sight_clear:
		cover = int(cover_map[target].get("target_cover", 0))
	var indirect: bool = unit.squad_type == Globals.SquadType.MORTAR
	if indirect:
		# Mortar impacts use the target hex's terrain, independent of LOS edge cover.
		cover = LOSHelper.is_sample_point_in_building(controller.ground_layer.map_to_local(target))
	var in_range: bool = distance <= InfluenceUnitQuery.get_unit_range(unit)
	var power: float = InfluenceUnitQuery.get_firepower_at_range(unit, distance) * InfluenceUnitQuery.get_unit_effectiveness(unit)
	power *= SquadFireMath.hit_cover_multiplier(float(cover), indirect)
	power *= SquadFireMath.point_blank_hit_multiplier(distance)
	if not sight_clear and not indirect:
		power = 0.0
	return {"distance": distance, "cover": cover, "sight_clear": sight_clear, "indirect": indirect, "in_range": in_range, "firepower": power}


static func order_via_option_wheel(controller: Node2D, map_hex: Vector2i, option: WheelOption.Option) -> bool:
	if option == WheelOption.Option.NONE:
		return false
	var reason: String = command_restriction(controller, map_hex, option)
	var command: String = command_name(option)
	if not reason.is_empty():
		controller.order_feedback.emit(false, command, reason)
		return false
	var unit: Unit = controller.selected_unit
	var glow_hex: Vector2i = map_hex
	match option:
		WheelOption.Option.MOVE_NORMAL:
			unit.order(Globals.UnitCmd.MOVE, map_hex)
		WheelOption.Option.FIRE_AT:
			unit.setAttackState(Unit.AttackState.MANUAL_GROUND)
			unit.order(Globals.UnitCmd.FIRE_AT_HEX, map_hex)
		WheelOption.Option.STOP:
			unit.clear_orders()
			unit.squad_fire.clear_target()
			unit.setAttackState(Unit.AttackState.AUTO)
			glow_hex = unit.current_hex
		WheelOption.Option.ROUT:
			if not unit.request_rout():
				controller.order_feedback.emit(false, command, unit.get_rout_restriction())
				return false
			glow_hex = unit.current_hex
	controller.hex_glow(controller.ground_layer.map_to_local(glow_hex))
	controller.order_feedback.emit(true, command, "")
	return true

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
	if not is_instance_valid(controller.ground_layer):
		return
	var ground: HexagonTileMapLayer = controller.ground_layer
	var local_point: Vector2 = ground.get_global_transform_with_canvas().affine_inverse() * event_pos
	var map_hex: Vector2i = ground.local_to_map(local_point)
	controller.hex_selected.emit(map_hex, local_point)
	var candidates: Array[Unit] = []
	for candidate: Unit in Globals.get_units():
		if candidate.is_active() and candidate.is_visible_in_tree():
			candidates.append(candidate)
	# Stacked and moving counters can extend into the neighboring hex on screen.
	var picked: Unit = _counter_under_pointer(candidates, event_pos)
	var stack_hex: Vector2i = map_hex
	if picked != null:
		stack_hex = picked.current_hex
	var units: Array[Unit] = []
	var selection_team: Globals.Team = Globals.team_player
	if picked != null:
		selection_team = picked.team
	var friendly_only: bool = selection_team == Globals.team_player
	for candidate: Unit in candidates:
		if candidate.current_hex == stack_hex and candidate.team == selection_team:
			units.append(candidate)
	if units.is_empty() and picked == null:
		for candidate: Unit in candidates:
			if candidate.current_hex == stack_hex:
				units.append(candidate)
				friendly_only = false
	if friendly_only and units.size() > 1 and controller.has_method("cycle_stack_selection"):
		if controller.cycle_stack_selection(stack_hex, picked):
			return
	if units.is_empty():
		if is_instance_valid(controller.selected_unit):
			controller._deselect_unit(controller.selected_unit)
			controller.hide_unit_details_in_ui.emit()
		controller.previous_selected_hex = stack_hex
		controller.selected_hex_index = 0
		return
	var selected_index: int = units.find(controller.selected_unit)
	if controller.previous_selected_hex == stack_hex and selected_index >= 0:
		controller.selected_hex_index = (selected_index + 1) % units.size()
	else:
		controller.selected_hex_index = maxi(0, units.find(picked))
	controller.previous_selected_hex = stack_hex
	var unit: Unit = units[controller.selected_hex_index]
	if unit != controller.selected_unit:
		controller._select_unit(unit)
	controller.show_unit_details_in_ui.emit(unit)
	LOSHelper.clear_los()


static func _counter_under_pointer(candidates: Array[Unit], screen_point: Vector2) -> Unit:
	var picked: Unit = null
	var picked_z: int = -4097
	for candidate: Unit in candidates:
		if not is_instance_valid(candidate.ui) or not candidate.ui.contains_battlefield_point(screen_point):
			continue
		var effective_z: int = 0
		var item: CanvasItem = candidate
		while item != null:
			effective_z += item.z_index
			if not item.z_as_relative:
				break
			item = item.get_parent() as CanvasItem
		if picked == null or effective_z >= picked_z:
			picked = candidate
			picked_z = effective_z
	return picked


# Nullable tile coordinates: Vector2i when present, null when cleared.


static func handle_mouse_event_position_changed(controller: Node2D, event_pos: Vector2) -> void:
	controller.mouse_event_position_changed.emit(event_pos)
	var local_point: Vector2 = Vector2.ZERO
	if is_instance_valid(controller.ground_layer):
		local_point = controller.ground_layer.get_local_mouse_position()
	refresh_target_preview(controller, local_point, controller.get_viewport().get_mouse_position())


static func refresh_target_preview(controller: Node2D, local_point: Vector2, screen_point: Vector2) -> void:
	var world: Node2D = controller.get_parent() as Node2D
	if not is_instance_valid(controller.ground_layer) or (controller.end_game_handled and not controller.continuing_after_end) or not is_instance_valid(controller.selected_unit) or not controller.selected_unit.is_active() or not can_command_unit(controller.selected_unit):
		world.ui.hide_target_hex_cover_distance()
		LOSHelper.clear_los()
		return
	if world.ui.selection_wheel_alt.is_open() or controller.get_viewport().gui_get_hovered_control() != null or world.hex_inspection.hovered_direction >= 0:
		world.ui.hide_target_hex_cover_distance()
		LOSHelper.clear_los()
		return
	var target: Vector2i = controller.ground_layer.local_to_map(local_point)
	if controller.ground_layer.get_cell_source_id(target) == -1 or target == controller.selected_unit.current_hex:
		world.ui.hide_target_hex_cover_distance()
		LOSHelper.clear_los()
		return
	var data: Dictionary = target_feedback(controller, target)
	controller.origin_hex = controller.selected_unit.current_hex
	controller.target_hex = target
	controller.distance = int(data["distance"])
	controller.targetCover = int(data["cover"])
	controller.firepower = float(data["firepower"])
	LOSHelper.draw_los(controller.selected_unit.position, local_point)
	world.ui.show_target_hex_cover_distance(screen_point, controller.targetCover, controller.distance, controller.firepower, bool(data["sight_clear"]), bool(data["indirect"]), bool(data["in_range"]))


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
	if not unit.is_active():
		return
	if unit.team != Globals.team_player and not unit.is_visible_in_tree():
		return
	controller.influence_map_controller.clear_inspection_queries()
	if controller.selected_unit:
		controller.selected_unit.deselect()
	controller.selected_unit = unit
	unit.select()
	controller.influence_map_debug_draw.set_selected_unit(unit)


static func deselect_unit(controller: Node2D, unit: Unit) -> void:
	if controller.selected_unit == unit:
		controller.influence_map_controller.clear_inspection_queries()
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
		query.defense_responsibility = mission.defense_responsibility
		query.withdrawal_requested = mission.execution_intent == TacticalPositionExecutor.Intent.WITHDRAW
		if mission.position_mode == PositionProfile.Mode.DEFEND:
			query.profile.max_exposure_seconds = mission.exposure_budget_seconds
			query.profile.max_open_exposure_seconds = mission.open_crossing_budget_seconds
		query.reservations = planner.reserved_hexes_by_squad.duplicate()
		break
	for friendly: Unit in Globals.get_units_for_team(unit.team):
		if friendly.movement != null and friendly.movement.is_moving:
			query.reservations[friendly] = friendly.movement.target_hex
	query.profile = PositionProfile.for_unit(query.profile, unit)
	return controller.influence_map_controller.query_inspection_positions(query)
