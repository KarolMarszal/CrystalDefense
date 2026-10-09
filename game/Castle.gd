class_name Castle
extends Node2D

signal treasury_count_changed(count: int)
signal remaining_trophies_changed(remaining: int, total: int)

const TROPHY_SCENE: PackedScene = preload("res://game/Trophy.tscn")

@export_range(0, 100, 1) var starting_trophy_count: int = 5

var permanently_lost_trophies: int = 0
var _permanently_lost_trophy_ids: Dictionary = {}

@onready var _treasury: Node2D = $Treasury


func _ready() -> void:
	for index in range(starting_trophy_count):
		var trophy := TROPHY_SCENE.instantiate() as Trophy
		trophy.trophy_id = StringName("trophy_%d" % (index + 1))
		trophy.set_state(Trophy.State.TREASURY)
		_treasury.add_child(trophy)
		_position_trophy(trophy, index)

	treasury_count_changed.emit(get_treasury_count())
	remaining_trophies_changed.emit(get_remaining_trophy_count(), get_total_trophy_count())


func get_total_trophy_count() -> int:
	return max(starting_trophy_count, 0)


func get_remaining_trophy_count() -> int:
	return max(get_total_trophy_count() - permanently_lost_trophies, 0)


func get_treasury_count() -> int:
	var count := 0
	for item in _treasury.get_children():
		if item is Trophy:
			count += 1
	return count


func register_permanent_trophy_loss(trophy_id: StringName) -> void:
	if trophy_id.is_empty() or _permanently_lost_trophy_ids.has(trophy_id):
		return
	if permanently_lost_trophies >= get_total_trophy_count():
		return

	_permanently_lost_trophy_ids[trophy_id] = true
	permanently_lost_trophies += 1
	remaining_trophies_changed.emit(get_remaining_trophy_count(), get_total_trophy_count())


func try_steal_trophy() -> Trophy:
	for item in _treasury.get_children():
		if item is Trophy:
			return take_trophy(item.trophy_id)
	return null


func take_trophy(trophy_id: StringName) -> Trophy:
	for index in range(_treasury.get_child_count()):
		var item := _treasury.get_child(index)
		if item is Trophy and item.trophy_id == trophy_id:
			var trophy := item as Trophy
			_treasury.remove_child(trophy)
			treasury_count_changed.emit(get_treasury_count())
			return trophy

	push_warning("Castle treasury has no Trophy with ID '%s'." % trophy_id)
	return null


func return_trophy(trophy: Trophy) -> bool:
	if not is_instance_valid(trophy):
		push_warning("Cannot return an invalid Trophy to the Castle.")
		return false
	if trophy.get_parent() == _treasury:
		return false
	if trophy.get_parent() != null:
		trophy.get_parent().remove_child(trophy)

	_treasury.add_child(trophy)
	trophy.set_state(Trophy.State.TREASURY)
	_position_trophy(trophy, get_treasury_count() - 1)
	treasury_count_changed.emit(get_treasury_count())
	return true


func _position_trophy(trophy: Trophy, index: int) -> void:
	var column := index % 4
	var row := floori(float(index) / 4.0)
	trophy.position = Vector2(-31.0 + column * 20.0, -20.0 + row * 18.0)
