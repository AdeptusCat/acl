extends Node

var _los_to_leader: bool = false
var _voice_range_to_leader: bool = false
var _runner_chain_to_leader: bool = false
var _radio_link_to_leader: bool = false

var command_link_strength: float = 0.0

var los_to_leader: bool:
	set(value):
		if _los_to_leader == value:
			return
		_los_to_leader = value
		update_command_link_strength()
	get:
		return _los_to_leader

var voice_range_to_leader: bool:
	set(value):
		if _voice_range_to_leader == value:
			return
		_voice_range_to_leader = value
		update_command_link_strength()
	get:
		return _voice_range_to_leader

var runner_chain_to_leader: bool:
	set(value):
		if _runner_chain_to_leader == value:
			return
		_runner_chain_to_leader = value
		update_command_link_strength()
	get:
		return _runner_chain_to_leader

var radio_link_to_leader: bool:
	set(value):
		if _radio_link_to_leader == value:
			return
		_radio_link_to_leader = value
		update_command_link_strength()
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
