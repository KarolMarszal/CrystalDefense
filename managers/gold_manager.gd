extends Node

signal gold_changed(new_amount: int)

const STARTING_RUN_GOLD: int = 300

var _run_gold: int = 0

var run_gold: int:
	get:
		return _run_gold


func start_new_run() -> void:
	_set_run_gold(STARTING_RUN_GOLD)


func end_run() -> void:
	_set_run_gold(0)


func add_gold(amount: int) -> void:
	if amount <= 0:
		return

	_set_run_gold(_run_gold + amount)


func can_afford(amount: int) -> bool:
	return amount >= 0 and _run_gold >= amount


func spend_gold(amount: int) -> bool:
	if not can_afford(amount):
		return false

	_set_run_gold(_run_gold - amount)
	return true


func _set_run_gold(amount: int) -> void:
	if _run_gold == amount:
		return

	_run_gold = amount
	gold_changed.emit(_run_gold)
