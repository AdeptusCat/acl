extends Node

@onready var container = $"../UnitContainer"


var unit_visible_enemies: Dictionary
var units: Array[Node2D] = []
signal draw_los_to_enemy(from_hex, to_hex)


func _process(delta: float) -> void:
	for unit in units:
		if not unit.moving and unit.alive and not unit.broken:
			unit.combat.handle_auto_fire(delta, unit, unit_visible_enemies, unit.current_hex, unit.range, unit.fire_rate, unit.firepower)


func _cover(u,e):
	var m = LOSHelper.los_lookup.get(e.current_hex, {})
	return m.get(u.current_hex, {}).get("target_cover", 0)

func _on_unit_moved(unit, vector):
	if not unit.alive:
		return
	
	var visible_hexes = LOSHelper.los_lookup.get(unit.current_hex, [])

	# Clear old visibility info for this unit
	unit_visible_enemies[unit] = []

	for enemy_unit in units:
		if enemy_unit == unit:
			continue
		if enemy_unit.team != unit.team and enemy_unit.current_hex in visible_hexes:
			draw_los_to_enemy.emit(unit.current_hex, enemy_unit.current_hex)
			if not unit_visible_enemies.has(unit):
				continue
			unit_visible_enemies[unit].append(enemy_unit)

			# Fire immediately if stationary (optional fast reaction shot)
			if not enemy_unit.movement.moving:
				var distance = enemy_unit.current_hex.distance_to(unit.current_hex)
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
				enemy_unit.fire_at(unit, distance, targetCover, unit_visible_enemies)

	# 🔥 Update LOS for all units too (global re-check)
	update_all_unit_visibilities()

func update_all_unit_visibilities():
	for unit in units:
		if not unit.alive:
			continue
		var visible_hexes = LOSHelper.los_lookup.get(unit.current_hex, [])
		unit_visible_enemies[unit] = []

		for enemy_unit in units:
			if enemy_unit == unit or not enemy_unit.alive:
				continue
			if enemy_unit.team != unit.team and enemy_unit.current_hex in visible_hexes:
				unit_visible_enemies[unit].append(enemy_unit)
