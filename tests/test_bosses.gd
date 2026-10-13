extends GdUnitTestSuite

const BOSS_SCENE: PackedScene = preload("res://enemies/BossEnemy.tscn")
const GAME_SCENE: PackedScene = preload("res://game/Game.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemies/Enemy.tscn")
const TOWER_SCENE: PackedScene = preload("res://towers/Tower.tscn")
const GOBLIN_DATA: EnemyData = preload("res://enemies/Goblin.tres")
const KOBOLD_DATA: EnemyData = preload("res://enemies/Kobold.tres")
const SKELETON_DATA: EnemyData = preload("res://enemies/Skeleton.tres")
const ORC_CHIEF: BossData = preload("res://enemies/bosses/OrcChief.tres")
const SKELETON_BOSS: BossData = preload("res://enemies/bosses/SkeletonBoss.tres")
const GHOUL: BossData = preload("res://enemies/bosses/Ghoul.tres")
const SNAKE: BossData = preload("res://enemies/bosses/Snake.tres")
const GOBLIN_CHIEF: BossData = preload("res://enemies/bosses/GoblinChief.tres")
const KOBOLD_CHIEF: BossData = preload("res://enemies/bosses/KoboldChief.tres")
const TROLL: BossData = preload("res://enemies/bosses/TrollBoss.tres")
const SPIDER_MATRON: BossData = preload("res://enemies/bosses/SpiderMatron.tres")
const BOSS_SCHEDULE = preload("res://waves/BossWaveSchedule.gd")
const WAVE_GENERATOR_SCRIPT = preload("res://waves/WaveGenerator.gd")

var _created_nodes: Array[Node] = []
var _original_profile_directory: String
var _test_profile_directory: String
var _original_test_wave_flag: bool
var _original_boss_debug_flag: bool


func before_test() -> void:
	_original_test_wave_flag = BossWaveSchedule.tier_one_test_waves_enabled
	BossWaveSchedule.tier_one_test_waves_enabled = true
	_original_boss_debug_flag = BossAbilityDebug.enabled
	BossAbilityDebug.enabled = true
	_original_profile_directory = CrystalInventory.profile_storage_directory
	_test_profile_directory = "user://gdunit-boss-tests/%d-%d" % [
		Time.get_ticks_usec(),
		randi()
	]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_test_profile_directory)
	)
	CrystalInventory.profile_storage_directory = _test_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	GoldManager.start_new_run()


func after_test() -> void:
	BossWaveSchedule.tier_one_test_waves_enabled = _original_test_wave_flag
	BossAbilityDebug.enabled = _original_boss_debug_flag
	GameSpeedManager.set_paused(false)
	GameSpeedManager.set_simulation_speed(1.0)
	for node in _created_nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.free()
	_created_nodes.clear()
	GoldManager.end_run()
	CrystalInventory.profile_storage_directory = _original_profile_directory
	CrystalInventory.load_profile()
	_remove_test_profile()


func test_tier_one_boss_data_and_wave_scaling() -> void:
	var pool: Array[BossData] = BOSS_SCHEDULE.get_boss_pool(1)
	assert_int(pool.size()).is_equal(8)
	var expected := {
		"goblin_chief": [1200, 90.0, 0.12, 0.003, 2, 100, 20],
		"kobold_chief": [700, 155.0, 0.09, 0.008, 2, 90, 18],
		"orc_chief": [2500, 55.0, 0.14, 0.002, 2, 180, 30],
		"troll_boss": [4000, 30.0, 0.15, 0.0, 1, 250, 40],
		"skeleton_boss": [1500, 80.0, 0.11, 0.003, 2, 140, 25],
		"ghoul": [1800, 75.0, 0.12, 0.003, 1, 160, 28],
		"spider_matron": [1400, 70.0, 0.1, 0.004, 2, 150, 27],
		"snake": [1600, 100.0, 0.1, 0.006, 2, 160, 28]
	}
	for data in pool:
		var values: Array = expected[String(data.boss_id)]
		assert_int(data.base_hp).is_equal(values[0])
		assert_float(data.base_speed).is_equal(values[1])
		assert_float(data.hp_growth_per_wave).is_equal(values[2])
		assert_float(data.speed_growth_per_wave).is_equal(values[3])
		assert_int(data.trophy_capacity).is_equal(values[4])
		assert_int(data.base_gold_reward).is_equal(values[5])
		assert_int(data.base_essence_reward).is_equal(values[6])

		var boss := _make_boss(data, 10)
		assert_int(boss.max_hp).is_equal(
			roundi(data.base_hp * pow(1.0 + data.hp_growth_per_wave, 9))
		)
		assert_float(boss.speed).is_equal_approx(
			data.base_speed * (1.0 + data.speed_growth_per_wave * 9.0),
			0.0001
		)


func test_tier_one_wave_composition_matches_selected_boss_and_budget() -> void:
	var generator := WAVE_GENERATOR_SCRIPT.new() as WaveGenerator
	var manager := WaveManager.new()
	manager._wave_generator = generator
	for boss_data in BOSS_SCHEDULE.get_boss_pool(1):
		var regular_enemy_data: EnemyData = (
			BOSS_SCHEDULE.get_regular_enemy_data(boss_data)
		)
		var config: WaveConfig = manager._create_tier_one_boss_wave_config(
			10,
			boss_data,
			&"BOSS_TEST"
		)
		if regular_enemy_data == null:
			assert_int(config.groups.size()).is_equal(0)
			continue

		assert_int(config.groups.size()).is_equal(1)
		assert_object(config.groups[0].enemy_data).is_same(regular_enemy_data)
		assert_int(config.groups[0].quantity).is_equal(
			floori(
				float(generator.get_difficulty_budget(10))
				/ float(regular_enemy_data.difficulty_cost)
			)
		)
		assert_str(config.archetype_id).is_equal("BOSS_TEST")
	manager.free()
	generator.free()


func test_temporary_test_wave_sequence_uses_exact_bosses_and_matching_composition() -> void:
	var expected_bosses: Array[BossData] = [
		GOBLIN_CHIEF,
		ORC_CHIEF,
		KOBOLD_CHIEF,
		TROLL,
		SKELETON_BOSS,
		GHOUL,
		SPIDER_MATRON,
		SNAKE
	]
	var expected_enemies: Array[EnemyData] = [
		GOBLIN_DATA,
		preload("res://enemies/Orc.tres"),
		KOBOLD_DATA,
		preload("res://enemies/Troll.tres"),
		SKELETON_DATA,
		SKELETON_DATA,
		null,
		null
	]
	var generator := WAVE_GENERATOR_SCRIPT.new() as WaveGenerator
	var manager := WaveManager.new()
	manager._wave_generator = generator

	for index in range(expected_bosses.size()):
		var wave_number := index + 1
		var boss_data := BOSS_SCHEDULE.get_test_wave_boss(wave_number)
		assert_object(boss_data).is_same(expected_bosses[index])
		var config := manager._create_tier_one_boss_wave_config(
			wave_number,
			boss_data,
			&"BOSS_TEST"
		)
		var expected_enemy := expected_enemies[index]
		if expected_enemy == null:
			assert_int(config.groups.size()).is_equal(0)
		else:
			assert_int(config.groups.size()).is_equal(1)
			assert_object(config.groups[0].enemy_data).is_same(expected_enemy)
			assert_int(config.groups[0].quantity).is_equal(
				floori(
					float(generator.get_difficulty_budget(wave_number))
					/ float(expected_enemy.difficulty_cost)
				)
			)
		assert_str(config.archetype_id).is_equal("BOSS_TEST")

	BossWaveSchedule.tier_one_test_waves_enabled = false
	assert_object(BOSS_SCHEDULE.get_test_wave_boss(1)).is_null()
	assert_int(BOSS_SCHEDULE.get_requirements(10).get("tier", 0)).is_equal(1)
	assert_int(BOSS_SCHEDULE.get_boss_pool(1).size()).is_equal(8)
	manager.free()
	generator.free()


func test_wave_manager_uses_test_boss_before_random_selection() -> void:
	var game := GAME_SCENE.instantiate()
	add_child(game)
	_created_nodes.append(game)
	var manager := game.get_node("WaveManager") as WaveManager
	manager.start_wave(WaveManager.StartReason.MANUAL)

	var wave: ActiveWave = manager.waves_by_number[1]
	assert_int(wave.boss_definitions.size()).is_equal(1)
	assert_object(wave.boss_definitions[0]).is_same(GOBLIN_CHIEF)
	assert_int(wave.config.groups.size()).is_equal(1)
	assert_object(wave.config.groups[0].enemy_data).is_same(GOBLIN_DATA)
	assert_int(manager._boss_selection_pools.size()).is_equal(0)


func test_boss_ability_debug_logging_can_be_disabled_centrally() -> void:
	var boss := _make_boss(GOBLIN_CHIEF, 1)
	assert_bool(BossAbilityDebug.enabled).is_true()
	BossAbilityDebug.enabled = false
	assert_bool(
		BossAbilityDebug.log(boss, "test", "should_not_emit")
	).is_false()
	BossAbilityDebug.enabled = true
	assert_bool(
		BossAbilityDebug.log(boss, "test", "emitted", "target=unit")
	).is_true()


func test_wave_does_not_complete_when_boss_reaches_castle_while_still_alive() -> void:
	var boss := _make_boss(GOBLIN_CHIEF, 1)
	var manager := WaveManager.new()
	_created_nodes.append(manager)
	var wave := ActiveWave.new()
	wave.wave_number = 1
	wave.total_enemies = 1
	wave.spawned_enemies = 1
	wave.state = ActiveWave.State.WAITING_FOR_ENEMIES
	manager._register_wave_enemy(wave, boss)

	boss._mark_inactive()
	assert_int(wave.active_enemies.size()).is_equal(1)
	assert_int(wave.state).is_equal(ActiveWave.State.WAITING_FOR_ENEMIES)

	boss.die()
	await get_tree().process_frame
	assert_int(wave.active_enemies.size()).is_equal(0)
	assert_int(wave.state).is_equal(ActiveWave.State.COMPLETED)


func test_orc_reduction_is_replaced_after_trophy_loss_and_rewards_once() -> void:
	var boss := _make_boss(ORC_CHIEF, 10)
	var orc := ENEMY_SCENE.instantiate() as Enemy
	orc.initialize_for_wave(ORC_CHIEF.visual_source, 300, 60.0, 10, 1.0)
	orc.global_position = boss.global_position
	add_child(orc)
	_created_nodes.append(orc)
	boss._process(0.01)
	boss._process(0.01)
	orc.take_damage(100)
	assert_int(orc.hp).is_equal(215)

	var essence_before := CrystalInventory.get_essence_balance()
	var starting_gold := GoldManager.run_gold
	boss.take_damage(100)
	assert_int(boss.hp).is_equal(boss.max_hp - 75)

	var trophy := Trophy.new()
	boss._on_trophy_permanently_lost(trophy)
	boss._on_trophy_permanently_lost(trophy)
	boss.take_damage(100)
	assert_int(boss.hp).is_equal(boss.max_hp - 75 - 90)

	boss.die()
	boss.die()
	assert_int(GoldManager.run_gold).is_equal(starting_gold + 180)
	assert_int(CrystalInventory.get_essence_balance()).is_equal(
		essence_before + 30
	)
	trophy.free()


func test_goblin_summoning_runs_from_boss_process_and_stops_when_paused() -> void:
	var boss := _make_boss(GOBLIN_CHIEF, 10)
	var requested_quantities: Array[int] = []
	boss.summons_requested.connect(
		func(_data: EnemyData, quantity: int, _source: BossEnemy) -> void:
			requested_quantities.append(quantity)
	)
	boss._summon_timer = 0.001
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(boss._summon_sequence_active).is_true()
	boss._update_summon_sequence(1.0)
	assert_int(requested_quantities.size()).is_equal(3)
	assert_int(requested_quantities[0]).is_equal(1)
	boss._reset_summon_sequence()

	boss._summon_timer = 30.0
	GameSpeedManager.set_simulation_speed(1.0)
	await get_tree().create_timer(0.12, true, false, true).timeout
	var normal_speed_delta := 30.0 - boss._summon_timer
	boss._summon_timer = 30.0
	GameSpeedManager.set_simulation_speed(3.0)
	await get_tree().create_timer(0.12, true, false, true).timeout
	var triple_speed_delta := 30.0 - boss._summon_timer
	assert_float(triple_speed_delta).is_greater(normal_speed_delta * 1.5)

	var remaining_cooldown := boss._summon_timer
	GameSpeedManager.set_paused(true)
	await get_tree().create_timer(0.05, true, false, true).timeout
	assert_float(boss._summon_timer).is_equal_approx(remaining_cooldown, 0.0001)
	GameSpeedManager.set_paused(false)
	GameSpeedManager.set_simulation_speed(1.0)


func test_wave_manager_spawns_selected_boss_composition_and_tracks_summons() -> void:
	var game := GAME_SCENE.instantiate()
	add_child(game)
	_created_nodes.append(game)
	var manager := game.get_node("WaveManager") as WaveManager
	manager.set_run_seed(12345)
	manager.next_wave_number = 10
	manager._boss_selection_pools[1] = [GOBLIN_CHIEF]
	manager.start_wave(WaveManager.StartReason.MANUAL)

	var wave: ActiveWave = manager.waves_by_number[10]
	assert_int(wave.boss_definitions.size()).is_equal(1)
	assert_object(wave.boss_definitions[0]).is_same(GOBLIN_CHIEF)
	assert_int(wave.config.groups.size()).is_equal(1)
	assert_object(wave.config.groups[0].enemy_data).is_same(GOBLIN_DATA)
	for group in wave.config.groups:
		assert_object(group.enemy_data).is_same(GOBLIN_DATA)

	var boss: BossEnemy
	for enemy in game.get_node("Enemies").get_children():
		if enemy is BossEnemy:
			boss = enemy
			break
	assert_object(boss).is_not_null()
	var enemies_before_summon := wave.active_enemies.size()
	boss._summon_timer = 0.001
	await get_tree().process_frame
	await get_tree().process_frame
	boss._update_summon_sequence(1.0)
	assert_int(wave.active_enemies.size()).is_equal(enemies_before_summon + 3)
	assert_int(boss._get_living_summon_count()).is_equal(3)


func test_ghoul_spawns_and_tracks_two_skeleton_escorts_in_its_wave() -> void:
	var game := GAME_SCENE.instantiate()
	add_child(game)
	_created_nodes.append(game)
	var manager := game.get_node("WaveManager") as WaveManager
	manager.next_wave_number = 10
	manager._boss_selection_pools[1] = [GHOUL]
	manager.start_wave(WaveManager.StartReason.MANUAL)

	var wave: ActiveWave = manager.waves_by_number[10]
	var boss: BossEnemy
	for enemy in game.get_node("Enemies").get_children():
		if enemy is BossEnemy:
			boss = enemy
			break
	assert_object(boss).is_not_null()
	assert_int(boss._get_living_summon_count()).is_equal(2)
	assert_int(wave.active_enemies.size()).is_equal(4)
	for enemy in boss._summoned_enemies.values():
		assert_object(enemy.enemy_data).is_same(SKELETON_DATA)


func test_skeleton_resurrects_on_three_lethal_hits_before_final_rewards() -> void:
	var boss := _make_boss(SKELETON_BOSS, 1)
	var essence_before := CrystalInventory.get_essence_balance()
	var starting_gold := GoldManager.run_gold
	boss.take_damage(boss.max_hp + 1)
	assert_bool(boss.is_dead).is_false()
	assert_int(boss.hp).is_equal(roundi(boss.max_hp * 0.75))
	assert_int(boss.resurrection_count).is_equal(1)
	assert_int(GoldManager.run_gold).is_equal(starting_gold)
	assert_int(CrystalInventory.get_essence_balance()).is_equal(essence_before)

	boss.take_damage(boss.hp + 1)
	assert_int(boss.hp).is_equal(roundi(boss.max_hp * 0.5))
	assert_int(boss.resurrection_count).is_equal(2)
	boss.take_damage(boss.hp + 1)
	assert_int(boss.hp).is_equal(roundi(boss.max_hp * 0.25))
	assert_int(boss.resurrection_count).is_equal(3)

	boss.take_damage(5000)
	assert_bool(boss.is_dead).is_true()
	assert_int(GoldManager.run_gold).is_equal(starting_gold + 140)
	assert_int(CrystalInventory.get_essence_balance()).is_equal(
		essence_before + 25
	)


func test_goblin_command_zone_is_directional_and_reversible() -> void:
	var boss := _make_boss(GOBLIN_CHIEF, 10)
	boss.path_distance = 150.0
	var goblin := ENEMY_SCENE.instantiate() as Enemy
	goblin.initialize_for_wave(GOBLIN_DATA, 100, 100.0, 10, 1.0)
	goblin.path_distance = 100.0
	goblin.position = Vector2(20.0, 0.0)
	add_child(goblin)
	_created_nodes.append(goblin)

	boss._process(0.01)
	assert_float(goblin.effective_speed).is_equal_approx(115.0, 0.0001)
	boss._process(0.01)
	assert_float(goblin.effective_speed).is_equal_approx(115.0, 0.0001)
	goblin.path_distance = 200.0
	boss._process(0.01)
	assert_float(goblin.effective_speed).is_equal_approx(100.0, 0.0001)


func test_goblin_dropped_trophy_stays_available_and_boss_skips_trophies_to_castle() -> void:
	var boss := _make_boss(GOBLIN_CHIEF, 1)
	var trophy := Trophy.new()
	boss.add_child(trophy)
	boss.carried_trophies.append(trophy)
	boss.movement_direction = Enemy.MovementDirection.RETURNING_TO_CAMP
	boss.hp = roundi(boss.max_hp * 0.5)

	boss._update_first_return_trophy_drop()
	_created_nodes.append(trophy)
	assert_int(trophy.state).is_equal(Trophy.State.DROPPED)
	assert_bool(boss._try_pick_up_dropped_trophy()).is_false()

	var other_trophy := Trophy.new()
	add_child(other_trophy)
	_created_nodes.append(other_trophy)
	other_trophy.set_state(Trophy.State.DROPPED)
	other_trophy.global_position = boss.global_position
	boss.movement_direction = Enemy.MovementDirection.MOVING_TO_CASTLE
	assert_bool(boss._try_pick_up_dropped_trophy()).is_false()


func test_kobold_speed_boost_expires_and_enrage_is_applied_once() -> void:
	var boss := _make_boss(KOBOLD_CHIEF, 1)
	var kobold := ENEMY_SCENE.instantiate() as Enemy
	kobold.initialize_for_wave(KOBOLD_DATA, 100, 100.0, 1, 1.0)
	add_child(kobold)
	_created_nodes.append(kobold)
	kobold.global_position = boss.global_position

	boss._escort_boost_remaining = 1.0
	boss._process(0.01)
	assert_float(kobold.effective_speed).is_equal_approx(150.0, 0.0001)
	boss._process(0.01)
	assert_float(kobold.effective_speed).is_equal_approx(150.0, 0.0001)
	boss._escort_boost_remaining = 0.0
	boss._process(0.01)
	assert_float(kobold.effective_speed).is_equal_approx(120.0, 0.0001)

	var trophy := Trophy.new()
	boss._on_trophy_permanently_lost(trophy)
	boss._on_trophy_permanently_lost(trophy)
	assert_float(boss.speed).is_equal_approx(
		KOBOLD_CHIEF.base_speed * KOBOLD_CHIEF.enrage_multiplier,
		0.0001
	)
	trophy.free()


func test_troll_regenerates_from_scaled_maximum_health() -> void:
	var boss := _make_boss(TROLL, 10)
	boss.hp = floori(boss.max_hp * 0.5)
	boss._process(1.0)
	assert_int(boss.hp).is_equal(
		floori(boss.max_hp * 0.5) + floori(boss.max_hp * 0.03)
	)

	boss.hp = floori(boss.max_hp * 0.29)
	boss._regeneration_remainder = 0.0
	boss._process(1.0)
	assert_int(boss.hp).is_equal(
		floori(boss.max_hp * 0.29) + floori(boss.max_hp * 0.05)
	)


func test_spider_matron_summons_only_to_its_living_limit() -> void:
	var boss := _make_boss(SPIDER_MATRON, 1)
	var requested_quantities: Array[int] = []
	boss.summons_requested.connect(
		func(_data: EnemyData, quantity: int, _source: BossEnemy) -> void:
			requested_quantities.append(quantity)
	)
	var summons: Array[Enemy] = []
	for _index in range(5):
		var summon := ENEMY_SCENE.instantiate() as Enemy
		summon.initialize_for_wave(GOBLIN_DATA, 10, 100.0, 1, 1.0, false)
		add_child(summon)
		_created_nodes.append(summon)
		summons.append(summon)
	boss.track_summoned_enemies(summons)

	boss._process(10.0)
	assert_int(requested_quantities.size()).is_equal(1)
	assert_int(requested_quantities[0]).is_equal(1)

	var final_summon := ENEMY_SCENE.instantiate() as Enemy
	final_summon.initialize_for_wave(GOBLIN_DATA, 10, 100.0, 1, 1.0, false)
	add_child(final_summon)
	_created_nodes.append(final_summon)
	boss.track_summoned_enemies([final_summon])
	boss._process(10.0)
	assert_int(requested_quantities.size()).is_equal(1)

	var trophy := Trophy.new()
	boss._on_trophy_permanently_lost(trophy)
	assert_float(boss._get_current_summon_interval()).is_equal(7.0)
	trophy.free()


func test_ghoul_heals_once_for_each_escort_death_or_resurrection_signal() -> void:
	var boss := _make_boss(GHOUL, 1)
	boss.hp = 500
	var escort := ENEMY_SCENE.instantiate() as Enemy
	escort.initialize_for_wave(SKELETON_DATA, 150, 85.0, 1, 1.0)
	add_child(escort)
	_created_nodes.append(escort)
	boss.track_summoned_enemies([escort])

	escort.resurrected.emit()
	await get_tree().process_frame
	assert_int(boss.hp).is_equal(644)
	escort.final_death.emit()
	await get_tree().process_frame
	assert_int(boss.hp).is_equal(788)
	escort.resurrected.emit()
	escort.resurrected.emit()
	await get_tree().process_frame
	assert_int(boss._healing_activations).is_equal(3)

	boss.track_summoned_enemies([escort])
	escort.resurrected.emit()
	await get_tree().process_frame
	assert_int(boss._healing_activations).is_equal(3)
	var escort_id := escort.get_instance_id()
	escort.free()
	await get_tree().process_frame
	assert_bool(boss._escort_connections.has(escort_id)).is_false()


func test_snake_tower_aura_leaves_a_timed_attack_speed_debuff() -> void:
	var boss := _make_boss(SNAKE, 1)
	var tower := TOWER_SCENE.instantiate() as Tower
	add_child(tower)
	_created_nodes.append(tower)
	tower.global_position = boss.global_position
	var initial_speed := tower.attack_speed
	var extended_range_tower := TOWER_SCENE.instantiate() as Tower
	add_child(extended_range_tower)
	_created_nodes.append(extended_range_tower)
	extended_range_tower.global_position = boss.global_position + Vector2(225.0, 0.0)
	var extended_range_initial_speed := extended_range_tower.attack_speed

	boss._process(0.01)
	assert_float(tower.attack_speed).is_equal_approx(initial_speed * 0.5, 0.0001)
	boss._process(0.01)
	assert_float(tower.attack_speed).is_equal_approx(initial_speed * 0.5, 0.0001)
	assert_float(extended_range_tower.attack_speed).is_equal_approx(
		extended_range_initial_speed,
		0.0001
	)
	var trophy := Trophy.new()
	boss._on_trophy_permanently_lost(trophy)
	assert_float(tower.attack_speed).is_equal_approx(initial_speed * 0.65, 0.0001)
	assert_float(extended_range_tower.attack_speed).is_equal_approx(
		extended_range_initial_speed * 0.65,
		0.0001
	)
	tower.global_position = Vector2(1000.0, 1000.0)
	boss._process(0.01)
	assert_float(tower.attack_speed).is_equal_approx(initial_speed * 0.65, 0.0001)
	boss.die()
	tower._process(SNAKE.tower_debuff_duration + 0.1)
	extended_range_tower._process(SNAKE.tower_debuff_duration + 0.1)
	assert_float(tower.attack_speed).is_equal_approx(initial_speed, 0.0001)
	assert_float(extended_range_tower.attack_speed).is_equal_approx(
		extended_range_initial_speed,
		0.0001
	)
	trophy.free()


func test_snake_poison_immunity_uses_shared_status_api() -> void:
	var snake := _make_boss(SNAKE, 1)
	var skeleton := ENEMY_SCENE.instantiate() as Enemy
	skeleton.initialize_for_wave(SKELETON_DATA, 150, 85.0, 1, 1.0)
	add_child(skeleton)
	_created_nodes.append(skeleton)
	var snake_hp := snake.hp
	var skeleton_hp := skeleton.hp

	snake.apply_poison(0.1, 1.0)
	skeleton.apply_poison(0.1, 1.0)
	snake._process_damage_over_time(&"poison", 1.0)
	skeleton._process_damage_over_time(&"poison", 1.0)

	assert_int(snake.hp).is_equal(snake_hp)
	assert_int(skeleton.hp).is_equal(skeleton_hp - 15)


func test_kobold_enrage_occurs_on_permanent_loss_not_pickup() -> void:
	var boss := _make_boss(KOBOLD_CHIEF, 1)
	var starting_speed := boss.speed
	var trophy := Trophy.new()
	boss._attach_trophy(trophy)
	assert_float(boss.speed).is_equal_approx(starting_speed, 0.0001)
	boss._on_trophy_permanently_lost(trophy)
	assert_float(boss.speed).is_equal_approx(
		starting_speed * KOBOLD_CHIEF.enrage_multiplier,
		0.0001
	)
	boss._on_trophy_permanently_lost(trophy)
	assert_float(boss.speed).is_equal_approx(
		starting_speed * KOBOLD_CHIEF.enrage_multiplier,
		0.0001
	)


func _make_boss(data: BossData, wave_number: int) -> BossEnemy:
	var boss := BOSS_SCENE.instantiate() as BossEnemy
	boss.initialize_for_boss(data, wave_number, 1.0)
	add_child(boss)
	_created_nodes.append(boss)
	return boss


func _remove_test_profile() -> void:
	for file_name in [
		"player_profile.json",
		"player_profile.tmp",
		"player_profile.bak",
		"player_profile.bak.tmp"
	]:
		var file_path := _test_profile_directory.path_join(file_name)
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_profile_directory))
	_test_profile_directory = ""
