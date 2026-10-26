extends Resource
class_name OffboardBattery

@export var team: Globals.Team = Globals.Team.ALLIES
@export var weapon: WeaponSpec
@export_range(1, 500) var rounds: int = 36
@export_range(0.0, 120.0) var response_seconds: float = 8.0
@export_range(0.5, 30.0) var flight_seconds: float = 4.0

func is_valid() -> bool:
	return weapon != null and weapon.ammo_type == WeaponSpec.AmmoType.HE and weapon.projectile_speed > 0 and rounds > 0 and response_seconds >= 0.0 and flight_seconds > 0.0
