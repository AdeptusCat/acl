class_name BattlefieldEffects
extends Node2D

const Tracer: Script = preload("res://scenes/game/effects/tracer.gd")
const IMPACT_PATTERN: Script = preload("res://scenes/game/effects/burst_impact_pattern.gd")
const POOL_NAME: String = "BattlefieldEffects"
const MAX_EFFECTS: int = 192

@export_range(1, 8) var rifle_tracer_interval: int = 2
@export_range(1, 8) var mg_tracer_interval: int = 3
@export_range(1, 8) var smg_tracer_interval: int = 4

var _available: Array[Tracer] = []
var _all: Array[Tracer] = []
var _shot_counts: Array[int] = [0, 0, 0]
var _visible_cells: Dictionary[Vector2i, bool] = {}
var _visibility_frame: int = -1
var _ground: HexagonTileMapLayer


static func for_scene(context: Node) -> BattlefieldEffects:
	var scene: Node = context.get_tree().current_scene
	var effects: BattlefieldEffects = scene.get_node_or_null(NodePath(POOL_NAME)) as BattlefieldEffects
	if effects == null:
		effects = BattlefieldEffects.new()
		effects.name = POOL_NAME
		scene.add_child(effects)
	return effects


func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_index = 5
	_ground = LOSHelper.ground_layer


func _process(_delta: float) -> void:
	if _ground != LOSHelper.ground_layer:
		clear()
		_ground = LOSHelper.ground_layer


func clear() -> void:
	_available.clear()
	for tracer: Tracer in _all:
		tracer.deactivate()
		_available.append(tracer)
	_shot_counts = [0, 0, 0]
	_visible_cells.clear()
	_visibility_frame = -1


func fire(from: Vector2, to: Vector2, weapon: WeaponSpec, shot_kind: Tracer.Kind, scene: PackedScene, spawn_offset: Vector2 = Vector2.ZERO, impact_offset: Vector2 = Vector2.INF) -> Tracer:
	if _ground != LOSHelper.ground_layer:
		clear()
		_ground = LOSHelper.ground_layer
	var tracer: Tracer
	if not _available.is_empty():
		tracer = _available.pop_back()
	elif _all.size() < MAX_EFFECTS:
		tracer = scene.instantiate() as Tracer
		add_child(tracer)
		tracer.visibility_test = is_world_position_visible
		tracer.screen_test = is_on_screen
		tracer.finished.connect(_release.bind(tracer))
		_all.append(tracer)
	else:
		# Dropping a cosmetic effect must never delay or suppress combat resolution.
		return null
	var draw_streak: bool = true
	if shot_kind == Tracer.Kind.BULLET:
		draw_streak = _next_streak(weapon.type)
	var offset: Vector2 = impact_offset
	if not offset.is_finite():
		offset = Vector2.ZERO
		if is_instance_valid(_ground):
			var cell: Vector2i = _ground.local_to_map(_ground.to_local(to))
			var points: PackedVector2Array = IMPACT_PATTERN.create(_ground, cell, from + spawn_offset, 1)
			if not points.is_empty():
				offset = points[0] - to
	tracer.launch(from, to, weapon, shot_kind, surface_at(to + offset), draw_streak, spawn_offset, offset)
	return tracer


func _release(tracer: Tracer) -> void:
	_available.append(tracer)


func _next_streak(type: WeaponSpec.WeaponType) -> bool:
	var interval: int = rifle_tracer_interval
	if type == WeaponSpec.WeaponType.MG:
		interval = mg_tracer_interval
	elif type == WeaponSpec.WeaponType.SMG:
		interval = smg_tracer_interval
	var count: int = _shot_counts[type]
	_shot_counts[type] = count + 1
	return count % maxi(interval, 1) == 0


func is_on_screen(point: Vector2) -> bool:
	var screen_point: Vector2 = get_global_transform_with_canvas() * point
	return get_viewport_rect().grow(80.0).has_point(screen_point)


func is_world_position_visible(point: Vector2) -> bool:
	if Debug.hide_fog_of_war:
		return true
	if not is_instance_valid(LOSHelper.ground_layer):
		return false
	var frame: int = Engine.get_process_frames()
	if frame != _visibility_frame:
		_visibility_frame = frame
		_visible_cells.clear()
		for cell: Vector2i in LOSHelper.visible_hexes.get(Globals.team_player, []):
			_visible_cells[cell] = true
	var ground: HexagonTileMapLayer = LOSHelper.ground_layer
	return _visible_cells.has(ground.local_to_map(ground.to_local(point)))


static func surface_at(point: Vector2) -> Tracer.Surface:
	var data: TileData = _data_at(LOSHelper.building_layer, point)
	if data != null:
		if data.has_custom_data("name"):
			var building_name: String = str(data.get_custom_data("name")).to_lower()
			if building_name.contains("wood") and building_name.contains("building"):
				return Tracer.Surface.WOOD
			if building_name == "woods":
				return Tracer.Surface.FOLIAGE
		if data.has_custom_data("cover") and int(data.get_custom_data("cover")) == 2:
			return Tracer.Surface.WOOD
		return Tracer.Surface.STONE
	data = _data_at(LOSHelper.terrain_layer, point)
	if data != null and data.has_custom_data("name"):
		var terrain_name: String = str(data.get_custom_data("name")).to_lower()
		if terrain_name.contains("river") or terrain_name.contains("water"):
			return Tracer.Surface.WATER
		if terrain_name.contains("wood") or terrain_name.contains("orchard") or terrain_name.contains("brush"):
			return Tracer.Surface.FOLIAGE
	if _data_at(LOSHelper.road_layer, point) != null:
		return Tracer.Surface.ROAD
	return Tracer.Surface.GROUND


static func _data_at(layer: TileMapLayer, point: Vector2) -> TileData:
	if not is_instance_valid(layer):
		return null
	return layer.get_cell_tile_data(layer.local_to_map(layer.to_local(point)))
