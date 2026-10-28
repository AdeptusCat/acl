extends Node
class_name CommandConnectivity

enum ContactState { CONNECTED, LIMITED, LOST }

const RELIABLE_LINK_STRENGTH: float = 0.75
const SIGHT_RANGE_HEXES: int = 3
const MAX_SIGHT_HINDRANCE: int = 1

var _los_to_leader: bool = false
var _voice_range_to_leader: bool = false
var _runner_chain_to_leader: bool = false
var _radio_link_to_leader: bool = false
var hq_relay_used: bool = false
var _relay_probe: CommandConnectivity

var _state_mod_dict: Dictionary[STATES.MoraleState, float] = {
		STATES.MoraleState.NORMAL : 1.0,
		STATES.MoraleState.CAUTIOUS : 0.8,
		STATES.MoraleState.PINNED : 0.35,
		STATES.MoraleState.PANIC : 0.0,
		STATES.MoraleState.COMBAT_INEFFECTIVE : 0.0,
	}
var _command_unit_state: STATES.MoraleState

var command_link_strength: float = 0.0
var leader_presence_strength: float = 0.0


static func needs_command_contact(unit: Unit) -> bool:
	if is_instance_valid(unit.command_squad):
		return true
	if unit.acting_command_level >= 0:
		return false
	if CommandSuccession.is_headquarters(unit) and unit.company_command != null and CommandSuccession.headquarters_leader(unit) == null:
		return true
	return unit.squad_type != Globals.SquadType.COMPANY_HEADQUARTERS and unit.squad_type != Globals.SquadType.PLATOON_HEADQUARTERS


static func has_available_commander(unit: Unit) -> bool:
	var commander: Unit = unit.command_squad
	if not is_instance_valid(commander) or commander == unit or commander.team != unit.team or not commander.is_active() or commander.surrendered:
		return false
	var formation: FormationCommand = commanding_formation(unit)
	return formation == null or formation.has_commander()


static func contact_state_for(unit: Unit) -> ContactState:
	if not needs_command_contact(unit):
		return ContactState.CONNECTED
	if not has_available_commander(unit) or not is_instance_valid(unit.command_connectivity):
		return ContactState.LOST
	var strength: float = unit.command_connectivity.command_link_strength
	if strength >= RELIABLE_LINK_STRENGTH:
		return ContactState.CONNECTED
	if strength > 0.0:
		return ContactState.LIMITED
	return ContactState.LOST


static func contact_text(state: ContactState) -> String:
	match state:
		ContactState.CONNECTED:
			return "Connected"
		ContactState.LIMITED:
			return "Limited"
	return "No contact"


static func contact_method_for(unit: Unit) -> String:
	if not needs_command_contact(unit):
		return "Top-level HQ"
	if not has_available_commander(unit):
		return "HQ unavailable"
	var link: CommandConnectivity = unit.command_connectivity
	if not is_instance_valid(link) or link.command_link_strength <= 0.0:
		return "No contact"
	if link.hq_relay_used:
		return "Via HQ remnant"
	if link.radio_link_to_leader:
		return "Radio"
	if link.los_to_leader and link.voice_range_to_leader:
		return "Voice + sight"
	if link.los_to_leader:
		return "Sight"
	if link.runner_chain_to_leader:
		return "Runner"
	if link.voice_range_to_leader:
		return "Voice"
	return "No contact"


var command_unit_state: STATES.MoraleState:
	set(value):
		if _command_unit_state == value:
			return
		_command_unit_state = value
		update_command_link_strength()
		compute_morale_link_strength()
	get:
		return _command_unit_state

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
	elif _los_to_leader and _voice_range_to_leader:
		strength = 0.9
	elif _los_to_leader:
		strength = 0.8
	elif _runner_chain_to_leader:
		strength = 0.6
	elif _voice_range_to_leader:
		strength = 0.4
	
	var _state_mod: float = _state_mod_dict[_command_unit_state]
	command_link_strength = strength * _state_mod


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
	
	var _state_mod_cmd: float = _state_mod_dict[_command_unit_state]
	var command_strength: float = best * _state_mod_cmd
	
	leader_presence_strength = command_strength


func clear_connectivity() -> void:
	hq_relay_used = false
	los_to_leader = false
	voice_range_to_leader = false
	runner_chain_to_leader = false
	radio_link_to_leader = false
	command_unit_state = STATES.MoraleState.COMBAT_INEFFECTIVE


func compute_connectivity(unit: Unit, command_squad: Unit) -> void:
	hq_relay_used = false
	var formation: FormationCommand = commanding_formation(unit)
	if formation != null and not formation.has_commander():
		clear_connectivity()
		return
	compute_direct_connectivity(unit, command_squad)
	if formation == null:
		return
	if formation.has_support() and unit != formation.headquarters:
		if not is_instance_valid(_relay_probe):
			_relay_probe = CommandConnectivity.new()
			add_child(_relay_probe)
		_relay_probe.compute_direct_connectivity(unit, formation.headquarters)
		var relay_strength: float = minf(_relay_probe.command_link_strength, formation.support_link.command_link_strength)
		if relay_strength > command_link_strength:
			command_link_strength = relay_strength
			hq_relay_used = true
	command_link_strength *= formation.efficiency()
	leader_presence_strength *= formation.efficiency()


static func commanding_formation(unit: Unit) -> FormationCommand:
	for formation: FormationCommand in [unit.platoon_command, unit.company_command]:
		if formation != null and formation.commander == unit.command_squad:
			return formation
	return null


func compute_direct_connectivity(unit: Unit, command_squad: Unit) -> void:
	if LOSHelper.ground_layer == null:
		clear_connectivity()
		return
	if not is_instance_valid(command_squad) or not command_squad.is_active() or command_squad.surrendered or command_squad == unit or command_squad.team != unit.team:
		clear_connectivity()
		return
	if is_instance_valid(command_squad):
		command_unit_state = command_squad.stress_system.state
		var distance: int = LOSHelper.ground_layer.cube_distance(unit.current_cube, command_squad.current_cube)
		
		var unit_visible_hexes: Dictionary = LOSHelper.los_lookup.get(unit.current_hex, {})
		# The baked lookup omits blocked paths and the origin hex itself.
		if distance == 0:
			los_to_leader = true
		elif distance <= SIGHT_RANGE_HEXES and unit_visible_hexes.has(command_squad.current_hex):
			var sight_line: Dictionary = unit_visible_hexes[command_squad.current_hex]
			var hindrance: int = int(sight_line.get("hindrance", 0))
			los_to_leader = hindrance <= MAX_SIGHT_HINDRANCE
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

	update_command_link_strength()
	compute_morale_link_strength()
