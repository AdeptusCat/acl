extends AtlasTexture
class_name WheelOption

enum Option {
	NONE,
	MOVE_NORMAL,
	MOVE_SLOW,
	MOVE_FAST,
	FIRE_AT,
	ASSAULT,
	STOP,
}
@export var option: Option = Option.NONE
