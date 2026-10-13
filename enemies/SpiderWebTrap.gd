class_name SpiderWebTrap
extends Node2D

const SLOW_FRACTION := 0.5
const DURATION := 5.0
const AFFECTED_RADIUS := 56.0

var _remaining: float
var _inside_enemies: Dictionary = {}
var _last_positions: Dictionary = {}
var _affected_enemies: Dictionary = {}


func _ready() -> void:
	_remaining = DURATION


func _process(delta: float) -> void:
	if delta <= 0.0:
		return

	_remaining = maxf(_remaining - delta, 0.0)
	if _remaining <= 0.0:
		queue_free()
		return
	_update_enemy_contacts()


func _update_enemy_contacts() -> void:
	var present_enemies: Dictionary = {}
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not candidate is Enemy:
			continue
		var enemy := candidate as Enemy
		if (
			enemy.is_dead
			or not enemy.is_planned_wave_enemy
			or enemy is BossEnemy
		):
			continue

		var enemy_id := enemy.get_instance_id()
		present_enemies[enemy_id] = true
		var current_position := enemy.global_position
		var previous_position: Vector2 = _last_positions.get(
			enemy_id,
			current_position
		)
		var segment := current_position - previous_position
		var closest_position := previous_position
		if segment.length_squared() > 0.0:
			var segment_progress := clampf(
				(global_position - previous_position).dot(segment)
					/ segment.length_squared(),
				0.0,
				1.0
			)
			closest_position += segment * segment_progress
		var intersects_web := (
			closest_position.distance_to(global_position) <= AFFECTED_RADIUS
		)

		if intersects_web:
			if not _inside_enemies.has(enemy_id):
				enemy.set_movement_slow(get_instance_id(), SLOW_FRACTION)
				_affected_enemies[enemy_id] = enemy
			_inside_enemies[enemy_id] = true
		else:
			_inside_enemies.erase(enemy_id)
		_last_positions[enemy_id] = current_position

	for enemy_id in _last_positions.keys():
		if not present_enemies.has(enemy_id):
			_last_positions.erase(enemy_id)
			_inside_enemies.erase(enemy_id)

	for enemy_id in _affected_enemies.keys():
		if not is_instance_valid(_affected_enemies[enemy_id]):
			_affected_enemies.erase(enemy_id)


func _exit_tree() -> void:
	for enemy in _affected_enemies.values():
		if is_instance_valid(enemy):
			enemy.remove_movement_slow(get_instance_id())
	_affected_enemies.clear()
	_inside_enemies.clear()
	_last_positions.clear()
