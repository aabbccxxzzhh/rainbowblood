local mod = get_mod("RainbowBlood")

-- Migrate before DMF fills the new widgets' defaults.
if mod:get("screen_blood_mode") == nil then
    mod:set("screen_blood_mode", mod:get("screen_blood_colour_enabled") == false and "vanilla" or "rainbow")
end
if mod:get("weapon_blood_colour_enabled") == nil then
    mod:set("weapon_blood_colour_enabled", mod:get("weapon_blood_behavior") ~= "off")
end
if mod:get("weapon_blood_behavior") == "off" then mod:set("weapon_blood_behavior", "hit_count") end

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = false,
    options = {
        widgets = {
            {
                setting_id = "colour_order_mode",
                type = "dropdown",
                default_value = "palette_sequence",
                options = {
                    { text = "mode_random", value = "random" },
                    { text = "mode_palette_sequence", value = "palette_sequence" },
                },
            },
            {
                setting_id = "multi_target_blood_colour",
                tooltip = "multi_target_blood_colour_description",
                type = "dropdown",
                default_value = "different",
                options = {
                    { text = "multi_target_different", value = "different" },
                    { text = "multi_target_same", value = "same" },
                },
            },
            {
                setting_id = "screen_blood_mode",
                tooltip = "screen_blood_mode_description",
                type = "dropdown",
                default_value = "rainbow",
                options = {
                    { text = "screen_blood_rainbow", value = "rainbow" },
                    { text = "screen_blood_vanilla", value = "vanilla" },
                    { text = "screen_blood_off", value = "off" },
                },
            },
            {
                setting_id = "weapon_blood_colour_enabled",
                tooltip = "weapon_blood_colour_description",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "bleed_dot_colour_enabled",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "weapon_blood_behavior",
                type = "dropdown",
                default_value = "hit_count",
                options = {
                    { text = "weapon_behavior_attack_count", value = "attack_count" },
                    { text = "weapon_behavior_hit_count", value = "hit_count" },
                },
            },
            {
                setting_id = "weapon_cycle_n",
                type = "numeric",
                default_value = 2,
                range = { 1, 30 },
                decimals_number = 0,
            },
        },
    },
}
