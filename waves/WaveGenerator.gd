class_name WaveGenerator
extends Node

@export var enemy_catalog: Array[EnemyData] = []
@export var archetypes: Array[WaveArchetype] = []
@export_range(1, 100000, 1) var base_budget: int = 10
@export_range(0, 1000, 1) var budget_growth: int = 4
@export_range(1, 10000, 1) var maximum_generation_attempts: int = 1000
@export_range(1, 20, 1) var recent_wave_history_size: int = 3
@export_range(1, 10, 1) var maximum_preferred_archetype_repetition: int = 1
@export_range(0.0, 1.0, 0.05) var archetype_repetition_penalty: float = 0.35
@export_range(0.0, 1.0, 0.05) var dominant_enemy_threshold: float = 0.6
@export_range(0.0, 1.0, 0.05) var enemy_repetition_penalty: float = 0.65

var recent_wave_history: Array[Dictionary] = []


func get_difficulty_budget(wave_number: int) -> int:
	return maxi(base_budget + (wave_number - 1) * budget_growth, 0)


func reset_history() -> void:
	recent_wave_history.clear()


func generate_wave(
	wave_number: int,
	run_seed: int,
	log_generation: bool = false,
	commit_to_history: bool = false,
	map_data: MapData = null
) -> WaveConfig:
	var config := WaveConfig.new()
	config.wave_number = wave_number

	var budget := get_difficulty_budget(wave_number)
	var remaining_budget := budget
	var rng := RandomNumberGenerator.new()
	var map_signature := "default"
	if map_data != null:
		map_signature = map_data.get_deterministic_signature()
	rng.seed = hash("%d:%d:%s" % [run_seed, wave_number, map_signature])
	var archetype := _select_archetype(rng)
	if archetype == null:
		push_error("WaveGenerator requires at least one valid WaveArchetype.")
		config.archetype_id = &"STANDARD"
		return config
	config.archetype_id = archetype.archetype_id

	var enemy_repetition_modifiers: Dictionary = {}
	for _attempt in range(maximum_generation_attempts):
		var eligible_enemies := _get_eligible_enemies(
			wave_number,
			remaining_budget,
			map_data,
			config
		)
		if eligible_enemies.is_empty():
			break

		var selected_enemy := _select_weighted_enemy(
			eligible_enemies,
			archetype,
			config,
			enemy_repetition_modifiers,
			map_data,
			rng
		)
		if selected_enemy == null:
			break

		_add_enemy_to_group(config, selected_enemy)
		remaining_budget -= selected_enemy.difficulty_cost

	if commit_to_history:
		_record_wave(config)

	return config


func generate_matching_enemy_wave(
	wave_number: int,
	enemy_data: EnemyData,
	archetype_id: StringName
) -> WaveConfig:
	var config := WaveConfig.new()
	config.wave_number = wave_number
	config.archetype_id = archetype_id
	if enemy_data == null:
		return config
	if enemy_data.difficulty_cost <= 0:
		push_error(
			"Cannot generate a matching-enemy wave with a non-positive cost: %s"
			% enemy_data.resource_path
		)
		return config

	var remaining_budget := get_difficulty_budget(wave_number)
	var attempts := 0
	while (
		remaining_budget >= enemy_data.difficulty_cost
		and attempts < maximum_generation_attempts
	):
		_add_enemy_to_group(config, enemy_data)
		remaining_budget -= enemy_data.difficulty_cost
		attempts += 1
	if attempts >= maximum_generation_attempts and remaining_budget >= enemy_data.difficulty_cost:
		push_warning(
			"Matching-enemy wave generation reached its attempt limit on wave %d."
			% wave_number
		)
	return config


func _select_archetype(rng: RandomNumberGenerator) -> WaveArchetype:
	var total_weight := 0.0
	for archetype in archetypes:
		if archetype != null and archetype.selection_weight > 0.0:
			total_weight += (
				archetype.selection_weight
				* _get_archetype_repetition_modifier(archetype)
			)

	if total_weight <= 0.0:
		return null

	var selection := rng.randf() * total_weight
	for archetype in archetypes:
		if archetype == null or archetype.selection_weight <= 0.0:
			continue
		selection -= (
			archetype.selection_weight
			* _get_archetype_repetition_modifier(archetype)
		)
		if selection < 0.0:
			return archetype

	for index in range(archetypes.size() - 1, -1, -1):
		var fallback := archetypes[index]
		if fallback != null and fallback.selection_weight > 0.0:
			return fallback

	return null


func _get_archetype_repetition_modifier(archetype: WaveArchetype) -> float:
	var consecutive_count := 0
	for history_entry in recent_wave_history:
		if history_entry["archetype_id"] != archetype.archetype_id:
			break
		consecutive_count += 1

	var penalized_repeats := maxi(
		consecutive_count - maximum_preferred_archetype_repetition + 1,
		0
	)
	return maxf(pow(archetype_repetition_penalty, penalized_repeats), 0.05)


func _get_eligible_enemies(
	wave_number: int,
	remaining_budget: int,
	map_data: MapData,
	config: WaveConfig
) -> Array[EnemyData]:
	var eligible_enemies: Array[EnemyData] = []
	var candidates: Array[EnemyData] = []
	if map_data != null:
		for entry in map_data.enemy_entries:
			if entry == null or entry.enemy_data == null:
				continue
			if entry.weight_multiplier <= 0.0:
				continue
			if not candidates.has(entry.enemy_data):
				candidates.append(entry.enemy_data)
	else:
		candidates.append_array(enemy_catalog)

	for enemy_data in candidates:
		if enemy_data == null:
			continue
		if enemy_data.unlock_wave > wave_number:
			continue
		if enemy_data.difficulty_cost <= 0:
			push_warning(
				"Skipping EnemyData with non-positive difficulty cost: %s"
				% enemy_data.resource_path
			)
			continue
		if enemy_data.selection_weight <= 0.0:
			continue
		if enemy_data.difficulty_cost > remaining_budget:
			continue
		eligible_enemies.append(enemy_data)

	if not _has_non_spider_group(config):
		var has_affordable_non_spider := false
		var spider_cost := 0
		for enemy_data in eligible_enemies:
			if enemy_data.enemy_id == &"spider":
				spider_cost = enemy_data.difficulty_cost
				continue
			if (
				not _has_enemy_type(config, enemy_data)
				and enemy_data.difficulty_cost <= remaining_budget
			):
				has_affordable_non_spider = true
		if config.groups.size() > 0 or not has_affordable_non_spider:
			eligible_enemies = _without_spider_candidates(eligible_enemies)
		elif spider_cost > 0:
			var can_add_spider_and_another_type := false
			for enemy_data in eligible_enemies:
				if (
					enemy_data.enemy_id != &"spider"
					and enemy_data.difficulty_cost
						<= remaining_budget - spider_cost
				):
					can_add_spider_and_another_type = true
					break
			if not can_add_spider_and_another_type:
				eligible_enemies = _without_spider_candidates(eligible_enemies)

	return eligible_enemies


func _without_spider_candidates(
	candidates: Array[EnemyData]
) -> Array[EnemyData]:
	var filtered: Array[EnemyData] = []
	for enemy_data in candidates:
		if enemy_data.enemy_id != &"spider":
			filtered.append(enemy_data)
	return filtered


func _has_non_spider_group(config: WaveConfig) -> bool:
	for group in config.groups:
		if (
			group.enemy_data != null
			and group.enemy_data.enemy_id != &"spider"
			and group.quantity > 0
		):
			return true
	return false


func _select_weighted_enemy(
	eligible_enemies: Array[EnemyData],
	archetype: WaveArchetype,
	config: WaveConfig,
	repetition_modifiers: Dictionary,
	map_data: MapData,
	rng: RandomNumberGenerator
) -> EnemyData:
	var total_weight := 0.0
	var effective_weights: Array[float] = []
	var prioritize_new_types := (
		config.groups.size() < archetype.minimum_distinct_enemy_types
		and _has_affordable_unselected_type(eligible_enemies, config)
	)
	for enemy_data in eligible_enemies:
		if prioritize_new_types and _has_enemy_type(config, enemy_data):
			effective_weights.append(0.0)
			continue

		var weight := _get_effective_enemy_weight(
			enemy_data,
			eligible_enemies,
			archetype,
			config
		)
		if map_data != null:
			weight *= map_data.get_enemy_weight_multiplier(enemy_data)
		var repetition_modifier := _get_enemy_repetition_modifier(
			enemy_data,
			archetype
		)
		repetition_modifiers[enemy_data.enemy_id] = repetition_modifier
		weight *= repetition_modifier
		effective_weights.append(weight)
		total_weight += weight

	if total_weight <= 0.0:
		return null

	var selection := rng.randf() * total_weight
	for index in range(eligible_enemies.size()):
		selection -= effective_weights[index]
		if selection < 0.0:
			return eligible_enemies[index]

	return eligible_enemies.back()


func _get_enemy_repetition_modifier(
	enemy_data: EnemyData,
	archetype: WaveArchetype
) -> float:
	var dominance_count := 0
	for history_entry in recent_wave_history:
		if enemy_data.enemy_id in history_entry["dominant_enemy_ids"]:
			dominance_count += 1

	var base_modifier := maxf(
		pow(enemy_repetition_penalty, dominance_count),
		0.05
	)
	return lerpf(base_modifier, 1.0, archetype.repetition_resistance)


func _has_affordable_unselected_type(
	eligible_enemies: Array[EnemyData],
	config: WaveConfig
) -> bool:
	for enemy_data in eligible_enemies:
		if not _has_enemy_type(config, enemy_data):
			return true
	return false


func _get_effective_enemy_weight(
	enemy_data: EnemyData,
	eligible_enemies: Array[EnemyData],
	archetype: WaveArchetype,
	config: WaveConfig
) -> float:
	var cost_preference := _get_normalized_property(
		enemy_data.difficulty_cost,
		eligible_enemies,
		0
	)
	var speed_preference := _get_normalized_property(
		enemy_data.base_speed,
		eligible_enemies,
		1
	)
	var hp_preference := _get_normalized_property(
		enemy_data.base_hp,
		eligible_enemies,
		2
	)

	var weight := enemy_data.selection_weight
	weight *= maxf(
		0.05,
		1.0 + archetype.difficulty_cost_bias * (cost_preference * 2.0 - 1.0)
	)
	weight *= maxf(
		0.05,
		1.0 + archetype.movement_speed_bias * (speed_preference * 2.0 - 1.0)
	)
	weight *= maxf(
		0.05,
		1.0 + archetype.hp_bias * (hp_preference * 2.0 - 1.0)
	)

	if archetype.diversity_bonus > 0.0 and not _has_enemy_type(config, enemy_data):
		weight *= 1.0 + archetype.diversity_bonus

	return weight


func _get_normalized_property(
	value: float,
	enemies: Array[EnemyData],
	property: int
) -> float:
	if enemies.is_empty():
		return 0.5

	var minimum := INF
	var maximum := -INF
	for enemy_data in enemies:
		var number := _get_enemy_property_value(enemy_data, property)
		minimum = minf(minimum, number)
		maximum = maxf(maximum, number)

	if is_equal_approx(minimum, maximum):
		return 0.5

	return (value - minimum) / (maximum - minimum)


func _get_enemy_property_value(enemy_data: EnemyData, property: int) -> float:
	match property:
		0:
			return float(enemy_data.difficulty_cost)
		1:
			return enemy_data.base_speed
		2:
			return float(enemy_data.base_hp)

	return 0.0


func _has_enemy_type(config: WaveConfig, enemy_data: EnemyData) -> bool:
	for group in config.groups:
		if group.enemy_data == enemy_data:
			return true
	return false


func _add_enemy_to_group(config: WaveConfig, enemy_data: EnemyData) -> void:
	for group in config.groups:
		if group.enemy_data == enemy_data:
			group.quantity += 1
			return

	var group := WaveEnemyGroup.new()
	group.enemy_data = enemy_data
	group.quantity = 1
	config.groups.append(group)


func _record_wave(config: WaveConfig) -> void:
	var total_enemy_count := 0
	for group in config.groups:
		total_enemy_count += maxi(group.quantity, 0)

	var dominant_enemy_ids: Array[StringName] = []
	if total_enemy_count > 0:
		for group in config.groups:
			if (
				float(group.quantity) / float(total_enemy_count)
				>= dominant_enemy_threshold
			):
				dominant_enemy_ids.append(group.enemy_data.enemy_id)

	recent_wave_history.push_front({
		"archetype_id": config.archetype_id,
		"dominant_enemy_ids": dominant_enemy_ids
	})
	while recent_wave_history.size() > recent_wave_history_size:
		recent_wave_history.pop_back()
