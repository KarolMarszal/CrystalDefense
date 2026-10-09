class_name EnemyData
extends Resource

@export var enemy_id: StringName = &""
@export var display_name: String = ""
@export var base_hp: int = 1
@export var base_speed: float = 1.0
@export var gold_reward: int = 0
@export var visual_texture: Texture2D
@export_range(0.1, 1.0, 0.01) var visual_scale: float = 0.32
@export_range(1, 100, 1) var difficulty_cost: int = 1
@export_range(1, 1000, 1) var unlock_wave: int = 1
@export_range(0.0, 100.0, 0.1) var selection_weight: float = 1.0
@export var can_resurrect: bool = false
@export_range(0.0, 1.0, 0.01) var resurrection_chance: float = 0.0
@export_range(0.0, 1.0, 0.01) var resurrection_hp_percent: float = 0.5
@export_range(0, 10, 1) var max_resurrections: int = 0
@export var can_regenerate: bool = false
@export_range(0.0, 1.0, 0.001) var regeneration_percent_max_hp_per_second: float = 0.0
@export var can_carry_trophy: bool = true
@export var can_pickup_dropped_trophy: bool = false
