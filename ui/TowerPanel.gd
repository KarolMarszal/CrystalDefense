extends PanelContainer

signal priority_selected(priority: int)
signal close_requested

@onready var tower_title: Label = $MarginContainer/VBoxContainer/Header/TowerTitle
@onready var combat_stats_label: Label = $MarginContainer/VBoxContainer/CombatStatsLabel
@onready var damage_label: Label = $MarginContainer/VBoxContainer/DamageRow/DamageLabel
@onready var damage_upgrade_button: Button = $MarginContainer/VBoxContainer/DamageRow/DamageUpgradeButton
@onready var attack_speed_label: Label = $MarginContainer/VBoxContainer/AttackSpeedRow/AttackSpeedLabel
@onready var attack_speed_upgrade_button: Button = $MarginContainer/VBoxContainer/AttackSpeedRow/AttackSpeedUpgradeButton
@onready var range_label: Label = $MarginContainer/VBoxContainer/RangeRow/RangeLabel
@onready var range_upgrade_button: Button = $MarginContainer/VBoxContainer/RangeRow/RangeUpgradeButton
@onready var main_socket_label: Label = $MarginContainer/VBoxContainer/MainSocketLabel
@onready var crystal_drop_target: CrystalSocketDropTarget = $MarginContainer/VBoxContainer/CrystalSocketDropTarget
@onready var remove_crystal_button: Button = $MarginContainer/VBoxContainer/RemoveCrystalButton
@onready var priority_label: Label = $MarginContainer/VBoxContainer/PriorityLabel
@onready var nearest_button: Button = $MarginContainer/VBoxContainer/PriorityButtons/NearestButton
@onready var first_button: Button = $MarginContainer/VBoxContainer/PriorityButtons/FirstButton
@onready var strongest_button: Button = $MarginContainer/VBoxContainer/PriorityButtons/StrongestButton
@onready var trophy_carrier_checkbox: CheckBox = $MarginContainer/VBoxContainer/TrophyCarrierPriority
@onready var close_button: Button = $MarginContainer/VBoxContainer/Header/CloseButton

var _selected_tower: Tower
var _priority_buttons: Array[Button]
var _inventory_panel: RunCrystalInventoryPanel
var _crystal_feedback: String = ""


func _ready() -> void:
	_priority_buttons = [nearest_button, first_button, strongest_button]
	crystal_drop_target.set_tower_panel(self)
	nearest_button.pressed.connect(_on_priority_pressed.bind(Tower.TargetPriority.NEAREST))
	first_button.pressed.connect(_on_priority_pressed.bind(Tower.TargetPriority.FIRST))
	strongest_button.pressed.connect(_on_priority_pressed.bind(Tower.TargetPriority.STRONGEST))
	trophy_carrier_checkbox.toggled.connect(_on_trophy_carrier_priority_toggled)
	close_button.pressed.connect(func() -> void: close_requested.emit())
	damage_upgrade_button.pressed.connect(
		_on_upgrade_pressed.bind(Tower.UpgradeTrack.UPGRADE_1)
	)
	attack_speed_upgrade_button.pressed.connect(
		_on_upgrade_pressed.bind(Tower.UpgradeTrack.UPGRADE_2)
	)
	range_upgrade_button.pressed.connect(
		_on_upgrade_pressed.bind(Tower.UpgradeTrack.UPGRADE_3)
	)
	remove_crystal_button.pressed.connect(_on_remove_crystal_pressed)
	GoldManager.gold_changed.connect(_on_gold_changed)
	CrystalInventory.run_inventory_changed.connect(_refresh)
	CrystalInventory.profile_changed.connect(_on_profile_changed)


func _exit_tree() -> void:
	if GoldManager.gold_changed.is_connected(_on_gold_changed):
		GoldManager.gold_changed.disconnect(_on_gold_changed)
	if CrystalInventory.run_inventory_changed.is_connected(_refresh):
		CrystalInventory.run_inventory_changed.disconnect(_refresh)
	if CrystalInventory.profile_changed.is_connected(_on_profile_changed):
		CrystalInventory.profile_changed.disconnect(_on_profile_changed)


func show_tower(tower: Tower) -> void:
	if (
		not is_instance_valid(tower)
		or not tower.is_inside_tree()
		or tower.is_queued_for_deletion()
	):
		clear_tower()
		return

	if _selected_tower != tower:
		if (
			is_instance_valid(_selected_tower)
			and _selected_tower.stats_changed.is_connected(_refresh)
		):
			_selected_tower.stats_changed.disconnect(_refresh)
		_selected_tower = tower
		_selected_tower.stats_changed.connect(_refresh)

	visible = true
	_crystal_feedback = ""
	_refresh()


func clear_tower() -> void:
	if (
		is_instance_valid(_selected_tower)
		and _selected_tower.stats_changed.is_connected(_refresh)
	):
		_selected_tower.stats_changed.disconnect(_refresh)
	_selected_tower = null
	_crystal_feedback = ""
	visible = false


func set_inventory_panel(panel: RunCrystalInventoryPanel) -> void:
	_inventory_panel = panel


func can_install_crystal_from_inventory(data: Variant) -> bool:
	return can_install_crystal_on_tower(_selected_tower, data, true)


func can_install_crystal_on_tower(
	tower: Tower,
	data: Variant,
	allow_replacement: bool
) -> bool:
	if (
		not data is Dictionary
		or data.get("type") != "run_crystal"
		or typeof(data.get("crystal_id")) != TYPE_STRING
		or typeof(data.get("level")) != TYPE_INT
		or not is_instance_valid(tower)
		or not tower.is_inside_tree()
		or tower.is_queued_for_deletion()
	):
		return false

	var crystal_id := StringName(data["crystal_id"])
	var crystal_level := int(data["level"])
	var definition := CrystalInventory.get_crystal_definition(crystal_id)
	if definition == null or crystal_level < 1:
		return false

	var installed := tower.get_main_crystal()
	if installed != null:
		if not allow_replacement:
			return false
		if (
			StringName(installed.definition.crystal_id) == crystal_id
			and installed.level == crystal_level
		):
			return true
		return (
			tower.can_replace_main_crystal(definition, crystal_level)
			and CrystalInventory.can_replace_run_crystal(
				crystal_id,
				crystal_level,
				installed
			)
		)

	return (
		CrystalInventory.can_install_crystal(definition, crystal_level)
		and tower.can_install_main_crystal(definition, crystal_level)
	)


func install_crystal_from_inventory(data: Variant) -> bool:
	if not _has_selected_tower():
		set_crystal_feedback("Select a tower before installing a crystal.")
		return false
	return install_crystal_on_tower(_selected_tower, data, true)


func install_crystal_on_tower(
	tower: Tower,
	data: Variant,
	allow_replacement: bool
) -> bool:
	if not can_install_crystal_on_tower(tower, data, allow_replacement):
		_set_install_feedback(
			tower,
			"Invalid drop: select an available crystal and a compatible usable socket."
		)
		return false

	var crystal_id := StringName(data["crystal_id"])
	var crystal_level := int(data["level"])
	var definition := CrystalInventory.get_crystal_definition(crystal_id)
	var installed := tower.get_main_crystal()
	if installed != null:
		if (
			StringName(installed.definition.crystal_id) == crystal_id
			and installed.level == crystal_level
		):
			_set_install_feedback(
				tower,
				"That crystal is already installed; inventory unchanged."
			)
			return true

		var outgoing := tower.replace_main_crystal(definition, crystal_level)
		if outgoing == null:
			_set_install_feedback(tower, "Could not replace the installed crystal.")
			return false
		if not CrystalInventory.replace_run_crystal(
			crystal_id,
			crystal_level,
			outgoing
		):
			if not tower.restore_main_crystal(outgoing):
				push_error("Could not restore the original crystal after replacement failed.")
			_set_install_feedback(
				tower,
				"Replacement failed; inventory and socket restored."
			)
			return false
		_set_install_feedback(
			tower,
			"%s replaced %s on %s." % [
				definition.display_name,
				outgoing.definition.display_name,
				tower.name
			]
		)
		return true

	if not CrystalInventory.consume_run_crystal(definition, crystal_level):
		_set_install_feedback(tower, "Crystal is no longer available.")
		return false

	if (
		not is_instance_valid(tower)
		or tower.is_queued_for_deletion()
		or not tower.install_main_crystal(definition, crystal_level)
	):
		if not CrystalInventory.add_run_crystal(crystal_id, crystal_level):
			push_error("Could not restore a crystal after tower installation failed.")
		_set_install_feedback(
			tower,
			"Could not install the crystal; inventory restored."
		)
		return false

	_set_install_feedback(
		tower,
		"%s installed on %s." % [definition.display_name, tower.name]
	)
	return true


func _set_install_feedback(tower: Tower, message: String) -> void:
	if tower == _selected_tower and _has_selected_tower():
		set_crystal_feedback(message)
	elif is_instance_valid(_inventory_panel):
		_inventory_panel.set_feedback(message)


func set_crystal_feedback(message: String) -> void:
	_crystal_feedback = message
	crystal_drop_target.update_socket(
		_selected_tower if _has_selected_tower() else null,
		_crystal_feedback
	)
	if is_instance_valid(_inventory_panel):
		_inventory_panel.set_feedback(message)


func _on_priority_pressed(priority: int) -> void:
	if not _has_selected_tower():
		clear_tower()
		return

	_selected_tower.target_priority = priority
	priority_selected.emit(priority)
	_refresh()


func _on_trophy_carrier_priority_toggled(enabled: bool) -> void:
	if not _has_selected_tower():
		clear_tower()
		return

	_selected_tower.prioritize_trophy_carriers = enabled


func _on_upgrade_pressed(track: Tower.UpgradeTrack) -> void:
	if not _has_selected_tower():
		clear_tower()
		return

	_selected_tower.upgrade_tower_track(track)
	_refresh()


func _on_remove_crystal_pressed() -> void:
	if not _has_selected_tower():
		clear_tower()
		return

	var installed := _selected_tower.get_main_crystal()
	if installed == null:
		_refresh()
		return
	if not CrystalInventory.can_return_run_crystal(installed):
		set_crystal_feedback("This crystal cannot be returned right now.")
		_refresh()
		return
	var removed := _selected_tower.remove_main_crystal()
	if removed == null:
		_refresh()
		return
	if not CrystalInventory.return_run_crystal(removed):
		if not _selected_tower.restore_main_crystal(removed):
			push_error("Could not restore a crystal after inventory return failed.")
		set_crystal_feedback("Could not return the selected crystal.")
	_refresh()


func _on_gold_changed(_amount: int) -> void:
	if _has_selected_tower():
		_refresh()


func _on_profile_changed(_profile: Dictionary) -> void:
	if _has_selected_tower():
		_refresh()


func _refresh() -> void:
	if not _has_selected_tower():
		clear_tower()
		return

	var crystal_instance := _selected_tower.get_main_crystal()
	var configuration := _selected_tower.current_attack_configuration
	var crystal_ui_unlocked := CrystalInventory.is_crystal_inventory_unlocked()
	tower_title.text = (
		"Tower - %s" % crystal_instance.definition.display_name
		if crystal_instance != null and crystal_ui_unlocked
		else "Tower"
	)
	main_socket_label.visible = crystal_ui_unlocked
	crystal_drop_target.visible = crystal_ui_unlocked
	remove_crystal_button.visible = (
		crystal_instance != null and crystal_ui_unlocked
	)
	main_socket_label.text = (
		"Main Socket: %s" % crystal_instance.definition.display_name
		if crystal_instance != null and crystal_ui_unlocked
		else "Main Socket: Empty"
	)
	crystal_drop_target.update_socket(
		_selected_tower,
		_crystal_feedback
	)
	combat_stats_label.text = (
		"Damage: %s  |  Attack Speed: %s  |  Range: %d"
		% [
			_format_damage(configuration.damage),
			"N/A (Aura)"
			if configuration.attack_behavior == CrystalData.AttackBehavior.AURA
			else "%.2f/s" % configuration.attack_speed,
			roundi(configuration.attack_range)
		]
	)
	damage_label.text = _upgrade_track_text(Tower.UpgradeTrack.UPGRADE_1)
	attack_speed_label.text = _upgrade_track_text(Tower.UpgradeTrack.UPGRADE_2)
	range_label.text = _upgrade_track_text(Tower.UpgradeTrack.UPGRADE_3)
	damage_upgrade_button.text = "Upgrade %dg" % _selected_tower.get_upgrade_cost(
		Tower.UpgradeTrack.UPGRADE_1
	)
	attack_speed_upgrade_button.text = "Upgrade %dg" % _selected_tower.get_upgrade_cost(
		Tower.UpgradeTrack.UPGRADE_2
	)
	range_upgrade_button.text = "Upgrade %dg" % _selected_tower.get_upgrade_cost(
		Tower.UpgradeTrack.UPGRADE_3
	)
	damage_upgrade_button.disabled = not _selected_tower.can_upgrade(
		Tower.UpgradeTrack.UPGRADE_1
	)
	attack_speed_upgrade_button.disabled = not _selected_tower.can_upgrade(
		Tower.UpgradeTrack.UPGRADE_2
	)
	range_upgrade_button.disabled = not _selected_tower.can_upgrade(
		Tower.UpgradeTrack.UPGRADE_3
	)
	var upgrades_unlocked := CrystalInventory.is_skill_purchased(&"B")
	for upgrade_button in [
		damage_upgrade_button,
		attack_speed_upgrade_button,
		range_upgrade_button
	]:
		upgrade_button.tooltip_text = (
			"Unlock skill B — Tower Enhancements to upgrade towers."
			if not upgrades_unlocked
			else ""
		)
	priority_label.text = "Target priority: %s" % Tower.TargetPriority.keys()[
		_selected_tower.target_priority
	]
	trophy_carrier_checkbox.set_pressed_no_signal(
		_selected_tower.prioritize_trophy_carriers
	)

	for index in range(_priority_buttons.size()):
		var is_selected := index == _selected_tower.target_priority
		_priority_buttons[index].modulate = (
			Color(0.55, 1.0, 0.6) if is_selected else Color.WHITE
		)


func _has_selected_tower() -> bool:
	return (
		is_instance_valid(_selected_tower)
		and _selected_tower.is_inside_tree()
		and not _selected_tower.is_queued_for_deletion()
	)


func _upgrade_track_text(track: Tower.UpgradeTrack) -> String:
	return "Upgrade %d: %s (Lv. %d)" % [
		int(track) + 1,
		_selected_tower.get_upgrade_track_name(track),
		_selected_tower.get_upgrade_level(track)
	]


func _format_damage(value: float) -> String:
	if value <= 250.0:
		return "%.1f" % value
	return "%d" % roundi(value)
