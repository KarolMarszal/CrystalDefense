class_name EnemyCamp
extends Node2D

@onready var _storage: Node2D = $Storage
var _cosmetic_visual: Sprite2D


func _ready() -> void:
	AchievementManager.cosmetic_selection_changed.connect(
		_on_cosmetic_selection_changed
	)
	_apply_camp_skin()


func _exit_tree() -> void:
	if AchievementManager.cosmetic_selection_changed.is_connected(
		_on_cosmetic_selection_changed
	):
		AchievementManager.cosmetic_selection_changed.disconnect(
			_on_cosmetic_selection_changed
		)


func _on_cosmetic_selection_changed(
	cosmetic_type: String,
	_cosmetic_id: String
) -> void:
	if cosmetic_type == "enemy_camp_skin":
		_apply_camp_skin()


func _apply_camp_skin() -> void:
	if AchievementManager.get_selected_cosmetic("enemy_camp_skin").is_empty():
		if is_instance_valid(_cosmetic_visual):
			_cosmetic_visual.visible = false
		return
	var texture := AchievementManager.get_active_cosmetic_texture("enemy_camp_skin")
	if texture == null:
		if is_instance_valid(_cosmetic_visual):
			_cosmetic_visual.visible = false
		return
	if not is_instance_valid(_cosmetic_visual):
		_cosmetic_visual = Sprite2D.new()
		_cosmetic_visual.name = "CosmeticSkinVisual"
		_cosmetic_visual.position = Vector2(64, -57)
		_cosmetic_visual.scale = Vector2(0.7, 0.7)
		_cosmetic_visual.z_index = 1
		add_child(_cosmetic_visual)
	_cosmetic_visual.texture = texture
	_cosmetic_visual.visible = true


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
