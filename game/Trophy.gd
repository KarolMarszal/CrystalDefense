class_name Trophy
extends Node2D

enum State {
	TREASURY,
	CARRIED,
	DROPPED,
	DEPOSITED
}

@export var trophy_id: StringName = &""
var state: State = State.TREASURY


func _enter_tree() -> void:
	if state == State.DROPPED:
		add_to_group("dropped_trophies")


func set_state(new_state: State) -> void:
	if is_in_group("dropped_trophies"):
		remove_from_group("dropped_trophies")

	state = new_state
	if state == State.DROPPED and is_inside_tree():
		add_to_group("dropped_trophies")
