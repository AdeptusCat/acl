extends RefCounted
class_name FireSupportMission

enum Intensity { INTENSE, STEADY, HARASSING, SPORADIC }
enum Shape { POINT, LINE, AREA }
const SHAPE_NAMES: Array[String] = ["Point", "Line", "Area"]
const LENGTHS: Array[float] = [15.0, 30.0, 60.0, 120.0, 300.0]
const LENGTH_NAMES: Array[String] = ["15 seconds", "30 seconds", "1 minute", "2 minutes", "5 minutes"]
const INTERVALS: Array[float] = [5.0, 10.0, 20.0, 40.0]
const INTENSITY_NAMES: Array[String] = ["Intense · 5 s / shot", "Steady · 10 s / shot", "Harassing · 20 s / shot", "Sporadic · 40 s / shot"]

var asset_id: String
var target: Vector2i
var shape: Shape = Shape.POINT
var cells: Array[Vector2i] = []
var end: Vector2i
var radius: int = 1
var intensity: Intensity = Intensity.INTENSE
var duration_seconds: float = 15.0
var first_launch_at: float = -1.0
var planned_rounds: int = 0
var guns: int = 1
var pending_guns: int = 0
var onboard_guns: Array[Soldier] = []
var onboard_due: Dictionary[Soldier, float] = {}
var onboard_volley_at: float = 0.0
var onboard_volley_launched: bool = false

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

func gun_ready(soldier: Soldier) -> bool:
	if not onboard_guns.has(soldier):
		return false
	if guns == 1:
		return ready_to_fire()
	return active and remaining > 0 and not time_expired() and onboard_due.has(soldier) and elapsed >= onboard_due[soldier]

func begin_onboard_volley() -> void:
	onboard_volley_at = elapsed
	onboard_volley_launched = false
	var count: int = mini(onboard_guns.size(), remaining)
	onboard_due.clear()
	for index: int in range(count):
		var delay: float = 0.0
		if index > 0:
			delay = float(index) / float(maxi(count - 1, 1)) * 0.45
		onboard_due[onboard_guns[index]] = elapsed + delay
	pending_guns = count

func commit_gun(soldier: Soldier, rounds: int) -> void:
	if guns > 1 and not onboard_volley_launched:
		var offset: float = elapsed - onboard_volley_at
		for gun: Soldier in onboard_due:
			onboard_due[gun] += offset
		onboard_volley_at = elapsed
		onboard_volley_launched = true
	onboard_due.erase(soldier)
	pending_guns = onboard_due.size()
	commit_rounds(rounds)
	if guns > 1:
		last_launch_at = onboard_volley_at
		next_round = onboard_volley_at + INTERVALS[intensity]

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
	return active and remaining > 0 and elapsed >= next_round and not time_expired()

func time_expired() -> bool:
	return first_launch_at >= 0.0 and elapsed - first_launch_at >= duration_seconds

func seconds_left() -> float:
	if first_launch_at < 0.0:
		return duration_seconds
	return maxf(0.0, duration_seconds - (elapsed - first_launch_at))

static func intensity_text(value: Intensity, gun_count: int) -> String:
	var text: String = INTENSITY_NAMES[value]
	if gun_count > 1:
		text = text.replace("/ shot", "/ volley")
	return text

func commit_rounds(rounds: int) -> void:
	if first_launch_at < 0.0:
		first_launch_at = elapsed
	last_launch_at = elapsed
	launch_work_total = 0.0
	remaining = maxi(0, remaining - rounds)
	fired += rounds
	result = "Firing"
	next_round = elapsed + INTERVALS[intensity]
	if remaining <= 0:
		active = false
		result = "Complete · rounds may still be airborne"

func stop(reason: String = "Ceased · airborne rounds still land") -> void:
	active = false
	remaining = 0
	result = reason
