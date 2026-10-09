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
	INITIAL,
	MANUAL,
	AUTOMATIC
}

const ENEMY_SCENE: PackedScene = preload("res://enemies/Enemy.tscn")
const BASE_ENEMY_COUNT: int = 5
const ENEMIES_PER_WAVE: int = 2
const ENEMY_HP_GROWTH_FACTOR: float = 1.2
const ENEMY_SPEED_INCREASE_PER_WAVE: float = 0.008

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
var _initial_countdown_timer: Timer
var _initial_countdown_remaining: int = 0
var _initial_countdown_started: bool = false
var _initial_countdown_token: int = 0
var _automatic_start_timers: Dictionary = {}
var _automatic_start_tokens: Dictionary = {}
var _next_automatic_start_token: int = 0
var _automatic_schedule_generation: int = 0
var _run_generation: int = 0

@onready var _enemies_container: Node2D = get_node(enemies_container_path)
@onready var _enemy_path: Path2D = get_node(enemy_path_node_path)
@onready var _wave_generator: WaveGenerator = $WaveGenerator


func begin_run() -> void:
	_run_generation += 1
	_cancel_initial_countdown()
	_cancel_automatic_start_timers()
	_initial_countdown_started = false
	_spawning_stopped = false
	set_process(true)
	next_wave_number = 1
	active_waves.clear()
	completed_wave_numbers.clear()
	waves_by_number.clear()
	_started_wave_numbers.clear()
	auto_waves_enabled = true
	auto_waves_changed.emit(auto_waves_enabled)
	if auto_waves_enabled:
		_start_initial_countdown()


func start_wave(reason: StartReason) -> void:
	if _spawning_stopped:
		return

	if reason == StartReason.AUTOMATIC and not auto_waves_enabled:
		return

	var wave_number := next_wave_number
	if _started_wave_numbers.has(wave_number):
		return
	if reason == StartReason.INITIAL and wave_number != 1:
		return

	_cancel_initial_countdown()
	_cancel_automatic_start_for_wave(wave_number)
	_started_wave_numbers[wave_number] = true

	var wave := ActiveWave.new()
	wave.wave_number = wave_number
	wave.config = create_wave_config(wave.wave_number, true, true)
	var archetype_name := String(wave.config.archetype_id)
	if archetype_name.is_empty():
		archetype_name = "MANUAL" if reason == StartReason.MANUAL else "AUTO"
	print("Starting Wave %d | Archetype: %s" % [wave.wave_number, archetype_name])
	wave.total_enemies = _get_total_enemy_count(wave.config)
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

	_spawn_next_enemy(wave)


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
	_cancel_initial_countdown()
	_cancel_automatic_start_timers()


func set_auto_waves_enabled(enabled: bool) -> void:
	if auto_waves_enabled == enabled:
		return

	auto_waves_enabled = enabled
	if not auto_waves_enabled:
		_pause_initial_countdown()
		_cancel_automatic_start_timers()
	else:
		if next_wave_number == 1 and not _started_wave_numbers.has(1):
			_start_initial_countdown()
		else:
			_schedule_next_eligible_wave()
	auto_waves_changed.emit(auto_waves_enabled)


func _start_initial_countdown() -> void:
	if (
		_spawning_stopped
		or not auto_waves_enabled
		or next_wave_number != 1
		or _started_wave_numbers.has(1)
		or is_instance_valid(_initial_countdown_timer)
	):
		return

	_initial_countdown_token += 1
	if not _initial_countdown_started:
		_initial_countdown_remaining = 3
		_initial_countdown_started = true
	_initial_countdown_timer = Timer.new()
	_initial_countdown_timer.one_shot = true
	_initial_countdown_timer.wait_time = 1.0
	_initial_countdown_timer.timeout.connect(
		_on_initial_countdown_timeout.bind(
			_run_generation,
			_initial_countdown_token,
			_initial_countdown_timer
		)
	)
	add_child(_initial_countdown_timer)
	countdown_changed.emit(
		"First wave in: %d" % _initial_countdown_remaining
	)
	_initial_countdown_timer.start()


func _on_initial_countdown_timeout(
	generation: int,
	token: int,
	timer: Timer
) -> void:
	if (
		generation != _run_generation
		or token != _initial_countdown_token
		or timer != _initial_countdown_timer
		or _spawning_stopped
		or not auto_waves_enabled
	):
		return

	if _initial_countdown_remaining > 1:
		_initial_countdown_remaining -= 1
		countdown_changed.emit(
			"First wave in: %d" % _initial_countdown_remaining
		)
		timer.start()
		return

	_cancel_initial_countdown()
	start_wave(StartReason.INITIAL)


func _pause_initial_countdown() -> void:
	_initial_countdown_token += 1
	if is_instance_valid(_initial_countdown_timer):
		_initial_countdown_timer.stop()
		_initial_countdown_timer.queue_free()
	_initial_countdown_timer = null
	countdown_changed.emit("")


func _cancel_initial_countdown() -> void:
	_initial_countdown_token += 1
	_initial_countdown_remaining = 0
	_initial_countdown_started = false
	if is_instance_valid(_initial_countdown_timer):
		_initial_countdown_timer.stop()
		_initial_countdown_timer.queue_free()
	_initial_countdown_timer = null
	countdown_changed.emit("")


func _schedule_next_eligible_wave() -> void:
	var source_wave_number := next_wave_number - 1
	if not waves_by_number.has(source_wave_number):
		return

	var source_wave: ActiveWave = waves_by_number[source_wave_number]
	if source_wave.spawned_enemies < source_wave.total_enemies:
		return

	_schedule_automatic_start(next_wave_number)


func _schedule_automatic_start(wave_number: int) -> void:
	if (
		_spawning_stopped
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
	timer.wait_time = 5.0
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

	_automatic_start_timers.erase(wave_number)
	_automatic_start_tokens.erase(wave_number)
	timer.queue_free()
	if (
		_spawning_stopped
		or not auto_waves_enabled
		or wave_number != next_wave_number
		or _started_wave_numbers.has(wave_number)
	):
		return

	start_wave(StartReason.AUTOMATIC)


func _cancel_automatic_start_for_wave(wave_number: int) -> void:
	if not _automatic_start_timers.has(wave_number):
		return

	var timer: Timer = _automatic_start_timers[wave_number]
	_automatic_start_timers.erase(wave_number)
	_automatic_start_tokens.erase(wave_number)
	timer.stop()
	timer.queue_free()


func _cancel_automatic_start_timers() -> void:
	_automatic_schedule_generation += 1
	for timer in _automatic_start_timers.values():
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
	_automatic_start_timers.clear()
	_automatic_start_tokens.clear()


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
	var active_count := 0
	for enemy_id in wave.active_enemies.keys():
		var enemy = wave.active_enemies[enemy_id]
		if (
			is_instance_valid(enemy)
			and not enemy.get("is_dead")
			and not enemy.is_queued_for_deletion()
		):
			active_count += 1
		else:
			wave.active_enemies.erase(enemy_id)

	return active_count


func _get_gold_multiplier_for_wave(wave_number: int) -> float:
	if wave_number <= 1 or not waves_by_number.has(wave_number - 1):
		return 1.0

	var previous_wave: ActiveWave = waves_by_number[wave_number - 1]
	if previous_wave.total_enemies <= 0:
		return 1.0

	var active_previous_wave := _get_active_enemy_count_for_wave(previous_wave)
	var removed_previous_wave := previous_wave.spawned_enemies - active_previous_wave
	var contributing_previous_wave := maxi(
		previous_wave.total_enemies - removed_previous_wave,
		0
	)
	return 1.0 + (
		float(contributing_previous_wave) / float(previous_wave.total_enemies)
	) * 0.30


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


func _spawn_next_enemy(wave: ActiveWave) -> void:
	if wave.state != ActiveWave.State.SPAWNING:
		return

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

	var enemy_id := enemy.get_instance_id()
	wave.active_enemies[enemy_id] = enemy
	enemy.connect(
		"became_inactive",
		_on_enemy_inactive.bind(wave, enemy_id),
		CONNECT_ONE_SHOT
	)
	enemy.tree_exited.connect(
		_on_enemy_inactive.bind(wave, enemy_id),
		CONNECT_ONE_SHOT
	)
	wave.spawned_enemies += 1
	wave.spawned_in_group += 1
	_emit_wave_progress(wave)

	if wave.spawned_enemies >= wave.total_enemies:
		_finish_spawning(wave)


func _finish_spawning(wave: ActiveWave) -> void:
	if wave.state != ActiveWave.State.SPAWNING:
		return

	wave.state = ActiveWave.State.WAITING_FOR_ENEMIES
	_emit_wave_progress(wave)
	wave_spawn_completed.emit(wave.wave_number)
	if auto_waves_enabled:
		_schedule_automatic_start(wave.wave_number + 1)
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


func _try_complete_wave(wave: ActiveWave) -> void:
	if wave.state != ActiveWave.State.WAITING_FOR_ENEMIES:
		return
	if _get_active_enemy_count_for_wave(wave) > 0:
		return

	wave.state = ActiveWave.State.COMPLETED
	active_waves.erase(wave)
	completed_wave_numbers.append(wave.wave_number)
	wave_completed.emit(wave.wave_number)
	active_waves_changed.emit()
