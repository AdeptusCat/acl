extends Node

@export var enabled: bool = true

signal draw_los_to_enemy(from_hex, to_hex)

func _on_unit_entered_hex(unit: Unit, _vector):
	if not enabled:
		return
	if not unit.alive or unit.surrendered:
		return
	
	var visible_hexes: Dictionary = LOSHelper.los_lookup.get(unit.current_hex, {})
	var terrain_defence_bonus: int = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(unit.current_hex))
	visible_hexes[unit.current_hex] = {"shooter_cover" = terrain_defence_bonus, "target_cover" = terrain_defence_bonus}
	
	# Clear old visibility info for this unit
	Globals.unit_enemies_in_los[unit] = []

	for enemy_unit in Globals.units:
		if enemy_unit == unit:
			continue
		if enemy_unit.team != unit.team and enemy_unit.current_hex in visible_hexes:
			draw_los_to_enemy.emit(unit.current_hex, enemy_unit.current_hex)
			if not Globals.unit_enemies_in_los.has(unit):
				continue
			Globals.unit_enemies_in_los[unit].append(enemy_unit)

			## Fire immediately if stationary (optional fast reaction shot)
			#if enemy_unit.moving or not enemy_unit.alive or enemy_unit.broken or enemy_unit.surrendered:
				#if enemy_unit.broken:
					#var distance: int = LOSHelper.ground_layer.cube_distance(enemy_unit.current_cube, unit.current_cube)
					#if distance <= 1:
						#enemy_unit.stress_system.state_changed.emit(enemy_unit.stress_system.state, enemy_unit.stress_system.state)
			#else:
				#var _distance: int = LOSHelper.ground_layer.cube_distance(enemy_unit.current_cube, unit.current_cube)
				#
				## safely grab the inner dict for this shooter-hex
				#var cover_map = LOSHelper.los_lookup.get(enemy_unit.current_hex, null)
				#var targetCover 
				#if cover_map and cover_map.has(unit.current_hex):
					#var data        = cover_map[unit.current_hex]
					#targetCover = data["target_cover"]
				#else:
					#targetCover = 0  # no LOS or no cover entry
#
				## now display it
				#unit.set_cover(targetCover)
				#enemy_unit.order(Globals.UnitCmd.ATTACK, unit)

	# 🔥 Update LOS for all units too (global re-check)
	update_all_unit_visibilities()


func update_all_unit_visibilities():
	for unit in Globals.units:
		if not unit.alive:
			continue
		var visible_hexes: Dictionary = LOSHelper.los_lookup.get(unit.current_hex, {})
		var terrain_defence_bonus: int = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(unit.current_hex))
		visible_hexes[unit.current_hex] = {"shooter_cover" = terrain_defence_bonus, "target_cover" = terrain_defence_bonus}
		Globals.unit_enemies_in_los[unit] = []

		for enemy_unit in Globals.units:
			if enemy_unit == unit or not enemy_unit.alive:
				continue
			if enemy_unit.team != unit.team and enemy_unit.current_hex in visible_hexes:
				Globals.unit_enemies_in_los[unit].append(enemy_unit)
