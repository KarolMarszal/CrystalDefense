class_name WaveArchetype
extends Resource

@export var archetype_id: StringName = &""
@export var display_name: String = ""
@export_range(0.0, 100.0, 0.1) var selection_weight: float = 1.0
@export_range(-1.0, 1.0, 0.05) var difficulty_cost_bias: float = 0.0
@export_range(-1.0, 1.0, 0.05) var movement_speed_bias: float = 0.0
@export_range(-1.0, 1.0, 0.05) var hp_bias: float = 0.0
@export_range(0.0, 10.0, 0.1) var diversity_bonus: float = 0.0
@export_range(1, 5, 1) var minimum_distinct_enemy_types: int = 1
@export_range(0.0, 1.0, 0.05) var repetition_resistance: float = 0.5
