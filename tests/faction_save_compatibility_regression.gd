extends Node

var failures: int = 0


func _ready() -> void:
	# Exercise raw legacy paths too: export may convert the fixture to binary.
	var old_german: SquadLoadoutSpec = ResourceLoader.load("res://resources/squads/german/rifle_squad.tres") as SquadLoadoutSpec
	var old_american: SquadLoadoutSpec = ResourceLoader.load("res://resources/squads/us/rifle_squad.tres") as SquadLoadoutSpec
	var old_soldier: SoldierLoadout = ResourceLoader.load("res://resources/soldiers/us/rifleman.tres") as SoldierLoadout
	_check(old_german != null and old_german.soldiers.size() == 10, "The legacy German resource path resolves directly")
	_check(old_american != null and old_american.soldiers.size() == 12, "The legacy American resource path resolves directly")
	_check(old_soldier != null and old_soldier.resolve_weapon() != null, "The legacy soldier resource path resolves directly")

	var catalogs: SquadsCollection = load("res://resources/squads/team_squad_loadout_catalog.tres") as SquadsCollection
	_check(catalogs != null, "Team catalogs load after the faction directory changes")
	if catalogs != null:
		var german: Squads = catalogs.get_squad(Globals.Team.AXIS)
		var american: Squads = catalogs.get_squad(Globals.Team.ALLIES)
		_check(german.resource_path == "res://resources/squads/germany/squad_loadout_catalog.tres", "German catalog uses the canonical folder")
		_check(american.resource_path == "res://resources/squads/united_states/squad_loadout_catalog.tres", "American catalog uses the canonical folder")
		_check(german.get_squad(Globals.SquadType.Rifle).soldiers.size() == 10, "German authored rifle roster is preserved")
		_check(american.get_squad(Globals.SquadType.Rifle).soldiers.size() == 12, "American authored rifle roster is preserved")

	# This fixture was saved before the faction directory changes and has no resource UIDs.
	var resource: Resource = ResourceLoader.load(
		"res://tests/fixtures/legacy_faction_match.tres", "", ResourceLoader.CACHE_MODE_IGNORE
	)
	_check(resource is MatchSaveData, "A match referencing old faction folders retains its resource type")
	if resource is MatchSaveData:
		var data: MatchSaveData = resource as MatchSaveData
		_verify_match(data)
		var directory_error: Error = DirAccess.make_dir_recursive_absolute("user://tests")
		_check(directory_error == OK, "Create the round-trip save directory")
		var path: String = "user://tests/faction_match_roundtrip.tres"
		_check(ResourceSaver.save(data, path) == OK, "The legacy faction match can be saved again")
		var roundtrip: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		_check(roundtrip is MatchSaveData, "The resaved faction match retains its resource type")
		if roundtrip is MatchSaveData:
			_verify_match(roundtrip as MatchSaveData)

	print("Faction save compatibility regression failures: ", failures)
	get_tree().quit(failures)


func _verify_match(data: MatchSaveData) -> void:
	_check(data.match_id == "tests/faction_folder_legacy", "The legacy match retains its identity")
	_check(data.player_units.size() == 2, "The legacy match retains both faction rosters")
	if data.player_units.size() != 2:
		return
	var expected_sizes: Array[int] = [10, 12]
	var expected_weapons: Array[String] = [
		"res://resources/weapons/kar98.tres",
		"res://resources/weapons/m1_garand.tres",
	]
	for index: int in range(2):
		var unit: UnitSaveData = data.player_units[index]
		_check(unit.unit_id == index + 20 and unit.team == index, "The saved unit retains its identity and team")
		_check(unit.unit_scene_path == "res://scenes/game/units/unit.tscn", "The saved unit scene remains stable")
		_check(unit.squad_loadout != null, "The old faction loadout resolves")
		if unit.squad_loadout == null:
			continue
		_check(unit.squad_loadout.soldiers.size() == expected_sizes[index], "The old loadout retains its complete roster")
		if unit.squad_loadout.soldiers.is_empty():
			continue
		var rifleman: SoldierLoadout = unit.squad_loadout.soldiers[-1]
		var weapon: WeaponSpec = rifleman.resolve_weapon()
		_check(weapon != null and weapon.resource_path == expected_weapons[index], "The old loadout retains the faction's rifle without fallback")
	var american: UnitSaveData = data.player_units[1]
	_check(american.soldiers.size() == 1, "The direct reference to an old soldier resource is retained")
	if american.soldiers.size() == 1:
		var weapon: WeaponSpec = american.soldiers[0].resolve_weapon()
		_check(weapon != null and weapon.resource_path == expected_weapons[1], "The old soldier folder resolves the original weapon")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
