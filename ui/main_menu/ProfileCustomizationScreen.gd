extends Control

const CATALOG = preload("res://managers/AchievementCatalog.gd")

@onready var category_buttons: HFlowContainer = $Root/Margin/Contents/Categories
@onready var selected_label: Label = $Root/Margin/Contents/Selected
@onready var identity_preview: HBoxContainer = $Root/Margin/Contents/IdentityPreview
@onready var unlock_all_testing_button: Button = (
	$Root/Margin/Contents/UnlockAllTestingButton
)
@onready var items: VBoxContainer = $Root/Margin/Contents/ListPanel/Margin/Scroll/Items
@onready var back_button: Button = $Root/Margin/Contents/Header/BackButton

var _types: Array[String] = []
var _selected_type: String = ""
var _transitioning := false
var _identity_avatar: TextureRect
var _identity_frame: TextureRect
var _identity_emblem: TextureRect
var _unlock_all_confirmation: ConfirmationDialog


func _ready() -> void:
	back_button.pressed.connect(_return_to_menu)
	unlock_all_testing_button.visible = (
		OS.is_debug_build()
		and bool(ProjectSettings.get_setting(
			"crystal_defense/development_mode",
			false
		))
	)
	unlock_all_testing_button.pressed.connect(_confirm_unlock_all_cosmetics)
	_unlock_all_confirmation = ConfirmationDialog.new()
	_unlock_all_confirmation.title = "Unlock All Cosmetics (Testing)"
	_unlock_all_confirmation.dialog_text = (
		"Unlock every catalog cosmetic for this profile? This only adds "
		+ "cosmetic unlock records; it does not unlock achievements or grant "
		+ "Essence. You can use the testing achievement reset to clear these "
		+ "cosmetic unlocks later."
	)
	_unlock_all_confirmation.ok_button_text = "UNLOCK ALL"
	_unlock_all_confirmation.cancel_button_text = "CANCEL"
	_unlock_all_confirmation.confirmed.connect(_unlock_all_cosmetics)
	add_child(_unlock_all_confirmation)
	_build_identity_preview()
	AchievementManager.cosmetic_selection_changed.connect(_on_cosmetics_changed)
	AchievementManager.cosmetic_unlocked.connect(_on_cosmetics_changed)
	AchievementManager.achievements_reset.connect(_on_cosmetics_changed)
	_types = AchievementManager.get_cosmetic_types()
	_selected_type = _types[0] if not _types.is_empty() else ""
	_build_tabs()
	_refresh()


func _build_identity_preview() -> void:
	var avatar_stack := Control.new()
	avatar_stack.custom_minimum_size = Vector2(78, 78)
	identity_preview.add_child(avatar_stack)
	_identity_avatar = _make_preview_texture(avatar_stack)
	_identity_frame = _make_preview_texture(avatar_stack)
	_identity_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_identity_emblem = TextureRect.new()
	_identity_emblem.custom_minimum_size = Vector2(58, 58)
	_identity_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_identity_emblem.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	identity_preview.add_child(_identity_emblem)
	var note := Label.new()
	note.text = "Current profile identity"
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity_preview.add_child(note)


func _make_preview_texture(parent: Control) -> TextureRect:
	var preview := TextureRect.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(preview)
	return preview


func _exit_tree() -> void:
	if AchievementManager.cosmetic_selection_changed.is_connected(_on_cosmetics_changed):
		AchievementManager.cosmetic_selection_changed.disconnect(_on_cosmetics_changed)
	if AchievementManager.cosmetic_unlocked.is_connected(_on_cosmetics_changed):
		AchievementManager.cosmetic_unlocked.disconnect(_on_cosmetics_changed)
	if AchievementManager.achievements_reset.is_connected(_on_cosmetics_changed):
		AchievementManager.achievements_reset.disconnect(_on_cosmetics_changed)


func _build_tabs() -> void:
	for type_id in _types:
		var button := Button.new()
		button.text = CATALOG.get_cosmetic_type_name(type_id)
		button.toggle_mode = true
		button.button_pressed = type_id == _selected_type
		button.set_meta("type_id", type_id)
		button.pressed.connect(_select_type.bind(type_id))
		category_buttons.add_child(button)


func _select_type(type_id: String) -> void:
	_selected_type = type_id
	for button in category_buttons.get_children():
		button.button_pressed = button.get_meta("type_id", "") == type_id
	_refresh()


func _on_cosmetics_changed(_a = null, _b = null) -> void:
	_refresh()


func _confirm_unlock_all_cosmetics() -> void:
	_unlock_all_confirmation.popup_centered()


func _unlock_all_cosmetics() -> void:
	if not AchievementManager.unlock_all_cosmetics_for_testing():
		push_error("Could not unlock all cosmetics for testing.")
		return
	_refresh()


func _refresh() -> void:
	for child in items.get_children():
		child.queue_free()
	_refresh_identity_preview()
	if _selected_type.is_empty():
		selected_label.text = "No cosmetic categories available."
		return

	var selected_id := AchievementManager.get_selected_cosmetic(_selected_type)
	selected_label.text = "Selected: %s" % (
		CATALOG.get_cosmetic_name(selected_id) if not selected_id.is_empty() else "Default"
	)

	var cosmetics := AchievementManager.get_cosmetic_catalog(_selected_type)
	for cosmetic in cosmetics:
		var cosmetic_id := String(cosmetic["id"])
		_add_row(
			String(cosmetic["name"]),
			String(cosmetic["description"]),
			String(cosmetic["source_title"]),
			String(cosmetic["source_description"]),
			bool(cosmetic["unlocked"]),
			cosmetic_id == selected_id,
			cosmetic_id,
			cosmetic.get("texture") as Texture2D
		)
	if cosmetics.is_empty():
		var empty := Label.new()
		empty.text = "No cosmetics available in this category yet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		items.add_child(empty)


func _refresh_identity_preview() -> void:
	_identity_avatar.texture = AchievementManager.get_active_cosmetic_texture(
		"user_avatar"
	)
	_identity_frame.texture = AchievementManager.get_active_cosmetic_texture(
		"profile_frame"
	)
	_identity_emblem.texture = AchievementManager.get_active_cosmetic_texture(
		"emblem"
	)


func _add_row(
	display_name: String,
	description: String,
	unlock_title: String,
	unlock_description: String,
	unlocked: bool,
	is_selected: bool,
	cosmetic_id: String,
	texture: Texture2D
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	items.add_child(row)

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(88, 64)
	preview.texture = texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(preview)
	if texture == null:
		var fallback := Label.new()
		fallback.text = "Artwork unavailable"
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preview.add_child(fallback)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)
	var name_label := Label.new()
	name_label.text = display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 18)
	text_box.add_child(name_label)
	var status := "SELECTED" if is_selected else ("Unlocked" if unlocked else "Locked")
	var detail_label := Label.new()
	detail_label.text = "%s  |  %s" % [status, description]
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 13)
	text_box.add_child(detail_label)
	var requirement_label := Label.new()
	requirement_label.text = (
		"Unlock: %s — %s" % [unlock_title, unlock_description]
		if not unlocked
		else unlock_title
	)
	requirement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	requirement_label.add_theme_font_size_override("font_size", 12)
	text_box.add_child(requirement_label)

	var button := Button.new()
	button.custom_minimum_size = Vector2(120, 40)
	button.text = "USE DEFAULT" if cosmetic_id.is_empty() else "SELECT"
	button.disabled = not unlocked or is_selected
	button.pressed.connect(_on_select_pressed.bind(cosmetic_id))
	row.add_child(button)


func _on_select_pressed(cosmetic_id: String) -> void:
	if not AchievementManager.select_cosmetic(_selected_type, cosmetic_id):
		push_warning("Could not select cosmetic '%s'." % cosmetic_id)
		_refresh()


func _return_to_menu() -> void:
	if _transitioning:
		return
	_transitioning = true
	var error := get_tree().change_scene_to_file("res://ui/main_menu/MainMenu.tscn")
	if error != OK:
		_transitioning = false
		push_error("Could not return to the main menu (error %d)." % error)
