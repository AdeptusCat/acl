# leader_aura.gd
extends Node
class_name LeaderAura

@export var aura_radius_hexes: int = 2
@export var leadership_bonus: float = 0.15     # folds into stress controller's leadership_bonus
@export var rally_bonus: float = 0.10          # added to recovery rolls
@export var cohesion_mult: float = 1.05        # multiplicative on cohesion

@export var scan_interval_s: float = 0.25
@export var ground_map: HexagonTileMapLayer

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
	if ground_map == null:
		return
	var leader_hex: Vector2i = ground_map.local_to_map(_owner_unit.position)
	var candidates: Array = get_tree().get_nodes_in_group("units")
	var seen: Dictionary = {}

	for u in candidates:
		var unit: Node2D = u
		if not is_instance_valid(unit):
			continue
		if unit == _owner_unit:
			continue
		if not _same_team(_owner_unit, unit):
			continue

		var unit_hex: Vector2i = unit.current_hex
		var d: int = _hex_distance(leader_hex, unit_hex)
		if d <= aura_radius_hexes:
			_apply_to(unit)
			seen[unit] = true

	# remove those who left
	for prior in _affected.keys():
		if not seen.has(prior):
			_remove_from(prior)

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

func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	# Axial conversion if your map is axial; adjust if you’re using offset coords.
	var dx: int = a.x - b.x
	var dy: int = a.y - b.y
	var dz: int = -dx - dy
	var dist: int = int((abs(dx) + abs(dy) + abs(dz)) / 2)
	return dist
