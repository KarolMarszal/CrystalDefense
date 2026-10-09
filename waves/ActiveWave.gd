class_name ActiveWave
extends RefCounted

enum State {
	NOT_STARTED,
	SPAWNING,
	WAITING_FOR_ENEMIES,
	COMPLETED
}

var wave_number: int
var config: WaveConfig
var total_enemies: int = 0
var spawned_enemies: int = 0
var group_index: int = 0
var spawned_in_group: int = 0
var spawn_timer: float = 0.0
var state: State = State.NOT_STARTED
var active_enemies: Dictionary = {}
var gold_multiplier: float = 1.0
var start_reason: int = 0
