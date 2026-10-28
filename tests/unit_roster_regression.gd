extends Node

# Run with: godot --headless --path . tests/unit_roster_regression.tscn
class UnitUnderTest extends Unit:
	var elimination_count: int = 0
	var forced_casualty_indexes: Array[int] = []

	func get_unique_random_ints(n: int, maximum: int) -> Array[int]:
		if not forced_casualty_indexes.is_empty():
			return forced_casualty_indexes.duplicate()
		return super.get_unique_random_ints(n, maximum)

	func _set_combat_ineffective() -> void:
		elimination_count += 1
		alive = false


class RosterUiUnderTest extends UnitUi:
	var displayed_members: int = -1
	var events: Array[String] = []
	var displayed_losses: Array[int] = []

	func set_members_alive(count: int) -> void:
		displayed_members = count
		events.append("members:%d" % count)

	func show_casualty(count: int = 1) -> void:
		events.append("casualty")
		displayed_losses.append(count)

	func set_loadout(_soldiers: Array[Soldier]) -> void:
		events.append("loadout:%d" % _soldiers.size())

	func set_leadership_rank(_grade: int) -> void:
		pass


class WeaponAudioUnderTest extends WeaponAudio:
	func stop_mg_loop(_weapon: WeaponSpec, _position: Vector2, _owner_id: int, _unit: Node2D) -> void:
		pass


var failures: int = 0
var units: Array[UnitUnderTest] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Debug.no_damage = false
	_test_initial_strength()
	_test_seeded_hq_casualty()
	_test_stale_cached_counts()
	_test_casualty_bounds()
	_test_specific_and_ranged_casualties()
	_test_runtime_leader_lookup()
	_test_saved_roster_initialization()
	_test_runtime_phase_order()
	_test_specific_role_replacement()
	_test_secondary_role_replacement()
	for unit: UnitUnderTest in units:
		unit.free()
	units.clear()
	print("Unit roster regression failures: ", failures)
	get_tree().quit(failures)


func _test_initial_strength() -> void:
	for legacy_size: int in [0, 3, 12]:
		var unit: UnitUnderTest = _create_unit(5, legacy_size)
		_check_strength(unit, 5, "Initial strength ignores legacy roster size %d" % legacy_size)
		_check(unit.original_size == 5, "Initial baseline comes from runtime soldiers")
		_check(unit.casualties_taken == 0, "New roster has no casualties")
	var empty: UnitUnderTest = _create_unit(0, 12)
	_check_strength(empty, 0, "Empty runtime roster")
	_check(empty.original_size == 0, "Empty roster has zero starting strength")


func _test_seeded_hq_casualty() -> void:
	var unit: UnitUnderTest = _create_unit(5, 12)
	seed(0)
	unit._on_incoming_fire_effect(1, 0.0, 0.0, null)
	_check_strength(unit, 4, "Seed 0 removes exactly one of five HQ soldiers")
	_check(unit.casualties_taken == 1 and unit.squad_fire.casualties.size() == 1, "HQ records exactly one casualty")
	_check(unit.original_size == 5, "Casualties retain the initial strength baseline")
	_check(is_equal_approx(unit.combat_stats._get_base_strength(), 0.8), "Combat strength reflects four of five soldiers")
	_check(unit.loadouts.size() == 12, "Casualties leave editor loadouts unchanged")
	_check(unit.squad_loadout.soldiers.size() == 5, "Casualties leave the source squad loadout unchanged")
	for expected_size: int in [3, 2, 1]:
		unit._apply_casualties(1)
		_check_strength(unit, expected_size, "Repeated casualties always remove one available soldier")
		_check(unit.casualties_taken == 5 - expected_size, "Casualty count matches accumulated runtime losses")


func _test_stale_cached_counts() -> void:
	var too_high: UnitUnderTest = _create_unit(5, 12)
	too_high.members_alive = 100
	seed(0)
	too_high._apply_casualties(2)
	_check_strength(too_high, 3, "Selection ignores an inflated cached count")
	var too_low: UnitUnderTest = _create_unit(5, 1)
	too_low.members_alive = 1
	too_low._apply_casualties(3)
	_check_strength(too_low, 2, "Selection ignores an undersized cached count")


func _test_casualty_bounds() -> void:
	var unit: UnitUnderTest = _create_unit(3, 12)
	unit._apply_casualties(0)
	unit._apply_casualties(-1)
	_check_strength(unit, 3, "Zero and negative casualty requests do nothing")
	_check(unit.casualties_taken == 0, "No-op requests do not record losses")
	_check(is_zero_approx(unit.combat_stats.recent_casualty_shock), "No-op requests do not cause casualty shock")
	var ui: RosterUiUnderTest = unit.ui as RosterUiUnderTest
	_check(ui.displayed_losses.is_empty(), "No-op requests do not show a casualty cue")
	unit._apply_casualties(99)
	_check_strength(unit, 0, "Oversized request removes only the available soldiers")
	_check(unit.casualties_taken == 3, "Oversized request records actual losses")
	_check(is_equal_approx(unit.combat_stats.recent_casualty_shock, 0.36), "Casualty shock uses actual losses")
	_check(unit.elimination_count == 1, "Final casualty eliminates the unit once")
	_check(ui.displayed_losses == [3], "Elimination shows only the actual number lost, once")
	unit._apply_casualties(1)
	_check(unit.elimination_count == 1 and unit.casualties_taken == 3, "Empty roster does not receive another casualty or elimination")
	_check(ui.displayed_losses == [3], "An empty roster cannot show another casualty cue")


func _test_specific_and_ranged_casualties() -> void:
	var unit: UnitUnderTest = _create_unit(5, 0)
	var casualty: Soldier = unit.squad_fire.soldiers[2]
	_check(not unit.apply_specific_casualty(casualty), "One specific casualty does not eliminate the squad")
	_check_strength(unit, 4, "Specific casualty updates runtime strength")
	_check(unit.casualties_taken == 1, "Specific casualty updates the casualty counter")
	unit._on_incoming_fire_effect(1, 0.0, 0.0, null)
	_check_strength(unit, 3, "Ranged casualty following a specific casualty")
	_check(unit.casualties_taken == 2, "Mixed casualty paths share the same loss count")
	var shock_before: float = unit.combat_stats.recent_casualty_shock
	_check(not unit.apply_specific_casualty(casualty), "Repeated specific casualty is ignored")
	_check(unit.casualties_taken == 2 and unit.combat_stats.recent_casualty_shock == shock_before, "Repeated casualty does not duplicate loss accounting")
	var ui: RosterUiUnderTest = unit.ui as RosterUiUnderTest
	_check(ui.displayed_losses == [1, 1], "Specific and ranged losses each show one cue without duplicates")
	var last: UnitUnderTest = _create_unit(1, 12)
	_check(last.apply_specific_casualty(last.squad_fire.soldiers[0]), "Last specific casualty reports elimination to the caller")
	_check_strength(last, 0, "Last specific casualty leaves zero strength")
	_check(last.casualties_taken == 1, "Last specific casualty remains accounted for")
	_check((last.ui as RosterUiUnderTest).displayed_losses == [1], "The final specific casualty still displays a loss cue")


func _test_runtime_leader_lookup() -> void:
	var unit: UnitUnderTest = _create_unit(5, 1)
	unit.squad_fire.soldiers[4].rank_grade = RankGrades.Grade.PLATOON_LEADER
	_check(unit._highest_grade_from_runtime() == RankGrades.Grade.PLATOON_LEADER, "Leader lookup includes soldiers beyond the legacy roster")


func _test_saved_roster_initialization() -> void:
	var unit: UnitUnderTest = _create_unit(5, 12)
	unit._apply_casualties(1)
	var data: UnitSaveData = UnitSaveData.new()
	data.team = Globals.Team.ALLIES
	data.squad_loadout = _make_loadout(3)
	unit.apply_save_data(data)
	_check_strength(unit, 3, "Saved roster updates displayed and cached strength")
	_check(unit.original_size == 3, "Saved roster sets the new starting baseline")
	_check(unit.casualties_taken == 0 and unit.squad_fire.casualties.is_empty(), "Replacing the roster clears previous loss accounting")
	_check(unit.loadouts.size() == 12, "Saved roster initialization leaves editor loadouts unchanged")


func _create_unit(runtime_size: int, legacy_size: int) -> UnitUnderTest:
	var unit: UnitUnderTest = UnitUnderTest.new()
	unit.squad_fire = SquadFireController.new()
	unit.add_child(unit.squad_fire)
	unit.ui = RosterUiUnderTest.new()
	unit.add_child(unit.ui)
	unit.stress_system = StressController.new()
	unit.stress_system.name = "UnitStressController"
	unit.add_child(unit.stress_system)
	unit.combat_stats = UnitCombatStats.new()
	unit.combat_stats.unit = unit
	unit.add_child(unit.combat_stats)
	unit.weapon_audio = WeaponAudioUnderTest.new()
	unit.add_child(unit.weapon_audio)
	unit.leader_aura = LeaderAura.new()
	unit.add_child(unit.leader_aura)
	unit.loadouts = _make_loadout(legacy_size).soldiers
	unit.members_alive = legacy_size
	unit.original_size = legacy_size
	unit.squad_loadout = _make_loadout(runtime_size)
	unit._setup_runtime_soldiers(unit.squad_loadout)
	units.append(unit)
	return unit


func _test_runtime_phase_order() -> void:
	seed(774)
	var expected: Array[float] = []
	for index: int in range(5):
		expected.append(randf_range(0.0, 3.0))
	var expected_tail: float = randf()
	seed(774)
	var unit: UnitUnderTest = _create_unit(5, 0)
	for index: int in range(5):
		_check(unit.squad_fire.soldiers[index].cadence_phase_s == expected[index], "Runtime phases consume RNG in roster order")
	_check(randf() == expected_tail, "Roster construction preserves RNG continuation")


func _test_specific_role_replacement() -> void:
	var unit: UnitUnderTest = _create_unit(6, 0)
	var leader: Soldier = unit.squad_fire.soldiers[0]
	var assistant: Soldier = unit.squad_fire.soldiers[1]
	var gunner: Soldier = unit.squad_fire.soldiers[2]
	var loader: Soldier = unit.squad_fire.soldiers[3]
	leader.role = RankGrades.Role.SQUAD_LEADER
	assistant.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
	gunner.role = RankGrades.Role.GUNNER
	loader.role = RankGrades.Role.LOADER
	var definition: WeaponSpec = load("res://resources/weapons/mg34.tres") as WeaponSpec
	var gun: WeaponSpec = definition.create_runtime()
	gun.ammunition -= 7
	gun.is_setup = true
	gunner.weapon = gun
	var ui: RosterUiUnderTest = unit.ui as RosterUiUnderTest
	ui.events.clear()
	unit.soldiers_changed.connect(func() -> void:
		ui.events.append("signal:%d" % unit.squad_fire.soldiers.size())
	)
	unit.apply_specific_casualty(leader)
	_check(assistant.role == RankGrades.Role.SQUAD_LEADER, "Assistant takes over a specific leader casualty")
	_check(ui.events == ["members:5", "casualty", "signal:5", "loadout:5"], "Specific casualty publishes the updated roster before loadout presentation")
	unit.apply_specific_casualty(gunner)
	_check(loader.role == RankGrades.Role.GUNNER and loader.weapon == gun, "Specific gunner loss transfers the physical weapon to the loader")
	_check(gun.ammunition == definition.ammunition_start - 7 and gun.is_setup, "Casualty recrewing retains ammunition and setup")
	_check(unit.squad_fire.soldiers[unit.squad_fire.soldiers.size() - 1].role == RankGrades.Role.LOADER, "Ordinary soldier fills the loader vacancy")


func _test_secondary_role_replacement() -> void:
	for specific: bool in [true, false]:
		var unit: UnitUnderTest = _create_unit(8, 0)
		var roster: Array[Soldier] = unit.squad_fire.soldiers.duplicate()
		roster[0].role = RankGrades.Role.SQUAD_LEADER
		roster[1].role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
		roster[2].role = RankGrades.Role.GUNNER
		roster[2].weapon = (load("res://resources/weapons/mg34_heavy.tres") as WeaponSpec).create_runtime()
		roster[3].role = RankGrades.Role.LOADER
		roster[4].role = RankGrades.Role.ASSISTANT
		roster[5].weapon = (load("res://resources/weapons/kar98_riflegrenade.tres") as WeaponSpec).create_runtime()
		var replacement_weapon: WeaponSpec = roster[6].weapon
		var replacement_grade: RankGrades.Grade = roster[6].rank_grade
		_apply_role_casualty(unit, roster[1], specific)
		_check(roster[6].role == RankGrades.Role.ASSISTANT_SQUAD_LEADER, "An ordinary soldier replaces the assistant squad leader on both casualty paths")
		_check(roster[6].weapon == replacement_weapon and roster[6].rank_grade == replacement_grade, "Assistant leader replacement preserves the soldier's weapon and rank")
		_apply_role_casualty(unit, roster[4], specific)
		_check(roster[7].role == RankGrades.Role.ASSISTANT, "An ordinary soldier replaces a weapon assistant on both casualty paths")
		_check(roster[5].role == RankGrades.Role.SOLDIER and roster[3].role == RankGrades.Role.LOADER, "Secondary replacements preserve rifle grenadiers and essential crew")
		_apply_role_casualty(unit, roster[6], specific)
		_check(not unit._has_role(RankGrades.Role.ASSISTANT_SQUAD_LEADER), "An unfillable vacancy does not take a specialist or weapon assistant")

		var succession: UnitUnderTest = _create_unit(4, 0)
		var assistant: Soldier = succession.squad_fire.soldiers[1]
		var successor: Soldier = succession.squad_fire.soldiers[2]
		succession.squad_fire.soldiers[0].role = RankGrades.Role.SQUAD_LEADER
		assistant.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
		_apply_role_casualty(succession, succession.squad_fire.soldiers[0], specific)
		_check(assistant.role == RankGrades.Role.SQUAD_LEADER and successor.role == RankGrades.Role.ASSISTANT_SQUAD_LEADER, "Promoting the assistant leader also fills the vacated assistant position")

		var crew: UnitUnderTest = _create_unit(4, 0)
		var helper: Soldier = crew.squad_fire.soldiers[2]
		var reserve: Soldier = crew.squad_fire.soldiers[3]
		crew.squad_fire.soldiers[0].role = RankGrades.Role.GUNNER
		crew.squad_fire.soldiers[0].weapon = (load("res://resources/weapons/mg34_heavy.tres") as WeaponSpec).create_runtime()
		crew.squad_fire.soldiers[1].role = RankGrades.Role.LOADER
		helper.role = RankGrades.Role.ASSISTANT
		_apply_role_casualty(crew, crew.squad_fire.soldiers[1], specific)
		_check(helper.role == RankGrades.Role.LOADER and reserve.role == RankGrades.Role.ASSISTANT, "An assistant promoted to loader is replaced after the essential crew is filled")

	var batch: UnitUnderTest = _create_unit(8, 0)
	batch.squad_fire.soldiers[0].role = RankGrades.Role.GUNNER
	batch.squad_fire.soldiers[0].weapon = (load("res://resources/weapons/mg34_heavy.tres") as WeaponSpec).create_runtime()
	batch.squad_fire.soldiers[1].role = RankGrades.Role.LOADER
	batch.squad_fire.soldiers[2].role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
	batch.squad_fire.soldiers[3].role = RankGrades.Role.ASSISTANT
	batch.squad_fire.soldiers[4].role = RankGrades.Role.ASSISTANT
	batch.forced_casualty_indexes = [2, 3, 4]
	batch._apply_casualties(3)
	_check(batch._has_role(RankGrades.Role.ASSISTANT_SQUAD_LEADER) and UnitCasualtyHandler.secondary_role_counts(batch).y == 2, "A batch casualty restores all lost secondary positions when reserves suffice")

	var depleted: UnitUnderTest = _create_unit(5, 0)
	depleted.squad_fire.soldiers[0].role = RankGrades.Role.SQUAD_LEADER
	depleted.squad_fire.soldiers[1].role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
	depleted.squad_fire.soldiers[2].role = RankGrades.Role.GUNNER
	depleted.squad_fire.soldiers[2].weapon = (load("res://resources/weapons/mg34.tres") as WeaponSpec).create_runtime()
	depleted.squad_fire.soldiers[3].role = RankGrades.Role.LOADER
	depleted.forced_casualty_indexes = [1, 3]
	depleted._apply_casualties(2)
	_check(depleted._has_role(RankGrades.Role.LOADER) and not depleted._has_role(RankGrades.Role.ASSISTANT_SQUAD_LEADER), "The final reserve fills an essential loader vacancy before an assistant leader vacancy")

	var ordinary: UnitUnderTest = _create_unit(3, 0)
	ordinary._apply_casualties(1)
	_check(UnitCasualtyHandler.secondary_role_counts(ordinary) == Vector2i.ZERO, "Casualties do not invent secondary positions absent from the squad")


func _apply_role_casualty(unit: UnitUnderTest, casualty: Soldier, specific: bool) -> void:
	if specific:
		unit.apply_specific_casualty(casualty)
	else:
		unit.forced_casualty_indexes = [unit.squad_fire.soldiers.find(casualty)]
		unit._apply_casualties(1)


func _make_loadout(size: int) -> SquadLoadoutSpec:
	var result: SquadLoadoutSpec = SquadLoadoutSpec.new()
	var rifle: WeaponSpec = load("res://resources/weapons/m1_garand.tres") as WeaponSpec
	for index: int in range(size):
		var soldier: SoldierLoadout = SoldierLoadout.new()
		soldier.nickname = "Soldier %d" % index
		soldier.weapon = rifle
		result.soldiers.append(soldier)
	return result


func _check_strength(unit: UnitUnderTest, expected: int, context: String) -> void:
	_check(unit.squad_fire.soldiers.size() == expected, context + ": runtime roster")
	_check(unit.members_alive == expected, context + ": cached count")
	var ui: RosterUiUnderTest = unit.ui as RosterUiUnderTest
	_check(ui.displayed_members == expected, context + ": displayed count")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
