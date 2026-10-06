extends RefCounted
class_name CloseCombatCoordinator

# Synchronous CloseCombatCoordinator operations; state and scene identity stay on the caller.


static func set_close_combat_hexes_and_units(controller: Node2D) -> void:
	#Globals.units_in_close_combat.clear()
	#Globals.close_combat_locations.clear()
	
	#for child in close_combat_locations.get_children():
		#child.queue_free()
	
	for combat: CloseCombatInstance in controller.close_combat_instances.get_children():
		combat.refresh_participants()

	for unit: Unit in Globals.get_units():
		if not unit.is_good_order() or unit.squad_fire.soldiers.is_empty():
			continue
		var mask: int = 0
		var both_teams_present: bool = false
		var units_in_hex: Array[Unit] = LOSHelper.find_units_at(unit.current_hex)
		for _unit: Unit in units_in_hex:
			if not _unit.is_good_order() or _unit.squad_fire.soldiers.is_empty():
				continue
			match _unit.team:
				Globals.Team.AXIS:
					mask |= 1
				Globals.Team.ALLIES:
					mask |= 2
			if mask == 3:
				both_teams_present = true
		if both_teams_present:
			var close_combat_instance: CloseCombatInstance
			for close_combat_instance_present: CloseCombatInstance in controller.close_combat_instances.get_children():
				if not close_combat_instance_present.ongoing or close_combat_instance_present.is_queued_for_deletion():
					continue
				if close_combat_instance_present.hex == unit.current_hex:
					close_combat_instance = close_combat_instance_present
					break
			if not close_combat_instance:
				close_combat_instance = controller.close_combat_instance_scene.instantiate()
				close_combat_instance.hex = unit.current_hex
				close_combat_instance.terrain_defense_value = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(unit.current_hex))
				
			for _unit: Unit in units_in_hex:
				if not close_combat_instance.can_unit_participate(_unit):
					continue
				close_combat_instance.add_unit(_unit)
				_unit.movement.stop()
			#var close_combat_sign: Sprite2D = close_combat_sign_scene.instantiate()
			#close_combat_locations.add_child(close_combat_sign)
			#if not Globals.close_combat_locations.has(unit.current_hex):
				#Globals.close_combat_locations.append(unit.current_hex)
			#if not Globals.units_in_close_combat.has(unit):
				#Globals.units_in_close_combat.append(unit)
			
			if close_combat_instance.get_parent() == null:
				close_combat_instance.position = LOSHelper.ground_layer.map_to_local(unit.current_hex)
				controller.close_combat_instances.add_child(close_combat_instance)


#func set_close_combat_hexes_and_units():
	#Globals.units_in_close_combat.clear()
	#Globals.close_combat_locations.clear()
	#
	#for child in close_combat_locations.get_children():
		#child.queue_free()
	#
	#for unit: Unit in Globals.units:
		#if not unit.is_good_order():
			#continue
		#var mask: int = 0
		#var both_teams_present: bool = false
		#var units_in_hex: Array[Unit] = LOSHelper.find_units_at(unit.current_hex)
		#for _unit in units_in_hex:
			#if not _unit.is_good_order():
				#continue
			#match _unit.team:
				#Globals.Team.AXIS:
					#mask |= 1
				#Globals.Team.ALLIES:
					#mask |= 2
			#if mask == 3:
				#both_teams_present = true
		#if both_teams_present:
			#for _unit in units_in_hex:
				#_unit.in_close_combat = true
			#var close_combat_sign: Sprite2D = close_combat_sign_scene.instantiate()
			#close_combat_locations.add_child(close_combat_sign)
			#close_combat_sign.position = LOSHelper.ground_layer.map_to_local(unit.current_hex)
			#if not Globals.close_combat_locations.has(unit.current_hex):
				#Globals.close_combat_locations.append(unit.current_hex)
			#if not Globals.units_in_close_combat.has(unit):
				#Globals.units_in_close_combat.append(unit)
		#else:
			#for _unit in units_in_hex:
				#_unit.in_close_combat = false
