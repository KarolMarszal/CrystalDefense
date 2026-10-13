class_name WaveManager
extends Node

signal next_wave_changed(wave_number: int)
signal active_waves_changed
signal wave_spawn_completed(wave_number: int)
signal wave_progress_changed(
	wave_number: int,
	active_enemies: int,
	spawned_enemies: int,
	total_enemies: int,
	state: ActiveWave.State
)
signal wave_completed(wave_number: int)
signal countdown_changed(message: String)
signal auto_waves_changed(enabled: bool)

enum StartReason {
	MANUAL,
	AUTOMATIC
}

const ENEMY_SCENE: PackedScene = preload("res://enemies/Enemy.tscn")
const BOSS_SCENE: PackedScene = preload("res://enemies/BossEnemy.tscn")
const SPIDER_WEB_SCENE: PackedScene = preload("res://enemies/SpiderWebTrap.tscn")
const BOSS_WAVE_SCHEDULE = preload("res://waves/BossWaveSchedule.gd")
const BASE_ENEMY_COUNT: int = 5
const ENEMIES_PER_WAVE: int = 2
const ENEMY_HP_GROWTH_FACTOR: float = 1.1
const ENEMY_SPEED_INCREASE_PER_WAVE: float = 0.005
const AUTO_WAVE_DELAY_SECONDS: float = 10.0

@export var spawn_interval: float = 0.8
@export var default_enemy_data: EnemyData
@export var active_map_data: MapData
@export var wave_config_overrides: Array[WaveConfig] = []
@export_node_path("Node2D") var enemies_container_path: NodePath = ^"../Enemies"
@export_node_path("Path2D") var enemy_path_node_path: NodePath = ^"../EnemyPath"
@export_node_path("Node2D") var castle_node_path: NodePath = ^"../Castle"
@export_node_path("Node2D") var enemy_camp_node_path: NodePath = ^"../EnemyCamp"

var next_wave_number: int = 1
var run_seed: int = 0
var active_waves: Array[ActiveWave] = []
var completed_wave_numbers: Array[int] = []
var waves_by_number: Dictionary = {}
var auto_waves_enabled: bool = true
var _spawning_stopped: bool = false
var _started_wave_numbers: Dictionary = {}
var _automatic_start_timers: Dictionary = {}
var _automatic_start_tokens: Dictionary = {}
var _automatic_start_remaining: Dictionary = {}
var _next_automatic_start_token: int = 0
var _automatic_schedule_generation: int = 0
var _boss_selection_rng := RandomNumberGenerator.new()
var _summon_placement_rng := RandomNumberGenerator.new()
var _boss_selection_pools: Dictionary = {}

@onready var _enemies_container: Node2D = get_node(enemies_container_path)
@onready var _enemy_path: Path2D = get_node(enemy_path_node_path)
@onready var _wave_generator: WaveGenerator = $WaveGenerator


func begin_run() -> void:
	_cancel_automatic_start_timers()
	_spawning_stopped = false
	set_process(true)
	next_wave_number = 1
	active_waves.clear()
	completed_wave_numbers.clear()
	waves_by_number.clear()
	_started_wave_numbers.clear()
	_boss_selection_pools.clear()
	_boss_selection_rng.seed = hash("%d:tier-1-boss-selection" % run_seed)
	auto_waves_enabled = true
	auto_waves_changed.emit(auto_waves_enabled)


func start_wave(reason: StartReason) -> void:
	if _spawning_stopped:
		return

	if reason == StartReason.AUTOMATIC and not auto_waves_enabled:
		return

	var wave_number := next_wave_number
	if _started_wave_numbers.has(wave_number):
		return

	_cancel_automatic_start_for_wave(wave_number)
	_started_wave_numbers[wave_number] = true

	var wave := ActiveWave.new()
	wave.wave_number = wave_number
	var test_boss := BOSS_WAVE_SCHEDULE.get_test_wave_boss(wave_number)
	var test_enemy_data := BOSS_WAVE_SCHEDULE.get_test_wave_enemy_data(
		wave_number
	)
	if test_boss != null:
		wave.config = _create_tier_one_boss_wave_config(
			wave.wave_number,
			test_boss,
			&"BOSS_TEST"
		)
		wave.boss_definitions.append(test_boss)
	elif test_enemy_data != null:
		wave.config = _create_matching_enemy_wave_config(
			wave.wave_number,
			test_enemy_data,
			&"SPIDER_TEST"
		)
	else:
		wave.config = create_wave_config(wave.wave_number, false, true)
		wave.boss_definitions = _select_bosses_for_wave(wave_number)
	if (
		test_boss == null
		and int(get_boss_wave_requirements(wave_number).get("tier", 0)) == 1
		and not wave.boss_definitions.is_empty()
	):
		wave.config = _create_tier_one_boss_wave_config(
			wave.wave_number,
			wave.boss_definitions[0],
			wave.config.archetype_id
		)

	wave.total_enemies = (
		_get_total_enemy_count(wave.config)
		+ wave.boss_definitions.size()
	)
	wave.start_reason = reason
	wave.gold_multiplier = (
		_get_gold_multiplier_for_wave(wave.wave_number)
		if reason == StartReason.MANUAL
		else 1.0
	)
	wave.state = ActiveWave.State.SPAWNING

	active_waves.append(wave)
	waves_by_number[wave.wave_number] = wave
	_prune_old_wave_records(wave.wave_number)
	next_wave_number += 1
	next_wave_changed.emit(next_wave_number)
	active_waves_changed.emit()

	_spawn_scheduled_bosses(wave)
	_spawn_next_enemy(wave)


func _enter_tree() -> void:
	_summon_placement_rng.randomize()


func _create_tier_one_boss_wave_config(
	wave_number: int,
	boss_data: BossData,
	archetype_id: StringName
) -> WaveConfig:
	var regular_enemy_data := BOSS_WAVE_SCHEDULE.get_regular_enemy_data(
		boss_data
	)
	if _wave_generator != null:
		return _wave_generator.generate_matching_enemy_wave(
			wave_number,
			regular_enemy_data,
			archetype_id
		)

	var config := WaveConfig.new()
	config.wave_number = wave_number
	config.archetype_id = archetype_id
	if regular_enemy_data == null:
		return config
	var group := WaveEnemyGroup.new()
	group.enemy_data = regular_enemy_data
	group.quantity = BASE_ENEMY_COUNT + (wave_number - 1) * ENEMIES_PER_WAVE
	config.groups.append(group)
	return config


func _create_matching_enemy_wave_config(
	wave_number: int,
	enemy_data: EnemyData,
	archetype_id: StringName
) -> WaveConfig:
	if _wave_generator != null:
		return _wave_generator.generate_matching_enemy_wave(
			wave_number,
			enemy_data,
			archetype_id
		)

	var config := WaveConfig.new()
	config.wave_number = wave_number
	config.archetype_id = archetype_id
	if enemy_data == null:
		return config
	var group := WaveEnemyGroup.new()
	group.enemy_data = enemy_data
	group.quantity = BASE_ENEMY_COUNT + (wave_number - 1) * ENEMIES_PER_WAVE
	config.groups.append(group)
	return config


func _process(delta: float) -> void:
	if _spawning_stopped:
		return

	for wave in active_waves.duplicate():
		if wave.state != ActiveWave.State.SPAWNING:
			continue

		wave.spawn_timer += delta
		if wave.spawn_timer >= spawn_interval:
			wave.spawn_timer -= spawn_interval
			_spawn_next_enemy(wave)


func stop_spawning() -> void:
	_spawning_stopped = true
	set_process(false)
	_cancel_automatic_start_timers()


func set_auto_waves_enabled(enabled: bool) -> void:
	if auto_waves_enabled == enabled:
		return

	auto_waves_enabled = enabled
	if not auto_waves_enabled:
		_cancel_automatic_start_timers()
	elif next_wave_number > 1:
		_schedule_next_eligible_wave()
	auto_waves_changed.emit(auto_waves_enabled)


func _schedule_next_eligible_wave() -> void:
	var source_wave_number := next_wave_number - 1
	if not waves_by_number.has(source_wave_number):
		return

	var source_wave: ActiveWave = waves_by_number[source_wave_number]
	if source_wave.state != ActiveWave.State.COMPLETED:
		return

	_schedule_automatic_start(next_wave_number)


func _schedule_automatic_start(wave_number: int) -> void:
	if (
		_spawning_stopped
		or not is_inside_tree()
		or not auto_waves_enabled
		or wave_number != next_wave_number
		or _started_wave_numbers.has(wave_number)
		or _automatic_start_timers.has(wave_number)
	):
		return

	_next_automatic_start_token += 1
	var token := _next_automatic_start_token
	var timer := Timer.new()
	timer.one_shot = true
	_automatic_start_remaining[wave_number] = int(AUTO_WAVE_DELAY_SECONDS)
	timer.wait_time = 1.0
	timer.timeout.connect(
		_on_automatic_start_timeout.bind(
			wave_number,
			token,
			_automatic_schedule_generation,
			timer
		)
	)
	_automatic_start_timers[wave_number] = timer
	_automatic_start_tokens[wave_number] = token
	add_child(timer)
	countdown_changed.emit(
		"Next wave in: %d" % int(_automatic_start_remaining[wave_number])
	)
	timer.start()


func _on_automatic_start_timeout(
	wave_number: int,
	token: int,
	generation: int,
	timer: Timer
) -> void:
	if (
		generation != _automatic_schedule_generation
		or not _automatic_start_timers.has(wave_number)
		or _automatic_start_tokens.get(wave_number) != token
		or _automatic_start_timers[wave_number] != timer
	):
		return

	var remaining := int(_automatic_start_remaining.get(wave_number, 0))
	if remaining > 1:
		_automatic_start_remaining[wave_number] = remaining - 1
		countdown_changed.emit(
			"Next wave in: %d" % int(_automatic_start_remaining[wave_number])
		)
		timer.start(1.0)
		return

	_automatic_start_timers.erase(wave_number)
	_automatic_start_tokens.erase(wave_number)
	_automatic_start_remaining.erase(wave_number)
	timer.queue_free()
	countdown_changed.emit("")
	if (
		_spawning_stopped
		or not auto_waves_enabled
		or wave_number != next_wave_number
		or _started_wave_numbers.has(wave_number)
	):
		return

	start_wave(StartReason.AUTOMATIC)


func get_boss_wave_requirements(wave_number: int) -> Dictionary:
	return BOSS_WAVE_SCHEDULE.get_requirements(wave_number)


func _cancel_automatic_start_for_wave(wave_number: int) -> void:
	if not _automatic_start_timers.has(wave_number):
		return

	var timer: Timer = _automatic_start_timers[wave_number]
	_automatic_start_timers.erase(wave_number)
	_automatic_start_tokens.erase(wave_number)
	_automatic_start_remaining.erase(wave_number)
	timer.stop()
	timer.queue_free()
	countdown_changed.emit("")


func _cancel_automatic_start_timers() -> void:
	_automatic_schedule_generation += 1
	for timer in _automatic_start_timers.values():
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
	_automatic_start_timers.clear()
	_automatic_start_tokens.clear()
	_automatic_start_remaining.clear()
	countdown_changed.emit("")


func set_run_seed(value: int) -> void:
	run_seed = value
	if _wave_generator != null:
		_wave_generator.reset_history()


func create_wave_config(
	current_wave: int,
	log_generated_wave: bool = false,
	commit_generated_wave: bool = false
) -> WaveConfig:
	for configured_wave in wave_config_overrides:
		if configured_wave != null and configured_wave.wave_number == current_wave:
			return configured_wave

	if _wave_generator != null:
		return _wave_generator.generate_wave(
			current_wave,
			run_seed,
			log_generated_wave,
			commit_generated_wave,
			active_map_data
		)

	var config := WaveConfig.new()
	config.wave_number = current_wave

	if default_enemy_data == null:
		push_error("WaveManager requires default EnemyData to create a wave.")
		return config

	var default_group := WaveEnemyGroup.new()
	default_group.enemy_data = default_enemy_data
	default_group.quantity = BASE_ENEMY_COUNT + (current_wave - 1) * ENEMIES_PER_WAVE
	config.groups.append(default_group)
	return config


func get_preview_wave_number() -> int:
	return next_wave_number


func get_wave_preview(preview_wave_number: int) -> Dictionary:
	var config := create_wave_config(preview_wave_number)
	var preview_groups: Array[Dictionary] = []

	for group in config.groups:
		if group.enemy_data == null:
			continue

		preview_groups.append({
			"display_name": group.enemy_data.display_name,
			"quantity": maxi(group.quantity, 0),
			"hp": get_enemy_hp_for_wave(
				preview_wave_number,
				group.enemy_data.base_hp
			),
			"speed_percent": get_enemy_speed_percent_for_wave(
				preview_wave_number,
				group.enemy_data.base_speed
			)
		})

	var gold_multiplier := _get_gold_multiplier_for_wave(preview_wave_number)
	return {
		"wave_number": config.wave_number,
		"groups": preview_groups,
		"total_enemies": _get_total_enemy_count(config),
		"gold_multiplier": gold_multiplier,
		"gold_bonus_percent": (gold_multiplier - 1.0) * 100.0
	}


func get_active_enemy_count() -> int:
	var count := 0
	for wave in active_waves:
		count += _get_active_enemy_count_for_wave(wave)
	return count


func get_active_enemy_count_for_wave(wave_number: int) -> int:
	if not waves_by_number.has(wave_number):
		return 0

	return _get_active_enemy_count_for_wave(waves_by_number[wave_number])


func get_active_wave_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for wave in active_waves:
		summaries.append({
			"wave_number": wave.wave_number,
			"active_enemies": _get_active_enemy_count_for_wave(wave),
			"spawned_enemies": wave.spawned_enemies,
			"total_enemies": wave.total_enemies,
			"state": wave.state,
			"gold_multiplier": wave.gold_multiplier,
			"start_reason": wave.start_reason
		})
	return summaries


func _get_active_enemy_count_for_wave(wave: ActiveWave) -> int:
	# Read-only: entries are removed only by _on_enemy_inactive so the
	# completion check always runs for the death that removes the last enemy.
	var active_count := 0
	for enemy in wave.active_enemies.values():
		if (
			is_instance_valid(enemy)
			and not enemy.get("is_dead")
			and not enemy.is_queued_for_deletion()
		):
			active_count += 1

	return active_count


func _get_active_planned_enemy_count_for_wave(wave: ActiveWave) -> int:
	var active_count := 0
	for enemy in wave.active_enemies.values():
		if (
			is_instance_valid(enemy)
			and enemy.is_planned_wave_enemy
			and not enemy.is_dead
			and not enemy.get("_has_become_inactive")
			and not enemy.is_queued_for_deletion()
		):
			active_count += 1
	return active_count


func _get_gold_multiplier_for_wave(wave_number: int) -> float:
	if wave_number <= 1 or not waves_by_number.has(wave_number - 1):
		return 1.0

	var previous_wave: ActiveWave = waves_by_number[wave_number - 1]
	if previous_wave.total_enemies <= 0:
		return 1.0

	var active_previous_wave := _get_active_planned_enemy_count_for_wave(
		previous_wave
	)
	var removed_previous_wave := previous_wave.spawned_enemies - active_previous_wave
	var contributing_previous_wave := maxi(
		previous_wave.total_enemies - removed_previous_wave,
		0
	)
	var base_bonus := (
		float(contributing_previous_wave) / float(previous_wave.total_enemies)
	) * 0.30
	var improved_bonus := minf(
		base_bonus * (
			1.0 + CrystalInventory.get_skill_effect_value(
				&"early_wave_bonus_scale"
			)
		),
		0.30
	)
	return 1.0 + improved_bonus


func _prune_old_wave_records(new_wave_number: int) -> void:
	for recorded_wave_number in waves_by_number.keys():
		var wave: ActiveWave = waves_by_number[recorded_wave_number]
		if (
			recorded_wave_number < new_wave_number - 1
			and wave.state == ActiveWave.State.COMPLETED
		):
			waves_by_number.erase(recorded_wave_number)


func _get_total_enemy_count(config: WaveConfig) -> int:
	var total := 0
	for group in config.groups:
		if group.enemy_data != null:
			total += maxi(group.quantity, 0)
	return total


func _select_bosses_for_wave(wave_number: int) -> Array[BossData]:
	var selected: Array[BossData] = []
	var requirements := get_boss_wave_requirements(wave_number)
	if requirements.is_empty():
		return selected

	var tier := int(requirements["tier"])
	var requested_count := int(requirements["count"])
	while selected.size() < requested_count:
		var draw_pile: Array = _boss_selection_pools.get(tier, [])
		if draw_pile.is_empty():
			draw_pile = BOSS_WAVE_SCHEDULE.get_boss_pool(tier)
			if draw_pile.is_empty():
				push_warning(
					"No boss definitions are configured for Tier %d; "
					+ "wave %d will use its regular composition only."
					% [tier, wave_number]
				)
				break
			for index in range(draw_pile.size() - 1, 0, -1):
				var swap_index := _boss_selection_rng.randi_range(0, index)
				var swapped = draw_pile[index]
				draw_pile[index] = draw_pile[swap_index]
				draw_pile[swap_index] = swapped

		selected.append(draw_pile.pop_back() as BossData)
		_boss_selection_pools[tier] = draw_pile
	return selected


func _spawn_scheduled_bosses(wave: ActiveWave) -> void:
	for boss_data in wave.boss_definitions:
		var boss_instance := BOSS_SCENE.instantiate()
		var boss := boss_instance as BossEnemy
		if boss == null:
			push_error("Boss scene must have a BossEnemy root.")
			boss_instance.free()
			wave.spawned_enemies += 1
			continue

		boss.initialize_for_boss(
			boss_data,
			wave.wave_number,
			wave.gold_multiplier,
			BOSS_WAVE_SCHEDULE.get_test_boss_hp_multiplier(
				boss_data,
				wave.wave_number
			)
		)
		boss.castle = get_node_or_null(castle_node_path) as Castle
		boss.camp = get_node_or_null(enemy_camp_node_path) as EnemyCamp
		boss.path = _enemy_path.curve
		boss.position = _enemy_path.curve.get_point_position(0)
		boss.summons_requested.connect(_on_boss_summons_requested)
		_register_wave_enemy(wave, boss)
		_enemies_container.add_child(boss)
		wave.spawned_enemies += 1
		_emit_wave_progress(wave)


func _on_boss_summons_requested(
	enemy_data: EnemyData,
	quantity: int,
	boss: BossEnemy
) -> void:
	if not is_instance_valid(boss) or boss.is_dead:
		return
	if (
		enemy_data == null
		or quantity <= 0
	):
		if not _is_spider_summon_request(enemy_data, boss):
			boss._log_ability(
				"summon",
				"summon_rejected",
				"reason=invalid_enemy_data_or_quantity count=%d" % quantity
			)
		return
	if not waves_by_number.has(boss.wave_number):
		if not _is_spider_summon_request(enemy_data, boss):
			boss._log_ability(
				"summon",
				"summon_rejected",
				"reason=wave_not_registered wave=%d" % boss.wave_number
			)
		return
	var wave: ActiveWave = waves_by_number[boss.wave_number]
	if wave.state == ActiveWave.State.COMPLETED:
		if not _is_spider_summon_request(enemy_data, boss):
			boss._log_ability(
				"summon",
				"summon_rejected",
				"reason=wave_already_completed"
			)
		return

	var summoned: Array[Enemy] = []
	var placement_failures := 0
	for _index in range(quantity):
		var enemy_instance := ENEMY_SCENE.instantiate()
		var enemy := enemy_instance as Enemy
		if enemy == null:
			if not _is_spider_summon_request(enemy_data, boss):
				push_error("Summoned enemy scene must have an Enemy root.")
			enemy_instance.free()
			continue

		enemy.initialize_for_wave(
			enemy_data,
			get_enemy_hp_for_wave(wave.wave_number, enemy_data.base_hp),
			get_enemy_speed_for_wave(wave.wave_number, enemy_data.base_speed),
			wave.wave_number,
			wave.gold_multiplier,
			false
		)
		enemy.castle = get_node_or_null(castle_node_path) as Castle
		enemy.camp = get_node_or_null(enemy_camp_node_path) as EnemyCamp
		enemy.path = _enemy_path.curve
		enemy.path_distance = boss.path_distance
		var spawn_position: Vector2
		if boss.boss_data.ability == BossData.Ability.GOBLIN_CHIEF:
			enemy.path_distance = 0.0
			spawn_position = _enemy_path.to_global(
				_enemy_path.curve.sample_baked(0.0)
			)
		elif boss.boss_data.ability == BossData.Ability.KOBOLD_CHIEF:
			var placed_position: Variant = _find_kobold_summon_position(
				boss,
				summoned
			)
			if placed_position == null:
				enemy_instance.free()
				placement_failures += 1
				continue
			spawn_position = placed_position
		elif enemy_data.enemy_id == &"spider_summon":
			var placement: Variant = _find_spider_summon_position(
				boss,
				summoned
			)
			if placement == null:
				enemy_instance.free()
				placement_failures += 1
				continue
			enemy.path_distance = float(placement["path_distance"])
			spawn_position = placement["position"]
		else:
			spawn_position = _enemy_path.to_global(
				_enemy_path.curve.sample_baked(enemy.path_distance)
			)
		enemy.global_position = spawn_position
		if enemy_data.enemy_id == &"spider_summon":
			enemy.apply_continuous_self_damage(0.05)
			if (
				boss.movement_direction
				== Enemy.MovementDirection.RETURNING_TO_CAMP
			):
				enemy.start_return_to_camp()
		_register_wave_enemy(wave, enemy)
		_enemies_container.add_child(enemy)
		summoned.append(enemy)

	if is_instance_valid(boss):
		if summoned.is_empty():
			if not _is_spider_summon_request(enemy_data, boss):
				boss._log_ability(
					"summon",
					"summon_failed",
					"reason=all_spawns_failed requested=%d placement_failures=%d"
					% [quantity, placement_failures]
				)
		else:
			boss.track_summoned_enemies(summoned)
			if (
				boss.boss_data.ability == BossData.Ability.SPIDER_MATRON
				and boss.claim_spider_web_for_summon()
			):
				var web_instance := SPIDER_WEB_SCENE.instantiate()
				var web_trap := web_instance as SpiderWebTrap
				if web_trap == null:
					push_error("Spider web scene must have a SpiderWebTrap root.")
					web_instance.free()
				else:
					_enemies_container.add_child(web_trap)
					web_trap.global_position = boss.global_position
			if boss.boss_data.ability == BossData.Ability.KOBOLD_CHIEF:
				var spawned_positions := PackedStringArray()
				for enemy in summoned:
					spawned_positions.append(
						"(%.1f,%.1f)" % [
							enemy.global_position.x,
							enemy.global_position.y
						]
					)
				boss._log_ability(
					"kobold_summon",
					"spawn_position_result",
					"requested=%d spawned=%d positions=%s"
					% [quantity, summoned.size(), ", ".join(spawned_positions)]
				)


func _is_spider_summon_request(
	enemy_data: EnemyData,
	boss: BossEnemy
) -> bool:
	return (
		is_instance_valid(boss)
		and boss.boss_data != null
		and boss.boss_data.ability == BossData.Ability.SPIDER_MATRON
		and enemy_data != null
		and enemy_data.enemy_id == &"spider_summon"
	)


func _find_kobold_summon_position(
	boss: BossEnemy,
	already_placed: Array[Enemy]
) -> Variant:
	if boss.boss_data.summon_spawn_radius <= 0.0:
		boss._log_ability(
			"kobold_summon",
			"placement_failed",
			"reason=spawn_radius_not_configured"
		)
		return null

	for _attempt in range(20):
		var angle := _summon_placement_rng.randf_range(0.0, TAU)
		var distance := _summon_placement_rng.randf_range(
			minf(30.0, boss.boss_data.summon_spawn_radius),
			boss.boss_data.summon_spawn_radius
		)
		var candidate := boss.global_position + Vector2.from_angle(angle) * distance
		if _is_summon_position_clear(candidate, boss, already_placed, 28.0):
			return candidate

	boss._log_ability(
		"kobold_summon",
		"placement_failed",
		"reason=no_unoccupied_position attempts=20"
	)
	return null


func _find_spider_summon_position(
	boss: BossEnemy,
	already_placed: Array[Enemy]
) -> Variant:
	if (
		boss.boss_data.summon_spawn_radius <= 0.0
		or _enemy_path.curve == null
	):
		return null

	var path_length := _enemy_path.curve.get_baked_length()
	var minimum_distance := maxf(
		boss.path_distance - boss.boss_data.summon_spawn_radius,
		0.0
	)
	var maximum_distance := minf(
		boss.path_distance + boss.boss_data.summon_spawn_radius,
		path_length
	)
	if maximum_distance - minimum_distance < 32.0:
		return null

	for _attempt in range(40):
		var candidate_distance := _summon_placement_rng.randf_range(
			minimum_distance,
			maximum_distance
		)
		if (
			absf(candidate_distance - boss.path_distance)
			< BossEnemy.SPIDER_SUMMON_MIN_SEPARATION
		):
			continue
		var candidate_position := _enemy_path.to_global(
			_enemy_path.curve.sample_baked(candidate_distance)
		)
		if (
			candidate_position.distance_to(boss.global_position)
			< BossEnemy.SPIDER_SUMMON_MIN_SEPARATION
		):
			continue
		if not _is_summon_position_clear(
			candidate_position,
			boss,
			already_placed,
			BossEnemy.SPIDER_SUMMON_MIN_SEPARATION
		):
			continue
		return {
			"path_distance": candidate_distance,
			"position": candidate_position
		}

	return null


func _is_summon_position_clear(
	candidate: Vector2,
	boss: BossEnemy,
	already_placed: Array[Enemy],
	minimum_enemy_separation: float
) -> bool:
	for existing in get_tree().get_nodes_in_group("enemies"):
		if (
			is_instance_valid(existing)
			and existing != boss
			and candidate.distance_to(existing.global_position)
				< minimum_enemy_separation
		):
			return false
	for tower in get_tree().get_nodes_in_group("towers"):
		if (
			is_instance_valid(tower)
			and candidate.distance_to(tower.global_position) < 36.0
		):
			return false
	for placed in already_placed:
		if (
			is_instance_valid(placed)
			and candidate.distance_to(placed.global_position)
				< minimum_enemy_separation
		):
			return false
	for build_slot in get_tree().get_nodes_in_group("build_slots"):
		if (
			is_instance_valid(build_slot)
			and candidate.distance_to(build_slot.global_position) < 32.0
		):
			return false
	return true


func _register_wave_enemy(wave: ActiveWave, enemy: Enemy) -> void:
	var enemy_id := enemy.get_instance_id()
	wave.active_enemies[enemy_id] = enemy
	enemy.became_inactive.connect(
		_on_enemy_became_inactive.bind(wave, enemy_id, enemy),
		CONNECT_ONE_SHOT
	)
	enemy.tree_exited.connect(
		_on_enemy_inactive.bind(wave, enemy_id),
		CONNECT_ONE_SHOT
	)


func _spawn_next_enemy(wave: ActiveWave) -> void:
	if wave.state != ActiveWave.State.SPAWNING:
		return

	var interleave_spiders := _wave_has_spider_group(wave)
	if interleave_spiders:
		wave.group_index = _get_next_interleaved_group(wave)
		if wave.group_index < 0:
			_finish_spawning(wave)
			return
	else:
		while wave.group_index < wave.config.groups.size():
			var current_group := wave.config.groups[wave.group_index]
			if current_group.enemy_data != null and wave.spawned_in_group < maxi(
				current_group.quantity,
				0
			):
				break
			if current_group.enemy_data == null and current_group.quantity > 0:
				push_error("WaveManager found a wave group without EnemyData.")
			wave.group_index += 1
			wave.spawned_in_group = 0

		if wave.group_index >= wave.config.groups.size():
			_finish_spawning(wave)
			return

	var group := wave.config.groups[wave.group_index]
	if group.enemy_data == null:
		push_error("WaveManager found a wave group without EnemyData.")
		return

	var enemy_instance := ENEMY_SCENE.instantiate()
	var enemy := enemy_instance as Enemy
	if enemy == null:
		push_error("WaveManager enemy scene must have an Enemy root.")
		enemy_instance.free()
		# Consume the slot so a broken spawn cannot leave the wave unfinishable.
		wave.spawned_enemies += 1
		_record_spawned_group_enemy(wave, interleave_spiders)
		if wave.spawned_enemies >= wave.total_enemies:
			_finish_spawning(wave)
		return

	var base_hp := group.enemy_data.base_hp
	var base_speed := group.enemy_data.base_speed
	enemy.initialize_for_wave(
		group.enemy_data,
		get_enemy_hp_for_wave(wave.wave_number, base_hp),
		get_enemy_speed_for_wave(wave.wave_number, base_speed),
		wave.wave_number,
		wave.gold_multiplier,
		true,
		group.modifiers
	)
	enemy.castle = get_node_or_null(castle_node_path) as Castle
	enemy.camp = get_node_or_null(enemy_camp_node_path) as EnemyCamp
	enemy.path = _enemy_path.curve
	enemy.position = _enemy_path.curve.get_point_position(0)

	_enemies_container.add_child(enemy)

	_register_wave_enemy(wave, enemy)
	wave.spawned_enemies += 1
	_record_spawned_group_enemy(wave, interleave_spiders)
	_emit_wave_progress(wave)

	if wave.spawned_enemies >= wave.total_enemies:
		_finish_spawning(wave)


func _wave_has_spider_group(wave: ActiveWave) -> bool:
	for group in wave.config.groups:
		if (
			group.enemy_data != null
			and group.enemy_data.enemy_id == &"spider"
			and group.quantity > 0
		):
			return true
	return false


func _get_next_interleaved_group(wave: ActiveWave) -> int:
	if wave.interleaved_group_spawn_counts.size() != wave.config.groups.size():
		wave.interleaved_group_spawn_counts.resize(wave.config.groups.size())

	for offset in range(wave.config.groups.size()):
		var group_index := (
			wave.last_interleaved_group_index + 1 + offset
		) % wave.config.groups.size()
		var group := wave.config.groups[group_index]
		if (
			group.enemy_data != null
			and wave.interleaved_group_spawn_counts[group_index]
				< maxi(group.quantity, 0)
		):
			return group_index
	return -1


func _record_spawned_group_enemy(
	wave: ActiveWave,
	interleave_spiders: bool
) -> void:
	if interleave_spiders:
		wave.interleaved_group_spawn_counts[wave.group_index] += 1
		wave.last_interleaved_group_index = wave.group_index
	else:
		wave.spawned_in_group += 1


func get_remaining_spawn_count(wave: ActiveWave) -> int:
	return maxi(wave.total_enemies - wave.spawned_enemies, 0)


func _finish_spawning(wave: ActiveWave) -> void:
	if wave.state != ActiveWave.State.SPAWNING:
		return

	wave.state = ActiveWave.State.WAITING_FOR_ENEMIES
	_emit_wave_progress(wave)
	wave_spawn_completed.emit(wave.wave_number)
	_try_complete_wave(wave)


func get_enemy_hp_for_wave(current_wave: int, base_hp: int) -> int:
	var wave_index := maxi(current_wave - 1, 0)
	return roundi(base_hp * pow(ENEMY_HP_GROWTH_FACTOR, wave_index))


func get_enemy_speed_for_wave(current_wave: int, base_speed: float) -> float:
	var wave_index := maxi(current_wave - 1, 0)
	var wave_speed_multiplier := 1.0 + wave_index * ENEMY_SPEED_INCREASE_PER_WAVE
	return base_speed * wave_speed_multiplier


func get_enemy_speed_percent_for_wave(current_wave: int, base_speed: float) -> int:
	if base_speed <= 0.0:
		return 0

	return roundi(get_enemy_speed_for_wave(current_wave, base_speed) / base_speed * 100.0)


func _emit_wave_progress(wave: ActiveWave) -> void:
	wave_progress_changed.emit(
		wave.wave_number,
		_get_active_enemy_count_for_wave(wave),
		wave.spawned_enemies,
		wave.total_enemies,
		wave.state
	)
	active_waves_changed.emit()


func _on_enemy_inactive(wave: ActiveWave, enemy_id: int) -> void:
	if not wave.active_enemies.erase(enemy_id):
		return
	_emit_wave_progress(wave)
	_try_complete_wave(wave)


func _on_enemy_became_inactive(
	wave: ActiveWave,
	enemy_id: int,
	enemy: Enemy
) -> void:
	if not is_instance_valid(enemy) or enemy.is_dead:
		_on_enemy_inactive(wave, enemy_id)
		return
	_emit_wave_progress(wave)


func _try_complete_wave(wave: ActiveWave) -> void:
	if wave.state != ActiveWave.State.WAITING_FOR_ENEMIES:
		return
	# The countdown needs an empty spawn queue as well as no living enemies.
	if get_remaining_spawn_count(wave) > 0:
		return
	if _get_active_enemy_count_for_wave(wave) > 0:
		return

	wave.state = ActiveWave.State.COMPLETED
	active_waves.erase(wave)
	completed_wave_numbers.append(wave.wave_number)
	wave_completed.emit(wave.wave_number)
	active_waves_changed.emit()
	if auto_waves_enabled:
		_schedule_automatic_start(wave.wave_number + 1)
