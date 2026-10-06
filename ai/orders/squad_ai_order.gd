class_name AiOrder
extends Resource

enum OrderType {
	NONE,
	HOLD,
	MOVE_TO,
	SUPPRESS,
	ASSAULT,
	WITHDRAW,
	RALLY
}

@export var order_type: OrderType = OrderType.NONE
@export var target_hex: Vector2i = Vector2i.ZERO
@export var priority: float = 0.0
@export var allow_fire: bool = true
@export var allow_movement: bool = true
@export var allow_assault: bool = false

var target_unit: Unit = null
