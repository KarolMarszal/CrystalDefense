extends Node

signal speed_changed(multiplier: float)
signal pause_changed(paused: bool)

const SPEED_OPTIONS: Array[float] = [0.5, 1.0, 2.0, 3.0]

var simulation_speed: float = 1.0
var is_paused: bool = false


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func begin_run() -> void:
	reset()


func reset() -> void:
	set_paused(false)
	set_simulation_speed(1.0)


func set_simulation_speed(multiplier: float) -> bool:
	if not SPEED_OPTIONS.has(multiplier):
		push_warning("Unsupported simulation speed: %s" % multiplier)
		return false

	if is_equal_approx(simulation_speed, multiplier):
		return true

	simulation_speed = multiplier
	Engine.time_scale = multiplier
	speed_changed.emit(simulation_speed)
	return true


func set_paused(paused: bool) -> void:
	if is_paused == paused and get_tree().paused == paused:
		return

	is_paused = paused
	get_tree().paused = paused
	pause_changed.emit(is_paused)
