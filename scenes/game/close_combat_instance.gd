extends Node2D
class_name CloseCombatInstance


enum EngagementType {
	ASSAULT,
	MEETING
}

enum SideRole {
	NONE,
	ATTACKER,
	DEFENDER,
	CONTESTED
}

enum EntryRole {
	NONE,
	INITIAL_HOLDER,
	INITIAL_ASSAULTER,
	MEETING_ENTRANT,
	DEFENDER_REINFORCEMENT,
	ATTACKER_REINFORCEMENT,
	MEETING_REINFORCEMENT
}

class Participant:
	extends RefCounted

	var unit: Unit = null
	var unit_id: int = 0
	var team: Globals.Team = Globals.Team.AXIS
	var side_role: int = SideRole.NONE
	var entry_role: int = EntryRole.NONE
	var defense_preparedness: float = 0.0
	var joined_at: float = 0.0
	var time_in_instance: float = 0.0
	var active: bool = true

	func _init(p_unit: Unit) -> void:
		unit = p_unit
		if unit != null:
			unit_id = unit.get_instance_id()

var hex: Vector2i = Vector2i.ZERO
var terrain_defense_value: int = 0

var engagement_type: int = EngagementType.ASSAULT
var participants: Array[Participant] = []

var elapsed: float = 0.0
var meeting_elapsed: float = 0.0
var meeting_resolution_delay: float = 1.5

var units_by_team: Dictionary[Globals.Team, Array] = {
	Globals.Team.AXIS: [],
	Globals.Team.ALLIES: [],
}
var soldiers_by_team: Dictionary[Globals.Team, Array] = {
	Globals.Team.AXIS: [],
	Globals.Team.ALLIES: [],
}

var Team_A_soldiers: Array[Soldier] = []
var Team_B_soldiers: Array[Soldier] = []

var ongoing: bool = true
var opening_shock_done: bool = false



func setup_close_combat():
	terrain_defense_value = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(hex))
	


func add_unit(unit: Unit):
	if units_by_team[unit.team].has(unit):
		return
	var participant: Participant = Participant.new(unit)
	participant.team = unit.team
	if unit.moving: 
		participant.side_role = SideRole.ATTACKER
		if elapsed == 0.0:
			participant.entry_role = EntryRole.INITIAL_ASSAULTER
		else:
			participant.entry_role = EntryRole.ATTACKER_REINFORCEMENT
	else:
		participant.side_role = SideRole.DEFENDER
		if elapsed == 0.0:
			participant.entry_role = EntryRole.INITIAL_HOLDER
		else:
			participant.entry_role = EntryRole.DEFENDER_REINFORCEMENT
	
	participant.defense_preparedness = unit.close_combat_defense_preparedness
	participant.joined_at = elapsed
	participant.time_in_instance = 0.0 # ?
	participant.active = true
	for soldier in participant.unit.squad_fire.soldiers:
		soldier.cooldown_remaining = get_soldier_colldown_time(soldier, participant.unit.stress_system.state)
		soldiers_by_team[participant.team].append(soldier)
	units_by_team[unit.team].append(unit)
	unit.in_close_combat = true
	participants.append(participant)
	

#func test():
	#get_close_morale_attack_mult(attackers[0].unit.stress_system.state)
	#get_close_morale_defense_mult(defenders[0].unit.stress_system.state)
	#
	#var terrain_defence_bonus: int = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(defenders[0].unit.current_hex))
	#get_close_location_mods(terrain_defence_bonus, defenders[0].is_defender)


func get_soldier_colldown_time(soldier: Soldier, state: UnitStates.MoraleState):
	var cooldown_time: float = 0.0
	match soldier.weapon.type:
		WeaponSpec.WeaponType.Rifle:
			cooldown_time = 0.8
		WeaponSpec.WeaponType.SMG:
			cooldown_time = 0.5
		WeaponSpec.WeaponType.MG:
			cooldown_time = 3.0
	
	var morale_mod: float = 1.0
	match state:
		UnitStates.MoraleState.NORMAL:
			morale_mod = 1.0
		UnitStates.MoraleState.CAUTIOUS:
			morale_mod = 1.2
		UnitStates.MoraleState.PINNED:
			morale_mod = 1.5
		UnitStates.MoraleState.PANIC:
			morale_mod = 2.0
		UnitStates.MoraleState.COMBAT_INEFFECTIVE:
			morale_mod = 2.0
	cooldown_time *= morale_mod
	
	var rand_mod: float = randf_range(0.0, 2.0)
	cooldown_time *= rand_mod
	
	return cooldown_time


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


func get_close_morale_attack_mult(state: UnitStates.MoraleState) -> float:
	if state == UnitStates.MoraleState.NORMAL:
		return 1.0
	if state == UnitStates.MoraleState.CAUTIOUS:
		return 0.9
	if state == UnitStates.MoraleState.PINNED:
		return 0.10
	if state == UnitStates.MoraleState.PANIC:
		return 0.00
	if state == UnitStates.MoraleState.COMBAT_INEFFECTIVE:
		return 0.00
	return 1.0



func get_close_morale_defense_mult(state: UnitStates.MoraleState) -> float:
	if state == UnitStates.MoraleState.NORMAL:
		return 1.0
	if state == UnitStates.MoraleState.CAUTIOUS:
		return 0.95
	if state == UnitStates.MoraleState.PINNED:
		return 0.10
	if state == UnitStates.MoraleState.PANIC:
		return 0.00
	if state == UnitStates.MoraleState.COMBAT_INEFFECTIVE:
		return 0.00
	return 1.0


func get_soldier_defense_strength(soldier: Soldier) -> float:
	var strength: float = soldier.base_defense
	
	if soldier.weapon.type == WeaponSpec.WeaponType.Rifle:
		strength += 0.25
	if soldier.weapon.type == WeaponSpec.WeaponType.SMG:
		strength += 0.45
	if soldier.weapon.type == WeaponSpec.WeaponType.MG:
		strength += 0.05
	
	var morale_mod: float = get_close_morale_defense_mult(soldier.unit.stress_system.state )
	strength *= morale_mod
	
	var terrain_defense_value_prepared: float = terrain_defense_value * soldier.unit.close_combat_defense_preparedness
	var terrain_mod: float = get_close_location_mods(terrain_defense_value_prepared, false)
	strength *= terrain_mod
	
	#var preparedness_mult: float = lerp(0.7, 1.25, soldier.unit.close_combat_defense_preparedness)
	#strength *= preparedness_mult
	
	#print("d ", strength)
	
	return strength


func get_soldier_attack_strength(soldier: Soldier) -> float:
	var strength: float = soldier.base_defense
	
	if soldier.weapon.type == WeaponSpec.WeaponType.Rifle:
		strength += 0.20
	if soldier.weapon.type == WeaponSpec.WeaponType.SMG:
		strength += 0.40
	if soldier.weapon.type == WeaponSpec.WeaponType.MG:
		strength += 0.00
	
	var morale_mod: float = get_close_morale_defense_mult(soldier.unit.stress_system.state )
	strength *= morale_mod
	
	var terrain_mod: float = get_close_location_mods(terrain_defense_value, true)
	strength *= terrain_mod
	
	#print("a ", strength)
	
	
	return strength


func _on_timer_timeout() -> void:
	if units_by_team[Globals.Team.AXIS].is_empty():
		quit_close_combat()
	if units_by_team[Globals.Team.ALLIES].is_empty():
		quit_close_combat()
	
	var has_axis: bool = false
	var has_allis: bool = false
	for participant in participants:
		if participant.team == Globals.Team.AXIS:
			has_axis = true
		if participant.team == Globals.Team.ALLIES:
			has_allis = true
	if not has_allis and not has_axis:
		quit_close_combat()
	
	var participants_duplicate: Array[Participant] = participants.duplicate()
	for participant in participants_duplicate:
		if not participants.has(participant):
			continue
		if participant.unit == null:
			participants.erase(participant)
			continue
		if participant.unit.surrendered:
			units_by_team[participant.team].erase(participant.unit)
			participants.erase(participant)
			if units_by_team[Globals.Team.AXIS].is_empty():
				quit_close_combat()
				return
			if units_by_team[Globals.Team.ALLIES].is_empty():
				quit_close_combat()
				return
			continue
		participant.defense_preparedness = participant.unit.close_combat_defense_preparedness
		for soldier in participant.unit.squad_fire.soldiers:
			soldier.cooldown_remaining -= 0.1
			if soldier.cooldown_remaining <= 0.0:
				soldier.cooldown_remaining = get_soldier_colldown_time(soldier, participant.unit.stress_system.state)
				var enemy_soldiers: Array
				if participant.team == Globals.Team.AXIS:
					enemy_soldiers = soldiers_by_team[Globals.Team.ALLIES].duplicate()
				else:
					enemy_soldiers = soldiers_by_team[Globals.Team.AXIS].duplicate()
				enemy_soldiers.shuffle()
				
				if enemy_soldiers.is_empty():
					quit_close_combat()
					return
				var enemy_soldier: Soldier = enemy_soldiers.pop_back()
				var casualty_chance: float
				if participant.side_role == SideRole.ATTACKER:
					casualty_chance = get_soldier_attack_strength(soldier) / (get_soldier_attack_strength(soldier) + get_soldier_defense_strength(enemy_soldier))
				if participant.side_role == SideRole.DEFENDER:
					casualty_chance = get_soldier_defense_strength(soldier) / (get_soldier_defense_strength(soldier) + get_soldier_attack_strength(enemy_soldier))
				var lethality_scale: float = 0.3
				casualty_chance *= lethality_scale
				var min_chance = 0.05
				var max_chance = 0.80
				if casualty_chance < min_chance or casualty_chance > max_chance:
					pass
				casualty_chance = clamp(casualty_chance, min_chance, max_chance)
				
				var roll: float = randf()
				if roll < casualty_chance:
					#continue
					soldiers_by_team[enemy_soldier.team].erase(enemy_soldier)
					if enemy_soldier.unit.apply_specific_casualty(enemy_soldier):
						for p in participants:
							if p == enemy_soldier.unit:
								participants.erase(p)
						#participants.erase(participant)
						units_by_team[enemy_soldier.team].erase(enemy_soldier.unit)
						enemy_soldier.unit._set_combat_ineffective()
						
						if units_by_team[Globals.Team.AXIS].is_empty():
							quit_close_combat()
						if units_by_team[Globals.Team.ALLIES].is_empty():
							quit_close_combat()
						break

func quit_close_combat():
	for p in participants:
		if is_instance_valid(p):
			p.unit.in_close_combat = false
	queue_free()

# TODO add rout button so unit can rout if pinned
# TODO soldiers should get simple system that leads them to use the weapon that is appropriate to the task
# TODO riflegrenade, HE and mortar are weird exceptions that need to be properly incorporated
# FIXME a unit that is not seen should be detected at some point when firing. or maybe not certain but the chance to be spotted should increase
# FIXME if a unit already shoots at the enemy but only with like an mg that has range. if the enemy comes closer for rifle fire then everybody shoots at once.
# FIXME units should not be queued free but rather deactivated. should fix nulls in Units Array
# FIXME unit state change to pinned is too likely, needs fix
# FIXME if unit enters close combat and receives casualties, the likelyhood that they break is very high and thus will surrender quite quickly. make this more sensible
