extends RefCounted

const DEFINITIONS: Array[Dictionary] = [
	{
		"id": "first_blood",
		"title": "First Blood",
		"description": "Kill 1 enemy.",
		"category": "combat",
		"hidden": false,
		"event": "enemy_killed",
		"target": 1,
		"reward_essence": 2,
		"display_order": 10
	},
	{
		"id": "warmup",
		"title": "Warmup",
		"description": "Kill 10 enemies.",
		"category": "combat",
		"hidden": false,
		"event": "enemy_killed",
		"target": 10,
		"reward_essence": 3,
		"display_order": 20
	},
	{
		"id": "slayer_250",
		"title": "Slayer",
		"description": "Kill 250 enemies.",
		"category": "combat",
		"hidden": false,
		"event": "enemy_killed",
		"target": 250,
		"reward_essence": 12,
		"display_order": 30
	},
	{
		"id": "horde_terror",
		"title": "Horde Terror",
		"description": "Kill 1,000 enemies.",
		"category": "combat",
		"hidden": false,
		"event": "enemy_killed",
		"target": 1000,
		"reward_essence": 25,
		"display_order": 40
	},
	{
		"id": "endless_fight",
		"title": "Endless Fight",
		"description": "Kill 5,000 enemies.",
		"category": "combat",
		"hidden": false,
		"event": "enemy_killed",
		"target": 5000,
		"reward_essence": 50,
		"display_order": 50
	},
	{
		"id": "battle_legend",
		"title": "Battle Legend",
		"description": "Kill 10,000 enemies.",
		"category": "combat",
		"hidden": false,
		"event": "enemy_killed",
		"target": 10000,
		"reward_essence": 0,
		"cosmetic_reward_id": "ordinary_enemy_skin",
		"cosmetic_reward_type": "enemy_skin",
		"display_order": 60
	},
	{
		"id": "wave_10",
		"title": "Wave 10",
		"description": "Complete wave 10.",
		"category": "waves",
		"hidden": false,
		"event": "wave_completed",
		"target": 10,
		"reward_essence": 5,
		"display_order": 70
	},
	{
		"id": "wave_25",
		"title": "Wave 25",
		"description": "Complete wave 25.",
		"category": "waves",
		"hidden": false,
		"event": "wave_completed",
		"target": 25,
		"reward_essence": 10,
		"display_order": 80
	},
	{
		"id": "wave_100",
		"title": "Wave 100",
		"description": "Complete wave 100.",
		"category": "waves",
		"hidden": false,
		"event": "wave_completed",
		"target": 100,
		"reward_essence": 0,
		"cosmetic_reward_id": "wave_100_frame",
		"cosmetic_reward_type": "profile_frame",
		"display_order": 90
	},
	{
		"id": "boss_5",
		"title": "Boss Hunter",
		"description": "Defeat 5 bosses.",
		"category": "bosses",
		"hidden": false,
		"event": "boss_defeated",
		"target": 5,
		"reward_essence": 25,
		"display_order": 100
	},
	{
		"id": "all_t1_bosses",
		"title": "Tier 1 Conqueror",
		"description": "Defeat every Tier 1 boss type.",
		"category": "bosses",
		"hidden": false,
		"event": "boss_defeated",
		"condition": "all_tier_one_bosses",
		"target": 8,
		"reward_essence": 0,
		"cosmetic_reward_id": "tier_1_tower_skin",
		"cosmetic_reward_type": "tower_skin",
		"display_order": 110
	},
	{
		"id": "bestiary_complete",
		"title": "Bestiary Complete",
		"description": "Kill every ordinary enemy type and defeat every Tier 1 boss type.",
		"category": "bestiary",
		"hidden": false,
		"event": "enemy_killed",
		"condition": "bestiary_complete",
		"target": 1,
		"reward_essence": 0,
		"cosmetic_reward_id": "complete_bestiary_avatar",
		"cosmetic_reward_type": "user_avatar",
		"display_order": 120
	},
	{
		"id": "first_crystal",
		"title": "First Crystal",
		"description": "Purchase 1 crystal.",
		"category": "crystals",
		"hidden": false,
		"event": "crystal_purchased",
		"target": 1,
		"reward_essence": 3,
		"display_order": 130
	},
	{
		"id": "crystal_collector",
		"title": "Crystal Collector",
		"description": "Purchase 5 crystals cumulatively.",
		"category": "crystals",
		"hidden": false,
		"event": "crystal_purchased",
		"target": 5,
		"reward_essence": 5,
		"display_order": 140
	},
	{
		"id": "crystal_tycoon",
		"title": "Crystal Tycoon",
		"description": "Purchase 50 crystals cumulatively.",
		"category": "crystals",
		"hidden": false,
		"event": "crystal_purchased",
		"target": 50,
		"reward_essence": 15,
		"display_order": 150
	},
	{
		"id": "first_fusion",
		"title": "First Fusion",
		"description": "Complete 1 successful crystal fusion.",
		"category": "crystals",
		"hidden": false,
		"event": "fusion_completed",
		"target": 1,
		"reward_essence": 5,
		"display_order": 160
	},
	{
		"id": "fusion_master",
		"title": "Fusion Master",
		"description": "Complete 10 successful crystal fusions.",
		"category": "crystals",
		"hidden": false,
		"event": "fusion_completed",
		"target": 10,
		"reward_essence": 15,
		"display_order": 170
	},
	{
		"id": "defense_engineer",
		"title": "Defense Engineer",
		"description": "Complete 25 successful tower upgrades.",
		"category": "towers",
		"hidden": false,
		"event": "tower_upgrade_completed",
		"target": 25,
		"reward_essence": 0,
		"cosmetic_reward_id": "engineer_tower_skin",
		"cosmetic_reward_type": "tower_skin",
		"display_order": 180
	},
	{
		"id": "first_essence",
		"title": "First Essence",
		"description": "Earn Essence for the first time.",
		"category": "essence",
		"hidden": false,
		"event": "essence_earned",
		"target": 1,
		"reward_essence": 2,
		"display_order": 190
	},
	{
		"id": "essence_reserve",
		"title": "Essence Reserve",
		"description": "Earn 500 Essence cumulatively.",
		"category": "essence",
		"hidden": false,
		"event": "essence_earned",
		"target": 500,
		"reward_essence": 15,
		"display_order": 200
	},
	{
		"id": "trophy_escapees",
		"title": "Trophy Escapees",
		"description": "Lose 10 trophies to the enemy camp cumulatively.",
		"category": "trophies",
		"hidden": false,
		"event": "trophy_delivered",
		"target": 10,
		"reward_essence": 5,
		"display_order": 210
	},
	{
		"id": "perfect_defense",
		"title": "Perfect Defense",
		"description": "Complete wave 10 with all 5/5 trophies remaining.",
		"category": "trophies",
		"hidden": false,
		"event": "wave_completed",
		"condition": "perfect_wave_ten",
		"target": 1,
		"reward_essence": 10,
		"display_order": 220
	},
	{
		"id": "vault_guardian",
		"title": "Vault Guardian",
		"description": "Complete 50 waves in a row without losing a trophy.",
		"category": "trophies",
		"hidden": false,
		"event": "wave_completed",
		"condition": "lossless_wave_streak",
		"target": 50,
		"reward_essence": 0,
		"cosmetic_reward_id": "vault_castle_skin",
		"cosmetic_reward_type": "castle_skin",
		"display_order": 230
	},
	{
		"id": "fusion_streak_secret",
		"title": "Fusion Streak",
		"description": "Complete 3 successful fusions in one run.",
		"category": "secrets",
		"hidden": true,
		"event": "fusion_completed",
		"condition": "run_fusion_streak",
		"target": 3,
		"reward_essence": 10,
		"display_order": 240
	},
	{
		"id": "boss_no_loss_secret",
		"title": "Untouched Victory",
		"description": "Defeat a boss in a wave where no trophy was lost.",
		"category": "secrets",
		"hidden": true,
		"event": "boss_defeated",
		"condition": "boss_wave_without_trophy_loss",
		"target": 1,
		"reward_essence": 0,
		"cosmetic_reward_id": "untouched_enemy_camp_skin",
		"cosmetic_reward_type": "enemy_camp_skin",
		"display_order": 250
	},
	{
		"id": "final_skeleton_secret",
		"title": "The Last Stand",
		"description": "Defeat the Skeleton Boss after all its resurrection stages.",
		"category": "secrets",
		"hidden": true,
		"event": "boss_defeated",
		"condition": "final_skeleton_death",
		"target": 1,
		"reward_essence": 20,
		"display_order": 260
	},
	{
		"id": "endless_secret",
		"title": "Beyond the End",
		"description": "Complete wave 200.",
		"category": "secrets",
		"hidden": true,
		"event": "wave_completed",
		"target": 200,
		"reward_essence": 0,
		"cosmetic_reward_id": "endless_emblem",
		"cosmetic_reward_type": "emblem",
		"display_order": 270
	}
]

const CATEGORY_NAMES: Dictionary = {
	"combat": "Combat",
	"waves": "Waves",
	"bosses": "Bosses",
	"bestiary": "Bestiary",
	"crystals": "Crystals",
	"towers": "Towers",
	"essence": "Essence",
	"trophies": "Trophies",
	"secrets": "Secrets"
}


const COSMETIC_TYPE_NAMES: Dictionary = {
	"user_avatar": "Avatars",
	"profile_frame": "Profile Frames",
	"emblem": "Emblems",
	"tower_skin": "Tower Skins",
	"castle_skin": "Castle Skins",
	"enemy_camp_skin": "Enemy Camp Skins",
	"enemy_skin": "Enemy Skins"
}

# Optional human-readable cosmetic names; the ID is displayed when absent.
const COSMETIC_NAMES: Dictionary = {}


static func get_category_name(category_id: String) -> String:
	return String(CATEGORY_NAMES.get(category_id, category_id.capitalize()))


static func get_cosmetic_type_name(cosmetic_type: String) -> String:
	return String(COSMETIC_TYPE_NAMES.get(
		cosmetic_type,
		cosmetic_type.replace("_", " ").capitalize()
	))


static func get_cosmetic_name(cosmetic_id: String) -> String:
	return String(COSMETIC_NAMES.get(cosmetic_id, cosmetic_id))


static func get_reward_summary(definition: Dictionary) -> String:
	var parts: Array[String] = []
	var essence := int(definition.get("reward_essence", 0))
	if essence > 0:
		parts.append("%d Essence" % essence)
	var cosmetic_id := String(definition.get("cosmetic_reward_id", ""))
	if not cosmetic_id.is_empty():
		parts.append("%s: %s" % [
			get_cosmetic_type_name(
				String(definition.get("cosmetic_reward_type", ""))
			),
			get_cosmetic_name(cosmetic_id)
		])
	return " + ".join(parts) if not parts.is_empty() else "No reward"
