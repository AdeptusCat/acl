extends Node

# Run with: godot --headless --path . tests/weapon_state_regression.tscn
class AmmoUiUnderTest extends UnitUi:
	var ammunition_left: int = -1

	func set_ammunition_left(ammo: int) -> void:
		ammunition_left = ammo

	func set_members_alive(_members_alive: int) -> void:
		pass


var failures: int = 0
var units: Array[Unit] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_personal_weapons()
	_test_default_weapon()
	_test_mortar_ammunition()
	_test_support_weapon_transfer()
	for unit: Unit in units:
		for soldier: Soldier in unit.squad_fire.soldiers:
			_free_tasks(soldier)
		unit.free()
	units.clear()
	print("Weapon state regression failures: ", failures)
	get_tree().quit(failures)


func _test_personal_weapons() -> void:
	var source: WeaponSpec = load("res://resources/weapons/springfield_1903_riflegrenade.tres") as WeaponSpec
	var cached: WeaponSpec = load(source.resource_path) as WeaponSpec
	_check(source == cached, "Test squads use the same cached definition")
	var source_ammunition: int = source.ammunition
	var source_grenade_loaded: bool = source.riflegrenade_loaded
	var loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	loadout.soldiers = [_loadout(source), _loadout(source)]
	var first: Unit = _create_unit(loadout)
	var second: Unit = _create_unit(loadout)
	var weapon: WeaponSpec = first.squad_fire.soldiers[0].weapon
	var squadmate_weapon: WeaponSpec = first.squad_fire.soldiers[1].weapon
	var other_weapon: WeaponSpec = second.squad_fire.soldiers[0].weapon
	_check(weapon != source, "Runtime weapon is separate from its definition")
	_check(weapon != squadmate_weapon, "Personal weapons within a squad are independent")
	_check(weapon != other_weapon, "Weapons across squads are independent")
	_check(weapon.ammunition == source.ammunition_start, "New weapon starts with configured ammunition")
	_check(not weapon.riflegrenade_loaded, "New weapon starts without a loaded rifle grenade")
	_check(weapon.snd_shot == source.snd_shot, "Immutable audio assets remain shared")
	_check(weapon.range_hexes == source.range_hexes, "Weapon configuration is retained")
	weapon.ammunition -= 3
	weapon.riflegrenade_loaded = true
	_check(squadmate_weapon.ammunition == source.ammunition_start, "Spending ammunition leaves squadmates unchanged")
	_check(other_weapon.ammunition == source.ammunition_start, "Spending ammunition leaves other squads unchanged")
	_check(not squadmate_weapon.riflegrenade_loaded and not other_weapon.riflegrenade_loaded, "Loading a grenade affects only its weapon")
	_create_unit(loadout)
	_check(weapon.ammunition == source.ammunition_start - 3, "Later squad setup does not refill existing weapons")
	_check(weapon.riflegrenade_loaded, "Later squad setup does not alter loaded grenades")
	_check(source.ammunition == source_ammunition, "Runtime setup and firing do not mutate definition ammunition")
	_check(source.riflegrenade_loaded == source_grenade_loaded, "Runtime setup does not mutate definition grenade state")
	_check(first.squad_fire.soldiers[0].create_save_data().weapon_resource_path == source.resource_path, "Existing save code retains the source asset path")


func _test_default_weapon() -> void:
	var source: WeaponSpec = load("res://resources/weapons/m1_garand.tres") as WeaponSpec
	var loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	loadout.soldiers = [_loadout(null), _loadout(null)]
	var unit: Unit = _create_unit(loadout, source)
	var first: WeaponSpec = unit.squad_fire.soldiers[0].weapon
	var second: WeaponSpec = unit.squad_fire.soldiers[1].weapon
	_check(first != source and first != second, "Fallback rifles also have independent runtime state")
	first.ammunition -= 1
	_check(second.ammunition == source.ammunition_start, "Fallback rifle ammunition is independent")


func _test_mortar_ammunition() -> void:
	var source: WeaponSpec = load("res://resources/weapons/m2_60mm_mortar.tres") as WeaponSpec
	var loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	loadout.soldiers = [_loadout(source, RankGrades.Role.GUNNER)]
	var first: Unit = _create_unit(loadout)
	var second: Unit = _create_unit(loadout)
	var weapon: WeaponSpec = first.squad_fire.soldiers[0].weapon
	weapon.ammunition -= 1
	_check(second.squad_fire.soldiers[0].weapon.ammunition == source.ammunition_start, "Mortar teams have independent ammunition")
	var ui: AmmoUiUnderTest = first.ui as AmmoUiUnderTest
	_check(ui.ammunition_left == source.ammunition_start, "Mortar UI receives initial runtime ammunition")


func _test_support_weapon_transfer() -> void:
	var source: WeaponSpec = load("res://resources/weapons/mg34.tres") as WeaponSpec
	var rifle: WeaponSpec = load("res://resources/weapons/kar98.tres") as WeaponSpec
	var loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	loadout.soldiers = [
		_loadout(source, RankGrades.Role.GUNNER),
		_loadout(rifle, RankGrades.Role.LOADER),
		_loadout(rifle),
	]
	var first: Unit = _create_unit(loadout)
	var second: Unit = _create_unit(loadout)
	var old_gunner: Soldier = first.squad_fire.soldiers[0]
	var replacement: Soldier = first.squad_fire.soldiers[1]
	var weapon: WeaponSpec = old_gunner.weapon
	weapon.ammunition -= 8
	weapon.is_setup = true
	first.squad_fire.soldiers.erase(old_gunner)
	first._assign_gunner_and_loader_for_weapon(weapon)
	_check(replacement.role == RankGrades.Role.GUNNER, "Loader takes over the dropped support weapon")
	_check(replacement.weapon == weapon, "Re-crewing preserves the same physical weapon")
	_check(replacement.weapon.ammunition == source.ammunition_start - 8, "Re-crewing does not refill spent ammunition")
	_check(replacement.weapon.is_setup, "Re-crewing retains existing weapon state")
	_check(second.squad_fire.soldiers[0].weapon.ammunition == source.ammunition_start, "Other support weapons remain independent")
	_check(replacement.create_save_data().weapon_resource_path == source.resource_path, "Transferred weapons retain their source asset path")
	_free_tasks(old_gunner)


func _loadout(weapon: WeaponSpec, role: RankGrades.Role = RankGrades.Role.SOLDIER) -> SoldierLoadout:
	var result: SoldierLoadout = SoldierLoadout.new()
	result.weapon = weapon
	result.role = role
	return result


func _create_unit(loadout: SquadLoadoutSpec, default_weapon: WeaponSpec = null) -> Unit:
	var unit: Unit = Unit.new()
	unit.squad_fire = SquadFireController.new()
	unit.add_child(unit.squad_fire)
	unit.ui = AmmoUiUnderTest.new()
	unit.add_child(unit.ui)
	unit.default_rifle = default_weapon
	unit._setup_runtime_soldiers(loadout)
	units.append(unit)
	return unit


func _free_tasks(soldier: Soldier) -> void:
	var tasks: Array[SoldierTask] = [
		soldier.setup_weapon_task, soldier.aquire_target_task, soldier.reload_task,
		soldier.fire_weapon_task, soldier.assist_task, soldier.close_combat_task,
	]
	for task: SoldierTask in tasks:
		task.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
