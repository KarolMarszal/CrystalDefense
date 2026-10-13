class_name BossAbilityDebug
extends RefCounted

static var enabled: bool = true


static func log(
	boss: Node,
	ability: String,
	event: String,
	details: String = ""
) -> bool:
	if not enabled or not is_instance_valid(boss):
		return false
	var boss_data := boss.get("boss_data") as BossData
	if boss_data == null:
		return false

	var message := (
		"[BOSS_ABILITY] wave=%d boss=%s(%s#%d) ability=%s event=%s"
		% [
			boss.get("wave_number"),
			boss_data.display_name,
			boss_data.boss_id,
			boss.get_instance_id(),
			ability,
			event
		]
	)
	if not details.is_empty():
		message += " " + details
	print(message)
	return true


static func log_damage(
	target_name: String,
	damage: int,
	hit: int,
	hp_before: int,
	hp_after: int
) -> void:
	if not enabled:
		return
	print(
		"[DAMAGE] target=%s damage=%d hit=%d armour=%d hp_before=%d hp_after=%d"
		% [target_name, damage, hit, hit - damage, hp_before, hp_after]
	)


static func log_external(
	ability: String,
	event: String,
	details: String,
	context: String = ""
) -> void:
	if not enabled:
		return
	print(
		"[BOSS_ABILITY] %sability=%s event=%s %s"
		% [context, ability, event, details]
	)
