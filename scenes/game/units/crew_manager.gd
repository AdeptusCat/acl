# CrewManager.gd
extends Node
class_name CrewManager


signal crew_changed(slot_id: int)

# You can store skill as a dictionary key on Soldier, e.g. skills["gpmg"]
# Soldier should expose: alive: bool, role: Role, position: Vector2, state flags.

class CrewSlot:
	var id: int = -1
	var spec: WeaponSpec                # the crew-served weapon spec
	var gunner: Soldier = null
	var loader: Soldier = null
	var anchor: Node2D = null           # where the weapon is (for distance checks)

	func is_undermanned() -> bool:
		if spec == null:
			return true
		if spec.crew_required <= 1:
			return false
		if gunner == null:
			return true
		if spec.crew_required >= 2:
			if loader == null:
				return true
		return false

# Managed state
var slots: Array[CrewSlot] = []
var squad_members: Array[Soldier] = []

func setup(squad: Array[Soldier], crew_slots: Array[CrewSlot]) -> void:
	squad_members = squad
	slots = crew_slots
