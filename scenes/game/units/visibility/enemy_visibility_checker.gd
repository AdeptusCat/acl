extends Node
class_name EnemyVisibilityChecker


func check_enemy_visibility(unit: Unit) -> void:
	return
	var enemys_in_los: Array = Globals.unit_enemies_in_los.get(unit, [])
	var enemys_visible: Array = Globals.unit_visible_enemies.get(unit, [])
	Globals.unit_visible_enemies[unit] = []
	for enemy: Unit in enemys_in_los:
		if enemys_visible.has(enemy):
			continue
		Globals.unit_visible_enemies[unit].append(enemy)
	
