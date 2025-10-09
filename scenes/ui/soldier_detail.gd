extends MarginContainer
class_name SoldierDetail

@onready var weapon: TextureRect = $HBoxContainer/WeaponTexture
@export var mg_texture: Texture

func set_soldier_detail(soldier: Soldier):
	match soldier.weapon.type:
		WeaponSpec.WeaponType.MG:
			$HBoxContainer/WeaponTexture.texture = mg_texture
			$HBoxContainer/WeaponTexture.show()
			
	$HBoxContainer/WeaponName.text = soldier.weapon.name
	$HBoxContainer/RoleName.text = RankGrades.get_role_name(soldier.role)
