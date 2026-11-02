-- Dedicated RGB only. Native WoundMaterials still computes/applies every
-- position, radius, shape, scale, brightness and time. One native combined
-- wound mask has one stable hue per wounds_data; gibs reuse that same table.
return function(mod, choose, is_active, colour_revision, wrap_safe)
    local by_data = setmetatable({}, { __mode = "k" })
    local touched = setmetatable({}, { __mode = "k" })
    local applied_in = setmetatable({}, { __mode = "k" })
    local apply_serial = 0
    local EMPTY = {}
    local stats = { calculated = 0, applied = 0, inherited = 0, writes = 0, errors = 0,
        colour_calculations = 0, duplicate_writes_skipped = 0 }
    local parameter = "rainbowblood_wound_base"
    wrap_safe = wrap_safe or function(_, fn) return fn end
    local function write(unit, colour, vector, serial)
        if not unit or (Unit.alive and not Unit.alive(unit)) then return end
        if serial and applied_in[unit] == serial then
            stats.duplicate_writes_skipped = stats.duplicate_writes_skipped + 1
            return
        end
        local ok = pcall(Unit.set_vector4_for_materials, unit, parameter, vector or
            Quaternion.from_elements(colour[1], colour[2], colour[3], colour[4]), true)
        if ok then touched[unit] = true; stats.writes = stats.writes + 1
            if serial then applied_in[unit] = serial end
        else stats.errors = stats.errors + 1 end
    end
    local function colour(data, position)
        local state = by_data[data]
        local revision, reference
        if colour_revision then revision, reference = colour_revision() end
        local enabled = is_active() and 1 or 0
        if not state or not colour_revision or state.revision ~= revision
            or state.reference ~= reference or state.value[4] ~= enabled then
            local r, g, b, index = choose(state and state.index, position)
            if not state then state = { value = {} }; by_data[data] = state end
            state.index, state.revision, state.reference = index, revision, reference
            state.value[1], state.value[2], state.value[3], state.value[4] = r, g, b, enabled
            stats.colour_calculations = stats.colour_calculations + 1
        end
        return state.value, state
    end
    mod:hook_require("scripts/extension_systems/wounds/utilities/wound_materials", function(WoundMaterials)
        mod:hook_safe(WoundMaterials, "calculate", wrap_safe("WoundMaterials.calculate", function(unit, config, data, index, settings, shape, node, pose, position)
            if not is_active() then return end
            local value, state = colour(data, position)
            state.unit = state.unit or unit
            stats.calculated = stats.calculated + 1
            write(unit, value)
        end))
        mod:hook_safe(WoundMaterials, "apply", wrap_safe("WoundMaterials.apply", function(unit, data, index, slots)
            local state = by_data[data]
            if not state then return end
            local value = colour(data)
            stats.applied = stats.applied + 1
            if state.unit ~= unit then stats.inherited = stats.inherited + 1 end
            apply_serial = apply_serial + 1
            -- Temporary engine vectors are shared only during this callback,
            -- never retained across frames. Fresh applies always write again:
            -- unit materials may have been rebuilt without changing wound data.
            local vector = Quaternion.from_elements(value[1], value[2], value[3], value[4])
            local serial = apply_serial
            write(unit, value, vector, serial)
            for _, slot in pairs(slots or EMPTY) do
                if slot.unit and slot.state ~= "unequipped" then
                    write(slot.unit, value, vector, serial)
                    for _, attachment in ipairs(slot.attachments or EMPTY) do write(attachment, value, vector, serial) end
                end
            end
        end))
    end)
    local function reset(clear_alive)
        if clear_alive then
            for unit in pairs(touched) do write(unit, { 0, 0, 0, 0 }) end
        end
        by_data = setmetatable({}, { __mode = "k" })
        touched = setmetatable({}, { __mode = "k" })
        applied_in = setmetatable({}, { __mode = "k" })
        apply_serial = 0
    end
    
    return { reset = reset, stats = stats }
end
