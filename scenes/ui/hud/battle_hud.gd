extends CanvasLayer

@export var unit_stats_details_scene : PackedScene
@export var ground_layer : HexagonTileMapLayer

@onready var countdown_panel_container: PanelContainer = $Control/Countdown


@onready var cover_icon_scene: PackedScene = preload("res://scenes/ui/effects/cover_icon.tscn")

@onready var target_cover_distance: Control = $Control/TargetCoverDistance
@onready var cover_container: HBoxContainer = $Control/TargetCoverDistance/VBoxContainer/Cover
@onready var firepower_label: Label = $Control/TargetCoverDistance/VBoxContainer/HBoxContainer/FirepowerLabel
@onready var distance_label: Label = $Control/TargetCoverDistance/VBoxContainer/HBoxContainer2/DistanceLabel
@onready var selection_wheel: Control = $Control/SelectionWheel
@onready var selection_wheel_alt: Control = $Control/SelectionWheelAlt

@onready var unit_details: PanelContainer = $Control/UnitDetails
@onready var tile_details: PanelContainer = $Control/TileDetails

signal try_again

# Configuration
const HEX_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]


#func _process(delta: float) -> void:
	#if Input.is_action_just_pressed("RIGHT"):
		#selection_wheel.show()
	#elif Input.is_action_just_released("RIGHT"):
		#var option: WheelOption.Option = selection_wheel.close()
		#print(option)

func setup() -> void:
	#var db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	##var db = -2
	#var ratio = pow(10.0, db / 20.0)
	#$Control/Settings/FoldableContainer/VBoxContainer/VolumeSlider.value = ratio
	#$Control/Settings/FoldableContainer/VBoxContainer/VolumeSlider2.value = ratio
	tile_details.set_ground_layer(ground_layer)
	unit_details.hide()

func show_tile_data(result: Dictionary) -> void:
	tile_details.show_tile_data(result)


func show_target_hex_cover_distance(local_event_pos: Vector2, targetCover: int, distance: int, firepower: float) -> void:
	target_cover_distance.show()
	target_cover_distance.position = local_event_pos
	for child: Control in cover_container.get_children():
		child.queue_free()
	for cover: int in targetCover:
		var cover_icon: TextureRect = cover_icon_scene.instantiate()
		cover_icon.expand_mode = TextureRect.ExpandMode.EXPAND_FIT_WIDTH_PROPORTIONAL
		cover_container.add_child(cover_icon)
	firepower_label.text = str(firepower)
	distance_label.text = str(distance)
	#if detail_ui:
		#detail_ui.set_cover(targetCover)


func hide_target_hex_cover_distance() -> void:
	target_cover_distance.hide()


func _on_game_started_through_moving_unit() -> void:
	countdown_panel_container.set_countdown(true)


func _on_update_timer_label(time_left_seconds : float) -> void:
	countdown_panel_container.update_timer_label(time_left_seconds)


func mouse_event_position_changed(_event_pos: Vector2) -> void:
	pass

# legacy code that shows unit details
#func show_unit_data(map_hex: Vector2i, units: Array):
	#unit_stats.visible = true
	#var unit_detail_counter: int = 0
	#for child in unit_stats_container.get_children():
		#if "detail_ui" in child:
			#child.detail_ui = null
		#child.queue_free()
	#for unit in units:
		#if not LOSHelper.visible_hexes[Globals.team_player].has(unit.current_hex):
			#continue
		##var unit_ui = unit.ui.duplicate(Node.DuplicateFlags.DUPLICATE_SIGNALS | Node.DuplicateFlags.DUPLICATE_GROUPS | Node.DuplicateFlags.DUPLICATE_SCRIPTS)
		##unit_stats_container.add_child(unit_ui)
		##var unit_detail_container = unit_ui.soldiers_detail_container.duplicate()
		##unit_stats_container.add_child(unit_detail_container)
		##var unit_stats_details = unit_stats_details_scene.instantiate()
		##unit_stats_details.set_details(unit)
		##unit_stats_container.add_child(unit_stats_details)
		#
		##unit.ui.detail_ui = unit_ui
		##unit_ui._set_loadout(unit.squad_fire.soldiers)
		##unit_detail_counter += 1
	#if unit_detail_counter == 0:
		#unit_stats.visible = false


func _on_show_unit_details(unit: Unit) -> void:
	unit_details.show_unit_detail(unit)


func _on_hide_unit_details() -> void:
	unit_details.hide_unit_detail()


func _on_try_again_button_pressed() -> void:
	try_again.emit()


func _db_to_ratio(db: float) -> float:
	# Convert dB (-80..0) to 0–1 range for slider
	return pow(10.0, db / 20.0)

func _ratio_to_db(ratio: float) -> float:
	# Convert slider ratio (0–1) back to dB
	var db: float
	if ratio <= 0.0001:
		db = -80.0
	else:
		db = 20.0 * log(ratio)
	return db


func _on_start_screen_time_changed(_time: float) -> void:
	if countdown_panel_container:
		countdown_panel_container.update_timer_label(_time * 60.0)
		
