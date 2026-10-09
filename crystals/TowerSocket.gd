class_name TowerSocket
extends RefCounted

enum SocketType {
	MAIN
}

var socket_type: SocketType
var _crystal: CrystalInstance

var crystal: CrystalInstance:
	get:
		return _crystal


func _init(type: SocketType = SocketType.MAIN) -> void:
	socket_type = type


func is_empty() -> bool:
	return _crystal == null


func install(crystal_data: CrystalData, crystal_level: int = 1) -> bool:
	if crystal_data == null or not is_empty():
		return false

	_crystal = CrystalInstance.new(crystal_data, crystal_level)
	return true


func remove() -> CrystalInstance:
	var removed_crystal := _crystal
	_crystal = null
	return removed_crystal
