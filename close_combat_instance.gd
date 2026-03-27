extends RefCounted
class_name CloseCombatInstance


var hex: Vector2i = Vector2i.ZERO
var attackers: Array[Soldier] = []
var defenders: Array[Soldier] = []

var ongoing: bool = true
var elapsed: float = 0.0
var opening_shock_done: bool = false



func test():
	get_close_morale_attack_mult(attackers[0].unit.stress_system.state)
	get_close_morale_defense_mult(defenders[0].unit.stress_system.state)
	
	var terrain_defence_bonus: int = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(defenders[0].unit.current_hex))
	get_close_location_mods(terrain_defence_bonus, defenders[0].is_defender)




func compute_attack_power(actor: Soldier) -> float:
	var value: float = 0.0
	value += actor.base_attack
	value += actor.weapon_attack
	value += actor.side_attack_bonus
	value *= actor.morale_attack_mult
	value *= actor.location_attack_mult
	return max(value, 0.01)


func compute_defense_power(target: Soldier) -> float:
	var value: float = 0.0
	value += target.base_defense
	value += target.weapon_defense
	value += target.side_defense_bonus
	value *= target.morale_defense_mult
	value *= target.location_defense_mult
	return max(value, 0.01)


func compute_hit_chance(attack_power: float, defense_power: float) -> float:
	var chance: float = attack_power / (attack_power + defense_power)
	chance = clamp(chance, 0.05, 0.95)
	return chance


func get_close_location_mods(hex_defense_value: float, is_attacker: bool) -> float:
	if is_attacker:
		return max(0.5, 1.0 - hex_defense_value * 0.25)
	return 1.0 + hex_defense_value * 0.25


func get_close_morale_attack_mult(state: int) -> float:
	if state == UnitStates.MoraleState.NORMAL:
		return 1.0
	if state == UnitStates.MoraleState.CAUTIOUS:
		return 0.9
	if state == UnitStates.MoraleState.PINNED:
		return 0.65
	if state == UnitStates.MoraleState.PANIC:
		return 0.35
	if state == UnitStates.MoraleState.COMBAT_INEFFECTIVE:
		return 0.1
	return 1.0



func get_close_morale_defense_mult(state: int) -> float:
	if state == UnitStates.MoraleState.NORMAL:
		return 1.0
	if state == UnitStates.MoraleState.CAUTIOUS:
		return 0.95
	if state == UnitStates.MoraleState.PINNED:
		return 0.75
	if state == UnitStates.MoraleState.PANIC:
		return 0.45
	if state == UnitStates.MoraleState.COMBAT_INEFFECTIVE:
		return 0.2
	return 1.0
