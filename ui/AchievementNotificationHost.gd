extends CanvasLayer

const CATALOG = preload("res://managers/AchievementCatalog.gd")
# Autoload that presents achievement unlock popups in menus and gameplay.
# Display only: rewards are granted by AchievementManager before the signal.

@export var display_seconds: float = 5.0

var _queue: Array[String] = []
var _current_id: String = ""
var _panel: PanelContainer
var _title_label: Label
var _description_label: Label
var _reward_label: Label
var _icon_label: Label
var _timer: Timer


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	AchievementManager.achievement_unlocked.connect(_on_achievement_unlocked)
	AchievementManager.achievements_reset.connect(_on_achievements_reset)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	add_child(margin)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(440, 0)
	_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.14, 0.13, 0.97)
	style.border_color = Color(0.9, 0.75, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	row.add_child(_panel)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	_panel.add_child(content)

	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(56, 56)
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.add_child(icon_panel)
	_icon_label = Label.new()
	_icon_label.text = "★"
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_label.add_theme_font_size_override("font_size", 28)
	icon_panel.add_child(_icon_label)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(text_box)

	var heading := Label.new()
	heading.text = "★ ACHIEVEMENT UNLOCKED ★"
	heading.add_theme_color_override("font_color", Color(0.95, 0.8, 0.35))
	text_box.add_child(heading)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(_title_label)

	_description_label = Label.new()
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(_description_label)

	_reward_label = Label.new()
	_reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.65))
	text_box.add_child(_reward_label)

	var dismiss := Button.new()
	dismiss.text = "DISMISS"
	dismiss.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dismiss.pressed.connect(_dismiss_current)
	content.add_child(dismiss)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.ignore_time_scale = true
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer.timeout.connect(_dismiss_current)
	add_child(_timer)


func _on_achievement_unlocked(achievement_id: String) -> void:
	if achievement_id == _current_id or _queue.has(achievement_id):
		return
	_queue.append(achievement_id)
	if _current_id.is_empty():
		_show_next()


func _on_achievements_reset() -> void:
	_queue.clear()
	_current_id = ""
	_timer.stop()
	_panel.visible = false


func _dismiss_current() -> void:
	_current_id = ""
	_timer.stop()
	_panel.visible = false
	_show_next()


func _show_next() -> void:
	while not _queue.is_empty():
		var achievement_id: String = _queue.pop_front()
		var definition := _find_unlocked_definition(achievement_id)
		if definition.is_empty():
			continue
		_current_id = achievement_id
		_title_label.text = String(definition["title"])
		_description_label.text = String(definition["description"])
		_reward_label.text = "Reward: %s" % CATALOG.get_reward_summary(definition)
		_panel.visible = true
		_timer.start(maxf(display_seconds, 1.0))
		return
	_panel.visible = false


# Only already-unlocked achievements are returned, so no secret detail leaks.
func _find_unlocked_definition(achievement_id: String) -> Dictionary:
	var status := AchievementManager.get_achievement_status(achievement_id)
	if not bool(status.get("unlocked", false)):
		return {}
	for definition in AchievementManager.get_achievement_definitions():
		if String(definition["id"]) == achievement_id:
			return definition
	return {}
