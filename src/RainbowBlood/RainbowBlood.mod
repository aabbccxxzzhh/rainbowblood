return {
    run = function()
        new_mod("RainbowBlood", {
            mod_script = "RainbowBlood/scripts/mods/RainbowBlood/RainbowBlood",
            mod_data = "RainbowBlood/scripts/mods/RainbowBlood/RainbowBlood_data",
            mod_localization = function(mod)
                mod._rainbowblood_early_bootstrap = mod:io_dofile("RainbowBlood/scripts/mods/RainbowBlood/early_bootstrap")(mod)
                return mod:io_dofile("RainbowBlood/scripts/mods/RainbowBlood/RainbowBlood_localization")
            end,
        })
    end,
    packages = {},
}
