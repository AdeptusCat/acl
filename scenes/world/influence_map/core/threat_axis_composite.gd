class_name ThreatAxisComposite
extends RefCounted


var threat_axis: ThreatAxis = null
var composite: PackedFloat32Array = PackedFloat32Array()


func configure(
	p_threat_axis: ThreatAxis,
	p_composite: PackedFloat32Array
) -> void:
	threat_axis = p_threat_axis
	composite = p_composite
