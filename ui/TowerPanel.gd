extends PanelContainer

const RAPID_FIRE_CRYSTAL: CrystalData = preload("res://crystals/RapidFireCrystal.tres")
const SLOW_CRYSTAL: CrystalData = preload("res://crystals/SlowCrystal.tres")
const BLEED_CRYSTAL: CrystalData = preload("res://crystals/BleedCrystal.tres")

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
@onready var install_rapid_fire_button: Button = $MarginContainer/VBoxContainer/InstallRapidFireButton
@onready var install_slow_button: Button = $MarginContainer/VBoxContainer/InstallSlowButton
@onready var install_bleed_button: Button = $MarginContainer/VBoxContainer/InstallBleedButton
@onready var remove_crystal_button: Button = $MarginContainer/VBoxContainer/RemoveCrystalButton
@onready var priority_label: Label = $MarginContainer/VBoxContainer/PriorityLabel
@onready var nearest_button: Button = $MarginContainer/VBoxContainer/PriorityButtons/NearestButton
@onready var first_button: Button = $MarginContainer/VBoxContainer/PriorityButtons/FirstButton
@onready var strongest_button: Button = $MarginContainer/VBoxContainer/PriorityButtons/StrongestButton
@onready var trophy_carrier_checkbox: CheckBox = $MarginContainer/VBoxContainer/TrophyCarrierPriority
@onready var close_button: Button = $MarginContainer/VBoxContainer/Header/CloseButton

var _selected_tower: Tower
var _priority_buttons: Array[Button]


func _ready() -> void:
	_priority_buttons = [nearest_button, first_button, strongest_button]
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
	install_rapid_fire_button.pressed.connect(
		_on_install_crystal_pressed.bind(RAPID_FIRE_CRYSTAL)
	)
	install_slow_button.pressed.connect(_on_install_crystal_pressed.bind(SLOW_CRYSTAL))
	install_bleed_button.pressed.connect(_on_install_crystal_pressed.bind(BLEED_CRYSTAL))
	remove_crystal_button.pressed.connect(_on_remove_crystal_pressed)
	GoldManager.gold_changed.connect(_on_gold_changed)


func show_tower(tower: Tower) -> void:
	if _selected_tower != tower:
		if is_instance_valid(_selected_tower):
			_selected_tower.stats_changed.disconnect(_refresh)
		_selected_tower = tower
		_selected_tower.stats_changed.connect(_refresh)

	visible = true
	_refresh()


func clear_tower() -> void:
	if is_instance_valid(_selected_tower):
		_selected_tower.stats_changed.disconnect(_refresh)
	_selected_tower = null
	visible = false


func _on_priority_pressed(priority: int) -> void:
	if not is_instance_valid(_selected_tower):
		clear_tower()
		return

	_selected_tower.target_priority = priority
	priority_selected.emit(priority)
	_refresh()


func _on_trophy_carrier_priority_toggled(enabled: bool) -> void:
	if not is_instance_valid(_selected_tower):
		return

	_selected_tower.prioritize_trophy_carriers = enabled


func _on_upgrade_pressed(track: Tower.UpgradeTrack) -> void:
	if not is_instance_valid(_selected_tower):
		clear_tower()
		return

	_selected_tower.upgrade_tower_track(track)
	_refresh()


func _on_install_crystal_pressed(crystal: CrystalData) -> void:
	if not is_instance_valid(_selected_tower):
		clear_tower()
		return

	_selected_tower.install_main_crystal(crystal)
	_refresh()


func _on_remove_crystal_pressed() -> void:
	if not is_instance_valid(_selected_tower):
		clear_tower()
		return

	_selected_tower.remove_main_crystal()
	_refresh()


func _on_gold_changed(_amount: int) -> void:
	if is_instance_valid(_selected_tower):
		_refresh()


func _refresh() -> void:
	if not is_instance_valid(_selected_tower):
		clear_tower()
		return

	var crystal_instance := _selected_tower.get_main_crystal()
	var configuration := _selected_tower.current_attack_configuration
	tower_title.text = (
		"Tower - %s" % crystal_instance.definition.display_name
		if crystal_instance != null
		else "Tower"
	)
	main_socket_label.text = (
		"Main Socket: %s — Level %d"
		% [crystal_instance.definition.display_name, crystal_instance.level]
		if crystal_instance != null
		else "Main Socket: Empty"
	)
	var socket_is_empty := crystal_instance == null
	install_rapid_fire_button.visible = socket_is_empty
	install_slow_button.visible = socket_is_empty
	install_bleed_button.visible = socket_is_empty
	remove_crystal_button.visible = not socket_is_empty
	combat_stats_label.text = (
		"Damage: %d  |  Attack Speed: %s  |  Range: %.1f"
		% [
			roundi(configuration.damage),
			"N/A (Aura)"
			if configuration.attack_behavior == CrystalData.AttackBehavior.AURA
			else "%.1f/s" % configuration.attack_speed,
			configuration.attack_range
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


func _upgrade_track_text(track: Tower.UpgradeTrack) -> String:
	return "Upgrade %d: %s (Lv. %d)" % [
		int(track) + 1,
		_selected_tower.get_upgrade_track_name(track),
		_selected_tower.get_upgrade_level(track)
	]
