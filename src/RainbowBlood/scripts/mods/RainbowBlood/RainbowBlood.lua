local mod = get_mod("RainbowBlood")
local bootstrap = mod._rainbowblood_early_bootstrap or mod:io_dofile("RainbowBlood/scripts/mods/RainbowBlood/early_bootstrap")(mod)
mod._rainbowblood_early_bootstrap = nil
local reforge = bootstrap.reforge

local SELF_HOST_BUILD_ID = "wound-base.1-20261010"

local EXACT_BLOOD_MAP_PATH = "RainbowBlood/scripts/mods/RainbowBlood/exact_blood_map"
local WOUND_GRADIENT_MAP_PATH = "RainbowBlood/scripts/mods/RainbowBlood/wound_gradient_map"
local SCREEN_BLOOD_SOURCE = "content/fx/particles/screenspace/screen_blood_splatter"
local BLEED_DOT_SOURCE = "content/fx/particles/enemies/buff_bleeding"
local SELF_HOST_PACKAGE = "content/fx/particles/debug/flame_thrower_test"

local self_host_manifest = bootstrap.manifest
local self_host_handles = bootstrap.handles
local self_host_manifest_error = bootstrap.error
local register_self_host_manifest = bootstrap.register_manifest

local active = true
local sequence = 0

local settings = {

    mode = "random",
    colour_order_mode = "palette_sequence",
    multi_target_blood_colour = "different",
    colorize_screen_blood = true,
    screen_blood_mode = "rainbow",
    colorize_bleed_dot = true,
    speed = 0.45,
    saturation = 1.0,
    brightness = 1.0,
    sync_window = 0.12,
    colorize_decals = true,
    colorize_weapon_blood = true,
    weapon_blood_mode = "hit_count",
    weapon_cycle_n = 2,
    enable_poxwalker_spray = true,
    spray_palette = "l4d2_source_gradient",
}

local stats = {
    decals = 0,
    weapon_refreshes = 0,
    weapon_material_writes = 0,
    weapon_material_errors = 0,
    weapon_region_max = 0,
    blood_particle_calls = 0,
    bleed_dot_seen = 0,
    bleed_dot_replaced = 0,
    bleed_dot_last_palette = "none",
    bleed_dot_last_target = "none",
}

local seen_effects = {}
local weapon_states = setmetatable({}, { __mode = "k" })

local Items = require("scripts/utilities/items")

local exact_blood_map = { schema = 1, build_id = SELF_HOST_BUILD_ID, expected_resources = 42, special_source_count = 0, unresolved_count = 0, entries = {}, dependencies = {}, unresolved = {} }
do
    local ok, result = pcall(function()
        return mod:io_dofile(EXACT_BLOOD_MAP_PATH)
    end)
    if not ok then
        self_host_manifest_error = self_host_manifest_error or "Exact blood resource map is missing. Run the RC7.9 developer builder before launching."
    elseif type(result) ~= "table" or result.schema ~= 1 or result.build_id ~= SELF_HOST_BUILD_ID then
        self_host_manifest_error = self_host_manifest_error or "Exact blood resource map belongs to a different RainbowBlood release. Run the RC7.9 developer builder before launching."
    else
        exact_blood_map = result
    end
end

local wound_gradient_map = { schema = 1, build_id = SELF_HOST_BUILD_ID, expected_textures = 0, channel = "effect_gradient", textures = {} }
do
    local ok, result = pcall(function()
        return mod:io_dofile(WOUND_GRADIENT_MAP_PATH)
    end)
    if not ok then
        self_host_manifest_error = self_host_manifest_error or "Wound gradient resource map is missing. Run the RC7.9 developer builder before launching."
    elseif type(result) ~= "table" or result.schema ~= 1 or result.build_id ~= SELF_HOST_BUILD_ID then
        self_host_manifest_error = self_host_manifest_error or "Wound gradient map belongs to a different RainbowBlood release. Run the RC7.9 developer builder before launching."
    elseif type(result.textures) ~= "table" or #result.textures ~= 0 or result.channel ~= "effect_gradient" then
        self_host_manifest_error = self_host_manifest_error or "Wound gradient map is invalid. Run the RC7.9 developer builder again."
    else
        wound_gradient_map = result
    end
end

local precompiled_mono = {
    ready = false,
    loading = false,
    error = self_host_manifest_error,
    replacements = 0,
    fallbacks = 0,
    available_resources = 0,
    expected_resources = exact_blood_map.expected_resources or 42,
    available_wound_textures = 0,
    expected_wound_textures = wound_gradient_map.expected_textures or 0,
    host_package = SELF_HOST_PACKAGE,
    dependency_packages = {},
    assets = {
        [1] = { name = "red", standard = "content/mods/rainbow_blood/colour_only/red/770dbf9c20079947", reduced = "content/mods/rainbow_blood/colour_only/red/04ad0c6cfe1b7c6b", small = "content/mods/rainbow_blood/colour_only/red/740792e4db62501d", weakspot = "content/mods/rainbow_blood/colour_only/red/b8cea2f9003dcd8f", melee = "content/mods/rainbow_blood/colour_only/red/6bc508488bf0f8bc", ranged = "content/mods/rainbow_blood/colour_only/red/2cf76c6abdc2b9b9", chainsword_generic = "content/mods/rainbow_blood/mono/red/chainsword_loop_generic", chainsword_poxwalker = "content/mods/rainbow_blood/mono/red/chainsword_loop_poxwalker" },
        [2] = { name = "orange", standard = "content/mods/rainbow_blood/colour_only/orange/770dbf9c20079947", reduced = "content/mods/rainbow_blood/colour_only/orange/04ad0c6cfe1b7c6b", small = "content/mods/rainbow_blood/colour_only/orange/740792e4db62501d", weakspot = "content/mods/rainbow_blood/colour_only/orange/b8cea2f9003dcd8f", melee = "content/mods/rainbow_blood/colour_only/orange/6bc508488bf0f8bc", ranged = "content/mods/rainbow_blood/colour_only/orange/2cf76c6abdc2b9b9", chainsword_generic = "content/mods/rainbow_blood/mono/orange/chainsword_loop_generic", chainsword_poxwalker = "content/mods/rainbow_blood/mono/orange/chainsword_loop_poxwalker" },
        [3] = { name = "yellow", standard = "content/mods/rainbow_blood/colour_only/yellow/770dbf9c20079947", reduced = "content/mods/rainbow_blood/colour_only/yellow/04ad0c6cfe1b7c6b", small = "content/mods/rainbow_blood/colour_only/yellow/740792e4db62501d", weakspot = "content/mods/rainbow_blood/colour_only/yellow/b8cea2f9003dcd8f", melee = "content/mods/rainbow_blood/colour_only/yellow/6bc508488bf0f8bc", ranged = "content/mods/rainbow_blood/colour_only/yellow/2cf76c6abdc2b9b9", chainsword_generic = "content/mods/rainbow_blood/mono/yellow/chainsword_loop_generic", chainsword_poxwalker = "content/mods/rainbow_blood/mono/yellow/chainsword_loop_poxwalker" },
        [4] = { name = "green", standard = "content/mods/rainbow_blood/colour_only/green/770dbf9c20079947", reduced = "content/mods/rainbow_blood/colour_only/green/04ad0c6cfe1b7c6b", small = "content/mods/rainbow_blood/colour_only/green/740792e4db62501d", weakspot = "content/mods/rainbow_blood/colour_only/green/b8cea2f9003dcd8f", melee = "content/mods/rainbow_blood/colour_only/green/6bc508488bf0f8bc", ranged = "content/mods/rainbow_blood/colour_only/green/2cf76c6abdc2b9b9", chainsword_generic = "content/mods/rainbow_blood/mono/green/chainsword_loop_generic", chainsword_poxwalker = "content/mods/rainbow_blood/mono/green/chainsword_loop_poxwalker" },
        [5] = { name = "cyan", standard = "content/mods/rainbow_blood/colour_only/cyan/770dbf9c20079947", reduced = "content/mods/rainbow_blood/colour_only/cyan/04ad0c6cfe1b7c6b", small = "content/mods/rainbow_blood/colour_only/cyan/740792e4db62501d", weakspot = "content/mods/rainbow_blood/colour_only/cyan/b8cea2f9003dcd8f", melee = "content/mods/rainbow_blood/colour_only/cyan/6bc508488bf0f8bc", ranged = "content/mods/rainbow_blood/colour_only/cyan/2cf76c6abdc2b9b9", chainsword_generic = "content/mods/rainbow_blood/mono/cyan/chainsword_loop_generic", chainsword_poxwalker = "content/mods/rainbow_blood/mono/cyan/chainsword_loop_poxwalker" },
        [6] = { name = "blue", standard = "content/mods/rainbow_blood/colour_only/blue/770dbf9c20079947", reduced = "content/mods/rainbow_blood/colour_only/blue/04ad0c6cfe1b7c6b", small = "content/mods/rainbow_blood/colour_only/blue/740792e4db62501d", weakspot = "content/mods/rainbow_blood/colour_only/blue/b8cea2f9003dcd8f", melee = "content/mods/rainbow_blood/colour_only/blue/6bc508488bf0f8bc", ranged = "content/mods/rainbow_blood/colour_only/blue/2cf76c6abdc2b9b9", chainsword_generic = "content/mods/rainbow_blood/mono/blue/chainsword_loop_generic", chainsword_poxwalker = "content/mods/rainbow_blood/mono/blue/chainsword_loop_poxwalker" },
        [7] = { name = "purple", standard = "content/mods/rainbow_blood/colour_only/purple/770dbf9c20079947", reduced = "content/mods/rainbow_blood/colour_only/purple/04ad0c6cfe1b7c6b", small = "content/mods/rainbow_blood/colour_only/purple/740792e4db62501d", weakspot = "content/mods/rainbow_blood/colour_only/purple/b8cea2f9003dcd8f", melee = "content/mods/rainbow_blood/colour_only/purple/6bc508488bf0f8bc", ranged = "content/mods/rainbow_blood/colour_only/purple/2cf76c6abdc2b9b9", chainsword_generic = "content/mods/rainbow_blood/mono/purple/chainsword_loop_generic", chainsword_poxwalker = "content/mods/rainbow_blood/mono/purple/chainsword_loop_poxwalker" },
    },
}

for i = 1, #(exact_blood_map.dependencies or {}) do
    precompiled_mono.dependency_packages[#precompiled_mono.dependency_packages + 1] = exact_blood_map.dependencies[i]
end

local unresolved_exact_blood = {}
for i = 1, #(exact_blood_map.unresolved or {}) do
    local row = exact_blood_map.unresolved[i]
    if type(row) == "table" and type(row.source) == "string" then
        unresolved_exact_blood[row.source] = row.reason or "unresolved"
    end
end

local function exact_blood_targets(effect_name)
    if type(effect_name) ~= "string" then
        return nil
    end
    return exact_blood_map.entries and exact_blood_map.entries[effect_name] or nil
end

local function precompiled_effect_for(effect_name, colour_index, known_targets)
    if not precompiled_mono.ready then
        return nil
    end

    local row = precompiled_mono.assets[colour_index]
    if not row or type(effect_name) ~= "string" then
        return nil
    end

    local exact = known_targets or exact_blood_targets(effect_name)
    if exact then
        return exact[colour_index]
    end

    return nil
end

local function self_host_states()
    local counts = {}
    for i = 1, #self_host_handles do
        local state = reforge.state(self_host_handles[i])
        counts[state] = (counts[state] or 0) + 1
    end
    return counts
end

local function self_host_summary()
    if #self_host_handles == 0 then
        return "manifest-not-built"
    end
    local counts = self_host_states()
    local parts = {}
    for _, state in ipairs({ "active", "shared", "compatible", "displaced", "refused", "restart_required", "unavailable", "pending" }) do
        if counts[state] then
            parts[#parts + 1] = state .. "=" .. counts[state]
        end
    end
    return table.concat(parts, ", ")
end

local function all_self_host_redirects_served()
    if #self_host_handles == 0 then
        return false
    end
    for i = 1, #self_host_handles do
        if not reforge.served(reforge.state(self_host_handles[i])) then
            return false
        end
    end
    return true
end

local startup_error_reported = false
local function report_asset_error()
    if precompiled_mono.error and not startup_error_reported then
        startup_error_reported = true
        mod:error(precompiled_mono.error)
    end
end

local function self_host_failure_message()
    local details, failed, restart_only = {}, 0, true
    local status = reforge.status()
    for i = 1, #self_host_handles do
        local handle = self_host_handles[i]
        local state = reforge.state(handle)
        if not reforge.served(state) then
            failed = failed + 1
            restart_only = restart_only and state == "restart_required"
            if #details < 3 then
                local stock = handle.stock or "unknown"
                local detail = state .. ": " .. stock
                for _, row in ipairs(status.rows or {}) do
                    if row:sub(1, #stock + 1) == stock .. " " then detail = state .. ": " .. row; break end
                end
                local reason = reforge.reason(handle)
                if reason then detail = detail .. " reason=" .. tostring(reason) end
                details[#details + 1] = detail
            end
        end
    end
    if failed > #details then details[#details + 1] = tostring(failed - #details) .. " more affected resources" end
    local hint = restart_only and failed > 0
        and "Restart required: a resource was opened before its current replacement was registered. Close and restart the game."
        or "Resource replacement failed. Check the resource details below and the RainbowBlood installation."
    return "RainbowBlood self-host redirects are not all served: " .. self_host_summary() .. ". " .. hint .. " Details: " .. table.concat(details, "; ")
end

local function precompiled_resource_available(resource_type, name)
    if not Application or type(Application.can_get_resource) ~= "function" then
        return false
    end
    local ok, value = pcall(Application.can_get_resource, resource_type, name)
    return ok and value == true
end

local RESOURCE_CHECK_INTERVAL = 0.1
local pending_resources, next_resource_check = nil, 0
local requested_packages = {}
local package_load_failed = false

local function prepare_resource_checks()
    pending_resources = {}
    precompiled_mono.available_resources = 0
    precompiled_mono.available_wound_textures = 0
    next_resource_check = 0
    for _, targets in pairs(exact_blood_map.entries or {}) do
        for i = 1, #targets do
            pending_resources[#pending_resources + 1] = { "particles", targets[i] }
        end
    end
    for _, name in ipairs(wound_gradient_map.textures or {}) do
        pending_resources[#pending_resources + 1] = { "texture", name }
    end
end

local function refresh_precompiled_assets()
    if not precompiled_mono.loading then
        return
    end
    local now = Application.time_since_launch()
    if now < next_resource_check then return end
    next_resource_check = now + RESOURCE_CHECK_INTERVAL

    -- A ready resource stays resident while our package references are held.
    -- Only retry missing resources; reset the list on a new load or release.
    for i = #pending_resources, 1, -1 do
        local entry = pending_resources[i]
        if precompiled_resource_available(entry[1], entry[2]) then
            if entry[1] == "particles" then
                precompiled_mono.available_resources = precompiled_mono.available_resources + 1
            else
                precompiled_mono.available_wound_textures = precompiled_mono.available_wound_textures + 1
            end
            pending_resources[i] = pending_resources[#pending_resources]
            pending_resources[#pending_resources] = nil
        end
    end

    if precompiled_mono.available_resources == precompiled_mono.expected_resources
        and precompiled_mono.available_wound_textures == precompiled_mono.expected_wound_textures then
        precompiled_mono.loading = false
        precompiled_mono.ready = true
        precompiled_mono.error = nil
        pending_resources = nil
    end
end

local function unload_precompiled_package(package_name)
    if type(package_name) ~= "string" or package_name == "" then
        return
    end

    local ok_status, status = pcall(mod.package_status, mod, package_name)
    if not ok_status or status == nil then
        return
    end

    local ok, err = pcall(mod.unload_package, mod, package_name)
    if not ok then
        mod:error("RainbowBlood failed to release package " .. tostring(package_name) .. ": " .. tostring(err))
    end
end

local function release_precompiled_assets()
    precompiled_mono.ready = false
    precompiled_mono.loading = false
    pending_resources = nil
    next_resource_check = 0
    precompiled_mono.available_resources = 0
    precompiled_mono.available_wound_textures = 0
    -- Release only references this startup actually requested, host first.
    for i = #requested_packages, 1, -1 do
        local package_name = requested_packages[i]
        requested_packages[i] = nil
        unload_precompiled_package(package_name)
    end
end

local function request_precompiled_package(package_name)
    local ok, err = pcall(mod.load_package, mod, package_name)
    if ok then
        local ok_status, status = pcall(mod.package_status, mod, package_name)
        if ok_status and (status == "loading" or status == "loaded") then
            requested_packages[#requested_packages + 1] = package_name
            return true
        end
        err = ok_status and "the package request was not accepted" or tostring(status)
    end
    package_load_failed = true
    release_precompiled_assets()
    precompiled_mono.error = "Failed to load RainbowBlood package " .. tostring(package_name) .. ": " .. tostring(err)
    report_asset_error()
    return false
end

local redirects_waiting_since, next_redirect_check = nil, 0
local function acquire_precompiled_assets()
    if precompiled_mono.ready or precompiled_mono.loading or package_load_failed then
        return
    end
    local now = Application.time_since_launch()

    if self_host_manifest_error then
        precompiled_mono.error = self_host_manifest_error
        report_asset_error()
        return
    end

    if reforge.finish then reforge.finish() end
    reforge.commit()
    -- Keep the shared-loader handover prompt; only throttle status scans.
    if redirects_waiting_since and now < next_redirect_check then return end
    if not all_self_host_redirects_served() then
        local pending = false
        for _,handle in ipairs(self_host_handles) do
            if reforge.state(handle) == "pending" then pending = true end
        end
        if pending then
            redirects_waiting_since = redirects_waiting_since or now
            if now - redirects_waiting_since < 15 then
                next_redirect_check = now + RESOURCE_CHECK_INTERVAL
                return
            end
        end
        redirects_waiting_since = nil
        precompiled_mono.error = self_host_failure_message()
        report_asset_error()
        return
    end

    redirects_waiting_since = nil
    for i = 1, #precompiled_mono.dependency_packages do
        if not request_precompiled_package(precompiled_mono.dependency_packages[i]) then return end
    end

    if not request_precompiled_package(precompiled_mono.host_package) then return end

    prepare_resource_checks()
    precompiled_mono.loading = true
    precompiled_mono.error = nil
    refresh_precompiled_assets()
end

local GFX_CHAINSWORD_LOOP = "content/fx/particles/impacts/flesh/blood_chainsword_loop_01"
local PFX_CHAINSWORD_LOOP = "content/fx/particles/impacts/flesh/poxwalker_blood_chainsword_loop_01"

local spray_shuffle_bypass = 0

local test_forced_palette_entry = nil

local colour_rng_state = (os.time() % 2147483646) + 1
local function colour_random(first, last)
    colour_rng_state = (colour_rng_state * 48271) % 2147483647
    local value = (colour_rng_state - 1) / 2147483646
    if first == nil then return value end
    if last == nil then last = first; first = 1 end
    return first + math.floor(value * (last - first + 1))
end

local source_palette = {
    { name = "red", h = 0.992287664, s = 0.621622000, v = 0.545098039, decal_h = 0.009426861, decal_s = 1.000000000, decal_v = 1.112000178 },
    { name = "orange", h = 0.075075075075, s = 0.877470355732, v = 0.992156862745, decal_h = 0.040404040404, decal_s = 0.990000000000, decal_v = 3.200000000000 },
    { name = "yellow", h = 0.166666667, s = 0.820000000, v = 0.650000000, decal_h = 0.166666667, decal_s = 1.000000000, decal_v = 2.300000000 },
    { name = "green", h = 0.350894131, s = 0.773050000, v = 0.509803922, decal_h = 0.336111111, decal_s = 1.000000000, decal_v = 1.040000166 },
    { name = "cyan", h = 0.508776467, s = 0.647482000, v = 0.568627451, decal_h = 0.486111111, decal_s = 0.892475430, decal_v = 1.160000186 },
    { name = "blue", h = 0.656019189, s = 0.527027000, v = 0.600000000, decal_h = 0.6666666666666666, decal_s = 1.000000000, decal_v = 1.224000196 },
    { name = "purple", h = 0.836847828, s = 0.780335500, v = 0.560784314, decal_h = 0.750000000, decal_s = 1.000000000, decal_v = 1.144000183 },
}

local reference_palette_index = nil

local palette_hues = {}
for i = 1, #source_palette do
    palette_hues[i] = source_palette[i].h
end

local weapon_hues = palette_hues

local chain_attack_colour = nil
local mono = {
    colours = {
        { name = "red",    r = 1.22,  g = 0.00, b = 0.055 },
        { name = "orange", r = 2.50,  g = 0.916666667, b = 0.00 },
        { name = "yellow", r = 4.00,  g = 4.00, b = 0.00 },
        { name = "green",  r = 0.00,  g = 1.22, b = 0.025 },
        { name = "cyan",   r = 0.00,  g = 1.18, b = 1.30 },
        { name = "blue",   r = 0.035, g = 0.09, b = 1.34 },
        { name = "purple", r = 1.30,  g = 0.00, b = 1.27 },
    },
    bag = {},
    cursor = 1,
    last_index = nil,
    event_count = 0,
    last_name = "none",

    same_event_window = 0.0025,
    same_event_radius_sq = 0.08 * 0.08,
    recent_events = {},
    max_recent_events = 24,

    stats = {
        selected = 0,
        reused_same_event = 0,
        recoloured_particles = 0,
        cloud_matches = 0,
        cloud_sets = 0,
        cloud_set_errors = 0,
        no_cloud_map = 0,
        no_cloud_match = 0,
    },
}

function mono.refill()
    local bag = {}
    for i = 1, #mono.colours do
        bag[i] = i
    end
    for i = #bag, 2, -1 do
        local j = colour_random(i)
        bag[i], bag[j] = bag[j], bag[i]
    end
    if mono.last_index and #bag > 1 and bag[1] == mono.last_index then
        bag[1], bag[2] = bag[2], bag[1]
    end
    mono.bag = bag
    mono.cursor = 1
end

function mono.next_colour(excluded)
    if reference_palette_index then
        return mono.colours[reference_palette_index], reference_palette_index
    end
    if mono.cursor > #mono.bag then
        mono.refill()
    end
    if excluded then
        local available
        for i = mono.cursor, #mono.bag do
            if not excluded[mono.bag[i]] then available = i; break end
        end
        if not available then
            mono.refill()
            for i = 1, #mono.bag do
                if not excluded[mono.bag[i]] then available = i; break end
            end
        end
        if available then
            mono.bag[mono.cursor], mono.bag[available] = mono.bag[available], mono.bag[mono.cursor]
        end
    end
    local index = mono.bag[mono.cursor]
    mono.cursor = mono.cursor + 1
    mono.last_index = index
    mono.event_count = mono.event_count + 1
    mono.stats.selected = mono.stats.selected + 1
    mono.last_name = mono.colours[index].name
    return mono.colours[index], index
end

function mono.reset()
    if chain_attack_colour then chain_attack_colour.reset() end
    table.clear(mono.bag)
    table.clear(mono.recent_events)
    mono.cursor = 1
    mono.last_index = nil
    mono.event_count = 0
    mono.last_name = "none"
    for key, _ in pairs(mono.stats) do
        mono.stats[key] = 0
    end
    mono.refill()
end

function mono.find_same_event(position, now, world)
    if not position then
        return nil
    end
    local group = chain_attack_colour and chain_attack_colour.group() or nil
    for i = #mono.recent_events, 1, -1 do
        local event = mono.recent_events[i]
        local age = now - event.t
        if age > mono.same_event_window then
            break
        end
        if event.position and event.attack_group == group and (not world or event.world == world) then
            local delta = position - event.position:unbox()
            if Vector3.length_squared(delta) <= mono.same_event_radius_sq then
                return event
            end
        end
    end
    return nil
end

function mono.push_event(position, colour, index, now, world)
    local event = {
        t = now,
        position = position and Vector3Box(position) or nil,
        colour = colour,
        index = index,
        attack_group = chain_attack_colour and chain_attack_colour.group() or nil,
        world = world,
    }
    mono.recent_events[#mono.recent_events + 1] = event
    while #mono.recent_events > mono.max_recent_events do
        table.remove(mono.recent_events, 1)
    end
    return event
end

function mono.event_for(position, force_new, world, excluded)
    local now = Application.time_since_launch()
    if not force_new and not reference_palette_index and chain_attack_colour then
        local scoped, created = chain_attack_colour.event(position, world)
        if scoped then
            if created then return scoped end
            mono.stats.reused_same_event = mono.stats.reused_same_event + 1
            return mono.push_event(position, scoped.colour, scoped.index, now, world or scoped.world)
        end
    end
    if not force_new then
        local existing = mono.find_same_event(position, now, world)
        if existing then
            mono.stats.reused_same_event = mono.stats.reused_same_event + 1
            return existing
        end
    end
    local colour, index = mono.next_colour(excluded)
    return mono.push_event(position, colour, index, now, world)
end

chain_attack_colour = mod:io_dofile("RainbowBlood/scripts/mods/RainbowBlood/chain_attack_colour")(function(position, world, excluded)
    return mono.event_for(position, true, world, excluded)
end, function() return settings.multi_target_blood_colour end)

function mono.find_recent_for_decal(position)
    if not position then
        return nil
    end
    local now = Application.time_since_launch()
    local best
    local best_distance = 0.75 * 0.75
    for i = #mono.recent_events, 1, -1 do
        local event = mono.recent_events[i]
        local age = now - event.t
        if age > 0.18 then
            break
        end
        if event.position then
            local delta = position - event.position:unbox()
            local distance = Vector3.length_squared(delta)
            if distance <= best_distance then
                best = event
                best_distance = distance
            end
        end
    end
    return best
end

local wound_colour_by_data = setmetatable({}, { __mode = "k" })

mono.refill()

local recent_context = {
    t = -100,
    hue = 0,
    r = 1,
    g = 0,
    b = 0,
    reason = "init",
}

local function shuffled_copy(list)
    local copy = {}
    for i = 1, #list do
        copy[i] = list[i]
    end
    for i = #copy, 2, -1 do
        local j = colour_random(i)
        copy[i], copy[j] = copy[j], copy[i]
    end
    return copy
end

local function clamp(value, low, high)
    if value < low then
        return low
    elseif value > high then
        return high
    end
    return value
end

local colour_cache = { ground = {}, source = {}, revision = 0 }
local refresh_colour_cache

local function cache_settings()
    local colour_order_mode = mod:get("colour_order_mode") or "palette_sequence"
    if colour_order_mode ~= "random" and colour_order_mode ~= "palette_sequence" then
        colour_order_mode = "palette_sequence"
    end
    settings.colour_order_mode = colour_order_mode
    settings.multi_target_blood_colour = mod:get("multi_target_blood_colour") == "same" and "same" or "different"
    local screen_mode = mod:get("screen_blood_mode")
    if screen_mode ~= "rainbow" and screen_mode ~= "vanilla" and screen_mode ~= "off" then
        screen_mode = mod:get("screen_blood_colour_enabled") == false and "vanilla" or "rainbow"
    end
    settings.screen_blood_mode = screen_mode
    settings.colorize_screen_blood = screen_mode == "rainbow"
    settings.colorize_bleed_dot = mod:get("bleed_dot_colour_enabled") ~= false

    settings.mode = "random"

    settings.speed = 0.45
    settings.saturation = 1.0
    settings.brightness = 1.0
    settings.sync_window = 0.12
    settings.colorize_decals = true

    local weapon_behavior = mod:get("weapon_blood_behavior") or "hit_count"
    if weapon_behavior ~= "off" and weapon_behavior ~= "hit_count" and weapon_behavior ~= "attack_count" then
        weapon_behavior = "hit_count"
    end
    settings.colorize_weapon_blood = mod:get("weapon_blood_colour_enabled") ~= false and weapon_behavior ~= "off"
    settings.weapon_blood_mode = weapon_behavior == "hit_count" and "hit_count" or "attack_count"
    settings.weapon_cycle_n = math.floor(clamp(mod:get("weapon_cycle_n") or 2, 1, 30) + 0.5)
    settings.enable_poxwalker_spray = true
    settings.spray_palette = "l4d2_source_gradient"
    if refresh_colour_cache then refresh_colour_cache() end
end

local function hsv_to_rgb(h, s, v)
    h = h % 1
    s = clamp(s, 0, 1)
    v = math.max(v, 0)

    if s <= 0 then
        return v, v, v
    end

    local sector = h * 6
    local i = math.floor(sector)
    local f = sector - i
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))
    i = i % 6

    if i == 0 then
        return v, t, p
    elseif i == 1 then
        return q, v, p
    elseif i == 2 then
        return p, v, t
    elseif i == 3 then
        return p, q, v
    elseif i == 4 then
        return t, p, v
    end

    return v, p, q
end

local function next_hue()
    if reference_palette_index then
        return palette_hues[reference_palette_index]
    end
    if settings.mode == "random" then
        return palette_hues[colour_random(1, #palette_hues)]
    end

    sequence = sequence + 1
    return palette_hues[(sequence - 1) % #palette_hues + 1]
end

local function circular_hue_distance(a, b)
    local d = math.abs((a - b) % 1)
    return math.min(d, 1 - d)
end

local function nearest_palette_entry(hue)
    local best = source_palette[1]
    local best_distance = circular_hue_distance(hue, best.h)

    for i = 2, #source_palette do
        local entry = source_palette[i]
        local distance = circular_hue_distance(hue, entry.h)
        if distance < best_distance then
            best = entry
            best_distance = distance
        end
    end

    return best
end

refresh_colour_cache = function()
    for _, entry in ipairs(source_palette) do
        local r, g, b = hsv_to_rgb(entry.decal_h,
            clamp(entry.decal_s * settings.saturation, 0, 1), entry.decal_v * settings.brightness)
        colour_cache.ground[entry] = { r, g, b }
        r, g, b = hsv_to_rgb(entry.h,
            clamp(entry.s * settings.saturation, 0, 1), entry.v * settings.brightness)
        colour_cache.source[entry] = { r, g, b }
    end
    colour_cache.revision = colour_cache.revision + 1
end

local function ground_colour_for_entry(entry)
    local cached = colour_cache.ground[entry]
    if cached then return cached[1], cached[2], cached[3], entry end
    
    local s = clamp(entry.decal_s * settings.saturation, 0, 1)
    local v = entry.decal_v * settings.brightness
    local r, g, b = hsv_to_rgb(entry.decal_h, s, v)
    return r, g, b, entry
end

local function calibrated_decal_colour(hue)
    return ground_colour_for_entry(nearest_palette_entry(hue))
end

local wound_base_runtime = nil
if self_host_manifest and self_host_manifest.wound_rgb == true then
    wound_base_runtime = mod:io_dofile("RainbowBlood/scripts/mods/RainbowBlood/wound_base_runtime")(
        mod,
        function(existing_index, position)
            local index = reference_palette_index or existing_index or mono.event_for(position, false).index
            local r, g, b = ground_colour_for_entry(source_palette[index])
            return r, g, b, index
        end,
        function() return active end,
        function() return colour_cache.revision, reference_palette_index end,
        nil
    )
end

local function weapon_target_colour(hue, state)
    if reference_palette_index then hue = palette_hues[reference_palette_index] end
    if state then
        if state.palette_hue ~= hue or not state.palette_entry then
            state.palette_entry = nearest_palette_entry(hue)
            state.palette_hue = hue
        end

        local r, g, b, entry = ground_colour_for_entry(state.palette_entry)
        if state.powersword_red and entry == source_palette[1] then

            return r, 0, b, entry
        end
        return r, g, b, entry
    end
    return calibrated_decal_colour(hue)
end

local function new_context(reason)
    local hue = next_hue()
    local r, g, b, entry = calibrated_decal_colour(hue)
    recent_context.t = Application.time_since_launch()
    recent_context.hue = hue
    recent_context.r = r
    recent_context.g = g
    recent_context.b = b
    recent_context.palette_name = entry and entry.name or "unknown"
    recent_context.reason = reason or "generic"
    return recent_context
end

local function current_context(reason, force_new)
    local t = Application.time_since_launch()
    if force_new or (t - recent_context.t) > settings.sync_window then
        return new_context(reason)
    end
    recent_context.reason = reason or recent_context.reason
    return recent_context
end

local function is_blood_name(name, lower)
    if type(name) ~= "string" then
        return false
    end

    lower = lower or string.lower(name)
    return string.find(lower, "blood_splatter", 1, true) ~= nil
        or string.find(lower, "blood_decal", 1, true) ~= nil
        or string.find(lower, "screen_blood", 1, true) ~= nil
        or string.find(lower, "poxwalker_blood", 1, true) ~= nil
        or string.find(lower, "/blood_", 1, true) ~= nil
end

local function airborne_blood_kind(name, lower)
    if type(name) ~= "string" then
        return nil
    end

    lower = lower or string.lower(name)
    if string.find(lower, "/particles/impacts/flesh/", 1, true) == nil then
        return nil
    end

    if string.find(lower, "poxwalker_blood_splatter", 1, true)
        or string.find(lower, "/blood_splatter", 1, true) then
        return "splatter"
    end

    if string.find(lower, "blood_broker_toxin_fountain_head", 1, true) then
        return "broker_toxin_fountain"
    elseif string.find(lower, "blood_fountain_head", 1, true) then
        return "fountain"
    elseif string.find(lower, "blood_gushing", 1, true) then
        return "gushing"
    elseif string.find(lower, "blood_chainsword_loop", 1, true) then
        return "chainsword_loop"
    elseif string.find(lower, "blood_squirt", 1, true) then
        return "squirt"
    elseif string.find(lower, "poxwalker_splatter_gib_torso_small", 1, true) then
        return "poxwalker_gib_splatter"
    end

    return nil
end

local function is_known_liquid_blood_particle_name(name, lower)
    if type(name) ~= "string" then
        return false
    end

    lower = lower or string.lower(name)
    if string.find(lower, "/particles/impacts/flesh/", 1, true) == nil then
        return false
    end

    return string.find(lower, "/blood_", 1, true) ~= nil
        or string.find(lower, "poxwalker_blood_", 1, true) ~= nil
        or string.find(lower, "poxwalker_splatter_gib_torso_small", 1, true) ~= nil
end

local particle_classification = { entries = {}, count = 0, limit = 512, empty = {} }
local function classify_particle(name)
    if type(name) ~= "string" then return nil end
    local cached = particle_classification.entries[name]
    if cached ~= nil then return cached end
    local lower = string.lower(name)
    local targets = exact_blood_targets(name)
    local blood = is_blood_name(name, lower)
    local liquid = is_known_liquid_blood_particle_name(name, lower)
    local unresolved = unresolved_exact_blood[name]
    local result = false
    if targets or blood or liquid or unresolved then
        result = { targets = targets, blood = blood, liquid = liquid, unresolved = unresolved,
            splatter = not targets and airborne_blood_kind(name, lower) == "splatter" }
    end
    if particle_classification.count < particle_classification.limit then
        particle_classification.entries[name] = result
        particle_classification.count = particle_classification.count + 1
    end
    return result
end
for name in pairs(exact_blood_map.entries or {}) do classify_particle(name) end

local last_random_rebind_t = -100

local function apply_unit_colour(unit, r, g, b, alpha)
    if not unit then
        return
    end

    local vector3 = Vector3(r, g, b)

    pcall(Unit.set_vector3_for_materials, unit, "color", vector3, true)
end

local SCREEN_SINGLE_COLOUR_BURST_GAP = 0.35
local screen_effect_names = { [SCREEN_BLOOD_SOURCE] = true }
for _,name in ipairs(exact_blood_map.entries[SCREEN_BLOOD_SOURCE] or {}) do screen_effect_names[name] = true end
local screen_particles = {}
local function remember_screen(world, name, id)
    if not id or not screen_effect_names[name] then return end
    screen_particles[#screen_particles+1] = { world, id }
    if #screen_particles > 64 then table.remove(screen_particles, 1) end
end
local function clear_screen_particles()
    if World and type(World.are_particles_playing) == "function" then
        for _,row in ipairs(screen_particles) do
            local ok, playing = pcall(World.are_particles_playing, row[1], row[2])
            if ok and playing then pcall(World.destroy_particles, row[1], row[2]) end
        end
    end
    table.clear(screen_particles)
end
local screen_gameplay_colour = {
    index = nil,
    last_spawn_t = -100,
    world = nil,
    burst_serial = 0,
    sequence_cursor = 0,
}

local bleed_gameplay_colour = {
    sequence_cursor = 0,
}

local function reset_bleed_gameplay_colour()
    bleed_gameplay_colour.sequence_cursor = 0
end

local function next_bleed_palette_index()
    if reference_palette_index then return reference_palette_index end
    local next_index = (bleed_gameplay_colour.sequence_cursor % #source_palette) + 1
    bleed_gameplay_colour.sequence_cursor = next_index
    return next_index
end

local function reset_gameplay_screen_colour()
    screen_gameplay_colour.index = nil
    screen_gameplay_colour.last_spawn_t = -100
    screen_gameplay_colour.world = nil
    screen_gameplay_colour.burst_serial = 0
    screen_gameplay_colour.sequence_cursor = 0
end

local function next_screen_palette_index()
    if reference_palette_index then return reference_palette_index end
    if settings.colour_order_mode == "palette_sequence" then
        local next_index = (screen_gameplay_colour.sequence_cursor % #source_palette) + 1
        screen_gameplay_colour.sequence_cursor = next_index
        return next_index
    end

    local event = mono.recent_events[#mono.recent_events]
    local now = Application.time_since_launch()
    if not event or (now - event.t) > 0.18 then
        event = mono.event_for(nil, true)
    end
    return event and event.index or nil
end

mod:hook("PlayerUnitFxExtension", "_create_particles_wrapper", function(func, self, world, particle_name, position, rotation, scale, create_network_index)
    if active and settings.screen_blood_mode == "off" and screen_effect_names[particle_name] then return nil end
    if active and settings.enable_poxwalker_spray and (particle_name == GFX_CHAINSWORD_LOOP or particle_name == PFX_CHAINSWORD_LOOP) then
        return chain_attack_colour.with_owner(self and self._unit, func, self, world, particle_name, position, rotation, scale, create_network_index)
    end
    if active and settings.colorize_screen_blood and particle_name == SCREEN_BLOOD_SOURCE then
        local now = Application.time_since_launch()
        local is_new_burst = screen_gameplay_colour.index == nil
            or (now - screen_gameplay_colour.last_spawn_t) > SCREEN_SINGLE_COLOUR_BURST_GAP
        local cleared = 0
        local candidate_index = screen_gameplay_colour.index

        if is_new_burst then
            candidate_index = next_screen_palette_index()
            if candidate_index then
                screen_gameplay_colour.index = candidate_index
                screen_gameplay_colour.burst_serial = screen_gameplay_colour.burst_serial + 1
            end
        elseif screen_gameplay_colour.index == nil then
            candidate_index = next_screen_palette_index()
            screen_gameplay_colour.index = candidate_index
        end

        local replacement_index = screen_gameplay_colour.index or candidate_index
        local replacement_effect = replacement_index and precompiled_effect_for(SCREEN_BLOOD_SOURCE, replacement_index) or nil
        screen_gameplay_colour.last_spawn_t = now
        screen_gameplay_colour.world = world

        if replacement_effect then
            precompiled_mono.replacements = precompiled_mono.replacements + 1
            mono.stats.recoloured_particles = mono.stats.recoloured_particles + 1
            local entry = source_palette[replacement_index]
            if entry then
                local dr, dg, db = ground_colour_for_entry(entry)
                recent_context.t = now
                recent_context.hue = entry.h
                recent_context.r = dr
                recent_context.g = dg
                recent_context.b = db
                recent_context.palette_name = entry.name
                recent_context.reason = "screen_single_colour"
            end

            local id = func(self, world, replacement_effect, position, rotation, scale, create_network_index)
            remember_screen(world, replacement_effect, id)
            return id
        end

        precompiled_mono.fallbacks = precompiled_mono.fallbacks + 1
    end

    local id = func(self, world, particle_name, position, rotation, scale, create_network_index)
    remember_screen(world, particle_name, id)
    return id
end)

mod:hook("World", "create_particles", function(func, world, effect_name, position, rotation, scale, particle_group)
    if active and settings.screen_blood_mode == "off" and screen_effect_names[effect_name] then return nil end
    
    local classification = active and classify_particle(effect_name) or nil
    if not classification and effect_name ~= BLEED_DOT_SOURCE then
        local particle_id = func(world, effect_name, position, rotation, scale, particle_group)
        remember_screen(world, effect_name, particle_id)
        return particle_id
    end
    classification = classification or particle_classification.empty
    local bleed_colour_allowed = effect_name ~= BLEED_DOT_SOURCE or settings.colorize_bleed_dot
    local can_colour = active
        and settings.enable_poxwalker_spray
        and spray_shuffle_bypass == 0
        and effect_name ~= SCREEN_BLOOD_SOURCE
        and bleed_colour_allowed

    local event = nil
    local replacement_effect = nil
    local replacement_index = nil

    local exact_targets = can_colour and classification.targets or nil
    if effect_name == BLEED_DOT_SOURCE
        and settings.colorize_bleed_dot
        and settings.colour_order_mode == "palette_sequence"
        and exact_targets then
        replacement_index = next_bleed_palette_index()
        replacement_effect = precompiled_effect_for(effect_name, replacement_index, exact_targets)
        event = { index = replacement_index }
    elseif (can_colour and classification.splatter) or exact_targets then
        event = mono.event_for(position, false, world)
        replacement_index = event.index
        replacement_effect = precompiled_effect_for(effect_name, replacement_index, exact_targets)
    end

    if effect_name == BLEED_DOT_SOURCE then
        stats.bleed_dot_seen = stats.bleed_dot_seen + 1
        if settings.colorize_bleed_dot then
            
            local palette = replacement_index and source_palette[replacement_index] or nil
            stats.bleed_dot_last_palette = palette and palette.name or "none"
            stats.bleed_dot_last_target = replacement_effect or "none"
            
        else
            stats.bleed_dot_last_palette = "off"
            stats.bleed_dot_last_target = BLEED_DOT_SOURCE
        end
    end

    local effect_to_create = replacement_effect or effect_name
    local particle_id = func(world, effect_to_create, position, rotation, scale, particle_group)
    remember_screen(world, effect_to_create, particle_id)

    if classification.blood or classification.liquid or exact_targets or classification.unresolved then
        
        stats.blood_particle_calls = stats.blood_particle_calls + 1
        seen_effects[effect_name] = (seen_effects[effect_name] or 0) + 1
    end

    if event and particle_id then
        if replacement_effect then
            precompiled_mono.replacements = precompiled_mono.replacements + 1
            mono.stats.recoloured_particles = mono.stats.recoloured_particles + 1
            if effect_name == BLEED_DOT_SOURCE then
                stats.bleed_dot_replaced = stats.bleed_dot_replaced + 1
                
            end

            local entry = source_palette[replacement_index or event.index]
            if entry then
                local dr, dg, db = ground_colour_for_entry(entry)
                recent_context.t = Application.time_since_launch()
                recent_context.hue = entry.h
                recent_context.r = dr
                recent_context.g = dg
                recent_context.b = db
                recent_context.palette_name = entry.name
                recent_context.reason = "precompiled_mono_hit"
            end
        else
            precompiled_mono.fallbacks = precompiled_mono.fallbacks + 1
            local key = "PRECOMPILED_FALLBACK: " .. tostring(effect_name)
            seen_effects[key] = (seen_effects[key] or 0) + 1
        end
    elseif can_colour and particle_id and (classification.liquid or classification.unresolved) then
        local reason = classification.unresolved or "not-in-exact-map"
        local key = "PRECOMPILED_UNRESOLVED_BLOOD: " .. effect_name .. " :: " .. tostring(reason)
        seen_effects[key] = (seen_effects[key] or 0) + 1
    end

    return particle_id
end)

mod:hook("EngineOptimizedManagers", "decal_manager_add_decal", function(
    func,
    decal_system,
    decal_unit_name,
    decal_position,
    decal_rotation,
    decal_normal,
    decal_extents,
    hit_actor,
    hit_unit,
    t
)
    local decal_unit = func(
        decal_system,
        decal_unit_name,
        decal_position,
        decal_rotation,
        decal_normal,
        decal_extents,
        hit_actor,
        hit_unit,
        t
    )

    if active and settings.colorize_decals and is_blood_name(decal_unit_name) then
        if test_forced_palette_entry then
            local entry = test_forced_palette_entry
            local r, g, b = ground_colour_for_entry(entry)
            apply_unit_colour(decal_unit, r, g, b, 1)
            recent_context.palette_name = entry.name
            recent_context.reason = "lab_decal"
            test_forced_palette_entry = nil
        else
            local mono_event = mono.find_recent_for_decal(decal_position)
            if mono_event and mono_event.index then
                local entry = source_palette[mono_event.index]
                local dr, dg, db = ground_colour_for_entry(entry)
                apply_unit_colour(decal_unit, dr, dg, db, 1)
                recent_context.palette_name = entry.name
                recent_context.reason = "mono_decal_match"
            else
                local ctx = current_context("decal", false)
                apply_unit_colour(decal_unit, ctx.r, ctx.g, ctx.b, 1)
            end
        end
        stats.decals = stats.decals + 1
    end

    return decal_unit
end)

local function weapon_palette()
    return shuffled_copy(weapon_hues)
end

local function next_distinct_weapon_hue(state)
    if reference_palette_index then
        state.hue = weapon_hues[reference_palette_index]
        return state.hue
    end
    if settings.colour_order_mode == "palette_sequence" then
        state.sequence_cursor = ((state.sequence_cursor or 0) % #weapon_hues) + 1
        state.hue = weapon_hues[state.sequence_cursor]
        return state.hue
    end

    state.bag = state.bag or {}
    state.bag_index = state.bag_index or 1
    if state.bag_index > #state.bag then
        state.bag = weapon_palette()
        state.bag_index = 1
        if state.hue and #state.bag > 1 and circular_hue_distance(state.bag[1], state.hue) < 0.0001 then
            state.bag[1], state.bag[2] = state.bag[2], state.bag[1]
        end
    end
    local hue = state.bag[state.bag_index]
    state.bag_index = state.bag_index + 1
    state.hue = hue
    return hue
end

local function apply_weapon_single(unit_1p, unit_3p, hue, blood_amount, state)
    local r, g, b = weapon_target_colour(hue, state)
    local material_value = Quaternion.from_elements(r, g, b, blood_amount)
    if unit_1p then pcall(Unit.set_vector4_for_materials, unit_1p, "blood_color", material_value, true) end
    if unit_3p then pcall(Unit.set_vector4_for_materials, unit_3p, "blood_color", material_value, true) end
    return material_value
end

local function weapon_state_for(visual_loadout_extension, slot_name)
    if not visual_loadout_extension or not slot_name then return nil end
    local owner_state = weapon_states[visual_loadout_extension]
    if not owner_state then
        owner_state = {}
        weapon_states[visual_loadout_extension] = owner_state
    end
    local state = owner_state[slot_name]
    if not state then
        state = {
            last_amount = -1,
            hue = nil,
            bag = {},
            bag_index = 1,
            sequence_cursor = 0,
            hits_in_colour = 0,
            attacks_in_colour = 0,
            event_serial = 0,
            consumed_event_serial = 0,
            attack_serial = 0,
            consumed_attack_serial = 0,
            successful_attack_serial = 0,
            consumed_successful_attack_serial = 0,
            last_successful_attack_source_serial = nil,
            last_hit_switch_attack_serial = nil,
            fallback_hit_group_serial = 0,
            switch_log_budget = 20,
        }
        owner_state[slot_name] = state
    end
    local equipment = visual_loadout_extension._equipment
    local slot = type(equipment) == "table" and equipment[slot_name]
    local item = type(slot) == "table" and slot.item
    local name = type(item) == "table" and item.name or nil
    if state.weapon_item_name ~= name then
        state.weapon_item_name = name
        state.powersword_red = type(name) == "string"
            and name:find("content/items/weapons/player/melee/powersword_", 1, true) == 1
    end
    return state, owner_state
end

local function state_from_player_slot(player_unit, slot_name)
    if not player_unit or not slot_name then return nil end
    local visual_loadout_extension = ScriptUnit.has_extension(player_unit, "visual_loadout_system")
    if not visual_loadout_extension then return nil end
    return weapon_state_for(visual_loadout_extension, slot_name)
end

local function mark_weapon_blood_event(player_unit, slot_name)
    local state = state_from_player_slot(player_unit, slot_name)
    if state then
        state.event_serial = (state.event_serial or 0) + 1

        local attack_serial = state.attack_serial or 0
        if attack_serial > 0 and state.last_successful_attack_source_serial ~= attack_serial then
            state.last_successful_attack_source_serial = attack_serial
            state.successful_attack_serial = (state.successful_attack_serial or 0) + 1
        end
    end
end

local function mark_weapon_attack(player_unit, slot_name)
    local state = state_from_player_slot(player_unit, slot_name)
    if state then

        state.attack_serial = (state.attack_serial or 0) + 1
    end
end

mod:hook("ActionSweep", "start", function(func, self, action_settings, t, time_scale, action_start_params)
    local result = chain_attack_colour.start_call(self, func, self, action_settings, t, time_scale, action_start_params)
    if active and settings.colorize_weapon_blood then
        local inventory_component = self and self._inventory_component
        local slot_name = inventory_component and inventory_component.wielded_slot
        mark_weapon_attack(self and self._player_unit, slot_name)
    end
    return result
end)

mod:hook("ActionSweep", "fixed_update", function(func, self, ...)
    return chain_attack_colour.with_action(self, func, self, ...)
end)

mod:hook("ActionSweep", "finish", function(func, self, ...)
    return chain_attack_colour.finish_call(self, func, self, ...)
end)

mod:hook("ActionSweep", "_process_hit", function(func, self, t, hit_unit, ...)
    return chain_attack_colour.with_target(self and self._player_unit, hit_unit, func, self, t, hit_unit, ...)
end)

mod:hook("ActionSweep", "_update_hit_stickyness", function(func, self, dt, t, component, ...)
    return chain_attack_colour.with_target(self and self._player_unit, component and component.sweep_aborted_unit, func, self, dt, t, component, ...)
end)

mod:hook("FxSystem", "play_impact_fx", function(func, self, impact_fx, hit_position, attack_direction, source_parameters, attacking_unit, ...)
    return chain_attack_colour.with_target(attacking_unit, select(1, ...), func, self, impact_fx, hit_position, attack_direction, source_parameters, attacking_unit, ...)
end)

mod:hook("StickyEffects", "_start_stickyness", function(func, self, ...)
    if not active or not settings.enable_poxwalker_spray then return func(self, ...) end
    local fx_extension = self and self._fx_extension
    local component = self and self._action_sweep_component
    return chain_attack_colour.with_target(fx_extension and fx_extension._unit, component and component.sweep_aborted_unit, func, self, ...)
end)

mod:hook("BloodManager", "add_weapon_blood", function(func, self, player, slot_name, amount)
    local result = func(self, player, slot_name, amount)
    if active and settings.colorize_weapon_blood then
        local player_unit = player and player.player_unit
        mark_weapon_blood_event(player_unit, slot_name)
    end
    return result
end)

mod:hook("BloodManager", "rpc_add_weapon_blood", function(func, self, channel_id, game_object_id, slot_name_id, weapon_blood_amount_id)
    local result = func(self, channel_id, game_object_id, slot_name_id, weapon_blood_amount_id)
    local unit_spawner = Managers.state and Managers.state.unit_spawner
    local player_unit = unit_spawner and unit_spawner:unit(game_object_id)
    local slot_name = NetworkLookup and NetworkLookup.player_inventory_slot_names and NetworkLookup.player_inventory_slot_names[slot_name_id]
    if active and settings.colorize_weapon_blood and player_unit and ALIVE and ALIVE[player_unit] then
        mark_weapon_blood_event(player_unit, slot_name)
    end
    return result
end)

mod:hook("BloodManager", "_set_weapon_blood_intensity", function(func, self, visual_loadout_extension, slot_name, blood_amount)

    if not active or not settings.colorize_weapon_blood then
        return func(self, visual_loadout_extension, slot_name, blood_amount)
    end

    local unit_1p, unit_3p = visual_loadout_extension:unit_and_attachments_from_slot(slot_name)
    if not unit_1p or not unit_3p then
        return false
    end

    local state, owner_state = weapon_state_for(visual_loadout_extension, slot_name)
    if not state then return true end
    state.native_set_intensity, state.native_manager = func, self

    local amount_increased = blood_amount > state.last_amount + 0.001
    local event_serial = state.event_serial or 0
    local consumed_event_serial = state.consumed_event_serial or 0
    local new_hit_count = math.max(event_serial - consumed_event_serial, 0)
    if new_hit_count == 0 and amount_increased then
        
        new_hit_count = 1
    end
    if event_serial > consumed_event_serial then
        state.consumed_event_serial = event_serial
    end

    local attack_serial = state.attack_serial or 0
    local consumed_attack_serial = state.consumed_attack_serial or 0
    local new_attack_count = math.max(attack_serial - consumed_attack_serial, 0)

    local successful_attack_serial = state.successful_attack_serial or 0
    local consumed_successful_attack_serial = state.consumed_successful_attack_serial or 0
    local new_successful_attack_count = math.max(successful_attack_serial - consumed_successful_attack_serial, 0)

    if new_hit_count > 0 then
        stats.weapon_refreshes = stats.weapon_refreshes + new_hit_count
    end
    state.last_amount = blood_amount

    if blood_amount <= 0 then
        
        local clear_hue = state.hue or source_palette[1].h
        apply_weapon_single(unit_1p, unit_3p, clear_hue, 0, state)
        owner_state[slot_name] = nil
        return true
    end

    local mode = settings.weapon_blood_mode

    if not state.hue then
        next_distinct_weapon_hue(state)

        state.hits_in_colour = new_hit_count > 0 and 1 or 0
        state.attacks_in_colour = new_successful_attack_count > 0 and 1 or 0
        state.consumed_attack_serial = attack_serial
        state.consumed_successful_attack_serial = successful_attack_serial
        new_hit_count = math.max(new_hit_count - 1, 0)
        new_attack_count = 0
        new_successful_attack_count = 0
    end

    if mode == "attack_count" then

        if new_successful_attack_count > 0 then
            state.consumed_successful_attack_serial = successful_attack_serial
            state.consumed_attack_serial = attack_serial
            local total = (state.attacks_in_colour or 0) + new_successful_attack_count
            if total >= settings.weapon_cycle_n then
                next_distinct_weapon_hue(state)

                state.attacks_in_colour = total % settings.weapon_cycle_n
                
            else
                state.attacks_in_colour = total
            end
        elseif new_attack_count > 0 then
            
            state.consumed_attack_serial = attack_serial
        end
    else

        if new_hit_count > 0 then
            local current_attack_id = attack_serial
            if current_attack_id <= 0 then
                state.fallback_hit_group_serial = (state.fallback_hit_group_serial or 0) + 1
                current_attack_id = -state.fallback_hit_group_serial
            end

            if state.last_hit_switch_attack_serial == current_attack_id then

                state.hits_in_colour = 0
            else
                local total = (state.hits_in_colour or 0) + new_hit_count
                if total >= settings.weapon_cycle_n then
                    next_distinct_weapon_hue(state)
                    state.last_hit_switch_attack_serial = current_attack_id

                    state.hits_in_colour = 0
                    
                else
                    state.hits_in_colour = total
                end
            end
        end
        if new_attack_count > 0 then
            state.consumed_attack_serial = attack_serial
        end
    end

    apply_weapon_single(unit_1p, unit_3p, state.hue, blood_amount, state)
    return true
end)

local function restore_weapon_colours()
    for visual, slots in pairs(weapon_states) do
        for slot, state in pairs(slots) do
            if state.native_set_intensity and state.last_amount >= 0 then
                pcall(state.native_set_intensity, state.native_manager, visual, slot, state.last_amount)
            end
        end
    end
end

mod.update = function(dt)
    if redirects_waiting_since then acquire_precompiled_assets() end
    refresh_precompiled_assets()
end

mod.on_setting_changed = function(setting_id)
    local old_weapon = settings.colorize_weapon_blood
    cache_settings()
    if old_weapon and not settings.colorize_weapon_blood then restore_weapon_colours() end

    if setting_id == "colour_order_mode" then
        
        reset_gameplay_screen_colour()
        reset_bleed_gameplay_colour()
        table.clear(weapon_states)
    elseif setting_id == "screen_blood_mode" or setting_id == "screen_blood_colour_enabled" then
        reset_gameplay_screen_colour()
        if settings.screen_blood_mode == "off" then clear_screen_particles() end
    elseif setting_id == "bleed_dot_colour_enabled" then
        reset_bleed_gameplay_colour()
    end

    if setting_id == "weapon_blood_colour_enabled" or setting_id == "weapon_blood_behavior" or setting_id == "weapon_cycle_n" then
        
        table.clear(weapon_states)
    end
end

mod.on_enabled = function()
    cache_settings()
    active = true
end

mod.on_disabled = function()
    restore_weapon_colours()
    table.clear(screen_particles)
    active = false
    chain_attack_colour.reset()
    table.clear(mono.recent_events)
    if wound_base_runtime then wound_base_runtime.reset(true) end
    reference_palette_index = nil

    reset_gameplay_screen_colour()
    reset_bleed_gameplay_colour()
    table.clear(weapon_states)
end

mod.on_all_mods_loaded = function()
    cache_settings()
    active = mod:is_enabled()

    if self_host_manifest then
        self_host_handles = register_self_host_manifest(self_host_manifest)
    end

    acquire_precompiled_assets()

    report_asset_error()
end

mod.on_unload = function()
    restore_weapon_colours()
    table.clear(screen_particles)
    redirects_waiting_since = nil
    chain_attack_colour.reset()
    table.clear(mono.recent_events)
    
    if wound_base_runtime then wound_base_runtime.reset(true) end
    release_precompiled_assets()
    reforge.clear(mod)
end

mod.on_game_state_changed = function(status, state_name)
    if status == "exit" and state_name == "StateGameplay" then
        table.clear(screen_particles)
        chain_attack_colour.reset()
        table.clear(mono.recent_events)
        if wound_base_runtime then wound_base_runtime.reset(false) end
        
        reference_palette_index = nil
        reset_gameplay_screen_colour()
        reset_bleed_gameplay_colour()
        table.clear(weapon_states)
        table.clear(seen_effects)
    end
end
