# WeaponSpec.gd (Resource) — designer-friendly kit
extends Resource
class_name WeaponSpec

enum WeaponKind {
	PERSONAL,
	CREW_SERVED
}

enum WeaponType {
	Rifle,
	MG,
	SMG
}

enum Family { SMALL_ARM, LAUNCHER, MORTAR, GUN, AUTOCANNON, HOWITZER }
enum FireMode { SINGLE, BURST, MANUAL }

@export var name: String = "Rifle"
@export var rpm: float = 600.0
@export var burst_rounds: int = 1              # rifles 1, SMG 2–3, MG 4–6
@export var burst_pause_s: float = 0.35        # rest between bursts (not including firing time)
@export var mag_capacity: int = 5
@export var reload_s: float = 3.6
@export var jam_per_shot: float = 0.0
@export var range_hexes: int = 6
@export var accuracy_base: float = 0.6
@export var kind: WeaponKind = WeaponKind.PERSONAL
@export var type: WeaponType = WeaponType.Rifle
@export var family: Family = Family.SMALL_ARM
@export var fire_mode: FireMode = FireMode.SINGLE
@export var crew_required: int = 1             # MG typically 2
@export var support_crew_optimal: int = 0             
@export var undercrew_penalty_mult: float = 1.6  # >1 slows ROF if under-crewed
@export var priority: int = 1  # 10 meaning that it has to me manned first
@export var raise_s: float = 1.5   # shoulder weapon
@export var aim_s: float = 0.5     # acquire/sight picture
@export var setup_s: float = 0.0     # setup weapon

@export var projectile_speed: int = 600

@export var can_fire_riflegrenades: bool = false
@export var riflegrenade_loaded: bool = false
@export var setup_riflegrenade_s: float = 5.0     # setup weapon
@export var raise_riflegrenade_s: float = 2.0   # shoulder weapon
@export var aim_riflegrenade_s: float = 2.0     # acquire/sight picture
@export var reload_riflegrenade_s: float = 3.6
@export var riflegrenade_range: int = 3


@export var snd_shot: AudioStream = null        # close one-shot muzzle
@export var snd_mech: AudioStream = null        # mechanical action (bolt, trigger)
@export var snd_mg_loop: AudioStream = null     # loop for continuous MG fire
@export var snd_mg_loop_decay: AudioStream = null 
@export var snd_reload: AudioStream = null
@export var snd_distant: AudioStream = null     # low-salience distant thumpse one-shot muzzle
@export var snd_hit: AudioStream = null     
@export var volume_db: float = 0.0

@export var riflegrenade_shot: AudioStream = null
@export var riflegrenade_hit: AudioStream = null     # low-salience distant thumpse one-shot muzzle
@export var riflegrenade_projectile_speed: int = 200
