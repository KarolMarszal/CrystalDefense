class_name BossData
extends Resource

enum Ability {
	GOBLIN_CHIEF,
	KOBOLD_CHIEF,
	ORC_CHIEF,
	TROLL,
	SKELETON,
	GHOUL,
	SPIDER_MATRON,
	SNAKE
}

@export var boss_id: StringName = &""
@export var display_name: String = ""
@export var visual_source: EnemyData
@export var base_hp: int = 1
@export var base_speed: float = 1.0
@export_range(0.0, 1.0, 0.001) var hp_growth_per_wave: float = 0.0
@export_range(0.0, 1.0, 0.001) var speed_growth_per_wave: float = 0.0
@export_range(1, 10, 1) var trophy_capacity: int = 1
@export var base_gold_reward: int = 0
@export var base_essence_reward: int = 0
@export var ability: Ability = Ability.GOBLIN_CHIEF
@export var summon_enemy_data: EnemyData
@export_range(0.0, 1000.0, 1.0) var ability_radius: float = 0.0
@export_range(0.1, 60.0, 0.1) var ability_interval: float = 0.0
@export_range(0.1, 30.0, 0.1) var ability_duration: float = 0.0
@export_range(0.0, 5.0, 0.01) var ability_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.01) var secondary_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.01) var enrage_multiplier: float = 1.0
@export_range(0.0, 1000.0, 1.0) var enraged_ability_radius: float = 0.0
@export_range(0.0, 60.0, 0.1) var enraged_ability_interval: float = 0.0
@export_range(0.0, 1000.0, 1.0) var summon_spawn_radius: float = 0.0
@export_range(0.0, 60.0, 0.1) var tower_debuff_duration: float = 0.0
@export_range(0.0, 1.0, 0.01) var damage_reduction: float = 0.0
@export_range(0.0, 1.0, 0.001) var regeneration_fraction_per_second: float = 0.0
@export_range(0.0, 1.0, 0.001) var low_hp_regeneration_fraction_per_second: float = 0.0
@export_range(0.0, 1.0, 0.01) var skeleton_threshold_heal_fraction: float = 0.0
@export_range(1, 20, 1) var summon_count: int = 1
@export_range(1, 50, 1) var maximum_living_summons: int = 1
@export var poison_immune: bool = false
