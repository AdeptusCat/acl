extends PanelContainer

signal inspection_closed
signal layout_requested

const PANEL_WIDTH: float = 240.0
const EDGE_KEYS: Array[String] = ["cover_n", "cover_ne", "cover_se", "cover_s", "cover_sw", "cover_nw"]
const EDGE_NAMES: Array[String] = ["North", "Northeast", "Southeast", "South", "Southwest", "Northwest"]

@onready var terrain_name: Label = $Content/Heading/Terrain
@onready var cover_label: Label = $Content/Cover
@onready var sight_label: Label = $Content/Sight
@onready var details: FoldableContainer = $Content/Details
@onready var scroll: ScrollContainer = $Content/Details/Scroll
@onready var breakdown: VBoxContainer = $Content/Details/Scroll/Breakdown
@onready var coordinates: Label = $Content/Details/Scroll/Breakdown/Coordinates
@onready var features: Label = $Content/Details/Scroll/Breakdown/Features
@onready var edge_rows: GridContainer = $Content/Details/Scroll/Breakdown/Edges

var ground_layer: HexagonTileMapLayer
var inspected_hex: Vector2i
var edge_values: Array[Label] = []


func _ready() -> void:
	for direction: String in EDGE_NAMES:
		var label: Label = Label.new()
		label.text = direction
		edge_rows.add_child(label)
		var value: Label = Label.new()
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		edge_rows.add_child(value)
		edge_values.append(value)
	$Content/Heading/Close.pressed.connect(_on_close_pressed)
	details.folding_changed.connect(_on_folding_changed)
	minimum_size_changed.connect(_request_layout)
	_request_layout()


func set_ground_layer(layer: HexagonTileMapLayer) -> void:
	ground_layer = layer


func show_tile_data(result: Dictionary) -> void:
	var hex: Vector2i = result.get("hex", Vector2i.ZERO)
	inspected_hex = hex
	var name_text: String = str(result.get("tile_name", ""))
	if name_text.is_empty():
		name_text = "Open ground"
	terrain_name.text = name_text
	terrain_name.tooltip_text = "%s · Hex (%d, %d)" % [name_text, hex.x, hex.y]
	var cover: int = int(result.get("cover_in_hex", 0))
	cover_label.text = "Hex cover: none"
	if cover > 0:
		cover_label.text = "Hex cover: %d" % cover
	var blocking: bool = bool(result.get("blocking", false))
	var hindrance: bool = bool(result.get("hindrance", false))
	sight_label.text = "Sight: clear inside hex"
	if blocking:
		sight_label.text = "Sight: blocks through hex"
	elif hindrance:
		sight_label.text = "Sight: obscures through hex"
	coordinates.text = "Hex (%d, %d)" % [hex.x, hex.y]
	var blocked_text: String = "No"
	var obscured_text: String = "No"
	if blocking:
		blocked_text = "Yes"
	if hindrance:
		obscured_text = "Yes"
	features.text = "Blocks sight: %s\nObscures sight: %s" % [blocked_text, obscured_text]
	for index: int in range(EDGE_KEYS.size()):
		var value: int = int(result.get(EDGE_KEYS[index], 0))
		edge_values[index].text = "None"
		if value > 0:
			edge_values[index].text = "Cover %d" % value
	show()
	_request_layout()


func hide_inspection() -> void:
	hide()


func _on_close_pressed() -> void:
	inspection_closed.emit()


func _on_folding_changed(_folded: bool) -> void:
	_request_layout()


func _request_layout() -> void:
	layout_requested.emit()


func get_minimum_height() -> float:
	if details.folded:
		return get_combined_minimum_size().y
	return maxf(0.0, get_combined_minimum_size().y - scroll.get_combined_minimum_size().y)


func get_preferred_height() -> float:
	if details.folded:
		return get_minimum_height()
	return get_minimum_height() + breakdown.get_combined_minimum_size().y


func fit_panel(panel_position: Vector2, max_height: float) -> void:
	if not details.folded:
		scroll.custom_minimum_size.y = minf(breakdown.get_combined_minimum_size().y, maxf(0.0, max_height - get_minimum_height()))
	custom_minimum_size.x = PANEL_WIDTH
	size = Vector2(PANEL_WIDTH, get_combined_minimum_size().y)
	position = panel_position
