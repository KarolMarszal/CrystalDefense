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

var _transitioning: bool = false
var _purchase_in_progress: bool = false


func _ready() -> void:
	back_button.pressed.connect(_return_to_menu)
	buy_crystal_button.pressed.connect(_buy_crystal)
	CrystalInventory.profile_changed.connect(_on_profile_changed)
	CrystalInventory.run_inventory_changed.connect(_refresh_inventory)
	_refresh_inventory()


func _exit_tree() -> void:
	if CrystalInventory.profile_changed.is_connected(_on_profile_changed):
		CrystalInventory.profile_changed.disconnect(_on_profile_changed)
	if CrystalInventory.run_inventory_changed.is_connected(_refresh_inventory):
		CrystalInventory.run_inventory_changed.disconnect(_refresh_inventory)


func _on_profile_changed(_profile: Dictionary) -> void:
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
		row.add_child(name_label)

		var details_label := Label.new()
		details_label.text = "%s: %d" % [
			quantity_label,
			entry["quantity"]
		]
		details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(details_label)
		entries_container.add_child(row)


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
