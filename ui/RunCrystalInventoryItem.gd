class_name RunCrystalInventoryItem
extends PanelContainer

@onready var icon: TextureRect = $Margin/Contents/Icon
@onready var name_label: Label = $Margin/Contents/Details/Name
@onready var level_label: Label = $Margin/Contents/Details/Level
@onready var quantity_label: Label = $Margin/Contents/Quantity

var crystal_id: StringName
var crystal_level: int = 1
var crystal_quantity: int = 0
var crystal_definition: CrystalData


func configure(entry: Dictionary) -> void:
	crystal_id = StringName(entry["crystal_id"])
	crystal_level = int(entry["level"])
	crystal_quantity = int(entry["quantity"])
	crystal_definition = entry["definition"] as CrystalData
	if is_inside_tree():
		_refresh()


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if crystal_definition == null:
		return

	icon.texture = crystal_definition.visual_texture
	name_label.text = crystal_definition.display_name
	level_label.hide()
	quantity_label.text = "x%d" % crystal_quantity
	tooltip_text = "Drag to a tower socket to install or replace"


func _get_drag_data(_at_position: Vector2) -> Variant:
	var drag_payload := get_drag_payload()
	if drag_payload.is_empty():
		return null

	var preview := PanelContainer.new()
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(0.12, 0.22, 0.19, 0.95)
	preview_style.border_color = Color(0.94, 0.72, 0.3, 1.0)
	preview_style.set_border_width_all(2)
	preview_style.set_corner_radius_all(8)
	preview.add_theme_stylebox_override("panel", preview_style)
	var preview_contents := HBoxContainer.new()
	var preview_icon := TextureRect.new()
	preview_icon.custom_minimum_size = Vector2(42.0, 42.0)
	preview_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_icon.texture = crystal_definition.visual_texture
	preview_contents.add_child(preview_icon)
	var preview_label := Label.new()
	preview_label.text = crystal_definition.display_name
	preview_contents.add_child(preview_label)
	preview.add_child(preview_contents)
	set_drag_preview(preview)
	return drag_payload


func get_drag_payload() -> Dictionary:
	if (
		crystal_quantity <= 0
		or not CrystalInventory.can_install_crystal(
			crystal_definition,
			crystal_level
		)
	):
		return {}

	return {
		"type": "run_crystal",
		"crystal_id": String(crystal_id),
		"level": crystal_level
	}
