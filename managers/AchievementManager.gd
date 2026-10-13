extends Node

signal achievement_unlocked(achievement_id: String)
signal achievement_progress_changed(achievement_id: String, progress: int, target: int)
signal cosmetic_unlocked(cosmetic_id: String, cosmetic_type: String)
signal cosmetic_selection_changed(cosmetic_type: String, cosmetic_id: String)
signal achievements_reset

const CATALOG = preload("res://managers/AchievementCatalog.gd")
const BOSS_WAVE_SCHEDULE = preload("res://waves/BossWaveSchedule.gd")
const ACHIEVEMENT_SAVE_VERSION: int = 1

var _state: Dictionary = {}
var _ordinary_enemy_ids: Array[String] = []
var _tier_one_boss_ids: Array[String] = []
var _pending_events: Array[Dictionary] = []
var _processing_events: bool = false
var _run_active: bool = false
var _achievement_state_writable: bool = true
var _cosmetic_texture_cache: Dictionary = {}


func _ready() -> void:
	_load_state()
	_reconcile_catalog_cosmetic_unlocks()
	_discover_enemy_types()
	_discover_tier_one_bosses()
	CrystalInventory.essence_earned.connect(_on_essence_earned)


func get_achievement_definitions() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for definition in CATALOG.DEFINITIONS:
		if (
			bool(definition["hidden"])
			and not _state["unlocked_ids"].has(String(definition["id"]))
		):
			continue
		definitions.append(definition.duplicate(true))
	return definitions


func get_achievement_state() -> Dictionary:
	var public_state := _state.duplicate(true)
	var progress: Dictionary = public_state["progress"]
	for definition in CATALOG.DEFINITIONS:
		var achievement_id := String(definition["id"])
		if (
			bool(definition["hidden"])
			and not _state["unlocked_ids"].has(achievement_id)
		):
			progress.erase(achievement_id)
	public_state["progress"] = progress
	return public_state


func get_achievement_status(achievement_id: String) -> Dictionary:
	for definition in CATALOG.DEFINITIONS:
		if String(definition["id"]) != achievement_id:
			continue
		var unlocked: bool = _state["unlocked_ids"].has(achievement_id)
		if bool(definition["hidden"]) and not unlocked:
			return {
				"id": achievement_id,
				"hidden": true,
				"unlocked": false
			}
		return {
			"id": achievement_id,
			"title": String(definition["title"]),
			"description": String(definition["description"]),
			"category": String(definition["category"]),
			"hidden": bool(definition["hidden"]),
			"unlocked": unlocked,
			"progress": int(_state["progress"].get(achievement_id, 0)),
			"target": _get_public_target(definition)
		}
	return {}


func get_unlocked_cosmetics() -> Dictionary:
	var cosmetics: Dictionary = _state["unlocked_cosmetics"]
	return cosmetics.duplicate(true)


func has_cosmetic_unlocked(cosmetic_id: String) -> bool:
	return _state["unlocked_cosmetics"].has(cosmetic_id)


func get_cosmetic_types() -> Array[String]:
	var types: Array[String] = []
	for cosmetic in CATALOG.COSMETICS:
		var cosmetic_type := String(cosmetic["type"])
		if not cosmetic_type.is_empty() and not types.has(cosmetic_type):
			types.append(cosmetic_type)
	return types


# Locked cosmetics rewarded by hidden achievements are omitted so they stay secret.
func get_cosmetic_catalog(cosmetic_type: String) -> Array[Dictionary]:
	var cosmetics: Array[Dictionary] = []
	for source in CATALOG.COSMETICS:
		if String(source["type"]) != cosmetic_type:
			continue
		var cosmetic_id := String(source["id"])
		var unlocked := bool(source.get("default", false)) or _is_cosmetic_owned(
			cosmetic_id,
			cosmetic_type
		)
		var unlock_definition := _get_unlock_definition(
			String(source.get("unlock_achievement", ""))
		)
		var hidden_source := (
			not unlock_definition.is_empty()
			and bool(unlock_definition.get("hidden", false))
		)
		var source_revealed: bool = (
			not hidden_source
			or _state["unlocked_ids"].has(
				String(source.get("unlock_achievement", ""))
			)
		)
		if hidden_source and not unlocked:
			continue
		var entry := source.duplicate(true)
		entry["unlocked"] = unlocked
		entry["texture"] = _load_cosmetic_texture(source)
		entry["source_title"] = (
			String(unlock_definition.get("title", ""))
			if not unlock_definition.is_empty() and source_revealed
			else (
				"Secret requirement"
				if hidden_source
				else "Default appearance"
			)
		)
		entry["source_description"] = (
			String(unlock_definition.get("description", ""))
			if not unlock_definition.is_empty() and source_revealed
			else (
				"Secret achievement requirement remains undisclosed."
				if hidden_source
				else "Available by default"
			)
		)
		cosmetics.append(entry)
	return cosmetics


func get_cosmetic_entry(cosmetic_type: String, cosmetic_id: String) -> Dictionary:
	for cosmetic in CATALOG.COSMETICS:
		if (
			String(cosmetic["type"]) != cosmetic_type
			or String(cosmetic["id"]) != cosmetic_id
		):
			continue
		if (
			not bool(cosmetic.get("default", false))
			and not _is_cosmetic_owned(cosmetic_id, cosmetic_type)
		):
			return {}
		var entry := cosmetic.duplicate(true)
		entry["texture"] = _load_cosmetic_texture(cosmetic)
		return entry
	return {}


func get_active_cosmetic_texture(cosmetic_type: String) -> Texture2D:
	var selected_id := get_selected_cosmetic(cosmetic_type)
	var definition: Dictionary
	if selected_id.is_empty():
		definition = CATALOG.get_default_cosmetic(cosmetic_type)
	else:
		definition = get_cosmetic_entry(cosmetic_type, selected_id)
	return _load_cosmetic_texture(definition)


func get_enemy_skin_texture(enemy_id: String) -> Texture2D:
	var selected_id := get_selected_cosmetic("enemy_skin")
	if selected_id.is_empty():
		return null
	var definition := get_cosmetic_entry("enemy_skin", selected_id)
	var compatible_enemy_ids: Array = definition.get("compatible_enemy_ids", [])
	if not compatible_enemy_ids.has(enemy_id):
		return null
	return _load_cosmetic_texture(definition)


func _load_cosmetic_texture(definition: Dictionary) -> Texture2D:
	var path := String(definition.get("texture_path", ""))
	if path.is_empty():
		return null
	if _cosmetic_texture_cache.has(path):
		return _cosmetic_texture_cache[path] as Texture2D
	if not ResourceLoader.exists(path):
		push_warning("Cosmetic texture is missing: %s" % path)
		_cosmetic_texture_cache[path] = null
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		push_warning("Cosmetic asset is not a texture: %s" % path)
		_cosmetic_texture_cache[path] = null
		return null
	_cosmetic_texture_cache[path] = texture
	return texture


func get_selected_cosmetic(cosmetic_type: String) -> String:
	var selected := String(
		CrystalInventory.get_cosmetic_selections().get(cosmetic_type, "")
	)
	if not selected.is_empty() and _is_cosmetic_owned(selected, cosmetic_type):
		return selected
	return ""


# An empty cosmetic_id restores the default appearance.
func select_cosmetic(cosmetic_type: String, cosmetic_id: String) -> bool:
	if not get_cosmetic_types().has(cosmetic_type):
		return false
	var selections := CrystalInventory.get_cosmetic_selections()
	if cosmetic_id.is_empty():
		if not selections.has(cosmetic_type):
			return true
		selections.erase(cosmetic_type)
	else:
		if (
			not _is_cataloged_cosmetic(cosmetic_id, cosmetic_type)
			or not _is_cosmetic_owned(cosmetic_id, cosmetic_type)
		):
			return false
		if String(selections.get(cosmetic_type, "")) == cosmetic_id:
			return true
		selections[cosmetic_type] = cosmetic_id
	if not CrystalInventory.commit_cosmetic_selections(selections):
		return false
	cosmetic_selection_changed.emit(cosmetic_type, cosmetic_id)
	return true


func unlock_all_cosmetics_for_testing() -> bool:
	if (
		not OS.is_debug_build()
		or not bool(ProjectSettings.get_setting(
			"crystal_defense/development_mode",
			false
		))
	):
		push_warning("All-cosmetics testing unlock requires development_mode.")
		return false
	if not _achievement_state_writable:
		push_error("Cannot unlock cosmetics while achievement data is read-only.")
		return false

	var candidate := _state.duplicate(true)
	var cosmetics: Dictionary = candidate["unlocked_cosmetics"]
	var new_unlocks: Array[Dictionary] = []
	for cosmetic in CATALOG.COSMETICS:
		var cosmetic_id := String(cosmetic["id"])
		if cosmetic_id.is_empty() or bool(cosmetic.get("default", false)):
			continue
		var cosmetic_type := String(cosmetic["type"])
		if String(cosmetics.get(cosmetic_id, "")) == cosmetic_type:
			continue
		cosmetics[cosmetic_id] = cosmetic_type
		new_unlocks.append({
			"id": cosmetic_id,
			"type": cosmetic_type
		})

	if new_unlocks.is_empty():
		return true
	candidate["unlocked_cosmetics"] = cosmetics
	if not CrystalInventory.commit_achievement_state(candidate):
		push_error("Could not save testing cosmetic unlocks.")
		return false

	_state = candidate
	for cosmetic in new_unlocks:
		cosmetic_unlocked.emit(
			String(cosmetic["id"]),
			String(cosmetic["type"])
		)
	return true


# Testing aid. Essence is not attributed per achievement in the profile, so the
# balance is intentionally preserved; only achievement-owned records are reset.
func reset_achievements_for_testing() -> bool:
	if not _achievement_state_writable:
		return false
	var fresh := _create_default_state()
	if not CrystalInventory.reset_achievement_data(fresh, {}):
		return false
	_pending_events.clear()
	_state = fresh
	for cosmetic_type in get_cosmetic_types():
		cosmetic_selection_changed.emit(cosmetic_type, "")
	achievements_reset.emit()
	return true


func _is_cosmetic_owned(cosmetic_id: String, cosmetic_type: String) -> bool:
	return (
		String(_state["unlocked_cosmetics"].get(cosmetic_id, ""))
		== cosmetic_type
	)


func _is_cataloged_cosmetic(cosmetic_id: String, cosmetic_type: String) -> bool:
	for definition in CATALOG.COSMETICS:
		if (
			String(definition["id"]) == cosmetic_id
			and String(definition["type"]) == cosmetic_type
		):
			return true
	return false


func _get_unlock_definition(achievement_id: String) -> Dictionary:
	for definition in CATALOG.DEFINITIONS:
		if String(definition["id"]) == achievement_id:
			return definition
	return {}


func _grant_catalog_cosmetics_for_achievement(
	achievement_id: String,
	candidate: Dictionary
) -> void:
	var cosmetics: Dictionary = candidate["unlocked_cosmetics"]
	for cosmetic in CATALOG.COSMETICS:
		if String(cosmetic.get("unlock_achievement", "")) != achievement_id:
			continue
		var cosmetic_id := String(cosmetic["id"])
		var cosmetic_type := String(cosmetic["type"])
		if cosmetic_id.is_empty():
			continue
		cosmetics[cosmetic_id] = cosmetic_type
	candidate["unlocked_cosmetics"] = cosmetics


func _reconcile_catalog_cosmetic_unlocks() -> void:
	if not _achievement_state_writable:
		return
	var candidate := _state.duplicate(true)
	var cosmetics: Dictionary = candidate["unlocked_cosmetics"]
	var changed := false
	for cosmetic in CATALOG.COSMETICS:
		var cosmetic_id := String(cosmetic["id"])
		var source_achievement := String(
			cosmetic.get("unlock_achievement", "")
		)
		if (
			cosmetic_id.is_empty()
			or source_achievement.is_empty()
			or not candidate["unlocked_ids"].has(source_achievement)
		):
			continue
		var cosmetic_type := String(cosmetic["type"])
		if String(cosmetics.get(cosmetic_id, "")) == cosmetic_type:
			continue
		cosmetics[cosmetic_id] = cosmetic_type
		changed = true
	if not changed:
		return
	candidate["unlocked_cosmetics"] = cosmetics
	if not CrystalInventory.commit_achievement_state(candidate):
		push_error("Existing achievement unlocks could not be reconciled with the cosmetic catalog.")
		return
	_state = candidate


func begin_run() -> void:
	_run_active = true
	var candidate := _state.duplicate(true)
	candidate["run_fusions"] = 0
	candidate["run_trophy_losses"] = 0
	candidate["wave_trophy_losses"] = {}
	_commit_state(candidate)


func end_run() -> void:
	if not _run_active:
		return
	_run_active = false
	var candidate := _state.duplicate(true)
	candidate["run_fusions"] = 0
	candidate["run_trophy_losses"] = 0
	_commit_state(candidate)


func report_enemy_killed(
	enemy_type: StringName,
	is_boss: bool = false,
	is_summon: bool = false,
	boss_tier: int = 0
) -> void:
	report_event(&"enemy_killed", 1, {
		"enemy_type": String(enemy_type),
		"is_boss": is_boss,
		"is_summon": is_summon,
		"boss_tier": boss_tier
	})


func report_wave_started(wave_number: int) -> void:
	report_event(&"wave_started", 1, {"wave_number": wave_number})


func report_boss_defeated(
	boss_type: StringName,
	boss_tier: int,
	wave_number: int
) -> void:
	report_event(&"boss_defeated", 1, {
		"boss_type": String(boss_type),
		"boss_tier": boss_tier,
		"wave_number": wave_number
	})


func report_wave_completed(
	wave_number: int,
	remaining_trophies: int,
	total_trophies: int
) -> void:
	report_event(&"wave_completed", 1, {
		"wave_number": wave_number,
		"remaining_trophies": remaining_trophies,
		"total_trophies": total_trophies
	})


func report_crystal_purchased(crystal_id: StringName = &"") -> void:
	report_event(&"crystal_purchased", 1, {"crystal_id": String(crystal_id)})


func report_crystal_fusion_completed() -> void:
	report_event(&"fusion_completed")


func report_tower_upgrade_completed() -> void:
	report_event(&"tower_upgrade_completed")


func report_trophy_delivered(
	trophy_id: StringName = &"",
	wave_number: int = 0
) -> void:
	report_event(&"trophy_delivered", 1, {
		"trophy_id": String(trophy_id),
		"wave_number": wave_number
	})


func report_event(
	event_type: StringName,
	amount: int = 1,
	details: Dictionary = {}
) -> void:
	if event_type == &"run_ended":
		end_run()
		return
	if event_type == &"run_started":
		begin_run()
		return
	if amount <= 0 and event_type != &"wave_started":
		return

	_pending_events.append({
		"type": String(event_type),
		"amount": maxi(amount, 1),
		"details": details.duplicate(true)
	})
	if _processing_events:
		return

	_processing_events = true
	while not _pending_events.is_empty():
		var event: Dictionary = _pending_events.pop_front()
		_process_event(event)
	_processing_events = false


func _on_essence_earned(amount: int) -> void:
	if amount > 0:
		report_event(&"essence_earned", amount)


func _process_event(event: Dictionary) -> void:
	var event_type := String(event["type"])
	var amount := int(event["amount"])
	var details: Dictionary = event["details"]
	var candidate := _state.duplicate(true)
	var counters: Dictionary = candidate["counters"]
	var newly_granted: Dictionary = {}

	match event_type:
		"wave_started":
			var started_wave_losses: Dictionary = candidate["wave_trophy_losses"]
			started_wave_losses[str(int(details.get("wave_number", 0)))] = 0
			candidate["wave_trophy_losses"] = started_wave_losses
		"enemy_killed":
			counters["enemy_kills"] = int(counters.get("enemy_kills", 0)) + amount
			var enemy_type := String(details.get("enemy_type", ""))
			var is_boss := bool(details.get("is_boss", false))
			var is_summon := bool(details.get("is_summon", false))
			if not is_boss and not is_summon and _ordinary_enemy_ids.has(enemy_type):
				var enemy_kills: Dictionary = candidate["enemy_kills"]
				enemy_kills[enemy_type] = int(enemy_kills.get(enemy_type, 0)) + amount
				candidate["enemy_kills"] = enemy_kills
		"boss_defeated":
			counters["boss_kills"] = int(counters.get("boss_kills", 0)) + amount
			var boss_type := String(details.get("boss_type", ""))
			var boss_kills: Dictionary = candidate["boss_kills"]
			boss_kills[boss_type] = int(boss_kills.get(boss_type, 0)) + amount
			candidate["boss_kills"] = boss_kills
		"wave_completed":
			candidate["completed_waves"] = int(candidate.get("completed_waves", 0)) + amount
			var completed_wave_losses: Dictionary = candidate["wave_trophy_losses"]
			var completed_wave_number := int(details.get("wave_number", 0))
			var wave_loss_count := int(
				completed_wave_losses.get(str(completed_wave_number), 0)
			)
			if wave_loss_count == 0:
				candidate["lossless_wave_streak"] = int(
					candidate.get("lossless_wave_streak", 0)
				) + amount
			else:
				candidate["lossless_wave_streak"] = 0
			completed_wave_losses.erase(str(completed_wave_number))
			candidate["wave_trophy_losses"] = completed_wave_losses
		"crystal_purchased":
			counters["crystals_purchased"] = int(counters.get("crystals_purchased", 0)) + amount
		"fusion_completed":
			counters["fusions_completed"] = int(counters.get("fusions_completed", 0)) + amount
			if _run_active:
				candidate["run_fusions"] = int(
					candidate.get("run_fusions", 0)
				) + amount
		"tower_upgrade_completed":
			counters["tower_upgrades"] = int(counters.get("tower_upgrades", 0)) + amount
		"essence_earned":
			counters["essence_earned"] = int(counters.get("essence_earned", 0)) + amount
		"trophy_delivered":
			counters["trophy_deliveries"] = int(counters.get("trophy_deliveries", 0)) + amount
			candidate["run_trophy_losses"] = int(
				candidate.get("run_trophy_losses", 0)
			) + amount
			var delivered_wave_losses: Dictionary = candidate["wave_trophy_losses"]
			var delivered_wave_number := int(details.get("wave_number", 0))
			if delivered_wave_number > 0:
				var delivered_wave_key := str(delivered_wave_number)
				delivered_wave_losses[delivered_wave_key] = int(
					delivered_wave_losses.get(delivered_wave_key, 0)
				) + amount
			candidate["wave_trophy_losses"] = delivered_wave_losses
			candidate["lossless_wave_streak"] = 0
		_:
			return

	candidate["counters"] = counters
	_evaluate_achievements(event_type, details, candidate, newly_granted)
	_commit_state(candidate, newly_granted)


func _evaluate_achievements(
	event_type: String,
	details: Dictionary,
	candidate: Dictionary,
	newly_granted: Dictionary
) -> void:
	var counters: Dictionary = candidate["counters"]
	var progress: Dictionary = candidate["progress"]
	for definition in CATALOG.DEFINITIONS:
		var achievement_id := String(definition["id"])
		if candidate["unlocked_ids"].has(achievement_id):
			continue
		var condition_event := String(definition["event"])
		if condition_event != event_type:
			continue

		var condition := String(definition.get("condition", ""))
		var target := _get_public_target(definition)
		var current_progress := _get_progress_for(
			condition_event,
			condition,
			details,
			candidate,
			counters
		)
		current_progress = mini(current_progress, target)
		progress[achievement_id] = current_progress
		if current_progress < target:
			continue

		var unlocked_ids: Array = candidate["unlocked_ids"]
		unlocked_ids.append(achievement_id)
		candidate["unlocked_ids"] = unlocked_ids
		var reward_granted: Dictionary = candidate["reward_granted"]
		reward_granted[achievement_id] = true
		candidate["reward_granted"] = reward_granted
		var essence_reward := int(definition.get("reward_essence", 0))
		var cosmetic_id := String(definition.get("cosmetic_reward_id", ""))
		var cosmetic_type := String(
			definition.get("cosmetic_reward_type", "")
		)
		if not cosmetic_id.is_empty():
			var cosmetics: Dictionary = candidate["unlocked_cosmetics"]
			cosmetics[cosmetic_id] = cosmetic_type
			candidate["unlocked_cosmetics"] = cosmetics
		_grant_catalog_cosmetics_for_achievement(achievement_id, candidate)
		newly_granted[achievement_id] = essence_reward
	candidate["progress"] = progress
	if event_type in ["enemy_killed", "boss_defeated"]:
		_evaluate_bestiary(candidate, newly_granted)


func _get_progress_for(
	event_type: String,
	condition: String,
	details: Dictionary,
	candidate: Dictionary,
	counters: Dictionary
) -> int:
	match condition:
		"all_tier_one_bosses":
			return _count_defeated_tier_one_bosses(candidate)
		"bestiary_complete":
			return _get_bestiary_progress(candidate)
		"perfect_wave_ten":
			return 1 if (
				int(details.get("wave_number", 0)) == 10
				and int(details.get("remaining_trophies", 0)) == 5
				and int(details.get("total_trophies", 0)) == 5
			) else 0
		"lossless_wave_streak":
			return int(candidate.get("lossless_wave_streak", 0))
		"run_fusion_streak":
			return (
				int(candidate.get("run_fusions", 0))
				if _run_active
				else 0
			)
		"boss_wave_without_trophy_loss":
			var boss_wave_losses: Dictionary = candidate["wave_trophy_losses"]
			return 1 if (
				_run_active
				and int(
					boss_wave_losses.get(
						str(int(details.get("wave_number", 0))),
						0
					)
				) == 0
			) else 0
		"final_skeleton_death":
			return 1 if (
				String(details.get("boss_type", "")) == "skeleton_boss"
			) else 0
		_:
			match event_type:
				"enemy_killed":
					return int(counters.get("enemy_kills", 0))
				"boss_defeated":
					return int(counters.get("boss_kills", 0))
				"wave_completed":
					return int(details.get("wave_number", 0))
				"crystal_purchased":
					return int(counters.get("crystals_purchased", 0))
				"fusion_completed":
					return int(counters.get("fusions_completed", 0))
				"tower_upgrade_completed":
					return int(counters.get("tower_upgrades", 0))
				"essence_earned":
					return int(counters.get("essence_earned", 0))
				"trophy_delivered":
					return int(counters.get("trophy_deliveries", 0))
	return 0


func _evaluate_bestiary(
	candidate: Dictionary,
	newly_granted: Dictionary
) -> void:
	var achievement_id := "bestiary_complete"
	var current_progress := _get_bestiary_progress(candidate)
	candidate["progress"][achievement_id] = current_progress
	if (
		not _is_bestiary_complete(candidate)
		or candidate["unlocked_ids"].has(achievement_id)
	):
		return

	for definition in CATALOG.DEFINITIONS:
		if String(definition["id"]) != achievement_id:
			continue
		var unlocked_ids: Array = candidate["unlocked_ids"]
		unlocked_ids.append(achievement_id)
		candidate["unlocked_ids"] = unlocked_ids
		var reward_granted: Dictionary = candidate["reward_granted"]
		reward_granted[achievement_id] = true
		candidate["reward_granted"] = reward_granted
		var cosmetics: Dictionary = candidate["unlocked_cosmetics"]
		cosmetics[String(definition["cosmetic_reward_id"])] = String(
			definition["cosmetic_reward_type"]
		)
		candidate["unlocked_cosmetics"] = cosmetics
		_grant_catalog_cosmetics_for_achievement(achievement_id, candidate)
		newly_granted[achievement_id] = int(
			definition.get("reward_essence", 0)
		)
		return


func _is_bestiary_complete(candidate: Dictionary) -> bool:
	var required_types := _ordinary_enemy_ids.size() + _tier_one_boss_ids.size()
	return (
		not _ordinary_enemy_ids.is_empty()
		and not _tier_one_boss_ids.is_empty()
		and _get_bestiary_progress(candidate) >= required_types
	)


func _get_bestiary_progress(candidate: Dictionary) -> int:
	var found := 0
	var enemy_kills: Dictionary = candidate["enemy_kills"]
	for enemy_id in _ordinary_enemy_ids:
		if int(enemy_kills.get(enemy_id, 0)) > 0:
			found += 1
	return found + _count_defeated_tier_one_bosses(candidate)


func _count_defeated_tier_one_bosses(candidate: Dictionary) -> int:
	var defeated := 0
	var boss_kills: Dictionary = candidate["boss_kills"]
	for boss_id in _tier_one_boss_ids:
		if int(boss_kills.get(boss_id, 0)) > 0:
			defeated += 1
	return defeated


func _commit_state(
	candidate: Dictionary,
	newly_granted: Dictionary = {}
) -> void:
	if not _achievement_state_writable:
		return
	var reward_claims: Dictionary = {}
	for achievement_id in newly_granted:
		reward_claims["achievement_%s" % achievement_id] = int(
			newly_granted[achievement_id]
		)
	if not CrystalInventory.commit_achievement_state(
		candidate,
		reward_claims
	):
		push_error("Achievement progress could not be saved.")
		return
	var previous_unlocked: Array = _state["unlocked_ids"]
	var previous_cosmetics: Dictionary = _state["unlocked_cosmetics"]
	var previous_progress: Dictionary = _state["progress"]
	_state = candidate
	for achievement_id in _state["progress"]:
		var current_progress := int(_state["progress"][achievement_id])
		if current_progress != int(previous_progress.get(achievement_id, 0)):
			for definition in CATALOG.DEFINITIONS:
				if String(definition["id"]) == String(achievement_id):
					if (
						bool(definition["hidden"])
						and not _state["unlocked_ids"].has(achievement_id)
					):
						break
					achievement_progress_changed.emit(
						String(achievement_id),
						current_progress,
						_get_public_target(definition)
					)
					break
	for achievement_id in _state["unlocked_ids"]:
		if not previous_unlocked.has(achievement_id):
			achievement_unlocked.emit(String(achievement_id))
	for cosmetic_id in _state["unlocked_cosmetics"]:
		if not previous_cosmetics.has(cosmetic_id):
			cosmetic_unlocked.emit(
				String(cosmetic_id),
				String(_state["unlocked_cosmetics"][cosmetic_id])
			)


func _get_public_target(definition: Dictionary) -> int:
	if String(definition.get("condition", "")) == "bestiary_complete":
		return maxi(_ordinary_enemy_ids.size() + _tier_one_boss_ids.size(), 1)
	return int(definition["target"])


func _load_state() -> void:
	var stored: Dictionary = CrystalInventory.get_achievement_state()
	_state = _create_default_state()
	if stored.is_empty():
		return
	if int(stored.get("schema_version", 0)) > ACHIEVEMENT_SAVE_VERSION:
		_achievement_state_writable = false
		push_error("Achievement save uses an unsupported newer schema version.")
		return

	for key in ["counters", "enemy_kills", "boss_kills", "progress",
			"reward_granted", "unlocked_cosmetics"]:
		if typeof(stored.get(key, {})) == TYPE_DICTIONARY:
			_state[key] = stored[key].duplicate(true)
	for key in ["unlocked_ids"]:
		if typeof(stored.get(key, [])) == TYPE_ARRAY:
			_state[key] = stored[key].duplicate()
	for key in [
		"run_fusions",
		"run_trophy_losses",
		"lossless_wave_streak",
		"completed_waves"
	]:
		_state[key] = maxi(int(stored.get(key, 0)), 0)
	var stored_wave_losses: Variant = stored.get("wave_trophy_losses", {})
	if typeof(stored_wave_losses) == TYPE_DICTIONARY:
		_state["wave_trophy_losses"] = stored_wave_losses.duplicate(true)


func _create_default_state() -> Dictionary:
	return {
		"schema_version": ACHIEVEMENT_SAVE_VERSION,
		"counters": {},
		"enemy_kills": {},
		"boss_kills": {},
		"progress": {},
		"unlocked_ids": [],
		"reward_granted": {},
		"unlocked_cosmetics": {},
		"run_fusions": 0,
		"run_trophy_losses": 0,
		"wave_trophy_losses": {},
		"lossless_wave_streak": 0,
		"completed_waves": 0
	}


func _discover_enemy_types() -> void:
	_ordinary_enemy_ids.clear()
	var directory := DirAccess.open("res://enemies")
	if directory == null:
		push_error("Could not open res://enemies to discover enemy types.")
		return
	for file_name in directory.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var data := load("res://enemies/%s" % file_name) as EnemyData
		if data == null or data.enemy_id.is_empty():
			continue
		var enemy_id := String(data.enemy_id)
		if (
			data.is_summon
			or enemy_id.ends_with("_summon")
			or enemy_id.begins_with("summon_")
		):
			continue
		_ordinary_enemy_ids.append(enemy_id)


func _discover_tier_one_bosses() -> void:
	_tier_one_boss_ids.clear()
	for boss_data in BOSS_WAVE_SCHEDULE.get_boss_pool(1):
		if boss_data != null and not boss_data.boss_id.is_empty():
			_tier_one_boss_ids.append(String(boss_data.boss_id))


func get_catalog_enemy_types() -> Array[String]:
	return _ordinary_enemy_ids.duplicate()


func get_tier_one_boss_types() -> Array[String]:
	return _tier_one_boss_ids.duplicate()
