# squad_order.gd
class_name SquadOrder
extends Resource

const GoapTypes = preload("res://scenes/goap/goap_types.gd")

var order_type: GoapTypes.SquadOrderType = GoapTypes.SquadOrderType.NONE
var target_line_id: int = -1
var sector_index: int = -1
var target_hexes: Array[Vector2i] = []
var axis_id: int = -1
var fire_arc_center_deg: float = 0.0
var fire_arc_width_deg: float = 120.0
var aggressiveness: float = 1.0
var rest_area_hex: Vector2i = Vector2i(-1, -1)

func reset() -> void:
	order_type = GoapTypes.SquadOrderType.NONE
	target_line_id = -1
	sector_index = -1
	target_hexes.clear()
	axis_id = -1
	fire_arc_center_deg = 0.0
	fire_arc_width_deg = 120.0
	aggressiveness = 1.0
	rest_area_hex = Vector2i(-1, -1)
