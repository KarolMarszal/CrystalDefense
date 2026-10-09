extends Node

signal profile_changed(profile: Dictionary)
signal save_status_changed(success: bool, message: String)

const CURRENT_SCHEMA_VERSION: int = 1
const MAX_ESSENCE: int = 9007199254740991
const MAX_CRYSTAL_ENTRIES: int = 100
const MAX_CRYSTAL_LEVEL: int = 10000
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

const SKILL_TREE_KEYS: Array[String] = [
	"crystals",
	"economy",
	"elemental_mastery",
	"tower_enhancements"
]

const CRYSTAL_CATALOG: Dictionary = {
	"rapid_fire": preload("res://crystals/RapidFireCrystal.tres"),
	"slow": preload("res://crystals/SlowCrystal.tres"),
	"bleed": preload("res://crystals/BleedCrystal.tres")
}

@export var profile_storage_directory: String = "user://"

var _profile: Dictionary = {}
var _profile_writable: bool = false
var _last_parse_error: String = ""
var last_load_success: bool = false
var last_load_message: String = "Profile has not been loaded."
var last_save_success: bool = false
var last_save_message: String = "Profile has not been saved."

var essence: int:
	get:
		return int(_profile.get("essence", 0))


func _ready() -> void:
	load_profile()


func load_profile() -> bool:
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
		if int(primary["schema_version"]) != CURRENT_SCHEMA_VERSION:
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


func add_crystal(
	crystal: CrystalData,
	crystal_level: int = 1,
	quantity: int = 1
) -> bool:
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
	return _commit_profile(candidate)


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


func _commit_profile(candidate: Dictionary) -> bool:
	var normalized := _normalize_profile(candidate)
	if normalized.is_empty():
		_set_save_status(false, "Profile update failed validation: " + _last_parse_error)
		return false
	if not _write_profile_file(normalized, true):
		return false

	_profile = normalized
	profile_changed.emit(get_profile_data())
	return true


func _create_default_profile() -> Dictionary:
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"essence": 0,
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

	var migrated := raw.duplicate(true)
	while schema_version < CURRENT_SCHEMA_VERSION:
		match schema_version:
			0:
				migrated = _migrate_v0_to_v1(migrated)
				schema_version = 1
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

	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"essence": essence_value,
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
