extends Node2D

var target = null
var damage: float = 25.0
var speed: float = 500.0
var bleed_max_hp_fraction_per_second: float = 0.0
var bleed_duration: float = 0.0
var area_damage_fraction: float = 0.0
var area_damage_radius: float = 0.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return

	var direction = global_position.direction_to(target.global_position)

	global_position += direction * speed * delta

	if global_position.distance_to(target.global_position) < 10.0:
		hit_target()

func hit_target():
	if target == null or not is_instance_valid(target):
		queue_free()
		return

	target.take_damage(roundi(damage))
	if (
		bleed_max_hp_fraction_per_second > 0.0
		and bleed_duration > 0.0
		and is_instance_valid(target)
		and target.has_method("apply_bleed")
	):
		target.apply_bleed(bleed_max_hp_fraction_per_second, bleed_duration)
	if area_damage_fraction > 0.0 and area_damage_radius > 0.0:
		_damage_nearby_enemies(target)

	queue_free()


func _damage_nearby_enemies(primary_target: Node2D) -> void:
	var area_damage := roundi(damage * area_damage_fraction)
	if area_damage <= 0:
		return

	for candidate in get_tree().get_nodes_in_group("enemies"):
		if (
			not candidate is Enemy
			or candidate == primary_target
			or candidate.is_queued_for_deletion()
		):
			continue
		var enemy := candidate as Enemy
		if (
			enemy.is_dead
			or enemy.global_position.distance_to(primary_target.global_position)
			> area_damage_radius
		):
			continue
		enemy.take_damage(area_damage)
