class_name BuildSlot
extends Area2D

signal tower_built

const TOWER_SCENE: PackedScene = preload("res://towers/Tower.tscn")

@export var price: int = 0
@export var slot_size: Vector2 = Vector2(50.0, 50.0)
@export var available_for_building: bool = true:
	set(value):
		available_for_building = value
		_update_input_pickable()
		queue_redraw()

var built_tower: Node2D
var build_mode: bool = false
var _failure_flash_time: float = 0.0
var _purchase_in_progress: bool = false

var occupied: bool:
	get:
		return is_instance_valid(built_tower)


func _ready() -> void:
	add_to_group("build_slots")
	input_pickable = false

	var collision_shape := $CollisionShape2D as CollisionShape2D
	var rectangle := RectangleShape2D.new()
	rectangle.size = slot_size
	collision_shape.shape = rectangle

	GoldManager.gold_changed.connect(_on_gold_changed)
	queue_redraw()


func is_available() -> bool:
	return available_for_building and not occupied


func set_build_mode(active: bool) -> void:
	build_mode = active
	_update_input_pickable()
	queue_redraw()


func attempt_build() -> bool:
	if _purchase_in_progress or not build_mode or not is_available():
		return false

	if price <= 0 or not GoldManager.can_afford(price):
		_show_purchase_failed()
		return false

	_purchase_in_progress = true
	_update_input_pickable()
	var tower := TOWER_SCENE.instantiate() as Node2D
	if tower == null:
		push_error("BuildSlot could not instantiate Tower.tscn.")
		_purchase_in_progress = false
		_update_input_pickable()
		return false

	var game_scene := get_tree().current_scene
	if game_scene == null:
		push_error("BuildSlot cannot build without an active scene.")
		tower.free()
		_purchase_in_progress = false
		_update_input_pickable()
		return false

	if not GoldManager.spend_gold(price):
		tower.free()
		_purchase_in_progress = false
		_update_input_pickable()
		_show_purchase_failed()
		return false

	built_tower = tower
	game_scene.add_child(tower)
	tower.global_position = global_position
	tower.tree_exited.connect(_on_tower_exited, CONNECT_ONE_SHOT)
	build_mode = false
	_purchase_in_progress = false
	_update_input_pickable()
	queue_redraw()
	tower_built.emit()
	return true


func clear_occupied() -> void:
	if is_instance_valid(built_tower):
		var callback := Callable(self, "_on_tower_exited")
		if built_tower.tree_exited.is_connected(callback):
			built_tower.tree_exited.disconnect(callback)

	built_tower = null
	_update_input_pickable()
	queue_redraw()


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			attempt_build()
	elif event is InputEventScreenTouch and event.pressed:
		attempt_build()


func _process(delta: float) -> void:
	if _failure_flash_time <= 0.0:
		return

	_failure_flash_time = maxf(_failure_flash_time - delta, 0.0)
	queue_redraw()

	if _failure_flash_time == 0.0:
		set_process(false)


func _draw() -> void:
	var rect := Rect2(-slot_size / 2.0, slot_size)
	var fill_color := Color(0.18, 0.2, 0.22, 0.28)

	if occupied:
		fill_color = Color(0.85, 0.45, 0.15, 0.72)
	elif not available_for_building:
		fill_color = Color(0.35, 0.35, 0.35, 0.45)
	elif build_mode and is_available() and price > 0 and GoldManager.can_afford(price):
		fill_color = Color(0.2, 0.75, 0.3, 0.75)
	elif build_mode and is_available():
		fill_color = Color(0.75, 0.18, 0.12, 0.75)

	if _failure_flash_time > 0.0:
		fill_color = Color(1.0, 0.08, 0.05, 0.85)

	draw_rect(rect, fill_color, true)
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.9), false, 3.0)

	if build_mode and is_available():
		draw_string(
			ThemeDB.fallback_font,
			Vector2(-slot_size.x / 2.0, slot_size.y / 2.0 - 4.0),
			"%dg" % price,
			HORIZONTAL_ALIGNMENT_CENTER,
			slot_size.x,
			12,
			Color.WHITE
		)

	elif occupied:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(-slot_size.x / 2.0, slot_size.y / 2.0 - 4.0),
			"BUILT",
			HORIZONTAL_ALIGNMENT_CENTER,
			slot_size.x,
			12,
			Color.WHITE
		)


func _show_purchase_failed() -> void:
	_failure_flash_time = 0.35
	set_process(true)
	queue_redraw()


func _on_gold_changed(_amount: int) -> void:
	_update_input_pickable()
	queue_redraw()


func _on_tower_exited() -> void:
	built_tower = null
	_update_input_pickable()
	queue_redraw()


func _update_input_pickable() -> void:
	input_pickable = (
		build_mode
		and is_available()
		and not _purchase_in_progress
		and price > 0
		and GoldManager.can_afford(price)
	)
