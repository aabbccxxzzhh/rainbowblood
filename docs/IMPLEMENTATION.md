# How RainbowBlood changes blood colours

## Airborne splashes and gibbing

The airborne splashes do not all expose a reliable Lua material-colour parameter. This implementation uses prebuilt colour variants of selected original blood particle resources and their referenced materials.

1. Offline asset work identifies a particle's material references and colour inputs. Some RGB values are authored in particle ColourGraphs; others are in material constants or compiled shader operations.
2. Variants retarget those RGB paths and material references. Original emission timing, geometry, movement, lifetime and alpha are protected by the colour-only asset contracts. RGB brightness/Bloom controls are separate audited changes.
3. Lua selects the matching prebuilt variant when a supported blood effect is spawned, forwarding the original spawn arguments. It does not substitute a different particle shape just to change colour.
4. Reforge serves the generated files through runtime redirects. Removing the mod from the load order and restarting removes those redirects; the release does not need to permanently overwrite retail blood resources.

This covers the supported splatters used when gibbing enemies. It is not a single global gibbing-colour setting, and not every game effect is claimed as covered.

Read [exact_blood_map.lua](../src/RainbowBlood/scripts/mods/RainbowBlood/exact_blood_map.lua) for source-to-variant mappings, then the blood-effect routes in [RainbowBlood.lua](../src/RainbowBlood/scripts/mods/RainbowBlood/RainbowBlood.lua). The map includes resources such as `poxwalker_splatter_gib_torso_small_01` and head fountains.

## Related effects and multi-target hits

`chain_attack_colour.lua` supplies scoped colour context for related near/far chainsword effects. The main module manages random/sequential selection and the same/different multi-target option. Colour selection changes neither targets hit nor attack damage.

## Other blood paths

The main module also handles projection-decal colour and weapon blood colour/intensity callbacks. Wound colouring uses `wound_base_runtime.lua` and its mapping. Screen splashes use their own variants and a rainbow/vanilla/off control. These are separate render paths; success on one does not establish correct lighting or coverage on another.

## Polychromatic

`polychromatic_compat.lua` and `polychromatic_map.lua` coordinate seven overlapping wound/burn material replacements for the recorded supported build. Combined materials preserve both modifications. Unknown payloads and materials already opened too early retain safeguards; they are not forcibly replaced to hide a conflict.

## Shader and format helpers

The selected Python modules demonstrate stage/packet parsing, colour reference calculations and RGB-only shader transformations. `airborne_final_output.py` contains the accepted final-output brightness/Bloom shaping logic. Its only adaptation here is importing shared helpers from extracted `shader_common.py` instead of the historical builder.

This helper subset is not the full release asset-generation pipeline. Extracted native shaders, game textures, generated payloads and private captures are omitted.
