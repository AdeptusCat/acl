extends AtlasTexture
class_name WheelOption

enum Option {
	NONE,
	MOVE_NORMAL,
	MOVE_SLOW,
	MOVE_FAST,
	FIRE_AT,
	ASSAULT,
}
@export var option: Option = Option.NONE
