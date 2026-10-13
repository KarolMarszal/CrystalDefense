extends Control

const CATALOG = preload("res://managers/AchievementCatalog.gd")

@onready var category_buttons: HFlowContainer = $Root/Margin/Contents/Categories
@onready var selected_label: Label = $Root/Margin/Contents/Selected
@onready var items: VBoxContainer = $Root/Margin/Contents/ListPanel/Margin/Scroll/Items
@onready var back_button: Button = $Root/Margin/Contents/Header/BackButton

var _types: Array[String] = []
var _selected_type: String = ""
var _transitioning := false


func _ready() -> void:
	back_button.pressed.connect(_return_to_menu)
	AchievementManager.cosmetic_selection_changed.connect(_on_cosmetics_changed)
	AchievementManager.cosmetic_unlocked.connect(_on_cosmetics_changed)
	AchievementManager.achievements_reset.connect(_on_cosmetics_changed)
	_types = AchievementManager.get_cosmetic_types()
	_selected_type = _types[0] if not _types.is_empty() else ""
	_build_tabs()
	_refresh()


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


func _refresh() -> void:
	for child in items.get_children():
		child.queue_free()
	if _selected_type.is_empty():
		selected_label.text = "No cosmetic categories available."
		return

	var selected_id := AchievementManager.get_selected_cosmetic(_selected_type)
	selected_label.text = "Selected: %s" % (
		CATALOG.get_cosmetic_name(selected_id) if not selected_id.is_empty() else "Default"
	)

	_add_row("Default appearance", "Built-in look", true, selected_id.is_empty(), "")
	var cosmetics := AchievementManager.get_cosmetic_catalog(_selected_type)
	for cosmetic in cosmetics:
		var cosmetic_id := String(cosmetic["id"])
		_add_row(
			String(cosmetic["name"]),
			"Reward: %s" % String(cosmetic["source_title"]),
			bool(cosmetic["unlocked"]),
			cosmetic_id == selected_id,
			cosmetic_id
		)
	if cosmetics.is_empty():
		var empty := Label.new()
		empty.text = "No cosmetics available in this category yet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		items.add_child(empty)


func _add_row(
	display_name: String,
	detail: String,
	unlocked: bool,
	is_selected: bool,
	cosmetic_id: String
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	items.add_child(row)

	var placeholder := PanelContainer.new()
	placeholder.custom_minimum_size = Vector2(96, 56)
	var placeholder_label := Label.new()
	placeholder_label.text = display_name if unlocked else "🔒 " + display_name
	placeholder_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder_label.add_theme_font_size_override("font_size", 11)
	placeholder.add_child(placeholder_label)
	row.add_child(placeholder)

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
	detail_label.text = "%s  |  %s" % [status, detail]
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 13)
	text_box.add_child(detail_label)

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
