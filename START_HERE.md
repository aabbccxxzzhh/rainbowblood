# Start here

This curated public repository preserves the RainbowBlood 1.0.2 runtime text. Read README.md for installation and docs/IMPLEMENTATION.md for colour routing and asset changes.

This import is not a new runtime change, rebuilt binary or game test. Generated payloads are omitted. Read docs/CURRENT_STATE.json and docs/SOURCE_PROVENANCE.json before changing release identities or rebuilding assets.

Public import verification completed:15runtime textfiles match release;Lua syntax/localisation/attackscope and10Python helper checks pass;55GitHub blobs verified. No binary build, package, installation or game test was performed.

Account identity updated on 2026-11-02. Public documentation and Git author/committer metadata use the current account. A local-only private backup preserves recovery; do not merge the previous public history back into this repository. Runtime source and package identities are unchanged.

Remote identity verification passed: current visible history and tracked text contain no previous account identifier; all source provenance hashes are preserved. Old unreferenced commit views remain cached by GitHub; complete cache removal requires Support and is not claimed by this checkpoint.

## Reproducible build work — 2026-11-02

The owner requested completing the missing release build chain. Work is in progress. Acceptance requires regenerating the full 1.0.2 file set and comparing every file against the recorded release. Supplying the release ZIP as the build output is not a source rebuild. Generated game payloads remain local; no installation or game launch is authorized.

## Reproducible build completed — 2026-11-03

Latest status supersedes the earlier import limitation. `tools/build_release.py` rebuilds release 1.0.2 from local retail inputs, seven hash-checked Polychromatic 3.0.0 shader inputs and the included source/recipes. It reconstructs 388 material streams and four format-8 containers, compiles Reforge and restores only PE build metadata. Whole-workspace Cargo compilation is required for the original Windows feature unification.

An offline full build regenerated all 410 release files exactly. The generated 69,332,898-byte ZIP also matched the original SHA256 `60c78ebc7f95cc835d8f40cb95a7a2ffc90ee63ae4e4e56fe80264c9b8b56a5a`. The original RainbowBlood ZIP was used only to author/validate contracts; it is not an input to the build entry point. Four builder tests and the two existing Lua checks passed. Runtime and Rust source were not changed, nothing was installed and the game was not launched. Different game/toolchain revisions may fail and must not be called an identical build. Generated assets, binaries, logs and the unrelated Chinese patch remain excluded from Git.

A second full build from a clean Git export of `827737a` also matched all 410 files and the complete ZIP hash. No untracked checkout files were needed. Build instructions and evidence are published with the source.
