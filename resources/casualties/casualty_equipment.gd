extends Resource
class_name CasualtyEquipment

# No live weapon or asset references: later firing and asset changes cannot
# alter or prevent loading the equipment state recorded at the time of death.
@export var weapon_id: String = ""
@export var resource_path_at_death: String = ""
@export var weapon_name: String = ""
@export var kind: int = 0
@export var type: int = 0
@export var family: int = 0
@export var ammo_type: int = 0
@export var fire_mode: int = 0
@export var rpm: float = 0.0
@export var range_hexes: int = 0
@export var mag_capacity: int = 0
@export var ammunition: int = 0
@export var rounds_in_mag: int = 0
@export var can_fire_riflegrenades: bool = false
@export var riflegrenade_loaded: bool = false
@export var is_setup: bool = false
@export var jammed: bool = false


static func capture(soldier: Soldier, current_battle_id: String) -> CasualtyEquipment:
	if soldier.weapon == null:
		return null
	var equipment: CasualtyEquipment = CasualtyEquipment.new()
	var weapon: WeaponSpec = soldier.weapon
	equipment.weapon_id = "%s:%s" % [current_battle_id, weapon.get_instance_id()]
	equipment.resource_path_at_death = weapon.source_resource_path
	if equipment.resource_path_at_death.is_empty():
		equipment.resource_path_at_death = weapon.resource_path
	equipment.weapon_name = weapon.name
	equipment.kind = weapon.kind
	equipment.type = weapon.type
	equipment.family = weapon.family
	equipment.ammo_type = weapon.ammo_type
	equipment.fire_mode = weapon.fire_mode
	equipment.rpm = weapon.rpm
	equipment.range_hexes = weapon.range_hexes
	equipment.mag_capacity = weapon.mag_capacity
	equipment.ammunition = weapon.ammunition
	equipment.rounds_in_mag = soldier.rounds_in_mag
	equipment.can_fire_riflegrenades = weapon.can_fire_riflegrenades
	equipment.riflegrenade_loaded = weapon.riflegrenade_loaded
	equipment.is_setup = weapon.is_setup
	equipment.jammed = soldier.jammed
	return equipment
