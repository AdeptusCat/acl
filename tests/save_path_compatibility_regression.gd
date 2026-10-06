extends Node

# These fixtures retain the script paths written before the folder refactor.
const WEAPON_PATHS: Array[String] = [
	"res://resources/weapons/m1_garand.tres",
	"res://resources/weapons/mp40.tres",
	"res://resources/weapons/mg34.tres",
	"res://resources/weapons/m2_60mm_mortar.tres",
	"res://resources/weapons/m1a1_bazooka.tres",
	"res://resources/weapons/m1_garand.tres",
]

var failures: int = 0


func _ready() -> void:
	var match_save: Resource = ResourceLoader.load(
		"res://tests/fixtures/legacy_weapon_match.tres", "", ResourceLoader.CACHE_MODE_IGNORE
	)
	_check(match_save is MatchSaveData, "Pre-refactor match keeps its resource type")
	if match_save is MatchSaveData:
		_verify_match(match_save as MatchSaveData)
		_check(DirAccess.make_dir_recursive_absolute("user://tests") == OK, "Create isolated round-trip directory")
		var save_path: String = "user://tests/legacy_match_roundtrip.tres"
		_check(ResourceSaver.save(match_save, save_path) == OK, "Legacy match can be saved again")
		var roundtrip: Resource = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		_check(roundtrip is MatchSaveData, "Resaved legacy match keeps its resource type")
		if roundtrip is MatchSaveData:
			_verify_match(roundtrip as MatchSaveData)

	var unit_save: Resource = load("res://tests/fixtures/legacy_casualty_unit.tres")
	_check(unit_save is UnitSaveData, "Pre-refactor casualty unit keeps its resource type")
	if unit_save is UnitSaveData:
		var data: UnitSaveData = unit_save as UnitSaveData
		_check(data.casualty_records.size() == 1, "Legacy unit retains casualty history")
		if data.casualty_records.size() == 1:
			var record: CasualtyRecord = data.casualty_records[0]
			_check(record.soldier_name == "Recorded soldier" and record.unit_name == "HistoryAlpha", "Legacy casualty identity is retained")
			_check(record.equipment != null and record.equipment.ammunition == 25 and record.equipment.jammed, "Legacy casualty equipment is retained")

	var soldier_save: Resource = load("res://tests/fixtures/legacy_soldier.tres")
	_check(soldier_save is SoldierSaveData, "Legacy soldier resource keeps its type")
	if soldier_save is SoldierSaveData:
		var data: SoldierSaveData = soldier_save as SoldierSaveData
		_check(data.soldier_id == 42 and data.soldier_name == "Legacy soldier", "Legacy soldier identity is retained")
		_check(data.weapon_resource_path == WEAPON_PATHS[0] and data.rounds_in_mag == 3 and data.jammed, "Legacy soldier weapon state is retained")
		_check(is_equal_approx(data.base_attack, 1.75) and is_equal_approx(data.base_defense, 1.25), "Legacy soldier combat values are retained")

	print("Save path compatibility regression failures: ", failures)
	get_tree().quit(failures)


func _verify_match(data: MatchSaveData) -> void:
	_check(data.player_units.size() == 2, "Legacy match retains both unit rosters")
	if data.player_units.size() != 2:
		return
	var first: UnitSaveData = data.player_units[0]
	_check(first.unit_scene_path == "res://scenes/game/units/unit.tscn", "Saved unit scene path remains valid")
	_check(first.squad_loadout != null, "Legacy squad retains its loadout type")
	if first.squad_loadout == null:
		return
	_check(first.squad_loadout.soldiers.size() == WEAPON_PATHS.size(), "Legacy loadout retains every soldier")
	if first.squad_loadout.soldiers.size() != WEAPON_PATHS.size():
		return
	for index: int in range(WEAPON_PATHS.size()):
		var soldier: SoldierLoadout = first.squad_loadout.soldiers[index]
		_check(soldier.nickname == "Weapon %d" % index, "Legacy soldier nickname is retained")
		var weapon: WeaponSpec = soldier.resolve_weapon()
		_check(weapon != null and weapon.resource_path == WEAPON_PATHS[index], "Legacy weapon resolves without fallback")
	var custom: SquadLoadoutSpec = data.player_units[1].squad_loadout
	_check(custom != null and custom.soldiers.size() == 1, "Legacy embedded loadout survives")
	if custom != null and custom.soldiers.size() == 1:
		var weapon: WeaponSpec = custom.soldiers[0].resolve_weapon()
		_check(weapon != null and weapon.name == "Embedded prototype weapon" and weapon.range_hexes == 9, "Legacy embedded weapon retains its definition")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
