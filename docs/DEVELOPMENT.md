# Development

## Scope

Runtime text is preserved from RainbowBlood 1.0.2. Reforge Rust source and selected pure shader/format helpers are included. A full asset rebuild still needs the original staged generation process and matching locally obtained game references; the selected helpers alone do not reproduce the release ZIP.

Historical installers, machine-specific scripts, old diagnostic baselines and failed experiments are excluded. Copying `src/RainbowBlood` into the game does not supply the omitted payloads.

## Lua checks

With Lua 5.1 on PATH, from the repository root:

```text
lua tests/release_localization_test.lua src/RainbowBlood
lua tests/chain_attack_colour_test.lua src/RainbowBlood/scripts/mods/RainbowBlood/chain_attack_colour.lua
```

These are offline checks, not game tests. Use `luac -p` for runtime syntax checks.

## Native source

The `native/reforge` Cargo workspace includes the Windows-targeted rb.2 fork used during release development. A compatible Rust toolchain, Windows compiler/linker and Windows SDK are required. From that directory:

```text
cargo build --locked --release -p reforge --target x86_64-pc-windows-msvc
```

A newly built DLL is not assumed byte-identical to the released DLL and needs separate validation before packaging. Dependencies come from their declared upstream sources. No native binary or retail extraction is included.

## Python helpers

Use Python 3.10 or newer. No third-party Python package is required. Native Oodle decompression requires a compatible local DLL passed explicitly to the helper; it is not redistributed. Shader assembly and a complete game-compatible asset rebuild require external tooling not supplied by this subset.

## Contributions

Keep tests/probes outside runtime packages. Preserve native particle shape, timing, movement, lifetime, alpha and spawn arguments when changing colour. Retain startup conflict safeguards and failure cleanup. Record offline checks, builds, installation and actual user game acceptance separately.

Do not commit credentials, personal logs, recordings, extracted game files, generated payloads, local settings or the separately excluded Polychromatic Chinese patch. This publication adds no automatic workflows and does not launch the game.
