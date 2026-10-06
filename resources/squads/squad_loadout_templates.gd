@tool
extends RefCounted
class_name SquadLoadoutTemplates

# Synchronous SquadLoadoutTemplates operations; state and scene identity stay on the caller.


static func resize_loadouts(unit: Unit, n: int) -> void:
	# grow
	var i: int = unit.loadouts.size()
	while i < n:
		var L: SoldierLoadout = SoldierLoadout.new()
		L.nickname = "Man %d" % int(i + 1)
		if unit.default_rifle != null:
			L.weapon = unit.default_rifle
		# sensible first two slots for MG team if MG exists
		if i == 0:
			if unit.default_mg != null:
				L.role = RankGrades.Role.GUNNER
				L.nickname = "Gunner"
				L.weapon = unit.default_mg
				L.is_key_role = true
		if i == 1:
			L.role = RankGrades.Role.LOADER
			L.nickname = "Loader"
			L.is_key_role = true
		unit.loadouts.append(L)
		i += 1
	# shrinkf
	while unit.loadouts.size() > n:
		unit.loadouts.pop_back()


static func make_rifle_squad(unit: Unit) -> void:
	if unit.team == 0:
		var group_size: int = 10
		var rifle: WeaponSpec
		var smg: WeaponSpec
		var mg: WeaponSpec
		rifle = preload("res://resources/weapons/kar98.tres")
		var riflegrenade: WeaponSpec = preload("res://resources/weapons/kar98_riflegrenade.tres")
		smg = preload("res://resources/weapons/mp40.tres")
		mg = preload("res://resources/weapons/mg34.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var leader: SoldierLoadout = unit.loadouts[i]
		leader.role = RankGrades.Role.SQUAD_LEADER
		leader.nickname = "Squad Leader"
		leader.rank_grade = RankGrades.Grade.SQUAD_LEADER
		leader.weapon = smg
		i += 1
		var assistant_leader: SoldierLoadout = unit.loadouts[i]
		assistant_leader.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
		assistant_leader.nickname = "Ass. Squad Leader"
		assistant_leader.rank_grade = RankGrades.Grade.TEAM_LEADER
		assistant_leader.weapon = smg
		i += 1
		var gunner: SoldierLoadout = unit.loadouts[i]
		gunner.role = RankGrades.Role.GUNNER
		gunner.nickname = "Gunner"
		gunner.rank_grade = RankGrades.Grade.SOLDIER
		gunner.weapon = mg
		i += 1
		var loader: SoldierLoadout = unit.loadouts[i]
		loader.role = RankGrades.Role.LOADER
		loader.nickname = "Loader"
		loader.rank_grade = RankGrades.Grade.SOLDIER
		loader.weapon = rifle
		i += 1
		var riflegrenadier: SoldierLoadout = unit.loadouts[i]
		riflegrenadier.role = RankGrades.Role.SOLDIER
		riflegrenadier.nickname = "Riflegrenadier"
		riflegrenadier.rank_grade = RankGrades.Grade.SOLDIER
		riflegrenadier.weapon = riflegrenade
		i += 1
		while i < group_size:
			var L: SoldierLoadout = unit.loadouts[i]
			L.role = RankGrades.Role.SOLDIER
			L.nickname = "Rifle %d" % int(i + 1)
			L.rank_grade = RankGrades.Grade.SOLDIER
			L.weapon = rifle
			i += 1
	else:
		var group_size: int = 12
		var rifle: WeaponSpec
		var _smg: WeaponSpec
		var mg: WeaponSpec
		rifle = preload("res://resources/weapons/m1_garand.tres")
		var riflegrenade: WeaponSpec = preload("res://resources/weapons/springfield_1903_riflegrenade.tres")
		_smg = preload("res://resources/weapons/m3_grease_gun.tres")
		mg = preload("res://resources/weapons/m1918a1_bar.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var leader: SoldierLoadout = unit.loadouts[i]
		leader.role = RankGrades.Role.SQUAD_LEADER
		leader.nickname = "Squad Leader"
		leader.rank_grade = RankGrades.Grade.SQUAD_LEADER
		leader.weapon = rifle
		i += 1
		var assistant_leader: SoldierLoadout = unit.loadouts[i]
		assistant_leader.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
		assistant_leader.nickname = "Ass. Squad Leader"
		assistant_leader.rank_grade = RankGrades.Grade.TEAM_LEADER
		assistant_leader.weapon = rifle
		i += 1
		var gunner: SoldierLoadout = unit.loadouts[i]
		gunner.role = RankGrades.Role.GUNNER
		gunner.nickname = "Gunner"
		gunner.rank_grade = RankGrades.Grade.SOLDIER
		gunner.weapon = mg
		i += 1
		var loader: SoldierLoadout = unit.loadouts[i]
		loader.role = RankGrades.Role.LOADER
		loader.nickname = "Loader"
		loader.rank_grade = RankGrades.Grade.SOLDIER
		loader.weapon = rifle
		i += 1
		var riflegrenadier: SoldierLoadout = unit.loadouts[i]
		riflegrenadier.role = RankGrades.Role.SOLDIER
		riflegrenadier.nickname = "Riflegrenadier"
		riflegrenadier.rank_grade = RankGrades.Grade.SOLDIER
		riflegrenadier.weapon = riflegrenade
		i += 1
		while i < group_size:
			var L: SoldierLoadout = unit.loadouts[i]
			L.role = RankGrades.Role.SOLDIER
			L.nickname = "Rifle %d" % int(i + 1)
			L.rank_grade = RankGrades.Grade.SOLDIER
			L.weapon = rifle
			i += 1
	unit.notify_property_list_changed()


static func make_platoon_headquarters_squad(unit: Unit) -> void:
	if unit.team == 0:
		var group_size: int = 7
		var rifle: WeaponSpec = preload("res://resources/weapons/kar98.tres")
		var smg: WeaponSpec = preload("res://resources/weapons/mp40.tres")
		#var mg: WeaponSpec = preload("res://resources/weapons/mg34.tres")
		#var riflegrenade: WeaponSpec = preload("res://resources/weapons/kar98_riflegrenade.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var leader: SoldierLoadout = unit.loadouts[i]
		leader.role = RankGrades.Role.SQUAD_LEADER
		leader.nickname = "Zugführer"
		leader.rank_grade = RankGrades.Grade.PLATOON_LEADER
		leader.weapon = smg
		i += 1
		var platoon_sergeant: SoldierLoadout = unit.loadouts[i]
		platoon_sergeant.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
		platoon_sergeant.nickname = "Zugtruppführer"
		platoon_sergeant.rank_grade = RankGrades.Grade.SQUAD_LEADER
		platoon_sergeant.weapon = smg
		i += 1
		var platoon_guide: SoldierLoadout = unit.loadouts[i]
		platoon_guide.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
		platoon_guide.nickname = "Melder"
		platoon_guide.rank_grade = RankGrades.Grade.SQUAD_LEADER
		platoon_guide.weapon = rifle
		i += 1
		var platoon_guide1: SoldierLoadout = unit.loadouts[i]
		platoon_guide1.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
		platoon_guide1.nickname = "Sanitäter"
		platoon_guide1.rank_grade = RankGrades.Grade.TEAM_LEADER
		platoon_guide1.weapon = rifle
		i += 1
		var platoon_guide2: SoldierLoadout = unit.loadouts[i]
		platoon_guide2.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
		platoon_guide2.nickname = "Funker"
		platoon_guide2.rank_grade = RankGrades.Grade.SOLDIER
		platoon_guide2.weapon = rifle
		i += 1
		while i < group_size:
			var L: SoldierLoadout = unit.loadouts[i]
			L.role = RankGrades.Role.SOLDIER
			L.nickname = "Messenger %d" % int(i + 1)
			L.rank_grade = RankGrades.Grade.SOLDIER
			L.weapon = rifle
			i += 1
	else:
		var group_size: int = 5
		var rifle: WeaponSpec = preload("res://resources/weapons/m1_garand.tres")
		var carbine: WeaponSpec = preload("res://resources/weapons/m1_carbine.tres")
		var riflegrenade: WeaponSpec = preload("res://resources/weapons/springfield_1903_riflegrenade.tres")
		#var smg: WeaponSpec = preload("res://resources/weapons/m3_grease_gun.tres")
		#var mg: WeaponSpec = preload("res://resources/weapons/m1918a1_bar.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var leader: SoldierLoadout = unit.loadouts[i]
		leader.role = RankGrades.Role.SQUAD_LEADER
		leader.nickname = "Platoon Leader"
		leader.rank_grade = RankGrades.Grade.PLATOON_LEADER
		leader.weapon = carbine
		i += 1
		var platoon_sergeant: SoldierLoadout = unit.loadouts[i]
		platoon_sergeant.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
		platoon_sergeant.nickname = "Platoon Seargeant"
		platoon_sergeant.rank_grade = RankGrades.Grade.SQUAD_LEADER
		platoon_sergeant.weapon = rifle
		i += 1
		var platoon_guide: SoldierLoadout = unit.loadouts[i]
		platoon_guide.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
		platoon_guide.nickname = "Platoon Guide"
		platoon_guide.rank_grade = RankGrades.Grade.SQUAD_LEADER
		platoon_guide.weapon = riflegrenade
		i += 1
		while i < group_size:
			var L: SoldierLoadout = unit.loadouts[i]
			L.role = RankGrades.Role.SOLDIER
			L.nickname = "Messenger %d" % int(i + 1)
			L.rank_grade = RankGrades.Grade.SOLDIER
			L.weapon = rifle
			i += 1
	unit.notify_property_list_changed()


static func make_company_headquarters_squad(unit: Unit) -> void:
	if unit.team == 0:
		var group_size: int = 7
		var rifle: WeaponSpec = preload("res://resources/weapons/kar98.tres")
		var smg: WeaponSpec = preload("res://resources/weapons/mp40.tres")
		#var mg: WeaponSpec = preload("res://resources/weapons/mg34.tres")
		#var riflegrenade: WeaponSpec = preload("res://resources/weapons/kar98_riflegrenade.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var leader: SoldierLoadout = unit.loadouts[i]
		leader.role = RankGrades.Role.SQUAD_LEADER
		leader.nickname = "Kompaniechef"
		leader.rank_grade = RankGrades.Grade.COMPANY_LEADER
		leader.weapon = smg
		i += 1
		var platoon_sergeant: SoldierLoadout = unit.loadouts[i]
		platoon_sergeant.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
		platoon_sergeant.nickname = "Zugführer"
		platoon_sergeant.rank_grade = RankGrades.Grade.PLATOON_LEADER
		platoon_sergeant.weapon = smg
		i += 1
		var platoon_guide: SoldierLoadout = unit.loadouts[i]
		platoon_guide.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
		platoon_guide.nickname = "Hauptfeldwebel"
		platoon_guide.rank_grade = RankGrades.Grade.SQUAD_LEADER
		platoon_guide.weapon = smg
		i += 1
		var platoon_guide2: SoldierLoadout = unit.loadouts[i]
		platoon_guide2.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
		platoon_guide2.nicknam = "Melderführer"
		platoon_guide2.rank_grade = RankGrades.Grade.SQUAD_LEADER
		platoon_guide2.weapon = smg
		i += 1
		var platoon_guide3: SoldierLoadout = unit.loadouts[i]
		platoon_guide3.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
		platoon_guide3.nickname = "Funker"
		platoon_guide3.rank_grade = RankGrades.Grade.TEAM_LEADER
		platoon_guide3.weapon = rifle
		i += 1
		while i < group_size:
			var L: SoldierLoadout = unit.loadouts[i]
			L.role = RankGrades.Role.SOLDIER
			L.nickname = "Messenger %d" % int(i + 1)
			L.rank_grade = RankGrades.Grade.SOLDIER
			L.weapon = rifle
			i += 1
	else:
		var group_size: int = 8
		#var rifle: WeaponSpec = preload("res://resources/weapons/m1_garand.tres")
		var carbine: WeaponSpec = preload("res://resources/weapons/m1_carbine.tres")
		var riflegrenade: WeaponSpec = preload("res://resources/weapons/springfield_1903_riflegrenade.tres")
		#var smg: WeaponSpec = preload("res://resources/weapons/m3_grease_gun.tres")
		#var mg: WeaponSpec = preload("res://resources/weapons/m1918a1_bar.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var leader: SoldierLoadout = unit.loadouts[i]
		leader.role = RankGrades.Role.SQUAD_LEADER
		leader.nickname = "Company Commander"
		leader.rank_grade = RankGrades.Grade.COMPANY_LEADER
		leader.weapon = carbine
		i += 1
		var company_executive_officer: SoldierLoadout = unit.loadouts[i]
		company_executive_officer.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
		company_executive_officer.nickname = "Executive Officer"
		company_executive_officer.rank_grade = RankGrades.Grade.PLATOON_LEADER
		company_executive_officer.weapon = carbine
		i += 1
		var company_first_sergeant: SoldierLoadout = unit.loadouts[i]
		company_first_sergeant.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
		company_first_sergeant.nickname = "First Sergeant"
		company_first_sergeant.rank_grade = RankGrades.Grade.SQUAD_LEADER
		company_first_sergeant.weapon = carbine
		i += 1
		var communications_sergeant: SoldierLoadout = unit.loadouts[i]
		communications_sergeant.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
		communications_sergeant.nickname = "Communications Sergeant"
		communications_sergeant.rank_grade = RankGrades.Grade.SQUAD_LEADER
		communications_sergeant.weapon = riflegrenade
		i += 1
		var bugler: SoldierLoadout = unit.loadouts[i]
		bugler.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
		bugler.nickname = "Bugler"
		bugler.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
		bugler.weapon = riflegrenade
		i += 1
		while i < group_size:
			var L: SoldierLoadout = unit.loadouts[i]
			L.role = RankGrades.Role.SOLDIER
			L.nickname = "Messenger %d" % int(i + 1)
			L.rank_grade = RankGrades.Grade.SOLDIER
			L.weapon = carbine
			i += 1
	unit.notify_property_list_changed()


static func make_light_mg_team(unit: Unit) -> void:
	if unit.team == 0:
		var group_size: int = 7
		var rifle: WeaponSpec
		var smg: WeaponSpec
		var mg: WeaponSpec
		rifle = preload("res://resources/weapons/kar98.tres")
		smg = preload("res://resources/weapons/mp40.tres")
		mg = preload("res://resources/weapons/mg34_heavy.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var leader: SoldierLoadout = unit.loadouts[i]
		leader.role = RankGrades.Role.SQUAD_LEADER
		leader.nickname = "Squad Leader"
		leader.rank_grade = RankGrades.Grade.SQUAD_LEADER
		leader.weapon = smg
		i += 1
		var gunner: SoldierLoadout = unit.loadouts[i]
		gunner.role = RankGrades.Role.GUNNER
		gunner.nickname = "Gunner"
		gunner.rank_grade = RankGrades.Grade.SOLDIER
		gunner.weapon = mg
		i += 1
		var loader: SoldierLoadout = unit.loadouts[i]
		loader.role = RankGrades.Role.LOADER
		loader.nickname = "Loader"
		loader.rank_grade = RankGrades.Grade.SOLDIER
		loader.weapon = rifle
		i += 1
		while i < group_size - 1:
			var assistant: SoldierLoadout = unit.loadouts[i]
			assistant.role = RankGrades.Role.ASSISTANT
			assistant.nickname = "Ass. %d" % int(i + 1)
			assistant.rank_grade = RankGrades.Grade.SOLDIER
			assistant.weapon = rifle
			i += 1
		var L: SoldierLoadout = unit.loadouts[i]
		L.role = RankGrades.Role.SOLDIER
		L.nickname = "Rifle %d" % int(i + 1)
		L.rank_grade = RankGrades.Grade.SOLDIER
		L.weapon = rifle
		i += 1
	else:
		var group_size: int = 5
		var rifle: WeaponSpec
		var mg: WeaponSpec
		rifle = preload("res://resources/weapons/m1_carbine.tres")
		mg = preload("res://resources/weapons/m1919a4.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var leader: SoldierLoadout = unit.loadouts[i]
		leader.role = RankGrades.Role.SQUAD_LEADER
		leader.nickname = "Squad Leader"
		leader.rank_grade = RankGrades.Grade.SQUAD_LEADER
		leader.weapon = rifle
		i += 1
		var gunner: SoldierLoadout = unit.loadouts[i]
		gunner.role = RankGrades.Role.GUNNER
		gunner.nickname = "Gunner"
		gunner.rank_grade = RankGrades.Grade.SOLDIER
		gunner.weapon = mg
		i += 1
		var loader: SoldierLoadout = unit.loadouts[i]
		loader.role = RankGrades.Role.LOADER
		loader.nickname = "Loader"
		loader.rank_grade = RankGrades.Grade.SOLDIER
		loader.weapon = rifle
		i += 1
		while i < group_size:
			var L: SoldierLoadout = unit.loadouts[i]
			L.role = RankGrades.Role.ASSISTANT
			L.nickname = "Ass. %d" % int(i + 1)
			L.rank_grade = RankGrades.Grade.SOLDIER
			L.weapon = rifle
			i += 1
	unit.notify_property_list_changed()


static func make_anti_tank_squad(unit: Unit) -> void:
	if unit.team == 0:
		var group_size: int = 2
		var rifle: WeaponSpec = preload("res://resources/weapons/kar98.tres")
		#var smg: WeaponSpec = preload("res://resources/weapons/mp40.tres")
		var antitank_weapon: WeaponSpec = preload("res://resources/weapons/rpzb_54_panzerschreck.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var gunner: SoldierLoadout = unit.loadouts[i]
		gunner.role = RankGrades.Role.GUNNER
		gunner.nickname = "Gunner"
		gunner.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
		gunner.weapon = antitank_weapon
		i += 1
		var loader: SoldierLoadout = unit.loadouts[i]
		loader.role = RankGrades.Role.LOADER
		loader.nickname = "Loader"
		loader.rank_grade = RankGrades.Grade.SOLDIER
		loader.weapon = rifle
		i += 1
	else:
		var group_size: int = 2
		var rifle: WeaponSpec = preload("res://resources/weapons/m1_carbine.tres")
		#var smg: WeaponSpec = preload("res://resources/weapons/m3_grease_gun.tres")
		var antitank_weapon: WeaponSpec = preload("res://resources/weapons/m1a1_bazooka.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var gunner: SoldierLoadout = unit.loadouts[i]
		gunner.role = RankGrades.Role.GUNNER
		gunner.nickname = "Gunner"
		gunner.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
		gunner.weapon = antitank_weapon
		i += 1
		var loader: SoldierLoadout = unit.loadouts[i]
		loader.role = RankGrades.Role.LOADER
		loader.nickname = "Loader"
		loader.rank_grade = RankGrades.Grade.SOLDIER
		loader.weapon = rifle
		i += 1
	unit.notify_property_list_changed()


static func make_light_mortar_squad(unit: Unit) -> void:
	if unit.team == 0:
		var group_size: int = 5
		var rifle: WeaponSpec = preload("res://resources/weapons/kar98.tres")
		#var smg: WeaponSpec = preload("res://resources/weapons/mp40.tres")
		var mortar: WeaponSpec = preload("res://resources/weapons/granatwerfer_36.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var leader: SoldierLoadout = unit.loadouts[i]
		leader.role = RankGrades.Role.TEAM_LEADER
		leader.nickname = "Squad Leader"
		leader.rank_grade = RankGrades.Grade.TEAM_LEADER
		leader.weapon = rifle
		i += 1
		var gunner: SoldierLoadout = unit.loadouts[i]
		gunner.role = RankGrades.Role.GUNNER
		gunner.nickname = "Gunner"
		gunner.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
		gunner.weapon = mortar
		i += 1
		var loader: SoldierLoadout = unit.loadouts[i]
		loader.role = RankGrades.Role.LOADER
		loader.nickname = "Loader"
		loader.rank_grade = RankGrades.Grade.SOLDIER
		loader.weapon = rifle
		i += 1
		while i < group_size:
			var L: SoldierLoadout = unit.loadouts[i]
			L.role = RankGrades.Role.ASSISTANT
			L.nickname = "Ass. %d" % int(i + 1)
			L.rank_grade = RankGrades.Grade.SOLDIER
			L.weapon = rifle
			i += 1
	else:
		var group_size: int = 3
		var rifle: WeaponSpec = preload("res://resources/weapons/m1_carbine.tres")
		#var smg: WeaponSpec = preload("res://resources/weapons/m3_grease_gun.tres")
		var mortar: WeaponSpec = preload("res://resources/weapons/m2_60mm_mortar.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var leader: SoldierLoadout = unit.loadouts[i]
		leader.role = RankGrades.Role.TEAM_LEADER
		leader.nickname = "Squad Leader"
		leader.rank_grade = RankGrades.Grade.TEAM_LEADER
		leader.weapon = rifle
		i += 1
		var gunner: SoldierLoadout = unit.loadouts[i]
		gunner.role = RankGrades.Role.GUNNER
		gunner.nickname = "Gunner"
		gunner.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
		gunner.weapon = mortar
		i += 1
		var loader: SoldierLoadout = unit.loadouts[i]
		loader.role = RankGrades.Role.LOADER
		loader.nickname = "Loader"
		loader.rank_grade = RankGrades.Grade.SOLDIER
		loader.weapon = rifle
		i += 1
		while i < group_size:
			var L: SoldierLoadout = unit.loadouts[i]
			L.role = RankGrades.Role.ASSISTANT
			L.nickname = "Ass. %d" % int(i + 1)
			L.rank_grade = RankGrades.Grade.SOLDIER
			L.weapon = rifle
			i += 1
	unit.notify_property_list_changed()


static func make_medium_mortar_squad(unit: Unit) -> void:
	if unit.team == 0:
		var group_size: int = 8
		var rifle: WeaponSpec = preload("res://resources/weapons/kar98.tres")
		#var smg: WeaponSpec = preload("res://resources/weapons/mp40.tres")
		var mortar: WeaponSpec = preload("res://resources/weapons/granatwerfer_34.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var leader: SoldierLoadout = unit.loadouts[i]
		leader.role = RankGrades.Role.SQUAD_LEADER
		leader.nickname = "Squad Leader"
		leader.rank_grade = RankGrades.Grade.SQUAD_LEADER
		leader.weapon = rifle
		i += 1
		var gunner: SoldierLoadout = unit.loadouts[i]
		gunner.role = RankGrades.Role.GUNNER
		gunner.nickname = "Gunner"
		gunner.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
		gunner.weapon = mortar
		i += 1
		var loader: SoldierLoadout = unit.loadouts[i]
		loader.role = RankGrades.Role.LOADER
		loader.nickname = "Loader"
		loader.rank_grade = RankGrades.Grade.SOLDIER
		loader.weapon = rifle
		i += 1
		while i < group_size:
			var L: SoldierLoadout = unit.loadouts[i]
			L.role = RankGrades.Role.ASSISTANT
			L.nickname = "Ass. %d" % int(i + 1)
			L.rank_grade = RankGrades.Grade.SOLDIER
			L.weapon = rifle
			i += 1
	else:
		var group_size: int = 9
		var rifle: WeaponSpec = preload("res://resources/weapons/m1_carbine.tres")
		#var smg: WeaponSpec = preload("res://resources/weapons/m3_grease_gun.tres")
		var mortar: WeaponSpec = preload("res://resources/weapons/m1_81mm_mortar.tres")
		unit._resize_loadouts(group_size)
		var i: int = 0
		var leader: SoldierLoadout = unit.loadouts[i]
		leader.role = RankGrades.Role.SQUAD_LEADER
		leader.nickname = "Squad Leader"
		leader.rank_grade = RankGrades.Grade.SQUAD_LEADER
		leader.weapon = rifle
		i += 1
		var gunner: SoldierLoadout = unit.loadouts[i]
		gunner.role = RankGrades.Role.GUNNER
		gunner.nickname = "Gunner"
		gunner.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
		gunner.weapon = mortar
		i += 1
		var loader: SoldierLoadout = unit.loadouts[i]
		loader.role = RankGrades.Role.LOADER
		loader.nickname = "Loader"
		loader.rank_grade = RankGrades.Grade.SOLDIER
		loader.weapon = rifle
		i += 1
		while i < group_size:
			var L: SoldierLoadout = unit.loadouts[i]
			L.role = RankGrades.Role.ASSISTANT
			L.nickname = "Ass. %d" % int(i + 1)
			L.rank_grade = RankGrades.Grade.SOLDIER
			L.weapon = rifle
			i += 1
	unit.notify_property_list_changed()
