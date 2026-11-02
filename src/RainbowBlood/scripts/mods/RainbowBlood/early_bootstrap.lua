-- Earliest supported DMFMod entry: called before localization/data initialization.
-- Registers only bundled file redirects; no game packages, worlds or particles.
return function(mod)
    local reforge = mod:io_dofile("RainbowBlood/scripts/mods/RainbowBlood/reforge")
    reforge = mod:io_dofile("RainbowBlood/scripts/mods/RainbowBlood/polychromatic_compat")(mod, reforge)
    local state = { reforge = reforge, handles = {} }
    function state.register_manifest(manifest)
        local handles = {}
        for pass = 1, 2 do
            for i, spec in ipairs(manifest.redirects) do
                if (spec.virtual == true) == (pass == 2) then
                    handles[i] = reforge.register(mod, spec)
                end
            end
        end
        return handles
    end
    local ok, manifest = pcall(mod.io_dofile, mod, "RainbowBlood/scripts/mods/RainbowBlood/reforge_manifest")
    if not ok then
        state.error = "Self-host manifest is missing. Reinstall or update RainbowBlood."
    elseif type(manifest) ~= "table" or manifest.schema ~= 1 or type(manifest.redirects) ~= "table" then
        state.error = "Self-host manifest is invalid. Reinstall or update RainbowBlood."
    elseif manifest.build_id ~= "wound-base.1-20261010" then
        state.error = "Self-host manifest belongs to a different RainbowBlood release. Reinstall or update RainbowBlood."
    else
        state.manifest = manifest
        state.handles = state.register_manifest(manifest)
        reforge.commit()
    end
    return state
end
