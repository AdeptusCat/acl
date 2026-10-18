extends Node

# Run with: godot --headless --path . tests/soldier_task_lifecycle_regression.tscn
class RosterUiUnderTest extends UnitUi:
	func set_members_alive(_count: int) -> void:
		pass


var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_history: CasualtyHistory = Globals.casualty_history
	Globals.casualty_history = CasualtyHistory.new()
	Globals.casualty_history.storage_path = "user://tests/soldier_task_lifecycle/casualties.tres"
	_test_task_lifetime_and_countdowns()
	_test_roster_replacement()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var orphan_baseline: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for cycle: int in range(3):
		await _test_restart(main, cycle)
	var orphan_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("Orphan nodes before/after three restarts: ", orphan_baseline, "/", orphan_after)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Globals.casualty_history = original_history
	print("Soldier task lifecycle regression failures: ", failures)
	get_tree().quit(failures)


func _test_task_lifetime_and_countdowns() -> void:
	_test_countdowns()
	_check_released(_discarded_soldier_task_refs(), "Discarding a standalone soldier")
	_check_released(_held_task_refs(), "Releasing an explicitly retained task")


func _test_countdowns() -> void:
	var soldier: Soldier = _make_soldier()
	for task: SoldierTask in _tasks(soldier):
		task.done = false
		task.start_time_s = 1.0
		_check(is_equal_approx(task.remaining_time_s, 1.0) and not task.task_name.is_empty(), "Tasks retain duration and display metadata")
	_check(not soldier.is_weapon_setup_done(0.5) and is_equal_approx(soldier.setup_weapon_task.remaining_time_s, 0.5), "Setup countdown advances")
	_check(not soldier.is_weapon_reload_done(0.5) and is_equal_approx(soldier.reload_task.remaining_time_s, 0.5), "Reload countdown advances")
	_check(not soldier.is_acquiring_target_done(0.5) and is_equal_approx(soldier.aquire_target_task.remaining_time_s, 0.5), "Target-acquisition countdown advances")


func _discarded_soldier_task_refs() -> Array[WeakRef]:
	var soldier: Soldier = _make_soldier()
	return _task_refs(soldier)


func _held_task_refs() -> Array[WeakRef]:
	var soldier: Soldier = _make_soldier()
	var refs: Array[WeakRef] = _task_refs(soldier)
	var held_task: SoldierTask = soldier.reload_task
	var held_ref: WeakRef = weakref(held_task)
	soldier = null
	_check(_surviving(refs) == 1 and held_ref.get_ref() != null, "An explicit task reference retains only that task")
	return refs


func _test_roster_replacement() -> void:
	var unit: Unit = Unit.new()
	unit.squad_fire = SquadFireController.new()
	unit.add_child(unit.squad_fire)
	unit.ui = RosterUiUnderTest.new()
	unit.add_child(unit.ui)
	var loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	for index: int in range(3):
		var entry: SoldierLoadout = SoldierLoadout.new()
		entry.weapon = WeaponSpec.new()
		loadout.soldiers.append(entry)
	unit._setup_runtime_soldiers(loadout)
	for cycle: int in range(3):
		var old_refs: Array[WeakRef] = _roster_task_refs(unit)
		# Both roster collections own their soldiers until replacement or teardown.
		unit.squad_fire.casualties.append(unit.squad_fire.soldiers.pop_back())
		unit._setup_runtime_soldiers(loadout)
		_check_released(old_refs, "Replacing living and casualty rosters")
	var before_load: Array[WeakRef] = _roster_task_refs(unit)
	unit.apply_save_data(unit.create_save_data())
	_check_released(before_load, "Applying a saved roster")
	var before_free: Array[WeakRef] = _roster_task_refs(unit)
	unit.free()
	_check_released(before_free, "Freeing a unit outside the scene tree")


func _test_restart(main: Node, cycle: int) -> void:
	var world: Node = main.world
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze_simulation(main)
	# Capture in a separate scope so iterator temporaries cannot retain a roster
	# across the restart await. Only weak references remain in this coroutine.
	var refs: Dictionary = _battle_refs()
	var task_refs: Array[WeakRef] = refs["tasks"]
	var soldier_refs: Array[WeakRef] = refs["soldiers"]
	var records_before: int = Globals.casualty_history.records.size()
	var casualties: int = _create_casualties()
	_check(casualties > 1, "Restart fixture includes an individual casualty and a dead squad")
	_check(_surviving(task_refs) == task_refs.size(), "Battlefield retains tasks for living soldiers and casualties")
	main._on_try_again()
	await get_tree().create_timer(0.2).timeout
	_check(not is_instance_valid(world) and main.world != null, "Try Again frees the old world and creates a new one")
	_check(Globals.get_units().is_empty(), "Restart clears runtime units")
	_check_released(soldier_refs, "Restart %d discards every runtime soldier" % cycle)
	_check_released(task_refs, "Restart %d discards every soldier task" % cycle)
	_check(Globals.casualty_history.records.size() == records_before + casualties, "Casualty history survives task cleanup")
	var loaded_history: CasualtyHistory = CasualtyHistory.load_history(Globals.casualty_history.storage_path)
	_check(loaded_history.records.size() == Globals.casualty_history.records.size(), "Casualty records and equipment remain saved after restart")
	_check(loaded_history.records.back().equipment != null, "Saved casualties retain their equipment")


func _battle_refs() -> Dictionary:
	var task_refs: Array[WeakRef] = []
	var soldier_refs: Array[WeakRef] = []
	for unit: Unit in Globals.get_units():
		task_refs.append_array(_roster_task_refs(unit))
		for soldier: Soldier in unit.squad_fire.soldiers:
			soldier_refs.append(weakref(soldier))
	return {"tasks": task_refs, "soldiers": soldier_refs}


func _create_casualties() -> int:
	var units: Array[Unit] = Globals.get_units()
	var victim: Unit = units[0]
	var corpse: Unit = units[3]
	var casualty_count: int = corpse.members_alive + 1
	victim.apply_specific_casualty(victim.squad_fire.soldiers.back())
	corpse.die()
	return casualty_count


func _make_soldier() -> Soldier:
	return Soldier.new(0, "Task fixture", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, WeaponSpec.new(), null, Globals.Team.AXIS)


func _tasks(soldier: Soldier) -> Array[SoldierTask]:
	return [soldier.setup_weapon_task, soldier.aquire_target_task, soldier.reload_task,
		soldier.fire_weapon_task, soldier.assist_task, soldier.close_combat_task]


func _task_refs(soldier: Soldier) -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	for task: SoldierTask in _tasks(soldier):
		refs.append(weakref(task))
	return refs


func _roster_task_refs(unit: Unit) -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	for soldier: Soldier in unit.squad_fire.soldiers:
		refs.append_array(_task_refs(soldier))
	for soldier: Soldier in unit.squad_fire.casualties:
		refs.append_array(_task_refs(soldier))
	return refs


func _surviving(refs: Array[WeakRef]) -> int:
	var count: int = 0
	for ref: WeakRef in refs:
		if ref.get_ref() != null:
			count += 1
	return count


func _check_released(refs: Array[WeakRef], label: String) -> void:
	var surviving: int = _surviving(refs)
	print(label, ": ", surviving, "/", refs.size(), " objects retained")
	_check(surviving == 0, label)


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
