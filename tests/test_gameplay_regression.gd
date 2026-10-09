extends GdUnitTestSuite

const ENEMY_SCENE: PackedScene = preload("res://enemies/Enemy.tscn")
const GAME_SCENE: PackedScene = preload("res://game/Game.tscn")
const MAIN_MENU_SCENE: PackedScene = preload("res://ui/main_menu/MainMenu.tscn")
const INVENTORY_SCENE: PackedScene = preload(
	"res://ui/main_menu/CrystalInventory.tscn"
)
const TOWER_SCENE: PackedScene = preload("res://towers/Tower.tscn")
const TROPHY_SCENE: PackedScene = preload("res://game/Trophy.tscn")
const GOBLIN_DATA: EnemyData = preload("res://enemies/Goblin.tres")
const SKELETON_DATA: EnemyData = preload("res://enemies/Skeleton.tres")
const TROLL_DATA: EnemyData = preload("res://enemies/Troll.tres")
const SLOW_CRYSTAL: CrystalData = preload("res://crystals/SlowCrystal.tres")
const RAPID_FIRE_CRYSTAL: CrystalData = preload(
	"res://crystals/RapidFireCrystal.tres"
)

var _original_gold: int
var _created_nodes: Array[Node] = []
var _original_current_scene: Node


func before_test() -> void:
	_original_gold = GoldManager.run_gold
	_original_current_scene = get_tree().current_scene
	GoldManager.end_run()


func after_test() -> void:
	get_tree().paused = false
	if get_tree().current_scene != _original_current_scene:
		var transitioned_scene := get_tree().current_scene
		get_tree().current_scene = null
		if is_instance_valid(transitioned_scene):
			transitioned_scene.free()

	for node in _created_nodes:
		if is_instance_valid(node):
			node.free()
	_created_nodes.clear()

	GoldManager.end_run()
	if _original_gold > 0:
		GoldManager.add_gold(_original_gold)


func test_run_gold_starts_and_ends_at_the_existing_run_values() -> void:
	GoldManager.start_new_run()
	assert_int(GoldManager.run_gold).is_equal(GoldManager.STARTING_RUN_GOLD)
	assert_bool(GoldManager.can_afford(100)).is_true()
	assert_bool(GoldManager.spend_gold(GoldManager.STARTING_RUN_GOLD + 1)).is_false()
	GoldManager.add_gold(-1)
	assert_bool(GoldManager.spend_gold(100)).is_true()
	assert_int(GoldManager.run_gold).is_equal(GoldManager.STARTING_RUN_GOLD - 100)
	GoldManager.end_run()
	assert_int(GoldManager.run_gold).is_equal(0)


func test_enemy_final_death_awards_gold_exactly_once() -> void:
	var enemy := _make_enemy(GOBLIN_DATA, 20)
	var expected_reward := enemy.gold_reward

	enemy.die()
	enemy.die()

	assert_bool(enemy.is_dead).is_true()
	assert_int(GoldManager.run_gold).is_equal(expected_reward)


func test_skeleton_resurrection_delays_reward_and_final_death_rewards_once() -> void:
	var deterministic_skeleton := SKELETON_DATA.duplicate(true) as EnemyData
	deterministic_skeleton.resurrection_chance = 1.0
	var enemy := _make_enemy(deterministic_skeleton, 100)

	enemy.take_damage(100)

	assert_int(enemy.resurrection_count).is_equal(1)
	assert_bool(enemy.is_dead).is_false()
	assert_int(GoldManager.run_gold).is_equal(0)

	enemy.take_damage(100)
	enemy.die()

	assert_bool(enemy.is_dead).is_true()
	assert_int(GoldManager.run_gold).is_equal(deterministic_skeleton.gold_reward)


func test_troll_regeneration_uses_percent_of_max_hp_per_second() -> void:
	var enemy := _make_enemy(TROLL_DATA)
	enemy.take_damage(100)
	var damaged_hp := enemy.hp

	enemy._regenerate(0.5)

	assert_int(enemy.hp - damaged_hp).is_equal(7)


func test_tower_nearest_and_strongest_target_priorities() -> void:
	var tower := _make_tower()
	var nearest := _make_enemy(GOBLIN_DATA, 10)
	var strongest := _make_enemy(GOBLIN_DATA, 90)
	var middle := _make_enemy(GOBLIN_DATA, 40)
	nearest.position = Vector2(20.0, 0.0)
	strongest.position = Vector2(65.0, 0.0)
	middle.position = Vector2(45.0, 0.0)

	tower.target_priority = Tower.TargetPriority.NEAREST
	assert_object(tower.select_target(180.0)).is_same(nearest)

	tower.target_priority = Tower.TargetPriority.STRONGEST
	assert_object(tower.select_target(180.0)).is_same(strongest)


func test_first_target_prefers_returning_enemies_then_greatest_progress() -> void:
	var tower := _make_tower()
	tower.target_priority = Tower.TargetPriority.FIRST
	var moving := _make_enemy(GOBLIN_DATA)
	var returning := _make_enemy(GOBLIN_DATA)
	moving.path_distance = 110.0
	returning.path_distance = 20.0
	returning.movement_direction = Enemy.MovementDirection.RETURNING_TO_CAMP

	assert_object(tower.select_target(180.0)).is_same(returning)

	moving.movement_direction = Enemy.MovementDirection.RETURNING_TO_CAMP
	moving.path_distance = 50.0
	assert_object(tower.select_target(180.0)).is_same(moving)


func test_tower_prioritizes_in_range_trophy_carriers_then_falls_back() -> void:
	var tower := _make_tower()
	tower.target_priority = Tower.TargetPriority.NEAREST
	tower.prioritize_trophy_carriers = true
	var nearby := _make_enemy(GOBLIN_DATA)
	var carrier := _make_enemy(GOBLIN_DATA)
	nearby.position = Vector2(10.0, 0.0)
	carrier.position = Vector2(70.0, 0.0)
	var trophy := TROPHY_SCENE.instantiate() as Trophy
	carrier.add_child(trophy)
	carrier.carried_trophies.append(trophy)

	assert_object(tower.select_target(180.0)).is_same(carrier)

	carrier.position = Vector2(200.0, 0.0)
	assert_object(tower.select_target(180.0)).is_same(nearby)


func test_crystal_installation_removal_and_slow_aura_effect() -> void:
	var tower := _make_tower()
	var enemy := _make_enemy(GOBLIN_DATA)
	enemy.position = Vector2(30.0, 0.0)

	assert_bool(tower.install_main_crystal(SLOW_CRYSTAL, 1)).is_true()
	assert_bool(tower.has_main_crystal()).is_true()
	assert_bool(tower.install_main_crystal(RAPID_FIRE_CRYSTAL, 1)).is_false()
	tower._process(0.1)
	assert_float(enemy.effective_speed).is_equal(enemy.speed * 0.5)

	var removed: CrystalInstance = tower.remove_main_crystal()
	assert_bool(removed != null).is_true()
	assert_str(String(removed.definition.crystal_id)).is_equal("slow")
	assert_int(removed.level).is_equal(1)
	assert_bool(tower.has_main_crystal()).is_false()
	assert_float(enemy.effective_speed).is_equal(enemy.speed)


func test_tower_panel_install_remove_and_crystal_configuration_stay_in_sync() -> void:
	var game = _make_game()
	var tower := game.get_node("Tower") as Tower
	var panel := game.get_node("HUD/TowerPanel") as PanelContainer
	var install_button := panel.get_node(
		"MarginContainer/VBoxContainer/InstallRapidFireButton"
	) as Button
	var remove_button := panel.get_node(
		"MarginContainer/VBoxContainer/RemoveCrystalButton"
	) as Button
	var profile_before: Dictionary = CrystalInventory.get_profile_data()
	var stats_change_count := [0]
	tower.stats_changed.connect(
		func() -> void:
			stats_change_count[0] += 1
	)
	game._select_tower(tower)
	game._select_tower(tower)

	assert_bool(panel.visible).is_true()
	install_button.pressed.emit()

	var installed := tower.get_main_crystal()
	assert_bool(installed != null).is_true()
	assert_object(installed.definition).is_same(RAPID_FIRE_CRYSTAL)
	assert_int(installed.level).is_equal(1)
	assert_int(tower.damage).is_equal(12)
	assert_float(tower.attack_speed).is_equal(2.0)
	assert_float(tower.attack_range).is_equal(180.0)
	assert_bool(install_button.visible).is_false()
	assert_bool(remove_button.visible).is_true()
	assert_int(stats_change_count[0]).is_equal(1)

	install_button.pressed.emit()
	assert_object(tower.get_main_crystal()).is_same(installed)
	assert_int(stats_change_count[0]).is_equal(1)

	remove_button.pressed.emit()
	assert_bool(tower.main_socket.is_empty()).is_true()
	assert_bool(tower.get_main_crystal() == null).is_true()
	assert_bool(install_button.visible).is_true()
	assert_bool(remove_button.visible).is_false()
	assert_int(stats_change_count[0]).is_equal(2)

	remove_button.pressed.emit()
	assert_bool(tower.remove_main_crystal() == null).is_true()
	assert_int(stats_change_count[0]).is_equal(2)
	assert_bool(tower.install_main_crystal(null)).is_false()
	assert_bool(tower.main_socket.is_empty()).is_true()
	assert_int(stats_change_count[0]).is_equal(2)
	assert_bool(CrystalInventory.get_profile_data() == profile_before).is_true()


func test_game_lifecycle_resets_run_state_without_changing_profile() -> void:
	var profile_before: Dictionary = CrystalInventory.get_profile_data()
	assert_int(get_tree().change_scene_to_packed(MAIN_MENU_SCENE)).is_equal(OK)
	await _await_scene_change()
	var menu: Variant = get_tree().current_scene
	assert_bool(menu != null).is_true()

	var start_button := menu.get_node(
		"CenterPanel/MarginContainer/MenuContents/StartButton"
	) as Button
	start_button.pressed.emit()
	await _await_scene_change()
	var first_game: Variant = get_tree().current_scene
	assert_str(first_game.scene_file_path).is_equal("res://game/Game.tscn")
	var first_wave_manager := first_game.get_node("WaveManager") as WaveManager
	assert_int(GoldManager.run_gold).is_equal(GoldManager.STARTING_RUN_GOLD)
	assert_int(first_wave_manager.next_wave_number).is_equal(1)
	assert_int(first_wave_manager.active_waves.size()).is_equal(0)
	assert_bool(first_wave_manager.auto_waves_enabled).is_true()
	assert_bool(first_wave_manager._initial_countdown_started).is_true()

	var first_tower := first_game.get_node("Tower") as Tower
	first_game._select_tower(first_tower)
	var first_panel := first_game.get_node("HUD/TowerPanel") as PanelContainer
	first_panel.get_node(
		"MarginContainer/VBoxContainer/InstallRapidFireButton"
	).pressed.emit()
	assert_bool(first_tower.has_main_crystal()).is_true()
	assert_bool(first_game.selected_tower == first_tower).is_true()

	GoldManager.add_gold(37)
	first_game.start_wave_button.pressed.emit()
	assert_int(first_wave_manager.active_waves.size()).is_equal(1)
	assert_bool(first_game.get_node("Enemies").get_child_count() > 0).is_true()

	var starting_trophies: int = first_game.castle.get_total_trophy_count()
	for index in range(starting_trophies):
		first_game.castle.register_permanent_trophy_loss(
			StringName("integration_trophy_%d" % index)
		)
	await get_tree().process_frame
	assert_bool(first_game.run_finished).is_true()
	assert_bool(first_game.game_over_overlay.visible).is_true()
	assert_bool(first_wave_manager._spawning_stopped).is_true()
	assert_bool(first_wave_manager._automatic_start_timers.is_empty()).is_true()
	assert_int(GoldManager.run_gold).is_equal(0)

	var wave_number_at_game_over := first_wave_manager.next_wave_number
	first_game.start_wave_button.pressed.emit()
	first_game.continue_run_button.pressed.emit()
	first_game._on_remaining_trophies_changed(0, starting_trophies)
	assert_int(first_wave_manager.next_wave_number).is_equal(wave_number_at_game_over)
	assert_int(first_wave_manager.active_waves.size()).is_equal(1)
	assert_int(GoldManager.run_gold).is_equal(0)
	assert_bool(get_tree().paused).is_true()

	var old_game_ref: WeakRef = weakref(first_game)
	var old_wave_manager_ref: WeakRef = weakref(first_wave_manager)
	first_game.restart_button.pressed.emit()
	first_game.restart_button.pressed.emit()
	await _await_scene_change()
	assert_bool(old_game_ref.get_ref() == null).is_true()
	assert_bool(old_wave_manager_ref.get_ref() == null).is_true()

	var retried_game: Variant = get_tree().current_scene
	assert_str(retried_game.scene_file_path).is_equal("res://game/Game.tscn")
	var retried_wave_manager := retried_game.get_node("WaveManager") as WaveManager
	assert_bool(retried_game.run_finished).is_false()
	assert_bool(retried_game.selected_tower == null).is_true()
	assert_int(retried_wave_manager.next_wave_number).is_equal(1)
	assert_int(retried_wave_manager.active_waves.size()).is_equal(0)
	assert_int(retried_wave_manager.completed_wave_numbers.size()).is_equal(0)
	assert_bool(retried_wave_manager.auto_waves_enabled).is_true()
	assert_bool(retried_wave_manager._initial_countdown_started).is_true()
	assert_int(retried_game.get_node("Enemies").get_child_count()).is_equal(0)
	assert_bool(
		(retried_game.get_node("Tower") as Tower).main_socket.is_empty()
	).is_true()
	assert_int(GoldManager.run_gold).is_equal(GoldManager.STARTING_RUN_GOLD)

	var build_slots := get_tree().get_nodes_in_group("build_slots")
	assert_int(build_slots.size()).is_equal(3)
	for build_slot in build_slots:
		assert_int(build_slot.tower_built.get_connections().size()).is_equal(1)

	retried_game.end_run_button.pressed.emit()
	assert_bool(retried_game.end_run_overlay.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	retried_game.confirm_end_run_button.pressed.emit()
	await _await_scene_change()
	assert_str(get_tree().current_scene.scene_file_path).is_equal(
		"res://ui/main_menu/MainMenu.tscn"
	)
	assert_bool(get_tree().paused).is_false()
	assert_int(GoldManager.run_gold).is_equal(0)

	var menu_after_run: Variant = get_tree().current_scene
	var start_again_button := menu_after_run.get_node(
		"CenterPanel/MarginContainer/MenuContents/StartButton"
	) as Button
	start_again_button.pressed.emit()
	await _await_scene_change()
	var second_game: Variant = get_tree().current_scene
	assert_str(second_game.scene_file_path).is_equal("res://game/Game.tscn")
	assert_bool(second_game.run_finished).is_false()
	assert_int(second_game.wave_manager.next_wave_number).is_equal(1)
	assert_int(second_game.wave_manager.active_waves.size()).is_equal(0)
	assert_int(second_game.get_node("Enemies").get_child_count()).is_equal(0)
	assert_int(GoldManager.run_gold).is_equal(GoldManager.STARTING_RUN_GOLD)
	assert_bool(CrystalInventory.get_profile_data() == profile_before).is_true()


func test_manual_early_wave_bonus_excludes_killed_enemies() -> void:
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	wave_manager.wave_config_overrides = [
		_create_wave_config(1, 5, GOBLIN_DATA),
		_create_wave_config(2, 1, GOBLIN_DATA)
	]
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	for _index in range(4):
		wave_manager._process(wave_manager.spawn_interval)

	var enemies: Array[Node] = game.get_node("Enemies").get_children()
	assert_int(enemies.size()).is_equal(5)
	(enemies[0] as Enemy)._mark_inactive()
	(enemies[1] as Enemy)._mark_inactive()
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)

	var summaries: Array[Dictionary] = wave_manager.get_active_wave_summaries()
	var wave_two: Dictionary = _find_wave_summary(summaries, 2)
	assert_float(wave_two["gold_multiplier"]).is_equal(1.18)
	assert_int(wave_two["start_reason"]).is_equal(WaveManager.StartReason.MANUAL)


func test_manual_early_wave_bonus_is_capped_at_thirty_percent() -> void:
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	wave_manager.wave_config_overrides = [
		_create_wave_config(1, 5, GOBLIN_DATA),
		_create_wave_config(2, 1, GOBLIN_DATA)
	]
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	for _index in range(4):
		wave_manager._process(wave_manager.spawn_interval)
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)

	var wave_two := _find_wave_summary(
		wave_manager.get_active_wave_summaries(),
		2
	)
	assert_float(wave_two["gold_multiplier"]).is_equal(1.3)


func test_automatic_wave_does_not_receive_manual_early_send_bonus() -> void:
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	wave_manager.wave_config_overrides = [
		_create_wave_config(1, 1, GOBLIN_DATA),
		_create_wave_config(2, 1, GOBLIN_DATA)
	]
	wave_manager.start_wave(WaveManager.StartReason.INITIAL)
	wave_manager.auto_waves_enabled = true
	wave_manager.start_wave(WaveManager.StartReason.AUTOMATIC)

	var wave_two: Dictionary = _find_wave_summary(
		wave_manager.get_active_wave_summaries(),
		2
	)
	assert_float(wave_two["gold_multiplier"]).is_equal(1.0)
	assert_int(wave_two["start_reason"]).is_equal(WaveManager.StartReason.AUTOMATIC)


func test_auto_wave_schedule_can_be_cancelled_and_started_deterministically() -> void:
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	wave_manager.wave_config_overrides = [
		_create_wave_config(1, 1, GOBLIN_DATA),
		_create_wave_config(2, 1, GOBLIN_DATA)
	]
	wave_manager.start_wave(WaveManager.StartReason.INITIAL)

	wave_manager.set_auto_waves_enabled(true)
	assert_bool(wave_manager._automatic_start_timers.has(2)).is_true()
	var stale_token: int = wave_manager._automatic_start_tokens[2]
	var stale_generation: int = wave_manager._automatic_schedule_generation
	var stale_timer: Timer = wave_manager._automatic_start_timers[2]
	wave_manager.set_auto_waves_enabled(false)
	assert_bool(wave_manager._automatic_start_timers.has(2)).is_false()
	wave_manager._on_automatic_start_timeout(
		2,
		stale_token,
		stale_generation,
		stale_timer
	)
	assert_int(wave_manager.next_wave_number).is_equal(2)

	wave_manager.set_auto_waves_enabled(true)
	var token: int = wave_manager._automatic_start_tokens[2]
	var generation: int = wave_manager._automatic_schedule_generation
	var timer: Timer = wave_manager._automatic_start_timers[2]
	wave_manager._on_automatic_start_timeout(2, token, generation, timer)

	var wave_two: Dictionary = _find_wave_summary(
		wave_manager.get_active_wave_summaries(),
		2
	)
	assert_int(wave_two["start_reason"]).is_equal(WaveManager.StartReason.AUTOMATIC)


func test_wave_progress_tracks_spawns_and_completes_after_all_enemies_inactivate() -> void:
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	wave_manager.wave_config_overrides = [
		_create_wave_config(1, 2, GOBLIN_DATA),
		_create_wave_config(2, 1, GOBLIN_DATA)
	]

	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	wave_manager._process(wave_manager.spawn_interval)
	var summary: Dictionary = wave_manager.get_active_wave_summaries()[0]
	assert_int(summary["spawned_enemies"]).is_equal(2)
	assert_int(summary["total_enemies"]).is_equal(2)
	assert_int(wave_manager.get_active_enemy_count_for_wave(1)).is_equal(2)

	for enemy_node in game.get_node("Enemies").get_children():
		(enemy_node as Enemy)._mark_inactive()

	assert_int(wave_manager.get_active_enemy_count_for_wave(1)).is_equal(0)
	assert_bool(wave_manager.completed_wave_numbers.has(1)).is_true()
	assert_int(wave_manager.get_active_wave_summaries().size()).is_equal(0)


func test_run_gold_changes_do_not_change_the_persistent_profile() -> void:
	var profile_before: Dictionary = CrystalInventory.get_profile_data()
	GoldManager.start_new_run()
	GoldManager.add_gold(73)
	GoldManager.end_run()

	assert_int(GoldManager.run_gold).is_equal(0)
	assert_bool(CrystalInventory.get_profile_data() == profile_before).is_true()


func test_main_menu_and_game_scenes_instantiate_and_run_overlay_can_continue() -> void:
	var menu := MAIN_MENU_SCENE.instantiate()
	_track_node(menu)
	assert_bool(menu is Control).is_true()
	var inventory := INVENTORY_SCENE.instantiate()
	_track_node(inventory)
	assert_bool(inventory is Control).is_true()

	var game = _make_game()
	game._show_end_run_confirmation()
	assert_bool(game.end_run_overlay.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	game._continue_run()
	assert_bool(game.end_run_overlay.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func _make_enemy(data: EnemyData, hp: int = -1) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	var initial_hp := data.base_hp if hp < 0 else hp
	enemy.initialize_for_wave(
		data,
		initial_hp,
		data.base_speed,
		1,
		1.0
	)
	_track_node(enemy)
	return enemy


func _make_tower() -> Tower:
	var tower := TOWER_SCENE.instantiate() as Tower
	_track_node(tower)
	return tower


func _make_game():
	var game = GAME_SCENE.instantiate()
	_track_node(game)
	game.wave_manager.set_auto_waves_enabled(false)
	return game


func _track_node(node: Node) -> void:
	add_child(node)
	_created_nodes.append(node)


func _create_wave_config(
	wave_number: int,
	quantity: int,
	data: EnemyData
) -> WaveConfig:
	var config := WaveConfig.new()
	config.wave_number = wave_number
	var group := WaveEnemyGroup.new()
	group.enemy_data = data
	group.quantity = quantity
	config.groups.append(group)
	return config


func _find_wave_summary(summaries: Array[Dictionary], wave_number: int) -> Dictionary:
	for summary in summaries:
		if int(summary["wave_number"]) == wave_number:
			return summary
	return {}


func _await_scene_change() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
