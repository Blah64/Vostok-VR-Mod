# Tests

Three independent suites cover the testable surface area of the VR mod:

| Suite      | Runner                          | What it covers                                                            |
|------------|---------------------------------|---------------------------------------------------------------------------|
| GDScript   | `run_gdscript_tests.bat`        | Pure helpers: zone math (holster/bag/NVG), `config_io` read/write/mutate. |
| C++        | `run_cpp_tests.bat`             | Pure helpers: command-line patcher idempotency.                           |
| Packaging  | `run_packaging_tests.bat`       | VMZ structure, forward-slash paths, native artifact freshness, no shadow. |

Run them all with `tests\run_all_tests.bat`. Each runner sets a nonzero exit
code on failure so CI can fan-in on `run_all_tests.bat`.

## Adding GDScript tests

Drop a `test_*.gd` file under `tests/gdscript/`, then register it in the
`SUITES` list at the top of `tests/gdscript/run_tests.gd`. Each test method
must be named `test_*` and take a single `t` argument (the test runner). Use
`t.assert_eq`, `t.assert_true`, `t.assert_near`, or `t.assert_vec_near`.

GDScript tests run via `Godot --headless`. The Godot binary path is
hard-coded in `run_gdscript_tests.bat` at:

```
C:\Games\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe
```

Edit the path at the top of the .bat if your install differs.

## Adding C++ tests

Drop a `test_*.cpp` file under `tests/cpp/` that exposes `int main()`. Add an
`add_executable` + `add_test` pair in `tests/CMakeLists.txt`. Each test ships
its own assertion harness (no Catch2 / GoogleTest dependency) so the test
target builds without any external pull.

The `cmake.exe` path in `run_cpp_tests.bat` defaults to the Visual Studio
2022 BuildTools install. Edit if needed.

## Adding packaging tests

Append to `tests/packaging/test_packaging.ps1`. The script walks the VMZ via
`System.IO.Compression.ZipArchive`, asserts entry paths, and verifies that
native DLLs are at least as new as their C/C++ sources. Run AFTER `build.bat`
so the artifacts exist.

## What is NOT covered

- VR runtime behaviour (XR hands, haptics, weapon sync, OpenXR session).
  These need the live game and an HMD — see CLAUDE.md "smoke test" notes.
- Hooked `GetCommandLineW` execution (only the pure logic is tested; the
  MinHook path runs only inside the host process).
- Metro Mod Loader autoload mounting. The packaging suite asserts the VMZ
  is well-formed; actual load is verified by launching the game.
