class_name CrystalUpgradeMapping
extends Resource

enum Operation {
	ADDITIVE,
	MULTIPLICATIVE
}

@export_range(0, 2, 1) var tower_upgrade_slot: int = 0
@export var display_name: String = ""
@export var affected_stat: AttackConfiguration.Stat = AttackConfiguration.Stat.DAMAGE
@export var operation: Operation = Operation.MULTIPLICATIVE
@export var amount: float = 1.2


func apply(configuration: AttackConfiguration, tower_upgrade_level: int) -> void:
	if configuration == null or tower_upgrade_level <= 0:
		return

	var current_value := configuration.get_stat(affected_stat)
	match operation:
		Operation.ADDITIVE:
			current_value += amount * tower_upgrade_level
		Operation.MULTIPLICATIVE:
			current_value *= pow(amount, tower_upgrade_level)
	configuration.set_stat(affected_stat, current_value)
