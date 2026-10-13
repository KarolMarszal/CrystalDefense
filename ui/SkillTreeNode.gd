class_name SkillTreeNode
extends Button

const CATALOG = preload("res://managers/skill_tree_catalog.gd")

signal skill_selected(skill_id: StringName)

@onready var category_label: Label = $Contents/Category
@onready var name_label: Label = $Contents/Name
@onready var cost_label: Label = $Contents/Cost
@onready var state_label: Label = $Contents/State

var skill_id: StringName


func _ready() -> void:
	pressed.connect(func() -> void: skill_selected.emit(skill_id))
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	alignment = HORIZONTAL_ALIGNMENT_CENTER


func configure(definition: Dictionary, state: String) -> void:
	skill_id = StringName(definition["id"])
	var category_id := String(definition["category"])
	category_label.text = CATALOG.get_category_name(category_id).to_upper()
	name_label.text = String(definition["name"])
	cost_label.text = "%d Essence" % int(definition["cost"])
	state_label.text = state.to_upper()
	var colors := _state_colors(state)
	var style := StyleBoxFlat.new()
	style.bg_color = colors["background"]
	style.border_color = colors["border"]
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style.duplicate())
	add_theme_stylebox_override("pressed", style.duplicate())
	add_theme_color_override("font_color", Color(0.95, 0.94, 0.86, 1))
	category_label.add_theme_color_override(
		"font_color",
		_category_color(category_id)
	)
	state_label.add_theme_color_override("font_color", colors["accent"])
	cost_label.add_theme_color_override("font_color", colors["accent"])
	disabled = state == "hidden"
	focus_mode = (
		Control.FOCUS_NONE
		if state == "hidden"
		else Control.FOCUS_ALL
	)


func _category_color(category_id: String) -> Color:
	match category_id:
		"tower_enhancements":
			return Color(0.96, 0.74, 0.36, 1)
		"crystals":
			return Color(0.49, 0.88, 0.85, 1)
		"elemental_mastery":
			return Color(0.98, 0.55, 0.39, 1)
		"economy":
			return Color(0.55, 0.75, 1, 1)
	return Color(0.83, 0.83, 0.76, 1)


func _state_colors(state: String) -> Dictionary:
	match state:
		"purchased":
			return {
				"background": Color(0.12, 0.24, 0.18, 1),
				"border": Color(0.57, 1.0, 0.68, 1),
				"accent": Color(0.57, 1.0, 0.68, 1)
			}
		"available":
			return {
				"background": Color(0.24, 0.21, 0.12, 1),
				"border": Color(1.0, 0.83, 0.36, 1),
				"accent": Color(1.0, 0.83, 0.36, 1)
			}
		"unaffordable":
			return {
				"background": Color(0.22, 0.16, 0.1, 1),
				"border": Color(0.92, 0.54, 0.31, 1),
				"accent": Color(0.98, 0.63, 0.39, 1)
			}
		"hidden":
			return {
				"background": Color(0.1, 0.12, 0.11, 1),
				"border": Color(0.2, 0.23, 0.21, 1),
				"accent": Color(0.35, 0.37, 0.34, 1)
			}
		_:
			return {
				"background": Color(0.11, 0.14, 0.13, 1),
				"border": Color(0.43, 0.48, 0.42, 1),
				"accent": Color(0.63, 0.66, 0.62, 1)
			}
