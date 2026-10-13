class_name CrystalData
extends Resource

const FIRE_AREA_DAMAGE_FRACTION: float = 0.5
const FIRE_AREA_DAMAGE_RADIUS: float = 48.0

enum AttackBehavior {
	PROJECTILE,
	AURA,
	PROJECTILE_WITH_EFFECT
}

@export var crystal_id: StringName = &""
@export var display_name: String = ""
@export var visual_texture: Texture2D
@export var damage: float = 0.0
@export var attack_speed: float = 0.0
@export var attack_range: float = 180.0
@export var attack_behavior: AttackBehavior = AttackBehavior.PROJECTILE
@export_range(1.0, 10.0, 0.01) var crystal_level_growth: float = 2.0
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
		var effect_ids: Array[StringName] = [
			&"damage_upgrade_effectiveness",
			&"speed_upgrade_effectiveness",
			&"range_upgrade_effectiveness"
		]
		var effectiveness := 1.0 + CrystalInventory.get_skill_effect_value(
			effect_ids[mapping.tower_upgrade_slot]
		)
		mapping.apply(
			configuration,
			tower_upgrade_levels[mapping.tower_upgrade_slot],
			effectiveness
		)

	_apply_skill_modifiers(configuration)
	configuration.area_damage_fraction *= level_scale
	configuration.area_damage_radius *= level_scale
	return configuration


func _apply_skill_modifiers(configuration: AttackConfiguration) -> void:
	var crystal_key := String(crystal_id)
	var skill_damage_multiplier := (
		1.0 + CrystalInventory.get_skill_effect_value(&"crystal_damage_bonus")
	)
	configuration.damage *= skill_damage_multiplier

	if crystal_key == "rapid_fire" or crystal_key == "sniper":
		configuration.damage *= 1.0 + CrystalInventory.get_skill_effect_value(
			&"rapid_sniper_damage_bonus"
		)
	if crystal_key == "fire":
		configuration.damage *= 1.0 + CrystalInventory.get_skill_effect_value(
			&"fire_damage_bonus"
		)
		if CrystalInventory.get_skill_effect_value(&"unlock_fire_area") > 0.0:
			configuration.area_damage_fraction = FIRE_AREA_DAMAGE_FRACTION
			configuration.area_damage_radius = FIRE_AREA_DAMAGE_RADIUS

	if slow_fraction > 0.0:
		var slow_bonus := 0.0
		for effect_id in [
			&"slow_strength_tier_1",
			&"slow_strength_tier_2",
			&"slow_strength_tier_3"
		]:
			slow_bonus = maxf(
				slow_bonus,
				CrystalInventory.get_skill_effect_value(effect_id)
			)
		configuration.slow_fraction = minf(
			configuration.slow_fraction + slow_bonus,
			1.0
		)
		configuration.slow_fraction = minf(
			configuration.slow_fraction * skill_damage_multiplier,
			1.0
		)

	if configuration.bleed_max_hp_fraction_per_second > 0.0:
		var bleed_bonus := 0.0
		for effect_id in [
			&"bleed_strength_tier_1",
			&"bleed_strength_tier_2",
			&"bleed_strength_tier_3"
		]:
			bleed_bonus = maxf(
				bleed_bonus,
				CrystalInventory.get_skill_effect_value(effect_id)
			)
		configuration.bleed_max_hp_fraction_per_second = (
			configuration.bleed_max_hp_fraction_per_second + bleed_bonus
		) * skill_damage_multiplier
