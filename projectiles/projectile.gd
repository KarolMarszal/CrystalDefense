extends Node2D

var target = null
var damage: int = 25
var speed: float = 500.0
var bleed_max_hp_fraction_per_second: float = 0.0
var bleed_duration: float = 0.0


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

	target.take_damage(damage)
	if (
		bleed_max_hp_fraction_per_second > 0.0
		and bleed_duration > 0.0
		and is_instance_valid(target)
		and target.has_method("apply_bleed")
	):
		target.apply_bleed(bleed_max_hp_fraction_per_second, bleed_duration)

	queue_free()
