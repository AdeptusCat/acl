class_name LosRebuildJob
extends RefCounted


var influence_map: InfluenceMap = null
var los_lookup: Dictionary = {}
var sources: Array[ProjectionSource] = []
var projection_modes: Array[bool] = []
var cursor: int = 0
var defending_team: int = -1
