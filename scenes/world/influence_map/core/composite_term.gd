class_name CompositeTerm
extends RefCounted

var source: int = 0
var layer: int = InfluenceMap.Layer.TERRAIN_COVER
var weight: float = 0.0


func _init(p_source: int = 0, p_layer: int = InfluenceMap.Layer.TERRAIN_COVER, p_weight: float = 0.0) -> void:
	source = p_source
	layer = p_layer
	weight = p_weight
