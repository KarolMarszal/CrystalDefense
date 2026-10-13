extends Control

const CATALOG = preload("res://managers/skill_tree_catalog.gd")
const NODE_SIZE := Vector2(190, 112)
const BUS_GUTTER := 30.0
const BUS_MERGE_DROP := 74.0

var _visible_ids: Dictionary = {}
var _purchased_ids: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = CATALOG.CANVAS_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_progress(visible_ids: Dictionary, purchased_ids: Dictionary) -> void:
	_visible_ids = visible_ids.duplicate()
	_purchased_ids = purchased_ids.duplicate()
	queue_redraw()


func _draw() -> void:
	for definition in CATALOG.get_skill_definitions():
		var child_id: String = definition["id"]
		var child_position := CATALOG.get_node_position(child_id)
		if (
			not _visible_ids.has(child_id)
			or child_position.x < 0.0
			or child_position.y < 0.0
		):
			continue
		for prerequisite_id in definition["prerequisites"]:
			var parent_id := String(prerequisite_id)
			var parent_position := CATALOG.get_node_position(parent_id)
			if (
				not _visible_ids.has(parent_id)
				or parent_position.x < 0.0
				or parent_position.y < 0.0
			):
				continue
			_draw_connection(parent_id, child_id)
	_draw_alternative_prerequisite_marker()


func _draw_alternative_prerequisite_marker() -> void:
	var definition := CATALOG.get_skill_definition(&"H")
	if (
		not _visible_ids.has("H")
		or definition.get("prerequisite_mode", "all") != "any"
	):
		return

	var f_points := get_connection_points("F", "H")
	var g_points := get_connection_points("G", "H")
	var marker_position := (f_points[2] + g_points[2]) * 0.5
	var marker_rect := Rect2(
		marker_position + Vector2(-20.0, -13.0),
		Vector2(40.0, 26.0)
	)
	draw_rect(marker_rect, Color(0.09, 0.14, 0.13, 1.0))
	draw_string(
		ThemeDB.fallback_font,
		marker_position + Vector2(0.0, 5.0),
		"OR",
		HORIZONTAL_ALIGNMENT_CENTER,
		40.0,
		14,
		Color(1.0, 0.83, 0.36, 1.0)
	)


static func get_connection_points(parent_id: String, child_id: String) -> PackedVector2Array:
	var parent_position := CATALOG.get_node_position(parent_id)
	var child_position := CATALOG.get_node_position(child_id)
	if child_id == "N":
		return _get_merge_bus_points(parent_position, child_position)
	var child_is_above := child_position.y + NODE_SIZE.y <= parent_position.y
	var start := parent_position + Vector2(
		NODE_SIZE.x * 0.5,
		0.0 if child_is_above else NODE_SIZE.y
	)
	var finish := child_position + Vector2(
		NODE_SIZE.x * 0.5,
		NODE_SIZE.y if child_is_above else 0.0
	)
	var middle_y := (start.y + finish.y) * 0.5
	if not child_is_above and middle_y >= finish.y:
		middle_y = finish.y - 14.0
	elif child_is_above and middle_y <= finish.y:
		middle_y = finish.y + 14.0
	return PackedVector2Array([
		start,
		Vector2(start.x, middle_y),
		Vector2(finish.x, middle_y),
		finish
	])


static func _get_merge_bus_points(
	parent_position: Vector2,
	child_position: Vector2
) -> PackedVector2Array:
	# Parents in a stack leave through the gutter beside their column and merge
	# above the stack, so no connector crosses sibling nodes.
	var exits_left := parent_position.x < child_position.x
	var start := parent_position + Vector2(
		0.0 if exits_left else NODE_SIZE.x,
		NODE_SIZE.y * 0.5
	)
	var bus_x := start.x + (-BUS_GUTTER if exits_left else BUS_GUTTER)
	var merge_y := child_position.y + NODE_SIZE.y + BUS_MERGE_DROP
	var finish := child_position + Vector2(NODE_SIZE.x * 0.5, NODE_SIZE.y)
	return PackedVector2Array([
		start,
		Vector2(bus_x, start.y),
		Vector2(bus_x, merge_y),
		Vector2(finish.x, merge_y),
		finish
	])


func _draw_connection(parent_id: String, child_id: String) -> void:
	var color := Color(0.57, 1.0, 0.68, 0.9) if _purchased_ids.has(parent_id) else Color(0.43, 0.48, 0.42, 0.85)
	var points := get_connection_points(parent_id, child_id)
	for index in range(points.size() - 1):
		draw_line(points[index], points[index + 1], color, 4.0, true)
