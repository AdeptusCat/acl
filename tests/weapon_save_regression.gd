extends Node

# Run normally, then again with -- --verify-persistence in a fresh process.
const MATCH_ID: String = "tests/weapon_reference_regression"
const WEAPON_PATHS: Array[String] = [
	"res://resources/weapons/m1_garand.tres",
	"res://resources/weapons/mp40.tres",
	"res://resources/weapons/mg34.tres",
	"res://resources/weapons/m2_60mm_mortar.tres",
	"res://resources/weapons/m1a1_bazooka.tres",
	"res://resources/weapons/m1_garand.tres",
]

class SaveUiUnderTest extends UnitUi:
	func set_members_alive(_members: int) -> void:
		pass

	func set_ammunition_left(_ammunition: int) -> void:
		pass


var failures: int = 0
var units: Array[Unit] = []
var soldiers_created: Array[Soldier] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DirAccess.make_dir_recursive_absolute("user://tests") == OK, "Create isolated test save directory")
	if OS.get_cmdline_user_args().has("--verify-persistence"):
		_verify_match(Globals.load_match_data(MATCH_ID))
		_finish()
		return
	var loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	for index: int in range(WEAPON_PATHS.size()):
		var spec: WeaponSpec = load(WEAPON_PATHS[index]) as WeaponSpec
		var soldier: SoldierLoadout = _soldier_loadout(spec, "Weapon %d" % index)
		if spec.kind == WeaponSpec.WeaponKind.CREW_SERVED:
			soldier.role = RankGrades.Role.GUNNER
		loadout.soldiers.append(soldier)
	var source: Unit = _create_unit(loadout)
	var custom: WeaponSpec = WeaponSpec.new()
	custom.name = "Embedded prototype weapon"
	custom.type = WeaponSpec.WeaponType.SMG
	custom.range_hexes = 9
	custom.ammunition_start = 73
	var custom_loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	custom_loadout.soldiers.append(_soldier_loadout(custom, "Custom weapon"))
	var custom_unit: Unit = _create_unit(custom_loadout)
	var match_save: MatchSaveData = MatchSaveData.new()
	match_save.match_id = MATCH_ID
	match_save.player_units = [source.create_save_data(), custom_unit.create_save_data()]
	Globals.save_match_data(match_save)
	# Mutating the live weapon cannot alter its embedded saved definition.
	custom_unit.squad_fire.soldiers[0].weapon.name = "Later live weapon change"
	_check(match_save.player_units[1].squad_loadout.soldiers[0].weapon != null, "Anonymous weapons retain an embedded saved definition")
	if match_save.player_units[1].squad_loadout.soldiers[0].weapon != null:
		_check(match_save.player_units[1].squad_loadout.soldiers[0].weapon.name == "Embedded prototype weapon", "Embedded saved weapons are independent of live mutations")
	_verify_match(Globals.load_match_data(MATCH_ID))
	_test_legacy_loadouts_and_path_copies()
	_test_recovered_support_weapon()
	_test_missing_weapon_resources()
	_finish()


func _verify_match(match_save: MatchSaveData) -> void:
	_check(match_save != null and match_save.player_units.size() == 2, "Match save loads both weapon rosters")
	if match_save == null or match_save.player_units.size() != 2:
		return
	var saved_unit: UnitSaveData = match_save.player_units[0]
	_check(saved_unit.squad_loadout.soldiers.size() == WEAPON_PATHS.size(), "Match retains every living soldier")
	for index: int in range(saved_unit.squad_loadout.soldiers.size()):
		_check(saved_unit.squad_loadout.soldiers[index].weapon_resource_path == WEAPON_PATHS[index], "Weapon source path survives disk serialization")
	var first: Unit = _restore_unit(saved_unit)
	var second: Unit = _restore_unit(saved_unit)
	for index: int in range(WEAPON_PATHS.size()):
		var expected: WeaponSpec = load(WEAPON_PATHS[index]) as WeaponSpec
		var restored: Soldier = first.squad_fire.soldiers[index]
		_check(restored.weapon.name == expected.name and restored.weapon.type == expected.type and restored.weapon.family == expected.family, "Restoration keeps each soldier's weapon type and definition")
		_check(restored.weapon.source_resource_path == WEAPON_PATHS[index], "Restored weapons retain the original asset path")
		_check(restored.weapon != expected and restored.weapon != second.squad_fire.soldiers[index].weapon, "Restored runtime weapons are independent of definitions and other units")
		_check(restored.name == saved_unit.squad_loadout.soldiers[index].nickname and restored.role == saved_unit.squad_loadout.soldiers[index].role, "Weapon restoration preserves soldier identity and role")
	var rifle: WeaponSpec = first.squad_fire.soldiers[0].weapon
	var other_rifle: WeaponSpec = first.squad_fire.soldiers[5].weapon
	rifle.ammunition -= 1
	_check(other_rifle != rifle and other_rifle.ammunition == other_rifle.ammunition_start, "Identical saved rifles within one squad remain independent")
	_check(second.squad_fire.soldiers[0].weapon.ammunition == rifle.ammunition_start, "Firing a restored weapon cannot spend another squad's ammunition")
	var resaved: UnitSaveData = first.create_save_data()
	for index: int in range(WEAPON_PATHS.size()):
		_check(resaved.squad_loadout.soldiers[index].weapon_resource_path == WEAPON_PATHS[index], "A second save retains the original weapon reference")
	var embedded_data: SoldierLoadout = match_save.player_units[1].squad_loadout.soldiers[0]
	_check(embedded_data.weapon != null, "Embedded weapons survive disk serialization")
	var embedded: Unit = _restore_unit(match_save.player_units[1])
	_check(embedded.squad_fire.soldiers[0].weapon.name == "Embedded prototype weapon" and embedded.squad_fire.soldiers[0].weapon.range_hexes == 9, "Embedded weapon configuration restores without a source file")
	var next_save: UnitSaveData = embedded.create_save_data()
	_check(next_save.squad_loadout.soldiers[0].weapon_resource_path.is_empty() and next_save.squad_loadout.soldiers[0].weapon != null, "Resaving an anonymous weapon does not reference the prior match file")
	var second_path: String = "user://tests/weapon_reference_second.tres"
	_check(ResourceSaver.save(next_save, second_path) == OK, "Embedded weapons can be saved a second time")
	var reloaded: UnitSaveData = ResourceLoader.load(second_path, "", ResourceLoader.CACHE_MODE_IGNORE) as UnitSaveData
	var restored_again: Unit = _restore_unit(reloaded)
	_check(restored_again.squad_fire.soldiers[0].weapon.name == "Embedded prototype weapon", "Repeated embedded weapon saves retain their definition")


func _test_legacy_loadouts_and_path_copies() -> void:
	var mg: WeaponSpec = load("res://resources/weapons/mg34.tres") as WeaponSpec
	var loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	loadout.soldiers.append(_soldier_loadout(mg, "Legacy MG"))
	loadout.soldiers.append(_soldier_loadout(null, "Old save with no reference"))
	var legacy: UnitSaveData = UnitSaveData.new()
	legacy.squad_loadout = loadout
	var path: String = "user://tests/weapon_reference_legacy.tres"
	_check(ResourceSaver.save(legacy, path) == OK, "Older direct-resource loadouts remain serializable")
	var loaded: UnitSaveData = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as UnitSaveData
	var restored: Unit = _restore_unit(loaded)
	_check(restored.squad_fire.soldiers[0].weapon.name == mg.name, "Older loadouts with a direct weapon reference still restore")
	_check(restored.squad_fire.soldiers[1].weapon.source_resource_path == restored.default_rifle.resource_path, "Older saves with no weapon reference retain the existing default-rifle fallback")
	var path_only: SoldierLoadout = _soldier_loadout(null, "Path-only MG")
	path_only.weapon_resource_path = mg.resource_path
	var copied: SoldierLoadout = path_only.copy_runtime()
	_check(copied.weapon_resource_path == mg.resource_path, "Loadout copies preserve saved weapon paths")
	var path_loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	path_loadout.soldiers.append(copied)
	var from_path: Unit = _create_unit(path_loadout)
	_check(from_path.squad_fire.soldiers[0].weapon.name == mg.name, "Path-only loadouts restore the referenced weapon")
	# The scene's built-in fallback weapon must also survive as an embedded spec.
	var scene_unit: Unit = (load("res://scenes/game/units/unit.tscn") as PackedScene).instantiate()
	var built_in_loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	built_in_loadout.soldiers.append(_soldier_loadout(scene_unit.default_mg, "Built-in weapon"))
	var built_in: Unit = _create_unit(built_in_loadout)
	var built_in_save: UnitSaveData = built_in.create_save_data()
	var built_in_path: String = "user://tests/weapon_reference_builtin.tres"
	_check(ResourceSaver.save(built_in_save, built_in_path) == OK, "Built-in weapons can be saved")
	var loaded_builtin: UnitSaveData = ResourceLoader.load(built_in_path, "", ResourceLoader.CACHE_MODE_IGNORE) as UnitSaveData
	_check(loaded_builtin.squad_loadout.soldiers[0].weapon != null, "Built-in weapons have an embedded saved definition")
	var restored_builtin: Unit = _restore_unit(loaded_builtin)
	_check(restored_builtin.squad_fire.soldiers[0].weapon.name == scene_unit.default_mg.name, "Built-in weapon definitions restore")
	scene_unit.free()


func _test_recovered_support_weapon() -> void:
	var mg: WeaponSpec = load("res://resources/weapons/mg34.tres") as WeaponSpec
	var rifle: WeaponSpec = load("res://resources/weapons/kar98.tres") as WeaponSpec
	var loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	loadout.soldiers = [_soldier_loadout(mg, "Original gunner"), _soldier_loadout(rifle, "Replacement")]
	loadout.soldiers[0].role = RankGrades.Role.GUNNER
	loadout.soldiers[1].role = RankGrades.Role.LOADER
	var source: Unit = _create_unit(loadout)
	var gunner: Soldier = source.squad_fire.soldiers[0]
	source.squad_fire.soldiers.erase(gunner)
	source._assign_gunner_and_loader_for_weapon(gunner.weapon)
	var saved: UnitSaveData = source.create_save_data()
	var path: String = "user://tests/weapon_reference_recovered.tres"
	_check(ResourceSaver.save(saved, path) == OK, "Recovered support weapon can be saved")
	var loaded: UnitSaveData = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as UnitSaveData
	var restored: Unit = _restore_unit(loaded)
	_check(restored.squad_fire.soldiers[0].weapon.name == mg.name and restored.squad_fire.soldiers[0].role == RankGrades.Role.GUNNER, "Replacement gunner keeps the recovered weapon after reloading")


func _test_missing_weapon_resources() -> void:
	var loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	var missing: SoldierLoadout = _soldier_loadout(null, "Missing source file")
	missing.weapon_resource_path = "res://resources/weapons/does_not_exist.tres"
	var wrong_type: SoldierLoadout = _soldier_loadout(null, "Wrong source type")
	wrong_type.weapon_resource_path = "res://squad_loadout_spec.gd"
	loadout.soldiers = [missing, wrong_type]
	var restored: Unit = _create_unit(loadout)
	for soldier: Soldier in restored.squad_fire.soldiers:
		_check(soldier.weapon.source_resource_path == restored.default_rifle.resource_path, "Missing or invalid references retain the configured fallback")


func _soldier_loadout(weapon: WeaponSpec, nickname: String) -> SoldierLoadout:
	var result: SoldierLoadout = SoldierLoadout.new()
	result.weapon = weapon
	result.nickname = nickname
	return result


func _create_unit(loadout: SquadLoadoutSpec) -> Unit:
	var unit: Unit = _empty_unit()
	unit.squad_loadout = loadout
	unit._setup_runtime_soldiers(loadout)
	soldiers_created.append_array(unit.squad_fire.soldiers)
	return unit


func _restore_unit(data: UnitSaveData) -> Unit:
	var unit: Unit = _empty_unit()
	unit.apply_save_data(data)
	soldiers_created.append_array(unit.squad_fire.soldiers)
	return unit


func _empty_unit() -> Unit:
	var unit: Unit = Unit.new()
	unit.scene_file_path = "res://scenes/game/units/unit.tscn"
	unit.default_rifle = load("res://resources/weapons/m1_garand.tres") as WeaponSpec
	unit.squad_fire = SquadFireController.new()
	unit.add_child(unit.squad_fire)
	unit.ui = SaveUiUnderTest.new()
	unit.add_child(unit.ui)
	units.append(unit)
	return unit


func _finish() -> void:
	for soldier: Soldier in soldiers_created:
		var tasks: Array[SoldierTask] = [
			soldier.setup_weapon_task, soldier.aquire_target_task, soldier.reload_task,
			soldier.fire_weapon_task, soldier.assist_task, soldier.close_combat_task,
		]
		for task: SoldierTask in tasks:
			task.free()
	for unit: Unit in units:
		unit.free()
	print("Weapon save regression failures: ", failures)
	get_tree().quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
