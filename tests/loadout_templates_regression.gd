extends Node

# The fixture records observable authoring behavior before decomposition, including
# the existing German company-HQ typo. Recording writes user data, never the fixture.
const FIXTURE_PATH: String = "res://tests/fixtures/loadout_templates_baseline.json"
const CATALOG_PATH: String = "res://resources/squads/team_squad_loadout_catalog.tres"
const RECIPES: Array[String] = [
	"make_rifle_squad", "make_platoon_headquarters_squad", "make_company_headquarters_squad",
	"make_light_mg_team", "make_anti_tank_squad", "make_light_mortar_squad", "make_medium_mortar_squad",
]

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var actual: Dictionary = {}
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		for recipe: String in RECIPES:
			for initial_size: int in [0, 14]:
				var key: String = "%d/%s/%d" % [team, recipe, initial_size]
				actual[key] = _observe_recipe(team, recipe, initial_size)
	_test_resize_identity()
	if OS.get_cmdline_user_args().has("--record-baseline"):
		var file: FileAccess = FileAccess.open("user://loadout_templates_baseline.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(actual, "\t"))
		print("Authoring baseline: ", ProjectSettings.globalize_path("user://loadout_templates_baseline.json"))
	else:
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
		var normalized: Dictionary = JSON.parse_string(JSON.stringify(actual))
		for key: String in actual:
			_check(normalized[key] == expected.get(key), "Authoring state and notification order: " + key)
	print("Loadout templates regression failures: ", failures)
	get_tree().quit(failures)


func _observe_recipe(team: Globals.Team, recipe: String, initial_size: int) -> Dictionary:
	var unit: Unit = _create_unit(team)
	unit._resize_loadouts(initial_size)
	var previous: Array[SoldierLoadout] = unit.loadouts.duplicate()
	var notifications: Array[Dictionary] = []
	unit.property_list_changed.connect(func() -> void:
		notifications.append(_snapshot(unit))
	)
	unit.set(recipe, false)
	_check(notifications.is_empty(), "False authoring toggle has no notification")
	unit.set(recipe, true)
	for index: int in range(mini(previous.size(), unit.loadouts.size())):
		_check(previous[index] == unit.loadouts[index], "Resizing preserves existing loadout identity")
	var result: Dictionary = {"state": _snapshot(unit), "notifications": notifications}
	unit.free()
	return result


func _snapshot(unit: Unit) -> Dictionary:
	var soldiers: Array[Dictionary] = []
	for soldier: SoldierLoadout in unit.loadouts:
		var path: String = ""
		var shared_definition: bool = false
		if soldier.weapon != null:
			path = soldier.weapon.resource_path
			shared_definition = soldier.weapon == load(path)
		soldiers.append({
			"name": soldier.nickname, "role": soldier.role, "rank": soldier.rank_grade,
			"key_role": soldier.is_key_role, "weapon": path, "shared_definition": shared_definition,
		})
	var flags: Dictionary = {}
	for recipe: String in RECIPES:
		flags[recipe] = unit.get(recipe)
	var catalog: SquadLoadoutSpec = unit.squads_collection.get_squad(unit.team).get_squad(unit.squad_type)
	return {
		"name": str(unit.name), "team": unit.team, "company": unit.company,
		"platoon": unit.platoon, "squad": unit.squad, "type": unit.squad_type,
		"flags": flags, "catalog_shared": unit.squad_loadout == catalog, "soldiers": soldiers,
	}


func _test_resize_identity() -> void:
	var unit: Unit = _create_unit(Globals.Team.ALLIES)
	unit._resize_loadouts(3)
	var first: SoldierLoadout = unit.loadouts[0]
	var second: SoldierLoadout = unit.loadouts[1]
	_check(first.role == RankGrades.Role.GUNNER and first.weapon == unit.default_mg, "Default first slot is the shared MG definition")
	_check(second.role == RankGrades.Role.LOADER, "Default second slot is the loader")
	unit._resize_loadouts(1)
	_check(unit.loadouts.size() == 1 and unit.loadouts[0] == first, "Shrink keeps retained objects")
	unit._resize_loadouts(3)
	_check(unit.loadouts[0] == first and unit.loadouts[1] != second, "Growth replaces removed objects only")
	unit.free()


func _create_unit(team: Globals.Team) -> Unit:
	var unit: Unit = Unit.new()
	unit.squads_collection = load(CATALOG_PATH) as SquadsCollection
	unit.team = team
	unit.default_rifle = load("res://resources/weapons/m1_garand.tres") as WeaponSpec
	unit.default_mg = load("res://resources/weapons/m1918a1_bar.tres") as WeaponSpec
	unit.company = Unit.Company.C
	unit.platoon = 2
	unit.squad = 3
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
