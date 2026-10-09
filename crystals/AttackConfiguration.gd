class_name AttackConfiguration
extends RefCounted

enum Stat {
	DAMAGE,
	ATTACK_SPEED,
	RANGE,
	SLOW_FRACTION,
	SLOW_DURATION,
	BLEED_MAX_HP_FRACTION_PER_SECOND,
	BLEED_DURATION
}

var attack_behavior: CrystalData.AttackBehavior = CrystalData.AttackBehavior.PROJECTILE
var damage: float = 0.0
var attack_speed: float = 0.0
var attack_range: float = 0.0
var slow_fraction: float = 0.0
var slow_duration: float = 0.0
var bleed_max_hp_fraction_per_second: float = 0.0
var bleed_duration: float = 0.0


func get_stat(stat: Stat) -> float:
	match stat:
		Stat.DAMAGE:
			return damage
		Stat.ATTACK_SPEED:
			return attack_speed
		Stat.RANGE:
			return attack_range
		Stat.SLOW_FRACTION:
			return slow_fraction
		Stat.SLOW_DURATION:
			return slow_duration
		Stat.BLEED_MAX_HP_FRACTION_PER_SECOND:
			return bleed_max_hp_fraction_per_second
		Stat.BLEED_DURATION:
			return bleed_duration
	return 0.0


func set_stat(stat: Stat, value: float) -> void:
	match stat:
		Stat.DAMAGE:
			damage = maxf(value, 0.0)
		Stat.ATTACK_SPEED:
			attack_speed = maxf(value, 0.0)
		Stat.RANGE:
			attack_range = maxf(value, 0.0)
		Stat.SLOW_FRACTION:
			slow_fraction = clampf(value, 0.0, 1.0)
		Stat.SLOW_DURATION:
			slow_duration = maxf(value, 0.0)
		Stat.BLEED_MAX_HP_FRACTION_PER_SECOND:
			bleed_max_hp_fraction_per_second = maxf(value, 0.0)
		Stat.BLEED_DURATION:
			bleed_duration = maxf(value, 0.0)
