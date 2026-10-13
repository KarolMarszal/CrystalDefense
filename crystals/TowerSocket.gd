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


func can_install(crystal_data: CrystalData, crystal_level: int = 1) -> bool:
	return crystal_data != null and is_empty() and crystal_level >= 1


func install(crystal_data: CrystalData, crystal_level: int = 1) -> bool:
	if not can_install(crystal_data, crystal_level):
		return false

	_crystal = CrystalInstance.new(crystal_data, crystal_level)
	return true


func can_replace(crystal_data: CrystalData, crystal_level: int = 1) -> bool:
	return crystal_data != null and not is_empty() and crystal_level >= 1


func replace(crystal_data: CrystalData, crystal_level: int = 1) -> CrystalInstance:
	if not can_replace(crystal_data, crystal_level):
		return null

	var previous := _crystal
	_crystal = CrystalInstance.new(crystal_data, crystal_level)
	return previous


func restore(crystal_instance: CrystalInstance) -> bool:
	if crystal_instance == null or is_empty():
		return false

	_crystal = crystal_instance
	return true


func remove() -> CrystalInstance:
	var removed_crystal := _crystal
	_crystal = null
	return removed_crystal
