extends Node

# Run with: godot --headless --path . tests/unit_death_regression.tscn
class ImpactProbe extends SquadFireController:
	var impacts: int = 0

	func _on_fire_weapon(_weapon: WeaponSpec, _position: Vector2, _auto: bool, _owner_id: int, _position_node: Node2D) -> void:
		pass

	func fire_at(_rounds: int, _weapon: WeaponSpec, _riflegrenade: bool, _hex: Vector2i, _distance: int, _cover: int, _targets: Array[Unit]) -> void:
		impacts += 1


var failures: int = 0
var shots: int = 0
var deaths: int = 0
var soldiers_created: Array[Soldier] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_history: CasualtyHistory = Globals.casualty_history
	Globals.casualty_history = CasualtyHistory.new()
	Globals.casualty_history.storage_path = "user://tests/unit_death/casualties.tres"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze_simulation(main)
	var units: Array[Unit] = Globals.get_units()
	for unit: Unit in units:
		soldiers_created.append_array(unit.squad_fire.soldiers)
	var hq: Unit = units[0]
	var recipient: Unit = units[1]
	var hq_soldiers: Array[Soldier] = hq.squad_fire.soldiers.duplicate()
	var enemy_hq: Unit = units[3]
	var enemy_recipient: Unit = units[4]
	_check(hq.team == recipient.team and enemy_hq.team == enemy_recipient.team, "Fixture pairs are on the same team")
	hq.current_cube = recipient.current_cube
	hq.current_hex = recipient.current_hex
	hq.leader_aura._update_aura()
	var source_id: int = hq.leader_aura.get_instance_id()
	var own_source_id: int = recipient.leader_aura.get_instance_id()
	recipient.leader_aura._apply_to(recipient)
	_check(recipient.stress_system._leadership_sources.has(source_id), "Living HQ supplies leadership to its neighbor")
	_check(recipient.stress_system._leadership_sources.has(own_source_id), "Recipient has an independent leadership source")
	recipient.command_squad = hq
	recipient._on_command_connectivity_timeout()
	_check(recipient.command_connectivity.leader_presence_strength > 0.0, "Living HQ supplies command presence")
	# Reparenting during scenario setup must leave living controllers active.
	var impact_probe: ImpactProbe = ImpactProbe.new()
	impact_probe.unit = hq
	impact_probe.stress_controller = hq.stress_system
	hq.add_child(impact_probe)
	impact_probe.set_process(false)
	var projectile_weapon: WeaponSpec = WeaponSpec.new()
	projectile_weapon.range_hexes = 100
	projectile_weapon.projectile_speed = 10000.0
	projectile_weapon.mag_capacity = 1
	projectile_weapon.ammunition = 10
	var projectile_soldier: Soldier = Soldier.new(998, "Impact probe", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, projectile_weapon, hq, hq.team)
	projectile_soldier.setup_weapon_task.done = true
	projectile_soldier.reload_task.done = true
	projectile_soldier.aquire_target_task.done = true
	soldiers_created.append(projectile_soldier)
	hq.attackState = Unit.AttackState.MANUAL_GROUND
	impact_probe.target_hex = enemy_recipient.current_hex
	Debug.dont_fire_wepaons = false
	impact_probe._try_fire_soldier(0.1, projectile_soldier, false, 0, 0, 0, 0)
	_check(projectile_weapon.ammunition == 9, "Fixture launches a projectile before death")
	var children: Array[Node] = hq.get_children()
	var child_ids: Array[int] = []
	for child: Node in children:
		child_ids.append(child.get_instance_id())
	var timers: Array[Node] = hq.find_children("*", "Timer", true, false)
	for timer_node: Node in timers:
		if not hq.ui.is_ancestor_of(timer_node):
			var timer: Timer = timer_node as Timer
			timer.start(1.0)
	hq.movement.path_hexes.append(recipient.current_hex)
	hq.movement.attack_in_progress = true
	hq.movement.exposed_path_hexes.append(enemy_recipient.current_hex)
	hq.movement.is_moving = true
	hq.is_moving = true
	var weapon: WeaponSpec = WeaponSpec.new()
	weapon.snd_mg_loop = AudioStreamGenerator.new()
	var soldier: Soldier = Soldier.new(999, "Burst probe", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, weapon, hq, hq.team)
	soldiers_created.append(soldier)
	hq.weapon_audio.start_mg_loop(soldier.id, weapon, hq)
	var loop_player: AudioStreamPlayer2D = hq.weapon_audio._mg_loops[soldier.id]
	_check(loop_player.playing, "Fixture starts a weapon loop")
	hq.squad_fire.fire_shot.connect(_on_shot)
	hq.unit_died.connect(_on_death)
	hq.squad_fire.fire_shots(soldier, 3, 1200.0, false, recipient.current_hex)
	_check(shots == 1, "First burst shot fires before death")
	var orphans_before: Array[int] = Node.get_orphan_node_ids()
	hq.die()
	_check(hq.casualty_records.size() == hq_soldiers.size() and hq.squad_fire.casualties.size() == hq_soldiers.size(), "Direct death retains every soldier and equipment record")
	for dead_soldier: Soldier in hq_soldiers:
		_check(not dead_soldier.is_alive and hq.squad_fire.casualties.has(dead_soldier), "Eliminated soldiers remain available in the casualty roster")
		var record: CasualtyRecord = Globals.casualty_history.find_record(dead_soldier.casualty_record_id)
		_check(record != null and record.soldier_name == dead_soldier.name and record.equipment.weapon_name == dead_soldier.weapon.name, "History preserves soldier identity and equipment")
	_check(not recipient.stress_system._leadership_sources.has(source_id), "Death immediately removes the HQ leadership source")
	_check(is_zero_approx(recipient.command_connectivity.command_link_strength) and is_zero_approx(recipient.command_connectivity.leader_presence_strength), "Death immediately clears command connectivity")
	_check(is_zero_approx(recipient.stress_system.leader_presence_strength), "Death immediately clears the command presence morale bonus")
	_check(recipient.stress_system._leadership_sources.has(own_source_id), "Death preserves independent leadership sources")
	_check(hq.leader_aura._affected.is_empty(), "Death clears the affected-unit registry")
	_check(not hq.leader_aura.is_in_group("leader_aura"), "Dead aura leaves the active aura group")
	_check(not loop_player.playing, "Death immediately stops the weapon loop")
	_check(hq.weapon_audio._mg_loops.is_empty(), "Death clears the weapon loop registry")
	_check(not hq.is_moving and not hq.movement.is_moving, "Death stops movement immediately")
	_check(hq.movement.path_hexes.is_empty() and hq.movement.exposed_path_hexes.is_empty() and not hq.movement.attack_in_progress, "Death cancels pending assault segments")
	for child: Node in children:
		_check(child.get_parent() == hq, "Death retains ownership of %s" % child.name)
		if child != hq.ui:
			_check(not child.can_process(), "Dead controller cannot process: %s" % child.name)
	for timer_node: Node in timers:
		if not hq.ui.is_ancestor_of(timer_node):
			var timer: Timer = timer_node as Timer
			_check(timer.is_stopped(), "Death stops timer %s" % timer.name)
	_check(hq.ui.dead.visible and not hq.ui.sprite_node.visible, "Corpse remains visible")
	_check(not hq.is_in_group("units") and hq.is_in_group("dead_units"), "Corpse leaves the live unit group")
	hq.leader_aura._apply_to(recipient)
	hq.leader_aura._apply_to(hq)
	_check(not recipient.stress_system._leadership_sources.has(source_id) and not hq.stress_system._leadership_sources.has(source_id), "Late callbacks cannot restore dead leadership")
	hq.die()
	_check(deaths == 1, "Repeated death emits the death signal once")
	if hq.squad_fire.is_inside_tree():
		hq.order(Globals.UnitCmd.FIRE_AT_UNIT, enemy_recipient)
		_check(hq.squad_fire.target_unit == null, "Dead units ignore new orders")
	await get_tree().create_timer(0.2).timeout
	_check(shots == 1, "Death cancels remaining delayed burst shots")
	_check(impact_probe.impacts == 1, "Already-launched projectile completes after its owner dies")
	_check(not is_instance_valid(loop_player), "Stopped weapon loop is freed")
	for orphan_id: int in Node.get_orphan_node_ids():
		_check(orphans_before.has(orphan_id), "Death creates no orphan nodes")
	for child_id: int in child_ids:
		_check(is_instance_id_valid(child_id), "Controllers remain valid while the corpse exists")
	# Free a live HQ to cover scene-exit cleanup without invoking die().
	enemy_hq.current_cube = enemy_recipient.current_cube
	enemy_hq.current_hex = enemy_recipient.current_hex
	enemy_hq.leader_aura._update_aura()
	var enemy_source_id: int = enemy_hq.leader_aura.get_instance_id()
	_check(enemy_recipient.stress_system._leadership_sources.has(enemy_source_id), "Second living HQ supplies leadership")
	enemy_recipient.command_squad = enemy_hq
	enemy_recipient._on_command_connectivity_timeout()
	enemy_hq.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not enemy_recipient.stress_system._leadership_sources.has(enemy_source_id), "Freeing a living HQ removes its leadership source")
	enemy_recipient._on_command_connectivity_timeout()
	_check(is_zero_approx(enemy_recipient.command_connectivity.leader_presence_strength) and is_zero_approx(enemy_recipient.stress_system.leader_presence_strength), "Freed command units cannot retain a presence bonus")
	var ranged_victim: Unit = units[2]
	var ranged_original_size: int = ranged_victim.original_size
	var casualty: Soldier = ranged_victim.squad_fire.soldiers.back()
	ranged_victim.apply_specific_casualty(casualty)
	_check(ranged_victim.alive and ranged_victim.casualty_records.size() == 1, "Individual casualties are recorded while their unit remains alive")
	_check(ranged_victim.create_save_data().casualty_records.size() == 1, "Unit saves include prior casualty records")
	var ranged_source_id: int = ranged_victim.leader_aura.get_instance_id()
	ranged_victim.leader_aura._apply_to(recipient)
	_check(recipient.stress_system._leadership_sources.has(ranged_source_id), "Ranged casualty fixture has a leadership source")
	Debug.no_damage = false
	ranged_victim._on_incoming_fire_effect(ranged_victim.members_alive, 10.0, 10.0, null)
	_check(not ranged_victim.alive and ranged_victim.members_alive == 0, "Lethal ranged fire eliminates the runtime roster")
	_check(not recipient.stress_system._leadership_sources.has(ranged_source_id), "Lethal ranged fire removes leadership from neighbors")
	_check(not ranged_victim.stress_system._leadership_sources.has(ranged_source_id), "The lethal-fire callback cannot restore the victim's aura")
	_check(ranged_victim.stress_system.state == STATES.MoraleState.COMBAT_INEFFECTIVE, "Lethal-fire callback preserves the final morale state")
	var scenario_name: String = scenario.scenario_name
	var match_id: String = "death_regression_" + Globals.battle_id
	scenario.scenario_name = match_id
	world._on_game_controller_show_winner(Globals.Team.AXIS, VictoryCondition.OutcomeLevel.MINOR, false)
	var saved_match: MatchSaveData = Globals.load_match_data(match_id)
	_check(saved_match != null and saved_match.casualty_records.size() == hq_soldiers.size() + ranged_original_size, "Battle-result saves include dead units and individual casualties")
	_check(saved_match.battle_id == Globals.battle_id, "Battle-result saves retain the casualty battle identity")
	scenario.scenario_name = scenario_name
	DirAccess.remove_absolute("user://matches/%s.tres" % match_id)
	main._on_try_again()
	await get_tree().create_timer(0.2).timeout
	for child_id: int in child_ids:
		_check(not is_instance_id_valid(child_id), "Restart frees the corpse's owned controllers")
	_check(Globals.get_units().is_empty(), "Restart clears the battlefield")
	_check(Globals.casualty_history.records.size() == hq_soldiers.size() + ranged_original_size, "History survives battlefield restart")
	var reloaded_history: CasualtyHistory = CasualtyHistory.load_history(Globals.casualty_history.storage_path)
	_check(reloaded_history.records.size() == Globals.casualty_history.records.size(), "Automatic history saves survive loading from disk")
	# Allow outstanding burst/watchdog timers to resume after scene cleanup.
	await get_tree().create_timer(6.0).timeout
	_free_soldier_tasks()
	# Clean up the old implementation's detached children when testing the baseline.
	for child_id: int in child_ids:
		if is_instance_id_valid(child_id):
			var child: Node = instance_from_id(child_id) as Node
			if child.get_parent() == null:
				child.free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Globals.casualty_history = original_history
	print("Unit death regression failures: ", failures)
	get_tree().quit(failures)


func _freeze_simulation(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		var timer: Timer = node as Timer
		timer.stop()
	for child: Node in node.get_children():
		_freeze_simulation(child)


func _free_soldier_tasks() -> void:
	for soldier: Soldier in soldiers_created:
		var tasks: Array[SoldierTask] = [
			soldier.setup_weapon_task, soldier.aquire_target_task, soldier.reload_task,
			soldier.fire_weapon_task, soldier.assist_task, soldier.close_combat_task,
		]
		for task: SoldierTask in tasks:
			if is_instance_valid(task):
				task.free()
	soldiers_created.clear()


func _on_shot(_weapon: WeaponSpec, _hex: Vector2i) -> void:
	shots += 1


func _on_death(_unit: Unit) -> void:
	deaths += 1


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
