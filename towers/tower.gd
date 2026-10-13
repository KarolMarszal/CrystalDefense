class_name Tower
extends Area2D

enum TargetPriority {
	NEAREST,
	FIRST,
	STRONGEST
}

enum UpgradeTrack {
	UPGRADE_1,
	UPGRADE_2,
	UPGRADE_3
}

const TOWER_UPGRADE_BASE_COSTS: Array[int] = [30, 40, 35]
const TOWER_UPGRADE_COST_GROWTH: float = 1.45
const TOWER_UPGRADE_MULTIPLIER: float = 1.2
const MAX_UPGRADE_COST: int = 9223372036854775807
const BASIC_UPGRADE_NAMES: Array[String] = ["Damage", "Attack Speed", "Range"]
const CRYSTAL_INSTALL_HIGHLIGHT_COLOR := Color(0.57, 1.0, 0.68, 0.8)
const CRYSTAL_INSTALL_HOVER_COLOR := Color(1.0, 0.83, 0.36, 0.95)
const CRYSTAL_REPLACE_HIGHLIGHT_COLOR := Color(0.72, 0.52, 1.0, 0.88)
const CRYSTAL_REPLACE_HOVER_COLOR := Color(0.88, 0.68, 1.0, 1.0)

var projectile_scene = preload("res://projectiles/Projectile.tscn")

@export var base_damage: float = 5.0
@export var base_attack_speed: float = 0.50
@export var base_attack_range: float = 140.0
@export var target_priority: TargetPriority = TargetPriority.FIRST
@export var prioritize_trophy_carriers: bool = true

signal stats_changed
signal external_attack_speed_modifier_expired(source_id: int)

var tower_upgrade_levels: Array[int] = [0, 0, 0]

var current_attack_configuration: AttackConfiguration:
	get:
		return _build_current_attack_configuration()

var damage: int:
	get:
		return roundi(current_attack_configuration.damage)

var attack_speed: float:
	get:
		return current_attack_configuration.attack_speed

var attack_range: float:
	get:
		return current_attack_configuration.attack_range

var attack_timer: float = 0.0
var target = null
var _range_visible: bool = false
var _crystal_drop_highlight: bool = false
var _crystal_drop_hovered: bool = false
var _crystal_drop_replacement: bool = false
var _main_socket: TowerSocket
var _aura_enemies: Dictionary = {}
var _external_attack_speed_multipliers: Dictionary = {}
var _external_attack_speed_durations: Dictionary = {}
var _external_attack_speed_debug_abilities: Dictionary = {}
var _external_attack_speed_debug_contexts: Dictionary = {}

@onready var _crystal_visual: Sprite2D = $CrystalVisual
@onready var _crystal_socket_visual: CrystalSocketVisual = $CrystalSocketVisual

var main_socket: TowerSocket:
	get:
		return _main_socket

func _init() -> void:
	_main_socket = TowerSocket.new(TowerSocket.SocketType.MAIN)


func _build_current_attack_configuration() -> AttackConfiguration:
	var crystal_instance := get_main_crystal()
	var configuration: AttackConfiguration
	if crystal_instance != null:
		configuration = crystal_instance.definition.create_attack_configuration(
			crystal_instance.level,
			tower_upgrade_levels
		)
	else:
		configuration = AttackConfiguration.new()
		configuration.damage = base_damage
		configuration.attack_speed = base_attack_speed
		configuration.attack_range = base_attack_range
		var effectiveness_ids: Array[StringName] = [
			&"damage_upgrade_effectiveness",
			&"speed_upgrade_effectiveness",
			&"range_upgrade_effectiveness"
		]
		configuration.damage *= pow(
			1.0 + (TOWER_UPGRADE_MULTIPLIER - 1.0) * (
				1.0 + CrystalInventory.get_skill_effect_value(
					effectiveness_ids[UpgradeTrack.UPGRADE_1]
				)
			),
			tower_upgrade_levels[UpgradeTrack.UPGRADE_1]
		)
		configuration.attack_speed *= pow(
			1.0 + (TOWER_UPGRADE_MULTIPLIER - 1.0) * (
				1.0 + CrystalInventory.get_skill_effect_value(
					effectiveness_ids[UpgradeTrack.UPGRADE_2]
				)
			),
			tower_upgrade_levels[UpgradeTrack.UPGRADE_2]
		)
		configuration.attack_range *= pow(
			1.0 + (TOWER_UPGRADE_MULTIPLIER - 1.0) * (
				1.0 + CrystalInventory.get_skill_effect_value(
					effectiveness_ids[UpgradeTrack.UPGRADE_3]
				)
			),
			tower_upgrade_levels[UpgradeTrack.UPGRADE_3]
		)
		_apply_tower_foundation_bonuses(configuration)
	for multiplier in _external_attack_speed_multipliers.values():
		configuration.attack_speed *= float(multiplier)
	return configuration


func set_external_attack_speed_multiplier(
	source_id: int,
	multiplier: float,
	duration: float = -1.0,
	debug_ability: String = "",
	debug_context: String = ""
) -> void:
	if not is_finite(multiplier):
		return
	var value := maxf(multiplier, 0.0)
	var changed := not is_equal_approx(
		float(_external_attack_speed_multipliers.get(source_id, 1.0)),
		value
	)
	_external_attack_speed_multipliers[source_id] = value
	if duration >= 0.0:
		_external_attack_speed_durations[source_id] = duration
		if not debug_ability.is_empty():
			_external_attack_speed_debug_abilities[source_id] = debug_ability
			_external_attack_speed_debug_contexts[source_id] = debug_context
	elif duration < 0.0:
		_external_attack_speed_durations.erase(source_id)
		_external_attack_speed_debug_abilities.erase(source_id)
		_external_attack_speed_debug_contexts.erase(source_id)
	if changed:
		stats_changed.emit()


func update_external_attack_speed_multiplier(
	source_id: int,
	multiplier: float
) -> void:
	if not _external_attack_speed_multipliers.has(source_id):
		return
	var value := maxf(multiplier, 0.0)
	if is_equal_approx(
		float(_external_attack_speed_multipliers[source_id]),
		value
	):
		return
	_external_attack_speed_multipliers[source_id] = value
	stats_changed.emit()


func remove_external_attack_speed_multiplier(source_id: int) -> void:
	if not _external_attack_speed_multipliers.has(source_id):
		return
	_external_attack_speed_multipliers.erase(source_id)
	_external_attack_speed_durations.erase(source_id)
	_external_attack_speed_debug_abilities.erase(source_id)
	_external_attack_speed_debug_contexts.erase(source_id)
	stats_changed.emit()


func has_main_crystal() -> bool:
	return not _main_socket.is_empty()


func get_main_crystal() -> CrystalInstance:
	return _main_socket.crystal


func can_install_main_crystal(crystal: CrystalData, crystal_level: int = 1) -> bool:
	return _main_socket.can_install(crystal, crystal_level)


func install_main_crystal(crystal: CrystalData, crystal_level: int = 1) -> bool:
	if not can_install_main_crystal(crystal, crystal_level):
		return false
	if not _main_socket.install(crystal, crystal_level):
		return false

	attack_timer = 0.0
	target = null
	_update_crystal_visual()
	queue_redraw()
	stats_changed.emit()
	return true


func can_replace_main_crystal(
	crystal: CrystalData,
	crystal_level: int = 1
) -> bool:
	return _main_socket.can_replace(crystal, crystal_level)


func replace_main_crystal(
	crystal: CrystalData,
	crystal_level: int = 1
) -> CrystalInstance:
	if not can_replace_main_crystal(crystal, crystal_level):
		return null

	var old_configuration := current_attack_configuration
	var previous := _main_socket.replace(crystal, crystal_level)
	if previous == null:
		return null
	if old_configuration.attack_behavior == CrystalData.AttackBehavior.AURA:
		_clear_aura_effects()
	attack_timer = 0.0
	target = null
	_update_crystal_visual()
	queue_redraw()
	stats_changed.emit()
	return previous


func restore_main_crystal(crystal: CrystalInstance) -> bool:
	if crystal == null or not _main_socket.restore(crystal):
		return false

	attack_timer = 0.0
	target = null
	_update_crystal_visual()
	queue_redraw()
	stats_changed.emit()
	return true


func remove_main_crystal() -> CrystalInstance:
	var old_configuration := current_attack_configuration
	var crystal := _main_socket.remove()
	if crystal != null:
		if old_configuration.attack_behavior == CrystalData.AttackBehavior.AURA:
			_clear_aura_effects()
		attack_timer = 0.0
		target = null
		_update_crystal_visual()
		queue_redraw()
		stats_changed.emit()
	return crystal


func get_upgrade_cost(track: UpgradeTrack) -> int:
	var track_index := int(track)
	if track_index < 0 or track_index >= TOWER_UPGRADE_BASE_COSTS.size():
		return 0

	var scaled_cost := (
		float(TOWER_UPGRADE_BASE_COSTS[track_index])
		* pow(TOWER_UPGRADE_COST_GROWTH, tower_upgrade_levels[track_index])
	)
	if not is_finite(scaled_cost) or scaled_cost >= float(MAX_UPGRADE_COST):
		return MAX_UPGRADE_COST

	var reduction_effects: Array[StringName] = [
		&"damage_upgrade_cost_reduction",
		&"speed_upgrade_cost_reduction",
		&"range_upgrade_cost_reduction"
	]
	var total_reduction := (
		CrystalInventory.get_skill_effect_value(
			reduction_effects[track_index]
		)
		+ CrystalInventory.get_skill_effect_value(
			&"tower_upgrade_cost_reduction_all"
		)
	)
	if total_reduction <= 0.0:
		return roundi(scaled_cost)
	var reduced_cost := scaled_cost * (1.0 - total_reduction)
	return maxi(floori(reduced_cost), 1)


func can_upgrade(track: UpgradeTrack) -> bool:
	var track_index := int(track)
	if track_index < 0 or track_index >= tower_upgrade_levels.size():
		return false
	if not CrystalInventory.is_skill_purchased(&"B"):
		return false

	var cost := get_upgrade_cost(track)
	return cost > 0 and GoldManager.can_afford(cost)


func upgrade_tower_track(track: UpgradeTrack) -> bool:
	if not can_upgrade(track):
		return false

	if not GoldManager.spend_gold(get_upgrade_cost(track)):
		return false

	tower_upgrade_levels[int(track)] += 1

	queue_redraw()
	stats_changed.emit()
	return true


func get_upgrade_track_name(track: UpgradeTrack) -> String:
	var track_index := int(track)
	var crystal_instance := get_main_crystal()
	if crystal_instance != null:
		for mapping in crystal_instance.definition.tower_upgrade_mappings:
			if mapping != null and mapping.tower_upgrade_slot == track_index:
				return mapping.display_name

	if track_index >= 0 and track_index < BASIC_UPGRADE_NAMES.size():
		return BASIC_UPGRADE_NAMES[track_index]
	return "Upgrade"


func get_upgrade_level(track: UpgradeTrack) -> int:
	var track_index := int(track)
	if track_index < 0 or track_index >= tower_upgrade_levels.size():
		return 0
	return tower_upgrade_levels[track_index]


func _ready() -> void:
	add_to_group("towers")
	var collision_shape := $CollisionShape2D as CollisionShape2D
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(50.0, 50.0)
	collision_shape.shape = rectangle
	_update_crystal_visual()


func _update_crystal_visual() -> void:
	var crystal_instance := get_main_crystal()
	if not is_instance_valid(_crystal_visual):
		return

	if crystal_instance == null or crystal_instance.definition == null:
		_crystal_visual.texture = null
		_crystal_visual.visible = false
		_crystal_socket_visual.occupied = false
		return

	_crystal_visual.texture = crystal_instance.definition.visual_texture
	_crystal_visual.visible = _crystal_visual.texture != null
	_crystal_socket_visual.occupied = true


func _apply_tower_foundation_bonuses(
	configuration: AttackConfiguration
) -> void:
	configuration.damage *= 1.0 + CrystalInventory.get_skill_effect_value(
		&"tower_base_damage_bonus"
	)
	configuration.attack_speed *= 1.0 + CrystalInventory.get_skill_effect_value(
		&"tower_base_speed_bonus"
	)
	configuration.attack_range *= 1.0 + CrystalInventory.get_skill_effect_value(
		&"tower_base_range_bonus"
	)


func _exit_tree() -> void:
	_clear_aura_effects()


func set_range_visible(visible: bool) -> void:
	_range_visible = visible
	queue_redraw()


func set_crystal_drop_highlight(
	enabled: bool,
	hovered: bool = false,
	replacement: bool = false
) -> void:
	_crystal_drop_highlight = enabled
	_crystal_drop_hovered = enabled and hovered
	_crystal_drop_replacement = enabled and replacement
	queue_redraw()


func _draw() -> void:
	if _crystal_drop_highlight:
		draw_arc(
			Vector2.ZERO,
			36.0,
			0.0,
			TAU,
			48,
			(
				CRYSTAL_REPLACE_HOVER_COLOR
				if _crystal_drop_hovered
				else CRYSTAL_REPLACE_HIGHLIGHT_COLOR
			)
			if _crystal_drop_replacement
			else (
				CRYSTAL_INSTALL_HOVER_COLOR
				if _crystal_drop_hovered
				else CRYSTAL_INSTALL_HIGHLIGHT_COLOR
			),
			5.0 if _crystal_drop_hovered else 3.0,
			true
		)
	if not _range_visible:
		return

	var configuration := current_attack_configuration
	var segments := maxi(ceili(configuration.attack_range / 8.0), 48)
	var fill_color := Color(0.25, 0.8, 1.0, 0.055)
	var line_color := Color(0.4, 0.85, 1.0, 0.55)
	if configuration.attack_behavior == CrystalData.AttackBehavior.AURA:
		fill_color = Color(0.3, 1.0, 0.45, 0.09)
		line_color = Color(0.55, 1.0, 0.55, 0.75)

	draw_circle(Vector2.ZERO, configuration.attack_range, fill_color)
	draw_arc(
		Vector2.ZERO,
		configuration.attack_range,
		0.0,
		TAU,
		segments,
		line_color,
		2.0,
		true
	)


func _process(delta: float) -> void:
	_process_external_attack_speed_durations(delta)
	var configuration := current_attack_configuration
	if configuration.attack_behavior == CrystalData.AttackBehavior.AURA:
		attack_timer = 0.0
		target = null
		_update_aura(configuration)
		return

	_clear_aura_effects()
	target = select_target(configuration.attack_range)
	attack_timer += delta

	if (
		target != null
		and configuration.attack_speed > 0.0
		and attack_timer >= 1.0 / configuration.attack_speed
	):
		attack_timer = 0.0
		attack_target(configuration)


func _process_external_attack_speed_durations(delta: float) -> void:
	for source_id in _external_attack_speed_durations.keys():
		var remaining := float(_external_attack_speed_durations[source_id]) - delta
		if remaining > 0.0:
			_external_attack_speed_durations[source_id] = remaining
			continue
		_external_attack_speed_durations.erase(source_id)
		_external_attack_speed_multipliers.erase(source_id)
		var ability := String(_external_attack_speed_debug_abilities.get(source_id, ""))
		var context := String(_external_attack_speed_debug_contexts.get(source_id, ""))
		_external_attack_speed_debug_abilities.erase(source_id)
		_external_attack_speed_debug_contexts.erase(source_id)
		stats_changed.emit()
		external_attack_speed_modifier_expired.emit(source_id)
		if not ability.is_empty():
			BossAbilityDebug.log_external(
				ability,
				"debuff_expired",
				"tower=%s" % name,
				context
			)


func select_target(target_range: float = -1.0) -> Node2D:
	if target_range < 0.0:
		target_range = current_attack_configuration.attack_range
	var best_target: Node2D = null
	var best_distance := target_range
	var best_is_returning := false
	var best_first_progress := -INF
	var best_hp := -INF
	var in_range_enemies: Array[Node2D] = []
	var in_range_carriers: Array[Node2D] = []

	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(candidate) or not candidate is Node2D:
			continue
		if candidate.is_queued_for_deletion():
			continue
		if _has_property(candidate, &"is_dead") and bool(candidate.get("is_dead")):
			continue

		var enemy := candidate as Node2D
		var distance := global_position.distance_to(enemy.global_position)
		if distance > target_range:
			continue
		in_range_enemies.append(enemy)
		if (
			_has_property(enemy, &"can_carry_trophy")
			and bool(enemy.get("can_carry_trophy"))
			and _has_property(enemy, &"is_carrying_trophy")
			and bool(enemy.get("is_carrying_trophy"))
		):
			in_range_carriers.append(enemy)

	var candidates := in_range_enemies
	if prioritize_trophy_carriers and not in_range_carriers.is_empty():
		candidates = in_range_carriers

	for enemy in candidates:
		var distance := global_position.distance_to(enemy.global_position)

		var is_better_target := false
		match target_priority:
			TargetPriority.NEAREST:
				is_better_target = best_target == null or distance <= best_distance
			TargetPriority.FIRST:
				if not _has_property(enemy, &"first_target_progress"):
					continue
				if not _has_property(enemy, &"movement_direction"):
					continue
				var is_returning := (
					int(enemy.get("movement_direction"))
					== Enemy.MovementDirection.RETURNING_TO_CAMP
				)
				var first_progress := float(enemy.get("first_target_progress"))
				is_better_target = (
					best_target == null
					or (is_returning and not best_is_returning)
					or (
						is_returning == best_is_returning
						and first_progress > best_first_progress
					)
				)
				if is_better_target:
					best_is_returning = is_returning
					best_first_progress = first_progress
			TargetPriority.STRONGEST:
				if not _has_property(enemy, &"hp"):
					continue
				var hp := float(enemy.get("hp"))
				is_better_target = best_target == null or hp > best_hp
				if is_better_target:
					best_hp = hp

		if is_better_target:
			best_target = enemy
			best_distance = distance

	return best_target


func _has_property(object: Object, property_name: StringName) -> bool:
	for property in object.get_property_list():
		if property["name"] == property_name:
			return true

	return false


func attack_target(configuration: AttackConfiguration = null) -> void:
	if target == null or not is_instance_valid(target):
		return
	if configuration == null:
		configuration = current_attack_configuration
	if configuration.attack_behavior == CrystalData.AttackBehavior.AURA:
		return

	var projectile = projectile_scene.instantiate()

	projectile.global_position = global_position
	projectile.target = target
	projectile.damage = configuration.damage
	projectile.bleed_max_hp_fraction_per_second = (
		configuration.bleed_max_hp_fraction_per_second
	)
	projectile.bleed_duration = configuration.bleed_duration
	projectile.area_damage_fraction = configuration.area_damage_fraction
	projectile.area_damage_radius = configuration.area_damage_radius

	get_tree().current_scene.add_child(projectile)


func _update_aura(configuration: AttackConfiguration) -> void:
	var source_id := get_instance_id()
	var affected_now: Dictionary = {}
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not candidate is Enemy or candidate.is_queued_for_deletion():
			continue

		var enemy := candidate as Enemy
		if enemy.is_dead or global_position.distance_to(enemy.global_position) > configuration.attack_range:
			continue

		enemy.set_movement_slow(source_id, configuration.slow_fraction)
		affected_now[enemy.get_instance_id()] = weakref(enemy)

	for enemy_id in _aura_enemies:
		if affected_now.has(enemy_id):
			continue
		var enemy_ref: WeakRef = _aura_enemies[enemy_id]
		var old_enemy := enemy_ref.get_ref() as Enemy
		if is_instance_valid(old_enemy):
			old_enemy.remove_movement_slow(
				source_id,
				configuration.slow_duration
			)

	_aura_enemies = affected_now


func _clear_aura_effects() -> void:
	var source_id := get_instance_id()
	for enemy_ref_value in _aura_enemies.values():
		var enemy_ref: WeakRef = enemy_ref_value
		var enemy := enemy_ref.get_ref() as Enemy
		if is_instance_valid(enemy):
			enemy.remove_movement_slow(source_id)
	_aura_enemies.clear()
