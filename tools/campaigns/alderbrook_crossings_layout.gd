class_name AlderbrookCrossingsLayout
extends RefCounted

# ASL board 41: a single-hex-wide winding river between farms and buildings.
const SIZE: Vector2i = Vector2i(28, 20)
const CHANNEL: Array[Vector2i] = [
	Vector2i(14, 0), Vector2i(14, 1), Vector2i(13, 1), Vector2i(13, 2), Vector2i(12, 3), Vector2i(11, 3),
	Vector2i(11, 4), Vector2i(11, 5), Vector2i(11, 6), Vector2i(12, 7), Vector2i(13, 7), Vector2i(14, 8),
	Vector2i(15, 8), Vector2i(16, 9), Vector2i(16, 10), Vector2i(17, 10), Vector2i(17, 11), Vector2i(17, 12),
	Vector2i(17, 13), Vector2i(17, 14), Vector2i(16, 15), Vector2i(16, 16), Vector2i(15, 16), Vector2i(15, 17),
	Vector2i(14, 18), Vector2i(14, 19),
]
const BRIDGES: Array[Vector2i] = [Vector2i(11, 5), Vector2i(17, 14)]
const ROUTES: Array[Array] = [
	[Vector3(-1, 3.5, 0), Vector3(4, 3.8, 0.2), Vector3(7, 5.25, 0), Vector3(15, 5.25, 0), Vector3(20, 4.2, 0), Vector3(24, 5, 0), Vector3(28, 4.6, -0.1)],
	[Vector3(-1, 16.2, 0), Vector3(4, 16, -0.1), Vector3(9, 15.3, -0.2), Vector3(12, 14.25, 0), Vector3(20, 14.25, 0), Vector3(24, 16, 0), Vector3(28, 15.5, -0.1)],
	[Vector3(4, 3.8, 3), Vector3(4.5, 8, 4), Vector3(6, 11, 1.3), Vector3(9, 15.3, 0.8)],
	[Vector3(20, 4.2, 3), Vector3(21, 8, 2), Vector3(23, 11, 1.3), Vector3(24, 16, 4)],
]
const PLAYER: Array[Array] = [
	[1, "hq", 2, 6], [1, "rifle", 3, 5], [1, "rifle", 2, 5], [1, "rifle", 3, 6], [1, "mg", 3, 7],
	[2, "hq", 3, 15], [2, "rifle", 4, 13], [2, "rifle", 5, 13], [2, "rifle", 6, 14], [2, "mg", 4, 15],
	[0, "company_hq", 2, 10],
]
const ENEMY: Array[Array] = [
	[1, "hq", 18, 3], [1, "rifle", 15, 4], [1, "rifle", 16, 7], [1, "mg", 17, 3],
	[2, "hq", 25, 13], [2, "rifle", 21, 13], [2, "rifle", 21, 16], [2, "mg", 22, 14],
	[0, "company_hq", 25, 9],
]
const ALLIED_MARKERS: Array[Array] = [[1, 15, 4], [2, 21, 13], [0, 26, 5], [0, 26, 16], [4, 2, 10]]
const AXIS_MARKERS: Array[Array] = [[1, 15, 4], [2, 21, 13], [4, 25, 9]]
const BRIEFING: String = "Road to Alderbrook - mission 4 of 5.\n\nTwo reinforced platoons approach a narrow, single-hex-wide river winding through farmland. The northern bridge crosses beside a stone hamlet; the southern bridge lies farther east at a wooded timber yard. The crossings are staggered around the river's S bend. Water is impassable everywhere except the two bridges.\n\n[b]A - Bridge hamlet:[/b] hedged fields lead to the northern bridge. Establish covering fire on the west bank, cross and secure the stone bridgehead house. Village walls and orchard edges give the defenders several positions near the road.\n[b]B - Timber crossing:[/b] the southern farm lane approaches through woods and orchard plots. Clear the timber buildings beyond the bridge. The southern bridgehead has more woodland but fewer long views than the hamlet.\n\nBank roads connect your two approaches, and an eastern lane links the enemy's bridgeheads. Coordinate both platoons; leave a garrison at each objective while the remaining squads advance toward the eastern Exit markers.\n\n[b]Major Victory:[/b] hold A and B for 20 seconds each and exit three units east. All three requirements must be met together.\n\n[b]Minor Victory:[/b] exit two units by the deadline."
