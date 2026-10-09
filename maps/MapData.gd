class_name MapData
extends Resource

@export var map_id: StringName = &""
@export var display_name: String = ""
@export var enemy_entries: Array[MapEnemyEntry] = []


func is_enemy_available(enemy_data: EnemyData) -> bool:
	return get_enemy_weight_multiplier(enemy_data) > 0.0


func get_enemy_weight_multiplier(enemy_data: EnemyData) -> float:
	for entry in enemy_entries:
		if entry != null and entry.enemy_data == enemy_data:
			return entry.weight_multiplier
	return 0.0


func get_deterministic_signature() -> String:
	var parts := PackedStringArray([String(map_id)])
	for entry in enemy_entries:
		if entry == null or entry.enemy_data == null:
			parts.append("invalid")
			continue
		parts.append(
			"%s=%.4f"
			% [entry.enemy_data.enemy_id, entry.weight_multiplier]
		)
	return "|".join(parts)
