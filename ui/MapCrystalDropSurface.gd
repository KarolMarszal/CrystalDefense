extends Control

var game: Node


func set_game(game_node: Node) -> void:
	game = game_node


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if (
		not data is Dictionary
		or data.get("type") != "run_crystal"
		or not is_instance_valid(game)
	):
		_clear_drop_highlights()
		return false

	var target := game.get_tower_at_screen_position(at_position) as Tower
	game.update_map_crystal_drop_highlights(data, target)
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if is_instance_valid(game):
		game.drop_crystal_on_map(data, at_position)
	_clear_drop_highlights()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_highlights()


func _clear_drop_highlights() -> void:
	if is_instance_valid(game):
		game.clear_map_crystal_drop_highlights()
