-- Validate release defaults and all supported UI languages.
local root = assert(arg[1]) .. '/scripts/mods/RainbowBlood/'
local translations = assert(loadfile(root .. 'RainbowBlood_localization.lua'))()
local locales = { 'en', 'fr', 'it', 'de', 'es', 'pl', 'pt-br', 'ru', 'ja', 'ko', 'zh-cn', 'zh-tw' }
local locale_set = {}; for _, language in ipairs(locales) do locale_set[language] = true end
local expected = {
    colour_order_mode = 'palette_sequence', screen_blood_mode = 'rainbow', weapon_blood_colour_enabled = true,
    bleed_dot_colour_enabled = true, weapon_blood_behavior = 'hit_count', weapon_cycle_n = 2,
    multi_target_blood_colour = 'different',
}
local mod = { localize = function(_, key) assert(translations[key]); return key end }
local saved = {}
function mod:get(key) return saved[key] end
function mod:set(key, value) saved[key] = value end
get_mod = function(name) assert(name == 'RainbowBlood'); return mod end
local data = assert(loadfile(root .. 'RainbowBlood_data.lua'))()
assert(#data.options.widgets == 7)
for _, widget in ipairs(data.options.widgets) do
    assert(widget.default_value == expected[widget.setting_id], 'Saved/default mismatch: ' .. widget.setting_id)
    assert(translations[widget.setting_id], 'Untranslated widget')
    if widget.tooltip then assert(translations[widget.tooltip], 'Untranslated tooltip') end
    local valid = widget.type ~= 'dropdown'
    for _, option in ipairs(widget.options or {}) do
        assert(translations[option.text], 'Untranslated option')
        if option.value == widget.default_value then valid = true end
    end
    assert(valid, 'Default not in dropdown')
end
local keys = 0
for key, row in pairs(translations) do
    keys = keys + 1
    local count = 0
    for language, text in pairs(row) do
        assert(locale_set[language], 'Unexpected language: ' .. language)
        assert(type(text) == 'string' and text:find('%S') and not text:find('%%'), 'Invalid UI text')
        count = count + 1
    end
    assert(count == 12, 'Incomplete languages: ' .. key)
    for _, language in ipairs(locales) do
        assert(row[language], key .. ': missing ' .. language)
        if key == 'mod_name' then assert(row[language] == 'RainbowBlood') end
        if key:match('^weapon_behavior_') and key ~= 'weapon_behavior_off' then
            assert(row[language]:find('N', 1, true), 'Missing N in ' .. key)
            assert(not row[language]:match('%f[%a]n%f[%A]'), 'Lowercase count symbol in ' .. key)
        end
    end
end
assert(keys == 21)
saved = { screen_blood_colour_enabled=false, weapon_blood_behavior='off' }
assert(loadfile(root .. 'RainbowBlood_data.lua'))()
assert(saved.screen_blood_mode=='vanilla' and saved.weapon_blood_colour_enabled==false and saved.weapon_blood_behavior=='hit_count')
saved.screen_blood_mode='off';saved.weapon_blood_colour_enabled=true
assert(loadfile(root .. 'RainbowBlood_data.lua'))()
assert(saved.screen_blood_mode=='off' and saved.weapon_blood_colour_enabled==true,'New choices overwritten by migration')
print('RELEASE_LOCALIZATION_PASS: 21 text keys x 12 languages; seven defaults; legacy settings migration, translated controls and N preserved')
