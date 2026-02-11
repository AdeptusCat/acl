extends Node
class_name CommandConnectivity

var _los_to_leader: bool = false
var _voice_range_to_leader: bool = false
var _runner_chain_to_leader: bool = false
var _radio_link_to_leader: bool = false

var command_link_strength: float = 0.0
var leader_presence_strength: float = 0.0


var los_to_leader: bool:
	set(value):
		if _los_to_leader == value:
			return
		_los_to_leader = value
		update_command_link_strength()
		compute_morale_link_strength()
	get:
		return _los_to_leader

var voice_range_to_leader: bool:
	set(value):
		if _voice_range_to_leader == value:
			return
		_voice_range_to_leader = value
		update_command_link_strength()
		compute_morale_link_strength()
	get:
		return _voice_range_to_leader

var runner_chain_to_leader: bool:
	set(value):
		if _runner_chain_to_leader == value:
			return
		_runner_chain_to_leader = value
		update_command_link_strength()
		compute_morale_link_strength()
	get:
		return _runner_chain_to_leader

var radio_link_to_leader: bool:
	set(value):
		if _radio_link_to_leader == value:
			return
		_radio_link_to_leader = value
		update_command_link_strength()
		compute_morale_link_strength()
	get:
		return _radio_link_to_leader


func update_command_link_strength() -> void:
	var strength: float = 0.0

	if _radio_link_to_leader == true:
		strength = 1.0
	else:
		if _los_to_leader == true and _voice_range_to_leader == true:
			strength = 0.9
		else:
			if _runner_chain_to_leader == true:
				strength = 0.6
			else:
				if _voice_range_to_leader == true:
					strength = 0.4
				else:
					strength = 0.0

	command_link_strength = strength


func compute_morale_link_strength() -> void:
	var best: float = 0.0

	# Presence is strongest when the leader is physically near and perceivable.
	if _los_to_leader == true and _voice_range_to_leader == true:
		best = 1.0
	else:
		if _voice_range_to_leader == true:
			best = 0.7
		else:
			# LOS without voice still helps (seeing the leader rallying/gesturing).
			if _los_to_leader == true:
				best = 0.4
			else:
				# Runner and radio provide reassurance, but less than presence.
				if _radio_link_to_leader == true:
					best = 0.35
				else:
					if _runner_chain_to_leader == true:
						best = 0.25
					else:
						best = 0.0
	
	leader_presence_strength = best


func compute_connectivity(unit: Unit, command_squad: Unit):
	if is_instance_valid(command_squad):
		var distance: int = LOSHelper.ground_layer.cube_distance(unit.current_cube, command_squad.current_cube)
		
		var unit_visible_hexes: Dictionary = LOSHelper.los_lookup.get(unit.current_hex, [])
		if unit_visible_hexes.has(command_squad.current_hex) and distance <= 3:
			los_to_leader = true
		else:
			los_to_leader = false
		
		if distance <= 1:
			voice_range_to_leader = true
		else:
			voice_range_to_leader = false
		
		if distance <= 6:
			runner_chain_to_leader = true
		else:
			runner_chain_to_leader = false
