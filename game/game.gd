extends Node2D

const GAME_SCENE_PATH: String = "res://game/Game.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://ui/main_menu/MainMenu.tscn"
const SKILL_CATALOG = preload("res://managers/skill_tree_catalog.gd")

var build_mode: bool = false
var run_finished: bool = false
var _transitioning: bool = false
var selected_tower: Tower
var _passive_gold_timer: Timer

@onready var build_button: Button = $HUD/BuildButton
@onready var cancel_button: Button = $HUD/CancelButton
@onready var end_run_button: Button = $HUD/EndRunButton
@onready var tower_panel: PanelContainer = $HUD/TowerPanel
@onready var wave_manager: WaveManager = $WaveManager
@onready var wave_label: Label = $HUD/WaveLabel
@onready var wave_preview_label: Label = $HUD/WavePreviewLabel
@onready var start_wave_button: Button = $HUD/StartWaveButton
@onready var auto_waves_button: Button = $HUD/AutoWavesButton
@onready var wave_countdown_label: Label = $HUD/WaveCountdownLabel
@onready var pause_button: Button = $HUD/PauseButton
@onready var speed_half_button: Button = $HUD/SpeedHalfButton
@onready var speed_normal_button: Button = $HUD/SpeedNormalButton
@onready var speed_double_button: Button = $HUD/SpeedDoubleButton
@onready var speed_triple_button: Button = $HUD/SpeedTripleButton
@onready var castle: Castle = $Castle
@onready var trophy_label: Label = $HUD/TrophyLabel
@onready var enemy_path: Path2D = $EnemyPath
@onready var path_border: Line2D = $EnemyPath/PathBorder
@onready var path_surface: Line2D = $EnemyPath/PathSurface
@onready var game_over_overlay: ColorRect = $HUD/GameOverOverlay
@onready var restart_button: Button = $HUD/GameOverOverlay/DefeatPanel/DefeatContents/RestartButton
@onready var main_menu_button: Button = $HUD/GameOverOverlay/DefeatPanel/DefeatContents/MainMenuButton
@onready var end_run_overlay: ColorRect = $HUD/EndRunOverlay
@onready var continue_run_button: Button = $HUD/EndRunOverlay/ConfirmationPanel/ConfirmationContents/ContinueRunButton
@onready var confirm_end_run_button: Button = $HUD/EndRunOverlay/ConfirmationPanel/ConfirmationContents/EndRunButton
@onready var crystals_button: Button = $HUD/CrystalsButton
@onready var run_crystal_inventory_panel: RunCrystalInventoryPanel = $HUD/RunCrystalInventoryPanel
@onready var map_crystal_drop_surface: Control = $HUD/MapCrystalDropSurface


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_draw_enemy_path()
	build_button.text = "BUILD (%d GOLD)" % BuildSlot.CONSTRUCTION_PRICE
	AchievementManager.begin_run()
	GameSpeedManager.begin_run()
	GoldManager.start_new_run()
	CrystalInventory.start_run_inventory()
	$HUD.process_mode = Node.PROCESS_MODE_ALWAYS
	map_crystal_drop_surface.call("set_game", self)
	var run_seed_generator := RandomNumberGenerator.new()
	run_seed_generator.randomize()
	wave_manager.set_run_seed(run_seed_generator.randi())
	build_button.pressed.connect(_enter_build_mode)
	cancel_button.pressed.connect(_exit_build_mode)
	end_run_button.pressed.connect(_show_end_run_confirmation)
	crystals_button.pressed.connect(_toggle_crystal_inventory)
	CrystalInventory.profile_changed.connect(_on_profile_changed)
	run_crystal_inventory_panel.close_requested.connect(
		_close_crystal_inventory
	)
	tower_panel.set_inventory_panel(run_crystal_inventory_panel)
	tower_panel.close_requested.connect(_clear_tower_selection)
	start_wave_button.pressed.connect(_start_wave_manually)
	auto_waves_button.pressed.connect(_toggle_auto_waves)
	pause_button.pressed.connect(_toggle_pause)
	speed_half_button.pressed.connect(_set_simulation_speed.bind(0.5))
	speed_normal_button.pressed.connect(_set_simulation_speed.bind(1.0))
	speed_double_button.pressed.connect(_set_simulation_speed.bind(2.0))
	speed_triple_button.pressed.connect(_set_simulation_speed.bind(3.0))
	GameSpeedManager.speed_changed.connect(_on_simulation_speed_changed)
	GameSpeedManager.pause_changed.connect(_on_pause_changed)
	restart_button.pressed.connect(_restart_run)
	main_menu_button.pressed.connect(_return_to_main_menu)
	continue_run_button.pressed.connect(_continue_run)
	confirm_end_run_button.pressed.connect(_confirm_end_run)
	wave_manager.next_wave_changed.connect(_on_next_wave_changed)
	wave_manager.active_waves_changed.connect(_refresh_wave_hud)
	wave_manager.countdown_changed.connect(_on_countdown_changed)
	wave_manager.auto_waves_changed.connect(_on_auto_waves_changed)
	castle.treasury_count_changed.connect(_on_treasury_count_changed)
	castle.remaining_trophies_changed.connect(_on_remaining_trophies_changed)
	game_over_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	end_run_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_on_auto_waves_changed(wave_manager.auto_waves_enabled)
	_update_crystal_inventory_access()
	wave_manager.begin_run()
	_update_skill_locked_hud()
	_configure_passive_gold()
	_on_remaining_trophies_changed(
		castle.get_remaining_trophy_count(),
		castle.get_total_trophy_count()
	)
	_refresh_wave_hud()
	_update_speed_controls()
	for node in get_tree().get_nodes_in_group("build_slots"):
		if node is BuildSlot:
			node.tower_built.connect(_on_tower_built)
	_update_build_mode()


func _on_profile_changed(_profile: Dictionary) -> void:
	_update_crystal_inventory_access()
	_update_skill_locked_hud()


func _update_crystal_inventory_access() -> void:
	var unlocked := CrystalInventory.is_crystal_inventory_unlocked()
	crystals_button.visible = unlocked
	if not unlocked:
		run_crystal_inventory_panel.hide()


func _toggle_crystal_inventory() -> void:
	if run_finished or not CrystalInventory.is_crystal_inventory_unlocked():
		return
	run_crystal_inventory_panel.visible = not run_crystal_inventory_panel.visible
	if run_crystal_inventory_panel.visible:
		run_crystal_inventory_panel.refresh()
		run_crystal_inventory_panel.set_feedback("")


func _close_crystal_inventory() -> void:
	run_crystal_inventory_panel.hide()


func _exit_tree() -> void:
	AchievementManager.end_run()
	if is_instance_valid(_passive_gold_timer):
		_passive_gold_timer.stop()
	if CrystalInventory.profile_changed.is_connected(_on_profile_changed):
		CrystalInventory.profile_changed.disconnect(_on_profile_changed)
	CrystalInventory.end_run_inventory()


func _draw_enemy_path() -> void:
	var curve := enemy_path.curve
	var distance := 0.0
	var baked_length := curve.get_baked_length()
	while distance < baked_length:
		var point := curve.sample_baked(distance)
		path_border.add_point(point)
		path_surface.add_point(point)
		distance += 8.0

	var endpoint := curve.sample_baked(baked_length)
	path_border.add_point(endpoint)
	path_surface.add_point(endpoint)


func _on_treasury_count_changed(count: int) -> void:
	if not is_instance_valid(castle):
		return
	_on_remaining_trophies_changed(castle.get_remaining_trophy_count(), castle.get_total_trophy_count())


func _on_remaining_trophies_changed(remaining: int, total: int) -> void:
	trophy_label.text = "Trophies: %d/%d" % [remaining, total]
	if remaining <= 0:
		_finish_run()


func _finish_run() -> void:
	if run_finished:
		return

	run_finished = true
	AchievementManager.end_run()
	_update_speed_controls()
	if is_instance_valid(_passive_gold_timer):
		_passive_gold_timer.stop()
	wave_manager.stop_spawning()
	GoldManager.end_run()
	CrystalInventory.end_run_inventory()
	build_mode = false
	build_button.disabled = true
	build_button.visible = false
	cancel_button.disabled = true
	cancel_button.visible = false
	end_run_button.disabled = true
	end_run_button.visible = false
	start_wave_button.disabled = true
	auto_waves_button.disabled = true
	end_run_overlay.visible = false
	run_crystal_inventory_panel.hide()
	_clear_tower_selection()
	for node in get_tree().get_nodes_in_group("build_slots"):
		if node is BuildSlot:
			node.set_build_mode(false)

	game_over_overlay.visible = true
	call_deferred("_pause_finished_run")


func _pause_finished_run() -> void:
	if run_finished and not _transitioning:
		GameSpeedManager.set_paused(true)


func _restart_run() -> void:
	_leave_run(GAME_SCENE_PATH)


func _show_end_run_confirmation() -> void:
	if run_finished or _transitioning:
		return

	end_run_overlay.visible = true
	GameSpeedManager.set_paused(true)


func _continue_run() -> void:
	if run_finished:
		return

	end_run_overlay.visible = false
	GameSpeedManager.set_paused(false)


func _toggle_pause() -> void:
	if run_finished or _transitioning:
		return
	GameSpeedManager.set_paused(not GameSpeedManager.is_paused)


func _set_simulation_speed(multiplier: float) -> void:
	if run_finished or _transitioning:
		return
	GameSpeedManager.set_simulation_speed(multiplier)
	_update_speed_controls()


func _on_simulation_speed_changed(_multiplier: float) -> void:
	_update_speed_controls()


func _on_pause_changed(_paused: bool) -> void:
	_update_speed_controls()


func _update_speed_controls() -> void:
	if not is_instance_valid(pause_button):
		return
	pause_button.text = "RESUME" if GameSpeedManager.is_paused else "PAUSE"
	pause_button.disabled = run_finished
	var speed_buttons: Array[Button] = [
		speed_half_button,
		speed_normal_button,
		speed_double_button,
		speed_triple_button
	]
	for index in range(speed_buttons.size()):
		var button := speed_buttons[index]
		button.set_pressed_no_signal(
			is_equal_approx(
				GameSpeedManager.simulation_speed,
				GameSpeedManager.SPEED_OPTIONS[index]
			)
		)
		button.disabled = run_finished


func _confirm_end_run() -> void:
	_leave_run(MAIN_MENU_SCENE_PATH)


func _return_to_main_menu() -> void:
	_leave_run(MAIN_MENU_SCENE_PATH)


func _leave_run(scene_path: String) -> void:
	if _transitioning:
		return

	_transitioning = true
	AchievementManager.end_run()
	if is_instance_valid(_passive_gold_timer):
		_passive_gold_timer.stop()
	wave_manager.stop_spawning()
	GoldManager.end_run()
	CrystalInventory.end_run_inventory()
	GameSpeedManager.reset()
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		_transitioning = false
		push_error("Could not leave the current run for '%s' (error %d)." % [
			scene_path,
			error
		])


func _enter_build_mode() -> void:
	if run_finished:
		return
	build_mode = true
	_update_build_mode()


func _exit_build_mode() -> void:
	build_mode = false
	_update_build_mode()


func _on_tower_built() -> void:
	_exit_build_mode()


func _update_build_mode() -> void:
	build_button.visible = not build_mode
	cancel_button.visible = build_mode

	if build_mode:
		_clear_tower_selection()

	for node in get_tree().get_nodes_in_group("build_slots"):
		if node is BuildSlot:
			node.set_build_mode(build_mode)


func _unhandled_input(event: InputEvent) -> void:
	if run_finished:
		get_viewport().set_input_as_handled()
		return

	if build_mode:
		return

	var screen_position: Vector2
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
			return
		screen_position = event.position
	elif event is InputEventScreenTouch and event.pressed:
		screen_position = event.position
	else:
		return

	if _is_over_interactive_hud_control(screen_position):
		return

	var tower := get_tower_at_screen_position(screen_position)
	if is_instance_valid(tower):
		_select_tower(tower)
	else:
		_clear_tower_selection()
		_close_crystal_inventory()


func _is_over_interactive_hud_control(screen_position: Vector2) -> bool:
	for node in $HUD.find_children("*", "Control", true, false):
		var control := node as Control
		if (
			control == map_crystal_drop_surface
			or not control.is_visible_in_tree()
			or control.mouse_filter != Control.MOUSE_FILTER_STOP
		):
			continue
		if control.get_global_rect().has_point(screen_position):
			return true
	return false


func get_tower_at_screen_position(screen_position: Vector2) -> Tower:
	var world_position := (
		get_viewport().get_canvas_transform().affine_inverse()
		* screen_position
	)
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collide_with_areas = true

	var nearest_tower: Tower
	var nearest_distance := INF
	for result in get_world_2d().direct_space_state.intersect_point(query):
		var collider := result["collider"] as Tower
		if (
			not is_instance_valid(collider)
			or collider.is_queued_for_deletion()
		):
			continue
		var distance := collider.global_position.distance_squared_to(world_position)
		if distance < nearest_distance:
			nearest_tower = collider
			nearest_distance = distance
	return nearest_tower


func update_map_crystal_drop_highlights(
	data: Variant,
	hovered_tower: Tower
) -> void:
	var definition: CrystalData
	var crystal_is_available := (
		data is Dictionary
		and typeof(data.get("crystal_id")) == TYPE_STRING
		and typeof(data.get("level")) == TYPE_INT
		and not build_mode
		and not run_finished
	)
	if crystal_is_available:
		definition = CrystalInventory.get_crystal_definition(
			StringName(data.get("crystal_id", ""))
		)
		crystal_is_available = CrystalInventory.can_install_crystal(
			definition,
			int(data.get("level", 0))
		)

	for node in get_tree().get_nodes_in_group("towers"):
		var tower := node as Tower
		var is_valid_target := (
			crystal_is_available
			and is_instance_valid(tower)
			and bool(tower_panel.call(
				"can_install_crystal_on_tower",
				tower,
				data,
				true
			))
		)
		tower.set_crystal_drop_highlight(
			is_valid_target,
			tower == hovered_tower,
			is_valid_target and tower.has_main_crystal()
		)


func clear_map_crystal_drop_highlights() -> void:
	for node in get_tree().get_nodes_in_group("towers"):
		(node as Tower).set_crystal_drop_highlight(false)


func drop_crystal_on_map(data: Variant, screen_position: Vector2) -> bool:
	clear_map_crystal_drop_highlights()
	if run_finished or build_mode:
		run_crystal_inventory_panel.set_feedback(
			"Crystal drops are unavailable while building or after the run."
		)
		return false
	if (
		not data is Dictionary
		or data.get("type") != "run_crystal"
		or typeof(data.get("crystal_id")) != TYPE_STRING
		or typeof(data.get("level")) != TYPE_INT
	):
		run_crystal_inventory_panel.set_feedback("Invalid crystal drop.")
		return false

	var tower := get_tower_at_screen_position(screen_position)
	if not is_instance_valid(tower):
		run_crystal_inventory_panel.set_feedback("Drop the crystal onto a tower.")
		return false
	if not bool(tower_panel.call(
		"can_install_crystal_on_tower",
		tower,
		data,
		true
	)):
		run_crystal_inventory_panel.set_feedback(
			"That tower cannot accept this crystal."
		)
		return false

	var installed: bool = tower_panel.install_crystal_on_tower(
		tower,
		data,
		true
	)
	return installed


func _select_tower(tower: Tower) -> void:
	if selected_tower == tower:
		tower_panel.show_tower(tower)
		return

	_clear_tower_selection()
	selected_tower = tower
	selected_tower.set_range_visible(true)
	tower_panel.show_tower(tower)
	tower.tree_exiting.connect(_on_selected_tower_exiting, CONNECT_ONE_SHOT)


func _clear_tower_selection() -> void:
	if is_instance_valid(selected_tower):
		selected_tower.set_range_visible(false)
		var callback := Callable(self, "_on_selected_tower_exiting")
		if selected_tower.tree_exiting.is_connected(callback):
			selected_tower.tree_exiting.disconnect(callback)

	selected_tower = null
	tower_panel.clear_tower()


func _on_selected_tower_exiting() -> void:
	selected_tower = null
	tower_panel.clear_tower()


func _on_next_wave_changed(wave_number: int) -> void:
	start_wave_button.text = "SEND WAVE %d" % wave_number
	_refresh_wave_hud()


func _refresh_wave_hud() -> void:
	var active_summaries := wave_manager.get_active_wave_summaries()
	if active_summaries.is_empty():
		wave_label.text = "NEXT WAVE"
	else:
		var active_numbers := PackedStringArray()
		for summary in active_summaries:
			active_numbers.append(str(summary["wave_number"]))
		wave_label.text = "ACTIVE WAVES: %s" % ", ".join(active_numbers)

	var preview_wave := wave_manager.get_preview_wave_number()
	var preview := wave_manager.get_wave_preview(preview_wave)
	wave_preview_label.text = _format_wave_preview(preview)
	start_wave_button.text = "SEND WAVE %d" % preview_wave


func _start_wave_manually() -> void:
	if run_finished or _transitioning:
		return

	wave_manager.start_wave(WaveManager.StartReason.MANUAL)


func _toggle_auto_waves() -> void:
	if run_finished:
		return
	wave_manager.set_auto_waves_enabled(not wave_manager.auto_waves_enabled)


func _on_auto_waves_changed(enabled: bool) -> void:
	auto_waves_button.text = "Auto Waves: %s" % ("ON" if enabled else "OFF")
	auto_waves_button.visible = CrystalInventory.is_skill_purchased(&"E")
	auto_waves_button.disabled = run_finished
	auto_waves_button.tooltip_text = ""


func _configure_passive_gold() -> void:
	if not CrystalInventory.is_skill_purchased(&"P"):
		if is_instance_valid(_passive_gold_timer):
			_passive_gold_timer.stop()
		return
	if is_instance_valid(_passive_gold_timer):
		return
	_passive_gold_timer = Timer.new()
	_passive_gold_timer.name = "PassiveGoldTimer"
	_passive_gold_timer.wait_time = SKILL_CATALOG.PASSIVE_GOLD_INTERVAL_SECONDS
	_passive_gold_timer.timeout.connect(_on_passive_gold_timeout)
	add_child(_passive_gold_timer)
	_passive_gold_timer.start()


func _update_skill_locked_hud() -> void:
	auto_waves_button.visible = CrystalInventory.is_skill_purchased(&"E")
	wave_preview_label.visible = CrystalInventory.is_skill_purchased(&"Q")
	if wave_preview_label.visible and is_instance_valid(wave_manager):
		_refresh_wave_hud()
	_configure_passive_gold()


func _on_passive_gold_timeout() -> void:
	if not run_finished and not _transitioning:
		GoldManager.add_gold(
			roundi(CrystalInventory.get_skill_effect_value(&"passive_gold"))
		)


func _on_countdown_changed(message: String) -> void:
	wave_countdown_label.text = message


func _format_wave_preview(preview: Dictionary) -> String:
	var lines: PackedStringArray = [
		"Wave: %d" % preview["wave_number"]
	]
	for group in preview["groups"]:
		lines.append(
			"%s: %d  |  HP: %d  |  Speed: %d%%" % [
				group["display_name"],
				group["quantity"],
				group["hp"],
				group["speed_percent"]
			]
		)
	if CrystalInventory.is_skill_purchased(&"Q"):
		lines.append("Total enemies: %d" % preview["total_enemies"])
		var gold_bonus: float = preview["gold_bonus_percent"]
		if is_equal_approx(gold_bonus, round(gold_bonus)):
			lines.append("Gold Bonus: +%d%%" % roundi(gold_bonus))
		else:
			lines.append("Gold Bonus: +%.1f%%" % gold_bonus)
	return "\n".join(lines)
