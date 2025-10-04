# WeaponSpec.gd (Resource) — designer-friendly kit
extends Resource
class_name WeaponSpec

@export var name: String = "Rifle"
@export var rpm: float = 500.0
@export var burst_rounds: int = 1              # rifles 1, SMG 2–3, MG 4–6
@export var burst_pause_s: float = 0.35        # rest between bursts (not including firing time)
@export var mag_capacity: int = 30
@export var reload_s: float = 2.4
@export var jam_per_shot: float = 0.0
@export var range_hexes: int = 6
@export var accuracy_base: float = 0.6
@export var kind: int = 0                      # 0 = personal, 1 = crew_served
@export var crew_required: int = 1             # MG typically 2
@export var undercrew_penalty_mult: float = 1.6  # >1 slows ROF if under-crewed
@export var priority: int = 1  # 10 meaning that it has to me manned first
