extends Control

@onready var entries_container: VBoxContainer = $CenterPanel/MarginContainer/Contents/ScrollContainer/Entries
@onready var empty_label: Label = $CenterPanel/MarginContainer/Contents/EmptyLabel
@onready var back_button: Button = $CenterPanel/MarginContainer/Contents/BackButton

var _transitioning: bool = false


func _ready() -> void:
	back_button.pressed.connect(_return_to_menu)
	_refresh_inventory()


func _refresh_inventory() -> void:
	var entries: Array[Dictionary] = CrystalInventory.get_owned_crystals()
	empty_label.visible = entries.is_empty()
	for child in entries_container.get_children():
		child.queue_free()

	for entry in entries:
		var definition := entry["definition"] as CrystalData
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 52.0

		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text = definition.display_name
		row.add_child(name_label)

		var details_label := Label.new()
		details_label.text = "Level %d    Owned: %d" % [
			entry["level"],
			entry["quantity"]
		]
		details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(details_label)
		entries_container.add_child(row)


func _return_to_menu() -> void:
	if _transitioning:
		return

	_transitioning = true
	var error := get_tree().change_scene_to_file(
		"res://ui/main_menu/MainMenu.tscn"
	)
	if error != OK:
		_transitioning = false
		push_error("Could not return to the Main Menu (error %d)." % error)
