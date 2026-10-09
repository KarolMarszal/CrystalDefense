extends Node2D

const GAME_SCENE_PATH: String = "res://game/Game.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://ui/main_menu/MainMenu.tscn"

var build_mode: bool = false
var run_finished: bool = false
var _transitioning: bool = false
var selected_tower: Tower

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


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_draw_enemy_path()
	GoldManager.start_new_run()
	$HUD.process_mode = Node.PROCESS_MODE_ALWAYS
	var run_seed_generator := RandomNumberGenerator.new()
	run_seed_generator.randomize()
	wave_manager.set_run_seed(run_seed_generator.randi())
	build_button.pressed.connect(_enter_build_mode)
	cancel_button.pressed.connect(_exit_build_mode)
	end_run_button.pressed.connect(_show_end_run_confirmation)
	tower_panel.close_requested.connect(_clear_tower_selection)
	start_wave_button.pressed.connect(_start_wave_manually)
	auto_waves_button.pressed.connect(_toggle_auto_waves)
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
	wave_manager.begin_run()
	_on_remaining_trophies_changed(
		castle.get_remaining_trophy_count(),
		castle.get_total_trophy_count()
	)
	_refresh_wave_hud()
	for node in get_tree().get_nodes_in_group("build_slots"):
		if node is BuildSlot:
			node.tower_built.connect(_on_tower_built)
	_update_build_mode()


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
	wave_manager.stop_spawning()
	GoldManager.end_run()
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
	_clear_tower_selection()
	for node in get_tree().get_nodes_in_group("build_slots"):
		if node is BuildSlot:
			node.set_build_mode(false)

	game_over_overlay.visible = true
	call_deferred("_pause_finished_run")


func _pause_finished_run() -> void:
	if run_finished and not _transitioning:
		get_tree().paused = true


func _restart_run() -> void:
	_leave_run(GAME_SCENE_PATH)


func _show_end_run_confirmation() -> void:
	if run_finished or _transitioning:
		return

	end_run_overlay.visible = true
	get_tree().paused = true


func _continue_run() -> void:
	if run_finished:
		return

	end_run_overlay.visible = false
	get_tree().paused = false


func _confirm_end_run() -> void:
	_leave_run(MAIN_MENU_SCENE_PATH)


func _return_to_main_menu() -> void:
	_leave_run(MAIN_MENU_SCENE_PATH)


func _leave_run(scene_path: String) -> void:
	if _transitioning:
		return

	_transitioning = true
	wave_manager.stop_spawning()
	GoldManager.end_run()
	get_tree().paused = false
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

	var world_position := get_viewport().get_canvas_transform().affine_inverse() * screen_position
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collide_with_areas = true

	for result in get_world_2d().direct_space_state.intersect_point(query):
		var tower := result["collider"] as Tower
		if is_instance_valid(tower):
			_select_tower(tower)
			return

	_clear_tower_selection()


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
	wave_manager.set_auto_waves_enabled(not wave_manager.auto_waves_enabled)


func _on_auto_waves_changed(enabled: bool) -> void:
	auto_waves_button.text = "Auto Waves: %s" % ("ON" if enabled else "OFF")


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
	lines.append("Total enemies: %d" % preview["total_enemies"])
	var gold_bonus: float = preview["gold_bonus_percent"]
	if is_equal_approx(gold_bonus, round(gold_bonus)):
		lines.append("Gold Bonus: +%d%%" % roundi(gold_bonus))
	else:
		lines.append("Gold Bonus: +%.1f%%" % gold_bonus)
	return "\n".join(lines)
