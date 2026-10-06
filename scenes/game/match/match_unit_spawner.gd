extends RefCounted
class_name MatchUnitSpawner

# Synchronous MatchUnitSpawner operations; state and scene identity stay on the caller.


static func spawn_unit(controller: Node2D, team: Globals.Team, location: Vector2i, squad_type: Globals.SquadType, formation_id: int) -> void:
	var unit: Unit = controller.unit_scene.instantiate()
	unit.ground_map = controller.ground_layer
	unit.team = team
	match squad_type:
		Globals.SquadType.Rifle:
			unit.make_rifle_squad = true
		Globals.SquadType.MG:
			unit.make_light_mg_team = true
		Globals.SquadType.PLATOON_HEADQUARTERS:
			unit.make_platoon_headquarters_squad = true
	
	unit.formation_id = formation_id 
	#$UnitContainer.add_child(unit)
	unit.position = controller.ground_layer.map_to_local(location)
	
	var map_coords: Vector2i = controller.ground_layer.local_to_map(controller.ground_layer.map_to_local(location))
	unit.position = controller.ground_layer.map_to_local(map_coords)
	unit.current_hex = map_coords
	unit.current_cube = controller.ground_layer.map_to_cube(map_coords)
	
	unit.hide()
	controller.get_node("UnitContainer").add_child(unit)
	
	unit.set_team(team)
	
	unit.unit_died.connect(controller._on_unit_died)
	unit.unit_entered_hex.connect(LOS._on_unit_entered_hex)
	unit.unit_entered_hex.connect(controller._on_unit_entered_hex)
	unit.unit_arrived_at_hex.connect(MovementSystem._on_arrived)
	unit.current_hex = controller.ground_layer.local_to_map(unit.global_position)
	unit.current_cube = controller.ground_layer.map_to_cube(unit.current_hex)
	unit.deselect_unit.connect(controller._deselect_unit)
	unit.started_moving.connect(controller._on_started_moving)
	unit.unit_surrendered.connect(controller._on_unit_surrendered)
	unit.squad_fire.draw_los_to_target_unit.connect(controller.los_renderer._on_draw_los_to_target_unit)
	unit.movement.draw_movement_path.connect(controller.los_renderer._on_draw_draw_movement_path)
	unit.draw_command_link_strength.connect(controller.los_renderer._on_draw_command_link_strength)
	unit.draw_leader_presence_strength.connect(controller.los_renderer._on_draw_leader_presence_strength)
	unit.squad_fire.shooting.connect(controller._on_unit_shooting)
	Globals.register_unit(unit.team, unit.company, unit.platoon, unit.squad, unit)
	unit.update_terrain_defense_bonus()
			
	# assign platoon headquarter to squad 
	if not unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS and not unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
		unit.command_squad = Globals.get_unit(unit.team, unit.company, unit.platoon, 0)
	# assign company headquarter to platoon headquarter 
	if unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
		unit.command_squad = Globals.get_unit(unit.team, unit.company, 0, 0)


static func spawn_units_from_match_save(controller: Node2D, match_save: MatchSaveData) -> void:
	for data: UnitSaveData in match_save.player_units:
		var packed_scene: PackedScene = ResourceLoader.load(data.unit_scene_path) as PackedScene

		if packed_scene == null:
			push_error("Could not load unit scene: %s" % data.unit_scene_path)
			continue
		controller.spawn_unit_from_save(data.team, Vector2.ZERO, data.squad_loadout, 0)
		#var unit: Unit = packed_scene.instantiate() as Unit
#
		#if unit == null:
			#push_error("Instanced scene is not Unit: %s" % unit_save_data.unit_scene_path)
			#continue
#
		#add_child(unit)
		#unit.apply_save_data(unit_save_data)


static func spawn_unit_from_save(controller: Node2D, team: Globals.Team, location: Vector2i, squad_loadout: SquadLoadoutSpec, formation_id: int) -> void:
	var unit: Unit = controller.unit_scene.instantiate()
	controller.get_node("UnitContainer").add_child(unit)
	unit.ground_map = controller.ground_layer
	unit.team = team
	unit.squad_loadout = squad_loadout
	unit._setup_runtime_soldiers(squad_loadout)
	unit.add_to_group("units")
	#match squad_type:
		#Globals.SquadType.Rifle:
			#unit.make_rifle_squad = true
		#Globals.SquadType.MG:
			#unit.make_light_mg_team = true
		#Globals.SquadType.PLATOON_HEADQUARTERS:
			#unit.make_platoon_headquarters_squad = true
	
	unit.formation_id = formation_id 
	#$UnitContainer.add_child(unit)
	unit.position = LOSHelper.ground_layer.map_to_local(location)
	#unit.position = ground_layer.map_to_local(location)
	
	var map_coords: Vector2i = LOSHelper.ground_layer.local_to_map(LOSHelper.ground_layer.map_to_local(location))
	unit.position = LOSHelper.ground_layer.map_to_local(map_coords)
	unit.current_hex = map_coords
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(map_coords)
	
	#unit.hide()
	
	
	unit.set_team(team)
	
	unit.unit_died.connect(controller._on_unit_died)
	unit.unit_entered_hex.connect(LOS._on_unit_entered_hex)
	unit.unit_entered_hex.connect(controller._on_unit_entered_hex)
	unit.unit_arrived_at_hex.connect(MovementSystem._on_arrived)
	unit.current_hex = controller.ground_layer.local_to_map(unit.global_position)
	unit.current_cube = controller.ground_layer.map_to_cube(unit.current_hex)
	unit.deselect_unit.connect(controller._deselect_unit)
	unit.started_moving.connect(controller._on_started_moving)
	unit.unit_surrendered.connect(controller._on_unit_surrendered)
	unit.squad_fire.draw_los_to_target_unit.connect(controller.los_renderer._on_draw_los_to_target_unit)
	unit.movement.draw_movement_path.connect(controller.los_renderer._on_draw_draw_movement_path)
	unit.draw_command_link_strength.connect(controller.los_renderer._on_draw_command_link_strength)
	unit.draw_leader_presence_strength.connect(controller.los_renderer._on_draw_leader_presence_strength)
	unit.squad_fire.shooting.connect(controller._on_unit_shooting)
	Globals.register_unit(unit.team, unit.company, unit.platoon, unit.squad, unit)
	unit.update_terrain_defense_bonus()
			
	# assign platoon headquarter to squad 
	if not unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS and not unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
		unit.command_squad = Globals.get_unit(unit.team, unit.company, unit.platoon, 0)
	# assign company headquarter to platoon headquarter 
	if unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
		unit.command_squad = Globals.get_unit(unit.team, unit.company, 0, 0)
