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
