extends Node

const UNIT_SCENE: PackedScene = preload("res://scenes/game/units/unit.tscn")

var failures: int = 0
var checks: int = 0
var units: Array[Unit] = []
var succession: CommandSuccession
var ground: HexagonTileMapLayer
var notices: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	name = "Main"
	var world: Node = Node.new()
	world.name = "World"
	add_child(world)
	var audio: AudioPool = AudioPool.new()
	audio.name = "AudioPool"
	world.add_child(audio)
	ground = HexagonTileMapLayer.new()
	ground.pathfinding_enabled = false
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	ground.tile_set.tile_size = Vector2i(128, 128)
	add_child(ground)
	LOSHelper.ground_layer = ground
	LOSHelper.los_lookup = {}
	succession = CommandSuccession.new()
	add_child(succession)
	succession.set_process(false)
	succession.company_headquarters_created.connect(func(unit: Unit, _source: Unit) -> void:
		_freeze(unit)
		units.append(unit)
	)
	succession.command_notice.connect(func(team: Globals.Team, title: String, explanation: String) -> void:
		notices.append({"team": team, "title": title, "explanation": explanation})
	)
	Debug.no_damage = false
	_test_local_succession()
	_test_platoon_recovery()
	_test_company_succession()
	_test_repurposed_headquarters()
	_test_unavailable_candidates()
	_test_missing_headquarters()
	_test_destroyed_headquarters()
	await _test_presentation()
	for unit: Unit in units:
		unit.squad_fire.calc.free()
		unit.free()
	succession.free()
	await _test_live_merge()
	print("Command succession checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _unit(type: Globals.SquadType, company: Unit.Company, platoon: int, squad: int, roster: Array[Vector2i]) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.squad_type = type
	unit.company = company
	unit.platoon = platoon
	unit.squad = squad
	add_child(unit)
	_freeze(unit)
	var loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	var rifle: WeaponSpec = load("res://resources/weapons/kar98.tres") as WeaponSpec
	for entry: Vector2i in roster:
		var soldier: SoldierLoadout = SoldierLoadout.new()
		soldier.role = entry.x as RankGrades.Role
		soldier.rank_grade = entry.y as RankGrades.Grade
		soldier.weapon = rifle
		loadout.soldiers.append(soldier)
	unit._setup_runtime_soldiers(loadout)
	unit.combat_stats.setup(unit)
	unit.movement.unit = unit
	unit.action_controller.init(unit, unit.movement, unit.squad_fire, unit.stress_system, unit.ui)
	unit.squad_fire.unit = unit
	unit.squad_fire.stress_controller = unit.stress_system
	unit.add_to_group("units")
	_position(unit, units.size() * 20)
	unit._refresh_leader_aura()
	units.append(unit)
	return unit


func _leader(grade: RankGrades.Grade = RankGrades.Grade.SQUAD_LEADER) -> Vector2i:
	return Vector2i(RankGrades.Role.SQUAD_LEADER, grade)


func _rifleman() -> Vector2i:
	return Vector2i(RankGrades.Role.SOLDIER, RankGrades.Grade.SOLDIER)


func _position(unit: Unit, distance: int) -> void:
	unit.current_cube = Vector3i(distance, -distance, 0)
	unit.current_hex = ground.cube_to_map(unit.current_cube)
	unit.is_moving = false


func _test_local_succession() -> void:
	var hq: Unit = _unit(Globals.SquadType.COMPANY_HEADQUARTERS, Unit.Company.A, 0, 0, [_leader(RankGrades.Grade.COMPANY_LEADER), Vector2i(RankGrades.Role.ASSISTANT_SQUAD_LEADER, RankGrades.Grade.PLATOON_LEADER), Vector2i(RankGrades.Role.ASSISTANT_TEAM_LEADER, RankGrades.Grade.SQUAD_LEADER), _rifleman()])
	var officer: Soldier = hq.squad_fire.soldiers[0]
	var deputy: Soldier = hq.squad_fire.soldiers[1]
	var nco: Soldier = hq.squad_fire.soldiers[2]
	var runner: Soldier = hq.squad_fire.soldiers[3]
	succession.refresh()
	_check(notices.is_empty(), "Starting a staffed HQ does not announce a false command change")
	hq.apply_specific_casualty(officer)
	succession.refresh()
	_check(hq.company_command.commander == hq and hq.company_command.leader == deputy, "The local deputy succeeds the company commander")
	_check(nco.role == RankGrades.Role.ASSISTANT_SQUAD_LEADER and runner.role == RankGrades.Role.SOLDIER, "Only an eligible senior NCO fills the deputy vacancy")
	hq.apply_specific_casualty(deputy)
	succession.refresh()
	_check(hq.company_command.leader == nco and nco.rank_grade == RankGrades.Grade.SQUAD_LEADER, "A senior NCO takes acting command without a rank increase")
	_check(hq.acting_command_level == Globals.SquadType.COMPANY_HEADQUARTERS and hq.acting_command_supported, "An eligible NCO commanding inside the surviving HQ is identified as acting commander")
	_check(hq.ui.rank_texture_rect.visible and hq.ui.rank_texture_rect.texture == hq.ui.captain_texture, "A senior NCO in company command displays II while retaining the actual rank")
	hq.apply_specific_casualty(nco)
	succession.refresh()
	_check(not hq.company_command.has_commander() and runner.role == RankGrades.Role.SOLDIER, "A surviving runner cannot become company commander")
	_check(hq.leader_aura.leadership_bonus == 0.0 and hq.get_command_assignment_text().contains("No commander"), "An HQ remnant has no leadership aura and reports its missing commander")
	_check(not hq.ui.rank_texture_rect.visible, "A runner-only HQ remnant does not retain a command icon")


func _test_platoon_recovery() -> void:
	var hq: Unit = _unit(Globals.SquadType.PLATOON_HEADQUARTERS, Unit.Company.B, 1, 0, [_leader(RankGrades.Grade.PLATOON_LEADER), Vector2i(RankGrades.Role.RADIO, RankGrades.Grade.SOLDIER)])
	var first: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.B, 1, 1, [_leader(), _rifleman()])
	var second: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.B, 1, 2, [_leader(), _rifleman()])
	var wrong_platoon: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.B, 2, 1, [_leader(RankGrades.Grade.COMPANY_LEADER)])
	var original_roster: Array[Soldier] = first.squad_fire.soldiers.duplicate()
	var radioman: Soldier = hq.squad_fire.soldiers[1]
	var radio_weapon: WeaponSpec = radioman.weapon
	radioman.rounds_in_mag = 2
	var casualty_count: int = Globals.battle_casualties.size()
	succession.refresh()
	hq.apply_specific_casualty(hq.squad_fire.soldiers[0])
	second._on_command_connectivity_timeout()
	_check(not CommandConnectivity.has_available_commander(second) and second.command_connectivity.command_link_strength == 0.0, "A fallen HQ commander stops supplying command before the next succession refresh")
	succession.refresh()
	var command: FormationCommand = first.platoon_command
	_check(command.commander == first and second.command_squad == first and hq.command_squad == first, "A platoon remnant and its squads follow the first eligible squad leader")
	_check(first.ui.rank_texture_rect.visible and first.ui.rank_texture_rect.texture == first.ui.second_lieutenant_texture and not hq.ui.rank_texture_rect.visible and not second.ui.rank_texture_rect.visible, "The platoon I icon moves to the acting command squad and leaves the remnant unmarked")
	first.ui.set_contact_report({}, true)
	_check(not first.ui.rank_texture_rect.visible, "Restricted contacts cannot disclose a command appointment")
	first.ui.set_contact_report({}, false)
	_check(first.ui.rank_texture_rect.visible and first.ui.rank_texture_rect.texture == first.ui.second_lieutenant_texture, "Restoring identification restores the correct command icon")
	_check(wrong_platoon.command_squad != first and command.leader.unit == first, "Succession remains inside the platoon")
	_check(first.squad_type == Globals.SquadType.Rifle and first.squad_fire.soldiers == original_roster, "Acting command preserves the squad and every soldier's location")
	_check(first.acting_command_level == Globals.SquadType.PLATOON_HEADQUARTERS and is_equal_approx(first.command_efficiency, 0.75), "An unsupported acting commander has reduced effectiveness")
	_position(first, 0)
	_position(hq, 5)
	_position(second, 10)
	succession.refresh()
	_check(command.has_support() and second.command_connectivity.hq_relay_used and second.command_connectivity.command_link_strength > 0.0, "An HQ remnant relays orders beyond direct commander contact")
	_check(not command.reconstituted and first.acting_command_supported, "Contact supplies HQ support before reconstitution")
	var stable_strength: float = second.command_connectivity.command_link_strength
	for refresh_index: int in range(4):
		succession.refresh()
	_check(is_equal_approx(second.command_connectivity.command_link_strength, stable_strength), "Repeated contact refreshes do not compound acting-command penalties")
	_position(hq, 0)
	first.is_moving = true
	succession.refresh()
	_check(not command.reconstituted, "Passing through the same hex does not reconstitute an HQ while moving")
	first.is_moving = false
	hq.in_close_combat = true
	succession.refresh()
	_check(not command.reconstituted and hq.is_active(), "HQ personnel never transfer during close combat")
	hq.in_close_combat = false
	succession.refresh()
	_check(command.reconstituted and is_equal_approx(first.command_efficiency, 1.0), "Stopping together automatically reconstitutes the HQ")
	_check(first.members_alive == original_roster.size() + 1 and first.squad_fire.soldiers.has(radioman) and radioman.unit == first, "Reconstitution transfers the surviving radioman into the acting HQ")
	_check(radioman.weapon == radio_weapon and radioman.rounds_in_mag == 2, "Transferred soldiers retain their physical weapon and ammunition")
	_check(radioman.id != original_roster[0].id and radioman.id != original_roster[1].id, "Transferred soldiers receive unique IDs in the receiving unit")
	_check(not hq.is_active() and not Globals.get_units().has(hq) and hq.members_alive == 0 and not hq.visible, "The empty remnant disappears from active units and the map")
	_check(hq.alive and not hq.exited and not hq.is_in_group("dead_units") and not hq.is_in_group("exited_units") and Globals.battle_casualties.size() == casualty_count + 1, "Merging counts nobody as killed or evacuated")
	_check(command.headquarters == first and not command.has_remnant(), "The receiving unit becomes the reconstituted headquarters")
	_position(hq, 20)
	succession.refresh()
	_check(first.acting_command_supported and is_equal_approx(first.command_efficiency, 1.0) and first.members_alive == 3, "Merged personnel remain with the HQ and repeated refreshes never duplicate them")
	var commander_soldier: Soldier = command.leader
	first.apply_specific_casualty(commander_soldier)
	succession.refresh()
	_check(command.commander == second and not command.reconstituted, "The next eligible squad leader succeeds a fallen acting commander")
	_check(first.acting_command_level == -1 and first.command_squad == second, "The former command squad becomes a subordinate again")


func _test_company_succession() -> void:
	var company: Unit = _unit(Globals.SquadType.COMPANY_HEADQUARTERS, Unit.Company.C, 0, 0, [_leader(RankGrades.Grade.COMPANY_LEADER), _rifleman()])
	var first: Unit = _unit(Globals.SquadType.PLATOON_HEADQUARTERS, Unit.Company.C, 1, 0, [_leader(RankGrades.Grade.PLATOON_LEADER), Vector2i(RankGrades.Role.ASSISTANT_SQUAD_LEADER, RankGrades.Grade.SQUAD_LEADER), Vector2i(RankGrades.Role.ASSISTANT_TEAM_LEADER, RankGrades.Grade.SQUAD_LEADER), _rifleman()])
	var officer: Soldier = first.squad_fire.soldiers[0]
	var sergeant: Soldier = first.squad_fire.soldiers[1]
	var guide: Soldier = first.squad_fire.soldiers[2]
	var weapon: WeaponSpec = officer.weapon
	officer.rounds_in_mag = 2
	var second: Unit = _unit(Globals.SquadType.PLATOON_HEADQUARTERS, Unit.Company.C, 2, 0, [_leader(RankGrades.Grade.PLATOON_LEADER), _rifleman()])
	var next_officer: Soldier = second.squad_fire.soldiers[0]
	var subordinate: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.C, 2, 1, [_leader(RankGrades.Grade.TEAM_LEADER)])
	succession.refresh()
	company.apply_specific_casualty(company.squad_fire.soldiers[0])
	var casualties_before: int = Globals.battle_casualties.size()
	var exits_before: int = Globals.battle_exits.size()
	succession.refresh()
	var headquarters: Unit = company.company_command.commander
	_check(headquarters != first and headquarters != company and headquarters.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS and headquarters.platoon == 0, "Promotion creates a separate company HQ")
	_check(headquarters.current_hex == first.current_hex and headquarters.current_cube == first.current_cube, "Both HQs initially occupy the same hex")
	_check(headquarters.members_alive == 1 and headquarters.squad_fire.soldiers[0] == officer and officer.unit == headquarters and not first.squad_fire.soldiers.has(officer), "Only the promoted officer moves into the new company HQ")
	_check(officer.weapon == weapon and officer.rounds_in_mag == 2 and officer.rank_grade == RankGrades.Grade.PLATOON_LEADER, "Promotion preserves the officer's weapon, ammunition and rank")
	_check(first.members_alive == 3 and first.original_size == 3 and headquarters.original_size == 1, "Splitting conserves the platoon HQ's living and original strength")
	_check(Globals.battle_casualties.size() == casualties_before and Globals.battle_exits.size() == exits_before, "Separating the commander creates neither casualties nor evacuations")
	_check(first.platoon_command.commander == first and first.platoon_command.leader == sergeant and guide.unit == first, "The sergeant and other platoon staff remain in the original HQ")
	_check(first.get_soldier_role_name(sergeant) == "Acting Platoon Commander" and sergeant.rank_grade == RankGrades.Grade.SQUAD_LEADER, "The platoon successor is explicitly labeled without changing rank")
	_check(first.command_squad == headquarters and second.command_squad == headquarters and subordinate.command_squad == second and headquarters.command_squad == null, "Company and platoon command links remain separate and acyclic")
	_check(headquarters.get_hud_name() == "Acting Company HQ" and first.get_hud_name() == "Acting Platoon HQ", "Both HQs have distinct visible command names")
	_check(company.get_hud_name() == "Company HQ Remnant", "Original company staff remain a separate remnant until reunion")
	_check(headquarters.get_soldier_role_name(officer) == "Acting Company Commander", "The detached officer is visibly identified as company commander")
	_check(_has_notice(officer.name, "acting company commander") and _has_notice(sergeant.name, "acting platoon commander"), "Both appointments announce the named successor")
	_check(headquarters.get_headquarters_status_text().contains("75%") and is_equal_approx(headquarters.command_efficiency, 0.75), "The new company HQ has reduced effectiveness until its staff arrive")
	_check(headquarters.ui.rank_texture_rect.texture == headquarters.ui.captain_texture and headquarters.ui.rank_texture_rect.visible and first.ui.rank_texture_rect.texture == first.ui.second_lieutenant_texture and first.ui.rank_texture_rect.visible, "Separate company and platoon HQs display II and I simultaneously")
	var unit_count: int = Globals.get_units().size()
	for refresh_index: int in range(4):
		succession.refresh()
	_check(Globals.get_units().size() == unit_count and company.company_command.commander == headquarters and first.platoon_command.leader == sergeant, "Repeated refreshes neither duplicate the company HQ nor recombine the appointments")
	var staff: Soldier = company.squad_fire.soldiers[0]
	_position(headquarters, 0)
	_position(company, 0)
	succession.refresh()
	_check(headquarters.company_command.reconstituted and headquarters.members_alive == 2 and staff.unit == headquarters and not company.is_active(), "Company remnants transfer exclusively into the new company HQ")
	_check(first.members_alive == 3 and first.platoon_command.leader == sergeant and first.is_active(), "Reuniting company staff leaves the platoon HQ intact")
	_check(headquarters.get_headquarters_status_text().contains("100%"), "Reuniting company staff restores full command effectiveness")
	_position(headquarters, 10)
	succession.refresh()
	_check(first.current_hex != headquarters.current_hex and first.command_squad == headquarters, "The two HQs can occupy different hexes and retain their command links")
	headquarters.apply_specific_casualty(officer)
	succession.refresh()
	var replacement: Unit = company.company_command.commander
	_check(replacement != second and replacement != headquarters and company.company_command.leader == next_officer and next_officer.unit == replacement, "A later company casualty detaches the next eligible platoon commander into another company HQ")
	_check(first.platoon_command.leader == sergeant and second.platoon_command.commander == subordinate, "Further company succession preserves the first platoon and fills the second platoon vacancy")
	replacement.surrendered = true
	succession.refresh()
	var third: Unit = company.company_command.commander
	_check(third != first and third.squad_fire.soldiers.has(sergeant) and first.platoon_command.leader == guide, "Replacing a surrendered company commander also separates the next platoon successor")
	first.surrendered = true
	third.exited = true
	succession.refresh()
	var last: Unit = company.company_command.commander
	_check(last != subordinate and last.squad_fire.soldiers[0].unit == last and not subordinate.is_active(), "Promoting the sole soldier of an acting HQ retires its empty original unit")
	_check(last.leader_aura.leadership_bonus > 0.0, "A detached acting commander keeps the leadership bonus for his actual rank")
	_check(not second.platoon_command.has_commander(), "A platoon remains leaderless when its final eligible commander transfers to the company")
	last.surrendered = true
	succession.refresh()
	_check(not company.company_command.has_commander(), "The company remains leaderless when no eligible commander survives")


func _test_repurposed_headquarters() -> void:
	var company: Unit = _unit(Globals.SquadType.COMPANY_HEADQUARTERS, Unit.Company.D, 0, 0, [_leader(RankGrades.Grade.COMPANY_LEADER), _rifleman()])
	var platoon: Unit = _unit(Globals.SquadType.PLATOON_HEADQUARTERS, Unit.Company.D, 3, 0, [_leader(RankGrades.Grade.PLATOON_LEADER), _rifleman()])
	var squad: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.D, 3, 1, [_leader(), _rifleman()])
	succession.refresh()
	var officer: Soldier = platoon.squad_fire.soldiers[0]
	company.apply_specific_casualty(company.squad_fire.soldiers[0])
	succession.refresh()
	var headquarters: Unit = company.company_command.commander
	_check(officer.unit == headquarters and headquarters != platoon and platoon.platoon_command.commander == squad, "Without an eligible HQ deputy a squad leader fills the vacated platoon command")
	_position(platoon, 50)
	_position(squad, 50)
	succession.refresh()
	_check(not platoon.is_active() and squad.members_alive == 3 and officer.unit == headquarters and headquarters.members_alive == 1, "Leaderless platoon staff join their acting platoon HQ while company command stays separate")
	_check(company.company_command.commander == headquarters and squad.get_command_icon_level() == Globals.SquadType.PLATOON_HEADQUARTERS, "The new company HQ and reconstituted platoon HQ retain their separate appointments")


func _test_unavailable_candidates() -> void:
	var hq: Unit = _unit(Globals.SquadType.PLATOON_HEADQUARTERS, Unit.Company.D, 1, 0, [_leader(RankGrades.Grade.PLATOON_LEADER), _rifleman()])
	var candidate: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.D, 1, 1, [_leader()])
	candidate.team = Globals.Team.ALLIES
	succession.refresh()
	hq.apply_specific_casualty(hq.squad_fire.soldiers[0])
	succession.refresh()
	_check(not hq.platoon_command.has_commander(), "Enemy leaders are never eligible successors")
	_check(CommandConnectivity.contact_state_for(hq) == CommandConnectivity.ContactState.LOST, "A remnant without any eligible commander reports no command contact")


func _test_missing_headquarters() -> void:
	var squad: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.E, 1, 1, [_leader()])
	succession.refresh()
	_check(squad.acting_command_level == -1 and squad.command_squad == null, "A formation without an authored HQ does not invent a higher command appointment")


func _test_destroyed_headquarters() -> void:
	var hq: Unit = _unit(Globals.SquadType.PLATOON_HEADQUARTERS, Unit.Company.F, 1, 0, [_leader(RankGrades.Grade.PLATOON_LEADER), _rifleman()])
	var first: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.F, 1, 1, [_leader(), _rifleman()])
	var second: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.F, 1, 2, [_leader(), _rifleman()])
	succession.refresh()
	hq.die()
	succession.refresh()
	_check(first.platoon_command.commander == first and second.command_squad == first, "Destroying the entire HQ triggers succession in a surviving squad")
	_check(not first.platoon_command.has_remnant() and not first.acting_command_supported, "Destroyed HQ personnel cannot relay orders or reconstitute")
	var reinforcement: Unit = _unit(Globals.SquadType.PLATOON_HEADQUARTERS, Unit.Company.F, 1, 0, [_leader(RankGrades.Grade.PLATOON_LEADER), _rifleman()])
	succession.refresh()
	_check(first.platoon_command.commander == reinforcement and first.acting_command_level == -1, "An arriving staffed HQ resumes command and clears the acting appointment")
	_check(second.command_squad == reinforcement, "Existing subordinates reconnect to the restored staffed HQ")
	_check(not first.ui.rank_texture_rect.visible and reinforcement.ui.rank_texture_rect.visible and reinforcement.ui.rank_texture_rect.texture == reinforcement.ui.second_lieutenant_texture, "Restored HQ authority takes back I and clears the former acting squad icon")


func _test_presentation() -> void:
	var company: Unit = _unit(Globals.SquadType.COMPANY_HEADQUARTERS, Unit.Company.E, 0, 0, [_leader(RankGrades.Grade.COMPANY_LEADER), _rifleman()])
	var platoon: Unit = _unit(Globals.SquadType.PLATOON_HEADQUARTERS, Unit.Company.E, 1, 0, [_leader(RankGrades.Grade.PLATOON_LEADER), Vector2i(RankGrades.Role.ASSISTANT_SQUAD_LEADER, RankGrades.Grade.SQUAD_LEADER), _rifleman()])
	platoon.squad_fire.soldiers[0].name = "Test Platoon Leader"
	platoon.squad_fire.soldiers[1].name = "Test Platoon Sergeant"
	succession.refresh()
	var hud: CanvasLayer = (load("res://scenes/ui/hud/battle_hud.tscn") as PackedScene).instantiate() as CanvasLayer
	add_child(hud)
	_freeze(hud)
	var notice_handler: Callable = func(team: Globals.Team, title: String, explanation: String) -> void:
		if team == Globals.team_player:
			hud.show_command_notice(title, explanation)
	succession.command_notice.connect(notice_handler)
	company.apply_specific_casualty(company.squad_fire.soldiers[0])
	succession.refresh()
	var headquarters: Unit = company.company_command.commander
	hud.squad_roster.setup(Globals.team_player)
	hud.unit_details.show_unit_detail(headquarters, false)
	hud.unit_details._process(0.0)
	await get_tree().process_frame
	_check(hud.unit_details.unit_type_label.text == "Acting Company HQ", "The selected unit header displays its new company HQ appointment")
	_check(hud.unit_details.commander_label.visible and hud.unit_details.commander_label.text.contains("Test Platoon Leader"), "The actual acting commander is named in a visible summary line")
	_check(not hud.unit_details.commander_label.text.contains("Test Platoon Sergeant"), "Company details list only the company commander")
	_check(hud.unit_details.hq_status_label.visible and hud.unit_details.hq_status_label.text.contains("75%"), "Unreconstituted HQ effectiveness is visible without a tooltip")
	var row: SquadRosterRow = hud.squad_roster.rows[headquarters]
	var company_rows: VBoxContainer = hud.squad_roster.company_branches[Unit.Company.E].get_node("Indent/Content") as VBoxContainer
	_check(row.identity.text == "Acting Company HQ" and row.get_parent() == company_rows, "The new company HQ appears directly under its company")
	_check(hud.squad_roster.rows[company].identity.text == "Company HQ Remnant", "The original company HQ row is explicitly labeled as a remnant")
	_check(hud.get_node("Control/CommandNotice").visible and hud.get_node("Control/CommandNotice/Content/Explanation").text.contains("Test Platoon Leader") and hud.get_node("Control/CommandNotice/Content/Explanation").text.contains("acting company commander"), "The succession notice names the new commander")
	_check(hud.squad_roster.rows[platoon].identity.text == "Acting Platoon HQ" and hud.squad_roster.rows[platoon].get_parent() != company_rows, "The platoon HQ retains its own row under its platoon")
	hud.unit_details.show_unit_detail(platoon, false)
	_check(hud.unit_details.commander_label.text.contains("Test Platoon Sergeant"), "Selecting the platoon HQ names its separate commander")
	hud.unit_details.show_unit_detail(headquarters, false)
	var recorder: EngagementRecorder = EngagementRecorder.new()
	var command_data: Dictionary = recorder._command_snapshot(headquarters)
	_check(command_data["commander_soldier"] == headquarters.company_command.leader.id and command_data["commander_name"] == "Test Platoon Leader" and command_data["acting_level"] == Globals.SquadType.COMPANY_HEADQUARTERS, "Engagement captures identify the appointed commander and echelon explicitly")
	var platoon_data: Dictionary = recorder._command_snapshot(platoon)
	_check(command_data["appointments"].size() == 1 and platoon_data["appointments"].size() == 1 and command_data["commander_unit"] != platoon_data["commander_unit"], "Captures record distinct physical units for company and platoon command")
	recorder.free()
	hud.unit_details.show_unit_detail(company, false)
	_position(company, 0)
	_position(headquarters, 0)
	succession.refresh()
	hud.unit_details._process(0.0)
	hud.squad_roster.refresh()
	_check(hud.unit_details.unit == headquarters and hud.unit_details.soldiers.size() == 2, "Selecting a merging remnant switches details to the receiving HQ and shows transferred personnel")
	_check(not hud.squad_roster.rows.has(company), "The empty remnant row is removed after transfer")
	_check(hud.unit_details.hq_status_label.text.contains("reconstituted") and hud.unit_details.hq_status_label.text.contains("100%"), "Joining the remnant visibly changes HQ status to reconstituted at full effectiveness")
	hud.show_order_feedback(true, "Move", "Move accepted")
	_check(hud.get_node("Control/CommandNotice/Content/Title").text.contains("command changed"), "A movement acknowledgement does not overwrite a command notice")
	hud._show_next_command_notice()
	hud._show_next_command_notice()
	_check(hud.get_node("Control/CommandNotice/Content/Title").text.contains("reconstituted"), "The queued recovery notice is shown after the appointment notice")
	succession.command_notice.disconnect(notice_handler)
	hud.free()


func _test_live_merge() -> void:
	name = "SuccessionFixture"
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_child(1) as Map
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	var controller: Node2D = world.game_controller
	var remnant: Unit = null
	for candidate: Unit in Globals.get_units_for_team(Globals.team_player):
		if candidate.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
			remnant = candidate
			break
	_check(remnant != null, "The live scenario provides a platoon HQ")
	if remnant == null:
		main.free()
		return
	# Exercise the production creation signal, visibility, registration and selection.
	var company: Unit = UNIT_SCENE.instantiate() as Unit
	company.team = remnant.team
	company.company = remnant.company
	company.squad_type = Globals.SquadType.COMPANY_HEADQUARTERS
	controller.unit_container.add_child(company)
	company.current_hex = remnant.current_hex + Vector2i(3, 0)
	company.position = LOSHelper.ground_layer.map_to_local(company.current_hex)
	var company_loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	company_loadout.squad_type = Globals.SquadType.COMPANY_HEADQUARTERS
	for entry: Vector2i in [_leader(RankGrades.Grade.COMPANY_LEADER), _rifleman()]:
		var loadout: SoldierLoadout = SoldierLoadout.new()
		loadout.role = entry.x as RankGrades.Role
		loadout.rank_grade = entry.y as RankGrades.Grade
		loadout.weapon = load("res://resources/weapons/kar98.tres") as WeaponSpec
		company_loadout.soldiers.append(loadout)
	company.squad_loadout = company_loadout
	company.setup()
	company.add_to_group("units")
	MatchUnitSpawner.register_authored_unit(controller, company)
	_freeze(company)
	controller.command_succession.refresh()
	var officer: Soldier = remnant.platoon_command.leader
	var original_members: int = remnant.members_alive
	company.apply_specific_casualty(company.squad_fire.soldiers[0])
	controller.command_succession.refresh()
	var company_hq: Unit = company.company_command.commander
	_freeze(company_hq)
	_check(company_hq != remnant and officer.unit == company_hq and company_hq.members_alive == 1 and remnant.members_alive == original_members - 1, "Live succession separates the company commander from the platoon HQ")
	_check(Globals.get_unit(company_hq.team, company_hq.company, 0, 0) == company_hq and company_hq.unit_exited.is_connected(controller._on_unit_exited), "The new company HQ is registered with the live controller and formation hierarchy")
	_check(company_hq.ui.rank_texture_rect.visible and remnant.ui.rank_texture_rect.visible and company_hq.ui.rank_texture_rect.texture != remnant.ui.rank_texture_rect.texture, "Live company and platoon HQs simultaneously display separate command icons")
	var independent_selection: Array[Unit] = [company_hq]
	controller.set_selected_units(independent_selection)
	_check(controller.selected_unit == company_hq, "The new company HQ is independently selectable")
	_check(company_hq.create_save_data().squad_loadout.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS, "The separate HQ saves as a company HQ")
	while CommandSuccession.headquarters_leader(remnant) != null:
		remnant.apply_specific_casualty(CommandSuccession.headquarters_leader(remnant))
	controller.command_succession.refresh()
	var receiver: Unit = remnant.platoon_command.commander
	_check(receiver != null and receiver != remnant, "The live scenario appoints a surviving squad leader")
	if receiver == null:
		main.free()
		return
	var selected: Array[Unit] = [remnant]
	controller.set_selected_units(selected)
	var transferred: Array[Soldier] = remnant.squad_fire.soldiers.duplicate()
	var expected_members: int = receiver.members_alive + remnant.members_alive
	var casualty_count: int = Globals.battle_casualties.size()
	var exit_count: int = Globals.battle_exits.size()
	remnant.current_hex = receiver.current_hex
	remnant.current_cube = receiver.current_cube
	remnant.is_moving = false
	remnant.movement.is_moving = false
	receiver.is_moving = false
	receiver.movement.is_moving = false
	controller.command_succession.refresh()
	_check(receiver.members_alive == expected_members and not remnant.is_active(), "Live command refresh transfers HQ survivors and removes the empty remnant")
	_check(controller.selected_unit == receiver and controller.selected_units == [receiver], "The live controller moves selection from the remnant to the receiving HQ")
	_check(Globals.battle_casualties.size() == casualty_count and Globals.battle_exits.size() == exit_count, "A live merge creates neither casualty nor evacuation records")
	for soldier: Soldier in transferred:
		_check(soldier.unit == receiver and receiver.squad_fire.soldiers.has(soldier) and soldier.is_alive, "Transferred survivors remain living members of the receiving unit")
	var saved: UnitSaveData = receiver.create_save_data()
	_check(saved.squad_loadout.soldiers.size() == expected_members, "Saving the receiving HQ includes all transferred survivors")
	main.free()


func _has_notice(person: String, role: String) -> bool:
	for notice: Dictionary in notices:
		var explanation: String = notice["explanation"]
		if explanation.contains(person) and explanation.contains(role):
			return true
	return false


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		(node as Timer).stop()
	for child: Node in node.get_children():
		_freeze(child)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
