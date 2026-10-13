extends Label


func _ready() -> void:
	CrystalInventory.profile_changed.connect(_on_profile_changed)
	_refresh()


func _exit_tree() -> void:
	if CrystalInventory.profile_changed.is_connected(_on_profile_changed):
		CrystalInventory.profile_changed.disconnect(_on_profile_changed)


func _on_profile_changed(_profile: Dictionary) -> void:
	_refresh()


func _refresh() -> void:
	text = "Essence points: %d / %d" % [
		CrystalInventory.get_essence_points(),
		CrystalInventory.get_essence_threshold()
	]
