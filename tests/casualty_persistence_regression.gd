extends Node

# Run normally to write fixtures, then run again with -- --verify-persistence
# to verify the same history from a fresh Godot process.
const HISTORY_PATH: String = "user://tests/casualty_persistence/history.tres"
const UNIT_PATH: String = "user://tests/casualty_persistence/unit.tres"

class UnitUnderTest extends Unit:
	func _make_squad() -> void:
		pass

	func _setup_runtime_soldiers(_loadout: SquadLoadoutSpec) -> void:
		pass

var failures: int = 0
var soldiers_created: Array[Soldier] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if OS.get_cmdline_user_args().has("--verify-persistence"):
		_verify_history(CasualtyHistory.load_history(HISTORY_PATH))
		_check(Globals.get_units().is_empty(), "History loads without any battlefield nodes")
		_finish()
		return
	var original_history: CasualtyHistory = Globals.casualty_history
	Globals.casualty_history = CasualtyHistory.new()
	Globals.casualty_history.storage_path = HISTORY_PATH
	Globals.begin_battle()
	var first_battle_id: String = Globals.battle_id
	var unit: Unit = UnitUnderTest.new()
	unit.name = "HistoryAlpha"
	unit.team = Globals.Team.AXIS
	unit.company = Unit.Company.B
	unit.platoon = 2
	unit.squad = 3
	unit.current_hex = Vector2i(11, 8)
	var weapon: WeaponSpec = (load("res://resources/weapons/m1_garand.tres") as WeaponSpec).create_runtime()
	weapon.name = "Recorded rifle"
	weapon.ammunition = 25
	weapon.is_setup = true
	weapon.riflegrenade_loaded = true
	var soldier: Soldier = _make_soldier(7, "Recorded soldier", unit, weapon)
	soldier.rounds_in_mag = 2
	soldier.jammed = true
	var first_record: CasualtyRecord = Globals.record_casualty(unit, soldier)
	_check(Globals.record_casualty(unit, soldier) == first_record and Globals.casualty_history.records.size() == 1, "Recording a casualty twice is idempotent")
	weapon.ammunition = 24
	var crew: Soldier = _make_soldier(8, "Recorded crew", unit, weapon)
	var crew_record: CasualtyRecord = Globals.record_casualty(unit, crew)
	_check(first_record.equipment.weapon_id == crew_record.equipment.weapon_id, "Shared physical weapons retain a common equipment identifier")
	_check(first_record.equipment != crew_record.equipment, "Shared weapons have independent historical snapshots")
	weapon.ammunition = 3
	weapon.name = "Recovered rifle"
	weapon.riflegrenade_loaded = false
	_check(first_record.equipment.ammunition == 25 and first_record.equipment.weapon_name == "Recorded rifle" and first_record.equipment.riflegrenade_loaded, "Later weapon changes cannot alter a casualty record")
	var enemy_unit: Unit = UnitUnderTest.new()
	enemy_unit.name = "HistoryBeta"
	enemy_unit.team = Globals.Team.ALLIES
	var unarmed: Soldier = _make_soldier(9, "Unarmed casualty", enemy_unit, weapon)
	unarmed.weapon = null
	Globals.record_casualty(enemy_unit, unarmed)
	var unit_save: UnitSaveData = UnitSaveData.new()
	unit_save.casualty_records.append(first_record)
	var match_save: MatchSaveData = MatchSaveData.new()
	match_save.match_id = "casualty_regression_" + first_battle_id
	match_save.battle_id = first_battle_id
	match_save.casualty_records.assign(Globals.battle_casualties)
	Globals.save_match_data(match_save)
	_check(DirAccess.make_dir_recursive_absolute(UNIT_PATH.get_base_dir()) == OK, "Create fixture save directory")
	_check(ResourceSaver.save(unit_save, UNIT_PATH) == OK, "Unit casualty records can be saved")
	var loaded_unit: UnitSaveData = ResourceLoader.load(UNIT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as UnitSaveData
	_check(loaded_unit != null and loaded_unit.casualty_records.size() == 1 and loaded_unit.casualty_records[0].equipment.ammunition == 25, "Unit saves retain casualty equipment state")
	# Scene cleanup and a new battle must leave the historical archive intact.
	unit.free()
	enemy_unit.free()
	Globals.reset()
	Globals.begin_battle()
	_check(Globals.battle_id != first_battle_id and Globals.battle_casualties.is_empty() and Globals.casualty_history.records.size() == 3, "New battles preserve history and start a distinct current roster")
	var next_unit: Unit = UnitUnderTest.new()
	next_unit.name = "NextBattle"
	next_unit.team = Globals.Team.ALLIES
	var next_weapon: WeaponSpec = weapon.create_runtime()
	next_weapon.ammunition = 7
	var next_soldier: Soldier = _make_soldier(7, "Later casualty", next_unit, next_weapon)
	Globals.record_casualty(next_unit, next_soldier)
	next_unit.free()
	await get_tree().process_frame
	await get_tree().process_frame
	_verify_history(CasualtyHistory.load_history(HISTORY_PATH))
	# Importing a saved match into an empty archive restores both teams' losses.
	var complete_history: CasualtyHistory = Globals.casualty_history
	Globals.casualty_history = CasualtyHistory.new()
	Globals.casualty_history.storage_path = "user://tests/casualty_persistence/imported.tres"
	var loaded_match: MatchSaveData = Globals.load_match_data(match_save.match_id)
	_check(loaded_match != null and loaded_match.casualty_records.size() == 3 and loaded_match.battle_id == first_battle_id, "Match saves round-trip casualties and battle identity")
	_check(Globals.casualty_history.records.size() == 3, "Loading a match restores its casualty archive")
	Globals.load_match_data(match_save.match_id)
	Globals.import_casualty_records(loaded_unit.casualty_records)
	_check(Globals.casualty_history.records.size() == 3, "Repeated match and unit imports do not duplicate history")
	var restored: Unit = UnitUnderTest.new()
	restored.squad_fire = SquadFireController.new()
	restored.add_child(restored.squad_fire)
	restored.apply_save_data(loaded_unit)
	_check(restored.casualty_records.size() == 1 and restored.casualty_records[0].equipment.ammunition == 25, "Applying unit save data restores historical casualty records")
	_check(Globals.casualty_history.records.size() == 3, "Applying unit save data merges history without duplicates")
	restored.free()
	var legacy: MatchSaveData = MatchSaveData.new()
	legacy.save_version = 1
	legacy.match_id = match_save.match_id + "_legacy"
	Globals.save_match_data(legacy)
	var loaded_legacy: MatchSaveData = Globals.load_match_data(legacy.match_id)
	_check(loaded_legacy != null and loaded_legacy.casualty_records.is_empty(), "Older match saves load with an empty casualty roster")
	await get_tree().process_frame
	await get_tree().process_frame
	Globals.casualty_history = complete_history
	_check(Globals.casualty_history.save_history() == OK, "Archive can replace an existing saved history")
	Globals.casualty_history = original_history
	DirAccess.remove_absolute("user://matches/%s.tres" % match_save.match_id)
	DirAccess.remove_absolute("user://matches/%s.tres" % legacy.match_id)
	for created: Soldier in soldiers_created:
		var tasks: Array[SoldierTask] = [created.setup_weapon_task, created.aquire_target_task, created.reload_task, created.fire_weapon_task, created.assist_task, created.close_combat_task]
		for task: SoldierTask in tasks:
			task.free()
	soldiers_created.clear()
	_finish()


func _make_soldier(id: int, nickname: String, unit: Unit, weapon: WeaponSpec) -> Soldier:
	var soldier: Soldier = Soldier.new(id, nickname, RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, weapon, unit, unit.team)
	soldiers_created.append(soldier)
	return soldier


func _verify_history(history: CasualtyHistory) -> void:
	_check(history.records.size() == 4, "Disk history retains casualties across two battles")
	if history.records.size() != 4:
		return
	var first: CasualtyRecord = history.records[0]
	_check(first.soldier_id == 7 and first.soldier_name == "Recorded soldier" and first.unit_name == "HistoryAlpha", "Historical identity survives scene destruction and loading")
	_check(first.company == Unit.Company.B and first.platoon == 2 and first.squad == 3 and first.hex == Vector2i(11, 8), "Historical unit designation and location survive loading")
	_check(first.equipment.ammunition == 25 and first.equipment.rounds_in_mag == 2 and first.equipment.jammed and first.equipment.is_setup and first.equipment.riflegrenade_loaded, "Equipment state survives disk loading")
	_check(first.equipment.weapon_name == "Recorded rifle" and first.equipment.resource_path_at_death == "res://resources/weapons/m1_garand.tres", "Equipment name and source identity survive loading")
	_check(history.records[1].equipment.ammunition == 24 and history.records[1].equipment.weapon_id == first.equipment.weapon_id, "Shared weapon identity and separate snapshots survive loading")
	_check(history.records[2].equipment == null and history.records[2].team == Globals.Team.ALLIES, "Unarmed and opposing-team casualties survive loading")
	_check(history.records[3].battle_id != first.battle_id and history.records[3].equipment.ammunition == 7, "Later battles append history")
	_check(history.find_record(first.record_id) == first and first.recorded_at_unix > 0.0, "Loaded history rebuilds the ID index and preserves timestamps")


func _finish() -> void:
	print("Casualty persistence regression failures: ", failures)
	get_tree().quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
