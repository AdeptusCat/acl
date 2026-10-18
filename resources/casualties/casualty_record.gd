extends Resource
class_name CasualtyRecord

# Historical data contains no scene nodes or mutable runtime weapon references.
@export var record_id: String = ""
@export var battle_id: String = ""
@export var scenario_name: String = ""
@export var recorded_at_unix: float = 0.0
@export var team: int = 0
@export var unit_id: String = ""
@export var unit_name: String = ""
@export var company: int = 0
@export var platoon: int = 0
@export var squad: int = 0
@export var hex: Vector2i = Vector2i.ZERO
@export var soldier_id: int = -1
@export var soldier_name: String = ""
@export var rank_grade: int = 0
@export var role: int = 0
@export var equipment: CasualtyEquipment


static func capture(unit: Unit, soldier: Soldier, current_battle_id: String) -> CasualtyRecord:
	var record: CasualtyRecord = CasualtyRecord.new()
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
	record.soldier_id = soldier.id
	record.soldier_name = soldier.name
	record.rank_grade = soldier.rank_grade
	record.role = soldier.role
	record.equipment = CasualtyEquipment.capture(soldier, current_battle_id)
	return record
