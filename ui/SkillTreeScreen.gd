extends Control

const CATALOG = preload("res://managers/skill_tree_catalog.gd")
const NODE_SCENE: PackedScene = preload("res://ui/SkillTreeNode.tscn")

@onready var essence_label: Label = $Root/Margin/Contents/Header/Essence
@onready var tree_canvas: Control = $Root/Margin/Contents/Body/TreePanel/Margin/Scroll/TreeCanvas
@onready var tree_scroll: ScrollContainer = $Root/Margin/Contents/Body/TreePanel/Margin/Scroll
@onready var selected_title: Label = $Root/Margin/Contents/Body/Details/Margin/Contents/Title
@onready var category_label: Label = $Root/Margin/Contents/Body/Details/Margin/Contents/Category
@onready var description_label: Label = $Root/Margin/Contents/Body/Details/Margin/Contents/Description
@onready var cost_label: Label = $Root/Margin/Contents/Body/Details/Margin/Contents/Cost
@onready var prerequisites_label: Label = $Root/Margin/Contents/Body/Details/Margin/Contents/Prerequisites
@onready var effect_label: Label = $Root/Margin/Contents/Body/Details/Margin/Contents/Effect
@onready var state_label: Label = $Root/Margin/Contents/Body/Details/Margin/Contents/State
@onready var purchase_button: Button = $Root/Margin/Contents/Body/Details/Margin/Contents/PurchaseButton
@onready var feedback_label: Label = $Root/Margin/Contents/Body/Details/Margin/Contents/Feedback
@onready var back_button: Button = $Root/Margin/Contents/Header/BackButton

var _nodes: Dictionary = {}
var _selected_skill_id: StringName = &"A"
var _transitioning: bool = false
var _is_panning: bool = false
var _last_pan_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	back_button.pressed.connect(_return_to_menu)
	purchase_button.pressed.connect(_purchase_selected_skill)
	tree_canvas.gui_input.connect(_on_tree_canvas_gui_input)
	CrystalInventory.profile_changed.connect(_on_profile_changed)
	_build_tree_nodes()
	_refresh_tree()
	call_deferred("_center_on_selected_node")


func _exit_tree() -> void:
	if CrystalInventory.profile_changed.is_connected(_on_profile_changed):
		CrystalInventory.profile_changed.disconnect(_on_profile_changed)


func _on_tree_canvas_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		_is_panning = true
		_last_pan_position = event.global_position
		tree_canvas.mouse_default_cursor_shape = Control.CURSOR_MOVE
		tree_canvas.accept_event()


func _input(event: InputEvent) -> void:
	if not _is_panning:
		return

	if event is InputEventMouseMotion:
		var delta: Vector2 = event.global_position - _last_pan_position
		_last_pan_position = event.global_position
		tree_scroll.scroll_horizontal -= roundi(delta.x)
		tree_scroll.scroll_vertical -= roundi(delta.y)
		get_viewport().set_input_as_handled()
	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		_is_panning = false
		tree_canvas.mouse_default_cursor_shape = Control.CURSOR_ARROW
		get_viewport().set_input_as_handled()


func _build_tree_nodes() -> void:
	for definition in CATALOG.get_skill_definitions():
		var node := NODE_SCENE.instantiate() as SkillTreeNode
		tree_canvas.add_child(node)
		node.position = CATALOG.get_node_position(String(definition["id"]))
		node.skill_selected.connect(_select_skill)
		_nodes[StringName(definition["id"])] = node


func _select_skill(skill_id: StringName) -> void:
	if not _nodes.has(skill_id):
		return
	var node := _nodes[skill_id] as SkillTreeNode
	if not node.visible:
		return
	_selected_skill_id = skill_id
	_refresh_tree()


func _on_profile_changed(_profile: Dictionary) -> void:
	_refresh_tree()


func _refresh_tree() -> void:
	if not is_node_ready():
		return

	essence_label.text = "Essence: %d" % CrystalInventory.get_essence_balance()
	var visible_ids: Dictionary = {}
	var purchased_ids: Dictionary = {}
	for definition in CATALOG.get_skill_definitions():
		var skill_id := StringName(definition["id"])
		var status := CrystalInventory.get_skill_node_status(skill_id)
		var node := _nodes[skill_id] as SkillTreeNode
		node.visible = bool(status["visible"])
		node.configure(definition, String(status["state"]))
		if node.visible:
			visible_ids[String(skill_id)] = true
			if bool(status["purchased"]):
				purchased_ids[String(skill_id)] = true

	tree_canvas.set_progress(visible_ids, purchased_ids)
	_refresh_details()


func _refresh_details() -> void:
	var status := CrystalInventory.get_skill_node_status(_selected_skill_id)
	if status.is_empty() or status.get("state") == "invalid":
		return
	if not bool(status["visible"]):
		_selected_skill_id = &"A"
		status = CrystalInventory.get_skill_node_status(_selected_skill_id)

	var definition: Dictionary = status["definition"]
	var prerequisites: Array[String] = []
	for prerequisite_id in definition["prerequisites"]:
		var prereq_definition := CATALOG.get_skill_definition(
			StringName(prerequisite_id)
		)
		prerequisites.append(String(prereq_definition["name"]))
	var prerequisite_separator := (
		" OR "
		if definition.get("prerequisite_mode", "all") == "any"
		else ", "
	)
	var missing: Array[String] = status["missing_prerequisites"]

	selected_title.text = String(definition["name"])
	category_label.text = "Category: %s" % CATALOG.get_category_name(
		String(definition["category"])
	)
	description_label.text = String(definition["description"])
	cost_label.text = "Cost: %d Essence" % int(definition["cost"])
	prerequisites_label.text = (
		"Prerequisites: None"
		if prerequisites.is_empty()
		else "Prerequisites: %s" % prerequisite_separator.join(prerequisites)
	)
	if missing.is_empty():
		prerequisites_label.text += "\nMissing: None"
	else:
		var missing_names: Array[String] = []
		for prerequisite_id in missing:
			var missing_definition := CATALOG.get_skill_definition(
				StringName(prerequisite_id)
			)
			missing_names.append(String(missing_definition["name"]))
		prerequisites_label.text += (
			"\nMissing: %s" % prerequisite_separator.join(missing_names)
		)

	effect_label.text = _get_effect_description(definition)
	state_label.text = "State: %s" % String(status["state"]).capitalize()
	purchase_button.disabled = not bool(status["can_purchase"])
	purchase_button.text = (
		"PURCHASE — %d ESSENCE" % int(definition["cost"])
	)
	feedback_label.text = ""


func _get_effect_description(definition: Dictionary) -> String:
	if bool(definition["planned"]):
		return "Effect: PLANNED — gameplay effect is not designed."
	match String(definition["effect_id"]):
		"unlock_sniper":
			return "Effect: unlocks Sniper Crystal and grants one persistent copy."
		"unlock_slow":
			return "Effect: unlocks Slow Crystal and grants one level-1 persistent copy."
		"unlock_bleed":
			return "Effect: unlocks Bleed Crystal and grants one level-1 persistent copy."
		"access_elemental_mastery":
			return "Effect: unlocks the Elemental Mastery skill-tree branch."
		"unlock_fire_area":
			return "Effect: grants one Fire Crystal and immediately enables its area-damage hit."
		"fire_damage_bonus":
			return "Effect: increases Fire Crystal damage by 20%."
	var unlock_crystal_id := String(definition["unlock_crystal_id"])
	if not unlock_crystal_id.is_empty():
		return (
			"Effect: unlocks crystal type '%s' and grants one level-1 persistent copy."
		) % unlock_crystal_id
	match String(definition["effect_id"]):
		"access_skill_tree":
			return "Effect: unlocks the Crystal Inventory, grants one Kinetic Crystal and one Rapid Fire Crystal, and opens permanent skill progression."
		"unlock_tower_upgrades":
			return "Effect: enables tower upgrade purchases in runs."
		"unlock_auto_waves":
			return "Effect: enables the existing Auto Waves control."
		"unlock_wave_preview":
			return "Effect: reveals the existing generated next-wave preview."
		"early_wave_bonus_scale":
			return "Effect: increases the current manual early-wave bonus by 10%, capped at the existing +30% maximum."
		"passive_gold":
			return "Effect: +%.0f run Gold every %.0f seconds while a run is active." % [
				float(definition["effect_value"]),
				CATALOG.PASSIVE_GOLD_INTERVAL_SECONDS
			]
		_:
			return "Effect: %s (+%.0f%%)." % [
				String(definition["effect_id"]).replace("_", " ").capitalize(),
				float(definition["effect_value"]) * 100.0
			]


func _purchase_selected_skill() -> void:
	if not CrystalInventory.purchase_skill_node(_selected_skill_id):
		_refresh_tree()
		feedback_label.text = "Purchase failed. Requirements or save state changed."
		return
	_refresh_tree()
	feedback_label.text = "Skill purchased."


func _center_on_selected_node() -> void:
	if not _nodes.has(_selected_skill_id):
		return
	var node := _nodes[_selected_skill_id] as Control
	tree_scroll.scroll_horizontal = maxi(
		roundi(node.position.x + node.size.x * 0.5 - tree_scroll.size.x * 0.5),
		0
	)
	tree_scroll.scroll_vertical = maxi(
		roundi(node.position.y + node.size.y * 0.5 - tree_scroll.size.y * 0.5),
		0
	)


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
