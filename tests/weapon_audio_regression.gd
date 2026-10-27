extends Node

class UnitProbe extends Unit:
	func set_cover(_value: int) -> void:
		pass

class PoolProbe extends AudioPool:
	var streams: Array[AudioStream] = []
	func _ready() -> void:
		pass
	func play_one_shot(stream: AudioStream, _position: Vector2, _volume: float = 0.0, _pitch: float = 1.0, _bus: String = "") -> void:
		streams.append(stream)

class AudioProbe extends WeaponAudio:
	var starts: int = 0
	var stops: int = 0
	var owners: Dictionary[int, bool] = {}
	func _ready() -> void:
		pass
	func start_mg_loop(owner_id: int, _weapon: WeaponSpec, _owner: Node2D) -> void:
		starts += 1
		owners[owner_id] = true
	func stop_mg_loop(weapon: WeaponSpec, position: Vector2, owner_id: int, _owner: Node2D) -> void:
		if not owners.has(owner_id):
			return
		owners.erase(owner_id)
		stops += 1
		play_shot_decay(weapon, position)

class ManagedAudio extends WeaponAudio:
	func _ready() -> void:
		pass

class FireProbe extends SquadFireController:
	func _resolve_airborne_round(_weapon: WeaponSpec, _grenade: bool, _cell: Vector2i, _distance: int, _cover: int, _targets: Array[Unit], _origin: Vector2, _life: float) -> void:
		pass

var checks: int = 0
var failures: int = 0
var shooter: Unit
var enemy: Unit
var fire: FireProbe
var sound: AudioProbe
var pool: PoolProbe
var fixture: Node2D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_size = Vector2i(64, 64)
	ground.pathfinding_enabled = false
	add_child(ground)
	LOSHelper.ground_layer = ground
	shooter = UnitProbe.new()
	shooter.current_hex = Vector2i.ZERO
	shooter.team = Globals.Team.AXIS
	enemy = UnitProbe.new()
	enemy.current_hex = Vector2i(0, 1)
	enemy.team = Globals.Team.ALLIES
	LOSHelper.los_lookup = {shooter.current_hex: {enemy.current_hex: {"target_cover": 0}}}
	Globals.unit_visible_enemies = {shooter: [enemy]}
	fixture = Node2D.new()
	add_child(fixture)
	pool = PoolProbe.new()
	fixture.add_child(pool)
	sound = AudioProbe.new()
	sound.name = "WeaponAudio"
	fixture.add_child(sound)
	sound._active = true
	sound.audio_pool = pool
	sound.snd_shot_default = AudioStreamWAV.new()
	fire = FireProbe.new()
	fire.unit = shooter
	shooter.squad_fire = fire
	fixture.add_child(fire)
	fire.set_process(false)
	var automatic: Soldier = _soldier(1, "res://resources/weapons/mg34.tres")
	_begin(automatic, 3)
	_check(sound.starts == 1 and pool.streams.is_empty(), "MG audio starts with the first round without a generic shot overlay")
	fire._advance_burst(automatic, 60.0 / automatic.weapon.rpm)
	_check(sound.starts == 1 and sound.stops == 0 and pool.streams.is_empty(), "Intermediate automatic rounds neither restart the loop nor add shot samples")
	fire._advance_burst(automatic, 60.0 / automatic.weapon.rpm)
	_check(sound.stops == 0, "The final automatic round retains its audio interval before the tail")
	await get_tree().create_timer(0.1).timeout
	_check(sound.stops == 1 and pool.streams == [automatic.weapon.snd_mg_loop_decay], "A completed burst stops once and plays the weapon's configured decay")
	_begin(automatic, 3)
	automatic.behavior = Soldier.Behavior.COWERING
	fire._advance_burst(automatic, 0.0)
	_check(sound.starts == 2 and sound.stops == 2, "An interrupted burst stops its loop immediately")
	automatic.behavior = Soldier.Behavior.ENGAGING
	var before: int = sound.stops
	_begin(automatic, 1)
	_begin(automatic, 3)
	await get_tree().create_timer(0.1).timeout
	_check(sound.stops == before and sound.owners.has(automatic.id), "An earlier burst's delayed stop cannot cut off a newer burst")
	automatic.behavior = Soldier.Behavior.TAKING_COVER
	fire._advance_burst(automatic, 0.0)
	_check(sound.stops == before + 1, "The newer burst retains ownership of its own stop")
	pool.streams.clear()
	var rifle: Soldier = _soldier(2, "res://resources/weapons/m1_garand.tres")
	_begin(rifle, 1)
	_begin(rifle, 1)
	_check(pool.streams == [rifle.weapon.snd_shot, rifle.weapon.snd_shot], "Single-shot rifles play their configured sample for each emitted round")
	var starts: int = sound.starts
	var grenade: Soldier = _soldier(3, "res://resources/weapons/kar98_riflegrenade.tres")
	grenade.weapon.fire_mode = WeaponSpec.FireMode.BURST
	grenade.weapon.riflegrenade_loaded = true
	pool.streams.clear()
	_begin(grenade, 1)
	_check(sound.starts == starts and pool.streams == [grenade.weapon.riflegrenade_shot], "Rifle grenades keep their launch sample without starting automatic audio")
	var stops: int = sound.stops
	automatic.behavior = Soldier.Behavior.ENGAGING
	Debug.dont_fire_wepaons = true
	_begin(automatic, 3)
	Debug.dont_fire_wepaons = false
	_check(sound.starts == starts and sound.stops == stops, "A burst rejected before its first round emits no loop or decay")
	await _test_loop_lifecycle()
	fire.calc.free()
	fixture.free()
	shooter.free()
	enemy.free()
	Globals.unit_visible_enemies.clear()
	LOSHelper.los_lookup.clear()
	LOSHelper.ground_layer = null
	print("Weapon audio checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)

func _soldier(id: int, path: String) -> Soldier:
	var weapon: WeaponSpec = (load(path) as WeaponSpec).create_runtime()
	weapon.ammunition = 100
	return Soldier.new(id, "Audio probe", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, weapon, shooter, shooter.team)

func _begin(soldier: Soldier, rounds: int) -> void:
	if fire.soldiers.size() != 1 or fire.soldiers[0] != soldier:
		fire.set_soldiers([soldier])
	fire.target_unit = enemy
	fire._start_burst(soldier, rounds, enemy.current_hex, enemy, false, 1, 0, [enemy])

func _test_loop_lifecycle() -> void:
	var manager: ManagedAudio = ManagedAudio.new()
	fixture.add_child(manager)
	manager._active = true
	manager.audio_pool = pool
	var position_node: Node2D = Node2D.new()
	fixture.add_child(position_node)
	var weapon: WeaponSpec = WeaponSpec.new()
	weapon.snd_mg_loop = AudioStreamGenerator.new()
	weapon.snd_mg_loop_decay = AudioStreamWAV.new()
	pool.streams.clear()
	manager.start_mg_loop(10, weapon, position_node)
	var original: AudioStreamPlayer2D = manager._mg_loops[10]
	manager.start_mg_loop(10, weapon, position_node)
	_check(manager._mg_loops[10] == original and original.playing, "Repeated loop starts preserve the existing playback instead of restarting it")
	manager.stop_mg_loop(weapon, Vector2.ZERO, 10, position_node)
	manager.stop_mg_loop(weapon, Vector2.ZERO, 10, position_node)
	_check(pool.streams == [weapon.snd_mg_loop_decay] and manager._mg_loops.is_empty(), "Repeated stops produce only one decay sample")
	manager.start_mg_loop(10, weapon, position_node)
	_check(manager._mg_loops[10] != original, "A new burst can start before the old player is freed")
	manager.shutdown()
	_check(manager._mg_loops.is_empty(), "Shutdown clears active playback")
	await get_tree().process_frame
	manager.free()
	position_node.free()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
