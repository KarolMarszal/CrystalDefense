extends GdUnitTestSuite

const PROFILE_MANAGER_SCRIPT: Script = preload(
	"res://managers/CrystalInventoryManager.gd"
)
const SKILL_CATALOG = preload("res://managers/skill_tree_catalog.gd")
const SKILL_CANVAS = preload("res://ui/SkillTreeCanvas.gd")
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

	assert_int(profile["schema_version"]).is_equal(4)
	assert_int(profile["essence"]).is_equal(0)
	assert_int(_manager.get_essence_balance()).is_equal(0)
	assert_int(profile["crystals"].size()).is_equal(0)
	assert_int(profile["unlocked_crystal_ids"].size()).is_equal(0)
	assert_int(profile["purchased_skill_nodes"]["crystals"].size()).is_equal(0)
	assert_bool(profile.has("records")).is_true()
	assert_bool(profile.has("reward_claims")).is_true()
	assert_bool(FileAccess.file_exists(_profile_path())).is_true()
	assert_bool(_manager.last_load_success).is_true()


func test_profile_round_trip_preserves_currency_crystals_unlocks_skills_and_reserved_data() -> void:
	var fixture := _default_profile_fixture()
	fixture["schema_version"] = 4
	fixture["essence"] = 275
	fixture["crystals"] = [
		{"crystal_id": "rapid_fire", "level": 2, "quantity": 3},
		{"crystal_id": "kinetic", "level": 1, "quantity": 1},
		{"crystal_id": "slow", "level": 1, "quantity": 1},
		{"crystal_id": "bleed", "level": 4, "quantity": 2}
	]
	fixture["unlocked_crystal_ids"] = ["rapid_fire", "kinetic", "bleed"]
	fixture["purchased_skill_nodes"] = {
		"crystals": ["crystal_node_1"],
		"economy": ["economy_node_2"],
		"elemental_mastery": ["element_node_3"],
		"tower_enhancements": ["tower_node_4", "A"]
	}
	fixture["records"] = {"best_wave": 12}
	fixture["reward_claims"] = [
		"first_clear",
		"awakening_rapid_fire_crystal",
		"awakening_kinetic_crystal"
	]
	_write_json(_profile_path(), fixture)

	assert_bool(_manager.load_profile()).is_true()
	assert_bool(_manager.save_profile()).is_true()
	_recreate_manager()

	var profile: Dictionary = _manager.get_profile_data()
	assert_int(profile["essence"]).is_equal(275)
	assert_int(profile["crystals"].size()).is_equal(4)
	assert_bool(_contains_crystal(profile["crystals"], "rapid_fire", 2, 3)).is_true()
	assert_bool(_contains_crystal(profile["crystals"], "kinetic", 1, 1)).is_true()
	assert_bool(_contains_crystal(profile["crystals"], "slow", 1, 1)).is_true()
	assert_bool(_contains_crystal(profile["crystals"], "bleed", 4, 2)).is_true()
	assert_bool(profile["unlocked_crystal_ids"].has("rapid_fire")).is_true()
	assert_bool(profile["unlocked_crystal_ids"].has("bleed")).is_true()
	assert_bool(_manager.is_crystal_unlocked(&"rapid_fire")).is_true()
	assert_bool(_manager.is_crystal_unlocked(&"slow")).is_false()
	assert_bool(_manager.is_crystal_unlocked(&"unknown")).is_false()
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
	assert_bool(
		_manager.get_purchased_skill_node_ids(&"crystals").has("crystal_node_1")
	).is_true()
	assert_bool(
		_manager.get_purchased_skill_node_ids(&"economy").has("economy_node_2")
	).is_true()
	assert_bool(
		_manager.get_purchased_skill_node_ids(&"elemental_mastery").has("element_node_3")
	).is_true()
	assert_bool(
		_manager.get_purchased_skill_node_ids(&"tower_enhancements").has("tower_node_4")
	).is_true()
	assert_int(
		_manager.get_purchased_skill_node_ids(&"unknown").size()
	).is_equal(0)
	assert_int(int(profile["records"]["best_wave"])).is_equal(12)
	assert_bool(profile["reward_claims"].has("first_clear")).is_true()


func test_crystal_api_saves_multiple_types_levels_and_quantities() -> void:
	_purchase_awakening_magic()
	assert_bool(_manager.add_crystal(RAPID_FIRE, 2, 3)).is_true()
	assert_bool(_manager.add_crystal(SLOW, 1, 1)).is_true()
	assert_bool(_manager.add_crystal(BLEED, 4, 2)).is_true()
	assert_int(_manager.get_owned_crystals().size()).is_equal(5)

	_recreate_manager()

	var owned: Array[Dictionary] = _manager.get_owned_crystals()
	assert_int(owned.size()).is_equal(5)
	assert_bool(_contains_owned_crystal(owned, "rapid_fire", 1, 1)).is_true()
	assert_bool(_contains_owned_crystal(owned, "kinetic", 1, 1)).is_true()
	assert_bool(_contains_owned_crystal(owned, "rapid_fire", 2, 3)).is_true()
	assert_bool(_contains_owned_crystal(owned, "slow", 1, 1)).is_true()
	assert_bool(_contains_owned_crystal(owned, "bleed", 4, 2)).is_true()


func test_run_crystals_remain_temporary_across_profile_saves_and_reload() -> void:
	_purchase_awakening_magic()
	assert_bool(_manager.add_crystal(RAPID_FIRE, 3, 2)).is_true()
	_manager.start_run_inventory()
	assert_int(
		_manager.get_available_crystal_quantity(&"rapid_fire", 3)
	).is_equal(2)
	assert_bool(_manager.add_run_crystal(&"slow", 2, 4)).is_true()
	assert_bool(_manager.save_profile()).is_true()

	var saved_entries: Array = _manager.get_profile_data()["crystals"]
	assert_int(saved_entries.size()).is_equal(3)
	assert_bool(_contains_crystal(saved_entries, "rapid_fire", 1, 1)).is_true()
	assert_bool(_contains_crystal(saved_entries, "kinetic", 1, 1)).is_true()
	assert_bool(_contains_crystal(saved_entries, "rapid_fire", 3, 2)).is_true()
	assert_bool(_manager.get_profile_data().has("run_inventory")).is_false()

	_recreate_manager()
	assert_bool(_manager.is_run_inventory_active()).is_false()
	assert_int(_manager.get_available_crystals().size()).is_equal(0)
	assert_bool(
		_contains_owned_crystal(_manager.get_owned_crystals(), "rapid_fire", 3, 2)
	).is_true()
	_manager.start_run_inventory()
	assert_int(
		_manager.get_available_crystal_quantity(&"rapid_fire", 3)
	).is_equal(2)
	assert_int(_manager.get_available_crystal_quantity(&"slow", 2)).is_equal(0)
	_manager.end_run_inventory()


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
	assert_int(profile["schema_version"]).is_equal(4)
	assert_int(profile["essence"]).is_equal(18)
	assert_int(profile["crystals"].size()).is_equal(0)
	assert_int(profile["unlocked_crystal_ids"].size()).is_equal(0)
	assert_bool(profile.has("records")).is_true()
	assert_bool(profile.has("reward_claims")).is_true()
	assert_bool(_manager.last_save_success).is_true()


func test_legacy_profile_without_skill_a_removes_saved_test_crystals() -> void:
	var fixture := _default_profile_fixture()
	fixture["schema_version"] = 1
	fixture["crystals"] = [
		{"crystal_id": "rapid_fire", "level": 1, "quantity": 3},
		{"crystal_id": "bleed", "level": 1, "quantity": 1},
		{"crystal_id": "slow", "level": 1, "quantity": 1}
	]
	fixture["unlocked_crystal_ids"] = ["rapid_fire", "bleed", "slow"]
	_write_json(_profile_path(), fixture)

	assert_bool(_manager.load_profile()).is_true()
	assert_int(_manager.get_owned_crystals().size()).is_equal(0)
	assert_int(_manager.get_profile_data()["unlocked_crystal_ids"].size()).is_equal(0)
	assert_int(int(_read_json(_profile_path())["schema_version"])).is_equal(4)
	assert_int(_read_json(_profile_path())["crystals"].size()).is_equal(0)

	_recreate_manager()
	assert_int(_manager.get_owned_crystals().size()).is_equal(0)
	assert_bool(_manager.is_crystal_inventory_unlocked()).is_false()
	_manager.start_run_inventory()
	assert_int(_manager.get_available_crystals().size()).is_equal(0)


func test_legacy_profile_with_skill_a_receives_kinetic_and_rapid_fire_once() -> void:
	var fixture := _default_profile_fixture()
	fixture["schema_version"] = 1
	fixture["purchased_skill_nodes"]["tower_enhancements"] = ["A"]
	_write_json(_profile_path(), fixture)

	assert_bool(_manager.load_profile()).is_true()
	assert_bool(_manager.is_crystal_inventory_unlocked()).is_true()
	assert_int(_manager.get_owned_crystals().size()).is_equal(2)
	assert_bool(
		_contains_owned_crystal(_manager.get_owned_crystals(), "rapid_fire", 1, 1)
	).is_true()
	assert_bool(
		_contains_owned_crystal(_manager.get_owned_crystals(), "kinetic", 1, 1)
	).is_true()

	_recreate_manager()
	assert_bool(_manager.load_profile()).is_true()
	_manager.start_run_inventory()
	assert_int(
		_manager.get_available_crystal_quantity(&"rapid_fire", 1)
	).is_equal(1)
	assert_int(
		_manager.get_available_crystal_quantity(&"kinetic", 1)
	).is_equal(1)
	_manager.start_run_inventory()
	assert_int(
		_manager.get_available_crystal_quantity(&"rapid_fire", 1)
	).is_equal(1)
	assert_int(
		_manager.get_available_crystal_quantity(&"kinetic", 1)
	).is_equal(1)


func test_v3_awakening_migration_adds_kinetic_without_duplicating_rapid_fire() -> void:
	var fixture := _default_profile_fixture()
	fixture["schema_version"] = 3
	fixture["purchased_skill_nodes"]["tower_enhancements"] = ["A"]
	fixture["purchased_skill_nodes"]["elemental_mastery"] = ["D", "I"]
	fixture["crystals"] = [
		{"crystal_id": "rapid_fire", "level": 1, "quantity": 1},
		{"crystal_id": "fire", "level": 1, "quantity": 1}
	]
	fixture["unlocked_crystal_ids"] = ["rapid_fire", "fire"]
	fixture["reward_claims"] = ["awakening_rapid_fire_crystal"]
	_write_json(_profile_path(), fixture)

	assert_bool(_manager.load_profile()).is_true()
	var owned: Array[Dictionary] = _manager.get_owned_crystals()
	assert_int(owned.size()).is_equal(3)
	assert_bool(_contains_owned_crystal(owned, "rapid_fire", 1, 1)).is_true()
	assert_bool(_contains_owned_crystal(owned, "kinetic", 1, 1)).is_true()
	assert_bool(_contains_owned_crystal(owned, "fire", 1, 1)).is_true()
	assert_bool(
		_manager.get_profile_data()["reward_claims"].has(
			"awakening_kinetic_crystal"
		)
	).is_true()

	_recreate_manager()
	assert_bool(_manager.load_profile()).is_true()
	assert_int(_manager.get_owned_crystals().size()).is_equal(3)
	assert_bool(
		_manager.get_profile_data()["reward_claims"].has(
			"skill_crystal_reward_I"
		)
	).is_true()


func test_legacy_fire_mastery_migrates_to_fire_mastery_with_aoe_once() -> void:
	var fixture := _default_profile_fixture()
	fixture["schema_version"] = 2
	fixture["purchased_skill_nodes"]["tower_enhancements"] = ["A"]
	fixture["purchased_skill_nodes"]["elemental_mastery"] = ["D"]
	_write_json(_profile_path(), fixture)

	assert_bool(_manager.load_profile()).is_true()
	assert_bool(_manager.is_skill_purchased(&"D")).is_true()
	assert_bool(_manager.is_skill_purchased(&"I")).is_true()
	assert_float(
		_manager.get_skill_effect_value(&"unlock_fire_area")
	).is_equal(1.0)
	assert_bool(
		_contains_owned_crystal(_manager.get_owned_crystals(), "fire", 1, 1)
	).is_true()

	_recreate_manager()
	assert_bool(_manager.load_profile()).is_true()
	assert_bool(_manager.is_skill_purchased(&"I")).is_true()
	assert_int(_manager.get_owned_crystals().size()).is_equal(3)
	assert_bool(
		_contains_owned_crystal(_manager.get_owned_crystals(), "fire", 1, 1)
	).is_true()


func test_elemental_mastery_reveals_fire_mastery_and_unlocks_fire_aoe() -> void:
	assert_bool(_manager.add_essence(17)).is_true()
	for skill_id in ["A", "C", "F", "G", "H"]:
		assert_bool(_manager.purchase_skill_node(StringName(skill_id))).is_true()

	assert_bool(_manager.get_skill_node_status(&"I")["visible"]).is_false()
	assert_bool(_manager.purchase_skill_node(&"D")).is_true()
	assert_bool(_manager.get_skill_node_status(&"I")["visible"]).is_true()
	assert_bool(_manager.get_skill_node_status(&"J")["visible"]).is_true()
	assert_bool(_manager.purchase_skill_node(&"I")).is_true()
	assert_float(
		_manager.get_skill_effect_value(&"unlock_fire_area")
	).is_equal(1.0)
	assert_bool(
		_contains_owned_crystal(_manager.get_owned_crystals(), "fire", 1, 1)
	).is_true()
	_recreate_manager()
	assert_bool(_manager.is_skill_purchased(&"D")).is_true()
	assert_bool(_manager.get_skill_node_status(&"I")["visible"]).is_true()
	assert_bool(_manager.is_skill_purchased(&"I")).is_true()
	assert_bool(
		_contains_owned_crystal(_manager.get_owned_crystals(), "fire", 1, 1)
	).is_true()


func test_each_crystal_unlocking_skill_grants_exactly_one_matching_crystal() -> void:
	assert_bool(_manager.add_essence(100)).is_true()
	assert_bool(_manager.purchase_skill_node(&"A")).is_true()
	_manager.start_run_inventory()

	var rewards: Dictionary = {}
	for definition in SKILL_CATALOG.get_skill_definitions():
		var crystal_id := String(definition["unlock_crystal_id"])
		if not crystal_id.is_empty():
			rewards[String(definition["id"])] = crystal_id
	assert_int(rewards.size()).is_equal(4)

	var purchase_order := ["C", "F", "G", "H", "D", "I"]
	for skill_id in purchase_order:
		var before := {}
		for crystal_id in ["sniper", "slow", "bleed", "fire"]:
			before[crystal_id] = _owned_quantity(crystal_id)
		var run_before: Dictionary = {}
		for crystal_id in ["sniper", "slow", "bleed", "fire"]:
			run_before[crystal_id] = _manager.get_available_crystal_quantity(
				StringName(crystal_id),
				1
			)

		assert_bool(_manager.purchase_skill_node(StringName(skill_id))).is_true()
		for crystal_id in ["sniper", "slow", "bleed", "fire"]:
			var expected := 1 if rewards.get(skill_id, "") == crystal_id else 0
			assert_int(_owned_quantity(crystal_id)).is_equal(
				before[crystal_id] + expected
			)
			assert_int(
				_manager.get_available_crystal_quantity(StringName(crystal_id), 1)
			).is_equal(run_before[crystal_id] + expected)

		var owned_after := _owned_quantity(String(rewards.get(skill_id, "sniper")))
		assert_bool(_manager.purchase_skill_node(StringName(skill_id))).is_false()
		assert_int(
			_owned_quantity(String(rewards.get(skill_id, "sniper")))
		).is_equal(owned_after)

	_recreate_manager()
	assert_bool(_manager.load_profile()).is_true()
	for crystal_id in ["sniper", "slow", "bleed", "fire"]:
		assert_int(_owned_quantity(crystal_id)).is_equal(1)


func test_unaffordable_crystal_skill_purchase_grants_nothing() -> void:
	_purchase_awakening_magic()
	var profile_before: Dictionary = _manager.get_profile_data()
	assert_bool(_manager.purchase_skill_node(&"C")).is_false()
	assert_int(_owned_quantity("sniper")).is_equal(0)
	assert_bool(_manager.get_profile_data() == profile_before).is_true()


func test_stale_reward_claims_do_not_block_regrant_when_crystal_is_missing() -> void:
	var fixture := _default_profile_fixture()
	fixture["schema_version"] = 4
	fixture["essence"] = 20
	fixture["reward_claims"] = [
		"awakening_rapid_fire_crystal",
		"awakening_kinetic_crystal",
		"skill_crystal_reward_C",
		"skill_crystal_reward_F"
	]
	_write_json(_profile_path(), fixture)
	assert_bool(_manager.load_profile()).is_true()

	assert_bool(_manager.purchase_skill_node(&"A")).is_true()
	assert_bool(_manager.purchase_skill_node(&"C")).is_true()
	assert_bool(_manager.purchase_skill_node(&"F")).is_true()
	assert_int(_owned_quantity("sniper")).is_equal(1)
	assert_int(_owned_quantity("slow")).is_equal(1)

	var claims: Array = _manager.get_profile_data()["reward_claims"]
	assert_int(claims.count("skill_crystal_reward_C")).is_equal(1)


func test_essence_points_persist_and_legacy_profiles_get_defaults() -> void:
	var fixture := _default_profile_fixture()
	fixture["schema_version"] = 4
	fixture["essence"] = 7
	fixture["crystals"] = [{"crystal_id": "rapid_fire", "level": 2, "quantity": 3}]
	fixture["unlocked_crystal_ids"] = ["rapid_fire", "kinetic"]
	fixture["purchased_skill_nodes"]["tower_enhancements"] = ["A", "B"]
	fixture["records"] = {"best_wave": 4}
	fixture["reward_claims"] = [
		"awakening_rapid_fire_crystal",
		"awakening_kinetic_crystal"
	]
	_write_json(_profile_path(), fixture)

	assert_bool(_manager.load_profile()).is_true()
	assert_int(_manager.get_essence_points()).is_equal(0)
	assert_int(_manager.get_essence_threshold()).is_equal(100)
	var legacy_profile: Dictionary = _manager.get_profile_data()
	assert_int(int(legacy_profile["essence"])).is_equal(7)
	assert_bool(_contains_crystal(legacy_profile["crystals"], "rapid_fire", 2, 3)).is_true()
	assert_array(legacy_profile["purchased_skill_nodes"]["tower_enhancements"]).is_equal(
		["A", "B"]
	)
	assert_int(int(legacy_profile["records"]["best_wave"])).is_equal(4)

	assert_int(_manager.add_essence_points(98)).is_equal(0)
	assert_int(_manager.add_essence_points(5)).is_equal(1)
	_recreate_manager()
	assert_bool(_manager.load_profile()).is_true()
	assert_int(_manager.get_essence_points()).is_equal(3)
	assert_int(_manager.get_essence_threshold()).is_equal(105)
	assert_int(_manager.get_essence_balance()).is_equal(8)
	assert_bool(
		_contains_crystal(_manager.get_profile_data()["crystals"], "rapid_fire", 2, 3)
	).is_true()
	assert_bool(_manager.is_skill_purchased(&"B")).is_true()

	# Reloading must not award the same Essence again.
	_recreate_manager()
	assert_bool(_manager.load_profile()).is_true()
	assert_int(_manager.get_essence_balance()).is_equal(8)
	assert_int(_manager.get_essence_points()).is_equal(3)


func test_invalid_essence_progress_is_rejected_by_validation() -> void:
	for invalid_values in [
		{"essence_points": -1, "essence_threshold": 100},
		{"essence_points": 100, "essence_threshold": 100},
		{"essence_points": 0, "essence_threshold": 99},
		{"essence_points": "5", "essence_threshold": 100}
	]:
		var fixture := _default_profile_fixture()
		fixture["schema_version"] = 4
		fixture.merge(invalid_values)
		var parsed: Dictionary = _manager._parse_profile_text(
			JSON.stringify(fixture),
			"test"
		)
		assert_bool(parsed.is_empty()).is_true()


func test_duplicate_crystal_entries_are_merged_by_id_and_level() -> void:
	var fixture := _default_profile_fixture()
	fixture["crystals"] = [
		{"crystal_id": "rapid_fire", "level": 1, "quantity": 2},
		{"crystal_id": "rapid_fire", "level": 1, "quantity": 4}
	]
	fixture["purchased_skill_nodes"]["tower_enhancements"] = ["A"]
	_write_json(_profile_path(), fixture)

	assert_bool(_manager.load_profile()).is_true()

	var crystals: Array = _manager.get_profile_data()["crystals"]
	assert_int(crystals.size()).is_equal(2)
	assert_bool(_contains_crystal(crystals, "rapid_fire", 1, 6)).is_true()
	assert_bool(_contains_crystal(crystals, "kinetic", 1, 1)).is_true()


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


func test_skill_purchase_spends_once_and_persists_atomically() -> void:
	assert_bool(_manager.add_essence(1)).is_true()
	assert_str(_manager.get_skill_node_status(&"A")["state"]).is_equal("available")

	assert_bool(_manager.purchase_skill_node(&"A")).is_true()
	assert_int(_manager.get_essence_balance()).is_equal(0)
	assert_bool(_manager.is_skill_purchased(&"A")).is_true()
	assert_bool(_manager.is_crystal_inventory_unlocked()).is_true()
	assert_bool(_manager.is_crystal_unlocked(&"rapid_fire")).is_true()
	assert_bool(_manager.is_crystal_unlocked(&"kinetic")).is_true()
	assert_bool(
		_contains_owned_crystal(_manager.get_owned_crystals(), "rapid_fire", 1, 1)
	).is_true()
	assert_bool(
		_contains_owned_crystal(_manager.get_owned_crystals(), "kinetic", 1, 1)
	).is_true()
	assert_bool(_manager.purchase_skill_node(&"A")).is_false()
	assert_int(_manager.get_essence_balance()).is_equal(0)

	_recreate_manager()
	assert_int(_manager.get_essence_balance()).is_equal(0)
	assert_bool(_manager.is_skill_purchased(&"A")).is_true()
	assert_str(_manager.get_skill_node_status(&"A")["state"]).is_equal("purchased")
	_manager.start_run_inventory()
	assert_int(
		_manager.get_available_crystal_quantity(&"rapid_fire", 1)
	).is_equal(1)
	assert_int(
		_manager.get_available_crystal_quantity(&"kinetic", 1)
	).is_equal(1)


func test_resetting_skill_points_refunds_costs_and_persists_atomically() -> void:
	assert_bool(_manager.add_essence(15)).is_true()
	for skill_id in ["A", "B", "C", "F", "G", "H"]:
		assert_bool(_manager.purchase_skill_node(StringName(skill_id))).is_true()
	assert_int(_manager.get_essence_balance()).is_equal(3)
	assert_bool(_manager.is_crystal_unlocked(&"kinetic")).is_true()
	assert_bool(_manager.is_crystal_unlocked(&"slow")).is_true()
	assert_bool(_manager.is_crystal_unlocked(&"bleed")).is_true()

	assert_bool(_manager.reset_purchased_skill_nodes()).is_true()
	assert_int(_manager.get_essence_balance()).is_equal(15)
	assert_bool(_manager.is_skill_purchased(&"A")).is_false()
	assert_bool(_manager.is_skill_purchased(&"B")).is_false()
	assert_bool(_manager.is_skill_purchased(&"C")).is_false()
	assert_bool(_manager.is_crystal_unlocked(&"kinetic")).is_false()
	assert_bool(_manager.is_crystal_unlocked(&"slow")).is_false()
	assert_bool(_manager.is_crystal_unlocked(&"bleed")).is_false()
	assert_int(_manager.get_owned_crystals().size()).is_equal(0)
	for tree_id in [
		"crystals",
		"economy",
		"elemental_mastery",
		"tower_enhancements"
	]:
		assert_int(
			_manager.get_purchased_skill_node_ids(StringName(tree_id)).size()
		).is_equal(0)

	_recreate_manager()
	assert_int(_manager.get_essence_balance()).is_equal(15)
	assert_bool(_manager.is_skill_purchased(&"B")).is_false()


func test_skill_catalog_keeps_the_canonical_multi_branch_dependencies() -> void:
	assert_bool(SKILL_CATALOG.has_unique_ids()).is_true()
	var definitions: Array[Dictionary] = SKILL_CATALOG.get_skill_definitions()
	var by_id: Dictionary = {}
	for definition in definitions:
		by_id[definition["id"]] = definition
	assert_int(by_id.size()).is_equal(32)

	for branch in ["B", "C", "D", "E"]:
		assert_bool(by_id[branch]["prerequisites"].has("A")).is_true()
	for prefix in ["K", "L", "M"]:
		assert_bool(by_id[prefix + "1"]["prerequisites"].has("B")).is_true()
		assert_bool(
			by_id[prefix + "2"]["prerequisites"] == [prefix + "1"]
		).is_true()
		assert_bool(
			by_id[prefix + "3"]["prerequisites"] == [prefix + "2"]
		).is_true()
	assert_int(by_id["N"]["prerequisites"].size()).is_equal(9)
	assert_bool(by_id["F"]["prerequisites"] == ["C"]).is_true()
	assert_bool(by_id["G"]["prerequisites"] == ["C"]).is_true()
	assert_bool(by_id["H"]["prerequisites"] == ["F", "G"]).is_true()
	assert_bool(by_id["I"]["prerequisites"] == ["H", "D"]).is_true()
	assert_bool(by_id["J"]["prerequisites"] == ["I"]).is_true()
	assert_bool(by_id["O"]["prerequisites"] == ["E"]).is_true()
	assert_bool(by_id["P"]["prerequisites"] == ["E"]).is_true()
	assert_bool(by_id["Q"]["prerequisites"] == ["O"]).is_true()
	assert_bool(by_id["D"]["prerequisites"] == ["A"]).is_true()
	assert_str(by_id["D"]["visible_after"]).is_equal("H")
	assert_str(by_id["I"]["visible_after"]).is_equal("D")
	assert_str(by_id["J"]["visible_after"]).is_equal("D")
	assert_int(by_id["D"]["cost"]).is_equal(3)
	assert_int(by_id["I"]["cost"]).is_equal(4)
	assert_int(by_id["J"]["cost"]).is_equal(5)
	for skill_id in ["F1", "F2", "F3", "G1", "G2", "G3"]:
		assert_bool(by_id["H"]["prerequisites"].has(skill_id)).is_false()


func test_fire_nodes_d_i_j_are_hidden_until_h_and_keep_requirements() -> void:
	assert_bool(_manager.add_essence(100)).is_true()
	for skill_id in ["D", "I", "J"]:
		var status: Dictionary = _manager.get_skill_node_status(StringName(skill_id))
		assert_bool(status["visible"]).is_false()
		assert_str(status["state"]).is_equal("hidden")
		assert_bool(_manager.purchase_skill_node(StringName(skill_id))).is_false()
	for skill_id in ["A", "C", "F", "G"]:
		assert_bool(_manager.purchase_skill_node(StringName(skill_id))).is_true()
	for skill_id in ["D", "I", "J"]:
		assert_bool(_manager.get_skill_node_status(StringName(skill_id))["visible"]).is_false()

	assert_bool(_manager.purchase_skill_node(&"H")).is_true()
	assert_bool(_manager.get_skill_node_status(&"D")["visible"]).is_true()
	assert_bool(_manager.get_skill_node_status(&"I")["visible"]).is_false()
	assert_bool(_manager.get_skill_node_status(&"J")["visible"]).is_false()
	assert_str(_manager.get_skill_node_status(&"D")["state"]).is_equal("available")
	var i_status: Dictionary = _manager.get_skill_node_status(&"I")
	assert_str(i_status["state"]).is_equal("hidden")
	assert_bool(i_status["missing_prerequisites"] == ["D"]).is_true()
	var j_status: Dictionary = _manager.get_skill_node_status(&"J")
	assert_str(j_status["state"]).is_equal("hidden")
	assert_bool(j_status["missing_prerequisites"] == ["I"]).is_true()
	assert_bool(_manager.purchase_skill_node(&"I")).is_false()
	assert_bool(_manager.purchase_skill_node(&"J")).is_false()


func test_h_accepts_f_or_g_while_i_and_j_keep_strict_requirements() -> void:
	for prerequisite in [&"F", &"G"]:
		assert_bool(_manager.add_essence(100)).is_true()
		assert_bool(_manager.purchase_skill_node(&"A")).is_true()
		assert_bool(_manager.purchase_skill_node(&"C")).is_true()
		assert_bool(_manager.purchase_skill_node(prerequisite)).is_true()
		assert_str(_manager.get_skill_node_status(&"H")["state"]).is_equal(
			"available"
		)
		assert_bool(_manager.purchase_skill_node(&"H")).is_true()
		assert_str(_manager.get_skill_node_status(&"I")["state"]).is_equal(
			"hidden"
		)
		assert_bool(
			_manager.get_skill_node_status(&"I")["missing_prerequisites"]
			== ["D"]
		).is_true()
		assert_str(_manager.get_skill_node_status(&"J")["state"]).is_equal(
			"hidden"
		)
		assert_bool(_manager.purchase_skill_node(&"J")).is_false()

		var fixture := _default_profile_fixture()
		_write_json(_profile_path(), fixture)
		assert_bool(_manager.load_profile()).is_true()

	assert_bool(_manager.add_essence(100)).is_true()
	assert_bool(_manager.purchase_skill_node(&"A")).is_true()
	assert_bool(_manager.purchase_skill_node(&"C")).is_true()
	assert_bool(_manager.purchase_skill_node(&"F")).is_true()
	assert_bool(_manager.purchase_skill_node(&"H")).is_true()
	assert_bool(_manager.purchase_skill_node(&"D")).is_true()
	assert_str(_manager.get_skill_node_status(&"I")["state"]).is_equal(
		"available"
	)
	assert_bool(_manager.purchase_skill_node(&"I")).is_true()
	assert_str(_manager.get_skill_node_status(&"J")["state"]).is_equal(
		"available"
	)
	assert_bool(_manager.purchase_skill_node(&"J")).is_true()
	assert_bool(_manager.is_skill_purchased(&"J")).is_true()


func test_fire_node_visibility_follows_saved_progression_not_ui_state() -> void:
	var fixture := _default_profile_fixture()
	fixture["purchased_skill_nodes"] = {
		"crystals": ["A", "C", "F", "G"],
		"economy": [],
		"elemental_mastery": [],
		"tower_enhancements": []
	}
	_write_json(_profile_path(), fixture)
	assert_bool(_manager.load_profile()).is_true()
	for skill_id in ["D", "I", "J"]:
		assert_bool(_manager.get_skill_node_status(StringName(skill_id))["visible"]).is_false()

	fixture["purchased_skill_nodes"]["crystals"] = ["A", "C", "F", "G", "H"]
	fixture["purchased_skill_nodes"]["elemental_mastery"] = ["D"]
	_write_json(_profile_path(), fixture)
	assert_bool(_manager.load_profile()).is_true()
	assert_bool(_manager.get_skill_node_status(&"D")["visible"]).is_true()
	assert_bool(_manager.get_skill_node_status(&"I")["visible"]).is_true()
	assert_bool(_manager.get_skill_node_status(&"J")["visible"]).is_true()


func test_skill_tree_layout_places_branches_around_central_a() -> void:
	var node_size: Vector2 = SKILL_CANVAS.NODE_SIZE
	var a_center: Vector2 = SKILL_CATALOG.get_node_position("A") + node_size * 0.5
	assert_float(a_center.x).is_equal_approx(SKILL_CATALOG.CANVAS_SIZE.x * 0.5, 1.0)
	assert_float(a_center.y).is_equal_approx(SKILL_CATALOG.CANVAS_SIZE.y * 0.5, 1.0)

	var quadrants := {
		"E": Vector2(-1, -1),
		"B": Vector2(1, -1),
		"D": Vector2(-1, 1),
		"C": Vector2(1, 1)
	}
	var branch_members := {
		"E": ["E", "O", "P", "Q"],
		"B": ["B", "K1", "K2", "K3", "L1", "L2", "L3", "M1", "M2", "M3", "N"],
		"D": ["D", "I", "J"],
		"C": ["C", "C1", "C2", "C3", "F", "F1", "F2", "F3", "G", "G1", "G2", "G3", "H"]
	}
	for root_id in quadrants:
		var direction: Vector2 = quadrants[root_id]
		var root_center: Vector2 = SKILL_CATALOG.get_node_position(root_id) + node_size * 0.5
		assert_bool(signf(root_center.x - a_center.x) == direction.x).is_true()
		assert_bool(signf(root_center.y - a_center.y) == direction.y).is_true()
		for member_id in branch_members[root_id]:
			var center: Vector2 = SKILL_CATALOG.get_node_position(member_id) + node_size * 0.5
			if member_id != "H":
				assert_bool(signf(center.x - a_center.x) == direction.x).is_true()
			assert_bool(signf(center.y - a_center.y) == direction.y).is_true()


func test_skill_tree_layout_has_no_overlaps_and_navigable_connectors() -> void:
	var node_size: Vector2 = SKILL_CANVAS.NODE_SIZE
	var definitions: Array[Dictionary] = SKILL_CATALOG.get_skill_definitions()
	var rects: Dictionary = {}
	for definition in definitions:
		var skill_id: String = definition["id"]
		assert_bool(SKILL_CATALOG.NODE_LAYOUT.has(skill_id)).is_true()
		var rect := Rect2(SKILL_CATALOG.get_node_position(skill_id), node_size)
		assert_bool(
			Rect2(Vector2.ZERO, SKILL_CATALOG.CANVAS_SIZE).encloses(rect)
		).is_true()
		for other_id in rects:
			assert_bool(rect.grow(8.0).intersects(rects[other_id])).is_false()
		rects[skill_id] = rect
	assert_int(SKILL_CATALOG.NODE_LAYOUT.size()).is_equal(definitions.size())

	var edge_count := 0
	var n_edge_count := 0
	for definition in definitions:
		var child_id: String = definition["id"]
		for parent_id in definition["prerequisites"]:
			var points: PackedVector2Array = SKILL_CANVAS.get_connection_points(
				String(parent_id),
				child_id
			)
			assert_int(points.size()).is_greater_equal(4)
			assert_bool(rects[String(parent_id)].grow(1.0).has_point(points[0])).is_true()
			assert_bool(rects[child_id].grow(1.0).has_point(points[points.size() - 1])).is_true()
			edge_count += 1
			if child_id == "N":
				n_edge_count += 1
			for index in range(points.size() - 1):
				var segment := Rect2(points[index], Vector2.ZERO).expand(points[index + 1])
				for other_id in rects:
					if other_id == String(parent_id) or other_id == child_id:
						continue
					assert_bool(segment.grow(2.0).intersects(rects[other_id])).is_false()
	assert_int(n_edge_count).is_equal(9)
	assert_int(edge_count).is_greater(n_edge_count)


func test_unaffordable_and_missing_prerequisite_purchases_do_not_spend_essence() -> void:
	assert_bool(_manager.purchase_skill_node(&"A")).is_false()
	assert_bool(_manager.add_essence(1)).is_true()
	assert_bool(_manager.purchase_skill_node(&"A")).is_true()
	assert_str(_manager.get_skill_node_status(&"B")["state"]).is_equal(
		"unaffordable"
	)
	assert_bool(_manager.purchase_skill_node(&"B")).is_false()
	assert_int(_manager.get_essence_balance()).is_equal(0)
	assert_bool(_manager.add_essence(100)).is_true()
	var before: int = int(_manager.get_essence_balance())
	assert_bool(_manager.purchase_skill_node(&"D")).is_false()
	assert_bool(_manager.purchase_skill_node(&"K1")).is_false()
	assert_int(_manager.get_essence_balance()).is_equal(before)
	assert_bool(_manager.is_skill_purchased(&"B")).is_false()


func test_crystal_branch_visibility_unlocks_and_keeps_collection_separate() -> void:
	assert_bool(_manager.add_essence(100)).is_true()
	assert_bool(_manager.purchase_skill_node(&"A")).is_true()
	assert_str(_manager.get_skill_node_status(&"D")["state"]).is_equal("hidden")
	assert_bool(_manager.purchase_skill_node(&"C")).is_true()
	assert_bool(_manager.is_crystal_unlocked(&"kinetic")).is_true()
	assert_bool(_manager.is_crystal_unlocked(&"sniper")).is_true()
	assert_int(_manager.get_owned_crystals().size()).is_equal(3)
	assert_bool(
		_contains_owned_crystal(_manager.get_owned_crystals(), "rapid_fire", 1, 1)
	).is_true()
	assert_bool(
		_contains_owned_crystal(_manager.get_owned_crystals(), "sniper", 1, 1)
	).is_true()
	assert_bool(_manager.purchase_skill_node(&"F")).is_true()
	assert_bool(_manager.is_crystal_unlocked(&"slow")).is_true()
	assert_bool(_manager.purchase_skill_node(&"G")).is_true()
	assert_bool(_manager.is_crystal_unlocked(&"bleed")).is_true()

	assert_bool(_manager.purchase_skill_node(&"H")).is_true()
	assert_str(_manager.get_skill_node_status(&"D")["state"]).is_equal("available")
	assert_str(_manager.get_skill_node_status(&"I")["state"]).is_equal("hidden")
	assert_bool(_manager.purchase_skill_node(&"D")).is_true()
	assert_str(_manager.get_skill_node_status(&"I")["state"]).is_equal("available")
	assert_bool(_manager.purchase_skill_node(&"I")).is_true()
	assert_str(_manager.get_skill_node_status(&"J")["state"]).is_equal("available")


func test_crystal_skill_rewards_are_one_time_and_persist_across_loads() -> void:
	assert_bool(_manager.add_essence(100)).is_true()
	for skill_id in ["A", "C", "F", "G", "H", "D"]:
		assert_bool(_manager.purchase_skill_node(StringName(skill_id))).is_true()
	assert_bool(_manager.purchase_skill_node(&"I")).is_true()

	var expected_crystals := [
		"kinetic",
		"rapid_fire",
		"sniper",
		"slow",
		"bleed",
		"fire"
	]
	for crystal_id in expected_crystals:
		assert_bool(
			_contains_owned_crystal(
				_manager.get_owned_crystals(),
				crystal_id,
				1,
				1
			)
		).is_true()

	_recreate_manager()
	_manager.start_run_inventory()
	for crystal_id in expected_crystals:
		assert_int(
			_manager.get_available_crystal_quantity(StringName(crystal_id), 1)
		).is_equal(1)
	assert_bool(_manager.purchase_skill_node(&"C")).is_false()
	assert_int(_manager.get_owned_crystals().size()).is_equal(6)
	_manager.start_run_inventory()
	for crystal_id in expected_crystals:
		assert_int(
			_manager.get_available_crystal_quantity(StringName(crystal_id), 1)
		).is_equal(1)


func test_existing_purchased_crystal_skills_receive_each_new_reward_once() -> void:
	var fixture := _default_profile_fixture()
	fixture["purchased_skill_nodes"] = {
		"crystals": ["C", "F", "G", "H"],
		"economy": [],
		"elemental_mastery": ["D"],
		"tower_enhancements": ["A"]
	}
	_write_json(_profile_path(), fixture)

	assert_bool(_manager.load_profile()).is_true()
	for crystal_id in [
		"kinetic",
		"rapid_fire",
		"sniper",
		"slow",
		"bleed",
		"fire"
	]:
		assert_bool(
			_contains_owned_crystal(
				_manager.get_owned_crystals(),
				crystal_id,
				1,
				1
			)
		).is_true()
	assert_bool(_manager.last_save_success).is_true()

	_recreate_manager()
	assert_int(_manager.get_owned_crystals().size()).is_equal(6)
	assert_bool(
		_manager.get_profile_data()["reward_claims"].has(
			"skill_crystal_reward_C"
		)
	).is_true()


func test_tower_paths_are_sequential_and_n_requires_all_nine_nodes() -> void:
	assert_bool(_manager.add_essence(100)).is_true()
	assert_bool(_manager.purchase_skill_node(&"A")).is_true()
	assert_bool(_manager.purchase_skill_node(&"B")).is_true()
	var n_definition := SKILL_CATALOG.get_skill_definition(&"N")
	assert_int(n_definition["prerequisites"].size()).is_equal(9)
	assert_str(_manager.get_skill_node_status(&"N")["state"]).is_equal("locked")

	for path_ids in [
		["K1", "K2", "K3"],
		["L1", "L2", "L3"],
		["M1", "M2", "M3"]
	]:
		assert_bool(_manager.purchase_skill_node(StringName(path_ids[0]))).is_true()
		assert_str(
			_manager.get_skill_node_status(StringName(path_ids[1]))["state"]
		).is_equal("available")
		assert_str(
			_manager.get_skill_node_status(StringName(path_ids[2]))["state"]
		).is_equal("locked")
		assert_bool(_manager.purchase_skill_node(StringName(path_ids[1]))).is_true()
		assert_bool(_manager.purchase_skill_node(StringName(path_ids[2]))).is_true()

	assert_str(_manager.get_skill_node_status(&"N")["state"]).is_equal("available")
	assert_bool(_manager.purchase_skill_node(&"N")).is_true()


func test_economy_prerequisites_and_effects_are_data_driven() -> void:
	assert_bool(_manager.add_essence(100)).is_true()
	assert_bool(_manager.purchase_skill_node(&"A")).is_true()
	assert_bool(_manager.purchase_skill_node(&"E")).is_true()
	assert_str(_manager.get_skill_node_status(&"O")["state"]).is_equal("available")
	assert_str(_manager.get_skill_node_status(&"P")["state"]).is_equal("available")
	assert_str(_manager.get_skill_node_status(&"Q")["state"]).is_equal("locked")
	assert_bool(_manager.purchase_skill_node(&"O")).is_true()
	assert_bool(_manager.purchase_skill_node(&"Q")).is_true()
	assert_bool(_manager.purchase_skill_node(&"P")).is_true()
	assert_float(
		_manager.get_skill_effect_value(&"early_wave_bonus_scale")
	).is_equal_approx(0.1, 0.0001)
	assert_float(
		_manager.get_skill_effect_value(&"passive_gold")
	).is_equal_approx(1.0, 0.0001)


func test_failed_skill_save_does_not_spend_essence_or_record_purchase() -> void:
	assert_bool(_manager.add_essence(10)).is_true()
	var profile_before: Dictionary = _manager.get_profile_data()
	var save_before := _read_text(_profile_path())
	var blocked_path := _storage_directory.path_join("not-a-directory")
	_write_text(blocked_path, "file occupies the intended directory path")
	_manager.profile_storage_directory = blocked_path

	assert_bool(_manager.purchase_skill_node(&"A")).is_false()
	assert_bool(_manager.get_profile_data() == profile_before).is_true()
	assert_str(_read_text(_profile_path())).is_equal(save_before)


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
		"schema_version": 2,
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


func _purchase_awakening_magic() -> void:
	if _manager.is_crystal_inventory_unlocked():
		return
	assert_bool(_manager.add_essence(1)).is_true()
	assert_bool(_manager.purchase_skill_node(&"A")).is_true()


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


func _owned_quantity(crystal_id: String) -> int:
	var total := 0
	for entry in _manager.get_owned_crystals():
		if String((entry["definition"] as CrystalData).crystal_id) == crystal_id:
			total += int(entry["quantity"])
	return total


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
