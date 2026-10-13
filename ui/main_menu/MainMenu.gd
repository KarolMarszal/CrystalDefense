extends Control

const GAME_SCENE_PATH: String = "res://game/Game.tscn"
const INVENTORY_SCENE_PATH: String = "res://ui/main_menu/CrystalInventory.tscn"
const SKILL_TREE_SCENE_PATH: String = "res://ui/SkillTreeScreen.tscn"

@onready var start_button: Button = $CenterPanel/MarginContainer/MenuContents/StartButton
@onready var inventory_button: Button = $CenterPanel/MarginContainer/MenuContents/InventoryButton
@onready var skill_tree_button: Button = $CenterPanel/MarginContainer/MenuContents/SkillTreeButton
@onready var reset_skills_button: Button = $CenterPanel/MarginContainer/MenuContents/ResetSkillsButton
@onready var quit_button: Button = $CenterPanel/MarginContainer/MenuContents/QuitButton
@onready var reset_confirmation: ConfirmationDialog = $ResetSkillsConfirmation

var _transitioning: bool = false


func _ready() -> void:
	start_button.pressed.connect(_open_game)
	inventory_button.pressed.connect(_open_inventory)
	skill_tree_button.pressed.connect(_open_skill_tree)
	reset_skills_button.pressed.connect(_confirm_reset_skills)
	reset_confirmation.confirmed.connect(_reset_skills)
	quit_button.pressed.connect(_quit_game)
	CrystalInventory.profile_changed.connect(_on_profile_changed)
	_update_inventory_access()


func _exit_tree() -> void:
	if CrystalInventory.profile_changed.is_connected(_on_profile_changed):
		CrystalInventory.profile_changed.disconnect(_on_profile_changed)


func _on_profile_changed(_profile: Dictionary) -> void:
	_update_inventory_access()


func _update_inventory_access() -> void:
	inventory_button.visible = CrystalInventory.is_crystal_inventory_unlocked()


func _open_game() -> void:
	_change_scene(GAME_SCENE_PATH)


func _open_inventory() -> void:
	_change_scene(INVENTORY_SCENE_PATH)


func _open_skill_tree() -> void:
	_change_scene(SKILL_TREE_SCENE_PATH)


func _confirm_reset_skills() -> void:
	reset_confirmation.popup_centered()


func _reset_skills() -> void:
	if not CrystalInventory.reset_purchased_skill_nodes():
		push_warning(
			"Could not reset purchased skills: %s"
			% CrystalInventory.last_save_message
		)


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
