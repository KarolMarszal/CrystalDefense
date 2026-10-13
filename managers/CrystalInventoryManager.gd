extends Node

signal profile_changed(profile: Dictionary)
signal save_status_changed(success: bool, message: String)
signal run_inventory_changed
signal essence_awarded(amount: int)
signal essence_earned(amount: int)

const CURRENT_SCHEMA_VERSION: int = 4
const MAX_ESSENCE: int = 9007199254740991
const FIRST_ESSENCE_THRESHOLD: int = 100
const MAX_ESSENCE_THRESHOLD: int = 1000000000000000
const ESSENCE_THRESHOLD_GROWTH_PERCENT: int = 105
const MAX_CRYSTAL_SHOP_PURCHASES: int = MAX_ESSENCE
const MAX_CRYSTAL_SHOP_PRICE: int = 100
const MAX_CRYSTAL_ENTRIES: int = 100
const MAX_CRYSTAL_LEVEL: int = 10000
const CRYSTAL_FUSION_SKILL_ID: StringName = &"crystal_fusion"
const MAX_CRYSTAL_QUANTITY: int = 1000000
const MAX_UNLOCKED_CRYSTALS: int = 100
const MAX_SKILL_NODES_PER_TREE: int = 1000
const MAX_REWARD_CLAIMS: int = 10000
const MAX_RECORD_KEYS: int = 1000
const MAX_PROFILE_STRING_LENGTH: int = 4096
const MAX_RESERVED_DATA_DEPTH: int = 8

const PROFILE_FILE_NAME: String = "player_profile.json"
const PROFILE_TEMP_FILE_NAME: String = "player_profile.tmp"
const PROFILE_BACKUP_FILE_NAME: String = "player_profile.bak"
const PROFILE_BACKUP_TEMP_FILE_NAME: String = "player_profile.bak.tmp"
const AWAKENING_RAPID_FIRE_REWARD_CLAIM: String = "awakening_rapid_fire_crystal"
const AWAKENING_KINETIC_REWARD_CLAIM: String = "awakening_kinetic_crystal"
static func get_skill_crystal_rewards() -> Dictionary:
	var rewards: Dictionary = {}
	for definition in SKILL_CATALOG.get_skill_definitions():
		var crystal_id := String(definition["unlock_crystal_id"])
		if not crystal_id.is_empty():
			rewards[String(definition["id"])] = crystal_id
	return rewards

const SKILL_TREE_KEYS: Array[String] = [
	"crystals",
	"economy",
	"elemental_mastery",
	"tower_enhancements"
]

const CRYSTAL_CATALOG: Dictionary = {
	"rapid_fire": preload("res://crystals/RapidFireCrystal.tres"),
	"kinetic": preload("res://crystals/KineticCrystal.tres"),
	"sniper": preload("res://crystals/SniperCrystal.tres"),
	"fire": preload("res://crystals/FireCrystal.tres"),
	"slow": preload("res://crystals/SlowCrystal.tres"),
	"bleed": preload("res://crystals/BleedCrystal.tres")
}
const SKILL_CATALOG = preload("res://managers/skill_tree_catalog.gd")

@export var profile_storage_directory: String = "user://"

var _profile: Dictionary = {}
var _run_crystals: Dictionary = {}
var _skill_effect_values: Dictionary = {}
var _run_inventory_active: bool = false
var _profile_writable: bool = false
var _last_parse_error: String = ""
var _profile_requires_migration_save: bool = false
var _crystal_shop_rng := RandomNumberGenerator.new()
var last_load_success: bool = false
var last_load_message: String = "Profile has not been loaded."
var last_save_success: bool = false
var last_save_message: String = "Profile has not been saved."

var essence: int:
	get:
		return int(_profile.get("essence", 0))


func _ready() -> void:
	_crystal_shop_rng.randomize()
	load_profile()


func load_profile() -> bool:
	_skill_effect_values.clear()
	_profile_writable = false
	var profile_path := _get_profile_path(PROFILE_FILE_NAME)
	var backup_path := _get_profile_path(PROFILE_BACKUP_FILE_NAME)
	if not FileAccess.file_exists(profile_path):
		_profile = _create_default_profile()
		_profile_writable = true
		last_load_success = true
		last_load_message = "No profile save found; initialized a new profile."
		if not save_profile():
			_profile_writable = false
			last_load_success = false
			last_load_message = (
				"Initialized a new profile in memory, but could not create its save: "
				+ last_save_message
			)
			return false
		profile_changed.emit(get_profile_data())
		return true

	var primary := _read_profile_file(profile_path)
	if not primary.is_empty():
		_profile = primary
		_profile_writable = true
		last_load_success = true
		last_load_message = "Loaded player profile."
		if _profile_requires_migration_save:
			last_load_message = "Loaded player profile and applied schema migration."
			if not save_profile():
				last_load_message += " Migration save failed: " + last_save_message
		else:
			_set_save_status(true, "Loaded player profile.")
		profile_changed.emit(get_profile_data())
		return true

	var primary_error := _last_parse_error
	var primary_is_future_version := primary_error.contains(
		"is newer than supported version"
	)
	if FileAccess.file_exists(backup_path):
		var backup := _read_profile_file(backup_path)
		if not backup.is_empty():
			_profile = backup
			_profile_writable = not primary_is_future_version
			last_load_success = true
			if primary_is_future_version:
				last_load_message = (
					"Primary save uses a newer schema and was preserved. "
					+ "Loaded the backup read-only: "
					+ primary_error
				)
				_set_save_status(false, last_load_message)
			else:
				last_load_message = (
					"Recovered player profile from backup. Primary save error: "
					+ primary_error
				)
				if not _write_profile_file(_profile, false):
					last_load_message += " Primary repair failed: " + last_save_message
				else:
					_set_save_status(
						true,
						"Recovered the primary save from the valid backup."
					)
			profile_changed.emit(get_profile_data())
			return true

		last_load_message = (
			"Primary save is invalid (%s); backup is also invalid (%s). "
			+ "Original files were preserved."
		) % [primary_error, _last_parse_error]
	else:
		last_load_message = (
			"Primary save is invalid (%s); no backup is available. "
			+ "Original file was preserved."
		) % primary_error

	_profile = _create_default_profile()
	last_load_success = false
	_set_save_status(false, last_load_message)
	push_error(last_load_message)
	return false


func save_profile() -> bool:
	if not _profile_writable:
		_set_save_status(
			false,
			"Profile saving is disabled because no valid writable profile was loaded."
		)
		return false

	return _write_profile_file(_profile, true)


func get_profile_data() -> Dictionary:
	return _profile.duplicate(true)


func get_essence_balance() -> int:
	return essence


func add_essence(amount: int) -> bool:
	if amount <= 0 or essence > MAX_ESSENCE - amount:
		return false

	var candidate := _profile.duplicate(true)
	candidate["essence"] = essence + amount
	return _commit_profile(candidate)


func spend_essence(amount: int) -> bool:
	if amount <= 0 or amount > essence:
		return false

	var candidate := _profile.duplicate(true)
	candidate["essence"] = essence - amount
	return _commit_profile(candidate)


static func get_crystal_shop_price_for_purchase_count(purchase_count: int) -> int:
	if purchase_count >= 29:
		return MAX_CRYSTAL_SHOP_PRICE
	if purchase_count <= 0:
		return 1

	var numerator := 10 + 5 * purchase_count + purchase_count * purchase_count
	return mini(int((numerator + 9) / 10), MAX_CRYSTAL_SHOP_PRICE)


func get_crystal_shop_purchase_count() -> int:
	return int(_profile.get("crystal_shop_purchase_count", 0))


func get_crystal_shop_price() -> int:
	return get_crystal_shop_price_for_purchase_count(
		get_crystal_shop_purchase_count()
	)


func get_crystal_shop_eligible_ids() -> Array[StringName]:
	var eligible: Array[StringName] = []
	for crystal_id in _profile.get("unlocked_crystal_ids", []):
		var id := StringName(crystal_id)
		if is_crystal_unlocked(id):
			eligible.append(id)
	return eligible


func purchase_random_crystal() -> bool:
	if not is_crystal_inventory_unlocked():
		return false

	var purchase_count := get_crystal_shop_purchase_count()
	if purchase_count >= MAX_CRYSTAL_SHOP_PURCHASES:
		return false
	var price := get_crystal_shop_price_for_purchase_count(purchase_count)
	if essence < price:
		return false

	var eligible_ids := get_crystal_shop_eligible_ids()
	if eligible_ids.is_empty():
		return false

	var selected_id: StringName = eligible_ids[
		_crystal_shop_rng.randi_range(0, eligible_ids.size() - 1)
	]
	var candidate := _profile.duplicate(true)
	candidate["essence"] = essence - price
	candidate["crystal_shop_purchase_count"] = purchase_count + 1
	if not _add_crystal_to_profile(candidate, String(selected_id), 1, 1):
		return false
	if not _commit_profile(candidate):
		return false
	AchievementManager.report_crystal_purchased(selected_id)
	return true


# Each threshold is the previous one plus 5%, rounded up. Integer math avoids
# float error (100 * 1.05 would otherwise round up to 106).
static func get_next_essence_threshold(current_threshold: int) -> int:
	var grown := (
		current_threshold * ESSENCE_THRESHOLD_GROWTH_PERCENT + 99
	) / 100
	return mini(maxi(grown, current_threshold), MAX_ESSENCE_THRESHOLD)


func get_essence_points() -> int:
	return int(_profile.get("essence_points", 0))


func get_essence_threshold() -> int:
	return int(_profile.get("essence_threshold", FIRST_ESSENCE_THRESHOLD))


# Adds hidden progress points and converts every crossed threshold into one
# persistent Essence in a single atomic profile commit. Returns the number of
# Essence awarded, or -1 if nothing could be saved.
func add_essence_points(points: int) -> int:
	if points <= 0:
		return 0

	var accumulated := get_essence_points()
	var threshold := get_essence_threshold()
	if accumulated > MAX_ESSENCE_THRESHOLD - points:
		return -1
	accumulated += points
	var awarded := 0
	while accumulated >= threshold:
		accumulated -= threshold
		threshold = get_next_essence_threshold(threshold)
		awarded += 1
	if essence > MAX_ESSENCE - awarded:
		return -1

	var candidate := _profile.duplicate(true)
	candidate["essence_points"] = accumulated
	candidate["essence_threshold"] = threshold
	candidate["essence"] = essence + awarded
	if not _commit_profile(candidate):
		return -1
	if awarded > 0:
		essence_awarded.emit(awarded)
	return awarded


func add_crystal(
	crystal: CrystalData,
	crystal_level: int = 1,
	quantity: int = 1
) -> bool:
	if not is_crystal_inventory_unlocked():
		push_error("Cannot add crystals before skill A unlocks the inventory.")
		return false
	if crystal == null:
		push_error("Cannot add a null Crystal to the persistent inventory.")
		return false
	if crystal_level < 1 or crystal_level > MAX_CRYSTAL_LEVEL:
		push_error("Crystal level is outside the supported profile limits.")
		return false
	if quantity < 1 or quantity > MAX_CRYSTAL_QUANTITY:
		push_error("Crystal quantity is outside the supported profile limits.")
		return false

	var crystal_id := String(crystal.crystal_id)
	if not CRYSTAL_CATALOG.has(crystal_id):
		push_error("Cannot add an unknown Crystal ID '%s'." % crystal_id)
		return false

	var candidate := _profile.duplicate(true)
	if not _add_crystal_to_profile(
		candidate,
		crystal_id,
		crystal_level,
		quantity
	):
		return false
	return _commit_profile(candidate)


func is_crystal_fusion_unlocked() -> bool:
	return is_skill_purchased(CRYSTAL_FUSION_SKILL_ID)


func can_fuse_crystals(crystal_id: StringName, level: int) -> bool:
	if not is_crystal_fusion_unlocked():
		return false
	if not _is_valid_fusion_input(crystal_id, level):
		return false

	if _run_inventory_active:
		var input_key := _get_run_crystal_key(crystal_id, level)
		var run_input_entry: Dictionary = _run_crystals.get(input_key, {})
		if int(run_input_entry.get("quantity", 0)) < 2:
			return false
		var run_output_level := level + 1
		if not _has_finite_crystal_level_stats(crystal_id, run_output_level):
			return false
		var output_key := _get_run_crystal_key(crystal_id, run_output_level)
		var run_output_entry: Dictionary = _run_crystals.get(output_key, {})
		if int(run_output_entry.get("quantity", 0)) >= MAX_CRYSTAL_QUANTITY:
			return false
		var run_resulting_entry_count := _run_crystals.size()
		if int(run_input_entry["quantity"]) == 2:
			run_resulting_entry_count -= 1
		if run_output_entry.is_empty():
			run_resulting_entry_count += 1
		if run_resulting_entry_count > MAX_CRYSTAL_ENTRIES:
			return false
		return true

	var entries: Array = _profile.get("crystals", [])
	var owned_input_entry := _find_profile_crystal_entry(
		entries,
		String(crystal_id),
		level
	)
	if owned_input_entry.is_empty() or int(owned_input_entry["quantity"]) < 2:
		return false
	var owned_output_level := level + 1
	if not _has_finite_crystal_level_stats(crystal_id, owned_output_level):
		return false
	var owned_output_entry := _find_profile_crystal_entry(
		entries,
		String(crystal_id),
		owned_output_level
	)
	if not owned_output_entry.is_empty():
		return int(owned_output_entry["quantity"]) < MAX_CRYSTAL_QUANTITY
	var owned_resulting_entry_count := entries.size()
	if int(owned_input_entry["quantity"]) == 2:
		owned_resulting_entry_count -= 1
	owned_resulting_entry_count += 1
	return owned_resulting_entry_count <= MAX_CRYSTAL_ENTRIES


func fuse_crystals(crystal_id: StringName, level: int) -> bool:
	if not can_fuse_crystals(crystal_id, level):
		return false

	var output_level := level + 1
	if _run_inventory_active:
		var candidate := _run_crystals.duplicate(true)
		_adjust_run_crystal_quantity(candidate, crystal_id, level, -2)
		_adjust_run_crystal_quantity(candidate, crystal_id, output_level, 1)
		if candidate.size() > MAX_CRYSTAL_ENTRIES:
			return false
		_run_crystals = candidate
		run_inventory_changed.emit()
	else:
		var candidate_profile := _profile.duplicate(true)
		var crystals: Array = candidate_profile["crystals"]
		if not _adjust_profile_crystal_quantity(
			crystals,
			String(crystal_id),
			level,
			-2
		):
			return false
		if not _add_crystal_to_profile(
			candidate_profile,
			String(crystal_id),
			output_level,
			1
		):
			return false
		if not _commit_profile(candidate_profile):
			return false

	AchievementManager.report_crystal_fusion_completed()
	return true


func _add_crystal_to_profile(
	candidate: Dictionary,
	crystal_id: String,
	crystal_level: int,
	quantity: int
) -> bool:
	var entries: Array = candidate["crystals"]
	var found_index := -1
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		if entry["crystal_id"] == crystal_id and entry["level"] == crystal_level:
			found_index = index
			break

	if found_index >= 0:
		var existing: Dictionary = entries[found_index]
		if int(existing["quantity"]) > MAX_CRYSTAL_QUANTITY - quantity:
			push_error("Crystal quantity would exceed the supported profile limit.")
			return false
		existing["quantity"] = int(existing["quantity"]) + quantity
		entries[found_index] = existing
	else:
		if entries.size() >= MAX_CRYSTAL_ENTRIES:
			push_error("Crystal inventory has reached the supported entry limit.")
			return false
		entries.append({
			"crystal_id": crystal_id,
			"level": crystal_level,
			"quantity": quantity
		})

	candidate["crystals"] = entries
	return true


func _is_valid_fusion_input(crystal_id: StringName, level: int) -> bool:
	return (
		level >= 1
		and level < MAX_CRYSTAL_LEVEL
		and CRYSTAL_CATALOG.has(String(crystal_id))
		and is_crystal_unlocked(crystal_id)
	)


func _has_finite_crystal_level_stats(
	crystal_id: StringName,
	level: int
) -> bool:
	var definition := get_crystal_definition(crystal_id)
	if definition == null:
		return false
	if (
		not is_finite(definition.crystal_level_growth)
		or definition.crystal_level_growth <= 0.0
	):
		return false
	var level_scale := pow(definition.crystal_level_growth, level - 1)
	if not is_finite(level_scale):
		return false
	var base_stats: Array[float] = [
		definition.damage,
		definition.attack_speed,
		definition.attack_range,
		definition.slow_fraction,
		definition.slow_duration,
		definition.bleed_max_hp_fraction_per_second,
		definition.bleed_duration,
		CrystalData.FIRE_AREA_DAMAGE_FRACTION,
		CrystalData.FIRE_AREA_DAMAGE_RADIUS
	]
	for base_stat in base_stats:
		if not is_finite(base_stat * level_scale):
			return false
	return true


func _find_profile_crystal_entry(
	entries: Array,
	crystal_id: String,
	level: int
) -> Dictionary:
	for entry in entries:
		if (
			String(entry["crystal_id"]) == crystal_id
			and int(entry["level"]) == level
		):
			return entry
	return {}


func _adjust_profile_crystal_quantity(
	entries: Array,
	crystal_id: String,
	level: int,
	delta: int
) -> bool:
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		if (
			String(entry["crystal_id"]) != crystal_id
			or int(entry["level"]) != level
		):
			continue
		var quantity := int(entry["quantity"]) + delta
		if quantity < 0:
			return false
		if quantity == 0:
			entries.remove_at(index)
		else:
			entry["quantity"] = quantity
			entries[index] = entry
		return true
	return false


func get_owned_crystals() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for entry in _profile.get("crystals", []):
		var crystal_id: String = entry["crystal_id"]
		if not CRYSTAL_CATALOG.has(crystal_id):
			continue
		snapshot.append({
			"definition": CRYSTAL_CATALOG[crystal_id],
			"level": entry["level"],
			"quantity": entry["quantity"]
		})
	return snapshot


func get_crystal_definition(crystal_id: StringName) -> CrystalData:
	return CRYSTAL_CATALOG.get(String(crystal_id)) as CrystalData


func is_crystal_unlocked(crystal_id: StringName) -> bool:
	if (
		not is_crystal_inventory_unlocked()
		or not CRYSTAL_CATALOG.has(String(crystal_id))
	):
		return false
	return _profile.get("unlocked_crystal_ids", []).has(String(crystal_id))


func is_crystal_inventory_unlocked() -> bool:
	return is_skill_purchased(&"A")


func get_purchased_skill_node_ids(tree_id: StringName) -> Array[String]:
	var purchased: Array[String] = []
	var tree_key := String(tree_id)
	if not SKILL_TREE_KEYS.has(tree_key):
		return purchased

	for node_id in _profile.get("purchased_skill_nodes", {}).get(tree_key, []):
		purchased.append(String(node_id))
	return purchased


func is_skill_purchased(skill_id: StringName) -> bool:
	var definition := SKILL_CATALOG.get_skill_definition(skill_id)
	if definition.is_empty():
		return false
	return get_purchased_skill_node_ids(
		StringName(definition["category"])
	).has(String(skill_id))


func get_skill_effect_value(effect_id: StringName) -> float:
	if _skill_effect_values.has(effect_id):
		return float(_skill_effect_values[effect_id])

	var total := 0.0
	for tree_id in SKILL_TREE_KEYS:
		for skill_id in get_purchased_skill_node_ids(StringName(tree_id)):
			var definition := SKILL_CATALOG.get_skill_definition(
				StringName(skill_id)
			)
			if (
				not definition.is_empty()
				and definition["effect_id"] == String(effect_id)
			):
				total += float(definition["effect_value"])
	_skill_effect_values[effect_id] = total
	return total


func get_skill_node_status(skill_id: StringName) -> Dictionary:
	var definition := SKILL_CATALOG.get_skill_definition(skill_id)
	if definition.is_empty():
		return {"state": "invalid"}

	var prerequisites: Array[String] = []
	for tree_id in SKILL_TREE_KEYS:
		prerequisites.append_array(
			get_purchased_skill_node_ids(StringName(tree_id))
		)
	var missing := SKILL_CATALOG.get_missing_prerequisites(
		skill_id,
		prerequisites
	)
	var purchased := prerequisites.has(String(skill_id))
	var visible := (
		String(definition["visible_after"]).is_empty()
		or prerequisites.has(String(definition["visible_after"]))
	)
	var state := "locked"
	if not visible:
		state = "hidden"
	elif purchased:
		state = "purchased"
	elif not missing.is_empty():
		state = "locked"
	elif essence < int(definition["cost"]):
		state = "unaffordable"
	else:
		state = "available"

	return {
		"definition": definition,
		"state": state,
		"visible": visible,
		"purchased": purchased,
		"missing_prerequisites": missing,
		"can_purchase": state == "available"
	}


func purchase_skill_node(skill_id: StringName) -> bool:
	var status := get_skill_node_status(skill_id)
	if not bool(status.get("can_purchase", false)):
		return false

	var definition: Dictionary = status["definition"]
	var cost := int(definition["cost"])
	var reward_crystal_id: String = get_skill_crystal_rewards().get(
		String(skill_id),
		""
	)
	var reward_claim := "skill_crystal_reward_%s" % String(skill_id)
	var grants_skill_crystal: bool = (
		not reward_crystal_id.is_empty()
		and (
			not _profile["reward_claims"].has(reward_claim)
			or not _owns_crystal_any_level(reward_crystal_id)
		)
	)
	var grants_awakening_crystal: bool = (
		String(skill_id) == "A"
		and not _profile["reward_claims"].has(
			AWAKENING_RAPID_FIRE_REWARD_CLAIM
		)
	)
	var grants_awakening_kinetic: bool = (
		String(skill_id) == "A"
		and not _profile["reward_claims"].has(
			AWAKENING_KINETIC_REWARD_CLAIM
		)
	)
	var category := String(definition["category"])
	var candidate := _profile.duplicate(true)
	candidate["essence"] = int(candidate["essence"]) - cost
	var purchased_by_tree: Dictionary = candidate["purchased_skill_nodes"]
	var purchased_ids: Array = purchased_by_tree[category]
	if purchased_ids.has(String(skill_id)):
		return false
	purchased_ids.append(String(skill_id))
	purchased_by_tree[category] = purchased_ids
	candidate["purchased_skill_nodes"] = purchased_by_tree

	var unlocked_crystal_id := String(definition["unlock_crystal_id"])
	if not unlocked_crystal_id.is_empty():
		var unlocked_ids: Array = candidate["unlocked_crystal_ids"]
		if not unlocked_ids.has(unlocked_crystal_id):
			unlocked_ids.append(unlocked_crystal_id)
		candidate["unlocked_crystal_ids"] = unlocked_ids
	if not reward_crystal_id.is_empty():
		var reward_unlocked_ids: Array = candidate["unlocked_crystal_ids"]
		if not reward_unlocked_ids.has(reward_crystal_id):
			reward_unlocked_ids.append(reward_crystal_id)
		candidate["unlocked_crystal_ids"] = reward_unlocked_ids

	if String(skill_id) == "A":
		if (
			not _grant_awakening_rapid_fire_crystal(candidate)
			or not _grant_awakening_kinetic_crystal(candidate)
		):
			_set_save_status(
				false,
				"Could not grant the Awakening Magic rewards: " + _last_parse_error
			)
			return false
	elif grants_skill_crystal and not _grant_skill_crystal_reward(
		candidate,
		reward_crystal_id,
		reward_claim
	):
		_set_save_status(
			false,
			"Could not grant the %s skill reward: %s"
			% [String(skill_id), _last_parse_error]
		)
		return false

	if not _commit_profile(candidate):
		return false
	if grants_awakening_crystal and _run_inventory_active:
		_store_run_crystal(&"rapid_fire", 1, 1)
		run_inventory_changed.emit()
	if grants_awakening_kinetic and _run_inventory_active:
		_store_run_crystal(&"kinetic", 1, 1)
		run_inventory_changed.emit()
	if grants_skill_crystal and _run_inventory_active:
		if not add_run_crystal(StringName(reward_crystal_id), 1, 1):
			push_error(
				"Skill %s reward was saved but could not be added to this run's inventory."
				% String(skill_id)
			)
	return true


func reset_purchased_skill_nodes() -> bool:
	var candidate := _profile.duplicate(true)
	var purchased_by_tree: Dictionary = candidate["purchased_skill_nodes"]
	var refunded_essence := 0
	var skill_unlocked_crystals: Dictionary = {}
	var refunded_skill_ids: Dictionary = {}

	for tree_id in SKILL_TREE_KEYS:
		var purchased_ids: Array = purchased_by_tree[tree_id]
		for purchased_id in purchased_ids:
			if refunded_skill_ids.has(purchased_id):
				continue
			var definition := SKILL_CATALOG.get_skill_definition(
				StringName(purchased_id)
			)
			if definition.is_empty() or definition["category"] != tree_id:
				_set_save_status(
					false,
					"Cannot reset unknown skill '%s' in '%s'." % [
						purchased_id,
						tree_id
					]
				)
				return false
			refunded_skill_ids[purchased_id] = true
			refunded_essence += int(definition["cost"])
			var crystal_id := String(definition["unlock_crystal_id"])
			if not crystal_id.is_empty():
				skill_unlocked_crystals[crystal_id] = true
			var reward_crystal_id: String = get_skill_crystal_rewards().get(
				String(purchased_id),
				""
			)
			if not reward_crystal_id.is_empty():
				skill_unlocked_crystals[reward_crystal_id] = true
		purchased_by_tree[tree_id] = []

	if essence > MAX_ESSENCE - refunded_essence:
		_set_save_status(false, "Skill reset refund would exceed the Essence limit.")
		return false

	candidate["essence"] = essence + refunded_essence
	candidate["purchased_skill_nodes"] = purchased_by_tree
	if candidate["reward_claims"].has("skill_crystal_reward_I"):
		skill_unlocked_crystals["fire"] = true
	var unlocked_crystal_ids: Array = candidate["unlocked_crystal_ids"]
	unlocked_crystal_ids = unlocked_crystal_ids.filter(
		func(crystal_id: String) -> bool:
			return not skill_unlocked_crystals.has(crystal_id)
	)
	candidate["unlocked_crystal_ids"] = unlocked_crystal_ids
	return _commit_profile(candidate)


func start_run_inventory() -> void:
	_run_crystals.clear()
	_run_inventory_active = true
	if is_crystal_inventory_unlocked():
		for entry in _profile.get("crystals", []):
			var crystal_id := StringName(entry["crystal_id"])
			var level := int(entry["level"])
			_store_run_crystal(crystal_id, level, int(entry["quantity"]))
	run_inventory_changed.emit()


func end_run_inventory() -> void:
	if not _run_inventory_active and _run_crystals.is_empty():
		return

	_run_crystals.clear()
	_run_inventory_active = false
	run_inventory_changed.emit()


func is_run_inventory_active() -> bool:
	return _run_inventory_active


func get_available_crystals() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	var keys: Array = _run_crystals.keys()
	keys.sort()
	for key in keys:
		var entry: Dictionary = _run_crystals[key]
		var definition := _get_crystal_definition(entry["crystal_id"])
		if definition == null:
			continue
		snapshot.append({
			"crystal_id": String(entry["crystal_id"]),
			"definition": definition,
			"level": int(entry["level"]),
			"quantity": int(entry["quantity"])
		})
	return snapshot


func get_available_crystal_quantity(crystal_id: StringName, level: int) -> int:
	if not _run_inventory_active or not _is_valid_run_crystal(crystal_id, level):
		return 0

	var entry: Dictionary = _run_crystals.get(
		_get_run_crystal_key(crystal_id, level),
		{}
	)
	return int(entry.get("quantity", 0))


func get_available_crystal_level(crystal_id: StringName) -> int:
	var levels: Array[int] = []
	for entry in _run_crystals.values():
		if entry["crystal_id"] == String(crystal_id) and int(entry["quantity"]) > 0:
			levels.append(int(entry["level"]))
	if levels.is_empty():
		return 0
	levels.sort()
	return levels[0]


func add_run_crystal(
	crystal_id: StringName,
	level: int = 1,
	quantity: int = 1
) -> bool:
	if (
		not _run_inventory_active
		or not _is_valid_run_crystal(crystal_id, level)
		or quantity < 1
		or quantity > MAX_CRYSTAL_QUANTITY
	):
		return false

	var key := _get_run_crystal_key(crystal_id, level)
	var existing: Dictionary = _run_crystals.get(key, {})
	var existing_quantity := int(existing.get("quantity", 0))
	if existing_quantity > MAX_CRYSTAL_QUANTITY - quantity:
		return false
	if existing.is_empty() and _run_crystals.size() >= MAX_CRYSTAL_ENTRIES:
		return false

	_store_run_crystal(crystal_id, level, existing_quantity + quantity)
	run_inventory_changed.emit()
	return true


func can_install_crystal(crystal: CrystalData, level: int = 1) -> bool:
	if crystal == null:
		return false
	var crystal_id := StringName(crystal.crystal_id)
	return (
		_is_valid_run_crystal(crystal_id, level)
		and get_available_crystal_quantity(crystal_id, level) > 0
	)


func consume_run_crystal(crystal: CrystalData, level: int = 1) -> bool:
	if not can_install_crystal(crystal, level):
		return false

	var key := _get_run_crystal_key(StringName(crystal.crystal_id), level)
	var entry: Dictionary = _run_crystals[key]
	var quantity := int(entry["quantity"]) - 1
	if quantity == 0:
		_run_crystals.erase(key)
	else:
		entry["quantity"] = quantity
		_run_crystals[key] = entry
	run_inventory_changed.emit()
	return true


func can_return_run_crystal(crystal: CrystalInstance) -> bool:
	if (
		not _run_inventory_active
		or crystal == null
		or crystal.definition == null
	):
		return false
	var crystal_id := StringName(crystal.definition.crystal_id)
	if not _is_valid_run_crystal(crystal_id, crystal.level):
		return false
	var key := _get_run_crystal_key(crystal_id, crystal.level)
	var existing: Dictionary = _run_crystals.get(key, {})
	if int(existing.get("quantity", 0)) >= MAX_CRYSTAL_QUANTITY:
		return false
	return not existing.is_empty() or _run_crystals.size() < MAX_CRYSTAL_ENTRIES


func can_replace_run_crystal(
	incoming_crystal_id: StringName,
	incoming_level: int,
	outgoing_crystal: CrystalInstance
) -> bool:
	if (
		not _run_inventory_active
		or outgoing_crystal == null
		or outgoing_crystal.definition == null
	):
		return false
	var outgoing_id := StringName(outgoing_crystal.definition.crystal_id)
	if not _is_valid_run_crystal(outgoing_id, outgoing_crystal.level):
		return false

	if (
		outgoing_id == incoming_crystal_id
		and outgoing_crystal.level == incoming_level
	):
		return true
	if (
		not _is_valid_run_crystal(incoming_crystal_id, incoming_level)
		or get_available_crystal_quantity(incoming_crystal_id, incoming_level) < 1
		or get_available_crystal_quantity(
			outgoing_id,
			outgoing_crystal.level
		) >= MAX_CRYSTAL_QUANTITY
	):
		return false

	var candidate := _run_crystals.duplicate(true)
	_adjust_run_crystal_quantity(
		candidate,
		incoming_crystal_id,
		incoming_level,
		-1
	)
	_adjust_run_crystal_quantity(
		candidate,
		outgoing_id,
		outgoing_crystal.level,
		1
	)
	return candidate.size() <= MAX_CRYSTAL_ENTRIES


func replace_run_crystal(
	incoming_crystal_id: StringName,
	incoming_level: int,
	outgoing_crystal: CrystalInstance
) -> bool:
	if not can_replace_run_crystal(
		incoming_crystal_id,
		incoming_level,
		outgoing_crystal
	):
		return false

	if (
		StringName(outgoing_crystal.definition.crystal_id) == incoming_crystal_id
		and outgoing_crystal.level == incoming_level
	):
		return true

	var candidate := _run_crystals.duplicate(true)
	_adjust_run_crystal_quantity(
		candidate,
		incoming_crystal_id,
		incoming_level,
		-1
	)
	_adjust_run_crystal_quantity(
		candidate,
		StringName(outgoing_crystal.definition.crystal_id),
		outgoing_crystal.level,
		1
	)
	if candidate.size() > MAX_CRYSTAL_ENTRIES:
		return false

	_run_crystals = candidate
	run_inventory_changed.emit()
	return true


func return_run_crystal(crystal: CrystalInstance) -> bool:
	if not can_return_run_crystal(crystal):
		return false

	var crystal_id := StringName(crystal.definition.crystal_id)
	var level := crystal.level
	var key := _get_run_crystal_key(crystal_id, level)
	var existing: Dictionary = _run_crystals.get(key, {})
	_store_run_crystal(
		crystal_id,
		level,
		int(existing.get("quantity", 0)) + 1
	)
	run_inventory_changed.emit()
	return true


func _adjust_run_crystal_quantity(
	inventory: Dictionary,
	crystal_id: StringName,
	level: int,
	delta: int
) -> void:
	var key := _get_run_crystal_key(crystal_id, level)
	var entry: Dictionary = inventory.get(key, {
		"crystal_id": String(crystal_id),
		"level": level,
		"quantity": 0
	})
	var quantity := int(entry["quantity"]) + delta
	if quantity <= 0:
		inventory.erase(key)
	else:
		entry["quantity"] = quantity
		inventory[key] = entry


func _is_valid_run_crystal(crystal_id: StringName, level: int) -> bool:
	return (
		_run_inventory_active
		and is_crystal_inventory_unlocked()
		and level >= 1
		and level <= MAX_CRYSTAL_LEVEL
		and CRYSTAL_CATALOG.has(String(crystal_id))
	)


func _get_crystal_definition(crystal_id: StringName) -> CrystalData:
	return CRYSTAL_CATALOG.get(String(crystal_id)) as CrystalData


func _get_run_crystal_key(crystal_id: StringName, level: int) -> String:
	return "%s:%d" % [String(crystal_id), level]


func _store_run_crystal(
	crystal_id: StringName,
	level: int,
	quantity: int
) -> void:
	var key := _get_run_crystal_key(crystal_id, level)
	if quantity <= 0:
		_run_crystals.erase(key)
		return
	_run_crystals[key] = {
		"crystal_id": String(crystal_id),
		"level": level,
		"quantity": quantity
	}


func _commit_profile(candidate: Dictionary) -> bool:
	var normalized := _normalize_profile(candidate)
	if normalized.is_empty():
		_set_save_status(false, "Profile update failed validation: " + _last_parse_error)
		return false
	var previous_essence := essence
	if not _write_profile_file(normalized, true):
		return false

	_profile = normalized
	_skill_effect_values.clear()
	profile_changed.emit(get_profile_data())
	var earned_essence := int(normalized["essence"]) - previous_essence
	if earned_essence > 0:
		essence_earned.emit(earned_essence)
	return true


func get_achievement_state() -> Dictionary:
	var records: Dictionary = _profile.get("records", {})
	var state: Variant = records.get("achievement_state", {})
	if typeof(state) != TYPE_DICTIONARY:
		return {}
	return state.duplicate(true)


func commit_achievement_state(
	achievement_state: Dictionary,
	reward_claims: Dictionary = {}
) -> bool:
	if not _profile_writable:
		_set_save_status(false, "Cannot save achievement progress without a writable profile.")
		return false

	var candidate := _profile.duplicate(true)
	var records: Dictionary = candidate["records"]
	records["achievement_state"] = achievement_state.duplicate(true)
	candidate["records"] = records

	var claims: Array = candidate["reward_claims"]
	var earned_reward := 0
	for raw_claim_id in reward_claims:
		var claim_id := String(raw_claim_id)
		var amount: Variant = reward_claims[raw_claim_id]
		if (
			claim_id.is_empty()
			or not _is_integer_number(amount)
			or int(amount) < 0
		):
			_set_save_status(false, "Achievement reward claim is invalid.")
			return false
		if claims.has(claim_id):
			continue
		if claims.size() >= MAX_REWARD_CLAIMS:
			_set_save_status(false, "Achievement reward claims exceed the supported limit.")
			return false
		claims.append(claim_id)
		if earned_reward > MAX_ESSENCE - int(amount):
			_set_save_status(false, "Achievement Essence reward exceeds the supported balance.")
			return false
		earned_reward += int(amount)

	if int(candidate["essence"]) > MAX_ESSENCE - earned_reward:
		_set_save_status(false, "Achievement reward would exceed the Essence balance limit.")
		return false
	candidate["essence"] = int(candidate["essence"]) + earned_reward
	candidate["reward_claims"] = claims
	return _commit_profile(candidate)


func get_cosmetic_selections() -> Dictionary:
	var records: Dictionary = _profile.get("records", {})
	var selections: Variant = records.get("cosmetic_selections", {})
	if typeof(selections) != TYPE_DICTIONARY:
		return {}
	return selections.duplicate(true)


func commit_cosmetic_selections(selections: Dictionary) -> bool:
	if not _profile_writable:
		_set_save_status(false, "Cannot save cosmetic selections without a writable profile.")
		return false

	var candidate := _profile.duplicate(true)
	var records: Dictionary = candidate["records"]
	records["cosmetic_selections"] = selections.duplicate(true)
	candidate["records"] = records
	return _commit_profile(candidate)


# Replaces only achievement-owned data in one save. Essence, skills, crystals
# and non-achievement reward claims are untouched.
func reset_achievement_data(
	fresh_achievement_state: Dictionary,
	remaining_selections: Dictionary
) -> bool:
	if not _profile_writable:
		_set_save_status(false, "Cannot reset achievements without a writable profile.")
		return false

	var candidate := _profile.duplicate(true)
	var records: Dictionary = candidate["records"]
	records["achievement_state"] = fresh_achievement_state.duplicate(true)
	records["cosmetic_selections"] = remaining_selections.duplicate(true)
	candidate["records"] = records
	var kept_claims: Array = []
	for claim_id in candidate["reward_claims"]:
		if not String(claim_id).begins_with("achievement_"):
			kept_claims.append(claim_id)
	candidate["reward_claims"] = kept_claims
	return _commit_profile(candidate)


func _create_default_profile() -> Dictionary:
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"essence": 0,
		"crystal_shop_purchase_count": 0,
		"essence_points": 0,
		"essence_threshold": FIRST_ESSENCE_THRESHOLD,
		"crystals": [],
		"unlocked_crystal_ids": [],
		"purchased_skill_nodes": {
			"crystals": [],
			"economy": [],
			"elemental_mastery": [],
			"tower_enhancements": []
		},
		"records": {},
		"reward_claims": []
	}


func _read_profile_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_last_parse_error = "Could not open '%s' (error %d)." % [
			path,
			FileAccess.get_open_error()
		]
		return {}

	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		_last_parse_error = "Could not read '%s' (error %d)." % [path, read_error]
		return {}

	return _parse_profile_text(text, path)


func _parse_profile_text(text: String, source: String) -> Dictionary:
	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		_last_parse_error = (
			"Invalid JSON in '%s' at line %d: %s."
			% [source, json.get_error_line(), json.get_error_message()]
		)
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		_last_parse_error = "Profile root in '%s' must be a JSON object." % source
		return {}

	return _normalize_profile(json.data)


func _normalize_profile(raw: Dictionary) -> Dictionary:
	_last_parse_error = ""
	_profile_requires_migration_save = false
	if (
		not raw.has("schema_version")
		or not _is_integer_number(raw["schema_version"])
	):
		_last_parse_error = "schema_version is required and must be an integer."
		return {}

	var schema_version := int(raw["schema_version"])
	if schema_version < 0:
		_last_parse_error = "schema_version cannot be negative."
		return {}
	if schema_version > CURRENT_SCHEMA_VERSION:
		_last_parse_error = (
			"Save schema version %d is newer than supported version %d."
			% [schema_version, CURRENT_SCHEMA_VERSION]
		)
		return {}
	var migrated_legacy_fire_mastery_schema := schema_version < 3
	_profile_requires_migration_save = schema_version < CURRENT_SCHEMA_VERSION

	var migrated := raw.duplicate(true)
	while schema_version < CURRENT_SCHEMA_VERSION:
		match schema_version:
			0:
				migrated = _migrate_v0_to_v1(migrated)
				schema_version = 1
			1:
				migrated = _migrate_v1_to_v2(migrated)
				schema_version = 2
			2:
				migrated = _migrate_v2_to_v3(migrated)
				schema_version = 3
			3:
				migrated = _migrate_v3_to_v4(migrated)
				schema_version = 4
			_:
				_last_parse_error = "No migration exists from schema version %d." % schema_version
				return {}

	if not migrated.has("essence"):
		migrated["essence"] = 0
	if not _is_integer_number(migrated["essence"]):
		_last_parse_error = "essence must be an integer."
		return {}
	var essence_value := int(migrated["essence"])
	if essence_value < 0 or essence_value > MAX_ESSENCE:
		_last_parse_error = "essence is outside the supported balance limits."
		return {}

	if not migrated.has("crystal_shop_purchase_count"):
		migrated["crystal_shop_purchase_count"] = 0
		_profile_requires_migration_save = true
	if not _is_integer_number(migrated["crystal_shop_purchase_count"]):
		_last_parse_error = "crystal_shop_purchase_count must be an integer."
		return {}
	var crystal_shop_purchase_count := int(
		migrated["crystal_shop_purchase_count"]
	)
	if (
		crystal_shop_purchase_count < 0
		or crystal_shop_purchase_count > MAX_CRYSTAL_SHOP_PURCHASES
	):
		_last_parse_error = (
			"crystal_shop_purchase_count is outside the supported limits."
		)
		return {}

	# Profiles saved before the Essence point system have neither field.
	if not migrated.has("essence_threshold"):
		migrated["essence_threshold"] = FIRST_ESSENCE_THRESHOLD
	if not migrated.has("essence_points"):
		migrated["essence_points"] = 0
	if (
		not _is_integer_number(migrated["essence_threshold"])
		or not _is_integer_number(migrated["essence_points"])
	):
		_last_parse_error = "essence_points and essence_threshold must be integers."
		return {}
	var essence_threshold_value := int(migrated["essence_threshold"])
	var essence_points_value := int(migrated["essence_points"])
	if (
		essence_threshold_value < FIRST_ESSENCE_THRESHOLD
		or essence_threshold_value > MAX_ESSENCE_THRESHOLD
		or essence_points_value < 0
		or essence_points_value >= essence_threshold_value
	):
		_last_parse_error = (
			"essence_points must be between 0 and the current essence_threshold."
		)
		return {}

	if not migrated.has("crystals"):
		migrated["crystals"] = []
	if typeof(migrated["crystals"]) != TYPE_ARRAY:
		_last_parse_error = "crystals must be an array."
		return {}
	var crystals := _normalize_crystal_entries(migrated["crystals"])
	if not _last_parse_error.is_empty():
		return {}

	if not migrated.has("unlocked_crystal_ids"):
		migrated["unlocked_crystal_ids"] = []
	var unlocked_ids := _normalize_unlocked_ids(migrated["unlocked_crystal_ids"])
	if not _last_parse_error.is_empty():
		return {}

	if not migrated.has("purchased_skill_nodes"):
		migrated["purchased_skill_nodes"] = {}
	if typeof(migrated["purchased_skill_nodes"]) != TYPE_DICTIONARY:
		_last_parse_error = "purchased_skill_nodes must be an object."
		return {}
	var skill_nodes := _normalize_skill_nodes(migrated["purchased_skill_nodes"])
	if not _last_parse_error.is_empty():
		return {}

	if not migrated.has("records"):
		migrated["records"] = {}
	if typeof(migrated["records"]) != TYPE_DICTIONARY:
		_last_parse_error = "records must be an object."
		return {}
	if not _validate_reserved_dictionary(migrated["records"]):
		return {}

	if not migrated.has("reward_claims"):
		migrated["reward_claims"] = []
	var reward_claims := _normalize_string_array(
		migrated["reward_claims"],
		MAX_REWARD_CLAIMS,
		"reward_claims"
	)
	if not _last_parse_error.is_empty():
		return {}

	var owns_awakening_magic: bool = (
		skill_nodes["tower_enhancements"].has("A")
	)
	if not owns_awakening_magic:
		if not crystals.is_empty() or not unlocked_ids.is_empty():
			_profile_requires_migration_save = true
		crystals = []
		unlocked_ids = []
	elif not reward_claims.has(AWAKENING_RAPID_FIRE_REWARD_CLAIM):
		var reward_profile := {
			"crystals": crystals,
			"unlocked_crystal_ids": unlocked_ids,
			"reward_claims": reward_claims
		}
		if not _grant_awakening_rapid_fire_crystal(reward_profile):
			return {}
		crystals = reward_profile["crystals"]
		unlocked_ids = reward_profile["unlocked_crystal_ids"]
		reward_claims = reward_profile["reward_claims"]
		_profile_requires_migration_save = true

	if owns_awakening_magic:
		if not reward_claims.has(AWAKENING_KINETIC_REWARD_CLAIM):
			var reward_profile := {
				"crystals": crystals,
				"unlocked_crystal_ids": unlocked_ids,
				"reward_claims": reward_claims
			}
			if not _grant_awakening_kinetic_crystal(reward_profile):
				return {}
			crystals = reward_profile["crystals"]
			unlocked_ids = reward_profile["unlocked_crystal_ids"]
			reward_claims = reward_profile["reward_claims"]
			_profile_requires_migration_save = true
		elif not unlocked_ids.has("kinetic"):
			if unlocked_ids.size() >= MAX_UNLOCKED_CRYSTALS:
				_last_parse_error = (
					"unlocked_crystal_ids exceeds the supported collection limit."
				)
				return {}
			unlocked_ids.append("kinetic")
			_profile_requires_migration_save = true

		if migrated_legacy_fire_mastery_schema:
			var elemental_skills: Array = skill_nodes["elemental_mastery"]
			var had_legacy_fire_mastery := (
				elemental_skills.has("D") or elemental_skills.has("I")
			)
			if had_legacy_fire_mastery:
				if elemental_skills.has("D") and not elemental_skills.has("I"):
					elemental_skills.append("I")
					skill_nodes["elemental_mastery"] = elemental_skills
				var legacy_fire_reward_claim := "skill_crystal_reward_D"
				var fire_mastery_reward_claim := "skill_crystal_reward_I"
				var legacy_reward_was_claimed := reward_claims.has(
					legacy_fire_reward_claim
				)
				var already_owns_fire := false
				for crystal_entry in crystals:
					if (
						crystal_entry["crystal_id"] == "fire"
						and int(crystal_entry["level"]) == 1
					):
						already_owns_fire = true
						break
				if (
					not legacy_reward_was_claimed
					and not reward_claims.has(fire_mastery_reward_claim)
					and not already_owns_fire
				):
					var reward_profile := {
						"crystals": crystals,
						"unlocked_crystal_ids": unlocked_ids,
						"reward_claims": reward_claims
					}
					if not _grant_skill_crystal_reward(
						reward_profile,
						"fire",
						fire_mastery_reward_claim
					):
						return {}
					crystals = reward_profile["crystals"]
					unlocked_ids = reward_profile["unlocked_crystal_ids"]
					reward_claims = reward_profile["reward_claims"]
				elif not unlocked_ids.has("fire"):
					if unlocked_ids.size() >= MAX_UNLOCKED_CRYSTALS:
						_last_parse_error = (
							"unlocked_crystal_ids exceeds the supported collection limit."
						)
						return {}
					unlocked_ids.append("fire")
				if not reward_claims.has(fire_mastery_reward_claim):
					if reward_claims.size() >= MAX_REWARD_CLAIMS:
						_last_parse_error = (
							"reward_claims exceeds the supported collection limit."
						)
						return {}
					reward_claims.append(fire_mastery_reward_claim)
				_profile_requires_migration_save = true

		var skill_crystal_rewards := get_skill_crystal_rewards()
		for skill_id in skill_crystal_rewards:
			var definition := SKILL_CATALOG.get_skill_definition(
				StringName(skill_id)
			)
			var tree_id := String(definition["category"])
			if not skill_nodes[tree_id].has(skill_id):
				continue

			var reward_claim := "skill_crystal_reward_%s" % skill_id
			if reward_claims.has(reward_claim):
				continue
			var reward_crystal_id := String(skill_crystal_rewards[skill_id])
			var already_owns_reward_crystal := false
			for crystal_entry in crystals:
				if (
					crystal_entry["crystal_id"] == reward_crystal_id
					and int(crystal_entry["level"]) == 1
				):
					already_owns_reward_crystal = true
					break
			if already_owns_reward_crystal:
				if not unlocked_ids.has(reward_crystal_id):
					if unlocked_ids.size() >= MAX_UNLOCKED_CRYSTALS:
						_last_parse_error = (
							"unlocked_crystal_ids exceeds the supported collection limit."
						)
						return {}
					unlocked_ids.append(reward_crystal_id)
				if reward_claims.size() >= MAX_REWARD_CLAIMS:
					_last_parse_error = "reward_claims exceeds the supported collection limit."
					return {}
				reward_claims.append(reward_claim)
				_profile_requires_migration_save = true
				continue
			var reward_profile := {
				"crystals": crystals,
				"unlocked_crystal_ids": unlocked_ids,
				"reward_claims": reward_claims
			}
			if not _grant_skill_crystal_reward(
				reward_profile,
				reward_crystal_id,
				reward_claim
			):
				return {}
			crystals = reward_profile["crystals"]
			unlocked_ids = reward_profile["unlocked_crystal_ids"]
			reward_claims = reward_profile["reward_claims"]
			_profile_requires_migration_save = true

	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"essence": essence_value,
		"crystal_shop_purchase_count": crystal_shop_purchase_count,
		"essence_points": essence_points_value,
		"essence_threshold": essence_threshold_value,
		"crystals": crystals,
		"unlocked_crystal_ids": unlocked_ids,
		"purchased_skill_nodes": skill_nodes,
		"records": migrated["records"].duplicate(true),
		"reward_claims": reward_claims
	}


func _migrate_v0_to_v1(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	migrated["schema_version"] = 1
	return migrated


func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	migrated["schema_version"] = 2
	return migrated


func _migrate_v2_to_v3(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	migrated["schema_version"] = 3
	return migrated


func _migrate_v3_to_v4(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	migrated["schema_version"] = 4
	return migrated


func _grant_awakening_rapid_fire_crystal(candidate: Dictionary) -> bool:
	var crystals: Array = candidate["crystals"]
	var has_level_one_rapid_fire := false
	for entry in crystals:
		if entry["crystal_id"] == "rapid_fire" and int(entry["level"]) == 1:
			has_level_one_rapid_fire = true
			break
	if not has_level_one_rapid_fire:
		if crystals.size() >= MAX_CRYSTAL_ENTRIES:
			_last_parse_error = "Crystal inventory has reached the supported entry limit."
			return false
		crystals.append({
			"crystal_id": "rapid_fire",
			"level": 1,
			"quantity": 1
		})
	candidate["crystals"] = crystals

	var unlocked_ids: Array = candidate["unlocked_crystal_ids"]
	if not unlocked_ids.has("rapid_fire"):
		unlocked_ids.append("rapid_fire")
	candidate["unlocked_crystal_ids"] = unlocked_ids

	var reward_claims: Array = candidate["reward_claims"]
	if not reward_claims.has(AWAKENING_RAPID_FIRE_REWARD_CLAIM):
		if reward_claims.size() >= MAX_REWARD_CLAIMS:
			_last_parse_error = "reward_claims exceeds the supported collection limit."
			return false
		reward_claims.append(AWAKENING_RAPID_FIRE_REWARD_CLAIM)
	candidate["reward_claims"] = reward_claims
	return true


func _grant_awakening_kinetic_crystal(candidate: Dictionary) -> bool:
	var crystals: Array = candidate["crystals"]
	var has_level_one_kinetic := false
	for entry in crystals:
		if entry["crystal_id"] == "kinetic" and int(entry["level"]) == 1:
			has_level_one_kinetic = true
			break
	if not has_level_one_kinetic:
		if crystals.size() >= MAX_CRYSTAL_ENTRIES:
			_last_parse_error = "Crystal inventory has reached the supported entry limit."
			return false
		crystals.append({
			"crystal_id": "kinetic",
			"level": 1,
			"quantity": 1
		})
	candidate["crystals"] = crystals

	var unlocked_ids: Array = candidate["unlocked_crystal_ids"]
	if not unlocked_ids.has("kinetic"):
		if unlocked_ids.size() >= MAX_UNLOCKED_CRYSTALS:
			_last_parse_error = (
				"unlocked_crystal_ids exceeds the supported collection limit."
			)
			return false
		unlocked_ids.append("kinetic")
	candidate["unlocked_crystal_ids"] = unlocked_ids

	var reward_claims: Array = candidate["reward_claims"]
	if not reward_claims.has(AWAKENING_KINETIC_REWARD_CLAIM):
		if reward_claims.size() >= MAX_REWARD_CLAIMS:
			_last_parse_error = "reward_claims exceeds the supported collection limit."
			return false
		reward_claims.append(AWAKENING_KINETIC_REWARD_CLAIM)
	candidate["reward_claims"] = reward_claims
	return true


func _grant_skill_crystal_reward(
	candidate: Dictionary,
	crystal_id: String,
	reward_claim: String
) -> bool:
	if not CRYSTAL_CATALOG.has(crystal_id):
		_last_parse_error = "Unknown skill reward crystal ID '%s'." % crystal_id
		return false

	var crystals: Array = candidate["crystals"]
	var found_index := -1
	for index in range(crystals.size()):
		var entry: Dictionary = crystals[index]
		if entry["crystal_id"] == crystal_id and int(entry["level"]) == 1:
			found_index = index
			break

	if found_index >= 0:
		var entry: Dictionary = crystals[found_index]
		if int(entry["quantity"]) >= MAX_CRYSTAL_QUANTITY:
			_last_parse_error = "Skill reward would exceed the crystal quantity limit."
			return false
		entry["quantity"] = int(entry["quantity"]) + 1
		crystals[found_index] = entry
	elif crystals.size() >= MAX_CRYSTAL_ENTRIES:
		_last_parse_error = "Crystal inventory has reached the supported entry limit."
		return false
	else:
		crystals.append({
			"crystal_id": crystal_id,
			"level": 1,
			"quantity": 1
		})

	var unlocked_ids: Array = candidate["unlocked_crystal_ids"]
	if not unlocked_ids.has(crystal_id):
		unlocked_ids.append(crystal_id)
	candidate["crystals"] = crystals
	candidate["unlocked_crystal_ids"] = unlocked_ids

	var reward_claims: Array = candidate["reward_claims"]
	if reward_claims.has(reward_claim):
		return true
	if reward_claims.size() >= MAX_REWARD_CLAIMS:
		_last_parse_error = "reward_claims exceeds the supported collection limit."
		return false
	reward_claims.append(reward_claim)
	candidate["reward_claims"] = reward_claims
	return true


# A claim alone is not proof of ownership: a reset or edited save can leave the
# claim behind without the crystal, which would block re-granting forever.
func _owns_crystal_any_level(crystal_id: String) -> bool:
	for entry in _profile.get("crystals", []):
		if entry["crystal_id"] == crystal_id and int(entry["quantity"]) > 0:
			return true
	return false


func _normalize_crystal_entries(raw_entries: Array) -> Array:
	if raw_entries.size() > MAX_CRYSTAL_ENTRIES * 10:
		_last_parse_error = "crystals contains too many entries."
		return []

	var normalized: Array = []
	var entries_by_key: Dictionary = {}
	for raw_entry in raw_entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			_last_parse_error = "Each crystal entry must be an object."
			return []
		if (
			typeof(raw_entry.get("crystal_id")) != TYPE_STRING
			or not _is_integer_number(raw_entry.get("level"))
			or not _is_integer_number(raw_entry.get("quantity"))
		):
			_last_parse_error = "Crystal entries require string ID and integer level/quantity."
			return []

		var crystal_id: String = raw_entry["crystal_id"]
		var level := int(raw_entry["level"])
		var quantity := int(raw_entry["quantity"])
		if not CRYSTAL_CATALOG.has(crystal_id):
			_last_parse_error = "Unknown crystal ID '%s'." % crystal_id
			return []
		if level < 1 or level > MAX_CRYSTAL_LEVEL:
			_last_parse_error = "Crystal level is outside the supported limits."
			return []
		if quantity < 0 or quantity > MAX_CRYSTAL_QUANTITY:
			_last_parse_error = "Crystal quantity is outside the supported limits."
			return []
		if quantity == 0:
			continue

		var key := "%s:%d" % [crystal_id, level]
		if entries_by_key.has(key):
			var existing: Dictionary = entries_by_key[key]
			var old_quantity: int = existing["quantity"]
			if old_quantity > MAX_CRYSTAL_QUANTITY - quantity:
				_last_parse_error = "Duplicate crystal quantities exceed the supported limit."
				return []
			existing["quantity"] = old_quantity + quantity
			entries_by_key[key] = existing
		else:
			entries_by_key[key] = {
				"crystal_id": crystal_id,
				"level": level,
				"quantity": quantity
			}

	if entries_by_key.size() > MAX_CRYSTAL_ENTRIES:
		_last_parse_error = "crystals exceeds the supported number of unique entries."
		return []
	for entry in entries_by_key.values():
		normalized.append(entry)
	return normalized


func _normalize_unlocked_ids(raw_ids: Variant) -> Array:
	if typeof(raw_ids) != TYPE_ARRAY:
		_last_parse_error = "unlocked_crystal_ids must be an array."
		return []

	var ids := _normalize_string_array(
		raw_ids,
		MAX_UNLOCKED_CRYSTALS,
		"unlocked_crystal_ids"
	)
	if ids.is_empty() and not raw_ids.is_empty():
		return []

	for crystal_id in ids:
		if not CRYSTAL_CATALOG.has(crystal_id):
			_last_parse_error = "Unknown unlocked crystal ID '%s'." % crystal_id
			return []
	return ids


func _normalize_skill_nodes(raw_nodes: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for tree_name in SKILL_TREE_KEYS:
		var node_ids: Variant = raw_nodes.get(tree_name, [])
		if typeof(node_ids) != TYPE_ARRAY:
			_last_parse_error = (
				"purchased_skill_nodes.%s must be an array." % tree_name
			)
			return {}
		var normalized_ids := _normalize_string_array(
			node_ids,
			MAX_SKILL_NODES_PER_TREE,
			"purchased_skill_nodes.%s" % tree_name
		)
		if not _last_parse_error.is_empty():
			return {}
		normalized[tree_name] = normalized_ids
	return normalized


func _is_integer_number(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value) and floorf(value) == value
	return false


func _normalize_string_array(
	raw_values: Variant,
	maximum_size: int,
	field_name: String
) -> Array:
	if typeof(raw_values) != TYPE_ARRAY:
		_last_parse_error = "%s must be an array." % field_name
		return []
	if raw_values.size() > maximum_size:
		_last_parse_error = "%s exceeds the supported collection limit." % field_name
		return []

	var result: Array = []
	var seen: Dictionary = {}
	for value in raw_values:
		if typeof(value) != TYPE_STRING or value.is_empty():
			_last_parse_error = "%s entries must be non-empty strings." % field_name
			return []
		if value.length() > 128:
			_last_parse_error = "%s contains an overlong identifier." % field_name
			return []
		if not seen.has(value):
			seen[value] = true
			result.append(value)
	return result


func _validate_reserved_dictionary(data: Dictionary) -> bool:
	if data.size() > MAX_RECORD_KEYS:
		_last_parse_error = "records exceeds the supported key limit."
		return false

	for key in data:
		if typeof(key) != TYPE_STRING or key.is_empty() or key.length() > 128:
			_last_parse_error = "records keys must be short, non-empty strings."
			return false
		if not _is_json_value(data[key], 0):
			_last_parse_error = "records contains unsupported or excessive data."
			return false
	return true


func _is_json_value(value: Variant, depth: int) -> bool:
	if depth > MAX_RESERVED_DATA_DEPTH:
		return false

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING:
			return value.length() <= MAX_PROFILE_STRING_LENGTH
		TYPE_ARRAY:
			if value.size() > MAX_RECORD_KEYS:
				return false
			for child in value:
				if not _is_json_value(child, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			if value.size() > MAX_RECORD_KEYS:
				return false
			for key in value:
				if typeof(key) != TYPE_STRING or key.length() > 128:
					return false
				if not _is_json_value(value[key], depth + 1):
					return false
			return true
	return false


func _write_profile_file(profile: Dictionary, preserve_valid_primary: bool) -> bool:
	if not _ensure_storage_directory():
		return false

	var profile_path := _get_profile_path(PROFILE_FILE_NAME)
	var temp_path := _get_profile_path(PROFILE_TEMP_FILE_NAME)
	var backup_path := _get_profile_path(PROFILE_BACKUP_FILE_NAME)

	var json_text := JSON.stringify(profile, "\t")
	if not _write_text_file(temp_path, json_text):
		return false

	var verified := _read_profile_file(temp_path)
	if verified.is_empty() or int(verified["schema_version"]) != CURRENT_SCHEMA_VERSION:
		_remove_if_exists(temp_path)
		_set_save_status(
			false,
			"Temporary profile failed validation: " + _last_parse_error
		)
		return false

	if preserve_valid_primary and FileAccess.file_exists(profile_path):
		var current_primary := _read_profile_file(profile_path)
		if not current_primary.is_empty():
			if not _write_backup_from_primary():
				_remove_if_exists(temp_path)
				return false

	if FileAccess.file_exists(profile_path):
		var remove_error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(profile_path)
		)
		if remove_error != OK:
			_remove_if_exists(temp_path)
			_set_save_status(
				false,
				"Could not replace the primary profile (error %d)." % remove_error
			)
			return false

	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(profile_path)
	)
	if rename_error != OK:
		_set_save_status(
			false,
			"Could not install the verified profile save (error %d)." % rename_error
		)
		return false

	_set_save_status(true, "Player profile saved.")
	return true


func _write_backup_from_primary() -> bool:
	var profile_path := _get_profile_path(PROFILE_FILE_NAME)
	var backup_path := _get_profile_path(PROFILE_BACKUP_FILE_NAME)
	var backup_temp_path := _get_profile_path(PROFILE_BACKUP_TEMP_FILE_NAME)
	var primary_text := _read_text_file(profile_path)
	if primary_text.is_empty():
		_set_save_status(false, "Could not read the current primary profile for backup.")
		return false
	if _parse_profile_text(primary_text, profile_path).is_empty():
		_set_save_status(
			false,
			"Refusing to replace the backup with an invalid primary profile."
		)
		return false
	if not _write_text_file(backup_temp_path, primary_text):
		return false
	if _parse_profile_text(
		_read_text_file(backup_temp_path),
		backup_temp_path
	).is_empty():
		_remove_if_exists(backup_temp_path)
		_set_save_status(false, "Temporary backup failed validation.")
		return false

	if FileAccess.file_exists(backup_path):
		var remove_error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(backup_path)
		)
		if remove_error != OK:
			_remove_if_exists(backup_temp_path)
			_set_save_status(
				false,
				"Could not rotate the previous backup (error %d)." % remove_error
			)
			return false

	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(backup_temp_path),
		ProjectSettings.globalize_path(backup_path)
	)
	if rename_error != OK:
		_set_save_status(
			false,
			"Could not install the verified backup (error %d)." % rename_error
		)
		return false
	return true


func _write_text_file(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_save_status(
			false,
			"Could not open '%s' for writing (error %d)." % [
				path,
				FileAccess.get_open_error()
			]
		)
		return false

	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_set_save_status(
			false,
			"Could not write '%s' (error %d)." % [path, write_error]
		)
		return false
	return true


func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _get_profile_path(file_name: String) -> String:
	return profile_storage_directory.path_join(file_name)


func _ensure_storage_directory() -> bool:
	var absolute_path := ProjectSettings.globalize_path(profile_storage_directory)
	if DirAccess.dir_exists_absolute(absolute_path):
		return true

	var error := DirAccess.make_dir_recursive_absolute(absolute_path)
	if error != OK:
		_set_save_status(
			false,
			"Could not create profile directory '%s' (error %d)." % [
				profile_storage_directory,
				error
			]
		)
		return false
	return true


func _set_save_status(success: bool, message: String) -> void:
	last_save_success = success
	last_save_message = message
	save_status_changed.emit(success, message)
