# Development

## Rebuild release 1.0.2

The repository now includes an offline build entry point and hash-locked transformation recipes. It reads game resources locally, applies RainbowBlood's material and shader edits, reconstructs the four resource containers, compiles Reforge from Rust, and verifies all 410 output files before packaging. It does not install anything or launch the game. The released RainbowBlood ZIP is **not** a build input.

Required on Windows x64:

- Python 3.10 or later.
- A legally installed, matching Darktide build, including its own Oodle 9 DLL. Every used resource is SHA256 checked; a different game revision may fail deliberately.
- The original Polychromatic 3.0.0 ZIP, or its extracted `Polychromatic` folder. Seven compatibility shader inputs are read and checked. This is a **build dependency**; players do not need Polychromatic to use RainbowBlood.
- Windows SDK 10.0.26100.0 x64 DXC (`dxc.exe`, `dxcompiler.dll`, `dxil.dll`). The DXC executable is pinned by SHA256 and each compiled shader must match its expected hash.
- Rust 1.97.1, commit `8bab26f4f68e0e26f0bb7960be334d5b520ea452`, on `x86_64-pc-windows-msvc`, plus the MSVC compiler/linker and Windows SDK. Cargo dependencies are locked in Cargo.lock. Cargo needs its dependency cache or network access.

From the repository root, replacing the three input paths:

```powershell
python tools/build_release.py --game "D:/SteamLibrary/steamapps/common/Warhammer 40,000 DARKTIDE" --polychromatic "D:/Downloads/Polychromatic" --dxc "C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/dxc.exe" --output "dist/rebuild-1.0.2"
```

The output directory must not exist and cannot be inside the game directory. Failed builds retain partial output for inspection; use a new output directory when retrying. Build scratch files are temporary and stay outside the install package. Nothing is written into the supplied game or third-party input directories.

The builder regenerates 388 material streams and four format-8 containers from local inputs. Recipe files contain edit instructions and hashes, not compressed shader binaries or complete retail payloads. Unchanged game instructions and bytes are copied from local inputs. The Polychromatic Chinese patch is unrelated and excluded.

Reforge must be built as the **whole Cargo workspace**, without `-p reforge` or an explicit `--target`: workspace feature unification affects code layout. The builder restores only the original PE timestamps and CodeView GUID, then requires the entire DLL hash to match. It never patches executable instructions to conceal a compiler mismatch. Different compiler/linker/dependency paths may prevent byte identity; a hash failure is not a successful release build. The harness executable is compiled but never run or packaged.

A completed build prints separate results for payload equality and ZIP-byte equality. All 410 uncompressed files must match. ZIP bytes can also depend on the Python/zlib version even when the installed files are identical.

Verify an existing extracted package without loading Oodle/DXC or running Cargo:

```text
python tools/build_release.py --verify "D:/Extracted/RainbowBlood"
```

## Offline checks

```text
python tests/build_release_test.py
lua tests/release_localization_test.lua src/RainbowBlood
lua tests/chain_attack_colour_test.lua src/RainbowBlood/scripts/mods/RainbowBlood/chain_attack_colour.lua
```

Use Lua 5.1 and `luac -p` for runtime syntax. Offline checks and successful builds are not new game tests.

## Editing

`release/1.0.2.json` describes the immutable published release. The recipes reconstruct that release and intentionally reject different output. To develop changed visuals, update transformation logic/recipes and the expected output contract deliberately; do not disable verification to label changed output as the old release. Runtime Lua remains under `src/RainbowBlood`; Reforge remains under `native/reforge`.

Preserve native particle shape, timing, movement, lifetime, alpha and spawn arguments when changing colour. Keep startup conflict safeguards and failure cleanup. Do not commit game assets, generated payloads, credentials, personal logs, probes or local settings. Do not change licensing or add automatic jobs without the owner's request.
