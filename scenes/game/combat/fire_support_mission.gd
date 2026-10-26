extends RefCounted
class_name FireSupportMission

enum Mode { QUICK, STANDARD, HARASSING }
const MODE_NAMES: Array[String] = ["Quick · 3 rounds", "Standard · 6 rounds", "Harassing · every 15–25 s"]

var asset_id: String
var target: Vector2i
var mode: Mode = Mode.QUICK
var remaining: int = 0
var fired: int = 0
var elapsed: float = 0.0
var next_round: float = 0.0
var active: bool = true
var result: String = "Preparing"

func ready_to_fire() -> bool:
	return active and remaining > 0 and elapsed >= next_round

func commit_rounds(rounds: int) -> void:
	remaining = maxi(0, remaining - rounds)
	fired += rounds
	result = "Firing"
	if mode == Mode.HARASSING:
		next_round = elapsed + randf_range(15.0, 25.0)
	elif mode == Mode.STANDARD:
		next_round = elapsed + 4.0
	else:
		next_round = elapsed
	if remaining <= 0:
		active = false
		result = "Complete · rounds may still be airborne"

func stop(reason: String = "Ceased · airborne rounds still land") -> void:
	active = false
	result = reason
