extends Control

const GAME_SCENE_PATH: String = "res://game/Game.tscn"
const INVENTORY_SCENE_PATH: String = "res://ui/main_menu/CrystalInventory.tscn"

@onready var start_button: Button = $CenterPanel/MarginContainer/MenuContents/StartButton
@onready var inventory_button: Button = $CenterPanel/MarginContainer/MenuContents/InventoryButton
@onready var quit_button: Button = $CenterPanel/MarginContainer/MenuContents/QuitButton

var _transitioning: bool = false


func _ready() -> void:
	start_button.pressed.connect(_open_game)
	inventory_button.pressed.connect(_open_inventory)
	quit_button.pressed.connect(_quit_game)


func _open_game() -> void:
	_change_scene(GAME_SCENE_PATH)


func _open_inventory() -> void:
	_change_scene(INVENTORY_SCENE_PATH)


func _quit_game() -> void:
	get_tree().quit()


func _change_scene(scene_path: String) -> void:
	if _transitioning:
		return

	_transitioning = true
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		_transitioning = false
		push_error("Could not open scene '%s' (error %d)." % [scene_path, error])
