extends MarginContainer
class_name SoldierDetail

@onready var weapon: TextureRect = $HBoxContainer/WeaponTexture
@export var mg_texture: Texture
var soldier: Soldier


func set_soldier_detail(_soldier: Soldier):
	soldier = _soldier
	$HBoxContainer/ProgressBar.value = 0.0
	match soldier.weapon.type:
		WeaponSpec.WeaponType.MG:
			$HBoxContainer/WeaponTexture.texture = mg_texture
			$HBoxContainer/WeaponTexture.show()
			
	$HBoxContainer/WeaponName.text = soldier.weapon.name
	$HBoxContainer/RoleName.text = RankGrades.get_role_name(soldier.role)

func _process(delta: float) -> void:
	if soldier:
		#var p: float = get_acquire_progress()
		#$HBoxContainer/ProgressBar.value = p
		var p2: float = get_makeready_progress()
		$HBoxContainer/ProgressBar2.value = p2

func get_acquire_progress() -> float:
	# 0.0..1.0 progress bar value
	var t1_delta: float = soldier.next_ready_delta_s
	var t0: float = soldier.acquire_start_s
	var elapsed: float = soldier.now_s - t0
	
	var p: float = elapsed / t1_delta
	if p < 0.0:
		p = 0.0
	if p > 1.0:
		p = 1.0
	return p


func get_makeready_progress() -> float:
	# 0.0..1.0 progress bar value
	var t1_delta: float = soldier.next_ready_delta_s
	var t0: float = soldier.next_ready_start_s
	var elapsed: float = soldier.now_s - t0
	$HBoxContainer/Label.text = str(t1_delta)
	var p: float = elapsed / t1_delta
	if p < 0.0:
		p = 0.0
	if p > 1.0:
		p = 1.0
	return p
