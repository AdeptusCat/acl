extends Resource
class_name UnitExitRecord

@export var record_id: String = ""
@export var battle_id: String = ""
@export var scenario_name: String = ""
@export var recorded_at_unix: float = 0.0
@export var team: Globals.Team = Globals.Team.AXIS
@export var unit_id: String = ""
@export var unit_name: String = ""
@export var company: int = 0
@export var platoon: int = 0
@export var squad: int = 0
@export var hex: Vector2i = Vector2i.ZERO
@export var members_alive: int = 0


static func capture(unit: Unit, current_battle_id: String) -> UnitExitRecord:
	var record: UnitExitRecord = UnitExitRecord.new()
	record.record_id = Crypto.new().generate_random_bytes(16).hex_encode()
	record.battle_id = current_battle_id
	if is_instance_valid(Globals.scenario_chosen):
		record.scenario_name = Globals.scenario_chosen.scenario_name
	record.recorded_at_unix = Time.get_unix_time_from_system()
	record.team = unit.team
	record.unit_id = "%s:%s" % [current_battle_id, unit.get_instance_id()]
	record.unit_name = unit.name
	record.company = unit.company
	record.platoon = unit.platoon
	record.squad = unit.squad
	record.hex = unit.current_hex
	record.members_alive = unit.members_alive
	return record
