# leader_aura.gd
extends Node
class_name LeaderAura

@export var aura_radius_hexes: int = 2
@export var leadership_bonus: float = 0.15     # folds into stress controller's leadership_bonus
@export var rally_bonus: float = 0.10          # added to recovery rolls
@export var cohesion_mult: float = 1.05        # multiplicative on cohesion
@export var scan_interval_s: float = 0.25

var _owner_unit: Node2D
var _since_scan: float = 0.0
var _affected: Dictionary = {}  # Node2D -> bool

func _ready() -> void:
	_owner_unit = get_parent() as Node2D
	add_to_group("leader_aura")

func _process(delta: float) -> void:
	_since_scan += delta
	if _since_scan < scan_interval_s:
		return
	_since_scan = 0.0
	_update_aura()

func _update_aura() -> void:
	if LOSHelper.ground_layer == null:
		return
	var leader_cube: Vector3i = _owner_unit.current_cube
	var candidates: Array = get_tree().get_nodes_in_group("units")
	var seen: Dictionary = {}

	for u in candidates:
		var unit: Node2D = u
		if not is_instance_valid(unit):
			continue
		# comment this to allow the same unit to influence itself
		#if unit == _owner_unit:
			#continue
		if not _same_team(_owner_unit, unit):
			continue
		
		var distance: int = LOSHelper.ground_layer.cube_distance(leader_cube, unit.current_cube)
		if aura_radius_hexes == 2:
			pass
		if distance <= aura_radius_hexes:
			_apply_to(unit)
			seen[unit] = true

	# remove those who left
	for prior in _affected.keys():
		if not seen.has(prior):
			if prior:
				_remove_from(prior)

func set_properties(_aura_radius_hexes, _leadership_bonus, _rally_bonus, _cohesion_mult):
	aura_radius_hexes = _aura_radius_hexes
	leadership_bonus = _leadership_bonus
	rally_bonus = _rally_bonus    
	cohesion_mult = _cohesion_mult

func _apply_to(unit: Node2D) -> void:
	if _affected.has(unit):
		return
	if not unit.has_node("UnitStressController"):
		return
	var sc: StressController = unit.get_node("UnitStressController") as StressController
	var sid: int = get_instance_id()
	sc.add_leadership_source(sid, leadership_bonus, rally_bonus, cohesion_mult)
	_affected[unit] = true

func _remove_from(unit: Node2D) -> void:
	if not _affected.has(unit):
		return
	if not is_instance_valid(unit):
		_affected.erase(unit)
		return
	if not unit.has_node("UnitStressController"):
		_affected.erase(unit)
		return
	var sc: StressController = unit.get_node("UnitStressController") as StressController
	var sid: int = get_instance_id()
	sc.remove_leadership_source(sid)
	_affected.erase(unit)

func _same_team(a: Node2D, b: Node2D) -> bool:
	var ta: int = a.team
	var tb: int = b.team
	if ta == tb:
		return true
	return false

#func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	## Axial conversion if your map is axial; adjust if you’re using offset coords.
	#var dx: int = a.x - b.x
	#var dy: int = a.y - b.y
	#var dz: int = -dx - dy
	#var dist: int = int((abs(dx) + abs(dy) + abs(dz)) / 2)
	#return dist
