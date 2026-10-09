class_name EnemyCamp
extends Node2D

@onready var _storage: Node2D = $Storage


func get_next_deposit_global_position() -> Vector2:
	return _storage.to_global(_get_storage_position(_get_deposited_trophy_count()))


func deposit_trophy(trophy: Trophy) -> bool:
	if not is_instance_valid(trophy) or trophy.state == Trophy.State.DEPOSITED:
		return false

	if trophy.get_parent() != null:
		trophy.reparent(_storage, true)
	else:
		_storage.add_child(trophy)

	trophy.position = _get_storage_position(_storage.get_child_count() - 1)
	trophy.set_state(Trophy.State.DEPOSITED)
	return true


func _get_deposited_trophy_count() -> int:
	var count := 0
	for item in _storage.get_children():
		if item is Trophy:
			count += 1
	return count


func _get_storage_position(index: int) -> Vector2:
	var column := index % 5
	var row := floori(float(index) / 5.0)
	return Vector2(-26.0 + column * 12.0, 5.0 - row * 12.0)
