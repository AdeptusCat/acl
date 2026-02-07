extends Node

@onready var container = $"../UnitContainer"

@export var enabled: bool = true

signal draw_los_to_enemy(from_hex, to_hex)


#func _process(delta: float) -> void:
	#if not enabled:
		#return
	#for unit in units:
		#if unit.moving or not unit.alive or unit.broken or unit.surrendered:
			#continue
		#else:
			##if unit.team == Globals.team_player:
			##unit.combat.handle_auto_fire(delta, unit, unit_visible_enemies, unit.current_hex, unit.range, unit.fire_rate, unit.firepower)
			#unit.squad_fire.handle_auto_fire(delta, unit, unit_visible_enemies, unit.current_hex, unit.range, unit.fire_rate, unit.firepower)
			
func _on_unit_entered_hex(unit: Unit, vector):
	if not enabled:
		return
	if not unit.alive or unit.surrendered:
		return
	
	var visible_hexes = LOSHelper.los_lookup.get(unit.current_hex, [])
	
	# Clear old visibility info for this unit
	Globals.unit_visible_enemies[unit] = []

	for enemy_unit in Globals.units:
		if enemy_unit == unit:
			continue
		if enemy_unit.team != unit.team and enemy_unit.current_hex in visible_hexes:
			draw_los_to_enemy.emit(unit.current_hex, enemy_unit.current_hex)
			if not Globals.unit_visible_enemies.has(unit):
				continue
			Globals.unit_visible_enemies[unit].append(enemy_unit)

			# Fire immediately if stationary (optional fast reaction shot)
			if enemy_unit.moving or not enemy_unit.alive or enemy_unit.broken or enemy_unit.surrendered:
				if enemy_unit.broken:
					var distance: int = LOSHelper.ground_layer.cube_distance(enemy_unit.current_cube, unit.current_cube)
					if distance <= 1:
						enemy_unit.stress_system.state_changed.emit(enemy_unit.stress_system.state, enemy_unit.stress_system.state)
			else:
				var distance: int = LOSHelper.ground_layer.cube_distance(enemy_unit.current_cube, unit.current_cube)
				
				# safely grab the inner dict for this shooter-hex
				var cover_map = LOSHelper.los_lookup.get(enemy_unit.current_hex, null)
				var targetCover 
				if cover_map and cover_map.has(unit.current_hex):
					var data        = cover_map[unit.current_hex]
					targetCover = data["target_cover"]
				else:
					targetCover = 0  # no LOS or no cover entry

				# now display it
				unit.set_cover(targetCover)
				enemy_unit.order(Globals.UnitCmd.ATTACK, unit)
				#enemy_unit.fire_at(unit, distance, targetCover, unit_visible_enemies)

	# 🔥 Update LOS for all units too (global re-check)
	update_all_unit_visibilities()


func update_all_unit_visibilities():
	for unit in Globals.units:
		if not unit.alive:
			continue
		var visible_hexes = LOSHelper.los_lookup.get(unit.current_hex, [])
		Globals.unit_visible_enemies[unit] = []

		for enemy_unit in Globals.units:
			if enemy_unit == unit or not enemy_unit.alive:
				continue
			if enemy_unit.team != unit.team and enemy_unit.current_hex in visible_hexes:
				Globals.unit_visible_enemies[unit].append(enemy_unit)
