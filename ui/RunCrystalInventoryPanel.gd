class_name RunCrystalInventoryPanel
extends PanelContainer

signal close_requested

const ITEM_SCENE: PackedScene = preload(
	"res://ui/RunCrystalInventoryItem.tscn"
)

@onready var entries: VBoxContainer = $Margin/Contents/Scroll/Entries
@onready var empty_label: Label = $Margin/Contents/EmptyLabel
@onready var feedback_label: Label = $Margin/Contents/Feedback
@onready var close_button: Button = $Margin/Contents/Header/CloseButton
@onready var fusion_status_label: Label = $Margin/Contents/FusionStatus
@onready var fusion_preview_label: Label = $Margin/Contents/FusionPreview
@onready var fuse_button: Button = $Margin/Contents/FusionActions/FuseButton
@onready var clear_selection_button: Button = (
	$Margin/Contents/FusionActions/ClearSelectionButton
)

var _fusion_selection: Array[Dictionary] = []
var _fusion_in_progress: bool = false


func _ready() -> void:
	close_button.pressed.connect(func() -> void: close_requested.emit())
	fuse_button.pressed.connect(_fuse_selected_crystals)
	clear_selection_button.pressed.connect(_clear_fusion_selection)
	CrystalInventory.run_inventory_changed.connect(_on_run_inventory_changed)
	CrystalInventory.profile_changed.connect(_on_profile_changed)
	refresh()


func _exit_tree() -> void:
	if CrystalInventory.run_inventory_changed.is_connected(
		_on_run_inventory_changed
	):
		CrystalInventory.run_inventory_changed.disconnect(
			_on_run_inventory_changed
		)
	if CrystalInventory.profile_changed.is_connected(_on_profile_changed):
		CrystalInventory.profile_changed.disconnect(_on_profile_changed)


func _on_run_inventory_changed() -> void:
	if not _fusion_in_progress:
		_fusion_selection.clear()
	refresh()


func _on_profile_changed(_profile: Dictionary) -> void:
	if not _fusion_in_progress:
		_fusion_selection.clear()
	refresh()


func refresh() -> void:
	if not is_node_ready():
		return

	for child in entries.get_children():
		entries.remove_child(child)
		child.queue_free()

	var available := CrystalInventory.get_available_crystals()
	empty_label.visible = available.is_empty()
	for entry in available:
		var item := ITEM_SCENE.instantiate() as RunCrystalInventoryItem
		item.configure(
			entry,
			_get_selected_count(
				StringName(entry["crystal_id"]),
				int(entry["level"])
			),
			CrystalInventory.is_crystal_fusion_unlocked(),
			_fusion_selection.size() >= 2
		)
		item.fusion_input_selected.connect(_select_fusion_input)
		entries.add_child(item)
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
	refresh()


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
			"Select two matching crystals. Installed crystals cannot be fused."
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
		fusion_preview_label.text = "Clear selection to choose a matching pair."
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
	refresh()


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
		refresh()
		set_feedback("Fusion complete.")
	else:
		set_feedback("Fusion failed. Available crystals were not changed.")


func set_feedback(message: String) -> void:
	feedback_label.text = message
