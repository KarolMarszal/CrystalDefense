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


func before_test() -> void:
	_original_gold = GoldManager.run_gold
	GoldManager.end_run()


func after_test() -> void:
	get_tree().paused = false
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
