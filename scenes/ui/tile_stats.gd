extends Control

@onready var hindrance: TextureRect = $Hindrance
@onready var blocked: TextureRect = $Blocked

@onready var coverN1: TextureRect = $CoverN1
@onready var coverN2: TextureRect = $CoverN2
@onready var coverNE1: TextureRect = $CoverNE1
@onready var coverNE2: TextureRect = $CoverNE2
@onready var coverSE1: TextureRect = $CoverSE1
@onready var coverSE2: TextureRect = $CoverSE2
@onready var coverS1: TextureRect = $CoverS1
@onready var coverS2: TextureRect = $CoverS2
@onready var coverSW1: TextureRect = $CoverSW1
@onready var coverSW2: TextureRect = $CoverSW2
@onready var coverNW1: TextureRect = $CoverNW1
@onready var coverNW2: TextureRect = $CoverNW2

var icon_scale_factor: float = 0.02

func _ready() -> void:
	hindrance.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_HINDRANCE))
	hindrance.mouse_exited.connect(_on_texture_rect_mouse_exited)
	blocked.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_BLOCKED))
	blocked.mouse_exited.connect(_on_texture_rect_mouse_exited)
	
	coverN1.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_WALL))
	coverN2.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_WALL))
	coverNE1.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_WALL))
	coverNE2.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_WALL))
	coverSE1.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_WALL))
	coverSE2.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_WALL))
	coverS1.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_WALL))
	coverS2.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_WALL))
	coverSW1.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_WALL))
	coverSW2.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_WALL))
	coverNW1.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_WALL))
	coverNW2.mouse_entered.connect(_on_texture_rect_mouse_entered.bind(TooltipSignals.Tooltip.LOS_WALL))
	
	coverN1.mouse_exited.connect(_on_texture_rect_mouse_exited)
	coverN2.mouse_exited.connect(_on_texture_rect_mouse_exited)
	coverNE1.mouse_exited.connect(_on_texture_rect_mouse_exited)
	coverNE2.mouse_exited.connect(_on_texture_rect_mouse_exited)
	coverSE1.mouse_exited.connect(_on_texture_rect_mouse_exited)
	coverSE2.mouse_exited.connect(_on_texture_rect_mouse_exited)
	coverS1.mouse_exited.connect(_on_texture_rect_mouse_exited)
	coverS2.mouse_exited.connect(_on_texture_rect_mouse_exited)
	coverSW1.mouse_exited.connect(_on_texture_rect_mouse_exited)
	coverSW2.mouse_exited.connect(_on_texture_rect_mouse_exited)
	coverNW1.mouse_exited.connect(_on_texture_rect_mouse_exited)
	coverNW2.mouse_exited.connect(_on_texture_rect_mouse_exited)

func set_offset_position(detail_tile_offset: Vector2, offset: Vector2, _size: Vector2, detail_zoom_factor: Vector2):
	blocked.scale = detail_zoom_factor * icon_scale_factor
	hindrance.scale = detail_zoom_factor * icon_scale_factor
	blocked.position = offset - (blocked.size * blocked.scale / 4)#+ Vector2(_size.x / 2, _size.y / 4)
	hindrance.position = offset - (hindrance.size * hindrance.scale / 4)#+ Vector2(_size.x / 2, _size.y / 4)
	offset = detail_tile_offset / 4
	coverN1.position = offset + Vector2(_size.x / 2 - _size.x / 10, 0)
	coverN2.position = offset + Vector2(_size.x / 2 + _size.x / 10 , 0)
	coverNW1.position = offset + Vector2(0, _size.y / 4)
	coverNW2.position = offset + Vector2(0 + _size.x / 7, _size.y / 4)
	coverSW1.position = offset + Vector2(0, _size.y / 4 * 3)
	coverSW2.position = offset + Vector2(0 + _size.x / 7, _size.y / 4 * 3)
	coverS1.position = offset + Vector2(_size.x / 2 - _size.x / 10, _size.y)
	coverS2.position = offset + Vector2(_size.x / 2 + _size.x / 10 , _size.y)
	coverSE1.position = offset + Vector2(_size.x / 6 * 5, _size.y / 4 * 3)
	coverSE2.position = offset + Vector2(_size.x / 6 * 5 + _size.x / 7, _size.y / 4 * 3)
	coverNE1.position = offset + Vector2(_size.x / 6 * 5, _size.y / 4)
	coverNE2.position = offset + Vector2(_size.x / 6 * 5 + _size.x / 7, _size.y / 4)
	
func show_stats(result: Dictionary):
	for child in get_children():
		child.visible = false
	
	if result.hindrance == true:
		$Hindrance.visible = true
	
	if result.blocking == true:
		$Blocked.visible = true
	
	if result.cover_n == 1:
		$CoverN1.visible = true
	elif result.cover_n == 2:
		$CoverN1.visible = true
		$CoverN2.visible = true
	
	if result.cover_ne == 1:
		$CoverNE1.visible = true
	elif result.cover_ne == 2:
		$CoverNE1.visible = true
		$CoverNE2.visible = true
	
	if result.cover_se == 1:
		$CoverSE1.visible = true
	elif result.cover_se == 2:
		$CoverSE1.visible = true
		$CoverSE2.visible = true
	
	if result.cover_s == 1:
		$CoverS2.visible = true
	elif result.cover_s == 2:
		$CoverS1.visible = true
		$CoverS2.visible = true
	
	if result.cover_sw == 1:
		$CoverSW2.visible = true
	elif result.cover_sw == 2:
		$CoverSW1.visible = true
		$CoverSW2.visible = true
	
	if result.cover_nw == 1:
		$CoverNW2.visible = true
	elif result.cover_nw == 2:
		$CoverNW1.visible = true
		$CoverNW2.visible = true
		

func _on_texture_rect_mouse_entered(tooltip: TooltipSignals.Tooltip) -> void:
	TooltipSignals.mouse_entered.emit(tooltip)


func _on_texture_rect_mouse_exited() -> void:
	TooltipSignals.mouse_exited.emit()
