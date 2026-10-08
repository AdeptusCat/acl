class_name PositionCandidate
extends RefCounted

var hex: Vector2i = Vector2i.ZERO
var index: int = -1
var score: float = -INF
var features: Dictionary = {}
var path: Array[Vector2i] = []
