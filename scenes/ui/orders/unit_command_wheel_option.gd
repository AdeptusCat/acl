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
	ROUT,
	WATCH,
}

const COMMAND_NAMES: Dictionary[Option, String] = {
	Option.NONE: "Cancel",
	Option.MOVE_NORMAL: "Move",
	Option.MOVE_SLOW: "Slow move",
	Option.MOVE_FAST: "Fast move",
	Option.FIRE_AT: "Fire",
	Option.ASSAULT: "Assault",
	Option.STOP: "Stop",
	Option.ROUT: "Rout",
	Option.WATCH: "Watch",
}

@export var option: Option = Option.NONE
