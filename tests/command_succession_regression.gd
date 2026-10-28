extends Node

const UNIT_SCENE: PackedScene = preload("res://scenes/game/units/unit.tscn")

var failures: int = 0
var checks: int = 0
var units: Array[Unit] = []
var succession: CommandSuccession
var ground: HexagonTileMapLayer


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
	Debug.no_damage = false
	_test_local_succession()
	_test_platoon_recovery()
	_test_company_succession()
	_test_unavailable_candidates()
	_test_missing_headquarters()
	_test_destroyed_headquarters()
	for unit: Unit in units:
		unit.squad_fire.calc.free()
		unit.free()
	succession.free()
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
	hq.apply_specific_casualty(officer)
	succession.refresh()
	_check(hq.company_command.commander == hq and hq.company_command.leader == deputy, "The local deputy succeeds the company commander")
	_check(nco.role == RankGrades.Role.ASSISTANT_SQUAD_LEADER and runner.role == RankGrades.Role.SOLDIER, "Only an eligible senior NCO fills the deputy vacancy")
	hq.apply_specific_casualty(deputy)
	succession.refresh()
	_check(hq.company_command.leader == nco and nco.rank_grade == RankGrades.Grade.SQUAD_LEADER, "A senior NCO takes acting command without a rank increase")
	_check(hq.acting_command_level == Globals.SquadType.COMPANY_HEADQUARTERS and hq.acting_command_supported, "An eligible NCO commanding inside the surviving HQ is identified as acting commander")
	hq.apply_specific_casualty(nco)
	succession.refresh()
	_check(not hq.company_command.has_commander() and runner.role == RankGrades.Role.SOLDIER, "A surviving runner cannot become company commander")
	_check(hq.leader_aura.leadership_bonus == 0.0 and hq.get_command_assignment_text().contains("No commander"), "An HQ remnant has no leadership aura and reports its missing commander")


func _test_platoon_recovery() -> void:
	var hq: Unit = _unit(Globals.SquadType.PLATOON_HEADQUARTERS, Unit.Company.B, 1, 0, [_leader(RankGrades.Grade.PLATOON_LEADER), Vector2i(RankGrades.Role.RADIO, RankGrades.Grade.SOLDIER)])
	var first: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.B, 1, 1, [_leader(), _rifleman()])
	var second: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.B, 1, 2, [_leader(), _rifleman()])
	var wrong_platoon: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.B, 2, 1, [_leader(RankGrades.Grade.COMPANY_LEADER)])
	var original_roster: Array[Soldier] = first.squad_fire.soldiers.duplicate()
	succession.refresh()
	hq.apply_specific_casualty(hq.squad_fire.soldiers[0])
	second._on_command_connectivity_timeout()
	_check(not CommandConnectivity.has_available_commander(second) and second.command_connectivity.command_link_strength == 0.0, "A fallen HQ commander stops supplying command before the next succession refresh")
	succession.refresh()
	var command: FormationCommand = first.platoon_command
	_check(command.commander == first and second.command_squad == first and hq.command_squad == first, "A platoon remnant and its squads follow the first eligible squad leader")
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
	succession.refresh()
	_check(command.reconstituted and is_equal_approx(first.command_efficiency, 1.0), "Stopping together automatically reconstitutes the HQ")
	_check(first.squad_fire.soldiers == original_roster and hq.members_alive == 1, "Reconstitution does not transfer soldiers or restore casualties")
	_position(hq, 20)
	succession.refresh()
	_check(not first.acting_command_supported and is_equal_approx(first.command_efficiency, 0.75), "Losing HQ contact removes the recovered support bonus")
	var commander_soldier: Soldier = command.leader
	first.apply_specific_casualty(commander_soldier)
	succession.refresh()
	_check(command.commander == second and not command.reconstituted, "The next eligible squad leader succeeds a fallen acting commander")
	_check(first.acting_command_level == -1 and first.command_squad == second, "The former command squad becomes a subordinate again")


func _test_company_succession() -> void:
	var company: Unit = _unit(Globals.SquadType.COMPANY_HEADQUARTERS, Unit.Company.C, 0, 0, [_leader(RankGrades.Grade.COMPANY_LEADER), _rifleman()])
	var first: Unit = _unit(Globals.SquadType.PLATOON_HEADQUARTERS, Unit.Company.C, 1, 0, [_leader(RankGrades.Grade.PLATOON_LEADER), _rifleman()])
	var second: Unit = _unit(Globals.SquadType.PLATOON_HEADQUARTERS, Unit.Company.C, 2, 0, [_leader(RankGrades.Grade.PLATOON_LEADER), _rifleman()])
	var subordinate: Unit = _unit(Globals.SquadType.Rifle, Unit.Company.C, 2, 1, [_leader()])
	succession.refresh()
	company.apply_specific_casualty(company.squad_fire.soldiers[0])
	succession.refresh()
	_check(first.company_command.commander == first and second.command_squad == first, "An eligible platoon commander automatically takes over the company")
	_check(first.command_squad == null and subordinate.command_squad == second, "Company succession preserves the platoon hierarchy without cycles")
	_check(first.acting_command_level == Globals.SquadType.COMPANY_HEADQUARTERS, "The acting company appointment appears on the original platoon HQ")
	_position(company, 0)
	_position(first, 0)
	succession.refresh()
	_check(company.company_command.reconstituted and first.acting_command_reconstituted, "A company HQ remnant also reconstitutes automatically")
	first.surrendered = true
	succession.refresh()
	_check(company.company_command.commander == second, "A surrendered acting commander is replaced")
	second.exited = true
	succession.refresh()
	_check(company.company_command.commander == subordinate, "Company succession can cascade through a newly appointed acting platoon commander")
	subordinate.surrendered = true
	succession.refresh()
	_check(not company.company_command.has_commander(), "The company remains leaderless when no eligible commander survives")


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
