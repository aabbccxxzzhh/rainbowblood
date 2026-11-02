-- Startup only. One loader owns each shared wound/burn file; no file writers,
-- commands, timers, gameplay polling, or changes to the other mod's files.
return function(mod, reforge)
    local mapping = mod:io_dofile("RainbowBlood/scripts/mods/RainbowBlood/polychromatic_map")
    local other = rawget(_G, "__asset_redirect_instance")
    local listed = type(other) == "table"
    for _, entry in ipairs(Managers and Managers.mod and Managers.mod._mods or {}) do
        if entry.name == "Polychromatic" and entry.enabled ~= false then listed = true end
    end
    if not listed then return reforge end

    local pending, original_specs, poly_originals = {}, {}, {}
    local api, saved_register, wrapped_register, finished, released
    local own_folder = mod:get_internal_data("load_order_name") or mod:get_name()
    local function proxy(owner)
        return setmetatable({
            get_name = function() return owner:get_name() end,
            get_internal_data = function(_, key)
                if key == "load_order_name" then return own_folder end
                return owner:get_internal_data(key)
            end,
        }, { __index = owner })
    end
    local function copy(spec)
        local result = {}; for k,v in pairs(spec) do result[k] = v end; return result
    end
    local release_owner = proxy(mod)
    -- The third-party library normally adds diagnostics to each registering mod.
    -- RainbowBlood's release deliberately exposes no diagnostic commands.
    release_owner.command = function() end
    local function native_hash(path)
        local ffi = Mods and Mods.lua and Mods.lua.ffi
        local lib = other and other.native
        if not ffi or not lib then return nil end
        local out = ffi.new("char[?]", 128)
        if lib.AssetRedirect_HashFile(path, out, 128) == 1 then return ffi.string(out):lower() end
    end
    local function install_bridge()
        if finished or released then return end
        other = rawget(_G, "__asset_redirect_instance")
        if type(other) ~= "table" or type(other.files) ~= "table" then
            -- Polychromatic has no active shared module (or failed to load).
            for stock, handle in pairs(pending) do handle.native = reforge.register(mod, original_specs[stock]) end
            finished = true; return
        end
        local shared = false
        for stock in pairs(pending) do
            local file = other.files[stock:sub(8)]
            for _,reg in ipairs(file and file.regs or {}) do
                if reg.owner == "Polychromatic" then shared = true end
            end
        end
        if not shared then
            for stock,handle in pairs(pending) do handle.native = reforge.register(mod, original_specs[stock]) end
            finished = true; return
        end
        if other.native_state == "pending" then return end
        if other.native_state ~= "ready" or not other.core then
            for _, handle in pairs(pending) do handle.error = "Polychromatic's resource loader is unavailable" end
            finished = true; return
        end
        api = other.core
        saved_register = api.register
        local supported = {}
        for stock, item in pairs(mapping) do
            local file = other.files[stock:sub(8)]
            for _, reg in ipairs(file and file.regs or {}) do
                if reg.owner == "Polychromatic" and reg.mod and reg.spec then
                    local folder = reg.mod:get_internal_data("load_order_name") or reg.mod:get_name()
                    if native_hash("mods/" .. folder .. "/" .. reg.spec.file) == item.poly_sha256 then
                        if other.native.AssetRedirect_Opens(stock:sub(8)) > 0 then
                            pending[stock].restart = true
                        else supported[stock] = true end
                    else
                        pending[stock].error = "Unsupported Polychromatic burn material; compatibility update required"
                    end
                end
            end
        end
        wrapped_register = function(owner, spec, version)
            local stock = type(spec) == "table" and ("bundle/" .. tostring(spec.stock))
            if supported[stock] and owner:get_name() == "Polychromatic" then
                poly_originals[stock] = { mod = owner, spec = copy(spec), version = version }
                local joint = copy(spec); joint.file = mapping[stock].file; joint.late = true
                return saved_register(proxy(owner), joint, version)
            end
            return saved_register(owner, spec, version)
        end
        api.register = wrapped_register
        for stock, handle in pairs(pending) do
            local item, short = mapping[stock], stock:sub(8)
            local file = other.files[short]
            if not handle.error and supported[stock] then
                local registrations = {}; for _,reg in ipairs(file.regs) do registrations[#registrations+1] = reg end
                for _,reg in ipairs(registrations) do
                    if reg.owner == "Polychromatic" then wrapped_register(reg.mod, reg.spec, other.core_version) end
                end
                handle.foreign = saved_register(release_owner, {stock=short, file=item.file, sha256=item.sha256, late=true}, other.core_version)
            elseif not handle.error and not handle.restart then
                handle.native = reforge.register(mod, original_specs[stock])
            end
        end
        finished = true
    end
    local adapter = setmetatable({}, { __index = reforge })
    function adapter.register(owner, spec)
        if owner ~= mod or not mapping[spec.stock] then return reforge.register(owner, spec) end
        original_specs[spec.stock] = spec
        local handle = pending[spec.stock]
        if not handle then handle = { stock = spec.stock, rb_poly = true }; pending[spec.stock] = handle end
        return handle
    end
    function adapter.finish() install_bridge() end
    function adapter.state(handle)
        if not handle or not handle.rb_poly then return reforge.state(handle) end
        if handle.restart then return "restart_required" end
        if handle.error then return "refused" end
        if handle.native then return reforge.state(handle.native) end
        if handle.foreign then return api.state(handle.foreign) end
        return "pending"
    end
    function adapter.reason(handle)
        if not handle or not handle.rb_poly then return reforge.reason(handle) end
        return handle.error or (handle.foreign and handle.foreign.reason)
    end
    function adapter.status()
        local status = reforge.status()
        for stock,handle in pairs(pending) do
            status.rows[#status.rows+1] = stock .. " RainbowBlood=" .. adapter.state(handle)
        end
        return status
    end
    function adapter.clear(owner)
        if owner == mod then
            released = true
            if api then
                if api.register == wrapped_register then api.register = saved_register end
                api.clear(mod)
                for _,row in pairs(poly_originals) do saved_register(row.mod, row.spec, row.version) end
            end
        end
        return reforge.clear(owner)
    end
    return adapter
end
