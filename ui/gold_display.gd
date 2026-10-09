extends Label


func _ready() -> void:
	GoldManager.gold_changed.connect(_on_gold_changed)
	_on_gold_changed(GoldManager.run_gold)


func _on_gold_changed(amount: int) -> void:
	text = "Gold: %d" % amount
