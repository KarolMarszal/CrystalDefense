class_name CrystalInstance
extends RefCounted

var definition: CrystalData
var level: int = 1:
	set(value):
		level = maxi(value, 1)


func _init(crystal_definition: CrystalData, initial_level: int = 1) -> void:
	definition = crystal_definition
	level = initial_level
