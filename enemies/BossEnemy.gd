class_name BossEnemy
extends Enemy

signal summons_requested(enemy_data: EnemyData, quantity: int, boss: BossEnemy)

var boss_data: BossData
var is_poison_immune: bool:
	get:
		return boss_data != null and boss_data.poison_immune


var _scaled_speed: float = 0.0
var _summon_timer: float = 0.0
var _boss_theft_elapsed: float = 0.0
var _boss_theft_complete: bool = false
var _escort_boost_cooldown: float = 0.0
var _escort_boost_remaining: float = 0.0
var _regeneration_remainder: float = 0.0
var _regeneration_log_elapsed: float = 0.0
var _regeneration_log_healed: int = 0
var _last_logged_regeneration_rate: float = -1.0
var _healing_activations: int = 0
var _healing_limit_logged: bool = false
var _has_lost_first_trophy: bool = false
var _first_return_trophy_dropped: bool = false
var _ignored_dropped_trophy_ids: Dictionary = {}
var _summoned_enemies: Dictionary = {}
var _escort_connections: Dictionary = {}
var _speed_aura_targets: Dictionary = {}
var _temporary_speed_targets: Dictionary = {}
var _damage_aura_targets: Dictionary = {}
var _tower_aura_targets: Dictionary = {}
var _tower_debuff_targets: Dictionary = {}
var _boss_name_label: Label
var _summon_rng := RandomNumberGenerator.new()
var _summon_stop_remaining: float = 0.0
const GOBLIN_SUMMON_SPAWN_TIMES: Array[float] = [0.5, 0.75, 1.0]
const GOBLIN_SUMMON_STOP_DURATION := 1.0
const KOBOLD_SUMMON_MIN_BATCH := 3
const KOBOLD_SUMMON_MAX_BATCH := 5
const KOBOLD_SUMMON_SPAWN_INTERVAL := 0.2
const SPIDER_SUMMON_MIN_SEPARATION := 20.0
var _summon_sequence_active := false
var _summon_schedule: Array[float] = []
var _summon_sequence_elapsed := 0.0
var _summon_sequence_next_index := 0
var _summon_sequence_spawned := 0
const SPIDER_SUMMON_SPAWN_INTERVAL := 0.15
var _spider_summon_batch_active := false
var _spider_summon_batch_elapsed := 0.0
var _spider_summon_batch_requested := 0
var _spider_summon_batch_attempted := 0
var _spider_web_placed_for_batch := false
var _test_hp_multiplier: float = 1.0
var _snake_effects_transferred: bool = false

const SKELETON_RESURRECTION_PHASES: Array[float] = [0.75, 0.5, 0.25]
const GOLD_GROWTH_PER_STEP: float = 1.10
const ESSENCE_GROWTH_PER_STEP: float = 1.15


func is_immune_to_poison() -> bool:
	return is_poison_immune


func initialize_for_boss(
	data: BossData,
	owning_wave: int,
	gold_multiplier: float,
	test_hp_multiplier: float = 1.0
) -> void:
	boss_data = data
	_test_hp_multiplier = maxf(test_hp_multiplier, 1.0)
	if boss_data == null or boss_data.visual_source == null:
		push_error("Boss requires BossData with a valid visual source.")
		return

	enemy_data = boss_data.visual_source
	max_hp = maxi(
		roundi(
			float(boss_data.base_hp)
			* pow(1.0 + boss_data.hp_growth_per_wave, maxi(owning_wave - 1, 0))
			* _test_hp_multiplier
		),
		1
	)
	hp = max_hp
	_scaled_speed = boss_data.base_speed * (
		1.0 + boss_data.speed_growth_per_wave * maxi(owning_wave - 1, 0)
	)
	speed = _scaled_speed
	wave_number = owning_wave
	wave_gold_multiplier = gold_multiplier
	trophy_carrying_capacity = boss_data.trophy_capacity
	is_planned_wave_enemy = true
	_summon_timer = boss_data.ability_interval
	_escort_boost_cooldown = boss_data.ability_interval
	_summon_rng.randomize()


func _ready() -> void:
	super._ready()
	if boss_data == null:
		push_error("BossEnemy must be initialized before it enters the scene tree.")
		return

	var visual := get_node_or_null("Visual") as Sprite2D
	if visual != null:
		visual.scale *= Vector2.ONE * 1.6

	_boss_name_label = Label.new()
	_boss_name_label.position = Vector2(-55.0, -34.0)
	_boss_name_label.size = Vector2(150.0, 22.0)
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.add_theme_font_size_override("font_size", 12)
	_boss_name_label.add_theme_color_override("font_color", Color(1.0, 0.83, 0.43))
	_boss_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_boss_name_label.add_theme_constant_override("outline_size", 3)
	add_child(_boss_name_label)
	_update_boss_display()
	_log_ability(
		"lifecycle",
		"spawned",
		"hp=%d/%d speed=%.2f trophy_capacity=%d hp_override_applied=%s multiplier=%.2fx"
		% [
			hp,
			max_hp,
			speed,
			trophy_carrying_capacity,
			str(_test_hp_multiplier > 1.0),
			_test_hp_multiplier
		]
	)
	_log_ability("lifecycle", "ability_initialized")

	if boss_data.ability == BossData.Ability.ORC_CHIEF:
		set_damage_taken_multiplier(get_instance_id(), 1.0 - boss_data.damage_reduction)
		_log_ability(
			"orc_damage_reduction",
			"activated",
			"reduction=%.0f%%"
			% (boss_data.damage_reduction * 100.0)
		)
	elif boss_data.ability == BossData.Ability.GHOUL:
		_request_summons(boss_data.summon_count, "starting_escorts")


func _process(delta: float) -> void:
	var was_stopped_for_summon := _summon_stop_remaining > 0.0
	super._process(delta)
	if was_stopped_for_summon:
		_summon_stop_remaining = _movement_stop_remaining
		if (
			_summon_stop_remaining <= 0.0
			and not is_dead
			and not _has_reached_castle
			and movement_direction in [
				MovementDirection.MOVING_TO_CASTLE,
				MovementDirection.RETURNING_TO_CAMP
			]
		):
			_log_ability(
				"goblin_summon_stop",
				"movement_resumed",
				"state=%s" % MovementDirection.keys()[movement_direction]
			)
	if is_dead or boss_data == null:
		return

	_update_boss_abilities(delta)
	_update_boss_regeneration(delta)
	_update_first_return_trophy_drop()
	_update_boss_display()


func _update_boss_abilities(delta: float) -> void:
	_update_summon_sequence(delta)
	match boss_data.ability:
		BossData.Ability.GOBLIN_CHIEF:
			_update_summon_timer(delta, _get_current_summon_interval())
			_update_goblin_command_aura()
		BossData.Ability.KOBOLD_CHIEF:
			_update_summon_timer(delta, _get_current_summon_interval())
			_update_kobold_escort_boost(delta)
			_update_kobold_auras()
		BossData.Ability.ORC_CHIEF:
			_update_orc_aura()
		BossData.Ability.SPIDER_MATRON:
			_update_spider_summon_timer(delta)
		BossData.Ability.SNAKE:
			_update_snake_tower_aura()


func _get_current_summon_interval() -> float:
	if not _has_lost_first_trophy:
		return boss_data.ability_interval
	if boss_data.ability == BossData.Ability.GOBLIN_CHIEF:
		return boss_data.ability_interval / maxf(boss_data.enrage_multiplier, 1.0)
	if boss_data.enraged_ability_interval > 0.0:
		return boss_data.enraged_ability_interval
	return boss_data.ability_interval


func _update_summon_timer(
	delta: float,
	interval: float,
	maximum_living: int = 0
) -> void:
	if boss_data.summon_enemy_data == null or interval <= 0.0:
		return

	_summon_timer -= delta
	while _summon_timer <= 0.0:
		_summon_timer += interval
		var living_count := _get_living_summon_count()
		if maximum_living > 0 and living_count >= maximum_living:
			continue
		if _is_staggered_summoner():
			if _summon_sequence_active:
				_log_ability(
					_get_staggered_summon_ability_name(),
					"summon_blocked",
					"reason=sequence_active"
				)
			else:
				_start_summon_sequence()
			continue
		var quantity := boss_data.summon_count
		if maximum_living > 0:
			quantity = mini(quantity, maximum_living - living_count)
		if boss_data.ability != BossData.Ability.SPIDER_MATRON:
			_log_ability(
				"boss_summon",
				"activation_started",
				"requested=%d reason=%s" % [quantity, "cooldown_elapsed"]
			)
		_request_summons(quantity, "cooldown_elapsed")


func _update_spider_summon_timer(delta: float) -> void:
	_update_spider_summon_batch(delta)
	var interval := _get_current_summon_interval()
	if boss_data.summon_enemy_data == null or interval <= 0.0:
		return

	_summon_timer -= delta
	while _summon_timer <= 0.0:
		_summon_timer += interval
		if _spider_summon_batch_active:
			continue
		if (
			_get_living_spider_summon_count()
			>= boss_data.maximum_living_summons
		):
			continue
		_start_spider_summon_batch()


func _start_spider_summon_batch() -> void:
	var available_slots := maxi(
		boss_data.maximum_living_summons
			- _get_living_spider_summon_count(),
		0
	)
	_spider_summon_batch_requested = mini(
		boss_data.summon_count,
		available_slots
	)
	if _spider_summon_batch_requested <= 0:
		return

	_spider_summon_batch_active = true
	_spider_summon_batch_elapsed = 0.0
	_spider_summon_batch_attempted = 0
	_spider_web_placed_for_batch = false
	_update_spider_summon_batch(0.0)


func _update_spider_summon_batch(delta: float) -> void:
	if not _spider_summon_batch_active:
		return
	if is_dead or is_queued_for_deletion():
		_cancel_spider_summon_batch()
		return

	_spider_summon_batch_elapsed += delta
	if (
		_spider_summon_batch_attempted
			< _spider_summon_batch_requested
		and _spider_summon_batch_elapsed
			>= _spider_summon_batch_attempted
				* SPIDER_SUMMON_SPAWN_INTERVAL
	):
		if (
			_get_living_spider_summon_count()
			>= boss_data.maximum_living_summons
		):
			_reset_spider_summon_batch()
			return

		_spider_summon_batch_attempted += 1
		_request_summons(
			1,
			"spider_summon_batch",
			true
		)
		if is_dead or is_queued_for_deletion():
			_cancel_spider_summon_batch()
			return

	if (
		_spider_summon_batch_attempted
			>= _spider_summon_batch_requested
		or _get_living_spider_summon_count()
			>= boss_data.maximum_living_summons
	):
		_reset_spider_summon_batch()


func _get_living_spider_summon_count() -> int:
	var count := 0
	for enemy_id in _summoned_enemies.keys():
		var enemy = _summoned_enemies[enemy_id]
		if (
			not is_instance_valid(enemy)
			or enemy.is_dead
			or enemy.is_queued_for_deletion()
		):
			_summoned_enemies.erase(enemy_id)
			continue
		if (
			enemy.enemy_data != null
			and enemy.enemy_data.enemy_id == &"spider_summon"
		):
			count += 1
	return count


func _reset_spider_summon_batch() -> void:
	_spider_summon_batch_active = false
	_spider_summon_batch_elapsed = 0.0
	_spider_summon_batch_requested = 0
	_spider_summon_batch_attempted = 0
	_spider_web_placed_for_batch = false


func _cancel_spider_summon_batch() -> void:
	if not _spider_summon_batch_active:
		return
	_reset_spider_summon_batch()


func claim_spider_web_for_summon() -> bool:
	if (
		not _spider_summon_batch_active
		or _spider_web_placed_for_batch
	):
		return false
	_spider_web_placed_for_batch = true
	return true


func _is_staggered_summoner() -> bool:
	return boss_data != null and boss_data.ability in [
		BossData.Ability.GOBLIN_CHIEF,
		BossData.Ability.KOBOLD_CHIEF
	]


func _get_staggered_summon_ability_name() -> String:
	if boss_data.ability == BossData.Ability.GOBLIN_CHIEF:
		return "goblin_summon_batch"
	return "kobold_summon"


# The schedule is plain data, so presentation can later hook into spawn events.
func _build_summon_schedule() -> Array[float]:
	var schedule: Array[float] = []
	if boss_data.ability == BossData.Ability.GOBLIN_CHIEF:
		schedule.append_array(GOBLIN_SUMMON_SPAWN_TIMES)
	else:
		var batch_size := _summon_rng.randi_range(
			KOBOLD_SUMMON_MIN_BATCH,
			KOBOLD_SUMMON_MAX_BATCH
		)
		for index in range(batch_size):
			schedule.append(index * KOBOLD_SUMMON_SPAWN_INTERVAL)
	return schedule


func _start_summon_sequence() -> void:
	_summon_schedule = _build_summon_schedule()
	_summon_sequence_active = true
	_summon_sequence_elapsed = 0.0
	_summon_sequence_next_index = 0
	_summon_sequence_spawned = 0
	var ability := _get_staggered_summon_ability_name()
	_log_ability(
		ability,
		"activation_started",
		"requested=%d reason=cooldown_elapsed schedule=%s"
		% [_summon_schedule.size(), str(_summon_schedule)]
	)
	if boss_data.ability == BossData.Ability.GOBLIN_CHIEF:
		stop_movement_for(GOBLIN_SUMMON_STOP_DURATION)
		_summon_stop_remaining = _movement_stop_remaining
		_log_ability(
			"goblin_summon_stop",
			"movement_stopped",
			"duration=%.2fs" % GOBLIN_SUMMON_STOP_DURATION
		)
	_update_summon_sequence(0.0)


func _update_summon_sequence(delta: float) -> void:
	if not _summon_sequence_active:
		return
	if is_dead or is_queued_for_deletion():
		_cancel_summon_sequence("boss_dead_or_removed")
		return

	_summon_sequence_elapsed += delta
	while (
		_summon_sequence_next_index < _summon_schedule.size()
		and _summon_sequence_elapsed
			>= _summon_schedule[_summon_sequence_next_index]
	):
		var sequence_index := _summon_sequence_next_index + 1
		_summon_sequence_next_index += 1
		var ability := _get_staggered_summon_ability_name()
		var spawned := _request_summons(1, "sequence_spawn")
		if spawned > 0:
			_summon_sequence_spawned += spawned
			_log_ability(
				ability,
				"sequence_spawn",
				"index=%d/%d scheduled=%.2fs elapsed=%.2fs result=spawned"
				% [
					sequence_index,
					_summon_schedule.size(),
					_summon_schedule[sequence_index - 1],
					_summon_sequence_elapsed
				]
			)
		else:
			_log_ability(
				ability,
				"sequence_spawn",
				"index=%d/%d scheduled=%.2fs elapsed=%.2fs result=failed"
				% [
					sequence_index,
					_summon_schedule.size(),
					_summon_schedule[sequence_index - 1],
					_summon_sequence_elapsed
				]
			)
		if is_dead or is_queued_for_deletion():
			_cancel_summon_sequence("boss_dead_or_removed")
			return

	if _summon_sequence_next_index >= _summon_schedule.size():
		_log_ability(
			_get_staggered_summon_ability_name(),
			"sequence_completed",
			"spawned=%d requested=%d elapsed=%.2fs"
			% [
				_summon_sequence_spawned,
				_summon_schedule.size(),
				_summon_sequence_elapsed
			]
		)
		_reset_summon_sequence()


func _cancel_summon_sequence(reason: String) -> void:
	if not _summon_sequence_active:
		return
	_log_ability(
		_get_staggered_summon_ability_name(),
		"sequence_cancelled",
		"reason=%s spawned=%d pending=%d elapsed=%.2fs"
		% [
			reason,
			_summon_sequence_spawned,
			_summon_schedule.size() - _summon_sequence_next_index,
			_summon_sequence_elapsed
		]
	)
	_reset_summon_sequence()


func _reset_summon_sequence() -> void:
	_summon_sequence_active = false
	_summon_schedule.clear()
	_summon_sequence_elapsed = 0.0
	_summon_sequence_next_index = 0
	_summon_sequence_spawned = 0


func _request_summons(
	quantity: int,
	reason: String,
	suppress_failure_log: bool = false
) -> int:
	if boss_data.summon_enemy_data == null or quantity <= 0:
		if not suppress_failure_log:
			_log_ability(
				"summon",
				"summon_rejected",
				"reason=invalid_enemy_data_or_quantity count=%d" % quantity
			)
		return 0
	var previous_living_count := _get_living_summon_count()
	summons_requested.emit(boss_data.summon_enemy_data, quantity, self)
	var spawned_count := _get_living_summon_count() - previous_living_count
	if (
		not suppress_failure_log
		and
		spawned_count <= 0
		and get_signal_connection_list("summons_requested").is_empty()
	):
		_log_ability(
			"summon",
			"summon_failed",
			"reason=no_spawn_handler action=%s requested=%d"
			% [reason, quantity]
		)
	return maxi(spawned_count, 0)


func _get_living_summon_count() -> int:
	var count := 0
	for enemy_id in _summoned_enemies.keys():
		var enemy = _summoned_enemies[enemy_id]
		if (
			is_instance_valid(enemy)
			and not enemy.is_dead
			and not enemy.is_queued_for_deletion()
		):
			count += 1
		else:
			_summoned_enemies.erase(enemy_id)
	return count


func track_summoned_enemies(enemies: Array[Enemy]) -> void:
	var newly_tracked: Array[Enemy] = []
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var enemy_id := enemy.get_instance_id()
		if _summoned_enemies.has(enemy_id):
			continue
		_summoned_enemies[enemy_id] = enemy
		newly_tracked.append(enemy)
		enemy.tree_exited.connect(
			_on_summoned_enemy_tree_exited.bind(enemy_id),
			CONNECT_ONE_SHOT
		)
		if boss_data.ability != BossData.Ability.GHOUL:
			if (
				boss_data.ability == BossData.Ability.GOBLIN_CHIEF
				and enemy.enemy_data != null
				and enemy.enemy_data.enemy_id == &"goblin"
			):
				enemy.summoner_boss = self
			continue
		var final_death_callback := _on_escort_final_death.bind(enemy_id)
		var resurrection_callback := _on_escort_resurrected.bind(enemy_id)
		enemy.final_death.connect(final_death_callback)
		enemy.resurrected.connect(resurrection_callback)
		_escort_connections[enemy_id] = {
			"enemy": enemy,
			"final_death_callback": final_death_callback,
			"resurrection_callback": resurrection_callback
		}
	if not newly_tracked.is_empty():
		var living_count := _get_living_summon_count()
		if boss_data.ability != BossData.Ability.SPIDER_MATRON:
			var ability_name := _get_ability_name()
			var spawned_positions := PackedStringArray()
			for enemy in newly_tracked:
				spawned_positions.append(
					"(%.1f,%.1f)" % [
						enemy.global_position.x,
						enemy.global_position.y
					]
				)
			_log_ability(
				ability_name,
				"summons_spawned",
				"count=%d living=%d types=%s positions=%s"
				% [
					newly_tracked.size(),
					living_count,
					String(boss_data.summon_enemy_data.enemy_id),
					", ".join(spawned_positions)
				]
			)
		if boss_data.ability == BossData.Ability.GHOUL:
			_log_ability(
				"ghoul_escorts",
				"spawned",
				"count=%d type=skeleton" % newly_tracked.size()
			)


func _get_ability_name() -> String:
	return BossData.Ability.keys()[boss_data.ability].to_lower()


func _log_ability(ability: String, event: String, details: String = "") -> void:
	BossAbilityDebug.log(self, ability, event, details)


func _on_summoned_enemy_tree_exited(enemy_id: int) -> void:
	var entry: Dictionary = _escort_connections.get(enemy_id, {})
	var enemy = entry.get("enemy")
	if is_instance_valid(enemy):
		var final_death_callback: Callable = entry["final_death_callback"]
		var resurrection_callback: Callable = entry["resurrection_callback"]
		if enemy.final_death.is_connected(final_death_callback):
			enemy.final_death.disconnect(final_death_callback)
		if enemy.resurrected.is_connected(resurrection_callback):
			enemy.resurrected.disconnect(resurrection_callback)
	_escort_connections.erase(enemy_id)
	_summoned_enemies.erase(enemy_id)


func _on_escort_final_death(_enemy_id: int) -> void:
	_heal_from_escort_event("escort_final_death")


func _on_escort_resurrected(_enemy_id: int) -> void:
	_heal_from_escort_event("escort_resurrection")


func _heal_from_escort_event(event: String) -> void:
	if is_dead:
		return
	if _healing_activations >= 3:
		if not _healing_limit_logged:
			_log_ability(
				"ghoul_healing",
				"activation_limit_reached",
				"maximum=3 ignored_event=%s" % event
			)
			_healing_limit_logged = true
		return
	_healing_activations += 1
	var previous_hp := hp
	hp = mini(
		hp + roundi(max_hp * boss_data.ability_multiplier),
		max_hp
	)
	update_health_bar()
	_log_ability(
		"ghoul_healing",
		"activated",
		"source=%s activation=%d/3 hp_restored=%d hp=%d/%d"
		% [event, _healing_activations, hp - previous_hp, hp, max_hp]
	)
	if _healing_activations == 3:
		_healing_limit_logged = true
		_log_ability("ghoul_healing", "activation_limit_reached", "maximum=3")


func _update_goblin_command_aura() -> void:
	var targets := _find_nearby_ordinary_enemies(
		&"goblin",
		boss_data.ability_radius,
		true
	)
	_update_speed_effect(
		_speed_aura_targets,
		targets,
		get_instance_id(),
		boss_data.ability_multiplier,
		"goblin_command",
		"movement_speed_increased"
	)


func _update_kobold_escort_boost(delta: float) -> void:
	if boss_data.ability_interval <= 0.0:
		return
	var was_active := _escort_boost_remaining > 0.0
	_escort_boost_cooldown -= delta
	if _escort_boost_cooldown <= 0.0:
		_escort_boost_cooldown += boss_data.ability_interval
		_escort_boost_remaining = boss_data.ability_duration
	_escort_boost_remaining = maxf(_escort_boost_remaining - delta, 0.0)
	if not was_active and _escort_boost_remaining > 0.0:
		_log_ability(
			"kobold_escort_command",
			"started",
			"duration=%.2fs" % _escort_boost_remaining
		)
	elif was_active and _escort_boost_remaining <= 0.0:
		_log_ability("kobold_escort_command", "ended")


func _update_kobold_auras() -> void:
	var targets := _find_nearby_ordinary_enemies(
		&"kobold",
		boss_data.ability_radius
	)
	_update_speed_effect(
		_speed_aura_targets,
		targets,
		get_instance_id(),
		boss_data.ability_multiplier,
		"kobold_nearby_buff",
		"movement_speed_increased"
	)
	if _escort_boost_remaining > 0.0:
		_update_speed_effect(
			_temporary_speed_targets,
			targets,
			-get_instance_id(),
			boss_data.secondary_multiplier,
			"kobold_escort_command",
			"temporary_speed_increased"
		)
	else:
		_clear_speed_effect(
			_temporary_speed_targets,
			-get_instance_id(),
			"kobold_escort_command",
			"temporary_speed_removed"
		)


func _update_orc_aura() -> void:
	var targets := _find_nearby_ordinary_enemies(&"orc", boss_data.ability_radius)
	_update_damage_effect(
		_damage_aura_targets,
		targets,
		get_instance_id(),
		boss_data.ability_multiplier,
		"orc_nearby_aura",
		"damage_reduction_applied"
	)


func _update_snake_tower_aura() -> void:
	var radius := boss_data.ability_radius
	var attack_speed_multiplier := boss_data.ability_multiplier
	if _has_lost_first_trophy:
		radius = boss_data.enraged_ability_radius
		attack_speed_multiplier = boss_data.enrage_multiplier

	var targets: Dictionary = {}
	for candidate in get_tree().get_nodes_in_group("towers"):
		if not candidate is Tower or candidate.is_queued_for_deletion():
			continue
		var tower := candidate as Tower
		if global_position.distance_to(tower.global_position) <= radius:
			targets[tower.get_instance_id()] = tower

	for tower_id in _tower_aura_targets.keys():
		if targets.has(tower_id):
			continue
		var old_tower = _tower_aura_targets[tower_id]
		if is_instance_valid(old_tower):
			old_tower.set_external_attack_speed_multiplier(
				get_instance_id(),
				attack_speed_multiplier,
				boss_data.tower_debuff_duration,
				"snake_attack_speed_aura",
				_get_debug_identity_context()
			)
			_track_tower_debuff(old_tower)
			_log_ability(
				"snake_attack_speed_aura",
				"tower_left",
				"tower=%s debuff_duration=%.1fs attack_speed_multiplier=%.2f"
				% [
					old_tower.name,
					boss_data.tower_debuff_duration,
					attack_speed_multiplier
				]
			)
		_tower_aura_targets.erase(tower_id)

	for tower_id in _tower_debuff_targets.keys():
		if not targets.has(tower_id):
			var lingering_tower = _tower_debuff_targets[tower_id]
			if not is_instance_valid(lingering_tower):
				_tower_debuff_targets.erase(tower_id)
				continue
			lingering_tower.update_external_attack_speed_multiplier(
				get_instance_id(),
				attack_speed_multiplier
			)
			continue

	for tower_id in targets:
		var tower: Tower = targets[tower_id]
		if _tower_debuff_targets.has(tower_id):
			_untrack_tower_debuff(tower_id)
			tower.set_external_attack_speed_multiplier(
				get_instance_id(),
				attack_speed_multiplier
			)
			_log_ability(
				"snake_attack_speed_aura",
				"tower_entered",
				"tower=%s radius=%.0f"
				% [tower.name, radius]
			)
			_log_ability(
				"snake_attack_speed_aura",
				"debuff_refreshed",
				"tower=%s duration=%.1fs attack_speed_multiplier=%.2f reduction=%.0f%%"
				% [
					tower.name,
					boss_data.tower_debuff_duration,
					attack_speed_multiplier,
					(1.0 - attack_speed_multiplier) * 100.0
				]
			)
		elif not _tower_aura_targets.has(tower_id):
			tower.set_external_attack_speed_multiplier(
				get_instance_id(),
				attack_speed_multiplier
			)
			_log_ability(
				"snake_attack_speed_aura",
				"tower_entered",
				"tower=%s radius=%.0f"
				% [tower.name, radius]
			)
			_log_ability(
				"snake_attack_speed_aura",
				"debuff_applied",
				"tower=%s duration=active attack_speed_multiplier=%.2f reduction=%.0f%%"
				% [
					tower.name,
					attack_speed_multiplier,
					(1.0 - attack_speed_multiplier) * 100.0
				]
			)
		else:
			tower.update_external_attack_speed_multiplier(
				get_instance_id(),
				attack_speed_multiplier
			)
		_tower_aura_targets[tower_id] = tower


func _find_nearby_ordinary_enemies(
	enemy_id: StringName,
	radius: float,
	only_behind: bool = false
) -> Dictionary:
	var targets: Dictionary = {}
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if (
			not candidate is Enemy
			or candidate is BossEnemy
			or candidate == self
			or candidate.is_dead
			or candidate.is_queued_for_deletion()
			or candidate.enemy_data == null
			or candidate.enemy_data.enemy_id != enemy_id
		):
			continue
		var enemy := candidate as Enemy
		if global_position.distance_to(enemy.global_position) > radius:
			continue
		if (
			only_behind
			and (
				enemy.movement_direction != MovementDirection.MOVING_TO_CASTLE
				or enemy.path_distance >= path_distance
			)
		):
			continue
		targets[enemy.get_instance_id()] = enemy
	return targets


func _update_speed_effect(
	tracked: Dictionary,
	targets: Dictionary,
	source_id: int,
	multiplier: float,
	ability: String = "",
	event: String = ""
) -> void:
	_clear_removed_targets(tracked, targets, source_id, false, ability)
	for enemy_id in targets:
		var enemy: Enemy = targets[enemy_id]
		var is_new_target := not tracked.has(enemy_id)
		enemy.set_speed_multiplier(source_id, multiplier)
		tracked[enemy_id] = enemy
		if is_new_target and not ability.is_empty():
			_log_ability(
				ability,
				event,
				"target=%s multiplier=%.2f"
				% [enemy.name, multiplier]
			)


func _update_damage_effect(
	tracked: Dictionary,
	targets: Dictionary,
	source_id: int,
	multiplier: float,
	ability: String = "",
	event: String = ""
) -> void:
	_clear_removed_targets(tracked, targets, source_id, true, ability)
	for enemy_id in targets:
		var enemy: Enemy = targets[enemy_id]
		var is_new_target := not tracked.has(enemy_id)
		enemy.set_damage_taken_multiplier(source_id, multiplier)
		tracked[enemy_id] = enemy
		if is_new_target and not ability.is_empty():
			_log_ability(
				ability,
				event,
				"target=%s damage_multiplier=%.2f"
				% [enemy.name, multiplier]
			)


func _clear_removed_targets(
	tracked: Dictionary,
	targets: Dictionary,
	source_id: int,
	damage_effect: bool,
	ability: String = ""
) -> void:
	for enemy_id in tracked.keys():
		if targets.has(enemy_id):
			continue
		var enemy = tracked[enemy_id]
		if is_instance_valid(enemy):
			if damage_effect:
				enemy.remove_damage_taken_multiplier(source_id)
			else:
				enemy.remove_speed_multiplier(source_id)
			if not ability.is_empty():
				_log_ability(
					ability,
					"target_left",
					"target=%s modifier_removed" % enemy.name
				)
		tracked.erase(enemy_id)


func _clear_speed_effect(
	tracked: Dictionary,
	source_id: int,
	ability: String = "",
	event: String = "target_left"
) -> void:
	for enemy in tracked.values():
		if is_instance_valid(enemy):
			enemy.remove_speed_multiplier(source_id)
			if not ability.is_empty():
				_log_ability(
					ability,
					event,
					"target=%s modifier_removed" % enemy.name
				)
	tracked.clear()


func _update_boss_regeneration(delta: float) -> void:
	var regeneration_rate := boss_data.regeneration_fraction_per_second
	if float(hp) / float(max_hp) < 0.3:
		regeneration_rate = boss_data.low_hp_regeneration_fraction_per_second
	if not is_equal_approx(regeneration_rate, _last_logged_regeneration_rate):
		_last_logged_regeneration_rate = regeneration_rate
		if regeneration_rate > 0.0:
			_log_ability(
				"troll_regeneration",
				"rate_changed",
				"rate=%.0f%%_max_hp_per_second hp=%d/%d"
				% [regeneration_rate * 100.0, hp, max_hp]
			)
	if regeneration_rate <= 0.0 or hp >= max_hp:
		_regeneration_remainder = 0.0
		_regeneration_log_elapsed = 0.0
		_regeneration_log_healed = 0
		return

	_regeneration_log_elapsed += delta
	_regeneration_remainder += max_hp * regeneration_rate * delta
	var regenerated := floori(_regeneration_remainder)
	if regenerated <= 0:
		return
	var previous_hp := hp
	hp = mini(hp + regenerated, max_hp)
	_regeneration_remainder -= hp - previous_hp
	_regeneration_log_healed += hp - previous_hp
	if hp >= max_hp:
		_regeneration_remainder = 0.0
	update_health_bar()
	if _regeneration_log_elapsed >= 5.0:
		if _regeneration_log_healed > 0:
			_log_ability(
				"troll_regeneration",
				"summary",
				"rate=%.0f%%_max_hp_per_second hp_restored=%d hp=%d/%d"
				% [
					regeneration_rate * 100.0,
					_regeneration_log_healed,
					hp,
					max_hp
				]
			)
		_regeneration_log_elapsed = 0.0
		_regeneration_log_healed = 0


func _regenerate(_delta: float) -> void:
	pass


func _on_damage_applied(_previous_hp: int) -> void:
	_update_boss_display()


func _get_damage_target_display_name() -> String:
	return (
		boss_data.display_name
		if boss_data != null
		else super._get_damage_target_display_name()
	)


func _update_first_return_trophy_drop() -> void:
	if (
		boss_data.ability != BossData.Ability.GOBLIN_CHIEF
		or _first_return_trophy_dropped
		or movement_direction != MovementDirection.RETURNING_TO_CAMP
		or _has_reached_start
		or _is_depositing
		or float(hp) / float(max_hp) > 0.5
		or carried_trophies.is_empty()
	):
		return
	var container: Node = get_parent()
	if container == null:
		return
	var trophy: Trophy = carried_trophies.pop_front()
	if not is_instance_valid(trophy):
		return
	trophy.reparent(container, true)
	trophy.global_position = global_position
	trophy.set_state(Trophy.State.DROPPED)
	_ignored_dropped_trophy_ids[trophy.get_instance_id()] = true
	_first_return_trophy_dropped = true
	_log_ability(
		"goblin_trophy_drop",
		"activated",
		"hp_threshold=50%% hp=%d/%d trophies_remaining=%d"
		% [hp, max_hp, carried_trophy_count]
	)


func _on_trophy_permanently_lost(_trophy: Trophy) -> void:
	if is_dead:
		return
	if _has_lost_first_trophy:
		_log_ability(
			"trophy_loss_reaction",
			"ignored",
			"reason=already_activated"
		)
		return
	_has_lost_first_trophy = true
	var previous_speed := speed
	match boss_data.ability:
		BossData.Ability.GOBLIN_CHIEF:
			speed = _scaled_speed * boss_data.enrage_multiplier
			_summon_timer = minf(
				_summon_timer,
				_get_current_summon_interval()
			)
		BossData.Ability.KOBOLD_CHIEF:
			speed = _scaled_speed * boss_data.enrage_multiplier
		BossData.Ability.ORC_CHIEF:
			set_damage_taken_multiplier(
				get_instance_id(),
				boss_data.enrage_multiplier
			)
	match boss_data.ability:
		BossData.Ability.GOBLIN_CHIEF:
			_log_ability(
				"goblin_enrage",
				"activated",
				"speed=%.2f summon_interval=%.2fs"
				% [speed, _get_current_summon_interval()]
			)
		BossData.Ability.KOBOLD_CHIEF:
			_log_ability(
				"kobold_boss_speed",
				"activated",
				"speed=%.2f previous_speed=%.2f" % [speed, previous_speed]
			)
		BossData.Ability.ORC_CHIEF:
			_log_ability(
				"orc_damage_reduction",
				"changed",
				"reduction=%.0f%%"
				% [(1.0 - boss_data.enrage_multiplier) * 100.0]
			)
		BossData.Ability.SPIDER_MATRON:
			_log_ability(
				"spider_summon",
				"interval_changed",
				"old=%.2fs new=%.2fs"
				% [boss_data.ability_interval, _get_current_summon_interval()]
			)
		BossData.Ability.SNAKE:
			_log_ability(
				"snake_attack_speed_aura",
				"parameters_changed",
				"radius=%.0f attack_speed_multiplier=%.2f reduction=%.0f%%"
				% [
					boss_data.enraged_ability_radius,
					boss_data.enrage_multiplier,
					(1.0 - boss_data.enrage_multiplier) * 100.0
				]
			)
	_update_boss_abilities(0.0)


func _on_poison_blocked() -> void:
	_log_ability("poison_immunity", "effect_blocked")


func _try_pick_up_dropped_trophy() -> bool:
	if (
		movement_direction == MovementDirection.MOVING_TO_CASTLE
		or enemy_data == null
		or not enemy_data.can_carry_trophy
		or not enemy_data.can_pickup_dropped_trophy
		or carried_trophy_count >= trophy_carrying_capacity
	):
		return false

	var closest_trophy: Trophy
	var closest_distance := dropped_trophy_pickup_radius
	for candidate in get_tree().get_nodes_in_group("dropped_trophies"):
		if not is_instance_valid(candidate) or not candidate is Trophy:
			continue
		var trophy := candidate as Trophy
		if (
			trophy.state != Trophy.State.DROPPED
			or _ignored_dropped_trophy_ids.has(trophy.get_instance_id())
		):
			continue
		var distance := global_position.distance_to(trophy.global_position)
		if distance <= closest_distance:
			closest_trophy = trophy
			closest_distance = distance

	if not is_instance_valid(closest_trophy):
		return false
	_attach_trophy(closest_trophy)
	return true


func _process_theft(delta: float) -> void:
	if _boss_theft_complete:
		return
	_boss_theft_elapsed += delta
	if _boss_theft_elapsed < theft_duration:
		return

	_boss_theft_complete = true
	if is_instance_valid(castle):
		while (
			carried_trophy_count < trophy_carrying_capacity
			and is_instance_valid(castle)
		):
			var trophy := castle.try_steal_trophy()
			if trophy == null:
				break
			_attach_trophy(trophy)
	start_return_to_camp()


func die() -> void:
	if is_dead:
		if boss_data != null and boss_data.ability == BossData.Ability.SKELETON:
			_log_ability(
				"skeleton_resurrection",
				"death_rejected",
				"reason=already_dead"
			)
		return
	if boss_data != null and boss_data.ability == BossData.Ability.SKELETON:
		if hp > 0:
			_log_ability(
				"skeleton_resurrection",
				"death_rejected",
				"reason=hp_above_zero hp=%d/%d" % [hp, max_hp]
			)
			return
		var lethal_hit := resurrection_count + 1
		_log_ability(
			"skeleton_resurrection",
			"lethal_hit",
			"hit=%d hp=0/%d" % [lethal_hit, max_hp]
		)
		if resurrection_count < SKELETON_RESURRECTION_PHASES.size():
			var phase_hp := roundi(
				max_hp * SKELETON_RESURRECTION_PHASES[resurrection_count]
			)
			resurrection_count += 1
			hp = maxi(phase_hp, 1)
			update_health_bar()
			_update_boss_display()
			_play_resurrection_feedback()
			resurrected.emit()
			_log_ability(
				"skeleton_resurrection",
				"resurrected",
				"phase=%d/3 hp=%d/%d"
				% [resurrection_count, hp, max_hp]
			)
			return
		_log_ability(
			"skeleton_resurrection",
			"final_lethal_hit",
			"hit=%d hp=0/%d" % [lethal_hit, max_hp]
		)
	_process_final_death()


func _process_final_death() -> void:
	if is_dead or boss_data == null:
		return
	is_dead = true
	_cancel_summon_sequence("boss_died")
	_cancel_spider_summon_batch()
	_movement_slows.clear()
	_speed_multipliers.clear()
	_damage_taken_multipliers.clear()
	_clear_bleed()
	_clear_boss_effects()
	_disconnect_escort_events()
	if is_instance_valid(_deposit_tween) and _deposit_tween.is_running():
		_deposit_tween.kill()
	_deposit_tween = null
	_is_depositing = false
	if not _drop_carried_trophies():
		return

	var reward_step := maxi(floori(float(wave_number - 10) / 10.0), 0)
	var gold_reward := roundi(
		boss_data.base_gold_reward * pow(GOLD_GROWTH_PER_STEP, reward_step)
	)
	gold_reward = roundi(gold_reward * wave_gold_multiplier)
	var essence_reward := roundi(
		boss_data.base_essence_reward
		* pow(ESSENCE_GROWTH_PER_STEP, reward_step)
	)
	GoldManager.add_gold(gold_reward)
	if not CrystalInventory.add_essence(essence_reward):
		push_error(
			"Boss reward Essence could not be saved for %s."
			% boss_data.display_name
		)
	if boss_data.ability == BossData.Ability.SKELETON:
		_log_ability(
			"skeleton_resurrection",
			"final_death",
			"lethal_hits=%d resurrections=%d"
			% [resurrection_count + 1, resurrection_count]
		)
	final_death.emit()
	_mark_inactive()
	queue_free()


func _clear_boss_effects() -> void:
	_clear_speed_effect(_speed_aura_targets, get_instance_id())
	_clear_speed_effect(_temporary_speed_targets, -get_instance_id())
	_clear_tracked_damage_targets()
	if boss_data != null and boss_data.ability == BossData.Ability.SNAKE:
		if _snake_effects_transferred:
			return
		_snake_effects_transferred = true
		for tower_id in _tower_aura_targets:
			var tower: Tower = _tower_aura_targets[tower_id]
			if not is_instance_valid(tower):
				continue
			tower.set_external_attack_speed_multiplier(
				get_instance_id(),
				_get_snake_attack_speed_multiplier(),
				boss_data.tower_debuff_duration,
				"snake_attack_speed_aura",
				_get_debug_identity_context()
			)
			_track_tower_debuff(tower)
			_log_ability(
				"snake_attack_speed_aura",
				"debuff_started_on_boss_death",
				"tower=%s duration=%.1fs"
				% [tower.name, boss_data.tower_debuff_duration]
			)
		_tower_aura_targets.clear()
		return
	for tower in _tower_aura_targets.values():
		if is_instance_valid(tower):
			tower.remove_external_attack_speed_multiplier(get_instance_id())
			_log_ability(
				"snake_attack_speed_aura",
				"tower_left",
				"tower=%s modifier_removed reason=boss_cleanup"
				% tower.name
			)
	_tower_aura_targets.clear()


func _track_tower_debuff(tower: Tower) -> void:
	var tower_id := tower.get_instance_id()
	_tower_debuff_targets[tower_id] = tower
	var callback := _on_tower_debuff_expired.bind(tower_id)
	if not tower.external_attack_speed_modifier_expired.is_connected(callback):
		tower.external_attack_speed_modifier_expired.connect(callback)


func _untrack_tower_debuff(tower_id: int) -> void:
	var tower = _tower_debuff_targets.get(tower_id) as Tower
	if is_instance_valid(tower):
		var callback := _on_tower_debuff_expired.bind(tower_id)
		if tower.external_attack_speed_modifier_expired.is_connected(callback):
			tower.external_attack_speed_modifier_expired.disconnect(callback)
	_tower_debuff_targets.erase(tower_id)


func _on_tower_debuff_expired(source_id: int, tower_id: int) -> void:
	if source_id == get_instance_id():
		_untrack_tower_debuff(tower_id)


func _get_snake_attack_speed_multiplier() -> float:
	return (
		boss_data.enrage_multiplier
		if _has_lost_first_trophy
		else boss_data.ability_multiplier
	)


func _get_debug_identity_context() -> String:
	if boss_data == null:
		return ""
	return "wave=%d boss=%s(%s#%d) " % [
		wave_number,
		boss_data.display_name,
		boss_data.boss_id,
		get_instance_id()
	]


func _clear_tracked_damage_targets() -> void:
	_clear_removed_targets(
		_damage_aura_targets,
		{},
		get_instance_id(),
		true
	)


func _disconnect_escort_events() -> void:
	for entry in _escort_connections.values():
		var enemy = entry["enemy"]
		if not is_instance_valid(enemy):
			continue
		var final_death_callback: Callable = entry["final_death_callback"]
		var resurrection_callback: Callable = entry["resurrection_callback"]
		if enemy.final_death.is_connected(final_death_callback):
			enemy.final_death.disconnect(final_death_callback)
		if enemy.resurrected.is_connected(resurrection_callback):
			enemy.resurrected.disconnect(resurrection_callback)
	_escort_connections.clear()


func _update_boss_display() -> void:
	if not is_instance_valid(_boss_name_label) or boss_data == null:
		return
	_boss_name_label.text = "%s  %d / %d" % [
		boss_data.display_name,
		hp,
		max_hp
	]


func _exit_tree() -> void:
	_cancel_summon_sequence("boss_removed")
	_cancel_spider_summon_batch()
	_log_ability(
		"lifecycle",
		"cleanup",
		"reason=%s" % ("death" if is_dead else "removed")
	)
	_clear_boss_effects()
	_disconnect_escort_events()
	super._exit_tree()
