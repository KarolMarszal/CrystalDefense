extends GdUnitTestSuite

const PROFILE_MANAGER_SCRIPT: Script = preload(
	"res://managers/CrystalInventoryManager.gd"
)
const PROFILE_FILE_NAME: String = "player_profile.json"
const BACKUP_FILE_NAME: String = "player_profile.bak"
const RAPID_FIRE: CrystalData = preload("res://crystals/RapidFireCrystal.tres")
const SLOW: CrystalData = preload("res://crystals/SlowCrystal.tres")
const BLEED: CrystalData = preload("res://crystals/BleedCrystal.tres")

var _storage_directory: String
var _manager
var _starting_run_gold: int


func before_test() -> void:
	_starting_run_gold = GoldManager.run_gold
	_storage_directory = "user://gdunit-profile-tests/%d-%d" % [
		Time.get_ticks_usec(),
		randi()
	]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_storage_directory)
	)
	_manager = _create_manager()


func after_test() -> void:
	if is_instance_valid(_manager):
		_manager.free()
	_manager = null

	for file_name in [
		PROFILE_FILE_NAME,
		"player_profile.tmp",
		BACKUP_FILE_NAME,
		"player_profile.bak.tmp"
	]:
		_remove_test_file(_storage_directory.path_join(file_name))

	var absolute_directory := ProjectSettings.globalize_path(_storage_directory)
	DirAccess.remove_absolute(absolute_directory)
	GoldManager.end_run()
	if _starting_run_gold > 0:
		GoldManager.add_gold(_starting_run_gold)


func after() -> void:
	var test_root := ProjectSettings.globalize_path("user://gdunit-profile-tests")
	DirAccess.remove_absolute(test_root)


func test_first_launch_creates_an_empty_default_profile_in_test_storage() -> void:
	var profile: Dictionary = _manager.get_profile_data()

	assert_int(profile["schema_version"]).is_equal(1)
	assert_int(profile["essence"]).is_equal(0)
	assert_int(profile["crystals"].size()).is_equal(0)
	assert_int(profile["unlocked_crystal_ids"].size()).is_equal(0)
	assert_int(profile["purchased_skill_nodes"]["crystals"].size()).is_equal(0)
	assert_bool(profile.has("records")).is_true()
	assert_bool(profile.has("reward_claims")).is_true()
	assert_bool(FileAccess.file_exists(_profile_path())).is_true()
	assert_bool(_manager.last_load_success).is_true()


func test_profile_round_trip_preserves_currency_crystals_unlocks_skills_and_reserved_data() -> void:
	var fixture := _default_profile_fixture()
	fixture["essence"] = 275
	fixture["crystals"] = [
		{"crystal_id": "rapid_fire", "level": 2, "quantity": 3},
		{"crystal_id": "slow", "level": 1, "quantity": 1},
		{"crystal_id": "bleed", "level": 4, "quantity": 2}
	]
	fixture["unlocked_crystal_ids"] = ["rapid_fire", "bleed"]
	fixture["purchased_skill_nodes"] = {
		"crystals": ["crystal_node_1"],
		"economy": ["economy_node_2"],
		"elemental_mastery": ["element_node_3"],
		"tower_enhancements": ["tower_node_4"]
	}
	fixture["records"] = {"best_wave": 12}
	fixture["reward_claims"] = ["first_clear"]
	_write_json(_profile_path(), fixture)

	assert_bool(_manager.load_profile()).is_true()
	assert_bool(_manager.save_profile()).is_true()
	_recreate_manager()

	var profile: Dictionary = _manager.get_profile_data()
	assert_int(profile["essence"]).is_equal(275)
	assert_int(profile["crystals"].size()).is_equal(3)
	assert_bool(_contains_crystal(profile["crystals"], "rapid_fire", 2, 3)).is_true()
	assert_bool(_contains_crystal(profile["crystals"], "slow", 1, 1)).is_true()
	assert_bool(_contains_crystal(profile["crystals"], "bleed", 4, 2)).is_true()
	assert_bool(profile["unlocked_crystal_ids"].has("rapid_fire")).is_true()
	assert_bool(profile["unlocked_crystal_ids"].has("bleed")).is_true()
	assert_bool(
		profile["purchased_skill_nodes"]["crystals"].has("crystal_node_1")
	).is_true()
	assert_bool(
		profile["purchased_skill_nodes"]["economy"].has("economy_node_2")
	).is_true()
	assert_bool(
		profile["purchased_skill_nodes"]["elemental_mastery"].has("element_node_3")
	).is_true()
	assert_bool(
		profile["purchased_skill_nodes"]["tower_enhancements"].has("tower_node_4")
	).is_true()
	assert_int(int(profile["records"]["best_wave"])).is_equal(12)
	assert_bool(profile["reward_claims"].has("first_clear")).is_true()


func test_crystal_api_saves_multiple_types_levels_and_quantities() -> void:
	assert_bool(_manager.add_crystal(RAPID_FIRE, 2, 3)).is_true()
	assert_bool(_manager.add_crystal(SLOW, 1, 1)).is_true()
	assert_bool(_manager.add_crystal(BLEED, 4, 2)).is_true()
	assert_int(_manager.get_owned_crystals().size()).is_equal(3)

	_recreate_manager()

	var owned: Array[Dictionary] = _manager.get_owned_crystals()
	assert_int(owned.size()).is_equal(3)
	assert_bool(_contains_owned_crystal(owned, "rapid_fire", 2, 3)).is_true()
	assert_bool(_contains_owned_crystal(owned, "slow", 1, 1)).is_true()
	assert_bool(_contains_owned_crystal(owned, "bleed", 4, 2)).is_true()


func test_empty_inventory_survives_save_and_reload() -> void:
	assert_bool(_manager.add_essence(45)).is_true()
	assert_bool(_manager.save_profile()).is_true()
	_recreate_manager()

	assert_int(_manager.get_essence_balance()).is_equal(45)
	assert_int(_manager.get_profile_data()["crystals"].size()).is_equal(0)


func test_multiple_saves_reload_the_latest_valid_profile() -> void:
	assert_bool(_manager.add_essence(10)).is_true()
	assert_bool(_manager.add_essence(25)).is_true()
	assert_bool(_manager.add_essence(40)).is_true()
	_recreate_manager()

	assert_int(_manager.get_essence_balance()).is_equal(75)
	assert_bool(_manager.last_load_success).is_true()


func test_v0_profile_and_missing_optional_fields_are_migrated_with_defaults() -> void:
	_write_json(_profile_path(), {
		"schema_version": 0,
		"essence": 18
	})

	assert_bool(_manager.load_profile()).is_true()

	var profile: Dictionary = _manager.get_profile_data()
	assert_int(profile["schema_version"]).is_equal(1)
	assert_int(profile["essence"]).is_equal(18)
	assert_int(profile["crystals"].size()).is_equal(0)
	assert_int(profile["unlocked_crystal_ids"].size()).is_equal(0)
	assert_bool(profile.has("records")).is_true()
	assert_bool(profile.has("reward_claims")).is_true()
	assert_bool(_manager.last_save_success).is_true()


func test_duplicate_crystal_entries_are_merged_by_id_and_level() -> void:
	var fixture := _default_profile_fixture()
	fixture["crystals"] = [
		{"crystal_id": "rapid_fire", "level": 3, "quantity": 2},
		{"crystal_id": "rapid_fire", "level": 3, "quantity": 4}
	]
	_write_json(_profile_path(), fixture)

	assert_bool(_manager.load_profile()).is_true()

	var crystals: Array = _manager.get_profile_data()["crystals"]
	assert_int(crystals.size()).is_equal(1)
	assert_bool(_contains_crystal(crystals, "rapid_fire", 3, 6)).is_true()


func test_invalid_json_and_profile_values_are_rejected_by_validation() -> void:
	var invalid_json: Dictionary = _manager._parse_profile_text(
		"{",
		"isolated-test"
	)
	assert_bool(invalid_json.is_empty()).is_true()
	assert_bool(not _manager._last_parse_error.is_empty()).is_true()

	var invalid_profiles: Array[Dictionary] = []
	var wrong_essence_type := _default_profile_fixture()
	wrong_essence_type["essence"] = "10"
	invalid_profiles.append(wrong_essence_type)
	var negative_essence := _default_profile_fixture()
	negative_essence["essence"] = -1
	invalid_profiles.append(negative_essence)
	var wrong_crystals_type := _default_profile_fixture()
	wrong_crystals_type["crystals"] = {}
	invalid_profiles.append(wrong_crystals_type)
	var negative_quantity := _default_profile_fixture()
	negative_quantity["crystals"] = [
		{"crystal_id": "slow", "level": 1, "quantity": -1}
	]
	invalid_profiles.append(negative_quantity)
	var invalid_level := _default_profile_fixture()
	invalid_level["crystals"] = [
		{"crystal_id": "slow", "level": 0, "quantity": 1}
	]
	invalid_profiles.append(invalid_level)
	var unknown_crystal := _default_profile_fixture()
	unknown_crystal["crystals"] = [
		{"crystal_id": "unknown", "level": 1, "quantity": 1}
	]
	invalid_profiles.append(unknown_crystal)
	var unknown_unlock := _default_profile_fixture()
	unknown_unlock["unlocked_crystal_ids"] = ["unknown"]
	invalid_profiles.append(unknown_unlock)
	var wrong_skill_tree_type := _default_profile_fixture()
	wrong_skill_tree_type["purchased_skill_nodes"] = {"crystals": "not-an-array"}
	invalid_profiles.append(wrong_skill_tree_type)

	for invalid_profile in invalid_profiles:
		var normalized: Dictionary = _manager._normalize_profile(invalid_profile)
		assert_bool(normalized.is_empty()).is_true()
		assert_bool(not _manager._last_parse_error.is_empty()).is_true()


func test_essence_operations_reject_invalid_amounts_and_prevent_negative_balance() -> void:
	assert_bool(_manager.add_essence(0)).is_false()
	assert_bool(_manager.add_essence(-1)).is_false()
	assert_bool(_manager.spend_essence(1)).is_false()
	assert_bool(_manager.add_essence(80)).is_true()
	assert_bool(_manager.spend_essence(81)).is_false()
	assert_bool(_manager.spend_essence(30)).is_true()

	assert_int(_manager.get_essence_balance()).is_equal(50)
	assert_bool(_manager.add_essence(0)).is_false()


func test_profile_change_signal_emits_an_updated_profile_snapshot() -> void:
	var emitted_profiles: Array[Dictionary] = []
	_manager.profile_changed.connect(
		func(profile: Dictionary) -> void:
			emitted_profiles.append(profile)
	)

	assert_bool(_manager.add_essence(12)).is_true()

	assert_int(emitted_profiles.size()).is_equal(1)
	assert_int(emitted_profiles[0]["essence"]).is_equal(12)


func test_corrupt_primary_recovers_from_the_last_valid_backup() -> void:
	assert_bool(_manager.add_essence(100)).is_true()
	assert_bool(_manager.add_essence(50)).is_true()
	_write_text(_profile_path(), "{corrupt")

	assert_bool(_manager.load_profile()).is_true()
	assert_int(_manager.get_essence_balance()).is_equal(100)
	assert_bool(_manager.last_load_message.contains("backup")).is_true()
	assert_bool(_manager.last_save_success).is_true()
	assert_int(int(_read_json(_profile_path())["essence"])).is_equal(100)


func test_future_schema_is_preserved_and_loaded_backup_is_read_only() -> void:
	var backup_profile := _default_profile_fixture()
	backup_profile["essence"] = 33
	_write_json(_backup_path(), backup_profile)
	var future_profile := _default_profile_fixture()
	future_profile["schema_version"] = 99
	future_profile["future_field"] = "keep me"
	_write_json(_profile_path(), future_profile)
	var original_future_text := _read_text(_profile_path())

	assert_bool(_manager.load_profile()).is_true()

	assert_int(_manager.get_essence_balance()).is_equal(33)
	assert_bool(_manager.last_load_message.contains("newer schema")).is_true()
	assert_bool(_manager.save_profile()).is_false()
	assert_str(_read_text(_profile_path())).is_equal(original_future_text)
	assert_bool(not _manager.last_save_message.is_empty()).is_true()


func test_invalid_primary_load_is_reported_and_preserves_the_corrupt_file() -> void:
	var corrupt_text := "{invalid"
	_write_text(_profile_path(), corrupt_text)

	await assert_error(
		func() -> void:
			_manager.load_profile()
	).is_push_error(GdUnitArgumentMatchers.by_type(TYPE_STRING))

	assert_bool(_manager.last_load_success).is_false()
	assert_bool(_manager.last_load_message.contains("Primary save is invalid")).is_true()
	assert_str(_read_text(_profile_path())).is_equal(corrupt_text)
	assert_bool(_manager.save_profile()).is_false()


func test_failed_save_reports_failure_without_changing_memory_profile() -> void:
	var blocked_path := _storage_directory.path_join("not-a-directory")
	_write_text(blocked_path, "file occupies the intended directory path")
	_manager.profile_storage_directory = blocked_path

	assert_bool(_manager.add_essence(10)).is_false()

	assert_int(_manager.get_essence_balance()).is_equal(0)
	assert_bool(_manager.last_save_success).is_false()
	assert_bool(not _manager.last_save_message.is_empty()).is_true()


func test_run_gold_is_not_part_of_the_persistent_profile_or_its_save() -> void:
	var before: Dictionary = _manager.get_profile_data()
	var saved_before := _read_text(_profile_path())
	var gold_before := GoldManager.run_gold
	GoldManager.add_gold(31)
	assert_bool(_manager.save_profile()).is_true()

	var after: Dictionary = _manager.get_profile_data()
	assert_bool(after.has("gold")).is_false()
	assert_bool(after == before).is_true()
	assert_str(_read_text(_profile_path())).is_equal(saved_before)
	assert_int(GoldManager.run_gold).is_equal(gold_before + 31)


func _create_manager():
	var instance = PROFILE_MANAGER_SCRIPT.new()
	instance.profile_storage_directory = _storage_directory
	add_child(instance)
	return instance


func _recreate_manager() -> void:
	_manager.free()
	_manager = _create_manager()


func _default_profile_fixture() -> Dictionary:
	return {
		"schema_version": 1,
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


func _contains_crystal(
	entries: Array,
	crystal_id: String,
	level: int,
	quantity: int
) -> bool:
	for entry in entries:
		if (
			entry["crystal_id"] == crystal_id
			and entry["level"] == level
			and entry["quantity"] == quantity
		):
			return true
	return false


func _contains_owned_crystal(
	entries: Array[Dictionary],
	crystal_id: String,
	level: int,
	quantity: int
) -> bool:
	for entry in entries:
		var definition := entry["definition"] as CrystalData
		if (
			String(definition.crystal_id) == crystal_id
			and entry["level"] == level
			and entry["quantity"] == quantity
		):
			return true
	return false


func _profile_path() -> String:
	return _storage_directory.path_join(PROFILE_FILE_NAME)


func _backup_path() -> String:
	return _storage_directory.path_join(BACKUP_FILE_NAME)


func _write_json(path: String, value: Dictionary) -> void:
	_write_text(path, JSON.stringify(value))


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(value)
	file.close()


func _read_json(path: String) -> Dictionary:
	return JSON.parse_string(_read_text(path))


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_object(file).is_not_null()
	var value := file.get_as_text()
	file.close()
	return value


func _remove_test_file(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_path)
