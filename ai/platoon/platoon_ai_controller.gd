class_name PlatoonAiController
extends Node

var blackboard: PlatoonBlackboard = PlatoonBlackboard.new()

@export var tactical_tick_interval: float = 0.5
@export var squads: Array[Unit] = []

@export var objective_hex: Vector2i = Vector2i(8, 4)

var tactical_tick_timer: float = 0.0


func _ready() -> void:
	for squad: Unit in squads:
		blackboard.register_friendly_squad(squad)
	
	set_attack_objective(objective_hex)
	print("--- Platoon blackboard test started ---")
	print("Objective hex: ", objective_hex)


func setup(p_units: Array[Unit]) -> void:
	squads = p_units
	blackboard.clear_friendly_squads()

	for squad: Unit in squads:
		blackboard.register_friendly_squad(squad)


func set_attack_objective(p_objective_hex: Vector2i) -> void:
	blackboard.reset_for_mission(
		PlatoonTypes.MissionType.ATTACK_OBJECTIVE,
		p_objective_hex
	)


func _physics_process(delta: float) -> void:
	tactical_tick_timer += delta

	if tactical_tick_timer < tactical_tick_interval:
		return

	var tick_delta: float = tactical_tick_timer
	tactical_tick_timer = 0.0

	_tactical_tick(tick_delta)
	
	_print_blackboard_state()
	
	
	
	#if Globals.get_units().size() > 0:
		##for unit in Globals.get_units():
			##print(unit.current_hex)
		#
		#blackboard.register_enemy_observation(
			#squads[0],
			#Globals.get_units()[1],
			#0.8,
			#0.7,
			#PlatoonTypes.TrackSource.LOS
		#)

func _print_blackboard_state() -> void:

	print("--- Blackboard State ----------------------------------------------------------------")
	print("Mission type: ", blackboard.mission_type)
	print("Current phase: ", blackboard.current_phase)
	print("Has objective: ", blackboard.has_objective)
	print("Objective hex: ", blackboard.objective_hex)

	print("Friendly squads: ", blackboard.friendly_squads.size())
	print("Squad states: ", blackboard.squad_states.size())

	print("Enemy tracks: ", blackboard.enemy_tracks.size())
	print("Suspected enemy zones: ", blackboard.suspected_enemy_zones.size())

	print("Objective enemy confidence: ", blackboard.objective_enemy_confidence)
	print("Objective clear confidence: ", blackboard.objective_clear_confidence)

	var should_recon: bool = blackboard.should_recon_objective()
	print("Should recon objective: ", should_recon)

	var probably_clear: bool = blackboard.is_objective_probably_clear()
	print("Objective probably clear: ", probably_clear)

	var can_assault: bool = blackboard.can_assault_objective()
	print("Can assault objective: ", can_assault)

	_print_squad_states()
	_print_suspected_zones()



func _print_squad_states() -> void:
	print("--- Squad States ---")

	for squad: Node in blackboard.friendly_squads:
		var state: SquadTacticalState = blackboard.get_squad_state(squad)

		if state == null:
			print("Missing state for squad: ", squad.name)
			continue

		print(
			state.squad.name,
			" hex=", state.hex,
			" E=", state.combat_effectiveness,
			" stress=", state.stress_effective,
			" cohesion=", state.cohesion,
			" morale=", state.morale_state,
			#" MG=", state.has_mg,
			#" leader=", state.has_leader,
			#" radio=", state.has_radio
		)


func _print_suspected_zones() -> void:
	print("--- Suspected Zones ---")

	for zone: SuspectedEnemyZone in blackboard.suspected_enemy_zones:
		print(
			"zone_id=", zone.zone_id,
			" hex=", zone.hex,
			" suspicion=", zone.suspicion,
			" danger=", zone.danger,
			" reason=", zone.reason
		)


func _tactical_tick(delta: float) -> void:
	_update_squad_snapshots()
	blackboard.ingest_unit_enemy_tracks(squads)
	blackboard.tactical_update(delta)

	# Next systems later:
	# PlatoonPhaseFsm.evaluate(blackboard)
	# PlatoonPhasePlanner.build_tasks(blackboard)
	# PlatoonUtilityAssigner.assign_roles(blackboard)
	# PlatoonOrderWriter.issue_orders(blackboard)


func _update_squad_snapshots() -> void:
	for squad: Unit in squads:
		if squad == null:
			continue

		var state: SquadTacticalState = _build_state_from_squad(squad)
		blackboard.update_squad_state(state)


func _build_state_from_squad(squad: Unit) -> SquadTacticalState:
	var state: SquadTacticalState = SquadTacticalState.new()

	var squad_hex: Vector2i = squad.current_hex
	var members_alive: int = squad.members_alive
	var original_size: int = squad.original_size
	var combat_effectiveness: float = squad.combat_stats.combat_effectiveness
	var stress_effective: float = squad.stress_system.S_eff
	var cohesion: float = squad.combat_stats.cohesion_current
	var morale_state: STATES.MoraleState = squad.stress_system.state

	#var has_mg: bool = squad.has_mg()
	#var has_leader: bool = squad.has_embedded_leader()
	#var has_radio: bool = squad.has_radio()

	state.configure(
		squad,
		squad_hex,
		members_alive,
		original_size,
		combat_effectiveness,
		stress_effective,
		cohesion,
		morale_state,
		#has_mg,
		#has_leader,
		#has_radio
	)
	
	return state
