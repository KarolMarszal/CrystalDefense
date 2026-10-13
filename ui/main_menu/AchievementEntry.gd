class_name AchievementEntry
extends PanelContainer

@onready var icon_label: Label = $Margin/Contents/Icon
@onready var title_label: Label = $Margin/Contents/Details/Title
@onready var description_label: Label = $Margin/Contents/Details/Description
@onready var progress_bar: ProgressBar = $Margin/Contents/Details/Progress
@onready var progress_label: Label = $Margin/Contents/Details/ProgressLabel
@onready var reward_label: Label = $Margin/Contents/Reward
@onready var state_label: Label = $Margin/Contents/State


func configure(
	definition: Dictionary,
	status: Dictionary,
	reward_granted: bool,
	cosmetic_unlocked: bool
) -> void:
	var unlocked := bool(status.get("unlocked", false))
	var target := int(status.get("target", 0))
	var progress := int(status.get("progress", 0))
	var title := String(status.get("title", definition.get("title", "")))
	var description := String(
		status.get("description", definition.get("description", ""))
	)

	icon_label.text = "*" if unlocked else "-"
	title_label.text = title
	description_label.text = description
	state_label.text = "UNLOCKED" if unlocked else "IN PROGRESS"
	state_label.modulate = (
		Color(0.65, 1.0, 0.7, 1.0)
		if unlocked
		else Color(0.83, 0.83, 0.76, 1.0)
	)

	var measurable := target > 0
	progress_bar.visible = measurable and not unlocked
	progress_label.visible = measurable
	if measurable:
		progress_label.text = (
			"Completed" if unlocked else "%d / %d" % [mini(progress, target), target]
		)
		progress_bar.max_value = target
		progress_bar.value = mini(progress, target)
	else:
		progress_label.text = "Completed" if unlocked else "Condition in progress"

	reward_label.text = _format_reward(
		definition,
		reward_granted,
		cosmetic_unlocked
	)


func _format_reward(
	definition: Dictionary,
	reward_granted: bool,
	cosmetic_unlocked: bool
) -> String:
	var reward_parts: Array[String] = []
	var essence := int(definition.get("reward_essence", 0))
	if essence > 0:
		reward_parts.append("%d Essence" % essence)

	var cosmetic_id := String(definition.get("cosmetic_reward_id", ""))
	if not cosmetic_id.is_empty():
		var cosmetic_type := String(
			definition.get("cosmetic_reward_type", "cosmetic")
		).replace("_", " ").capitalize()
		var cosmetic_state := (
			"unlocked"
			if cosmetic_unlocked
			else "pending"
		)
		reward_parts.append("%s: %s (%s)" % [
			cosmetic_type,
			cosmetic_id,
			cosmetic_state
		])

	if reward_parts.is_empty():
		return "Reward: None"
	var reward_state := "GRANTED" if reward_granted else "LOCKED"
	return "Reward: %s - %s" % [" + ".join(reward_parts), reward_state]
