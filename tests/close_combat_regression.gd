extends Node

# Run with: godot --headless --path . tests/close_combat_regression.tscn
const COMBAT_HEX: Vector2i = Vector2i(11, 10)

var failures: int = 0
var main: Node
var controller: Node
var fixture_units: Array[Unit] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_history: CasualtyHistory = Globals.casualty_history
	Globals.casualty_history = CasualtyHistory.new()
	Globals.casualty_history.storage_path = "user://tests/close_combat/casualties.tres"
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	controller = world.game_controller
	_freeze_simulation(main)
	Debug.no_damage = false
	_test_admission_and_surrender()
	await _clear_fixtures()
	_test_external_casualties()
	await _clear_fixtures()
	_test_roster_replacement_and_missing_notifications()
	await _clear_fixtures()
	_test_surrender_during_casualty_callback()
	await _clear_fixtures()
	_test_elimination_during_tick()
	await _clear_fixtures()
	_test_last_side_and_same_frame_reentry()
	await _clear_fixtures()
	_test_movement_lock()
	await _clear_fixtures()
	await _test_path_interception()
	_test_rout_lock()
	await _clear_fixtures()
	await _test_movement_and_freeing()
	await _clear_fixtures()
	_test_empty_combat()
	await _clear_fixtures()
	_test_scene_exit()
	await _clear_fixtures()
	await _test_live_timer()
	await _clear_fixtures()
	await get_tree().process_frame
	var saved_history: CasualtyHistory = CasualtyHistory.load_history(Globals.casualty_history.storage_path)
	_check(saved_history.records.size() == Globals.casualty_history.records.size() and not saved_history.records.is_empty(), "Close-combat cleanup preserves the durable casualty archive")
	main._on_try_again()
	await get_tree().create_timer(0.2).timeout
	_check(Globals.get_units().is_empty(), "Restart clears surviving units and corpses")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Globals.casualty_history = original_history
	print("Close combat regression failures: ", failures)
	get_tree().quit(failures)


func _test_admission_and_surrender() -> void:
	var axis: Unit = _create_unit(Globals.Team.AXIS, 2)
	var reserve: Unit = _create_unit(Globals.Team.AXIS, 2)
	var allies: Unit = _create_unit(Globals.Team.ALLIES, 2)
	var prisoner: Unit = _create_unit(Globals.Team.AXIS, 2)
	prisoner.surrender()
	var empty: Unit = _create_unit(Globals.Team.ALLIES, 0)
	var combat: CloseCombatInstance = _discover_combat()
	_check(combat != null, "Opposing live units start close combat")
	if combat == null:
		return
	_check_removed(combat, prisoner, "Already surrendered unit is not admitted")
	_check_removed(combat, empty, "Empty roster is not admitted")
	var surrendering_soldiers: Array[Soldier] = axis.squad_fire.soldiers.duplicate()
	var records_before: int = Globals.casualty_history.records.size()
	axis.surrender()
	_check_removed(combat, axis, "Surrender immediately removes unit, participant and targets")
	_check(combat.ongoing and reserve.in_close_combat and allies.in_close_combat, "Other units continue fighting after a surrender")
	# Rebuilding the hex and subsequent timer ticks must not re-admit prisoners.
	controller.set_close_combat_hexes_and_units()
	combat._on_timer_timeout()
	_check_removed(combat, axis, "Hex reconciliation cannot re-admit surrendered soldiers")
	_check(axis.members_alive == 2 and axis.squad_fire.soldiers == surrendering_soldiers, "Surrender preserves living soldiers and their equipment")
	_check(Globals.casualty_history.records.size() == records_before, "Surrender is not recorded as a death")


func _test_external_casualties() -> void:
	var axis: Unit = _create_unit(Globals.Team.AXIS, 3)
	var reserve: Unit = _create_unit(Globals.Team.AXIS, 2)
	_create_unit(Globals.Team.ALLIES, 2)
	var combat: CloseCombatInstance = _discover_combat()
	var casualty: Soldier = axis.squad_fire.soldiers.back()
	axis._on_incoming_fire_effect(1, 0.0, 0.0, null)
	var ranged_casualty: Soldier = axis.squad_fire.casualties.back()
	_check(not combat.soldiers_by_team[axis.team].has(ranged_casualty), "Ranged casualties immediately leave close-combat targets")
	_check(axis.casualty_records.size() == 1, "Ranged casualty retains an equipment record")
	# Specific close-combat casualties and ranged fire use the same live roster.
	if axis.squad_fire.soldiers.has(casualty):
		axis.apply_specific_casualty(casualty)
	else:
		casualty = axis.squad_fire.soldiers.back()
		axis.apply_specific_casualty(casualty)
	combat._on_timer_timeout()
	_check(not combat.soldiers_by_team[axis.team].has(casualty), "Specific casualties leave cached targets")
	axis.die()
	_check_removed(combat, axis, "Direct death immediately removes all combat references")
	_check(combat.ongoing and reserve.in_close_combat, "Death of one squad does not end a reinforced side")
	_check(is_instance_valid(axis) and axis.squad_fire.casualties.size() == 3 and axis.casualty_records.size() == 3, "Death cleanup preserves the corpse and all casualty equipment records")
	var record: CasualtyRecord = axis.casualty_records[0]
	_check(record.equipment != null and not record.equipment.weapon_name.is_empty(), "Close-combat removal retains historical equipment")


func _test_roster_replacement_and_missing_notifications() -> void:
	var axis: Unit = _create_unit(Globals.Team.AXIS, 2)
	var reserve: Unit = _create_unit(Globals.Team.AXIS, 2)
	_create_unit(Globals.Team.ALLIES, 2)
	var combat: CloseCombatInstance = _discover_combat()
	var replaced_soldiers: Array[Soldier] = axis.squad_fire.soldiers.duplicate()
	axis._setup_runtime_soldiers(axis.squad_loadout)
	for soldier: Soldier in axis.squad_fire.soldiers:
		soldier.cooldown_remaining = 100.0
	combat._on_timer_timeout()
	for soldier: Soldier in replaced_soldiers:
		_check(not combat.soldiers_by_team[axis.team].has(soldier), "Roster replacement removes old soldier references before attacks")
	for soldier: Soldier in axis.squad_fire.soldiers:
		_check(combat.soldiers_by_team[axis.team].has(soldier), "Roster replacement includes the new runtime soldiers")
	axis.surrendered = true
	combat._on_timer_timeout()
	_check_removed(combat, axis, "Timer reconciles surrender without a notification")
	# Also cover a freed reference when the normal tree-exit notification is absent.
	reserve.set_block_signals(true)
	reserve.free()
	combat._on_timer_timeout()
	_check(not combat.ongoing and combat.participants.is_empty(), "A freed participant cannot survive reconciliation")


func _test_surrender_during_casualty_callback() -> void:
	var axis: Unit = _create_unit(Globals.Team.AXIS, 2)
	var allies: Unit = _create_unit(Globals.Team.ALLIES, 2)
	var combat: CloseCombatInstance = _discover_combat()
	allies.soldiers_changed.connect(axis.surrender)
	var records_before: int = Globals.casualty_history.records.size()
	seed(73)
	for tick: int in range(100):
		if axis.surrendered:
			break
		for soldier: Soldier in axis.squad_fire.soldiers:
			soldier.cooldown_remaining = 0.0
		for soldier: Soldier in allies.squad_fire.soldiers:
			soldier.cooldown_remaining = 100.0
		combat._on_timer_timeout()
	_check(axis.surrendered and not combat.ongoing, "Surrender from a casualty callback safely ends the current tick")
	_check(axis.members_alive == 2 and allies.members_alive == 1, "Removed actors and ended combat cannot inflict further casualties")
	_check(Globals.casualty_history.records.size() == records_before + 1, "Reentrant cleanup records only the completed casualty")


func _test_elimination_during_tick() -> void:
	var axis: Unit = _create_unit(Globals.Team.AXIS, 1)
	var allies: Unit = _create_unit(Globals.Team.ALLIES, 1)
	var reserve: Unit = _create_unit(Globals.Team.ALLIES, 3)
	var combat: CloseCombatInstance = _discover_combat()
	seed(17)
	for tick: int in range(100):
		if not allies.alive or not reserve.alive or not combat.ongoing:
			break
		axis.squad_fire.soldiers[0].cooldown_remaining = 0.0
		for defender: Unit in [allies, reserve]:
			for soldier: Soldier in defender.squad_fire.soldiers:
				soldier.cooldown_remaining = 100.0
		combat._on_timer_timeout()
	var eliminated: Unit = allies
	var survivor: Unit = reserve
	if reserve.alive == false:
		eliminated = reserve
		survivor = allies
	_check(not eliminated.alive, "Seeded close-combat ticks eliminate a squad")
	_check_removed(combat, eliminated, "Elimination during a tick removes the participant record")
	_check(combat.ongoing and survivor.in_close_combat, "Remaining defenders stay in combat")
	_check(not eliminated.casualty_records.is_empty(), "Close-combat kills retain casualty history")
	for target: Soldier in combat.soldiers_by_team[Globals.Team.ALLIES]:
		_check(target.is_alive and target.unit.alive and target.unit.squad_fire.soldiers.has(target), "Every remaining target belongs to a living runtime roster")


func _test_last_side_and_same_frame_reentry() -> void:
	var axis: Unit = _create_unit(Globals.Team.AXIS, 1)
	var allies: Unit = _create_unit(Globals.Team.ALLIES, 1)
	var old_combat: CloseCombatInstance = _discover_combat()
	allies.surrender()
	_check(not old_combat.ongoing and old_combat.is_queued_for_deletion(), "Last opposing surrender ends combat immediately")
	_check(not axis.in_close_combat and not allies.in_close_combat, "Combat end releases both sides")
	_check(old_combat.get_node("Timer").is_stopped() and not old_combat.visible, "Ended combat stops its timer and hides its marker")
	var reinforcement: Unit = _create_unit(Globals.Team.ALLIES, 1)
	var new_combat: CloseCombatInstance = _discover_combat()
	_check(new_combat != old_combat and new_combat != null, "Same-frame reinforcement creates a fresh combat instance")
	_check(axis.in_close_combat and reinforcement.in_close_combat, "New combat owns surviving units' flags")
	old_combat._on_timer_timeout()
	_check(axis.in_close_combat and reinforcement.in_close_combat, "Ended instance cannot clear new combat flags or resume attacks")
	# The final opposing casualty must end immediately inside the timer callback.
	seed(23)
	for tick: int in range(100):
		if not reinforcement.alive:
			break
		axis.squad_fire.soldiers[0].cooldown_remaining = 0.0
		reinforcement.squad_fire.soldiers[0].cooldown_remaining = 100.0
		new_combat._on_timer_timeout()
	_check(not reinforcement.alive and not new_combat.ongoing, "Final close-combat casualty ends the encounter")
	_check(not axis.in_close_combat and not reinforcement.in_close_combat, "Final elimination releases all combat flags")
	var late_joiner: Unit = _create_unit(Globals.Team.ALLIES, 1)
	new_combat.add_unit(late_joiner)
	_check(not late_joiner.in_close_combat and new_combat.participants.is_empty(), "Ended combat rejects new participants")
	var records_before: int = Globals.casualty_history.records.size()
	new_combat._on_timer_timeout()
	_check(Globals.casualty_history.records.size() == records_before, "Repeated ended-combat ticks cannot create casualties")


func _test_movement_lock() -> void:
	var axis: Unit = _create_unit(Globals.Team.AXIS, 2)
	var destination: Vector2i = COMBAT_HEX + Vector2i(1, 0)
	var path: Array[Vector3i] = [LOSHelper.ground_layer.map_to_cube(COMBAT_HEX), LOSHelper.ground_layer.map_to_cube(destination)]
	var exposed: Array[Vector3i] = [LOSHelper.ground_layer.map_to_cube(destination + Vector2i(1, 0))]
	axis.give_attack_hex_order(destination + Vector2i(1, 0), path, exposed)
	var allies: Unit = _create_unit(Globals.Team.ALLIES, 2)
	var combat: CloseCombatInstance = _discover_combat()
	_check(not axis.movement.is_moving and not axis.is_moving, "Admission immediately stops both movement flags")
	_check(axis.movement.path_hexes.is_empty() and axis.movement.exposed_path_hexes.is_empty(), "Admission cancels the old movement and exposed assault segment")
	_check(axis.action_controller.action_state == SquadActionController.SquadActionState.NO_ORDER, "Admission clears the previous action")
	for unit: Unit in [axis, allies]:
		var position_before: Vector2 = unit.position
		var order_before: int = unit.action_controller.action_order_id
		unit.give_defend_area_order(destination, path)
		unit.give_move_to_hex_order(destination, path, false)
		unit.give_attack_hex_order(destination, path, exposed)
		unit.give_withdraw_to_hex_order(destination, path)
		unit.order(Globals.UnitCmd.MOVE, destination)
		_check(unit.action_controller.action_order_id == order_before, "Close combat rejects AI and direct movement orders without replacing action ownership")
		var advice: PositionResult = PositionResult.new()
		advice.unit = unit
		advice.status = PositionResult.Status.ACCEPTED
		advice.target_index = 0
		advice.target_hex = destination
		advice.should_move = true
		advice.path = [COMBAT_HEX, destination]
		var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()
		_check(not PositionQueryService.can_follow_intent(unit) and not executor.execute(advice), "Close combat rejects previously computed position advice")
		unit.movement.move_to_hex(destination)
		unit.movement.follow_cube_path(path)
		unit.movement.set_attack_paths(path, exposed)
		unit.movement.start_covered_phase()
		unit.movement.stop()
		unit.movement._process(100.0)
		_check(unit.current_hex == COMBAT_HEX and unit.position == position_before, "Direct movement and assault phases cannot move a combat participant")
		_check(not unit.movement.is_moving and not unit.is_moving and unit.movement.path_hexes.is_empty() and not unit.movement.attack_in_progress, "Rejected movement leaves no queued path or assault")
		_check(combat.units_by_team[unit.team].has(unit) and unit.in_close_combat, "Rejected movement keeps the unit in its encounter")
	allies.surrender()
	_check(not axis.in_close_combat, "Ending the encounter releases movement eligibility")
	axis.movement._process(100.0)
	_check(axis.current_hex == COMBAT_HEX, "Combat end cannot resume a canceled movement order")
	axis.give_defend_area_order(destination, path)
	axis.movement._process(100.0)
	_check(axis.current_hex == destination, "A fresh movement order works after close combat ends")


func _test_path_interception() -> void:
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		var holder: Unit = _create_unit(Globals.get_enemy_team(team), 2)
		var mover: Unit = _create_unit(team, 2)
		var start: Vector2i = COMBAT_HEX + Vector2i(-1, 0)
		var destination: Vector2i = COMBAT_HEX + Vector2i(1, 0)
		mover.current_hex = start
		mover.current_cube = LOSHelper.ground_layer.map_to_cube(start)
		mover.position = LOSHelper.ground_layer.map_to_local(start)
		var arrivals: Array[Vector2i] = []
		mover.unit_arrived_at_hex.connect(func(cell: Vector2i) -> void: arrivals.append(cell))
		var path: Array[Vector3i] = [LOSHelper.ground_layer.map_to_cube(start), LOSHelper.ground_layer.map_to_cube(COMBAT_HEX), LOSHelper.ground_layer.map_to_cube(destination)]
		mover.give_defend_area_order(destination, path)
		var step_seconds: float = 100.0
		if team == Globals.Team.ALLIES:
			step_seconds = 0.75 * mover.position.distance_to(mover.movement.target_position) / (mover.movement.move_speed * mover.movement.terrain_mult)
		mover.movement._process(step_seconds)
		var entry_position: Vector2 = mover.position
		var combat: CloseCombatInstance = _discover_combat()
		_check(combat != null and mover.in_close_combat, "A moving squad enters combat at an intercepted waypoint")
		_check(mover.current_hex == COMBAT_HEX and not mover.movement.is_moving and not mover.is_moving, "Combat entry interrupts the current movement step immediately")
		_check(mover.movement.path_hexes.is_empty() and arrivals.is_empty(), "Intercepted movement discards subsequent waypoints without emitting destination arrival")
		mover.movement._process(100.0)
		_check(mover.position == entry_position, "Locked movement cannot recenter or continue after a partial hex-entry step")
		for participant: CloseCombatInstance.Participant in combat.participants:
			if participant.unit == mover:
				_check(participant.side_role == CloseCombatInstance.SideRole.ATTACKER, "Movement locking preserves the entering squad's attacker role")
		holder.surrender()
		mover.movement._process(100.0)
		_check(mover.current_hex == COMBAT_HEX and arrivals.is_empty(), "A canceled intercepted path stays canceled after resolution")
		await _clear_fixtures()


func _test_rout_lock() -> void:
	var axis: Unit = _create_unit(Globals.Team.AXIS, 2)
	var reserve: Unit = _create_unit(Globals.Team.AXIS, 2)
	var allies: Unit = _create_unit(Globals.Team.ALLIES, 2)
	var combat: CloseCombatInstance = _discover_combat()
	axis.action_controller._start_rout()
	_check(axis.surrendered and axis.current_hex == COMBAT_HEX and not axis.movement.is_moving, "Close combat cannot rout; the existing failed-rout rule resolves surrender")
	_check(combat.ongoing and reserve.in_close_combat and allies.in_close_combat, "Failed rout does not release the remaining combat participants")


func _test_movement_and_freeing() -> void:
	var axis: Unit = _create_unit(Globals.Team.AXIS, 2)
	var reserve: Unit = _create_unit(Globals.Team.AXIS, 2)
	var allies: Unit = _create_unit(Globals.Team.ALLIES, 2)
	var combat: CloseCombatInstance = _discover_combat()
	axis.movement._update_current_hex(COMBAT_HEX + Vector2i(1, 0))
	_check_removed(combat, axis, "Forced hex displacement removes soldiers immediately")
	_check(combat.ongoing and reserve.in_close_combat, "Remaining units continue after forced displacement")
	axis.movement._update_current_hex(COMBAT_HEX)
	controller.set_close_combat_hexes_and_units()
	_check(combat.units_by_team[axis.team].count(axis) == 1, "Returning unit joins exactly once")
	_check(combat.soldiers_by_team[axis.team].count(axis.squad_fire.soldiers[0]) == 1, "Returning soldier is not duplicated")
	allies.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not is_instance_valid(combat) and not axis.in_close_combat and not reserve.in_close_combat, "Freeing the last enemy safely ends combat")


func _test_empty_combat() -> void:
	var combat: CloseCombatInstance = controller.close_combat_instance_scene.instantiate()
	controller.close_combat_instances.add_child(combat)
	combat.get_node("Timer").stop()
	combat._on_timer_timeout()
	_check(not combat.ongoing and combat.is_queued_for_deletion(), "Empty combat exits before resolving attacks")


func _test_scene_exit() -> void:
	var axis: Unit = _create_unit(Globals.Team.AXIS, 2)
	var allies: Unit = _create_unit(Globals.Team.ALLIES, 2)
	var combat: CloseCombatInstance = _discover_combat()
	combat.free()
	_check(not axis.in_close_combat and not allies.in_close_combat, "Freeing a combat instance releases surviving participants")


func _test_live_timer() -> void:
	var axis: Unit = _create_unit(Globals.Team.AXIS, 2)
	var allies: Unit = _create_unit(Globals.Team.ALLIES, 2)
	var combat: CloseCombatInstance = _discover_combat()
	var timer: Timer = combat.get_node("Timer") as Timer
	timer.start()
	await timer.timeout
	var remaining_cooldown: float = axis.squad_fire.soldiers[0].cooldown_remaining
	_check(remaining_cooldown < 100.0 and combat.ongoing, "The scene's real timer advances an active encounter")
	allies.surrender()
	await get_tree().create_timer(0.15).timeout
	_check(not is_instance_valid(combat) and not axis.in_close_combat, "Live timer encounter is freed after the last enemy surrenders")
	_check(axis.squad_fire.soldiers[0].cooldown_remaining == remaining_cooldown, "A stopped encounter cannot advance its fighters again")


func _create_unit(team: Globals.Team, size: int) -> Unit:
	var unit: Unit = controller.unit_scene.instantiate()
	unit.team = team
	unit.ground_map = LOSHelper.ground_layer
	unit.current_hex = COMBAT_HEX
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(COMBAT_HEX)
	unit.position = LOSHelper.ground_layer.map_to_local(COMBAT_HEX)
	controller.unit_container.add_child(unit)
	var loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	var rifle: WeaponSpec = load("res://resources/weapons/m1_garand.tres")
	for index: int in range(size):
		var soldier: SoldierLoadout = SoldierLoadout.new()
		soldier.nickname = "Close combat fixture %d" % index
		soldier.weapon = rifle
		loadout.soldiers.append(soldier)
	unit.squad_loadout = loadout
	unit.setup()
	unit.add_to_group("units")
	_freeze_simulation(unit)
	unit.unit_entered_hex.connect(controller._on_unit_entered_hex)
	fixture_units.append(unit)
	return unit


func _discover_combat() -> CloseCombatInstance:
	controller.set_close_combat_hexes_and_units()
	for combat: CloseCombatInstance in controller.close_combat_instances.get_children():
		if combat.hex == COMBAT_HEX and combat.ongoing and not combat.is_queued_for_deletion():
			combat.get_node("Timer").stop()
			for unit: Unit in fixture_units:
				if is_instance_valid(unit):
					for soldier: Soldier in unit.squad_fire.soldiers:
						soldier.cooldown_remaining = 100.0
			return combat
	return null


func _check_removed(combat: CloseCombatInstance, unit: Unit, label: String) -> void:
	var retained: bool = combat.units_by_team[unit.team].has(unit) or unit.in_close_combat
	for participant: CloseCombatInstance.Participant in combat.participants:
		if participant.unit == unit:
			retained = true
	for soldier: Soldier in combat.soldiers_by_team[unit.team]:
		if soldier.unit == unit:
			retained = true
	_check(not retained, label)


func _clear_fixtures() -> void:
	for combat: CloseCombatInstance in controller.close_combat_instances.get_children():
		combat.queue_free()
	for unit: Unit in fixture_units:
		if is_instance_valid(unit):
			unit.queue_free()
	fixture_units.clear()
	await get_tree().process_frame
	await get_tree().process_frame


func _freeze_simulation(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		var timer: Timer = node as Timer
		timer.stop()
	for child: Node in node.get_children():
		_freeze_simulation(child)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
