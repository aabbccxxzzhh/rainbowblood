# RainbowBlood

Rainbow-coloured blood for **Warhammer 40,000: Darktide**.

Recolours ground and wall blood, weapon blood, screen splashes, wounds, hit splashes and bleeding effects in seven colours.

## Install

Download the complete mod from [Nexus Mods](https://www.nexusmods.com/warhammer40kdarktide/mods/1517). Install Darktide Mod Loader and Darktide Mod Framework, extract `RainbowBlood` into `<Darktide>/mods/`, and add `RainbowBlood` to `mods/mod_load_order.txt`.

Reforge is bundled with the release; no separate installation is needed. Polychromatic is optional. Enable Gibbing and adjust the game's blood-related settings for the full effect. Remove the RainbowBlood load-order entry and restart the game to restore vanilla blood.

**This repository contains source, not a ready-to-install mod package.** GitHub's source ZIP omits generated game-dependent payloads and the native DLL.

## Settings

- Random or sequential colours.
- Different colours per target, or a shared colour for targets hit by one attack.
- Screen blood: rainbow, vanilla or off.
- Weapon blood: rainbow or vanilla, with configurable colour cycling.
- Bleeding-effect colouring.
- Settings translated into all 12 supported game languages.

## Source layout

| Folder | Contents |
| --- | --- |
| `src/RainbowBlood/` | The 15 runtime text files corresponding to release 1.0.2 |
| `native/reforge/` | Bundled Reforge source, including RainbowBlood startup fixes |
| `tools/shaders/` | Selected binary-format and shader-colour transformation helpers |
| `tests/` | Portable Lua checks for localisation and attack colour scope |
| `docs/` | Implementation, development and source-provenance notes |
| `LICENSES/` | Third-party license notices |

Start with [implementation details](docs/IMPLEMENTATION.md), [developer notes](docs/DEVELOPMENT.md) and [source provenance](docs/SOURCE_PROVENANCE.json).

## Known issues

On first installation, the first few attacks may stutter while resources and graphics pipelines are prepared; subsequent attacks normally run smoothly. This is not a measured guarantee for every GPU or driver.

Graphics-reduction settings can make blood blurry. A separate user comparison also reproduced blurry vanilla wall/ground blood with this mod disabled; that shared rendering issue has not been isolated to RainbowBlood.

The recorded Polychromatic compatibility target is the supplied 3.0.0 build; future builds may need a new compatibility audit.

## Credits and licensing

Includes modified Reforge by Vansinnet and contributors, licensed under MIT. See [the notices](THIRD_PARTY_NOTICES.md) and [full Reforge license](LICENSES/Reforge-MIT.txt).

No blanket license has been assigned to original RainbowBlood code by this source publication. Existing component licenses remain in effect. Game assets and trademarks belong to their respective owners. This is an unofficial mod.
