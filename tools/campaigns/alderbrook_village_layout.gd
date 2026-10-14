class_name AlderbrookVillageLayout
extends RefCounted

const SIZE: Vector2i = Vector2i(26, 18)
const ROUTES: Array[Array] = [
	[Vector3(-1, 8.4, 0), Vector3(5, 8, 0), Vector3(10, 8.2, 0.12), Vector3(15, 9, 0), Vector3(20, 8.3, 0), Vector3(26, 8.7, 0.05)],
	[Vector3(6, 8, -0.6), Vector3(9, 5.6, -0.9), Vector3(12, 3, 0), Vector3(17, 3.3, 0.1), Vector3(23, 4.8, 0), Vector3(26, 4.4, -0.1)],
	[Vector3(7, 8.05, 0.65), Vector3(10, 11.2, 0.65), Vector3(14, 13.3, 0.1), Vector3(20, 14.1, 0), Vector3(26, 13.6, -0.08)],
	[Vector3(14, 3.1, 0.9), Vector3(16, 5.5, 1.1), Vector3(18, 8.5, 1.2), Vector3(21, 11.8, 0.8), Vector3(23, 13.9, 0.8)],
	[Vector3(20, 1.5, 1.2), Vector3(21.5, 5, 1.5), Vector3(23, 8.5, 1.4), Vector3(24, 10.8, 1.5), Vector3(26, 13.6, 0.4)],
	[Vector3(-1, 3.5, 0), Vector3(4, 3.5, 0), Vector3(8, 3.8, -0.15), Vector3(12, 3, 0)],
]
const PLAYER: Array[Array] = [
	[1, "hq", 2, 3], [1, "rifle", 3, 2], [1, "rifle", 3, 3], [1, "rifle", 3, 4], [1, "mg", 2, 5],
	[2, "hq", 2, 8], [2, "rifle", 3, 7], [2, "rifle", 3, 8], [2, "rifle", 3, 9], [2, "mg", 2, 10],
	[3, "hq", 2, 13], [3, "rifle", 3, 12], [3, "rifle", 3, 13], [3, "rifle", 3, 14], [3, "mg", 2, 15],
	[0, "company_hq", 1, 8], [0, "light_mortar", 1, 10],
]
const ENEMY: Array[Array] = [
	[1, "hq", 17, 4], [1, "rifle", 13, 4], [1, "rifle", 15, 6], [1, "mg", 14, 5],
	[2, "hq", 22, 9], [2, "rifle", 18, 7], [2, "rifle", 19, 12], [2, "mg", 20, 10],
	[3, "hq", 21, 14], [3, "rifle", 14, 12], [3, "rifle", 18, 15], [3, "mg", 16, 15],
	[0, "company_hq", 24, 11], [0, "medium_mortar", 24, 2],
]
const ALLIED_MARKERS: Array[Array] = [[1, 14, 5], [2, 20, 10], [3, 16, 15], [4, 2, 8]]
const AXIS_MARKERS: Array[Array] = [[1, 20, 10], [2, 14, 5], [3, 16, 15], [0, 25, 8], [0, 25, 13], [4, 22, 9]]
const BRIEFING: String = "Road to Alderbrook - mission 5 of 5.\n\nYour company attacks from farmland into Alderbrook. Hedges divide the fields, an orchard screens the northern estate, and scattered timber farms lead toward denser town blocks. Branching roads and garden lanes connect the approaches. A small pond lies off the southern flank; there is no river crossing.\n\n[b]A - Orchard estate:[/b] clear the orchard edge and take the stone estate house. Its garden walls give the defenders covered positions, with openings toward the lanes.\n[b]B - Market hall:[/b] the main road bends into the town center. Houses and workshop courts break the sight lines. Use a flank street to reach the hall rather than sending the company down the open road.\n[b]C - Timber yard:[/b] barns, sheds and hedged gardens form the southern approach. Capture the large workshop, then move through the connecting streets toward the market.\n\nThree rifle platoons, machine-gun teams, company headquarters and a light mortar support the attack. Establish covering fire and keep a reserve able to switch between districts. Enemy survivors may withdraw through the eastern roads after their defense breaks.\n\n[b]Major Victory:[/b] hold A, B and C for 45 seconds each, destroy six enemy units, and allow no more than one enemy exit. Victory is assessed at the deadline.\n\n[b]Minor Victory:[/b] hold B for 45 seconds and destroy three enemy units at the deadline."

