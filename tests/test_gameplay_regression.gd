extends GdUnitTestSuite

const ENEMY_SCENE: PackedScene = preload("res://enemies/Enemy.tscn")
const GAME_SCENE: PackedScene = preload("res://game/Game.tscn")
const MAIN_MENU_SCENE: PackedScene = preload("res://ui/main_menu/MainMenu.tscn")
const SKILL_TREE_SCENE: PackedScene = preload("res://ui/SkillTreeScreen.tscn")
const SKILL_TREE_CATALOG = preload("res://managers/skill_tree_catalog.gd")
const INVENTORY_SCENE: PackedScene = preload(
	"res://ui/main_menu/CrystalInventory.tscn"
)
const TOWER_SCENE: PackedScene = preload("res://towers/Tower.tscn")
const TROPHY_SCENE: PackedScene = preload("res://game/Trophy.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://projectiles/Projectile.tscn")
const GOBLIN_DATA: EnemyData = preload("res://enemies/Goblin.tres")
const SKELETON_DATA: EnemyData = preload("res://enemies/Skeleton.tres")
const TROLL_DATA: EnemyData = preload("res://enemies/Troll.tres")
const SLOW_CRYSTAL: CrystalData = preload("res://crystals/SlowCrystal.tres")
const KINETIC_CRYSTAL: CrystalData = preload(
	"res://crystals/KineticCrystal.tres"
)
const RAPID_FIRE_CRYSTAL: CrystalData = preload(
	"res://crystals/RapidFireCrystal.tres"
)
const BLEED_CRYSTAL: CrystalData = preload("res://crystals/BleedCrystal.tres")
const SNIPER_CRYSTAL: CrystalData = preload("res://crystals/SniperCrystal.tres")
const FIRE_CRYSTAL: CrystalData = preload("res://crystals/FireCrystal.tres")
const STANDARD_ARCHETYPE: WaveArchetype = preload(
	"res://wave_archetypes/Standard.tres"
)

var _original_gold: int
var _created_nodes: Array[Node] = []
var _original_current_scene: Node
var _original_profile_directory: String
var _temporary_profile_directory: String
var _original_test_wave_flag: bool


func before_test() -> void:
	_original_test_wave_flag = BossWaveSchedule.tier_one_test_waves_enabled
	BossWaveSchedule.tier_one_test_waves_enabled = false
	_original_gold = GoldManager.run_gold
	_original_current_scene = get_tree().current_scene
	_original_profile_directory = CrystalInventory.profile_storage_directory
	GoldManager.end_run()
	CrystalInventory.end_run_inventory()


func after_test() -> void:
	BossWaveSchedule.tier_one_test_waves_enabled = _original_test_wave_flag
	GameSpeedManager.set_paused(false)
	GameSpeedManager.set_simulation_speed(1.0)
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
	CrystalInventory.end_run_inventory()
	if CrystalInventory.profile_storage_directory != _original_profile_directory:
		CrystalInventory.profile_storage_directory = _original_profile_directory
		CrystalInventory.load_profile()
	_remove_temporary_profile()
	if _original_gold > 0:
		GoldManager.add_gold(_original_gold)


func test_run_gold_starts_and_ends_at_the_existing_run_values() -> void:
	GoldManager.start_new_run()
	assert_int(GoldManager.run_gold).is_equal(300)
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


func test_enemy_types_award_their_configured_kill_gold() -> void:
	GoldManager.start_new_run()
	var enemy_data: Array[EnemyData] = [
		GOBLIN_DATA,
		preload("res://enemies/Kobold.tres"),
		SKELETON_DATA,
		preload("res://enemies/Orc.tres"),
		TROLL_DATA
	]
	var expected_total := 0
	for data in enemy_data:
		var deterministic_data := data.duplicate(true) as EnemyData
		deterministic_data.can_resurrect = false
		var enemy := _make_enemy(deterministic_data)
		expected_total += deterministic_data.gold_reward
		enemy.die()
	var discounted_enemy := ENEMY_SCENE.instantiate() as Enemy
	discounted_enemy.initialize_for_wave(
		GOBLIN_DATA,
		GOBLIN_DATA.base_hp,
		GOBLIN_DATA.base_speed,
		1,
		0.59
	)
	_track_node(discounted_enemy)
	discounted_enemy.die()
	expected_total += 5
	assert_int(GoldManager.run_gold).is_equal(
		GoldManager.STARTING_RUN_GOLD + expected_total
	)


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


func test_tower_enhancements_skill_unlocks_existing_upgrade_controls_and_persists() -> void:
	var original_profile_directory := CrystalInventory.profile_storage_directory
	var test_profile_directory := "user://gdunit-tower-skill-tests/%d-%d" % [
		Time.get_ticks_usec(),
		randi()
	]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(test_profile_directory)
	)
	CrystalInventory.profile_storage_directory = test_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	assert_bool(CrystalInventory.add_essence(3)).is_true()

	var game = GAME_SCENE.instantiate()
	_track_node(game)
	var tower := _add_test_tower(game, Vector2(405.0, 365.0))
	game._select_tower(tower)
	var panel := game.get_node("HUD/TowerPanel") as PanelContainer
	var upgrade_button := panel.get_node(
		"MarginContainer/VBoxContainer/DamageRow/DamageUpgradeButton"
	) as Button
	assert_bool(upgrade_button.disabled).is_true()
	assert_bool(tower.can_upgrade(Tower.UpgradeTrack.UPGRADE_1)).is_false()
	assert_float(tower.base_damage).is_equal(5.0)
	assert_float(tower.base_attack_speed).is_equal(0.5)
	assert_float(tower.base_attack_range).is_equal(140.0)
	assert_int(tower.get_upgrade_cost(Tower.UpgradeTrack.UPGRADE_1)).is_equal(30)
	assert_int(tower.damage).is_equal(5)
	assert_bool(tower.upgrade_tower_track(Tower.UpgradeTrack.UPGRADE_1)).is_false()

	if not CrystalInventory.is_skill_purchased(&"A"):
		assert_bool(CrystalInventory.purchase_skill_node(&"A")).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"B")).is_true()
	panel.show_tower(tower)
	assert_bool(upgrade_button.disabled).is_false()
	assert_str(upgrade_button.text).is_equal("Upgrade 30g")
	upgrade_button.pressed.emit()
	assert_int(tower.get_upgrade_level(Tower.UpgradeTrack.UPGRADE_1)).is_equal(1)
	assert_int(tower.damage).is_equal(6)
	assert_int(GoldManager.run_gold).is_equal(
		GoldManager.STARTING_RUN_GOLD - 30
	)
	assert_int(tower.get_upgrade_cost(Tower.UpgradeTrack.UPGRADE_1)).is_equal(44)

	assert_bool(CrystalInventory.load_profile()).is_true()
	assert_bool(CrystalInventory.is_skill_purchased(&"B")).is_true()
	assert_bool(tower.can_upgrade(Tower.UpgradeTrack.UPGRADE_1)).is_true()

	CrystalInventory.profile_storage_directory = original_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	for file_name in [
		"player_profile.json",
		"player_profile.tmp",
		"player_profile.bak",
		"player_profile.bak.tmp"
	]:
		var file_path := test_profile_directory.path_join(file_name)
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(test_profile_directory)
	)


func test_tower_skill_modifiers_preserve_upgrade_progression_and_apply_cost_floor() -> void:
	var original_profile_directory := CrystalInventory.profile_storage_directory
	var test_profile_directory := "user://gdunit-tower-modifier-tests/%d-%d" % [
		Time.get_ticks_usec(),
		randi()
	]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(test_profile_directory)
	)
	CrystalInventory.profile_storage_directory = test_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	assert_bool(CrystalInventory.add_essence(100)).is_true()
	for skill_id in ["A", "B", "K1", "K2", "K3"]:
		assert_bool(
			CrystalInventory.purchase_skill_node(StringName(skill_id))
		).is_true()

	var tower := _make_tower()
	var configuration := tower.current_attack_configuration
	assert_float(configuration.damage).is_equal_approx(5.5, 0.0001)
	assert_float(configuration.attack_speed).is_equal_approx(0.5, 0.0001)
	assert_float(configuration.attack_range).is_equal_approx(140.0, 0.0001)
	assert_int(tower.get_upgrade_cost(Tower.UpgradeTrack.UPGRADE_1)).is_equal(27)
	tower.tower_upgrade_levels[0] = 1
	assert_float(
		tower.current_attack_configuration.damage
	).is_equal_approx(6.71, 0.0001)
	assert_int(tower.get_upgrade_cost(Tower.UpgradeTrack.UPGRADE_1)).is_equal(39)

	for skill_id in ["L1", "L2", "L3", "M1", "M2", "M3", "N"]:
		assert_bool(
			CrystalInventory.purchase_skill_node(StringName(skill_id))
		).is_true()
	assert_float(
		tower.current_attack_configuration.attack_speed
	).is_equal_approx(0.55, 0.0001)
	assert_float(
		tower.current_attack_configuration.attack_range
	).is_equal_approx(154.0, 0.0001)
	tower.tower_upgrade_levels = [1, 1, 1]
	var upgraded_configuration := tower.current_attack_configuration
	assert_float(upgraded_configuration.damage).is_equal_approx(6.71, 0.0001)
	assert_float(upgraded_configuration.attack_speed).is_equal_approx(
		0.671,
		0.0001
	)
	assert_float(upgraded_configuration.attack_range).is_equal_approx(
		187.88,
		0.0001
	)
	assert_int(tower.get_upgrade_cost(Tower.UpgradeTrack.UPGRADE_1)).is_equal(36)

	CrystalInventory.profile_storage_directory = original_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	_remove_test_profile_directory(test_profile_directory)


func test_kinetic_crystal_upgrades_apply_to_purchase_and_combat_stats() -> void:
	var original_profile_directory := CrystalInventory.profile_storage_directory
	var test_profile_directory := "user://gdunit-kinetic-upgrade-tests/%d-%d" % [
		Time.get_ticks_usec(),
		randi()
	]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(test_profile_directory)
	)
	CrystalInventory.profile_storage_directory = test_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	assert_bool(CrystalInventory.add_essence(100)).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"A")).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"B")).is_true()

	var tower := _make_tower()
	assert_bool(tower.install_main_crystal(KINETIC_CRYSTAL)).is_true()
	GoldManager.start_new_run()
	var initial_configuration := tower.current_attack_configuration
	assert_float(initial_configuration.damage).is_equal_approx(22.0, 0.0001)
	assert_float(initial_configuration.attack_speed).is_equal_approx(
		1.0,
		0.0001
	)
	assert_float(initial_configuration.attack_range).is_equal_approx(
		180.0,
		0.0001
	)

	assert_bool(
		tower.upgrade_tower_track(Tower.UpgradeTrack.UPGRADE_1)
	).is_true()
	assert_bool(
		tower.upgrade_tower_track(Tower.UpgradeTrack.UPGRADE_2)
	).is_true()
	assert_bool(
		tower.upgrade_tower_track(Tower.UpgradeTrack.UPGRADE_3)
	).is_true()
	var upgraded_configuration := tower.current_attack_configuration
	assert_float(upgraded_configuration.damage).is_equal_approx(26.4, 0.0001)
	assert_float(upgraded_configuration.attack_speed).is_equal_approx(
		1.2,
		0.0001
	)
	assert_float(upgraded_configuration.attack_range).is_equal_approx(
		216.0,
		0.0001
	)
	assert_int(tower.get_upgrade_level(Tower.UpgradeTrack.UPGRADE_1)).is_equal(1)
	assert_int(tower.get_upgrade_level(Tower.UpgradeTrack.UPGRADE_2)).is_equal(1)
	assert_int(tower.get_upgrade_level(Tower.UpgradeTrack.UPGRADE_3)).is_equal(1)
	assert_int(GoldManager.run_gold).is_equal(195)

	assert_bool(
		tower.upgrade_tower_track(Tower.UpgradeTrack.UPGRADE_1)
	).is_true()
	assert_float(
		tower.current_attack_configuration.damage
	).is_equal_approx(31.68, 0.0001)
	assert_int(tower.get_upgrade_level(Tower.UpgradeTrack.UPGRADE_1)).is_equal(2)
	assert_int(GoldManager.run_gold).is_equal(151)
	assert_bool(
		tower.upgrade_tower_track(Tower.UpgradeTrack.UPGRADE_3)
	).is_true()
	assert_float(
		tower.current_attack_configuration.attack_range
	).is_equal_approx(259.2, 0.0001)

	CrystalInventory.profile_storage_directory = original_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	_remove_test_profile_directory(test_profile_directory)


func test_crystal_skill_tiers_have_the_current_configured_effect_values() -> void:
	var original_profile_directory := CrystalInventory.profile_storage_directory
	var test_profile_directory := "user://gdunit-crystal-tier-tests/%d-%d" % [
		Time.get_ticks_usec(),
		randi()
	]
	_temporary_profile_directory = test_profile_directory
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(test_profile_directory)
	)
	CrystalInventory.profile_storage_directory = test_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	assert_bool(CrystalInventory.add_essence(100)).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"A")).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"C")).is_true()
	var levels: Array[int] = [0, 0, 0]

	for tier in range(1, 4):
		assert_bool(
			CrystalInventory.purchase_skill_node(StringName("C%d" % tier))
		).is_true()
		var damage_bonus := (float(tier) * (tier + 1) / 2.0) * 0.1
		assert_float(
			RAPID_FIRE_CRYSTAL.create_attack_configuration(1, levels).damage
		).is_equal_approx(12.0 * (1.0 + damage_bonus), 0.0001)
		assert_float(
			SNIPER_CRYSTAL.create_attack_configuration(1, levels).damage
		).is_equal_approx(150.0 * (1.0 + damage_bonus), 0.0001)

	assert_bool(CrystalInventory.purchase_skill_node(&"F")).is_true()
	var slow_values: Array[float] = [0.25, 0.30, 0.35]
	for tier in range(1, 4):
		assert_bool(
			CrystalInventory.purchase_skill_node(StringName("F%d" % tier))
		).is_true()
		assert_float(
			CrystalInventory.get_crystal_definition(
				&"slow"
			).create_attack_configuration(1, levels).slow_fraction
		).is_equal_approx(slow_values[tier - 1], 0.0001)

	assert_bool(CrystalInventory.purchase_skill_node(&"G")).is_true()
	var bleed_values: Array[float] = [0.03, 0.04, 0.05]
	for tier in range(1, 4):
		assert_bool(
			CrystalInventory.purchase_skill_node(StringName("G%d" % tier))
		).is_true()
		assert_float(
			BLEED_CRYSTAL.create_attack_configuration(
				1,
				levels
			).bleed_max_hp_fraction_per_second
		).is_equal_approx(bleed_values[tier - 1], 0.0001)

	assert_bool(CrystalInventory.purchase_skill_node(&"H")).is_true()
	var convergence_slow := CrystalInventory.get_crystal_definition(
		&"slow"
	).create_attack_configuration(1, levels)
	var convergence_bleed := BLEED_CRYSTAL.create_attack_configuration(
		1,
		levels
	)
	assert_float(convergence_slow.slow_fraction).is_equal_approx(0.385, 0.0001)
	assert_float(
		convergence_bleed.bleed_max_hp_fraction_per_second
	).is_equal_approx(0.055, 0.0001)

	assert_bool(CrystalInventory.purchase_skill_node(&"D")).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"I")).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"J")).is_true()
	assert_float(
		FIRE_CRYSTAL.create_attack_configuration(1, levels).damage
	).is_equal_approx(15.84, 0.0001)

	CrystalInventory.profile_storage_directory = original_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	_remove_test_profile_directory(test_profile_directory)


func test_crystal_skill_modifiers_and_fire_area_hit_apply_once() -> void:
	var original_profile_directory := CrystalInventory.profile_storage_directory
	var test_profile_directory := "user://gdunit-crystal-effect-tests/%d-%d" % [
		Time.get_ticks_usec(),
		randi()
	]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(test_profile_directory)
	)
	CrystalInventory.profile_storage_directory = test_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	assert_bool(CrystalInventory.add_essence(100)).is_true()
	for skill_id in [
		"A", "C", "C1", "C2", "C3", "F", "F1", "F2", "F3",
		"G", "G1", "G2", "G3", "H", "D", "I", "J"
	]:
		assert_bool(
			CrystalInventory.purchase_skill_node(StringName(skill_id))
		).is_true()

	var tower := _make_tower()
	var upgrade_levels: Array[int] = [0, 0, 0]
	var rapid := CrystalInventory.get_crystal_definition(&"rapid_fire")
	var sniper := CrystalInventory.get_crystal_definition(&"sniper")
	var slow := CrystalInventory.get_crystal_definition(&"slow")
	var bleed := CrystalInventory.get_crystal_definition(&"bleed")
	var fire := CrystalInventory.get_crystal_definition(&"fire")
	assert_float(
		rapid.create_attack_configuration(1, upgrade_levels).damage
	).is_equal_approx(21.12, 0.0001)
	assert_float(
		sniper.create_attack_configuration(1, upgrade_levels).damage
	).is_equal_approx(264.0, 0.0001)
	assert_float(
		slow.create_attack_configuration(1, upgrade_levels).slow_fraction
	).is_equal_approx(0.385, 0.0001)
	assert_float(
		bleed.create_attack_configuration(
			1,
			upgrade_levels
		).bleed_max_hp_fraction_per_second
	).is_equal_approx(0.055, 0.0001)

	assert_bool(tower.install_main_crystal(fire)).is_true()
	var fire_configuration := tower.current_attack_configuration
	assert_float(fire_configuration.damage).is_equal_approx(15.84, 0.0001)
	assert_float(fire_configuration.area_damage_fraction).is_equal(0.5)
	assert_float(fire_configuration.area_damage_radius).is_equal(48.0)

	var primary := _make_enemy(GOBLIN_DATA, 100)
	var nearby := _make_enemy(GOBLIN_DATA, 100)
	var second_nearby := _make_enemy(GOBLIN_DATA, 100)
	primary.global_position = Vector2.ZERO
	nearby.global_position = Vector2(20.0, 0.0)
	second_nearby.global_position = Vector2(30.0, 0.0)
	var projectile = PROJECTILE_SCENE.instantiate()
	_track_node(projectile)
	projectile.target = primary
	projectile.damage = fire_configuration.damage
	projectile.area_damage_fraction = fire_configuration.area_damage_fraction
	projectile.area_damage_radius = fire_configuration.area_damage_radius
	projectile.hit_target()

	assert_int(primary.hp).is_equal(84)
	assert_int(nearby.hp).is_equal(92)
	assert_int(second_nearby.hp).is_equal(92)

	CrystalInventory.profile_storage_directory = original_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	_remove_test_profile_directory(test_profile_directory)


func test_sniper_base_stats_and_tower_panel_formatting() -> void:
	assert_float(SNIPER_CRYSTAL.damage).is_equal(150.0)
	assert_float(SNIPER_CRYSTAL.attack_speed).is_equal(0.33)
	assert_float(SNIPER_CRYSTAL.attack_range).is_equal(350.0)

	var game = _make_game()
	var tower := _add_test_tower(game, Vector2(405.0, 365.0))
	assert_bool(tower.install_main_crystal(SNIPER_CRYSTAL)).is_true()
	game._select_tower(tower)
	var panel := game.get_node("HUD/TowerPanel") as PanelContainer
	var stats_label := panel.get_node(
		"MarginContainer/VBoxContainer/CombatStatsLabel"
	) as Label
	assert_str(stats_label.text).is_equal(
		"Damage: 150.0  |  Attack Speed: 0.33/s  |  Range: 350"
	)
	assert_str(panel._format_damage(12.0)).is_equal("12.0")
	assert_str(panel._format_damage(250.0)).is_equal("250.0")
	assert_str(panel._format_damage(250.5)).is_equal("251")


func test_skill_a_reveals_inventories_and_persists_kinetic_and_rapid_fire() -> void:
	_temporary_profile_directory = "user://gdunit-awakening-inventory/%d-%d" % [
		Time.get_ticks_usec(),
		randi()
	]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_temporary_profile_directory)
	)
	CrystalInventory.profile_storage_directory = _temporary_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()

	var menu = MAIN_MENU_SCENE.instantiate()
	_track_node(menu)
	var menu_inventory_button := menu.get_node(
		"CenterPanel/MarginContainer/MenuContents/InventoryButton"
	) as Button
	var inventory = INVENTORY_SCENE.instantiate()
	_track_node(inventory)
	var game = GAME_SCENE.instantiate()
	_track_node(game)

	assert_bool(menu_inventory_button.visible).is_false()
	assert_bool(inventory.visible).is_false()
	assert_bool(game.crystals_button.visible).is_false()
	assert_bool(game.run_crystal_inventory_panel.visible).is_false()
	assert_int(CrystalInventory.get_owned_crystals().size()).is_equal(0)
	assert_int(CrystalInventory.get_available_crystals().size()).is_equal(0)

	assert_bool(CrystalInventory.add_essence(1)).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"A")).is_true()
	assert_bool(menu_inventory_button.visible).is_true()
	assert_bool(inventory.visible).is_true()
	assert_bool(game.crystals_button.visible).is_true()
	assert_int(CrystalInventory.get_owned_crystals().size()).is_equal(2)
	assert_bool(
		_contains_owned_crystal(
			CrystalInventory.get_owned_crystals(),
			"rapid_fire",
			1,
			1
		)
	).is_true()
	assert_bool(
		_contains_owned_crystal(
			CrystalInventory.get_owned_crystals(),
			"kinetic",
			1,
			1
		)
	).is_true()
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"rapid_fire", 1)
	).is_equal(1)
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"kinetic", 1)
	).is_equal(1)

	assert_bool(CrystalInventory.load_profile()).is_true()
	assert_int(CrystalInventory.get_owned_crystals().size()).is_equal(2)
	CrystalInventory.end_run_inventory()
	CrystalInventory.start_run_inventory()
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"rapid_fire", 1)
	).is_equal(1)
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"kinetic", 1)
	).is_equal(1)
	CrystalInventory.end_run_inventory()
	CrystalInventory.start_run_inventory()
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"rapid_fire", 1)
	).is_equal(1)
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"kinetic", 1)
	).is_equal(1)


func test_wave_controls_preview_and_early_send_bonus_follow_their_skill_unlocks() -> void:
	var original_profile_directory := CrystalInventory.profile_storage_directory
	var test_profile_directory := "user://gdunit-wave-preview-tests/%d-%d" % [
		Time.get_ticks_usec(),
		randi()
	]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(test_profile_directory)
	)
	CrystalInventory.profile_storage_directory = test_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	assert_bool(CrystalInventory.add_essence(7)).is_true()
	for skill_id in ["A", "E", "O", "Q"]:
		assert_bool(
			CrystalInventory.purchase_skill_node(StringName(skill_id))
		).is_true()
	var game = GAME_SCENE.instantiate()
	_track_node(game)

	assert_bool(game.wave_preview_label.visible).is_true()
	assert_bool(game.auto_waves_button.visible).is_true()
	assert_bool(game.auto_waves_button.disabled).is_false()
	assert_bool(game.wave_manager.auto_waves_enabled).is_true()
	game.auto_waves_button.pressed.emit()
	assert_bool(game.wave_manager.auto_waves_enabled).is_false()
	game.auto_waves_button.pressed.emit()
	assert_bool(game.wave_manager.auto_waves_enabled).is_true()
	assert_bool(game.wave_preview_label.text.contains("Total enemies:")).is_true()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	var wave_overrides: Array[WaveConfig] = [
		_create_wave_config(1, 5, GOBLIN_DATA),
		_create_wave_config(2, 1, GOBLIN_DATA)
	]
	wave_manager.wave_config_overrides = wave_overrides
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	for _index in range(4):
		wave_manager._process(wave_manager.spawn_interval)
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	var wave_two := _find_wave_summary(
		wave_manager.get_active_wave_summaries(),
		2
	)
	assert_float(
		wave_two["gold_multiplier"]
	).is_equal(1.3)

	CrystalInventory.profile_storage_directory = original_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	for file_name in [
		"player_profile.json",
		"player_profile.tmp",
		"player_profile.bak",
		"player_profile.bak.tmp"
	]:
		var file_path := test_profile_directory.path_join(file_name)
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(test_profile_directory)
	)


func test_crystal_installation_removal_and_slow_aura_effect() -> void:
	var tower := _make_tower()
	var enemy := _make_enemy(GOBLIN_DATA)
	enemy.position = Vector2(30.0, 0.0)

	assert_bool(tower.install_main_crystal(SLOW_CRYSTAL, 1)).is_true()
	assert_bool(tower.has_main_crystal()).is_true()
	assert_bool(tower.install_main_crystal(RAPID_FIRE_CRYSTAL, 1)).is_false()
	tower._process(0.1)
	assert_float(enemy.effective_speed).is_equal(enemy.speed * 0.8)

	var removed: CrystalInstance = tower.remove_main_crystal()
	assert_bool(removed != null).is_true()
	assert_str(String(removed.definition.crystal_id)).is_equal("slow")
	assert_int(removed.level).is_equal(1)
	assert_bool(tower.has_main_crystal()).is_false()
	assert_float(enemy.effective_speed).is_equal(enemy.speed)


func test_projectile_attack_intervals_and_bleed_ticks_are_deterministic() -> void:
	var original_profile_directory := CrystalInventory.profile_storage_directory
	var test_profile_directory := "user://gdunit-combat-timing-tests/%d-%d" % [
		Time.get_ticks_usec(),
		randi()
	]
	_temporary_profile_directory = test_profile_directory
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(test_profile_directory)
	)
	CrystalInventory.profile_storage_directory = test_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	assert_bool(CrystalInventory.add_essence(1)).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"A")).is_true()

	var combat_scene := Node2D.new()
	combat_scene.name = "CombatTestScene"
	get_tree().root.add_child(combat_scene)
	_created_nodes.append(combat_scene)
	get_tree().current_scene = combat_scene
	var tower := TOWER_SCENE.instantiate() as Tower
	combat_scene.add_child(tower)
	var target := ENEMY_SCENE.instantiate() as Enemy
	target.initialize_for_wave(GOBLIN_DATA, 100, GOBLIN_DATA.base_speed, 1, 1.0)
	combat_scene.add_child(target)
	target.global_position = Vector2(30.0, 0.0)
	tower.target_priority = Tower.TargetPriority.STRONGEST
	assert_bool(tower.install_main_crystal(RAPID_FIRE_CRYSTAL)).is_true()
	var projectiles: Array[Node] = []
	var on_node_added := func(node: Node) -> void:
		if node.has_method("hit_target"):
			projectiles.append(node)
			_created_nodes.append(node)
	get_tree().node_added.connect(on_node_added)

	tower._process(0.49)
	assert_float(tower.attack_timer).is_equal_approx(0.49, 0.0001)
	assert_int(projectiles.size()).is_equal(0)
	tower._process(0.01)
	assert_float(tower.attack_timer).is_equal(0.0)
	assert_int(projectiles.size()).is_equal(1)
	tower._process(0.49)
	assert_int(projectiles.size()).is_equal(1)
	tower._process(0.011)
	assert_int(projectiles.size()).is_equal(2)
	get_tree().node_added.disconnect(on_node_added)

	var bleed_target := ENEMY_SCENE.instantiate() as Enemy
	bleed_target.initialize_for_wave(
		GOBLIN_DATA,
		100,
		GOBLIN_DATA.base_speed,
		1,
		1.0
	)
	combat_scene.add_child(bleed_target)
	var bleed_projectile = PROJECTILE_SCENE.instantiate()
	_track_node(bleed_projectile)
	bleed_projectile.target = bleed_target
	bleed_projectile.damage = BLEED_CRYSTAL.damage
	bleed_projectile.bleed_max_hp_fraction_per_second = (
		BLEED_CRYSTAL.bleed_max_hp_fraction_per_second
	)
	bleed_projectile.bleed_duration = BLEED_CRYSTAL.bleed_duration
	bleed_projectile.hit_target()
	assert_int(bleed_target.hp).is_equal(95)
	bleed_target._process_bleed(1.0)
	assert_int(bleed_target.hp).is_equal(93)
	assert_float(bleed_target._bleed_remaining).is_equal(9.0)
	var reapplication := PROJECTILE_SCENE.instantiate()
	_track_node(reapplication)
	reapplication.target = bleed_target
	reapplication.damage = BLEED_CRYSTAL.damage
	reapplication.bleed_max_hp_fraction_per_second = (
		BLEED_CRYSTAL.bleed_max_hp_fraction_per_second
	)
	reapplication.bleed_duration = BLEED_CRYSTAL.bleed_duration
	reapplication.hit_target()
	assert_int(bleed_target.hp).is_equal(88)
	bleed_target._process_bleed(1.0)
	assert_int(bleed_target.hp).is_equal(86)
	assert_float(bleed_target._bleed_remaining).is_equal(9.0)

	CrystalInventory.profile_storage_directory = original_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	_remove_test_profile_directory(test_profile_directory)


func test_wave_scaling_opening_count_and_generated_budget_are_explicit() -> void:
	var game = _make_game()
	var wave_manager := game.wave_manager as WaveManager
	assert_int(wave_manager.get_enemy_hp_for_wave(1, 100)).is_equal(100)
	assert_int(wave_manager.get_enemy_hp_for_wave(5, 100)).is_equal(146)
	assert_float(
		wave_manager.get_enemy_speed_for_wave(5, 100.0)
	).is_equal_approx(102.0, 0.0001)
	assert_int(wave_manager.get_enemy_speed_percent_for_wave(5, 100.0)).is_equal(
		102
	)

	var generator := wave_manager._wave_generator
	var opening_wave := wave_manager.create_wave_config(1)
	assert_bool(opening_wave.archetype_id == &"MANUAL").is_false()
	assert_bool(wave_manager._get_total_enemy_count(opening_wave) > 0).is_true()
	var opening_cost := 0
	var old_test_composition := false
	for group in opening_wave.groups:
		opening_cost += group.enemy_data.difficulty_cost * group.quantity
		if (
			String(group.enemy_data.enemy_id) == "skeleton"
			and group.quantity == 3
		):
			for other_group in opening_wave.groups:
				if (
					String(other_group.enemy_data.enemy_id) == "troll"
					and other_group.quantity == 2
				):
					old_test_composition = true
	assert_bool(old_test_composition).is_false()
	assert_bool(
		opening_cost <= generator.get_difficulty_budget(1)
	).is_true()
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	assert_bool(
		wave_manager.active_waves[0].config.archetype_id == &"MANUAL"
	).is_false()

	var only_enemy := GOBLIN_DATA.duplicate(true) as EnemyData
	only_enemy.difficulty_cost = 2
	only_enemy.selection_weight = 1.0
	only_enemy.unlock_wave = 1
	generator.enemy_catalog = [only_enemy]
	generator.archetypes = [STANDARD_ARCHETYPE]
	generator.reset_history()
	wave_manager.active_map_data = null
	assert_int(generator.get_difficulty_budget(1)).is_equal(10)
	assert_int(generator.get_difficulty_budget(2)).is_equal(14)
	var generated_wave := generator.generate_wave(2, 1234)
	assert_int(wave_manager._get_total_enemy_count(generated_wave)).is_equal(7)
	assert_int(generated_wave.groups.size()).is_equal(1)
	assert_str(String(generated_wave.groups[0].enemy_data.enemy_id)).is_equal(
		"goblin"
	)


func test_map_has_five_empty_build_slots_and_fixed_construction_price() -> void:
	var game = _make_game()
	var slots: Array[BuildSlot] = []
	var built_towers: Array[Tower] = []
	for child in game.get_children():
		if child is BuildSlot:
			slots.append(child)
		elif child is Tower:
			built_towers.append(child)

	assert_int(slots.size()).is_equal(5)
	assert_int(built_towers.size()).is_equal(0)
	var expected_positions: Array[Vector2] = [
		Vector2(275.0, 375.0),
		Vector2(405.0, 365.0),
		Vector2(555.0, 375.0),
		Vector2(720.0, 365.0),
		Vector2(865.0, 375.0)
	]
	for expected_position in expected_positions:
		var found := false
		for slot in slots:
			if slot.global_position == expected_position and slot.is_available():
				found = true
				break
		assert_bool(found).is_true()
	for slot in slots:
		assert_int(slot.price).is_equal(100)
	assert_str(game.build_button.text).is_equal("BUILD (100 GOLD)")


func test_building_costs_exactly_one_hundred_and_rejects_insufficient_gold() -> void:
	var game = _make_game()
	var slots := get_tree().get_nodes_in_group("build_slots")
	assert_int(slots.size()).is_equal(5)
	var first_slot := game.get_node("BuildSlot") as BuildSlot
	first_slot.set_build_mode(true)
	assert_int(GoldManager.run_gold).is_equal(300)
	assert_bool(first_slot.attempt_build()).is_true()
	assert_int(GoldManager.run_gold).is_equal(200)
	assert_bool(first_slot.occupied).is_true()
	assert_bool(first_slot.built_tower is Tower).is_true()

	assert_bool(GoldManager.spend_gold(101)).is_true()
	var second_slot := game.get_node("BuildSlot2") as BuildSlot
	second_slot.set_build_mode(true)
	assert_int(GoldManager.run_gold).is_equal(99)
	assert_bool(second_slot.attempt_build()).is_false()
	assert_int(GoldManager.run_gold).is_equal(99)
	assert_bool(second_slot.occupied).is_false()


func test_wave_one_waits_for_manual_start_and_uses_generated_configuration() -> void:
	var game = GAME_SCENE.instantiate()
	_track_node(game)
	var wave_manager := game.get_node("WaveManager") as WaveManager
	assert_bool(wave_manager.auto_waves_enabled).is_true()
	assert_int(wave_manager.next_wave_number).is_equal(1)
	assert_int(wave_manager.active_waves.size()).is_equal(0)
	assert_bool(wave_manager._automatic_start_timers.is_empty()).is_true()
	assert_str(game.wave_countdown_label.text).is_equal("")

	game.start_wave_button.pressed.emit()
	assert_int(wave_manager.active_waves.size()).is_equal(1)
	assert_int(wave_manager.active_waves[0].wave_number).is_equal(1)
	assert_bool(
		wave_manager.active_waves[0].config.archetype_id == &"MANUAL"
	).is_false()


func test_tower_panel_install_remove_and_crystal_configuration_stay_in_sync() -> void:
	var game = _make_game()
	var tower := _add_test_tower(game, Vector2(405.0, 365.0))
	var panel := game.get_node("HUD/TowerPanel") as PanelContainer
	var remove_button := panel.get_node(
		"MarginContainer/VBoxContainer/RemoveCrystalButton"
	) as Button
	var profile_before: Dictionary = CrystalInventory.get_profile_data()
	assert_bool(CrystalInventory.add_run_crystal(&"rapid_fire", 1, 2)).is_true()
	var stats_change_count := [0]
	tower.stats_changed.connect(
		func() -> void:
			stats_change_count[0] += 1
	)
	game._select_tower(tower)
	game._select_tower(tower)

	assert_bool(panel.visible).is_true()
	assert_bool(
		panel.install_crystal_from_inventory({
			"type": "run_crystal",
			"crystal_id": "rapid_fire",
			"level": 1
		})
	).is_true()

	var installed := tower.get_main_crystal()
	assert_bool(installed != null).is_true()
	assert_object(installed.definition).is_same(RAPID_FIRE_CRYSTAL)
	assert_int(installed.level).is_equal(1)
	assert_int(tower.damage).is_equal(12)
	assert_float(tower.attack_speed).is_equal(2.0)
	assert_float(tower.attack_range).is_equal(180.0)
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"rapid_fire", 1)
	).is_equal(2)
	var socket_label := panel.get_node(
		"MarginContainer/VBoxContainer/MainSocketLabel"
	) as Label
	assert_bool(socket_label.text.contains("Level")).is_false()
	assert_bool(remove_button.visible).is_true()
	assert_int(stats_change_count[0]).is_equal(1)

	assert_bool(
		panel.install_crystal_from_inventory({
			"type": "run_crystal",
			"crystal_id": "rapid_fire",
			"level": 1
		})
	).is_true()
	assert_object(tower.get_main_crystal()).is_same(installed)
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"rapid_fire", 1)
	).is_equal(2)
	assert_int(stats_change_count[0]).is_equal(1)

	remove_button.pressed.emit()
	assert_bool(tower.main_socket.is_empty()).is_true()
	assert_bool(tower.get_main_crystal() == null).is_true()
	assert_bool(remove_button.visible).is_false()
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"rapid_fire", 1)
	).is_equal(3)
	assert_int(stats_change_count[0]).is_equal(2)

	remove_button.pressed.emit()
	assert_bool(tower.remove_main_crystal() == null).is_true()
	assert_int(stats_change_count[0]).is_equal(2)
	assert_bool(tower.install_main_crystal(null)).is_false()
	assert_bool(tower.main_socket.is_empty()).is_true()
	assert_int(stats_change_count[0]).is_equal(2)
	assert_bool(CrystalInventory.get_profile_data() == profile_before).is_true()


func test_run_inventory_validates_quantities_and_preserves_levels() -> void:
	_ensure_awakened_for_test()
	CrystalInventory.start_run_inventory()
	var initial_quantity := CrystalInventory.get_available_crystal_quantity(
		&"rapid_fire",
		2
	)

	assert_bool(CrystalInventory.add_run_crystal(&"rapid_fire", 2, 3)).is_true()
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"rapid_fire", 2)
	).is_equal(initial_quantity + 3)
	assert_bool(CrystalInventory.add_run_crystal(&"unknown", 1)).is_false()
	assert_bool(CrystalInventory.add_run_crystal(&"rapid_fire", 0)).is_false()
	assert_bool(
		CrystalInventory.add_run_crystal(
			&"rapid_fire",
			CrystalInventory.MAX_CRYSTAL_LEVEL + 1
		)
	).is_false()
	assert_bool(CrystalInventory.add_run_crystal(&"rapid_fire", 2, 0)).is_false()
	assert_bool(CrystalInventory.add_run_crystal(&"rapid_fire", 2, -1)).is_false()
	assert_bool(
		CrystalInventory.add_run_crystal(
			&"rapid_fire",
			2,
			CrystalInventory.MAX_CRYSTAL_QUANTITY
		)
	).is_false()

	var profile_before: Dictionary = CrystalInventory.get_profile_data()
	var definition := RAPID_FIRE_CRYSTAL
	assert_bool(CrystalInventory.can_install_crystal(null, 2)).is_false()
	assert_bool(CrystalInventory.can_install_crystal(definition, 2)).is_true()
	assert_bool(CrystalInventory.consume_run_crystal(definition, 2)).is_true()
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"rapid_fire", 2)
	).is_equal(initial_quantity + 2)
	assert_bool(CrystalInventory.get_profile_data() == profile_before).is_true()
	CrystalInventory.end_run_inventory()

	assert_int(CrystalInventory.get_available_crystals().size()).is_equal(0)
	assert_bool(CrystalInventory.add_run_crystal(&"rapid_fire", 2)).is_false()


func test_tower_panel_rejects_empty_inventory_and_competing_towers() -> void:
	var game = _make_game()
	var first_tower := _add_test_tower(game, Vector2(405.0, 365.0))
	var second_tower := TOWER_SCENE.instantiate() as Tower
	game.add_child(second_tower)
	var panel := game.get_node("HUD/TowerPanel") as PanelContainer
	assert_bool(
		panel.get_node_or_null(
			"MarginContainer/VBoxContainer/InstallRapidFireButton"
		) == null
	).is_true()
	assert_bool(
		panel.get_node_or_null("MarginContainer/VBoxContainer/InstallSlowButton") == null
	).is_true()
	assert_bool(
		panel.get_node_or_null("MarginContainer/VBoxContainer/InstallBleedButton") == null
	).is_true()
	assert_bool(
		panel.get_node_or_null("MarginContainer/VBoxContainer/CrystalAvailabilityLabel")
		== null
	).is_true()
	game._select_tower(first_tower)
	assert_bool(panel.can_install_crystal_from_inventory({
		"type": "run_crystal",
		"crystal_id": "slow",
		"level": 3
	})).is_false()
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 3)).is_equal(0)

	assert_bool(CrystalInventory.add_run_crystal(&"slow", 3)).is_true()
	assert_bool(panel.can_install_crystal_from_inventory({
		"type": "run_crystal",
		"crystal_id": "slow",
		"level": 3
	})).is_true()
	assert_bool(panel.install_crystal_from_inventory({
		"type": "run_crystal",
		"crystal_id": "slow",
		"level": 3
	})).is_true()
	assert_int(first_tower.get_main_crystal().level).is_equal(3)
	assert_float(
		first_tower.current_attack_configuration.slow_fraction
	).is_equal_approx(0.242, 0.0001)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 3)).is_equal(0)

	game._select_tower(second_tower)
	assert_bool(panel.install_crystal_from_inventory({
		"type": "run_crystal",
		"crystal_id": "slow",
		"level": 3
	})).is_false()
	assert_bool(second_tower.has_main_crystal()).is_false()
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 3)).is_equal(0)

	game._select_tower(first_tower)
	var remove_button := panel.get_node(
		"MarginContainer/VBoxContainer/RemoveCrystalButton"
	) as Button
	remove_button.pressed.emit()
	assert_bool(first_tower.has_main_crystal()).is_false()
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 3)).is_equal(1)
	remove_button.pressed.emit()
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 3)).is_equal(1)


func test_run_inventory_button_refreshes_and_closes_without_regranting_crystals() -> void:
	var game = _make_game()
	var button := game.get_node("HUD/CrystalsButton") as Button
	var panel := game.run_crystal_inventory_panel as RunCrystalInventoryPanel
	assert_bool(CrystalInventory.add_run_crystal(&"bleed", 1, 1)).is_true()
	assert_bool(CrystalInventory.add_run_crystal(&"slow", 1, 1)).is_true()

	assert_bool(panel.visible).is_false()
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 1)).is_equal(1)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 1)).is_equal(1)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"rapid_fire", 1)).is_equal(1)
	button.pressed.emit()

	assert_bool(panel.visible).is_true()
	assert_int(panel.get_node("Margin/Contents/Scroll/Entries").get_child_count()).is_equal(4)
	var item := panel.get_node(
		"Margin/Contents/Scroll/Entries"
	).get_child(0) as RunCrystalInventoryItem
	assert_bool(item.level_label.visible).is_false()
	assert_str(item.crystal_id).is_equal("bleed")
	assert_int(item.crystal_level).is_equal(1)
	assert_int(item.crystal_quantity).is_equal(1)

	button.pressed.emit()
	button.pressed.emit()
	assert_bool(panel.visible).is_true()
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"bleed", 1)
	).is_equal(1)
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"slow", 1)
	).is_equal(1)
	panel.get_node("Margin/Contents/Header/CloseButton").pressed.emit()
	assert_bool(panel.visible).is_false()


func test_dragging_crystal_to_selected_tower_socket_installs_and_returns_same_level() -> void:
	var game = _make_game()
	assert_bool(CrystalInventory.add_run_crystal(&"bleed", 1, 1)).is_true()
	var tower := _add_test_tower(game, Vector2(405.0, 365.0))
	var panel := game.get_node("HUD/TowerPanel") as PanelContainer
	var drop_target := panel.get_node(
		"MarginContainer/VBoxContainer/CrystalSocketDropTarget"
	) as CrystalSocketDropTarget
	game._select_tower(tower)
	game.crystals_button.pressed.emit()

	var entries := game.run_crystal_inventory_panel.get_node(
		"Margin/Contents/Scroll/Entries"
	) as VBoxContainer
	var item := entries.get_child(0) as RunCrystalInventoryItem
	var drag_data: Dictionary = item.get_drag_payload()
	assert_bool(drag_data is Dictionary).is_true()
	assert_str(drag_data["crystal_id"]).is_equal("bleed")
	assert_int(drag_data["level"]).is_equal(1)
	assert_bool(drop_target._can_drop_data(Vector2.ZERO, drag_data)).is_true()

	drop_target._drop_data(Vector2.ZERO, drag_data)
	assert_bool(tower.has_main_crystal()).is_true()
	assert_bool(tower.get_node("CrystalSocketVisual").occupied).is_true()
	assert_int(entries.get_child_count()).is_equal(2)
	assert_str(String(tower.get_main_crystal().definition.crystal_id)).is_equal("bleed")
	assert_int(tower.get_main_crystal().level).is_equal(1)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 1)).is_equal(0)
	assert_object(drop_target.icon.texture).is_same(tower.get_main_crystal().definition.visual_texture)
	assert_int(roundi(tower.current_attack_configuration.damage)).is_equal(5)
	assert_float(
		tower.current_attack_configuration.bleed_max_hp_fraction_per_second
	).is_equal_approx(0.02, 0.0001)
	var installed := tower.get_main_crystal()
	assert_bool(drop_target._can_drop_data(Vector2.ZERO, drag_data)).is_true()
	assert_bool(
		panel.install_crystal_from_inventory({
			"type": "run_crystal",
			"crystal_id": "bleed",
			"level": 1
		})
	).is_true()
	assert_object(tower.get_main_crystal()).is_same(installed)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 1)).is_equal(0)

	var remove_button := panel.get_node(
		"MarginContainer/VBoxContainer/RemoveCrystalButton"
	) as Button
	remove_button.pressed.emit()
	assert_bool(tower.has_main_crystal()).is_false()
	assert_bool(tower.get_node("CrystalSocketVisual").occupied).is_false()
	assert_int(entries.get_child_count()).is_equal(3)
	assert_bool(drop_target.icon.texture == null).is_true()
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 1)).is_equal(1)
	remove_button.pressed.emit()
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 1)).is_equal(1)


func test_drag_replaces_crystal_atomically_and_preserves_outgoing_level() -> void:
	var game = _make_game()
	assert_bool(
		CrystalInventory.consume_run_crystal(RAPID_FIRE_CRYSTAL, 1)
	).is_true()
	var tower := _add_test_tower(game, Vector2(405.0, 365.0))
	var panel := game.get_node("HUD/TowerPanel") as PanelContainer
	var drop_target := panel.get_node(
		"MarginContainer/VBoxContainer/CrystalSocketDropTarget"
	) as CrystalSocketDropTarget
	assert_bool(CrystalInventory.add_run_crystal(&"bleed", 4, 1)).is_true()
	assert_bool(CrystalInventory.add_run_crystal(&"slow", 3, 2)).is_true()
	game._select_tower(tower)
	game.crystals_button.pressed.emit()

	var entries := game.run_crystal_inventory_panel.get_node(
		"Margin/Contents/Scroll/Entries"
	) as VBoxContainer
	var bleed_item: RunCrystalInventoryItem
	for entry in entries.get_children():
		var inventory_item := entry as RunCrystalInventoryItem
		if inventory_item.crystal_id == "bleed" and inventory_item.crystal_level == 4:
			bleed_item = inventory_item
			break
	assert_bool(bleed_item != null).is_true()
	var bleed_drag_data := bleed_item.get_drag_payload()
	assert_bool(drop_target._can_drop_data(Vector2.ZERO, bleed_drag_data)).is_true()
	drop_target._drop_data(Vector2.ZERO, bleed_drag_data)
	assert_str(String(tower.get_main_crystal().definition.crystal_id)).is_equal("bleed")
	assert_int(tower.get_main_crystal().level).is_equal(4)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 4)).is_equal(0)

	var slow_item: RunCrystalInventoryItem
	for entry in entries.get_children():
		var inventory_item := entry as RunCrystalInventoryItem
		if inventory_item.crystal_id == "slow" and inventory_item.crystal_level == 3:
			slow_item = inventory_item
			break
	assert_bool(slow_item != null).is_true()
	var slow_drag_data := slow_item.get_drag_payload()
	assert_bool(drop_target._can_drop_data(Vector2.ZERO, slow_drag_data)).is_true()
	drop_target._drop_data(Vector2.ZERO, slow_drag_data)

	assert_str(String(tower.get_main_crystal().definition.crystal_id)).is_equal("slow")
	assert_int(tower.get_main_crystal().level).is_equal(3)
	assert_bool(tower.get_node("CrystalSocketVisual").occupied).is_true()
	assert_object(drop_target.icon.texture).is_same(SLOW_CRYSTAL.visual_texture)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 4)).is_equal(1)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 3)).is_equal(1)
	assert_float(
		tower.current_attack_configuration.slow_fraction
	).is_equal_approx(0.242, 0.0001)

	var installed := tower.get_main_crystal()
	assert_bool(panel.install_crystal_from_inventory(slow_drag_data)).is_true()
	assert_object(tower.get_main_crystal()).is_same(installed)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 3)).is_equal(1)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 4)).is_equal(1)

	assert_bool(panel.install_crystal_from_inventory({
		"type": "run_crystal",
		"crystal_id": "rapid_fire",
		"level": 1
	})).is_false()
	assert_object(tower.get_main_crystal()).is_same(installed)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 3)).is_equal(1)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 4)).is_equal(1)

	panel.get_node("MarginContainer/VBoxContainer/RemoveCrystalButton").pressed.emit()
	assert_bool(tower.has_main_crystal()).is_false()
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 3)).is_equal(2)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 4)).is_equal(1)


func test_invalid_or_other_tower_drop_does_not_consume_inventory() -> void:
	var game = _make_game()
	assert_bool(CrystalInventory.add_run_crystal(&"bleed", 1, 1)).is_true()
	var first_tower := _add_test_tower(game, Vector2(405.0, 365.0))
	var second_tower := _add_test_tower(game, Vector2(720.0, 365.0))
	game._select_tower(first_tower)
	var tower_panel := game.tower_panel as PanelContainer
	game.crystals_button.pressed.emit()
	var item := game.run_crystal_inventory_panel.get_node(
		"Margin/Contents/Scroll/Entries"
	).get_child(0) as RunCrystalInventoryItem
	var drag_data: Dictionary = item.get_drag_payload()
	var drop_target := game.get_node(
		"HUD/TowerPanel/MarginContainer/VBoxContainer/CrystalSocketDropTarget"
	) as CrystalSocketDropTarget

	assert_bool(drop_target._can_drop_data(Vector2.ZERO, {
		"type": "other",
		"crystal_id": "bleed",
		"level": 1
	})).is_false()
	assert_bool(
		tower_panel.install_crystal_from_inventory({
			"type": "invalid",
			"crystal_id": "bleed",
			"level": 1
		})
	).is_false()
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 1)).is_equal(1)

	game._select_tower(second_tower)
	assert_bool(drop_target._can_drop_data(Vector2.ZERO, drag_data)).is_true()
	drop_target._drop_data(Vector2.ZERO, drag_data)
	assert_bool(first_tower.has_main_crystal()).is_false()
	assert_bool(second_tower.has_main_crystal()).is_true()
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 1)).is_equal(0)


func test_map_drop_installs_on_unselected_tower_without_opening_its_panel() -> void:
	var game = _make_game()
	assert_bool(CrystalInventory.add_run_crystal(&"bleed", 1, 1)).is_true()
	var tower := _add_test_tower(game, Vector2(720.0, 365.0))
	var panel := game.get_node("HUD/TowerPanel") as PanelContainer
	var screen_position := (
		get_viewport().get_canvas_transform() * tower.global_position
	)
	await get_tree().physics_frame
	assert_bool(game.selected_tower == null).is_true()
	assert_bool(panel.visible).is_false()
	assert_object(game.get_tower_at_screen_position(screen_position)).is_same(tower)

	var data := {
		"type": "run_crystal",
		"crystal_id": "bleed",
		"level": 1
	}
	var drop_surface: Control = game.map_crystal_drop_surface
	assert_bool(drop_surface.call("_can_drop_data", screen_position, data)).is_true()
	assert_bool(tower._crystal_drop_highlight).is_true()
	assert_bool(tower._crystal_drop_replacement).is_false()
	drop_surface.call("_notification", Control.NOTIFICATION_DRAG_END)
	assert_bool(tower._crystal_drop_highlight).is_false()

	assert_bool(drop_surface.call("_can_drop_data", screen_position, data)).is_true()
	drop_surface.call("_drop_data", screen_position, data)

	assert_str(String(tower.get_main_crystal().definition.crystal_id)).is_equal("bleed")
	assert_int(tower.get_main_crystal().level).is_equal(1)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 1)).is_equal(0)
	assert_bool(game.selected_tower == null).is_true()
	assert_bool(panel.visible).is_false()
	assert_bool(tower._crystal_drop_highlight).is_false()


func test_map_drop_replaces_occupied_socket_and_returns_original_crystal_level() -> void:
	var game = _make_game()
	assert_bool(CrystalInventory.add_run_crystal(&"slow", 1, 1)).is_true()
	var tower := _add_test_tower(game, Vector2(720.0, 365.0))
	var bleed_definition := CrystalInventory.get_crystal_definition(&"bleed")
	assert_bool(tower.install_main_crystal(bleed_definition, 3)).is_true()
	var data := {
		"type": "run_crystal",
		"crystal_id": "slow",
		"level": 1
	}
	var screen_position := (
		get_viewport().get_canvas_transform() * Vector2(80.0, 80.0)
	)
	await get_tree().physics_frame
	assert_bool(game.drop_crystal_on_map(data, screen_position)).is_false()
	assert_str(String(tower.get_main_crystal().definition.crystal_id)).is_equal("bleed")
	assert_int(tower.get_main_crystal().level).is_equal(3)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 1)).is_equal(1)

	var tower_screen_position := (
		get_viewport().get_canvas_transform() * tower.global_position
	)
	game.update_map_crystal_drop_highlights(data, tower)
	assert_bool(tower._crystal_drop_highlight).is_true()
	assert_bool(tower._crystal_drop_replacement).is_true()
	assert_bool(game.drop_crystal_on_map(data, tower_screen_position)).is_true()
	assert_str(String(tower.get_main_crystal().definition.crystal_id)).is_equal("slow")
	assert_int(tower.get_main_crystal().level).is_equal(1)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 1)).is_equal(0)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 3)).is_equal(1)
	assert_bool(tower._crystal_drop_highlight).is_false()
	assert_bool(tower._crystal_drop_replacement).is_false()


func test_failed_map_replacement_preserves_inventory_tower_and_highlight_state() -> void:
	var game = _make_game()
	var tower := _add_test_tower(game, Vector2(720.0, 365.0))
	assert_bool(tower.install_main_crystal(
		CrystalInventory.get_crystal_definition(&"bleed"),
		2
	)).is_true()
	assert_bool(CrystalInventory.add_run_crystal(
		&"bleed",
		2,
		CrystalInventory.MAX_CRYSTAL_QUANTITY
	)).is_true()
	assert_bool(CrystalInventory.add_run_crystal(&"slow", 1, 1)).is_true()
	var data := {
		"type": "run_crystal",
		"crystal_id": "slow",
		"level": 1
	}
	var screen_position := (
		get_viewport().get_canvas_transform() * tower.global_position
	)
	await get_tree().physics_frame

	game.update_map_crystal_drop_highlights(data, tower)
	assert_bool(tower._crystal_drop_highlight).is_false()
	assert_bool(tower._crystal_drop_replacement).is_false()
	assert_bool(game.drop_crystal_on_map(data, screen_position)).is_false()
	assert_str(String(tower.get_main_crystal().definition.crystal_id)).is_equal("bleed")
	assert_int(tower.get_main_crystal().level).is_equal(2)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 2)).is_equal(
		CrystalInventory.MAX_CRYSTAL_QUANTITY
	)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 1)).is_equal(1)
	assert_bool(tower._crystal_drop_highlight).is_false()


func test_map_drop_refreshes_selected_panel_without_changing_selection() -> void:
	var game = _make_game()
	assert_bool(CrystalInventory.add_run_crystal(&"slow", 1, 1)).is_true()
	var tower := _add_test_tower(game, Vector2(405.0, 365.0))
	var panel := game.get_node("HUD/TowerPanel") as PanelContainer
	game._select_tower(tower)
	var screen_position := (
		get_viewport().get_canvas_transform() * tower.global_position
	)
	await get_tree().physics_frame

	assert_bool(game.drop_crystal_on_map({
		"type": "run_crystal",
		"crystal_id": "slow",
		"level": 1
	}, screen_position)).is_true()
	assert_object(game.selected_tower).is_same(tower)
	assert_bool(panel.visible).is_true()
	assert_bool(
		(panel.get_node("MarginContainer/VBoxContainer/MainSocketLabel") as Label)
		.text.contains("Slow")
	).is_true()
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 1)).is_equal(0)


func test_empty_map_click_closes_both_panels_but_tower_click_selects_tower() -> void:
	var game = _make_game()
	var tower := _add_test_tower(game, Vector2(405.0, 365.0))
	var panel := game.get_node("HUD/TowerPanel") as PanelContainer
	var inventory_panel: RunCrystalInventoryPanel = game.run_crystal_inventory_panel
	game._toggle_crystal_inventory()
	game._select_tower(tower)
	assert_bool(panel.visible).is_true()
	assert_bool(inventory_panel.visible).is_true()

	game._unhandled_input(_make_mouse_button_event(Vector2(500.0, 580.0)))
	assert_bool(game.selected_tower == null).is_true()
	assert_bool(panel.visible).is_false()
	assert_bool(inventory_panel.visible).is_false()

	game._toggle_crystal_inventory()
	var tower_screen_position := (
		get_viewport().get_canvas_transform() * tower.global_position
	)
	await get_tree().physics_frame
	game._unhandled_input(_make_mouse_button_event(tower_screen_position))
	assert_object(game.selected_tower).is_same(tower)
	assert_bool(panel.visible).is_true()
	assert_bool(inventory_panel.visible).is_true()


func test_inventory_ui_and_drag_release_do_not_trigger_empty_map_close() -> void:
	var game = _make_game()
	var tower := _add_test_tower(game, Vector2(720.0, 365.0))
	var panel := game.get_node("HUD/TowerPanel") as PanelContainer
	var inventory_panel: RunCrystalInventoryPanel = game.run_crystal_inventory_panel
	game._toggle_crystal_inventory()
	game._select_tower(tower)

	var inventory_position: Vector2 = inventory_panel.get_global_rect().get_center()
	assert_bool(game._is_over_interactive_hud_control(inventory_position)).is_true()
	game._unhandled_input(_make_mouse_button_event(inventory_position))
	assert_bool(panel.visible).is_true()
	assert_bool(inventory_panel.visible).is_true()

	game._unhandled_input(_make_mouse_button_event(
		Vector2(500.0, 580.0),
		false
	))
	assert_bool(panel.visible).is_true()
	assert_bool(inventory_panel.visible).is_true()


func test_skill_tree_is_one_connected_read_only_graph_with_hidden_fire_branch() -> void:
	var profile_before: Dictionary = CrystalInventory.get_profile_data()
	var gold_before := GoldManager.run_gold
	var run_crystals_before := CrystalInventory.get_available_crystals()
	var screen := SKILL_TREE_SCENE.instantiate()
	_track_node(screen)
	var tree_canvas := screen.get_node(
		"Root/Margin/Contents/Body/TreePanel/Margin/Scroll/TreeCanvas"
	) as Control
	var definitions: Array[Dictionary] = SKILL_TREE_CATALOG.get_skill_definitions()
	var seen_ids: Dictionary = {}
	var prerequisites_by_id: Dictionary = {}
	for definition in definitions:
		var skill_id: String = definition["id"]
		assert_bool(seen_ids.has(skill_id)).is_false()
		seen_ids[skill_id] = true
		prerequisites_by_id[skill_id] = definition["prerequisites"]
	assert_bool(SKILL_TREE_CATALOG.has_unique_ids()).is_true()
	assert_bool(prerequisites_by_id["B"].has("A")).is_true()
	assert_bool(prerequisites_by_id["C"].has("A")).is_true()
	assert_bool(prerequisites_by_id["D"].has("A")).is_true()
	assert_bool(prerequisites_by_id["E"].has("A")).is_true()
	assert_int(tree_canvas.get_child_count()).is_equal(definitions.size())

	var h_purchased := CrystalInventory.is_skill_purchased(&"H")
	for hidden_id in [&"D", &"I", &"J"]:
		assert_bool(
			(screen._nodes[hidden_id] as SkillTreeNode).visible == h_purchased
		).is_true()
	(screen._nodes[&"B"] as Control).grab_focus()
	assert_int(screen.tree_scroll.scroll_horizontal).is_greater(0)
	assert_bool(
		screen.get_node(
			"Root/Margin/Contents/Body/Details/Margin/Contents/"
			+ "PurchaseButton"
		).disabled
	).is_true()
	assert_bool(prerequisites_by_id["H"].has("F")).is_true()
	assert_bool(prerequisites_by_id["H"].has("G")).is_true()
	assert_bool(prerequisites_by_id["I"].has("H")).is_true()
	assert_bool(prerequisites_by_id["I"].has("D")).is_true()
	assert_bool(prerequisites_by_id["J"].has("I")).is_true()
	assert_bool(prerequisites_by_id["Q"].has("O")).is_true()

	assert_bool(CrystalInventory.get_profile_data() == profile_before).is_true()
	assert_int(GoldManager.run_gold).is_equal(gold_before)
	assert_bool(
		CrystalInventory.get_available_crystals() == run_crystals_before
	).is_true()
	var menu := MAIN_MENU_SCENE.instantiate()
	_track_node(menu)
	assert_bool(menu.get_node_or_null(
		"CenterPanel/MarginContainer/MenuContents/SkillTreeButton"
	) != null).is_true()
	assert_bool(menu.get_node_or_null(
		"CenterPanel/MarginContainer/MenuContents/ResetSkillsButton"
	) != null).is_true()
	assert_bool(menu.get_node_or_null("ResetSkillsConfirmation") != null).is_true()
	assert_bool(screen.get_node_or_null(
		"Root/Margin/Contents/TreeTabs"
	) == null).is_true()


func test_run_inventory_screen_refreshes_and_labels_the_run_view() -> void:
	_ensure_awakened_for_test()
	var inventory = INVENTORY_SCENE.instantiate()
	_track_node(inventory)

	var title := inventory.get_node(
		"CenterPanel/MarginContainer/Contents/Title"
	) as Label
	var empty_label := inventory.get_node(
		"CenterPanel/MarginContainer/Contents/EmptyLabel"
	) as Label
	var entries := inventory.get_node(
		"CenterPanel/MarginContainer/Contents/ScrollContainer/Entries"
	) as VBoxContainer
	assert_str(title.text).is_equal("PERSISTENT CRYSTAL COLLECTION")
	assert_int(entries.get_child_count()).is_equal(
		CrystalInventory.get_owned_crystals().size()
	)

	CrystalInventory.start_run_inventory()
	assert_str(title.text).is_equal("RUN INVENTORY - AVAILABLE")
	assert_bool(empty_label.visible).is_false()
	assert_int(entries.get_child_count()).is_equal(2)

	assert_bool(CrystalInventory.add_run_crystal(&"bleed", 4, 2)).is_true()
	assert_bool(empty_label.visible).is_false()
	assert_int(entries.get_child_count()).is_equal(3)
	var row := entries.get_child(0) as HBoxContainer
	assert_str((row.get_child(1) as Label).text).is_equal(
		"Bleed Crystal (bleed)"
	)
	assert_str((row.get_child(2) as Label).text).is_equal(
		"Available: 2"
	)

	CrystalInventory.end_run_inventory()
	assert_str(title.text).is_equal("PERSISTENT CRYSTAL COLLECTION")
	assert_bool(empty_label.visible).is_false()
	assert_int(entries.get_child_count()).is_equal(2)


func test_game_lifecycle_resets_run_state_without_changing_profile() -> void:
	_ensure_awakened_for_test()
	var profile_before: Dictionary = CrystalInventory.get_profile_data()
	var essence_before := CrystalInventory.get_essence_balance()
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
	assert_int(CrystalInventory.get_essence_balance()).is_equal(essence_before)
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"bleed", 1)
	).is_equal(0)
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"slow", 1)
	).is_equal(0)
	assert_int(
		CrystalInventory.get_available_crystal_quantity(&"rapid_fire", 1)
	).is_equal(1)
	assert_int(first_wave_manager.next_wave_number).is_equal(1)
	assert_int(first_wave_manager.active_waves.size()).is_equal(0)
	assert_bool(first_wave_manager.auto_waves_enabled).is_true()
	assert_bool(first_wave_manager._automatic_start_timers.is_empty()).is_true()
	assert_bool(first_game.auto_waves_button.visible).is_false()
	assert_bool(first_game.wave_preview_label.visible).is_false()

	var first_tower := _add_test_tower(first_game, Vector2(405.0, 365.0))
	first_game._select_tower(first_tower)
	var first_panel := first_game.get_node("HUD/TowerPanel") as PanelContainer
	assert_bool(first_panel.install_crystal_from_inventory({
		"type": "run_crystal",
		"crystal_id": "rapid_fire",
		"level": 1
	})).is_true()
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
	assert_int(CrystalInventory.get_essence_balance()).is_equal(essence_before)
	assert_bool(CrystalInventory.is_run_inventory_active()).is_false()
	assert_int(CrystalInventory.get_available_crystals().size()).is_equal(0)

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
	assert_bool(retried_wave_manager._automatic_start_timers.is_empty()).is_true()
	assert_bool(retried_game.auto_waves_button.visible).is_false()
	assert_bool(retried_game.wave_preview_label.visible).is_false()
	assert_int(retried_game.get_node("Enemies").get_child_count()).is_equal(0)
	assert_bool(retried_game.get_node_or_null("Tower") == null).is_true()
	assert_int(GoldManager.run_gold).is_equal(GoldManager.STARTING_RUN_GOLD)
	assert_int(CrystalInventory.get_essence_balance()).is_equal(essence_before)
	assert_str(
		(retried_game.get_node("HUD/EssenceLabel") as Label).text
	).is_equal("Essence: %d" % essence_before)
	assert_bool(CrystalInventory.is_run_inventory_active()).is_true()


	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 1)).is_equal(0)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 1)).is_equal(0)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"rapid_fire", 1)).is_equal(1)

	var build_slots := get_tree().get_nodes_in_group("build_slots")
	assert_int(build_slots.size()).is_equal(5)
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
	assert_str(
		(get_tree().current_scene.get_node("EssenceLabel") as Label).text
	).is_equal("Essence: %d" % essence_before)

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
	assert_int(CrystalInventory.get_essence_balance()).is_equal(essence_before)
	assert_str(
		(second_game.get_node("HUD/EssenceLabel") as Label).text
	).is_equal("Essence: %d" % essence_before)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"bleed", 1)).is_equal(0)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"slow", 1)).is_equal(0)
	assert_int(CrystalInventory.get_available_crystal_quantity(&"rapid_fire", 1)).is_equal(1)
	assert_bool(CrystalInventory.get_profile_data() == profile_before).is_true()


func test_passive_gold_uses_one_run_timer_and_stops_when_the_run_ends() -> void:
	var original_profile_directory := CrystalInventory.profile_storage_directory
	var test_profile_directory := "user://gdunit-passive-gold/%d-%d" % [
		Time.get_ticks_usec(),
		randi()
	]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(test_profile_directory)
	)
	CrystalInventory.profile_storage_directory = test_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	assert_bool(CrystalInventory.add_essence(6)).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"A")).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"E")).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"P")).is_true()

	var game = GAME_SCENE.instantiate()
	_track_node(game)
	var timer := game.get_node("PassiveGoldTimer") as Timer
	assert_object(timer).is_not_null()
	assert_bool(game.wave_manager.auto_waves_enabled).is_true()
	assert_bool(game.auto_waves_button.visible).is_true()
	game._configure_passive_gold()
	assert_int(
		game.find_children("PassiveGoldTimer", "Timer", false, false).size()
	).is_equal(1)
	timer.wait_time = 0.01
	timer.start()
	await get_tree().create_timer(0.04).timeout
	assert_bool(GoldManager.run_gold > 0).is_true()

	game._finish_run()
	var gold_after_end := GoldManager.run_gold
	assert_bool(timer.is_stopped()).is_true()
	game._on_passive_gold_timeout()
	assert_int(GoldManager.run_gold).is_equal(gold_after_end)

	CrystalInventory.profile_storage_directory = original_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()
	for file_name in [
		"player_profile.json",
		"player_profile.tmp",
		"player_profile.bak",
		"player_profile.bak.tmp"
	]:
		var file_path := test_profile_directory.path_join(file_name)
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(test_profile_directory)
	)


func test_essence_displays_refresh_from_profile_and_remains_separate_from_gold() -> void:
	var menu := MAIN_MENU_SCENE.instantiate()
	_track_node(menu)
	var game = _make_game()
	var menu_essence_label := menu.get_node("EssenceLabel") as Label
	var game_essence_label := game.get_node("HUD/EssenceLabel") as Label
	var original_essence := CrystalInventory.get_essence_balance()
	var expected_text := "Essence: %d" % original_essence

	assert_str(menu_essence_label.text).is_equal(expected_text)
	assert_str(game_essence_label.text).is_equal(expected_text)
	assert_bool(CrystalInventory.add_essence(17)).is_true()
	expected_text = "Essence: %d" % (original_essence + 17)
	assert_str(menu_essence_label.text).is_equal(expected_text)
	assert_str(game_essence_label.text).is_equal(expected_text)

	GoldManager.add_gold(31)
	assert_int(GoldManager.run_gold).is_equal(
		GoldManager.STARTING_RUN_GOLD + 31
	)
	assert_int(CrystalInventory.get_essence_balance()).is_equal(
		original_essence + 17
	)
	game._finish_run()
	assert_int(GoldManager.run_gold).is_equal(0)
	assert_int(CrystalInventory.get_essence_balance()).is_equal(
		original_essence + 17
	)
	assert_str(menu_essence_label.text).is_equal(expected_text)
	assert_str(game_essence_label.text).is_equal(expected_text)

	assert_bool(CrystalInventory.spend_essence(17)).is_true()
	expected_text = "Essence: %d" % original_essence
	assert_str(menu_essence_label.text).is_equal(expected_text)
	assert_str(game_essence_label.text).is_equal(expected_text)


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
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	wave_manager.set_auto_waves_enabled(true)
	_complete_wave_for_test(game)
	var timer: Timer = wave_manager._automatic_start_timers[2]
	var token: int = wave_manager._automatic_start_tokens[2]
	var generation := wave_manager._automatic_schedule_generation
	for _second in range(int(WaveManager.AUTO_WAVE_DELAY_SECONDS) - 1):
		wave_manager._on_automatic_start_timeout(2, token, generation, timer)
	wave_manager._on_automatic_start_timeout(2, token, generation, timer)

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
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)

	wave_manager.set_auto_waves_enabled(true)
	assert_bool(wave_manager._automatic_start_timers.has(2)).is_false()
	_complete_wave_for_test(game)
	assert_bool(wave_manager._automatic_start_timers.has(2)).is_true()
	var stale_token: int = wave_manager._automatic_start_tokens[2]
	var stale_generation: int = wave_manager._automatic_schedule_generation
	var stale_timer: Timer = wave_manager._automatic_start_timers[2]
	assert_float(stale_timer.wait_time).is_equal(1.0)
	assert_int(wave_manager._automatic_start_remaining[2]).is_equal(10)
	assert_str(game.wave_countdown_label.text).is_equal("Next wave in: 10")
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
	for _second in range(int(WaveManager.AUTO_WAVE_DELAY_SECONDS) - 1):
		wave_manager._on_automatic_start_timeout(2, token, generation, timer)
	assert_int(wave_manager.next_wave_number).is_equal(2)
	assert_int(wave_manager._automatic_start_remaining[2]).is_equal(1)
	wave_manager._on_automatic_start_timeout(2, token, generation, timer)

	var wave_two: Dictionary = _find_wave_summary(
		wave_manager.get_active_wave_summaries(),
		2
	)
	assert_int(wave_two["start_reason"]).is_equal(WaveManager.StartReason.AUTOMATIC)


func test_manual_wave_start_cancels_pending_automatic_start() -> void:
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	wave_manager.wave_config_overrides = [
		_create_wave_config(1, 1, GOBLIN_DATA),
		_create_wave_config(2, 1, GOBLIN_DATA)
	]
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	wave_manager.set_auto_waves_enabled(true)
	_complete_wave_for_test(game)
	assert_bool(wave_manager._automatic_start_timers.has(2)).is_true()
	var stale_token: int = wave_manager._automatic_start_tokens[2]
	var stale_generation: int = wave_manager._automatic_schedule_generation
	var stale_timer: Timer = wave_manager._automatic_start_timers[2]
	for _second in range(int(WaveManager.AUTO_WAVE_DELAY_SECONDS) - 1):
		wave_manager._on_automatic_start_timeout(
			2,
			stale_token,
			stale_generation,
			stale_timer
		)
	assert_int(wave_manager._automatic_start_remaining[2]).is_equal(1)

	wave_manager.start_wave(WaveManager.StartReason.MANUAL)

	assert_bool(wave_manager._automatic_start_timers.has(2)).is_false()
	assert_int(wave_manager.next_wave_number).is_equal(3)
	assert_int(wave_manager.active_waves.size()).is_equal(1)
	assert_int(
		_find_wave_summary(wave_manager.get_active_wave_summaries(), 2)["start_reason"]
	).is_equal(WaveManager.StartReason.MANUAL)
	wave_manager._on_automatic_start_timeout(
		2,
		stale_token,
		stale_generation,
		stale_timer
	)
	assert_int(wave_manager.next_wave_number).is_equal(3)


func test_pausing_freezes_pending_automatic_wave_countdown() -> void:
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	wave_manager.wave_config_overrides = [
		_create_wave_config(1, 1, GOBLIN_DATA),
		_create_wave_config(2, 1, GOBLIN_DATA)
	]
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	wave_manager.set_auto_waves_enabled(true)
	_complete_wave_for_test(game)
	var timer: Timer = wave_manager._automatic_start_timers[2]
	assert_int(wave_manager._automatic_start_remaining[2]).is_equal(10)

	GameSpeedManager.set_paused(true)
	await get_tree().process_frame
	assert_bool(get_tree().paused).is_true()
	assert_bool(timer.is_stopped()).is_false()
	assert_int(wave_manager._automatic_start_remaining[2]).is_equal(10)
	GameSpeedManager.set_paused(false)
	assert_bool(get_tree().paused).is_false()


func test_game_speed_and_pause_preserve_selected_simulation_speed() -> void:
	assert_bool(GameSpeedManager.set_simulation_speed(2.0)).is_true()
	assert_float(Engine.time_scale).is_equal(2.0)
	GameSpeedManager.set_paused(true)
	assert_bool(get_tree().paused).is_true()
	assert_bool(GameSpeedManager.set_simulation_speed(0.5)).is_true()
	assert_float(Engine.time_scale).is_equal(0.5)
	assert_bool(get_tree().paused).is_true()
	GameSpeedManager.set_paused(false)
	assert_bool(get_tree().paused).is_false()
	assert_float(GameSpeedManager.simulation_speed).is_equal(0.5)


func test_game_run_continue_keeps_current_gold() -> void:
	var game = _make_game()
	GoldManager.add_gold(73)
	game._show_end_run_confirmation()
	assert_bool(get_tree().paused).is_true()

	game._continue_run()

	assert_bool(get_tree().paused).is_false()
	assert_int(GoldManager.run_gold).is_equal(
		GoldManager.STARTING_RUN_GOLD + 73
	)


func test_boss_wave_schedule_reports_tier_and_count_milestones() -> void:
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	assert_bool(wave_manager.get_boss_wave_requirements(9).is_empty()).is_true()
	var requirements := wave_manager.get_boss_wave_requirements(10)
	assert_int(requirements["tier"]).is_equal(1)
	assert_int(requirements["count"]).is_equal(1)
	requirements = wave_manager.get_boss_wave_requirements(50)
	assert_int(requirements["tier"]).is_equal(2)
	assert_int(requirements["count"]).is_equal(1)
	requirements = wave_manager.get_boss_wave_requirements(100)
	assert_int(requirements["tier"]).is_equal(3)
	assert_int(requirements["count"]).is_equal(1)
	requirements = wave_manager.get_boss_wave_requirements(150)
	assert_int(requirements["tier"]).is_equal(3)
	assert_int(requirements["count"]).is_equal(2)


func test_wave_progress_waits_for_all_living_enemies_to_leave() -> void:
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

	assert_int(wave_manager.get_active_enemy_count_for_wave(1)).is_equal(2)
	assert_bool(wave_manager.completed_wave_numbers.has(1)).is_false()

	for enemy_node in game.get_node("Enemies").get_children():
		(enemy_node as Enemy).die()
	await get_tree().process_frame

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


func test_enemy_types_have_the_configured_essence_points() -> void:
	var expected := {
		"goblin": 1,
		"kobold": 1,
		"orc": 2,
		"skeleton": 3,
		"troll": 5
	}
	for data in _all_enemy_data():
		assert_int(data.essence_points).is_equal(expected[String(data.enemy_id)])


func test_each_enemy_death_awards_its_essence_points_exactly_once() -> void:
	_use_temporary_profile()
	var balance_before := CrystalInventory.get_essence_balance()
	var running_total := 0
	for data in _all_enemy_data():
		var deterministic_data := data.duplicate(true) as EnemyData
		deterministic_data.can_resurrect = false
		var enemy := _make_enemy(deterministic_data)
		enemy.die()
		enemy.die()
		enemy.take_damage(1)
		running_total += data.essence_points
		assert_int(CrystalInventory.get_essence_points()).is_equal(running_total)

	assert_int(running_total).is_equal(12)
	assert_int(CrystalInventory.get_essence_balance()).is_equal(balance_before)


func test_enemy_leaving_the_game_without_dying_awards_no_essence_points() -> void:
	_use_temporary_profile()
	var enemy := _make_enemy(TROLL_DATA)
	enemy._mark_inactive()
	enemy.queue_free()
	await get_tree().process_frame

	assert_int(CrystalInventory.get_essence_points()).is_equal(0)


func test_skeleton_resurrection_awards_essence_points_only_on_final_death() -> void:
	_use_temporary_profile()
	var deterministic_skeleton := SKELETON_DATA.duplicate(true) as EnemyData
	deterministic_skeleton.resurrection_chance = 1.0
	var enemy := _make_enemy(deterministic_skeleton, 100)

	enemy.take_damage(100)
	assert_int(enemy.resurrection_count).is_equal(1)
	assert_int(CrystalInventory.get_essence_points()).is_equal(0)

	enemy.take_damage(100)
	enemy.die()
	assert_bool(enemy.is_dead).is_true()
	assert_int(CrystalInventory.get_essence_points()).is_equal(3)


func test_essence_thresholds_grow_five_percent_rounded_up() -> void:
	assert_int(CrystalInventory.get_essence_threshold()).is_equal(100)
	var threshold := 100
	var expected: Array[int] = [105, 111, 117, 123, 130]
	for expected_threshold in expected:
		threshold = CrystalInventory.get_next_essence_threshold(threshold)
		assert_int(threshold).is_equal(expected_threshold)


func test_essence_points_carry_overflow_and_handle_multiple_thresholds() -> void:
	_use_temporary_profile()
	var awards: Array[int] = []
	CrystalInventory.essence_awarded.connect(
		func(amount: int) -> void: awards.append(amount)
	)
	var balance_before := CrystalInventory.get_essence_balance()

	assert_int(CrystalInventory.add_essence_points(98)).is_equal(0)
	assert_int(CrystalInventory.get_essence_balance()).is_equal(balance_before)
	assert_int(CrystalInventory.add_essence_points(5)).is_equal(1)
	assert_int(CrystalInventory.get_essence_points()).is_equal(3)
	assert_int(CrystalInventory.get_essence_threshold()).is_equal(105)
	assert_int(CrystalInventory.get_essence_balance()).is_equal(balance_before + 1)

	# 3 + 342 crosses the 105, 111 and 117 thresholds in a single award.
	assert_int(CrystalInventory.add_essence_points(102 + 111 + 117 + 12)).is_equal(3)
	assert_int(CrystalInventory.get_essence_points()).is_equal(12)
	assert_int(CrystalInventory.get_essence_threshold()).is_equal(123)
	assert_int(CrystalInventory.get_essence_balance()).is_equal(balance_before + 4)
	assert_array(awards).is_equal([1, 3])
	assert_int(CrystalInventory.add_essence_points(0)).is_equal(0)
	assert_int(CrystalInventory.add_essence_points(-4)).is_equal(0)


func test_hud_shows_essence_point_progress_and_updates_immediately() -> void:
	_use_temporary_profile()
	var game = _make_game()
	var progress_label := game.get_node("HUD/EssenceProgressLabel") as Label
	assert_str(progress_label.text).is_equal("Essence points: 0 / 100")

	CrystalInventory.add_essence_points(73)
	assert_str(progress_label.text).is_equal("Essence points: 73 / 100")
	CrystalInventory.add_essence_points(30)
	assert_str(progress_label.text).is_equal("Essence points: 3 / 105")
	assert_str((game.get_node("HUD/EssenceLabel") as Label).text).is_equal(
		"Essence: %d" % CrystalInventory.get_essence_balance()
	)


func test_enemy_hp_and_speed_scale_ten_and_half_percent_per_wave() -> void:
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	for data in _all_enemy_data():
		assert_int(wave_manager.get_enemy_hp_for_wave(1, data.base_hp)).is_equal(
			data.base_hp
		)
		assert_float(
			wave_manager.get_enemy_speed_for_wave(1, data.base_speed)
		).is_equal(data.base_speed)
	assert_int(wave_manager.get_enemy_hp_for_wave(2, 100)).is_equal(110)
	assert_int(wave_manager.get_enemy_hp_for_wave(3, 100)).is_equal(121)
	assert_int(wave_manager.get_enemy_hp_for_wave(11, 100)).is_equal(
		roundi(100.0 * pow(1.10, 10))
	)
	assert_float(wave_manager.get_enemy_speed_for_wave(2, 100.0)).is_equal_approx(
		100.5,
		0.0001
	)
	assert_float(wave_manager.get_enemy_speed_for_wave(21, 100.0)).is_equal_approx(
		110.0,
		0.0001
	)


func test_spawned_enemies_use_wave_scaling_once_and_keep_slows_separate() -> void:
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	wave_manager.wave_config_overrides = [
		_create_wave_config(1, 1, GOBLIN_DATA),
		_create_wave_config(2, 1, GOBLIN_DATA)
	]
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)

	var enemies: Array[Node] = game.get_node("Enemies").get_children()
	var wave_one_enemy := enemies[0] as Enemy
	var wave_two_enemy := enemies[1] as Enemy
	assert_int(wave_one_enemy.max_hp).is_equal(GOBLIN_DATA.base_hp)
	assert_float(wave_one_enemy.speed).is_equal(GOBLIN_DATA.base_speed)
	assert_int(wave_two_enemy.max_hp).is_equal(110)
	assert_int(wave_two_enemy.hp).is_equal(110)
	assert_float(wave_two_enemy.speed).is_equal_approx(100.5, 0.0001)

	wave_two_enemy.set_movement_slow(7, 0.2)
	assert_float(wave_two_enemy.speed).is_equal_approx(100.5, 0.0001)
	assert_float(wave_two_enemy.effective_speed).is_equal_approx(80.4, 0.0001)
	wave_two_enemy.take_damage(10)
	assert_int(wave_two_enemy.hp).is_equal(100)
	assert_int(wave_two_enemy.max_hp).is_equal(110)


func test_countdown_waits_for_the_spawn_queue_and_starts_exactly_once() -> void:
	_use_temporary_profile()
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	wave_manager.wave_config_overrides = [
		_create_wave_config(1, 3, GOBLIN_DATA),
		_create_wave_config(2, 1, GOBLIN_DATA)
	]
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	wave_manager.set_auto_waves_enabled(true)
	var wave: ActiveWave = wave_manager.active_waves[0]
	assert_int(wave_manager.get_remaining_spawn_count(wave)).is_equal(2)

	# Killing the only living enemy must not count while two are still queued.
	(game.get_node("Enemies").get_child(0) as Enemy).die()
	assert_int(wave_manager.get_active_enemy_count_for_wave(1)).is_equal(0)
	assert_bool(wave_manager._automatic_start_timers.is_empty()).is_true()
	assert_bool(wave_manager.completed_wave_numbers.has(1)).is_false()

	wave_manager._process(wave_manager.spawn_interval)
	var second := wave_manager.active_waves[0].active_enemies.values()[0] as Enemy
	second.die()
	assert_int(wave_manager.get_remaining_spawn_count(wave)).is_equal(1)
	assert_bool(wave_manager._automatic_start_timers.is_empty()).is_true()

	# The last enemy has spawned, but it is still alive, so no countdown yet.
	wave_manager._process(wave_manager.spawn_interval)
	assert_int(wave_manager.get_remaining_spawn_count(wave)).is_equal(0)
	assert_int(wave_manager.get_active_enemy_count_for_wave(1)).is_equal(1)
	assert_bool(wave_manager._automatic_start_timers.is_empty()).is_true()

	(wave_manager.active_waves[0].active_enemies.values()[0] as Enemy).die()
	assert_bool(wave_manager.completed_wave_numbers.has(1)).is_true()
	assert_int(wave_manager._automatic_start_timers.size()).is_equal(1)
	assert_int(wave_manager._automatic_start_remaining[2]).is_equal(10)
	assert_str(game.wave_countdown_label.text).is_equal("Next wave in: 10")

	var timer: Timer = wave_manager._automatic_start_timers[2]
	wave_manager._try_complete_wave(wave)
	wave_manager._schedule_automatic_start(2)
	assert_int(wave_manager._automatic_start_timers.size()).is_equal(1)
	assert_bool(wave_manager._automatic_start_timers[2] == timer).is_true()
	# Toggling auto-waves cancels the pending timer and schedules a single new one.
	wave_manager.set_auto_waves_enabled(false)
	assert_bool(wave_manager._automatic_start_timers.is_empty()).is_true()
	wave_manager.set_auto_waves_enabled(true)
	assert_int(wave_manager._automatic_start_timers.size()).is_equal(1)
	var timer_count := 0
	for child in wave_manager.get_children():
		if child is Timer and not child.is_queued_for_deletion():
			timer_count += 1
	assert_int(timer_count).is_equal(1)


func test_countdown_pauses_and_resumes_and_empty_waves_do_not_get_stuck() -> void:
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	wave_manager.wave_config_overrides = [
		_create_wave_config(1, 0, GOBLIN_DATA),
		_create_wave_config(2, 1, GOBLIN_DATA)
	]
	wave_manager.set_auto_waves_enabled(true)
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	assert_bool(wave_manager.completed_wave_numbers.has(1)).is_true()
	assert_bool(wave_manager._automatic_start_timers.has(2)).is_true()

	var timer: Timer = wave_manager._automatic_start_timers[2]
	GameSpeedManager.set_paused(true)
	await get_tree().process_frame
	var paused_time_left := timer.time_left
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(timer.time_left).is_equal(paused_time_left)

	GameSpeedManager.set_paused(false)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(timer.time_left).is_less(paused_time_left)


func test_manual_start_cancels_countdown_and_never_starts_a_wave_twice() -> void:
	_use_temporary_profile()
	var game = _make_game()
	var wave_manager := game.get_node("WaveManager") as WaveManager
	wave_manager.wave_config_overrides = [
		_create_wave_config(1, 1, GOBLIN_DATA),
		_create_wave_config(2, 1, GOBLIN_DATA)
	]
	wave_manager.set_auto_waves_enabled(true)
	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	(game.get_node("Enemies").get_child(0) as Enemy).die()
	assert_bool(wave_manager._automatic_start_timers.has(2)).is_true()

	wave_manager.start_wave(WaveManager.StartReason.MANUAL)
	assert_bool(wave_manager._automatic_start_timers.is_empty()).is_true()
	assert_int(wave_manager.next_wave_number).is_equal(3)
	assert_bool(wave_manager._started_wave_numbers.has(2)).is_true()
	assert_int(wave_manager.active_waves.size()).is_equal(1)
	assert_int(
		_find_wave_summary(wave_manager.get_active_wave_summaries(), 2)["start_reason"]
	).is_equal(WaveManager.StartReason.MANUAL)


func _all_enemy_data() -> Array[EnemyData]:
	var all_data: Array[EnemyData] = [
		GOBLIN_DATA,
		preload("res://enemies/Kobold.tres"),
		preload("res://enemies/Orc.tres"),
		SKELETON_DATA,
		TROLL_DATA
	]
	return all_data


func _use_temporary_profile() -> void:
	_temporary_profile_directory = "user://gdunit-essence-tests/%d-%d" % [
		Time.get_ticks_usec(),
		randi()
	]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_temporary_profile_directory)
	)
	CrystalInventory.profile_storage_directory = _temporary_profile_directory
	assert_bool(CrystalInventory.load_profile()).is_true()


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


func _add_test_tower(game: Node, position: Vector2) -> Tower:
	var tower := TOWER_SCENE.instantiate() as Tower
	game.add_child(tower)
	tower.global_position = position
	return tower


func _make_game():
	_ensure_awakened_for_test()
	var game = GAME_SCENE.instantiate()
	_track_node(game)
	game.wave_manager.set_auto_waves_enabled(false)
	return game


func _ensure_awakened_for_test() -> void:
	if CrystalInventory.is_crystal_inventory_unlocked():
		return
	assert_bool(CrystalInventory.add_essence(1)).is_true()
	assert_bool(CrystalInventory.purchase_skill_node(&"A")).is_true()


func _remove_temporary_profile() -> void:
	if _temporary_profile_directory.is_empty():
		return
	var absolute_directory := ProjectSettings.globalize_path(
		_temporary_profile_directory
	)
	for file_name in [
		"player_profile.json",
		"player_profile.tmp",
		"player_profile.bak",
		"player_profile.bak.tmp"
	]:
		var file_path := _temporary_profile_directory.path_join(file_name)
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	DirAccess.remove_absolute(absolute_directory)
	_temporary_profile_directory = ""


func _remove_test_profile_directory(directory: String) -> void:
	for file_name in [
		"player_profile.json",
		"player_profile.tmp",
		"player_profile.bak",
		"player_profile.bak.tmp"
	]:
		var file_path := directory.path_join(file_name)
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))


func _contains_owned_crystal(
	entries: Array[Dictionary],
	crystal_id: String,
	level: int,
	quantity: int
) -> bool:
	for entry in entries:
		var definition := entry["definition"] as CrystalData
		if (
			String(definition.crystal_id) == crystal_id
			and int(entry["level"]) == level
			and int(entry["quantity"]) == quantity
		):
			return true
	return false


func _make_mouse_button_event(
	position: Vector2,
	is_pressed: bool = true
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = is_pressed
	return event


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


func _complete_wave_for_test(game: Node) -> void:
	for enemy_node in game.get_node("Enemies").get_children():
		if enemy_node is Enemy:
			enemy_node.die()


func _find_wave_summary(summaries: Array[Dictionary], wave_number: int) -> Dictionary:
	for summary in summaries:
		if int(summary["wave_number"]) == wave_number:
			return summary
	return {}


func _await_scene_change() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
