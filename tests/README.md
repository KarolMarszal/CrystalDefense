# Regression tests

The suite uses GdUnit4 6.2.2 and was run with Godot 4.7.2. Before running the
suite, use an isolated project copy with a different `application/config/name`.
The `CrystalInventory` Autoload initializes its normal `user://` profile when
the runner starts, so running tests directly from the production project could
create or load that project's real profile. The profile tests themselves use
unique `user://gdunit-profile-tests/...` directories and remove their test
files afterward.

In the isolated copy, import the project once, then run the command-line runner
from the project directory:

```powershell
& "C:\path\to\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\path\to\isolated-project" --editor --import --quit
& "C:\path\to\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\path\to\isolated-project" -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" --ignoreHeadlessMode --continue -a "res://tests"
```

`--ignoreHeadlessMode` is required by GdUnit4 for headless test execution.
Tests that simulate UI input are not covered by this headless suite.

Essence reward coverage: per-enemy point values, once-only awards on death,
Skeleton resurrection, 5% round-up threshold growth with overflow and
multi-threshold awards, HUD progress text, profile save/load/legacy defaults,
HP (10%) and speed (0.5%) wave scaling, and the next-wave countdown
(spawn-queue guard, single start, pause/resume, manual cancellation).

The latest additions cover 300 starting run Gold and continuing-run retention,
the weakened uncrystalled tower configuration, five empty build slots and fixed
100 Gold construction, procedural wave-one generation, manual wave-one start,
the 10-second post-completion countdown and manual cancellation, pause/speed
state, Awakening's one-time Kinetic and Rapid Fire rewards and schema migration,
legacy Fire Mastery migration, and Elemental Master's Fire Mastery visibility
and immediate AoE effect. `test_bosses.gd` covers Tier 1 boss configuration and
scaling, per-boss regular-wave composition and budget limits, live WaveManager
summon tracking, pause/simulation-speed-aware ability processing, Orc damage
reduction and rewards, Skeleton lethal-hit resurrections, Goblin directional
buffs and trophy drops, Kobold speed boosts, Troll regeneration, Spider summon
limits, Ghoul escort healing and cleanup, and Snake tower-aura cleanup and
poison immunity.
No ordinary Spider or Snake is in the selectable wave roster, so those two
bosses have no regular accompanying enemy group; SpiderSummon remains exclusive
to Spider Matron's ability.

The temporary Spider Matron test boss on wave 1 and Spider-only test wave 2
are disabled by default. Set
`BossWaveSchedule.tier_one_test_waves_enabled` in
`waves/BossWaveSchedule.gd` to `true` to enable those test encounters.
`BossAbilityDebug.enabled` in `enemies/BossAbilityDebug.gd` centrally controls
the `[BOSS_ABILITY]` and `[DAMAGE]` logs. The Kobold Chief 5x HP test override
is also gated by the test-wave flag and currently has no effect because no
Kobold Chief is in the fixed test-wave mapping.
