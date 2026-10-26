extends Node2D
class_name CloseCombatInstance

const FEEDBACK: Script = preload("res://scenes/game/effects/close_combat_feedback.gd")
const TICK_SECONDS: float = 0.1
const OPENING_SECONDS: float = 1.0
const LETHALITY_SCALE: float = 0.18

var _feedback: FEEDBACK


func _ready() -> void:
	_sync_feedback()


func _sync_feedback() -> void:
	if not is_inside_tree() or not ongoing:
		return
	if not is_instance_valid(_feedback):
		if participants.is_empty():
			return
		_feedback = FEEDBACK.new()
		_feedback.hex = hex
		var host: Node = get_tree().current_scene
		if get_parent() != null and get_parent().get_parent() != null:
			var markers: Node = get_parent().get_parent().get_node_or_null("CloseCombatLocations")
			if markers != null:
				host = markers
		for child: Node in host.get_children():
			if child.get_script() != FEEDBACK:
				continue
			var previous: FEEDBACK = child as FEEDBACK
			if previous.hex == hex and previous.resolved:
				previous.hide()
				previous.queue_free()
		host.add_child(_feedback)
		_feedback.global_position = global_position
		var ground: HexagonTileMapLayer = LOSHelper.ground_layer
		if is_instance_valid(ground) and ground.geometry_tile_shape != null and ground.geometry_tile_shape.shape is ConvexPolygonShape2D:
			var shape: ConvexPolygonShape2D = ground.geometry_tile_shape.shape as ConvexPolygonShape2D
			var corners: PackedVector2Array = PackedVector2Array()
			for corner: Vector2 in shape.points:
				corners.append(ground.global_transform.basis_xform(corner))
			_feedback.outline = corners
	_feedback.set_opening_contact(elapsed < OPENING_SECONDS)
	for team: Globals.Team in units_by_team:
		var living: int = 0
		var unknown: bool = false
		var attacking: bool = false
		var defending: bool = false
		for participant: Participant in participants:
			if not participant.active or participant.team != team or not is_instance_valid(participant.unit):
				continue
			var unit: Unit = participant.unit
			if team != Globals.team_player and not Debug.show_enemies and not Debug.hide_fog_of_war and not unit.is_visible_in_tree():
				unknown = true
			for soldier: Soldier in unit.squad_fire.soldiers:
				if soldier.is_alive:
					living += 1
			attacking = attacking or participant.side_role == SideRole.ATTACKER
			defending = defending or participant.side_role == SideRole.DEFENDER
		var role: String = "ENGAGED"
		if attacking and not defending:
			role = "ATTACKING"
		elif defending and not attacking:
			role = "DEFENDING"
		if unknown:
			living = -1
			role = "ENGAGED"
		_feedback.set_force(team, living, role)

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



func setup_close_combat() -> void:
	terrain_defense_value = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(hex))
	


func can_unit_participate(unit: Unit) -> bool:
	if not is_instance_valid(unit) or unit.is_queued_for_deletion():
		return false
	if not unit.is_active() or unit.surrendered or unit.current_hex != hex:
		return false
	if not is_instance_valid(unit.squad_fire):
		return false
	for soldier: Soldier in unit.squad_fire.soldiers:
		if soldier.is_alive:
			return true
	return false


func add_unit(unit: Unit) -> void:
	if not ongoing or is_queued_for_deletion() or not can_unit_participate(unit):
		return
	if units_by_team[unit.team].has(unit):
		return
	var participant: Participant = Participant.new(unit)
	participant.team = unit.team
	if unit.is_moving: 
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
	for soldier: Soldier in participant.unit.squad_fire.soldiers:
		if not soldier.is_alive:
			continue
		soldier.cooldown_remaining = get_soldier_colldown_time(soldier, participant.unit.stress_system.state)
		soldiers_by_team[participant.team].append(soldier)
	units_by_team[unit.team].append(unit)
	unit.in_close_combat = true
	participants.append(participant)
	unit.unit_died.connect(remove_unit)
	unit.unit_exited.connect(remove_unit)
	unit.unit_surrendered.connect(remove_unit)
	unit.unit_entered_hex.connect(_on_unit_entered_hex)
	unit.soldiers_changed.connect(refresh_participants)
	unit.tree_exiting.connect(remove_unit.bind(unit))
	# Entry roles were captured before canceling the action that brought the unit here.
	if unit.action_controller != null and unit.action_controller.movement != null:
		unit.action_controller.clear_orders()
	elif unit.movement != null:
		unit.movement.stop()
	_sync_feedback()


func remove_unit(unit: Unit) -> void:
	for participant: Participant in participants.duplicate():
		if participant.unit == unit:
			_remove_participant(participant)
	refresh_participants()


func _on_unit_entered_hex(unit: Unit, hex_entered: Vector2i) -> void:
	if hex_entered != hex:
		remove_unit(unit)


func _disconnect_unit(unit: Unit) -> void:
	if unit.unit_died.is_connected(remove_unit):
		unit.unit_died.disconnect(remove_unit)
	if unit.unit_exited.is_connected(remove_unit):
		unit.unit_exited.disconnect(remove_unit)
	if unit.unit_surrendered.is_connected(remove_unit):
		unit.unit_surrendered.disconnect(remove_unit)
	if unit.unit_entered_hex.is_connected(_on_unit_entered_hex):
		unit.unit_entered_hex.disconnect(_on_unit_entered_hex)
	if unit.soldiers_changed.is_connected(refresh_participants):
		unit.soldiers_changed.disconnect(refresh_participants)
	var on_exit: Callable = remove_unit.bind(unit)
	if unit.tree_exiting.is_connected(on_exit):
		unit.tree_exiting.disconnect(on_exit)


func _remove_participant(participant: Participant) -> void:
	participant.active = false
	units_by_team[participant.team].erase(participant.unit)
	if is_instance_valid(participant.unit):
		_disconnect_unit(participant.unit)
		participant.unit.in_close_combat = false
		if participant.unit.movement != null:
			participant.unit.movement.resume_centering()
	participants.erase(participant)
	participant.unit = null


func refresh_participants() -> void:
	if not ongoing:
		return
	# Ranged fire and roster replacement can change soldiers outside this timer.
	for participant: Participant in participants.duplicate():
		if not is_instance_valid(participant.unit) or not can_unit_participate(participant.unit):
			_remove_participant(participant)
	for team: Globals.Team in soldiers_by_team:
		soldiers_by_team[team].clear()
	for participant: Participant in participants:
		for soldier: Soldier in participant.unit.squad_fire.soldiers:
			if soldier.is_alive:
				soldiers_by_team[participant.team].append(soldier)
	_sync_feedback()
	if soldiers_by_team[Globals.Team.AXIS].is_empty() or soldiers_by_team[Globals.Team.ALLIES].is_empty():
		quit_close_combat()


#func test():
	#get_close_morale_attack_mult(attackers[0].unit.stress_system.state)
	#get_close_morale_defense_mult(defenders[0].unit.stress_system.state)
	#
	#var terrain_defence_bonus: int = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(defenders[0].unit.current_hex))
	#get_close_location_mods(terrain_defence_bonus, defenders[0].is_defender)


func get_soldier_colldown_time(soldier: Soldier, state: UnitStates.MoraleState) -> float:
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
	refresh_participants()
	if not ongoing:
		return
	# Contact gives the player time to read the encounter before melee losses.
	# Reinforcements join the existing timeline rather than restarting this phase.
	var opening_contact: bool = elapsed < OPENING_SECONDS
	elapsed = snappedf(elapsed + TICK_SECONDS, TICK_SECONDS)
	for participant: Participant in participants:
		participant.time_in_instance += TICK_SECONDS
	if is_instance_valid(_feedback):
		_feedback.set_opening_contact(elapsed < OPENING_SECONDS)
	if opening_contact:
		return

	var participants_duplicate: Array[Participant] = participants.duplicate()
	for participant: Participant in participants_duplicate:
		if not participant.active:
			continue
		participant.defense_preparedness = participant.unit.close_combat_defense_preparedness
		# Casualty signals can remove either participant while this loop is running.
		var fighters: Array[Soldier] = participant.unit.squad_fire.soldiers.duplicate()
		for soldier: Soldier in fighters:
			if not ongoing:
				return
			if not participant.active:
				break
			if not soldier.is_alive or not participant.unit.squad_fire.soldiers.has(soldier):
				continue
			soldier.cooldown_remaining -= TICK_SECONDS
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
				casualty_chance *= LETHALITY_SCALE
				var min_chance: float = 0.05
				var max_chance: float = 0.80
				if casualty_chance < min_chance or casualty_chance > max_chance:
					pass
				casualty_chance = clamp(casualty_chance, min_chance, max_chance)
				
				var roll: float = randf()
				if roll < casualty_chance:
					#continue
					var victim_team: Globals.Team = enemy_soldier.unit.team
					var eliminated: bool = enemy_soldier.unit.apply_specific_casualty(enemy_soldier)
					if is_instance_valid(_feedback):
						_feedback.record_exchange(participant.team, victim_team, not enemy_soldier.is_alive)
					if eliminated:
						enemy_soldier.unit._set_combat_ineffective()
					refresh_participants()
					if not ongoing:
						return
				elif is_instance_valid(_feedback):
					_feedback.record_exchange(participant.team, enemy_soldier.unit.team, false)


func _clear_participants() -> void:
	for participant: Participant in participants.duplicate():
		_remove_participant(participant)
	for team: Globals.Team in soldiers_by_team:
		soldiers_by_team[team].clear()


func quit_close_combat() -> void:
	if not ongoing:
		return
	_sync_feedback()
	if is_instance_valid(_feedback):
		_feedback.finish()
		_feedback = null
	ongoing = false
	var timer: Timer = get_node_or_null("Timer") as Timer
	if timer != null:
		timer.stop()
	hide()
	_clear_participants()
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_feedback):
		_feedback.queue_free()
	ongoing = false
	_clear_participants()

# TODO add rout button so unit can rout if pinned
# TODO soldiers should get simple system that leads them to use the weapon that is appropriate to the task
# TODO riflegrenade, HE and mortar are weird exceptions that need to be properly incorporated
# FIXME a unit that is not seen should be detected at some point when firing. or maybe not certain but the chance to be spotted should increase
# FIXME if a unit already shoots at the enemy but only with like an mg that has range. if the enemy comes closer for rifle fire then everybody shoots at once.
# FIXME units should not be queued free but rather deactivated. should fix nulls in Units Array
# FIXME unit state change to pinned is too likely, needs fix
# FIXME if unit enters close combat and receives casualties, the likelyhood that they break is very high and thus will surrender quite quickly. make this more sensible
