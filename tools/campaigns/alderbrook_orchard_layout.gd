class_name AlderbrookOrchardLayout
extends RefCounted

# ASL boards 17 and 54: separated farm buildings and irregular, hedged orchards.
const SIZE: Vector2i = Vector2i(22, 16)
const ROUTES: Array[Array] = [
	[Vector3(6, -1, 1.5), Vector3(8, 2.5, 0.6), Vector3(12, 4.2, 0.15), Vector3(16, 4.7, 0.4), Vector3(19, 8, 1.7), Vector3(20, 12, 2), Vector3(22, 14, 0.4)],
	[Vector3(6, 13.5, -1), Vector3(8, 11, -0.7), Vector3(11, 9.7, -0.6), Vector3(14, 7.5, -0.9), Vector3(16, 4.7, -1.5)],
]
const PLAYER: Array[Array] = [
	[1, "hq", 4, 13], [1, "rifle", 5, 11], [1, "rifle", 6, 12], [1, "rifle", 5, 12], [1, "mg", 4, 11],
]
const ENEMY: Array[Array] = [
	[1, "hq", 17, 2], [1, "rifle", 15, 3], [1, "rifle", 10, 8], [1, "mg", 13, 5],
]
const ALLIED_MARKERS: Array[Array] = [[1, 15, 3], [2, 10, 8], [4, 4, 13]]
const AXIS_MARKERS: Array[Array] = [[1, 15, 3], [2, 10, 8], [4, 17, 2]]
const BRIEFING: String = "Road to Alderbrook - mission 2 of 5.\n\nYour platoon and machine-gun team approach an orchard estate from the southwest. Irregular orchard plots and hedges divide the ground into short fields of fire. The main road enters from the northwest, bends below the farmhouse and leaves through the eastern fields. A narrower farm lane winds south toward your assembly area.\n\n[b]B - Orchard barn:[/b] the barn anchors the middle of the estate. Hedged orchards screen the western approach, but gaps and the farm lane expose troops crossing between plots. Establish the machine gun before advancing through the next opening.\n[b]A - Farmhouse:[/b] the northern stone farmhouse and its walled yard command the final approach. Work through the orchard compartments or make a wider, more exposed move through the eastern fields. Keep a rifle squad available to protect the barn after taking it.\n\n[b]Major Victory:[/b] destroy two enemy units and hold the farmhouse at A for 30 seconds. Both requirements must be met.\n\n[b]Minor Victory:[/b] hold the orchard barn at B for 30 seconds at the deadline."
