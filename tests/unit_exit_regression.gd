extends Node

const LOG_PATH: String = "user://tests/unit_exits/session_log.tres"
const MATCH_ID: String = "unit_exit_regression"
const AXIS_EXIT: Vector2i = Vector2i(8, 19)
const ALLIED_EXIT: Vector2i = Vector2i(9, 19)

var checks: int = 0
var failures: int = 0
var exits: int = 0
var deaths: int = 0
var shots: int = 0
var controller: Node2D
var axis_exit: ExitUnitsCondition
var allied_exit: ExitUnitsCondition
var prevent_axis: PreventEnemyExitCondition
var prevent_allies: PreventEnemyExitCondition


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if OS.get_cmdline_user_args().has("--verify-persistence"):
		_verify_persistence()
		_finish()
		return
	Globals.session_log = SessionLog.new()
	Globals.session_log.storage_path = LOG_PATH
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("DefaultMap")
	var scenario: Scenario = map.get_scenario(0)
	scenario.axis_ai_status = Scenario.AIStatus.OFF
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	controller = world.game_controller
	_freeze(main)
	Globals.game_started = true
	controller.timer_running = true
	_configure_conditions()
	var axis: Array[Unit] = Globals.get_units_for_team(Globals.Team.AXIS)
	var allies: Array[Unit] = Globals.get_units_for_team(Globals.Team.ALLIES)
	var hq: Unit
	var rifle: Unit
	for unit: Unit in axis:
		if unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
			hq = unit
		elif unit.squad_type == Globals.SquadType.Rifle:
			rifle = unit
	_check(hq != null and rifle != null and not allies.is_empty(), "Fixture supplies HQ, rifle, and opposing squads")
	var enemy: Unit = allies[0]
	var active_before: int = Globals.get_units().size()
	var members: int = rifle.members_alive
	var losses: int = Globals.battle_casualties.size()
	var destroyed: int = Globals.units_destroyed.units_collection[Globals.Team.ALLIES].units.size()
	controller._on_unit_entered_hex(rifle, ALLIED_EXIT)
	_check(not rifle.exited, "A squad cannot leave through the opposing side's exit")
	rifle.surrendered = true
	controller._on_unit_entered_hex(rifle, AXIS_EXIT)
	_check(not rifle.exited and axis_exit.state.units_exited.is_empty(), "Surrendered squads cannot exit")
	rifle.surrendered = false
	rifle.unit_exited.connect(_on_exit)
	rifle.unit_died.connect(_on_death)
	rifle.squad_fire.fire_shot.connect(_on_shot)
	Globals.unit_visible_enemies[enemy] = [rifle]
	Globals.unit_enemies_in_los[enemy] = [rifle]
	enemy.enemy_memory[rifle] = {"last_seen_time": 0.0}
	enemy.squad_fire.target_unit = rifle
	var burst_soldier: Soldier = rifle.squad_fire.soldiers[0]
	rifle.squad_fire.fire_shots(burst_soldier, 3, 1200.0, false, enemy.current_hex)
	_check(shots == 1, "Fixture starts a delayed burst before exit")
	rifle.goal_hex = AXIS_EXIT
	rifle.movement.target_position = controller.ground_layer.map_to_local(AXIS_EXIT)
	rifle.position = rifle.movement.target_position
	rifle.movement.is_moving = true
	rifle.is_moving = true
	rifle.movement.path_hexes = [rifle.current_hex, AXIS_EXIT, ALLIED_EXIT]
	rifle.movement.path_index = 1
	rifle.movement._process_movement(1.0)
	_check(rifle.exited and rifle.alive and rifle.members_alive == members, "Actual movement into an exit retires the squad without killing soldiers")
	_check(Globals.get_units().size() == active_before - 1 and not Globals.get_units().has(rifle) and Globals.get_exited_units().has(rifle), "Exited markers remain owned by the map outside the active roster")
	_check(axis_exit.state.units_exited == [rifle] and prevent_axis.state.units_exited == [rifle], "Own exit and enemy prevention ledgers both record the entry before retirement")
	_check(not rifle.is_good_order() and not InfluenceUnitQuery.is_valid_living_unit(rifle), "Exited units cannot occupy objectives or contribute AI influence")
	_check(not rifle.is_moving and not rifle.movement.is_moving and rifle.movement.path_hexes.is_empty(), "Exit cancels the remaining route instead of advancing past the marker")
	_check(rifle.action_controller.establishing_timer.is_stopped(), "Exit does not start a late setup timer")
	_check(rifle.ui.broken_label.visible and rifle.ui.broken_label.text == "Exited" and rifle.ui.sprite_node.visible and not rifle.ui.dead.visible, "Visible exit marker is distinct from a corpse")
	_check(not rifle.ui.morale_bar.visible, "Inactive exit markers hide combat status")
	_check(not Globals.unit_visible_enemies[enemy].has(rifle) and not Globals.unit_enemies_in_los[enemy].has(rifle) and not enemy.enemy_memory.has(rifle) and enemy.squad_fire.target_unit == null, "Exit clears visibility, remembered contacts, and enemy firing targets")
	_check(not LOSHelper.find_units_at(AXIS_EXIT).has(rifle), "Exited units do not occupy the exit hex for movement or combat")
	controller._select_unit(rifle)
	_check(controller.selected_unit != rifle, "Inactive markers cannot receive selection orders")
	rifle.order(Globals.UnitCmd.MOVE, ALLIED_EXIT)
	rifle.movement.move_to_hex(ALLIED_EXIT)
	rifle.action_controller.on_reached_hex(AXIS_EXIT)
	rifle.action_controller.give_hold_order()
	rifle._on_retreat_complete(ALLIED_EXIT)
	rifle._on_started_moving()
	_check(not rifle.movement.is_moving and rifle.current_hex == AXIS_EXIT and rifle.action_controller.establishing_timer.is_stopped(), "Orders and late arrivals cannot reactivate exited squads")
	var action_state: int = rifle.action_controller.action_state
	_check(action_state == SquadActionController.SquadActionState.NO_ORDER and not PositionQueryService.can_follow_intent(rifle), "Direct tactical orders cannot reassign an exited squad")
	rifle._on_incoming_fire_effect(members, 100.0, 100.0, enemy)
	_check(not rifle.apply_specific_casualty(burst_soldier) and rifle.members_alive == members, "Late impacts and debug casualties cannot kill escaped soldiers")
	rifle.die()
	rifle.surrender()
	rifle.exit_map()
	controller._on_unit_entered_hex(rifle, ALLIED_EXIT)
	_check(exits == 1 and deaths == 0 and Globals.battle_exits.size() == 1, "Exit is idempotent and cannot become death or surrender")
	_check(Globals.battle_casualties.size() == losses and Globals.units_destroyed.units_collection[Globals.Team.ALLIES].units.size() == destroyed, "Exit creates no casualties or destruction credit")
	await get_tree().create_timer(0.2).timeout
	_check(shots == 1, "Exit cancels the rest of a delayed burst")
	var recipient: Unit = axis[1]
	if recipient == hq or recipient == rifle:
		recipient = axis[2]
	_set_hex(hq, recipient.current_hex)
	hq.leader_aura._update_aura()
	recipient.command_squad = hq
	recipient._on_command_connectivity_timeout()
	var source: int = hq.leader_aura.get_instance_id()
	_check(recipient.stress_system._leadership_sources.has(source) and recipient.command_connectivity.leader_presence_strength > 0.0, "HQ fixture supplies leadership before exiting")
	_set_hex(hq, AXIS_EXIT)
	controller._on_unit_entered_hex(hq, AXIS_EXIT)
	_check(hq.exited and not recipient.stress_system._leadership_sources.has(source) and is_zero_approx(recipient.command_connectivity.leader_presence_strength), "An exited HQ immediately loses its leadership and command effects")
	var links: Node2D = controller.get_node("CommandConnectivityRenderer")
	links._process(0.0)
	for line: MovingDottedDrawLine in links.get_children():
		if line.unit == hq or line.unit.command_squad == hq:
			_check(not line.visible, "Command overlays cannot retain links to exited HQs")
	_set_hex(enemy, ALLIED_EXIT)
	controller._on_unit_entered_hex(enemy, ALLIED_EXIT)
	_check(enemy.exited and allied_exit.state.units_exited == [enemy] and prevent_allies.state.units_exited == [enemy], "Physical exit works identically for the other side")
	axis_exit.advance_time(0.1)
	_check(axis_exit.state.units_exited.size() == 2 and axis_exit.is_condition_met() and not prevent_axis.is_condition_met(), "Victory progress persists after units leave active play")
	await get_tree().process_frame
	var log: SessionLog = SessionLog.load_log(LOG_PATH)
	_check(log.exit_records.size() == 3, "Exit events are persisted during the match, before the result save")
	var record: UnitExitRecord = rifle.exit_record
	_check(record.hex == AXIS_EXIT and record.members_alive == members and record.battle_id == Globals.battle_id and record.scenario_name == scenario.scenario_name, "Session record identifies the battle, scenario, squad and exit location")
	scenario.scenario_name = MATCH_ID
	world._on_game_controller_show_winner(Globals.Team.AXIS, VictoryCondition.OutcomeLevel.MINOR, false)
	var saved: MatchSaveData = Globals.load_match_data(MATCH_ID)
	_check(saved != null and saved.exited_units.size() == 3 and saved.exit_records.size() == 3, "Result save includes exited rosters and events from both sides")
	var player_exited: int = 0
	for data: UnitSaveData in saved.player_units:
		if data.exited:
			player_exited += 1
	_check(player_exited == 1, "Player roster preserves escaped survivors and their exited status")
	var restored_data: UnitSaveData
	for data: UnitSaveData in saved.exited_units:
		if data.exit_record.record_id == rifle.exit_record.record_id:
			restored_data = data
	_check(restored_data != null and restored_data.squad_loadout.soldiers.size() == members, "Escaped soldiers and their equipment survive serialization")
	for marker: Unit in Globals.get_exited_units():
		marker.free()
	axis_exit.state.units_exited.clear()
	allied_exit.state.units_exited.clear()
	prevent_axis.state.units_exited.clear()
	prevent_allies.state.units_exited.clear()
	# Restore only exited markers; active roster deployment is tested independently.
	for data: UnitSaveData in saved.player_units.duplicate():
		if not data.exited:
			saved.player_units.erase(data)
	controller.spawn_units_from_match_save(saved)
	_check(Globals.get_exited_units().size() == 3, "Loading restores each exited marker once even when also present in the player's roster")
	_check(axis_exit.state.units_exited.size() == 2 and allied_exit.state.units_exited.size() == 1 and not prevent_axis.is_condition_met() and not prevent_allies.is_condition_met(), "Restored exited markers preserve both victory ledgers")
	for marker: Unit in Globals.get_exited_units():
		_check(marker.exited and marker.alive and not marker.is_in_group("units") and marker.ui.broken_label.text == "Exited", "Loaded markers remain inactive with surviving soldiers")
	_check(Globals.session_log.exit_records.size() == 3, "Loading saved exits does not duplicate session records")
	_check(Globals.battle_exits.size() == 3, "Reloaded exits remain available to subsequent result saves")
	_check(not UnitSaveData.new().exited and MatchSaveData.new().exit_records.is_empty(), "Older saves default to no exits")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_finish()


func _configure_conditions() -> void:
	Globals.objectives = {
		Globals.Team.AXIS: _objectives(Globals.Team.AXIS, AXIS_EXIT),
		Globals.Team.ALLIES: _objectives(Globals.Team.ALLIES, ALLIED_EXIT),
	}
	axis_exit = ExitUnitsCondition.new()
	axis_exit.team = Globals.Team.AXIS
	axis_exit.required_unit_count = 2
	axis_exit.test_at_scenario_end = true
	allied_exit = ExitUnitsCondition.new()
	allied_exit.team = Globals.Team.ALLIES
	allied_exit.test_at_scenario_end = true
	prevent_axis = PreventEnemyExitCondition.new()
	prevent_axis.team = Globals.Team.ALLIES
	prevent_allies = PreventEnemyExitCondition.new()
	prevent_allies.team = Globals.Team.AXIS
	Globals.victory_conditions = {
		Globals.Team.AXIS: VictoryConditionCollection.new(),
		Globals.Team.ALLIES: VictoryConditionCollection.new(),
	}
	Globals.victory_conditions[Globals.Team.AXIS].victory_conditions = [axis_exit, prevent_allies]
	Globals.victory_conditions[Globals.Team.ALLIES].victory_conditions = [allied_exit, prevent_axis]
	controller.set_victory_conditions()


func _objectives(team: Globals.Team, hex: Vector2i) -> ObjectivesCollection:
	var objective: ObjectiveDefinition = ObjectiveDefinition.new()
	objective.team = team
	objective.hex = hex
	objective.objective_id = ExitUnitsCondition.ObjectiveId.EXIT
	var collection: ObjectivesCollection = ObjectivesCollection.new()
	collection.objectives = [objective]
	return collection


func _set_hex(unit: Unit, hex: Vector2i) -> void:
	unit.current_hex = hex
	unit.current_cube = controller.ground_layer.map_to_cube(hex)
	unit.position = controller.ground_layer.map_to_local(hex)


func _verify_persistence() -> void:
	var log: SessionLog = SessionLog.load_log(LOG_PATH)
	_check(log.exit_records.size() == 3, "A fresh process reads the persistent exit log")
	var saved: MatchSaveData = Globals.load_match_data(MATCH_ID)
	_check(saved != null and saved.exit_records.size() == 3 and saved.exited_units.size() == 3, "A fresh process reads both sides' exits from the match save")
	if saved != null:
		for record: UnitExitRecord in saved.exit_records:
			_check(not record.record_id.is_empty() and record.members_alive > 0 and not record.battle_id.is_empty(), "Persistent exit records retain identity and survivors")
		for data: UnitSaveData in saved.exited_units:
			_check(data.exited and data.exit_record != null and not data.squad_loadout.soldiers.is_empty(), "Persistent exited rosters retain soldiers and equipment")


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		(node as Timer).stop()
	for child: Node in node.get_children():
		_freeze(child)


func _on_exit(_unit: Unit) -> void:
	exits += 1


func _on_death(_unit: Unit) -> void:
	deaths += 1


func _on_shot(_weapon: WeaponSpec, _hex: Vector2i) -> void:
	shots += 1


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _finish() -> void:
	print("Unit exit checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)
