extends Control

const CATALOG = preload("res://managers/AchievementCatalog.gd")
const ENTRY_SCENE: PackedScene = preload(
	"res://ui/main_menu/AchievementEntry.tscn"
)

@onready var total_label: Label = $Root/Margin/Contents/Header/Total
@onready var category_buttons: HBoxContainer = (
	$Root/Margin/Contents/Categories
)
@onready var entries: VBoxContainer = (
	$Root/Margin/Contents/ListPanel/Margin/Scroll/Entries
)
@onready var empty_label: Label = (
	$Root/Margin/Contents/ListPanel/Margin/Scroll/Entries/Empty
)
@onready var back_button: Button = $Root/Margin/Contents/Header/BackButton

var _definitions: Array[Dictionary] = []
var _categories: Array[String] = []
var _selected_category: String = ""
var _transitioning := false
var _reset_dialog: ConfirmationDialog


func _ready() -> void:
	back_button.pressed.connect(_return_to_menu)
	AchievementManager.achievement_progress_changed.connect(
		_on_achievement_changed
	)
	AchievementManager.achievement_unlocked.connect(_on_achievement_changed)
	AchievementManager.achievements_reset.connect(_on_achievements_reset)
	_build_reset_controls()
	_build_catalog_view()
	_refresh()


func _build_reset_controls() -> void:
	if (
		not OS.is_debug_build()
		or not bool(ProjectSettings.get_setting(
			"crystal_defense/development_mode",
			false
		))
	):
		return
	var reset_button := Button.new()
	reset_button.text = "RESET ACHIEVEMENTS (TESTING)"
	reset_button.custom_minimum_size = Vector2(0, 44)
	reset_button.add_theme_font_size_override("font_size", 14)
	reset_button.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	reset_button.pressed.connect(_on_reset_pressed)
	var header := back_button.get_parent()
	header.add_child(reset_button)
	header.move_child(reset_button, back_button.get_index())

	_reset_dialog = ConfirmationDialog.new()
	_reset_dialog.title = "Reset Achievements (Testing)"
	_reset_dialog.ok_button_text = "Reset"
	_reset_dialog.cancel_button_text = "Cancel"
	_reset_dialog.dialog_autowrap = true
	_reset_dialog.min_size = Vector2i(460, 0)
	_reset_dialog.dialog_text = (
		"Testing feature. This will reset:\n"
		+ "- achievement unlocks, progress, counters and streaks\n"
		+ "- achievement reward-claim records\n"
		+ "- cosmetics unlocked by achievements and their selections\n\n"
		+ "This will keep: skill tree (including Crystal Fusion), crystals, "
		+ "towers and all other profile data.\n\n"
		+ "Essence is NOT refunded or removed: achievement Essence cannot be "
		+ "separated from other Essence, so your current balance is preserved."
	)
	_reset_dialog.confirmed.connect(_on_reset_confirmed)
	add_child(_reset_dialog)


func _on_reset_pressed() -> void:
	_reset_dialog.popup_centered()


func _on_reset_confirmed() -> void:
	if not AchievementManager.reset_achievements_for_testing():
		push_error("Achievement reset failed; no profile data was changed.")


func _exit_tree() -> void:
	if AchievementManager.achievements_reset.is_connected(_on_achievements_reset):
		AchievementManager.achievements_reset.disconnect(_on_achievements_reset)
	if AchievementManager.achievement_progress_changed.is_connected(
		_on_achievement_changed
	):
		AchievementManager.achievement_progress_changed.disconnect(
			_on_achievement_changed
		)
	if AchievementManager.achievement_unlocked.is_connected(
		_on_achievement_changed
	):
		AchievementManager.achievement_unlocked.disconnect(
			_on_achievement_changed
		)


func _build_catalog_view() -> void:
	_definitions = AchievementManager.get_achievement_definitions()
	_categories.clear()
	for definition in _definitions:
		var category := String(definition.get("category", ""))
		if not _categories.has(category):
			_categories.append(category)
	if _selected_category.is_empty() or not _categories.has(_selected_category):
		_selected_category = _categories[0] if not _categories.is_empty() else ""

	for child in category_buttons.get_children():
		child.queue_free()
	for category in _categories:
		var button := Button.new()
		button.text = CATALOG.get_category_name(category)
		button.set_meta("category_id", category)
		button.toggle_mode = true
		button.button_pressed = category == _selected_category
		button.pressed.connect(_select_category.bind(category))
		category_buttons.add_child(button)


func _select_category(category: String) -> void:
	if not _categories.has(category):
		return
	_selected_category = category
	for button in category_buttons.get_children():
		button.button_pressed = button.get_meta("category_id", "") == category
	_refresh()


func _on_achievements_reset() -> void:
	_build_catalog_view()
	_refresh()


func _on_achievement_changed(_achievement_id: String, _value := 0, _target := 0) -> void:
	_build_catalog_view()
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	var state := AchievementManager.get_achievement_state()
	var unlocked_ids: Array = state.get("unlocked_ids", [])
	var progress: Dictionary = state.get("progress", {})
	var reward_granted: Dictionary = state.get("reward_granted", {})
	var cosmetics: Dictionary = state.get("unlocked_cosmetics", {})
	var available_count := _definitions.size()
	var unlocked_count := 0
	for definition in _definitions:
		if unlocked_ids.has(String(definition["id"])):
			unlocked_count += 1
	var percentage := (
		100.0 * float(unlocked_count) / float(available_count)
		if available_count > 0
		else 0.0
	)
	total_label.text = "Unlocked: %d / %d  (%.1f%%)" % [
		unlocked_count,
		available_count,
		percentage
	]

	for child in entries.get_children():
		if child != empty_label:
			child.queue_free()
	var visible_count := 0
	for definition in _definitions:
		if String(definition.get("category", "")) != _selected_category:
			continue
		visible_count += 1
		var achievement_id := String(definition["id"])
		var entry := ENTRY_SCENE.instantiate() as AchievementEntry
		entries.add_child(entry)
		var status := AchievementManager.get_achievement_status(achievement_id)
		status["progress"] = int(progress.get(achievement_id, 0))
		entry.configure(
			definition,
			status,
			bool(reward_granted.get(achievement_id, false)),
			cosmetics.has(String(definition.get("cosmetic_reward_id", "")))
		)
	empty_label.visible = visible_count == 0


func _return_to_menu() -> void:
	if _transitioning:
		return
	_transitioning = true
	var error := get_tree().change_scene_to_file(
		"res://ui/main_menu/MainMenu.tscn"
	)
	if error != OK:
		_transitioning = false
		push_error("Could not return to the main menu (error %d)." % error)
