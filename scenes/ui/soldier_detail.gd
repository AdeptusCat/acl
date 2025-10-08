extends VBoxContainer
class_name SoldierDetail

@onready var weapon: TextureRect = $Weapon
@export var mg_texture: Texture

func set_soldier_detail(soldier: Soldier):
	match soldier.weapon.type:
		WeaponSpec.WeaponType.MG:
			$Weapon.texture = mg_texture
			$Weapon.show()
