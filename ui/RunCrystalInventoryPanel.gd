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


func _ready() -> void:
	close_button.pressed.connect(func() -> void: close_requested.emit())
	CrystalInventory.run_inventory_changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if CrystalInventory.run_inventory_changed.is_connected(refresh):
		CrystalInventory.run_inventory_changed.disconnect(refresh)


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
		item.configure(entry)
		entries.add_child(item)


func set_feedback(message: String) -> void:
	feedback_label.text = message
