class_name CrystalData
extends Resource

enum AttackBehavior {
	PROJECTILE,
	AURA,
	PROJECTILE_WITH_EFFECT
}

@export var crystal_id: StringName = &""
@export var display_name: String = ""
@export var visual_texture: Texture2D
@export var damage: int = 0
@export var attack_speed: float = 0.0
@export var attack_range: float = 180.0
@export var attack_behavior: AttackBehavior = AttackBehavior.PROJECTILE
@export_range(1.0, 10.0, 0.01) var crystal_level_growth: float = 1.1
@export_range(0.0, 1.0, 0.01) var slow_fraction: float = 0.0
@export var slow_duration: float = 0.0
@export_range(0.0, 1.0, 0.001) var bleed_max_hp_fraction_per_second: float = 0.0
@export_range(0.0, 600.0, 0.5) var bleed_duration: float = 0.0
@export var tower_upgrade_mappings: Array[CrystalUpgradeMapping] = []


func create_attack_configuration(
	crystal_level: int,
	tower_upgrade_levels: Array[int]
) -> AttackConfiguration:
	var configuration := AttackConfiguration.new()
	configuration.attack_behavior = attack_behavior
	configuration.damage = damage
	configuration.attack_speed = attack_speed
	configuration.attack_range = attack_range
	configuration.slow_fraction = slow_fraction
	configuration.slow_duration = slow_duration
	configuration.bleed_max_hp_fraction_per_second = (
		bleed_max_hp_fraction_per_second
	)
	configuration.bleed_duration = bleed_duration

	var level_scale := pow(crystal_level_growth, maxi(crystal_level - 1, 0))
	for stat in AttackConfiguration.Stat.values():
		configuration.set_stat(stat, configuration.get_stat(stat) * level_scale)

	for mapping in tower_upgrade_mappings:
		if mapping == null or mapping.tower_upgrade_slot >= tower_upgrade_levels.size():
			continue
		mapping.apply(
			configuration,
			tower_upgrade_levels[mapping.tower_upgrade_slot]
		)

	return configuration
