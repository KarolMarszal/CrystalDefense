class_name CrystalSocketDropTarget
extends PanelContainer

@onready var icon: TextureRect = $Contents/Icon
@onready var status_label: Label = $Contents/Details/Status
@onready var hint_label: Label = $Contents/Details/Hint

var tower_panel: Node
var _valid_drop_hover: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_style()


func set_tower_panel(panel: Node) -> void:
	tower_panel = panel


func update_socket(tower: Tower, feedback: String = "") -> void:
	var installed := (
		tower.get_main_crystal()
		if is_instance_valid(tower)
		else null
	)
	if installed == null:
		icon.texture = null
		status_label.text = "EMPTY CRYSTAL SOCKET"
		hint_label.text = feedback if not feedback.is_empty() else "Drag a crystal here to equip"
	else:
		icon.texture = installed.definition.visual_texture
		status_label.text = installed.definition.display_name.to_upper()
		hint_label.text = (
			feedback
			if not feedback.is_empty()
			else "Drop another crystal here to replace it"
		)
	queue_redraw()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	_valid_drop_hover = (
		data is Dictionary
		and data.get("type") == "run_crystal"
		and is_instance_valid(tower_panel)
		and bool(tower_panel.call("can_install_crystal_from_inventory", data))
	)
	if not _valid_drop_hover and is_instance_valid(tower_panel):
		tower_panel.call(
			"set_crystal_feedback",
			"Drop requires an available crystal and a valid tower socket."
		)
	elif _valid_drop_hover and is_instance_valid(tower_panel):
		tower_panel.call("set_crystal_feedback", "")
	_apply_style()
	return _valid_drop_hover


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_valid_drop_hover = false
	if not is_instance_valid(tower_panel):
		return
	tower_panel.call("install_crystal_from_inventory", data)
	_apply_style()


func _apply_style() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = (
		Color(0.19, 0.34, 0.25, 1.0)
		if _valid_drop_hover
		else Color(0.12, 0.19, 0.17, 1.0)
	)
	background.border_color = (
		Color(1.0, 0.83, 0.36, 1.0)
		if _valid_drop_hover
		else Color(0.56, 0.62, 0.49, 1.0)
	)
	background.set_border_width_all(2 if _valid_drop_hover else 1)
	background.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", background)
