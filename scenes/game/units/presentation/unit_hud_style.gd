extends RefCounted
class_name UnitHudStyle

const PLATOON_COLORS: Array[Color] = [Color("79bade"), Color("e3b769"), Color("a79bdd"), Color("75c7b5"), Color("df927d")]
const SUPPORT_COLOR: Color = Color("c9b78a")


static func formation_color(unit: Unit) -> Color:
	if unit.platoon <= 0 or unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
		return SUPPORT_COLOR
	return PLATOON_COLORS[(unit.platoon - 1) % PLATOON_COLORS.size()]
