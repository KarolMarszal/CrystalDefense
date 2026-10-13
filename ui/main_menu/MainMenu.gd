extends Control

const GAME_SCENE_PATH: String = "res://game/Game.tscn"
const INVENTORY_SCENE_PATH: String = "res://ui/main_menu/CrystalInventory.tscn"
const SKILL_TREE_SCENE_PATH: String = "res://ui/SkillTreeScreen.tscn"
const ACHIEVEMENTS_SCENE_PATH: String = "res://ui/main_menu/AchievementsScreen.tscn"
const PROFILE_SCENE_PATH: String = "res://ui/main_menu/ProfileCustomizationScreen.tscn"

@onready var start_button: Button = $CenterPanel/MarginContainer/MenuContents/StartButton
@onready var inventory_button: Button = $CenterPanel/MarginContainer/MenuContents/InventoryButton
@onready var skill_tree_button: Button = $CenterPanel/MarginContainer/MenuContents/SkillTreeButton
@onready var achievements_button: Button = $CenterPanel/MarginContainer/MenuContents/AchievementsButton
@onready var profile_button: Button = $CenterPanel/MarginContainer/MenuContents/ProfileButton
@onready var reset_skills_button: Button = $CenterPanel/MarginContainer/MenuContents/ResetSkillsButton
@onready var quit_button: Button = $CenterPanel/MarginContainer/MenuContents/QuitButton
@onready var reset_confirmation: ConfirmationDialog = $ResetSkillsConfirmation

var _transitioning: bool = false
var _profile_avatar: TextureRect
var _profile_frame: TextureRect
var _profile_emblem: TextureRect


func _ready() -> void:
	start_button.pressed.connect(_open_game)
	inventory_button.pressed.connect(_open_inventory)
	skill_tree_button.pressed.connect(_open_skill_tree)
	achievements_button.pressed.connect(_open_achievements)
	profile_button.pressed.connect(_open_profile)
	reset_skills_button.pressed.connect(_confirm_reset_skills)
	reset_confirmation.confirmed.connect(_reset_skills)
	quit_button.pressed.connect(_quit_game)
	CrystalInventory.profile_changed.connect(_on_profile_changed)
	AchievementManager.cosmetic_selection_changed.connect(
		_on_cosmetic_selection_changed
	)
	_build_profile_identity()
	_refresh_profile_identity()
	_update_inventory_access()


func _exit_tree() -> void:
	if CrystalInventory.profile_changed.is_connected(_on_profile_changed):
		CrystalInventory.profile_changed.disconnect(_on_profile_changed)
	if AchievementManager.cosmetic_selection_changed.is_connected(
		_on_cosmetic_selection_changed
	):
		AchievementManager.cosmetic_selection_changed.disconnect(
			_on_cosmetic_selection_changed
		)


func _on_profile_changed(_profile: Dictionary) -> void:
	_update_inventory_access()


func _update_inventory_access() -> void:
	inventory_button.visible = CrystalInventory.is_crystal_inventory_unlocked()


func _build_profile_identity() -> void:
	var contents := $CenterPanel/MarginContainer/MenuContents as VBoxContainer
	var title := $CenterPanel/MarginContainer/MenuContents/Title as Control
	var identity := HBoxContainer.new()
	identity.name = "ProfileIdentityPreview"
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.add_theme_constant_override("separation", 8)
	var avatar_stack := Control.new()
	avatar_stack.custom_minimum_size = Vector2(58, 58)
	identity.add_child(avatar_stack)
	_profile_avatar = _make_profile_texture(avatar_stack)
	_profile_frame = _make_profile_texture(avatar_stack)
	_profile_emblem = TextureRect.new()
	_profile_emblem.custom_minimum_size = Vector2(42, 42)
	_profile_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_profile_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	identity.add_child(_profile_emblem)
	var label := Label.new()
	label.text = "PROFILE"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity.add_child(label)
	contents.add_child(identity)
	contents.move_child(identity, title.get_index() + 1)


func _make_profile_texture(parent: Control) -> TextureRect:
	var preview := TextureRect.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(preview)
	return preview


func _on_cosmetic_selection_changed(
	_cosmetic_type: String,
	_cosmetic_id: String
) -> void:
	_refresh_profile_identity()


func _refresh_profile_identity() -> void:
	if not is_instance_valid(_profile_avatar):
		return
	_profile_avatar.texture = AchievementManager.get_active_cosmetic_texture(
		"user_avatar"
	)
	_profile_frame.texture = AchievementManager.get_active_cosmetic_texture(
		"profile_frame"
	)
	_profile_emblem.texture = AchievementManager.get_active_cosmetic_texture(
		"emblem"
	)


func _open_game() -> void:
	_change_scene(GAME_SCENE_PATH)


func _open_inventory() -> void:
	_change_scene(INVENTORY_SCENE_PATH)


func _open_skill_tree() -> void:
	_change_scene(SKILL_TREE_SCENE_PATH)


func _open_achievements() -> void:
	_change_scene(ACHIEVEMENTS_SCENE_PATH)


func _open_profile() -> void:
	_change_scene(PROFILE_SCENE_PATH)


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
