extends RefCounted
class_name FireSupportMission

enum Mode { QUICK, STANDARD, HARASSING }
enum Shape { POINT, LINE, AREA }
const SHAPE_NAMES: Array[String] = ["Point", "Line", "Area"]
const MODE_NAMES: Array[String] = ["Quick · 3 rounds", "Standard · 6 rounds", "Harassing · every 15–25 s"]

var asset_id: String
var target: Vector2i
var shape: Shape = Shape.POINT
var cells: Array[Vector2i] = []
var end: Vector2i
var radius: int = 1
var mode: Mode = Mode.QUICK
var remaining: int = 0
var fired: int = 0
var elapsed: float = 0.0
var next_round: float = 0.0
var last_launch_at: float = 0.0
var launch_work_total: float = 0.0
var active: bool = true
var result: String = "Preparing"
var _area_cycle: Array[Vector2i] = []
var _cycle_number: int = -1

func next_target() -> Vector2i:
	if cells.is_empty():
		return target
	if shape == Shape.AREA:
		var cycle: int = floori(float(fired) / float(cells.size()))
		if cycle != _cycle_number:
			_area_cycle.assign(cells)
			_area_cycle.shuffle()
			_cycle_number = cycle
		return _area_cycle[fired % cells.size()]
	return cells[fired % cells.size()]

func ready_to_fire() -> bool:
	return active and remaining > 0 and elapsed >= next_round

func commit_rounds(rounds: int) -> void:
	last_launch_at = elapsed
	launch_work_total = 0.0
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
