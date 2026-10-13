class_name Enemy
extends Node2D

enum MovementDirection {
	MOVING_TO_CASTLE,
	RETURNING_TO_CAMP
}

enum SummonMovementMode {
	NONE,
	INTERCEPT_BOSS,
	FOLLOW_BOSS
}

signal became_inactive
signal final_death
signal resurrected

@export var enemy_data: EnemyData
@export_range(0.0, 30.0, 0.1) var theft_duration: float = 1.0
@export_range(0, 10, 1) var trophy_carrying_capacity: int = 1
@export_range(1.0, 100.0, 1.0) var dropped_trophy_pickup_radius: float = 28.0
var active_modifiers: Array[EnemyModifierData] = []
var castle: Castle
var camp: EnemyCamp
var carried_trophies: Array[Trophy] = []
var summoner_boss: Node2D
var summon_movement_mode: SummonMovementMode = SummonMovementMode.NONE

var carried_trophy_count: int:
	get:
		return carried_trophies.size()
var is_carrying_trophy: bool:
	get:
		return not carried_trophies.is_empty()
var can_carry_trophy: bool:
	get:
		return enemy_data != null and enemy_data.can_carry_trophy

var base_hp: int:
	get:
		return enemy_data.base_hp
var base_speed: float:
	get:
		return enemy_data.base_speed
var gold_reward: int:
	get:
		return enemy_data.gold_reward

var max_hp: int
var hp: int
var speed: float
var effective_speed: float:
	get:
		var strongest_slow := 0.0
		var speed_multiplier := 1.0
		for multiplier in _speed_multipliers.values():
			speed_multiplier *= float(multiplier)
		for slow_data in _movement_slows.values():
			strongest_slow = maxf(strongest_slow, float(slow_data["fraction"]))
		return maxf(speed * speed_multiplier * (1.0 - strongest_slow), 0.0)

var wave_number: int = 0
var wave_gold_multiplier: float = 1.0
var is_planned_wave_enemy: bool = true

var path: Curve2D
var path_distance: float = 0.0
var movement_direction: MovementDirection = MovementDirection.MOVING_TO_CASTLE
var first_target_progress: float:
	get:
		if path == null:
			return path_distance
		var path_length := path.get_baked_length()
		if movement_direction == MovementDirection.RETURNING_TO_CAMP:
			return path_length - path_distance
		return path_distance
var is_dead: bool = false
var _has_become_inactive: bool = false
var resurrection_count: int = 0
var _combat_rng := RandomNumberGenerator.new()
var _regeneration_hp_remainder: float = 0.0
var _has_reached_castle: bool = false
var _returning_to_start: bool = false
var _has_reached_start: bool = false
var _is_depositing: bool = false
var _deposit_tween: Tween
var _theft_elapsed: float = 0.0
var _theft_attempted: bool = false
var _movement_stop_remaining: float = 0.0
var _movement_slows: Dictionary = {}
var _speed_multipliers: Dictionary = {}
var _damage_taken_multipliers: Dictionary = {}
var _damage_over_time_effects: Dictionary = {}
var _bleed_remaining: float:
	get:
		return float(
			_damage_over_time_effects.get(&"bleed", {}).get("remaining", 0.0)
		)

@onready var _visual: Sprite2D = $Visual


func initialize_for_wave(
	data: EnemyData,
	value: int,
	final_speed: float,
	owning_wave_number: int,
	owning_wave_gold_multiplier: float,
	is_planned: bool = true,
	modifiers: Array[EnemyModifierData] = []
) -> void:
	enemy_data = data
	movement_direction = MovementDirection.MOVING_TO_CASTLE
	active_modifiers = modifiers.duplicate()
	max_hp = maxi(value, 1)
	hp = max_hp
	speed = final_speed
	wave_number = owning_wave_number
	wave_gold_multiplier = owning_wave_gold_multiplier
	is_planned_wave_enemy = is_planned


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if enemy_data == null:
		push_error("Enemy requires EnemyData.")
		return
	if max_hp <= 0:
		max_hp = enemy_data.base_hp
		hp = max_hp
	if speed <= 0.0:
		speed = enemy_data.base_speed

	_combat_rng.randomize()
	_visual.texture = enemy_data.visual_texture
	_visual.scale = Vector2.ONE * enemy_data.visual_scale
	add_to_group("enemies")
	update_health_bar()


func _exit_tree() -> void:
	_movement_slows.clear()
	_speed_multipliers.clear()
	_damage_taken_multipliers.clear()
	_clear_bleed()
	_clear_poison()
	_damage_over_time_effects.erase(&"self_damage")


func set_speed_multiplier(source_id: int, multiplier: float) -> void:
	if is_dead or not is_finite(multiplier):
		return
	_speed_multipliers[source_id] = maxf(multiplier, 0.0)


func remove_speed_multiplier(source_id: int) -> void:
	_speed_multipliers.erase(source_id)


func stop_movement_for(duration: float) -> void:
	if is_dead or not is_finite(duration) or duration <= 0.0:
		return
	_movement_stop_remaining = maxf(_movement_stop_remaining, duration)


func set_damage_taken_multiplier(source_id: int, multiplier: float) -> void:
	if is_dead or not is_finite(multiplier):
		return
	_damage_taken_multipliers[source_id] = clampf(multiplier, 0.0, 1.0)


func remove_damage_taken_multiplier(source_id: int) -> void:
	_damage_taken_multipliers.erase(source_id)


func _get_damage_taken_multiplier() -> float:
	var multiplier := 1.0
	for source_multiplier in _damage_taken_multipliers.values():
		multiplier *= float(source_multiplier)
	return clampf(multiplier, 0.0, 1.0)


func set_movement_slow(source_id: int, slow_fraction: float) -> void:
	if is_dead or not is_finite(slow_fraction):
		return

	_movement_slows[source_id] = {
		"fraction": clampf(slow_fraction, 0.0, 1.0),
		"remaining": -1.0
	}


func remove_movement_slow(source_id: int, linger_duration: float = 0.0) -> void:
	if linger_duration > 0.0 and _movement_slows.has(source_id):
		var slow_data: Dictionary = _movement_slows[source_id]
		slow_data["remaining"] = linger_duration
		_movement_slows[source_id] = slow_data
	else:
		_movement_slows.erase(source_id)


func apply_bleed(max_hp_fraction_per_second: float, duration: float) -> void:
	_apply_damage_over_time(
		&"bleed",
		max_hp_fraction_per_second,
		duration
	)


func apply_continuous_self_damage(max_hp_fraction_per_second: float) -> void:
	if (
		is_dead
		or not is_finite(max_hp_fraction_per_second)
		or max_hp_fraction_per_second <= 0.0
	):
		return

	_damage_over_time_effects[&"self_damage"] = {
		"elapsed": 0.0,
		"damage_remainder": 0.0,
		"fraction_per_second": clampf(
			max_hp_fraction_per_second,
			0.0,
			1.0
		),
		"remaining": -1.0
	}


func apply_poison(max_hp_fraction_per_second: float, duration: float) -> void:
	if is_immune_to_poison():
		_on_poison_blocked()
		return
	_apply_damage_over_time(
		&"poison",
		max_hp_fraction_per_second,
		duration
	)


func _apply_damage_over_time(
	effect_id: StringName,
	max_hp_fraction_per_second: float,
	duration: float
) -> void:
	if (
		is_dead
		or not is_finite(max_hp_fraction_per_second)
		or not is_finite(duration)
		or max_hp_fraction_per_second <= 0.0
		or duration <= 0.0
	):
		return

	var effect: Dictionary = _damage_over_time_effects.get(effect_id, {})
	if float(effect.get("remaining", 0.0)) <= 0.0:
		effect["elapsed"] = 0.0
		effect["damage_remainder"] = 0.0
	effect["fraction_per_second"] = clampf(
		max_hp_fraction_per_second,
		0.0,
		1.0
	)
	effect["remaining"] = duration
	_damage_over_time_effects[effect_id] = effect


func is_immune_to_poison() -> bool:
	return false


func _on_poison_blocked() -> void:
	pass


func take_damage(amount: int):
	if is_dead or amount <= 0:
		return
	var previous_hp := hp
	var effective_damage := roundi(float(amount) * _get_damage_taken_multiplier())
	hp = maxi(hp - effective_damage, 0)

	_on_damage_applied(previous_hp)
	update_health_bar()
	BossAbilityDebug.log_damage(
		_get_damage_target_display_name(),
		amount,
		maxi(previous_hp - hp, 0),
		previous_hp,
		hp
	)

	if hp <= 0:
		die()


func _on_damage_applied(_previous_hp: int) -> void:
	pass


func _get_damage_target_display_name() -> String:
	return enemy_data.display_name if enemy_data != null else "Unknown"


func die():
	if is_dead:
		return

	_regeneration_hp_remainder = 0.0
	if _try_resurrect():
		return

	_process_final_death()


func _process_final_death() -> void:
	if is_dead:
		return

	is_dead = true
	_movement_slows.clear()
	_clear_bleed()
	_clear_poison()
	_damage_over_time_effects.erase(&"self_damage")
	if is_instance_valid(_deposit_tween) and _deposit_tween.is_running():
		_deposit_tween.kill()
	_deposit_tween = null
	_is_depositing = false
	if not _drop_carried_trophies():
		return
	var final_reward := floori(float(gold_reward) * wave_gold_multiplier)
	GoldManager.add_gold(final_reward)
	_award_essence_points()
	final_death.emit()
	_mark_inactive()
	queue_free()


func _award_essence_points() -> void:
	if enemy_data == null or enemy_data.essence_points <= 0:
		return

	var awarded_essence := CrystalInventory.add_essence_points(
		enemy_data.essence_points
	)
	if awarded_essence > 0:
		_show_essence_drop(awarded_essence)


# The balance is already updated; this is only visual feedback at the kill site.
func _show_essence_drop(amount: int) -> void:
	var container: Node = get_tree().current_scene
	if container == null:
		container = get_parent()
	if container == null:
		return

	var drop := Label.new()
	drop.text = "+%d Essence" % amount
	drop.top_level = true
	drop.z_index = 100
	drop.add_theme_font_size_override("font_size", 20)
	drop.add_theme_color_override("font_color", Color(0.66, 0.89, 1.0))
	drop.add_theme_color_override("font_outline_color", Color.BLACK)
	drop.add_theme_constant_override("outline_size", 4)
	container.add_child(drop)
	drop.global_position = global_position + Vector2(-30.0, -40.0)
	var tween := drop.create_tween()
	tween.set_parallel(true)
	tween.tween_property(drop, "global_position:y", drop.global_position.y - 40.0, 1.0)
	tween.tween_property(drop, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(drop.queue_free)


func _try_resurrect() -> bool:
	if not enemy_data.can_resurrect:
		return false
	if resurrection_count >= enemy_data.max_resurrections:
		return false
	if _combat_rng.randf() >= clampf(enemy_data.resurrection_chance, 0.0, 1.0):
		return false

	resurrection_count += 1
	var hp_fraction := clampf(enemy_data.resurrection_hp_percent, 0.0, 1.0)
	hp = maxi(roundi(max_hp * hp_fraction), 1)
	update_health_bar()
	_play_resurrection_feedback()
	resurrected.emit()
	return true


func _play_resurrection_feedback() -> void:
	_visual.modulate = Color(2.0, 2.0, 2.0, 1.0)
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", Color.WHITE, 0.3)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if is_dead or enemy_data == null:
		return
	_process_movement_slows(delta)
	_process_bleed(delta)
	_process_poison(delta)
	_process_damage_over_time(&"self_damage", delta)
	if is_dead or is_queued_for_deletion():
		return
	if _movement_stop_remaining > 0.0:
		_movement_stop_remaining = maxf(_movement_stop_remaining - delta, 0.0)
		if _movement_stop_remaining > 0.0:
			return
	if _process_summon_movement(delta):
		_regenerate(delta)
		return

	if _has_reached_start:
		return

	if _returning_to_start:
		_process_return_path(delta)
		_regenerate(delta)
		return

	if _has_reached_castle:
		_process_theft(delta)
		_regenerate(delta)
		return

	if path != null:
		var max_distance = path.get_baked_length()
		path_distance = minf(path_distance + effective_speed * delta, max_distance)
		position = path.sample_baked(path_distance)
		if _try_pick_up_dropped_trophy():
			_regenerate(delta)
			return

		if path_distance >= max_distance:
			_has_reached_castle = true
			_mark_inactive()
			_process_theft(0.0)
			_regenerate(delta)
			return

	_regenerate(delta)


func _process_summon_movement(delta: float) -> bool:
	if summon_movement_mode == SummonMovementMode.NONE:
		if (
			is_instance_valid(summoner_boss)
			and not bool(summoner_boss.get("is_dead"))
			and int(summoner_boss.get("movement_direction"))
				== MovementDirection.RETURNING_TO_CAMP
			and movement_direction == MovementDirection.MOVING_TO_CASTLE
		):
			summon_movement_mode = SummonMovementMode.INTERCEPT_BOSS
			BossAbilityDebug.log(
				summoner_boss,
				"goblin_interception",
				"started",
				"summon=%s" % name
			)
		else:
			return false

	if (
		not is_instance_valid(summoner_boss)
		or bool(summoner_boss.get("is_dead"))
	):
		if summon_movement_mode == SummonMovementMode.INTERCEPT_BOSS:
			movement_direction = MovementDirection.MOVING_TO_CASTLE
			_returning_to_start = false
		summon_movement_mode = SummonMovementMode.NONE
		summoner_boss = null
		return false

	var boss_path := summoner_boss.get("path") as Curve2D
	if path == null or boss_path != path:
		BossAbilityDebug.log(
			summoner_boss,
			"goblin_interception",
			"rejected",
			"reason=invalid_or_mismatched_path summon=%s" % name
		)
		summon_movement_mode = SummonMovementMode.NONE
		summoner_boss = null
		return false

	if summon_movement_mode == SummonMovementMode.INTERCEPT_BOSS:
		if (
			int(summoner_boss.get("movement_direction"))
			!= MovementDirection.RETURNING_TO_CAMP
		):
			summon_movement_mode = SummonMovementMode.NONE
			return false
		var boss_path_distance := float(summoner_boss.get("path_distance"))
		if path_distance > boss_path_distance:
			path_distance = maxf(
				path_distance - effective_speed * delta,
				boss_path_distance
			)
		else:
			path_distance = minf(
				path_distance + effective_speed * delta,
				boss_path_distance
			)
		position = path.sample_baked(path_distance)
		if (
			global_position.distance_to(summoner_boss.global_position) <= 28.0
			or absf(path_distance - boss_path_distance) <= 28.0
		):
			movement_direction = MovementDirection.RETURNING_TO_CAMP
			_returning_to_start = true
			summon_movement_mode = SummonMovementMode.FOLLOW_BOSS
			BossAbilityDebug.log(
				summoner_boss,
				"goblin_interception",
				"escort_started",
				"summon=%s path_distance=%.1f" % [name, path_distance]
			)
		return true

	if (
		int(summoner_boss.get("movement_direction"))
		!= MovementDirection.RETURNING_TO_CAMP
	):
		summon_movement_mode = SummonMovementMode.NONE
		summoner_boss = null
		return false

	var follow_distance := maxf(
		float(summoner_boss.get("path_distance")) - 28.0,
		0.0
	)
	if path_distance > follow_distance:
		path_distance = maxf(path_distance - effective_speed * delta, follow_distance)
	else:
		path_distance = minf(path_distance + effective_speed * delta, follow_distance)
	position = path.sample_baked(path_distance)
	return true


func _process_theft(delta: float) -> void:
	if _theft_attempted:
		return

	_theft_elapsed += delta
	if _theft_elapsed < theft_duration:
		return

	_theft_attempted = true
	if not is_instance_valid(castle):
		push_warning("Enemy reached the Castle without a valid Castle reference.")
		start_return_to_camp()
		return

	if not _can_carry_trophy():
		start_return_to_camp()
		return

	var stolen_trophy := castle.try_steal_trophy()
	if stolen_trophy == null:
		start_return_to_camp()
		return

	_attach_trophy(stolen_trophy)
	start_return_to_camp()


func _can_carry_trophy() -> bool:
	return (
		enemy_data != null
		and enemy_data.can_carry_trophy
		and trophy_carrying_capacity > 0
		and carried_trophy_count < trophy_carrying_capacity
	)


func _attach_trophy(trophy: Trophy) -> void:
	if trophy.get_parent() == null:
		add_child(trophy)
	else:
		trophy.reparent(self)
	trophy.position = Vector2(28.0, -18.0)
	trophy.set_state(Trophy.State.CARRIED)
	carried_trophies.append(trophy)


func _try_pick_up_dropped_trophy() -> bool:
	if (
		enemy_data == null
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
		if trophy.state != Trophy.State.DROPPED:
			continue

		var distance := global_position.distance_to(trophy.global_position)
		if distance <= closest_distance:
			closest_trophy = trophy
			closest_distance = distance

	if not is_instance_valid(closest_trophy):
		return false

	var was_moving_to_castle := movement_direction == MovementDirection.MOVING_TO_CASTLE
	_attach_trophy(closest_trophy)
	if was_moving_to_castle:
		start_return_to_camp()
	return true


func start_return_to_camp() -> void:
	if _returning_to_start:
		return

	_returning_to_start = true
	movement_direction = MovementDirection.RETURNING_TO_CAMP


func _drop_carried_trophies() -> bool:
	if carried_trophies.is_empty():
		return true

	var drop_container: Node = get_parent()
	if drop_container == null:
		drop_container = get_tree().current_scene
	if drop_container == null:
		push_error("Cannot drop carried Trophy because no world container is available.")
		return false

	while not carried_trophies.is_empty():
		var trophy: Trophy = carried_trophies.pop_back()
		if not is_instance_valid(trophy):
			continue

		var drop_position := global_position
		trophy.reparent(drop_container, true)
		trophy.global_position = drop_position
		trophy.set_state(Trophy.State.DROPPED)
	return true


func _process_return_path(delta: float) -> void:
	if _has_reached_start:
		return

	if path == null:
		_has_reached_start = true
		_finalize_return()
		return

	path_distance -= effective_speed * delta
	if path_distance <= 0.0:
		path_distance = 0.0
		position = path.sample_baked(path_distance)
		_try_pick_up_dropped_trophy()
		_has_reached_start = true
		_finalize_return()
		return

	position = path.sample_baked(path_distance)
	_try_pick_up_dropped_trophy()


func _finalize_return() -> void:
	if not is_carrying_trophy:
		queue_free()
		return

	if not is_instance_valid(camp) or not is_instance_valid(castle):
		push_error("Enemy cannot deposit Trophy without valid camp and Castle references.")
		return

	if _is_depositing:
		return

	_is_depositing = true
	_deposit_carried_trophies()


func _deposit_carried_trophies() -> void:
	while not carried_trophies.is_empty() and not is_dead:
		var trophy: Trophy = carried_trophies[0]
		if not is_instance_valid(trophy):
			carried_trophies.pop_front()
			continue

		var destination := camp.get_next_deposit_global_position()
		_deposit_tween = create_tween()
		_deposit_tween.set_trans(Tween.TRANS_SINE)
		_deposit_tween.set_ease(Tween.EASE_IN_OUT)
		_deposit_tween.tween_property(trophy, "global_position", destination, 0.35)
		_deposit_tween.tween_callback(_complete_trophy_deposit.bind(trophy))
		return

	if not is_dead:
		_is_depositing = false
		queue_free()


func _complete_trophy_deposit(trophy: Trophy) -> void:
	_deposit_tween = null
	if is_dead or not is_instance_valid(trophy) or not carried_trophies.has(trophy):
		return
	if not camp.deposit_trophy(trophy):
		push_warning("Enemy could not transfer a Trophy into the camp storage.")
		_is_depositing = false
		return

	carried_trophies.erase(trophy)
	castle.register_permanent_trophy_loss(trophy.trophy_id)
	_on_trophy_permanently_lost(trophy)
	_deposit_carried_trophies()


func _on_trophy_permanently_lost(_trophy: Trophy) -> void:
	pass


func _get_debug_identifier() -> String:
	var enemy_name := "unknown"
	if enemy_data != null and not enemy_data.enemy_id.is_empty():
		enemy_name = String(enemy_data.enemy_id)
	return "%s#%d" % [enemy_name, get_instance_id()]


func _regenerate(delta: float) -> void:
	if (
		not enemy_data.can_regenerate
		or hp <= 0
		or hp >= max_hp
		or delta <= 0.0
		or enemy_data.regeneration_percent_max_hp_per_second <= 0.0
	):
		if hp >= max_hp:
			_regeneration_hp_remainder = 0.0
		return

	_regeneration_hp_remainder += (
		max_hp
		* enemy_data.regeneration_percent_max_hp_per_second
		* delta
	)
	var regenerated_hp := floori(_regeneration_hp_remainder)
	if regenerated_hp <= 0:
		return

	var previous_hp := hp
	hp = mini(hp + regenerated_hp, max_hp)
	_regeneration_hp_remainder -= hp - previous_hp
	if hp >= max_hp:
		_regeneration_hp_remainder = 0.0
	update_health_bar()


func _process_bleed(delta: float) -> void:
	_process_damage_over_time(&"bleed", delta)


func _process_poison(delta: float) -> void:
	_process_damage_over_time(&"poison", delta)


func _process_damage_over_time(effect_id: StringName, delta: float) -> void:
	if not _damage_over_time_effects.has(effect_id) or delta <= 0.0:
		return

	var effect: Dictionary = _damage_over_time_effects[effect_id]
	var remaining := float(effect["remaining"])
	var elapsed := float(effect["elapsed"])
	var damage_remainder := float(effect["damage_remainder"])
	if remaining < 0.0:
		elapsed += delta
	else:
		elapsed += minf(delta, remaining)
		remaining = maxf(remaining - delta, 0.0)

	while elapsed >= 1.0:
		elapsed -= 1.0
		damage_remainder += (
			float(max_hp) * float(effect["fraction_per_second"])
		)
		var tick_damage := floori(damage_remainder)
		damage_remainder -= tick_damage
		if tick_damage > 0:
			take_damage(tick_damage)
			if is_dead or is_queued_for_deletion():
				return

	if remaining == 0.0:
		_damage_over_time_effects.erase(effect_id)
		return
	effect["elapsed"] = elapsed
	effect["damage_remainder"] = damage_remainder
	effect["remaining"] = remaining
	_damage_over_time_effects[effect_id] = effect


func _process_movement_slows(delta: float) -> void:
	if delta <= 0.0:
		return

	for source_id in _movement_slows.keys():
		var slow_data: Dictionary = _movement_slows[source_id]
		if float(slow_data["remaining"]) < 0.0:
			continue

		slow_data["remaining"] = maxf(
			float(slow_data["remaining"]) - delta,
			0.0
		)
		if float(slow_data["remaining"]) == 0.0:
			_movement_slows.erase(source_id)
		else:
			_movement_slows[source_id] = slow_data


func _clear_bleed() -> void:
	_damage_over_time_effects.erase(&"bleed")


func _clear_poison() -> void:
	_damage_over_time_effects.erase(&"poison")


func update_health_bar():
	$HealthBar.max_value = max_hp
	$HealthBar.value = hp


func _mark_inactive() -> void:
	if _has_become_inactive:
		return

	_has_become_inactive = true
	became_inactive.emit()
