extends Control

@onready var entries_container: VBoxContainer = $CenterPanel/MarginContainer/Contents/ScrollContainer/Entries
@onready var empty_label: Label = $CenterPanel/MarginContainer/Contents/EmptyLabel
@onready var back_button: Button = $CenterPanel/MarginContainer/Contents/BackButton
@onready var title_label: Label = $CenterPanel/MarginContainer/Contents/Title
@onready var shop_balance_label: Label = (
	$CenterPanel/MarginContainer/Contents/CrystalShop/EssenceBalance
)
@onready var buy_crystal_button: Button = (
	$CenterPanel/MarginContainer/Contents/CrystalShop/BuyCrystalButton
)
@onready var shop_status_label: Label = (
	$CenterPanel/MarginContainer/Contents/ShopStatus
)
@onready var fusion_status_label: Label = (
	$CenterPanel/MarginContainer/Contents/FusionStatus
)
@onready var fusion_preview_label: Label = (
	$CenterPanel/MarginContainer/Contents/FusionPreview
)
@onready var fuse_button: Button = (
	$CenterPanel/MarginContainer/Contents/FusionActions/FuseButton
)
@onready var clear_selection_button: Button = (
	$CenterPanel/MarginContainer/Contents/FusionActions/ClearSelectionButton
)

var _transitioning: bool = false
var _purchase_in_progress: bool = false
var _fusion_in_progress: bool = false
var _fusion_selection: Array[Dictionary] = []


func _ready() -> void:
	back_button.pressed.connect(_return_to_menu)
	buy_crystal_button.pressed.connect(_buy_crystal)
	fuse_button.pressed.connect(_fuse_selected_crystals)
	clear_selection_button.pressed.connect(_clear_fusion_selection)
	CrystalInventory.profile_changed.connect(_on_profile_changed)
	CrystalInventory.run_inventory_changed.connect(_refresh_inventory)
	_refresh_inventory()


func _exit_tree() -> void:
	if CrystalInventory.profile_changed.is_connected(_on_profile_changed):
		CrystalInventory.profile_changed.disconnect(_on_profile_changed)
	if CrystalInventory.run_inventory_changed.is_connected(_refresh_inventory):
		CrystalInventory.run_inventory_changed.disconnect(_refresh_inventory)


func _on_profile_changed(_profile: Dictionary) -> void:
	_fusion_selection.clear()
	_refresh_inventory()


func _refresh_inventory() -> void:
	visible = CrystalInventory.is_crystal_inventory_unlocked()
	if not visible:
		return

	var entries: Array[Dictionary]
	var quantity_label: String
	if CrystalInventory.is_run_inventory_active():
		$CenterPanel/MarginContainer/Contents/CrystalShop.visible = false
		shop_status_label.visible = false
		title_label.text = "RUN INVENTORY - AVAILABLE"
		empty_label.text = "No crystals available this run."
		quantity_label = "Available"
		entries = CrystalInventory.get_available_crystals()
	else:
		$CenterPanel/MarginContainer/Contents/CrystalShop.visible = true
		shop_status_label.visible = true
		title_label.text = "PERSISTENT CRYSTAL COLLECTION"
		empty_label.text = "No crystals owned yet."
		quantity_label = "Owned"
		entries = CrystalInventory.get_owned_crystals()
		_refresh_crystal_shop()
	empty_label.visible = entries.is_empty()
	for child in entries_container.get_children():
		entries_container.remove_child(child)
		child.free()

	for entry in entries:
		var definition := entry["definition"] as CrystalData
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 52.0

		if definition.visual_texture != null:
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(40.0, 40.0)
			icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = definition.visual_texture
			row.add_child(icon)

		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text = "%s (%s)" % [
			definition.display_name,
			entry["crystal_id"] if entry.has("crystal_id") else String(definition.crystal_id)
		]
		name_label.text += " - Lv. %d" % int(entry["level"])
		row.add_child(name_label)

		var details_label := Label.new()
		details_label.text = "%s: %d" % [
			quantity_label,
			entry["quantity"]
		]
		details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(details_label)
		var select_button := Button.new()
		var crystal_id := StringName(
			entry.get("crystal_id", definition.crystal_id)
		)
		var level := int(entry["level"])
		var selected_count := _get_selected_count(crystal_id, level)
		select_button.text = (
			"SELECTED x%d" % selected_count
			if selected_count > 0
			else "SELECT"
		)
		select_button.disabled = (
			not CrystalInventory.is_crystal_fusion_unlocked()
			or selected_count >= int(entry["quantity"])
			or _fusion_selection.size() >= 2
			or _fusion_in_progress
		)
		select_button.pressed.connect(
			_select_fusion_input.bind(
				crystal_id,
				level,
				int(entry["quantity"])
			)
		)
		row.add_child(select_button)
		entries_container.add_child(row)
	_refresh_fusion_controls()


func _get_selected_count(crystal_id: StringName, level: int) -> int:
	var count := 0
	for selected in _fusion_selection:
		if (
			StringName(selected["crystal_id"]) == crystal_id
			and int(selected["level"]) == level
		):
			count += 1
	return count


func _select_fusion_input(
	crystal_id: StringName,
	level: int,
	available_quantity: int
) -> void:
	if (
		not CrystalInventory.is_crystal_fusion_unlocked()
		or _fusion_selection.size() >= 2
		or _get_selected_count(crystal_id, level) >= available_quantity
	):
		return
	_fusion_selection.append({
		"crystal_id": String(crystal_id),
		"level": level
	})
	_refresh_inventory()


func _refresh_fusion_controls() -> void:
	var unlocked := CrystalInventory.is_crystal_fusion_unlocked()
	fuse_button.disabled = true
	clear_selection_button.disabled = (
		_fusion_selection.is_empty() or _fusion_in_progress
	)
	if not unlocked:
		fusion_status_label.text = (
			"Fusion locked. Unlock Crystal Fusion in the Crystals skill tree."
		)
		fusion_preview_label.text = ""
		return
	if _fusion_selection.size() < 2:
		fusion_status_label.text = (
			"Select two crystals with the same type and level."
		)
		fusion_preview_label.text = (
			"Selected: %d/2" % _fusion_selection.size()
		)
		return

	var first: Dictionary = _fusion_selection[0]
	var second: Dictionary = _fusion_selection[1]
	if (
		first["crystal_id"] != second["crystal_id"]
		or int(first["level"]) != int(second["level"])
	):
		fusion_status_label.text = (
			"Selected crystals must have the same type and level."
		)
		fusion_preview_label.text = "Clear the selection to choose matching crystals."
		return

	var crystal_id := StringName(first["crystal_id"])
	var level := int(first["level"])
	var definition := CrystalInventory.get_crystal_definition(crystal_id)
	if definition == null:
		fusion_status_label.text = "Crystal definition is unavailable."
		fusion_preview_label.text = ""
		return
	fusion_preview_label.text = (
		"Result: %s — Level %d" % [definition.display_name, level + 1]
	)
	if not CrystalInventory.can_fuse_crystals(crystal_id, level):
		fusion_status_label.text = (
			"Fusion unavailable: insufficient matching crystals or maximum level reached."
		)
		return
	fusion_status_label.text = "Two matching crystals selected."
	fuse_button.disabled = _fusion_in_progress


func _clear_fusion_selection() -> void:
	_fusion_selection.clear()
	_refresh_inventory()


func _fuse_selected_crystals() -> void:
	if _fusion_in_progress or _fusion_selection.size() != 2:
		return
	var first: Dictionary = _fusion_selection[0]
	var second: Dictionary = _fusion_selection[1]
	if (
		first["crystal_id"] != second["crystal_id"]
		or int(first["level"]) != int(second["level"])
	):
		_refresh_fusion_controls()
		return

	_fusion_in_progress = true
	_refresh_fusion_controls()
	var success := CrystalInventory.fuse_crystals(
		StringName(first["crystal_id"]),
		int(first["level"])
	)
	_fusion_in_progress = false
	if success:
		_fusion_selection.clear()
		_refresh_inventory()
	else:
		fusion_status_label.text = (
			"Fusion failed. Your crystal inventory was not changed."
		)


func _refresh_crystal_shop() -> void:
	var price := CrystalInventory.get_crystal_shop_price()
	var balance := CrystalInventory.get_essence_balance()
	var has_eligible_crystal := (
		not CrystalInventory.get_crystal_shop_eligible_ids().is_empty()
	)
	shop_balance_label.text = "Essence: %d" % balance
	buy_crystal_button.text = "BUY CRYSTAL - %d ESSENCE" % price
	buy_crystal_button.disabled = (
		_purchase_in_progress
		or balance < price
		or not has_eligible_crystal
	)


func _buy_crystal() -> void:
	if _purchase_in_progress or buy_crystal_button.disabled:
		return

	_purchase_in_progress = true
	shop_status_label.text = ""
	_refresh_crystal_shop()
	if not CrystalInventory.purchase_random_crystal():
		_purchase_in_progress = false
		shop_status_label.text = "Purchase could not be completed."
		_refresh_inventory()
		return

	_purchase_in_progress = false
	shop_status_label.text = ""
	_refresh_inventory()


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
