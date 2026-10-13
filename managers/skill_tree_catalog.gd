extends RefCounted

static func get_skill_definitions() -> Array[Dictionary]:
	return [
	_skill("A", "Awakening Magic", "tower_enhancements", 1, [], "Unlocks the Crystal Inventory and grants one Kinetic Crystal and one Rapid Fire Crystal.", "access_skill_tree"),
	_skill("B", "Tower Enhancements", "tower_enhancements", 2, ["A"], "Unlocks tower upgrades during a run.", "unlock_tower_upgrades"),
	_skill("C", "Sniper Crystal", "crystals", 2, ["A"], "Unlocks Sniper Crystal and grants one copy.", "unlock_sniper", 0.0, "sniper"),
	_skill("D", "Elemental Mastery", "elemental_mastery", 3, ["A"], "Unlocks the Elemental Mastery skill-tree branch.", "access_elemental_mastery", 0.0, "", "H"),
	_skill("E", "Economy", "economy", 2, ["A"], "Unlocks control of the existing automatic-wave system.", "unlock_auto_waves"),
	_skill("K1", "Damage Foundation", "tower_enhancements", 1, ["B"], "Increases base tower damage by 10%.", "tower_base_damage_bonus", 0.10),
	_skill("K2", "Damage Expertise", "tower_enhancements", 2, ["K1"], "Improves the bonus from damage-track upgrades by 10%.", "damage_upgrade_effectiveness", 0.10),
	_skill("K3", "Efficient Damage", "tower_enhancements", 3, ["K2"], "Reduces damage-track upgrade costs by 10%.", "damage_upgrade_cost_reduction", 0.10),
	_skill("L1", "Speed Foundation", "tower_enhancements", 1, ["B"], "Increases base tower attack speed by 10%.", "tower_base_speed_bonus", 0.10),
	_skill("L2", "Speed Expertise", "tower_enhancements", 2, ["L1"], "Improves the bonus from attack-speed upgrades by 10%.", "speed_upgrade_effectiveness", 0.10),
	_skill("L3", "Efficient Speed", "tower_enhancements", 3, ["L2"], "Reduces attack-speed upgrade costs by 10%.", "speed_upgrade_cost_reduction", 0.10),
	_skill("M1", "Range Foundation", "tower_enhancements", 1, ["B"], "Increases base tower range by 10%.", "tower_base_range_bonus", 0.10),
	_skill("M2", "Range Expertise", "tower_enhancements", 2, ["M1"], "Improves the bonus from range upgrades by 10%.", "range_upgrade_effectiveness", 0.10),
	_skill("M3", "Efficient Range", "tower_enhancements", 3, ["M2"], "Reduces range-upgrade costs by 10%.", "range_upgrade_cost_reduction", 0.10),
	_skill("N", "Tower Mastery", "tower_enhancements", 5, ["K1", "K2", "K3", "L1", "L2", "L3", "M1", "M2", "M3"], "Reduces all tower-upgrade costs by an additional 5%.", "tower_upgrade_cost_reduction_all", 0.05),
	_skill("C1", "Crystal Attunement I", "crystals", 1, ["C"], "Increases Rapid Fire and Sniper Crystal damage by 10%.", "rapid_sniper_damage_bonus", 0.10),
	_skill("C2", "Crystal Attunement II", "crystals", 2, ["C"], "Adds a 20% Rapid Fire and Sniper Crystal damage bonus.", "rapid_sniper_damage_bonus", 0.20),
	_skill("C3", "Crystal Attunement III", "crystals", 3, ["C"], "Adds a 30% Rapid Fire and Sniper Crystal damage bonus.", "rapid_sniper_damage_bonus", 0.30),
	_skill("F", "Slow Crystal", "crystals", 2, ["C"], "Unlocks and grants one level-1 Slow Crystal.", "unlock_slow", 0.0, "slow"),
	_skill("F1", "Slow Attunement I", "crystals", 1, ["F"], "Increases base slow strength to 25%.", "slow_strength_tier_1", 0.05),
	_skill("F2", "Slow Attunement II", "crystals", 2, ["F1"], "Increases base slow strength to 30%.", "slow_strength_tier_2", 0.10),
	_skill("F3", "Slow Attunement III", "crystals", 3, ["F2"], "Increases base slow strength to 35%.", "slow_strength_tier_3", 0.15),
	_skill("G", "Bleed Crystal", "crystals", 2, ["C"], "Unlocks and grants one level-1 Bleed Crystal.", "unlock_bleed", 0.0, "bleed"),
	_skill("G1", "Bleed Attunement I", "crystals", 1, ["G"], "Increases base Bleed damage to 3% of enemy maximum HP per second.", "bleed_strength_tier_1", 0.01),
	_skill("G2", "Bleed Attunement II", "crystals", 2, ["G1"], "Increases base Bleed damage to 4% of enemy maximum HP per second.", "bleed_strength_tier_2", 0.02),
	_skill("G3", "Bleed Attunement III", "crystals", 3, ["G2"], "Increases base Bleed damage to 5% of enemy maximum HP per second.", "bleed_strength_tier_3", 0.03),
	_skill("H", "Convergence", "crystals", 3, ["F", "G"], "Increases crystal damage and non-damage crystal effects by 10%.", "crystal_damage_bonus", 0.10, "", "", false, "any"),
	_skill("I", "Fire Mastery", "elemental_mastery", 4, ["H", "D"], "Grants one Fire Crystal and immediately enables its area-damage hit.", "unlock_fire_area", 1.0, "fire", "D"),
	_skill("J", "Further Fire Mastery", "elemental_mastery", 5, ["I"], "Increases Fire Crystal damage by 20%.", "fire_damage_bonus", 0.20, "", "D"),
	_skill("O", "Early-Wave Tactics", "economy", 2, ["E"], "Improves manual early-wave Gold bonuses while retaining the existing 30% cap.", "early_wave_bonus_scale", 0.1),
	_skill("Q", "Wave Foresight", "economy", 2, ["O"], "Unlocks the existing generated next-wave preview.", "unlock_wave_preview"),
	_skill("P", "Passive Income", "economy", 3, ["E"], "Generates 1 run Gold every 10 seconds during an active run.", "passive_gold", 1.0)
	]

const NODE_LAYOUT: Dictionary = {
	"A": Vector2(1480, 1170),
	"B": Vector2(1980, 880),
	"C": Vector2(1980, 1460),
	"D": Vector2(980, 1460),
	"E": Vector2(980, 880),
	"K1": Vector2(1730, 630),
	"K2": Vector2(1730, 450),
	"K3": Vector2(1730, 270),
	"L1": Vector2(1980, 630),
	"L2": Vector2(1980, 450),
	"L3": Vector2(1980, 270),
	"M1": Vector2(2230, 630),
	"M2": Vector2(2230, 450),
	"M3": Vector2(2230, 270),
	"N": Vector2(1980, 10),
	"C1": Vector2(2480, 1720),
	"C2": Vector2(2720, 1720),
	"C3": Vector2(2960, 1720),
	"F": Vector2(1630, 1720),
	"G": Vector2(2230, 1720),
	"F1": Vector2(1630, 1970),
	"F2": Vector2(1630, 2150),
	"F3": Vector2(1630, 2330),
	"G1": Vector2(2230, 1970),
	"G2": Vector2(2230, 2150),
	"G3": Vector2(2230, 2330),
	"H": Vector2(1930, 1970),
	"I": Vector2(980, 2120),
	"J": Vector2(980, 2340),
	"O": Vector2(830, 630),
	"P": Vector2(1130, 630),
	"Q": Vector2(830, 450)
}

const CANVAS_SIZE := Vector2(3150, 2452)
const PASSIVE_GOLD_INTERVAL_SECONDS: float = 10.0
const CATEGORY_NAMES: Dictionary = {
	"tower_enhancements": "Tower Enhancements",
	"crystals": "Crystals",
	"elemental_mastery": "Elemental Mastery",
	"economy": "Economy"
}


static func _skill(
	skill_id: String,
	display_name: String,
	category: String,
	cost: int,
	prerequisites: Array,
	description: String,
	effect_id: String,
	effect_value: float = 0.0,
	unlock_crystal_id: String = "",
	visible_after: String = "",
	planned: bool = false,
	prerequisite_mode: String = "all"
) -> Dictionary:
	return {
		"id": skill_id,
		"name": skill_id + " — " + display_name,
		"display_name": display_name,
		"category": category,
		"cost": cost,
		"prerequisites": prerequisites,
		"prerequisite_mode": prerequisite_mode,
		"description": description,
		"effect_id": effect_id,
		"effect_value": effect_value,
		"unlock_crystal_id": unlock_crystal_id,
		"visible_after": visible_after,
		"planned": planned
	}


static func get_skill_definition(skill_id: StringName) -> Dictionary:
	for definition in get_skill_definitions():
		if definition["id"] == String(skill_id):
			return definition.duplicate(true)
	return {}


static func get_node_position(skill_id: String) -> Vector2:
	return NODE_LAYOUT.get(skill_id, Vector2.ZERO)


static func get_category_name(category_id: String) -> String:
	return CATEGORY_NAMES.get(category_id, category_id)


static func has_unique_ids() -> bool:
	var seen: Dictionary = {}
	for definition in get_skill_definitions():
		var skill_id: String = definition["id"]
		if seen.has(skill_id):
			return false
		seen[skill_id] = true
	return true


static func get_missing_prerequisites(
	skill_id: StringName,
	purchased_ids: Array[String]
) -> Array[String]:
	var definition := get_skill_definition(skill_id)
	var missing: Array[String] = []
	for prerequisite_id in definition.get("prerequisites", []):
		if not purchased_ids.has(String(prerequisite_id)):
			missing.append(String(prerequisite_id))
	if definition.get("prerequisite_mode", "all") == "any":
		for prerequisite_id in definition.get("prerequisites", []):
			if purchased_ids.has(String(prerequisite_id)):
				return []
	return missing
