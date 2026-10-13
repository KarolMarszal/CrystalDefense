class_name BossWaveSchedule
extends RefCounted

const TIER_1_POOL: Array[BossData] = [
	preload("res://enemies/bosses/GoblinChief.tres"),
	preload("res://enemies/bosses/KoboldChief.tres"),
	preload("res://enemies/bosses/OrcChief.tres"),
	preload("res://enemies/bosses/TrollBoss.tres"),
	preload("res://enemies/bosses/SkeletonBoss.tres"),
	preload("res://enemies/bosses/Ghoul.tres"),
	preload("res://enemies/bosses/SpiderMatron.tres"),
	preload("res://enemies/bosses/Snake.tres")
]
const TIER_2_POOL: Array = []
const TIER_3_POOL: Array = []
static var tier_one_test_waves_enabled: bool = false
static var kobold_chief_test_hp_override_enabled: bool = true
const KOBOLD_CHIEF_TEST_HP_MULTIPLIER: float = 5.0
const TIER_1_TEST_WAVE_BOSSES: Dictionary = {
	1: preload("res://enemies/bosses/SpiderMatron.tres")
}
const SPIDER_TEST_WAVE_ENEMIES: Dictionary = {
	2: preload("res://enemies/Spider.tres")
}
const TIER_1_REGULAR_ENEMIES: Dictionary = {
	&"goblin_chief": preload("res://enemies/Goblin.tres"),
	&"kobold_chief": preload("res://enemies/Kobold.tres"),
	&"orc_chief": preload("res://enemies/Orc.tres"),
	&"troll_boss": preload("res://enemies/Troll.tres"),
	&"skeleton_boss": preload("res://enemies/Skeleton.tres"),
	&"ghoul": preload("res://enemies/Skeleton.tres"),
	&"spider_matron": null,
	&"snake": null
}


static func get_requirements(wave_number: int) -> Dictionary:
	if wave_number < 50 or wave_number % 10 != 0:
		return {}

	if wave_number >= 150:
		return {"tier": 3, "count": 2}
	if wave_number >= 100:
		return {"tier": 3, "count": 1}
	if wave_number >= 50:
		return {"tier": 2, "count": 1}
	return {"tier": 1, "count": 1}


static func get_boss_pool(tier: int) -> Array[BossData]:
	var pool: Array[BossData] = []
	match tier:
		1:
			pool.append_array(TIER_1_POOL)
		2:
			pool.append_array(TIER_2_POOL)
		3:
			pool.append_array(TIER_3_POOL)
	return pool


static func get_test_wave_boss(wave_number: int) -> BossData:
	if not tier_one_test_waves_enabled:
		return null
	return TIER_1_TEST_WAVE_BOSSES.get(wave_number) as BossData


static func get_test_wave_enemy_data(wave_number: int) -> EnemyData:
	if not tier_one_test_waves_enabled:
		return null
	return SPIDER_TEST_WAVE_ENEMIES.get(wave_number) as EnemyData


static func get_test_boss_hp_multiplier(boss: BossData, wave_number: int) -> float:
	if (
		not tier_one_test_waves_enabled
		or not kobold_chief_test_hp_override_enabled
		or boss == null
		or boss.boss_id != &"kobold_chief"
		or get_test_wave_boss(wave_number) != boss
	):
		return 1.0
	return KOBOLD_CHIEF_TEST_HP_MULTIPLIER


static func get_regular_enemy_data(boss: BossData) -> EnemyData:
	if boss == null:
		return null
	return TIER_1_REGULAR_ENEMIES.get(boss.boss_id) as EnemyData
