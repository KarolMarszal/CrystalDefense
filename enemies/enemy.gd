class_name Enemy
extends Node2D

enum MovementDirection {
	MOVING_TO_CASTLE,
	RETURNING_TO_CAMP
}

signal became_inactive

@export var enemy_data: EnemyData
@export_range(0.0, 30.0, 0.1) var theft_duration: float = 1.0
@export_range(0, 10, 1) var trophy_carrying_capacity: int = 1
@export_range(1.0, 100.0, 1.0) var dropped_trophy_pickup_radius: float = 28.0
var active_modifiers: Array[EnemyModifierData] = []
var castle: Castle
var camp: EnemyCamp
var carried_trophies: Array[Trophy] = []

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
		for slow_data in _movement_slows.values():
			strongest_slow = maxf(strongest_slow, float(slow_data["fraction"]))
		return maxf(speed * (1.0 - strongest_slow), 0.0)

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
var _movement_slows: Dictionary = {}
var _bleed_max_hp_fraction_per_second: float = 0.0
var _bleed_remaining: float = 0.0
var _bleed_tick_elapsed: float = 0.0
var _bleed_damage_remainder: float = 0.0

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
	print("Enemy created. HP: ", hp)


func _exit_tree() -> void:
	_movement_slows.clear()
	_clear_bleed()


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
	if (
		is_dead
		or not is_finite(max_hp_fraction_per_second)
		or not is_finite(duration)
		or max_hp_fraction_per_second <= 0.0
		or duration <= 0.0
	):
		return

	if _bleed_remaining <= 0.0:
		_bleed_tick_elapsed = 0.0
		_bleed_damage_remainder = 0.0
	_bleed_max_hp_fraction_per_second = clampf(
		max_hp_fraction_per_second,
		0.0,
		1.0
	)
	_bleed_remaining = duration


func take_damage(amount: int):
	hp -= amount

	if hp < 0:
		hp = 0

	update_health_bar()

	print("enemy took ", amount, " damage. Hp left: ", hp)

	if hp <= 0:
		die()

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
	if is_instance_valid(_deposit_tween) and _deposit_tween.is_running():
		_deposit_tween.kill()
	_deposit_tween = null
	_is_depositing = false
	if not _drop_carried_trophies():
		return
	var final_reward := floori(float(gold_reward) * wave_gold_multiplier)
	GoldManager.add_gold(final_reward)
	_mark_inactive()
	print("Enemy died!")
	queue_free()


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
	if is_dead or is_queued_for_deletion():
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
			print("Enemy reached the end.")
			_has_reached_castle = true
			_mark_inactive()
			_process_theft(0.0)
			_regenerate(delta)
			return

	_regenerate(delta)


func _process_theft(delta: float) -> void:
	if _theft_attempted:
		return

	_theft_elapsed += delta
	if _theft_elapsed < theft_duration:
		return

	_theft_attempted = true
	if not is_instance_valid(castle):
		push_warning("Enemy reached the Castle without a valid Castle reference.")
		_start_return_phase()
		return

	if not _can_carry_trophy():
		_start_return_phase()
		return

	var stolen_trophy := castle.try_steal_trophy()
	if stolen_trophy == null:
		print(
			"[Enemy %s] No Trophy available. Returning without Trophy."
			% _get_debug_identifier()
		)
		_start_return_phase()
		return

	_attach_trophy(stolen_trophy)
	print(
		"[Enemy %s] Stole Trophy. Carrying 1 Trophy. Returning to start."
		% _get_debug_identifier()
	)
	_start_return_phase()


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
	var message: String
	if was_moving_to_castle:
		_start_return_phase()
		message = "[Enemy %s] Picked up dropped Trophy. Returning to camp."
	else:
		message = "[Enemy %s] Picked up dropped Trophy while returning."
	print(message % _get_debug_identifier())
	return true


func _start_return_phase() -> void:
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

	var dropped_trophy_count := 0
	while not carried_trophies.is_empty():
		var trophy: Trophy = carried_trophies.pop_back()
		if not is_instance_valid(trophy):
			continue

		var drop_position := global_position
		trophy.reparent(drop_container, true)
		trophy.global_position = drop_position
		trophy.set_state(Trophy.State.DROPPED)
		dropped_trophy_count += 1

	if dropped_trophy_count > 0:
		print(
			"[Enemy %s] Died while carrying Trophy. Trophy dropped at current position."
			% _get_debug_identifier()
		)
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
		print("[Enemy %s] Reached start without Trophy." % _get_debug_identifier())
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
	_deposit_carried_trophies()


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
	if _bleed_remaining <= 0.0 or delta <= 0.0:
		return

	var active_delta := minf(delta, _bleed_remaining)
	_bleed_tick_elapsed += active_delta
	_bleed_remaining = maxf(_bleed_remaining - delta, 0.0)

	while _bleed_tick_elapsed >= 1.0:
		_bleed_tick_elapsed -= 1.0
		_bleed_damage_remainder += (
			float(max_hp) * _bleed_max_hp_fraction_per_second
		)
		var tick_damage := floori(_bleed_damage_remainder)
		_bleed_damage_remainder -= tick_damage
		if tick_damage > 0:
			take_damage(tick_damage)
			if is_dead or is_queued_for_deletion():
				return

	if _bleed_remaining == 0.0:
		_clear_bleed()


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
	_bleed_max_hp_fraction_per_second = 0.0
	_bleed_remaining = 0.0
	_bleed_tick_elapsed = 0.0
	_bleed_damage_remainder = 0.0

func update_health_bar():
	$HealthBar.max_value = max_hp
	$HealthBar.value = hp


func _mark_inactive() -> void:
	if _has_become_inactive:
		return

	_has_become_inactive = true
	became_inactive.emit()
