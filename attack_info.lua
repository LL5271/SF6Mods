-- Changelog:
-- 0.92 (June 27, 2026)
-- - Fixed defender display getting stuck on previous combo
-- - Minor changes to debugger (improved logging performance)
-- 0.91 (June 26, 2026)
-- - Fixed issue with carry calculations on right half of stage
-- - Fixed position percentage bounding

local MOD_NAME = "Attack Info"
local VERSION = 0.92
local NEXUS_URL = "https://www.nexusmods.com/streetfighter6/mods/3637"

local CONFIG_PATH = "attack_info.json"
local DEBUG_PATH = "attack_info_debug.log"
local SNAPSHOT_DATA_PATH = "attack_info_snapshots.json"
local SAVE_DELAY = 0.5
local LEFT_CLICK = 0x01
local RIGHT_CLICK = 0x02
local F2_KEY = 0x71
local CTRL_KEY = 0x11
local KEY_4, KEY_5 = 0x34, 0x35

local Config, Utils, GameObjects, ComboData, UI = {}, {}, {}, {}, {}
local ADVANTAGE_SETTLE_FRAMES = 30
local PRECOMBO_RESOURCE_BASELINE_FRAMES = 120
local DEFENDER_PRECOMBO_RESOURCE_BASELINE_FRAMES = 8
local PENDING_START_TTL_FRAMES = 12
local THROW_CONNECT_MIN_ACTION_FRAME = 8
local THROW_SIDE_SWITCH_CONFIRM_FRAMES = 20
local DRIVE_IMPACT_RESOURCE_COST = 10000
local DRIVE_RUSH_RESOURCE_COST = 5000
local DRIVE_IMPACT_ACTION_MIN = 850
local DRIVE_IMPACT_ACTION_MAX = 859
local PARRY_ACTION_MIN = 480
local PARRY_ACTION_MAX = 489
local PARRY_ACT_ST = 39
local POST_MATCH_CLEAR_FRAMES = 120
local CARRY_LEFT_FACING_MIN = -765
local CARRY_LEFT_FACING_MAX = 695
local CARRY_RIGHT_FACING_MIN = -695
local CARRY_RIGHT_FACING_MAX = 765
local CARRY_TOTAL_MAX = CARRY_RIGHT_FACING_MAX - CARRY_RIGHT_FACING_MIN
local DEFAULT_STRING_GAP = 2
local DEFAULT_IGNORE_FRAMEKILLS = true
local BLOCKSTRING_TOOLTIP = "Non-blocking frames before a blockstring is considered complete."
local DEFAULT_BACKGROUND_OPACITY = 20
local DEFAULT_TEXT_OPACITY = 100
local DEFAULT_DISPLAY_SCALE = 100
local DEFAULT_COMBO_TIMER_DURATION = 30
local DEFAULT_HIDE_BUILTIN_ATTACK_DATA_DISPLAY = true
local DEFAULT_CLEAR_ON_DAMAGE = false
local DEFAULT_CLEAR_ON_BLOCK = false
local DEFAULT_UPDATE_ON_DAMAGE = true
local DEFAULT_UPDATE_ON_BLOCK = true
local DEFAULT_COMBO_END_MODE = "latest"
local COMBO_END_MODES = {
    latest = true,
    attacker_recovery = true,
    defender_recovery = true,
}
-- DEFAULT_POSITION_OFFSET and DEFAULT_POSITION_Y removed: now using static defaults in get_default_position_coords()
local DEFAULT_UNIT_MODE = "raw"
local DEFAULT_UNIT_MODES = {
    damage = "raw",
    drive = "raw",
    super = "raw",
    carry = "percent",
    gap = "percent",
}
local IMGUI_COL_TEXT = 0
local IMGUI_COL_WINDOW_BG = 2
local UNIT_MODES = { raw = true, percent = true }
local UNIT_DEFS = {
    { id = "damage", label = "Damage" },
    { id = "drive",  label = "Drive" },
    { id = "super",  label = "Super" },
    { id = "carry",  label = "Carry" },
    { id = "gap",    label = "Spacing" },
}
local COLUMN_DEFS = {
    { id = "hit_damage", label = "Damage", width = 76, default_visible = true },
    { id = "damage",   label = "Damage",   width = 76, unit_id = "damage", percent_max = 10000, color_max = 10000 },
    { id = "p1_drive", label = "P1 Drive", width = 92, unit_id = "drive",  percent_max = 60000, color_max = 60000 },
    { id = "p1_super", label = "P1 Super", width = 88, unit_id = "super",  percent_max = 30000, color_max = 30000 },
    { id = "p2_drive", label = "P2 Drive", width = 92, unit_id = "drive",  percent_max = 60000, color_max = 60000 },
    { id = "p2_super", label = "P2 Super", width = 88, unit_id = "super",  percent_max = 30000, color_max = 30000, default_visible = false },
    { id = "p1_carry", label = "P1 Carry", width = 59, percent_width = 63, unit_id = "carry", percent_max = CARRY_TOTAL_MAX, color_max = CARRY_TOTAL_MAX, default_visible = true },
    { id = "p2_carry", label = "P2 Carry", width = 59, percent_width = 63, unit_id = "carry", percent_max = CARRY_TOTAL_MAX, color_max = CARRY_TOTAL_MAX, default_visible = false },
     { id = "gap",      label = "Spacing",      width = 100, percent_width = 68, unit_id = "gap",   percent_max = 490,  color_max = 490 },
    { id = "adv",      label = "Adv",      width = 42, color_max = 80 },
}
local POSITION_DEFS = {
    { id = "self", label = "P1" },
    { id = "opponent", label = "P2" },
}

-------------------------
-- Config
-------------------------

Config.initialized = false
Config.settings = {
    toggle_all = true,
    toggle_p1 = true,
    toggle_p2 = true,
    toggle_show_blocked_attacks = true,
    toggle_ignore_framekills = DEFAULT_IGNORE_FRAMEKILLS,
    string_gap = DEFAULT_STRING_GAP,
    toggle_minimal_view_p1 = true,
    toggle_minimal_view_p2 = true,
    toggle_mirror_column_order = true,
    toggle_show_empty_p1 = false,
    toggle_show_empty_p2 = false,
    combo_timer_duration = DEFAULT_COMBO_TIMER_DURATION,
    toggle_clear_on_damage = DEFAULT_CLEAR_ON_DAMAGE,
    toggle_clear_on_block = DEFAULT_CLEAR_ON_BLOCK,
    toggle_update_on_damage = DEFAULT_UPDATE_ON_DAMAGE,
    toggle_update_on_block = DEFAULT_UPDATE_ON_BLOCK,
    hide_all_alerts = false,
    alert_on_toggle = true,
    alert_on_minimal = true,
    reduce_drive = false,
    reduce_super = false,
    display_background_opacity = DEFAULT_BACKGROUND_OPACITY,
    display_text_opacity = DEFAULT_TEXT_OPACITY,
    display_scale = DEFAULT_DISPLAY_SCALE,
    hide_builtin_attack_data_display = DEFAULT_HIDE_BUILTIN_ATTACK_DATA_DISPLAY,
    unit_display = {
        damage = DEFAULT_UNIT_MODES.damage,
        drive = DEFAULT_UNIT_MODES.drive,
        super = DEFAULT_UNIT_MODES.super,
        carry = DEFAULT_UNIT_MODES.carry,
        gap = DEFAULT_UNIT_MODES.gap,
    },
    column_visibility_p1 = {
        hit_damage = true, damage = true, p1_drive = true, p1_super = true,
        p2_drive = true, p2_super = false, p2_carry = false,
        p1_carry = true, gap = true, adv = true,
    },
    column_visibility_p2 = {
        hit_damage = true, damage = true, p1_drive = true, p1_super = true,
        p2_drive = true, p2_super = false, p2_carry = false,
        p1_carry = true, gap = true, adv = true,
    },
    position_coords = {
        self = { x = nil, y = nil },
        opponent = { x = nil, y = nil },
    },
    position_mirror_y_axis = true,
    position_match_vertical = true,
    combo_end_mode = DEFAULT_COMBO_END_MODE,
    toggle_enable_debug_logging = false,
    toggle_enable_drive_cooldown_debug = true,
    log_attacker_display = true,
    log_defender_display = true,
    log_start_finish_values = true,
    log_settings_changed = true,
    log_display_update = true,
    log_display_clear = true,
    position_mode = "percent",
}

function Config.loaded_settings_missing_defaults(loaded_settings)
    if loaded_settings.toggle_mirror_column_order == nil then
        return true
    end

    if loaded_settings.display_background_opacity == nil or loaded_settings.display_text_opacity == nil or loaded_settings.display_scale == nil or loaded_settings.hide_builtin_attack_data_display == nil then
        return true
    end

    if type(loaded_settings.unit_display) ~= "table" then
        return true
    end

    if type(loaded_settings.position_coords) ~= "table" then
        return true
    end

    if loaded_settings.position_mirror_y_axis == nil then
        return true
    end

    if loaded_settings.position_match_vertical == nil then
        return true
    end

    if loaded_settings.combo_end_mode == nil then
        return true
    end

    if loaded_settings.log_attacker_display == nil or loaded_settings.log_defender_display == nil or loaded_settings.log_start_finish_values == nil or loaded_settings.log_settings_changed == nil or loaded_settings.log_display_update == nil or loaded_settings.log_display_clear == nil then
        return true
    end

    for _, unit in ipairs(UNIT_DEFS) do
        if loaded_settings.unit_display[unit.id] == nil then
            return true
        end
    end

    return false
end

function Config.load()
    local loaded_settings = json.load_file(CONFIG_PATH)
    local save_missing_defaults = false
    if loaded_settings then
        save_missing_defaults = Config.loaded_settings_missing_defaults(loaded_settings)
        for k, v in pairs(loaded_settings) do Config.settings[k] = v end
    else Config.save() end
    Config.ensure_defaults(save_missing_defaults)
end

function Config.save() json.dump_file(CONFIG_PATH, Config.settings) end

function Config.ensure_column_visibility()
    local changed = false

    for _, key in ipairs({ "column_visibility_p1", "column_visibility_p2" }) do
        if type(Config.settings[key]) ~= "table" then
            Config.settings[key] = {}
            changed = true
        end

        for _, column in ipairs(COLUMN_DEFS) do
            local default_visible = column.default_visible ~= false
            if Config.settings[key][column.id] == nil then
                Config.settings[key][column.id] = default_visible
                changed = true
            end
        end
    end

    return changed
end

function Config.ensure_percent_setting(key, default_value, fallback_value, min_value, max_value)
    local current = tonumber(Config.settings[key])
    local changed = false
    if current == nil then
        Config.settings[key] = Utils.clamp(fallback_value ~= nil and fallback_value or default_value, min_value, max_value)
        changed = true
    else
        local clamped = Utils.clamp(current, min_value, max_value)
        if Config.settings[key] ~= clamped then
            Config.settings[key] = clamped
            changed = true
        end
    end

    return changed
end

function Config.ensure_display_settings()
    local changed = false

    local old_opacity = tonumber(Config.settings.display_opacity)
    changed = Config.ensure_percent_setting("display_background_opacity", DEFAULT_BACKGROUND_OPACITY, old_opacity, 0, 100) or changed
    changed = Config.ensure_percent_setting("display_text_opacity", DEFAULT_TEXT_OPACITY, nil, 0, 100) or changed
    changed = Config.ensure_percent_setting("display_scale", DEFAULT_DISPLAY_SCALE, nil, 50, 150) or changed

    if Config.settings.hide_builtin_attack_data_display == nil then
        Config.settings.hide_builtin_attack_data_display = DEFAULT_HIDE_BUILTIN_ATTACK_DATA_DISPLAY
        changed = true
    end

    if Config.settings.display_opacity ~= nil then
        Config.settings.display_opacity = nil
        changed = true
    end

    return changed
end

function Config.ensure_unit_settings()
    local changed = false
    if type(Config.settings.unit_display) ~= "table" then
        Config.settings.unit_display = {}
        changed = true
    end

    for _, unit in ipairs(UNIT_DEFS) do
        local mode = Config.settings.unit_display[unit.id]
        if not UNIT_MODES[mode] then
            Config.settings.unit_display[unit.id] = DEFAULT_UNIT_MODES[unit.id] or DEFAULT_UNIT_MODE
            changed = true
        end
    end

    return changed
end

function Config.ensure_position_settings()
    local changed = false
    if type(Config.settings.position_coords) ~= "table" then
        Config.settings.position_coords = {}
        changed = true
    end

    if Config.settings.position_mirror_y_axis == nil then
        Config.settings.position_mirror_y_axis = true
        changed = true
    end

    if Config.settings.position_match_vertical == nil then
    Config.settings.position_match_vertical = true
    Config.settings.position_mode = "percent"
        changed = true
    end

    for _, def in ipairs(POSITION_DEFS) do
        if type(Config.settings.position_coords[def.id]) ~= "table" then
            Config.settings.position_coords[def.id] = { x = nil, y = nil }
            changed = true
        end
    end

    if Config.settings.position_mode == nil then
        Config.settings.position_mode = "percent"
        changed = true
    end

    return changed
end

function Config.get_string_gap()
    return math.max(0, math.floor(tonumber(Config.settings.string_gap) or DEFAULT_STRING_GAP))
end

function Config.ensure_defaults(force_save)
    local changed = false
    changed = Config.ensure_column_visibility() or changed
    changed = Config.ensure_display_settings() or changed
    changed = Config.ensure_unit_settings() or changed
    if Config.settings.toggle_mirror_column_order == nil then
        Config.settings.toggle_mirror_column_order = true
        changed = true
    end
    if Config.settings.toggle_clear_on_damage == nil then
        Config.settings.toggle_clear_on_damage = DEFAULT_CLEAR_ON_DAMAGE
        changed = true
    end
    if Config.settings.toggle_clear_on_block == nil then
        Config.settings.toggle_clear_on_block = DEFAULT_CLEAR_ON_BLOCK
        changed = true
    end
    if Config.settings.toggle_update_on_damage == nil then
        Config.settings.toggle_update_on_damage = DEFAULT_UPDATE_ON_DAMAGE
        changed = true
    end
    if Config.settings.toggle_update_on_block == nil then
        Config.settings.toggle_update_on_block = DEFAULT_UPDATE_ON_BLOCK
        changed = true
    end
    changed = Config.ensure_position_settings() or changed
    if not COMBO_END_MODES[Config.settings.combo_end_mode] then
        Config.settings.combo_end_mode = DEFAULT_COMBO_END_MODE
        changed = true
    end
    if Config.settings.toggle_enable_debug_logging == nil then
    Config.settings.toggle_enable_debug_logging = false
    Config.settings.toggle_enable_drive_cooldown_debug = true
        changed = true
    end
    if Config.settings.toggle_enable_drive_cooldown_debug == nil then
        Config.settings.toggle_enable_drive_cooldown_debug = true
        changed = true
    end
    if Config.settings.log_attacker_display == nil then
        Config.settings.log_attacker_display = true
        changed = true
    end
    if Config.settings.log_defender_display == nil then
        Config.settings.log_defender_display = true
        changed = true
    end
    if Config.settings.log_start_finish_values == nil then
        Config.settings.log_start_finish_values = true
        changed = true
    end
    if Config.settings.log_settings_changed == nil then
        Config.settings.log_settings_changed = true
        changed = true
    end
    if Config.settings.log_display_update == nil then
        Config.settings.log_display_update = true
        changed = true
    end
    if Config.settings.log_display_clear == nil then
        Config.settings.log_display_clear = true
        changed = true
    end
    if Config.settings.toggle_damage_scaling_icon ~= nil then
        Config.settings.toggle_damage_scaling_icon = nil
        changed = true
    end
    if changed or force_save then Config.save() end
end

function Config.reset_unit_defaults()
    if type(Config.settings.unit_display) ~= "table" then
        Config.settings.unit_display = {}
    end
    for _, unit in ipairs(UNIT_DEFS) do
        Config.settings.unit_display[unit.id] = DEFAULT_UNIT_MODES[unit.id] or DEFAULT_UNIT_MODE
    end
    Config.settings.reduce_drive = false
    Config.settings.reduce_super = false
end

function Config.reset_attack_info_defaults()
    Config.settings.toggle_all = true
    Config.settings.toggle_p1 = true
    Config.settings.toggle_p2 = true
    Config.settings.toggle_minimal_view_p1 = true
    Config.settings.toggle_minimal_view_p2 = true
    Config.reset_updating_defaults()
    Config.reset_display_defaults()
    Config.reset_unit_defaults()
    Config.reset_column_visibility_defaults()
    local _, defaults = UI.ensure_position_coords()
    Config.reset_position_defaults(defaults)
    Config.settings.toggle_enable_debug_logging = false
    Config.settings.toggle_enable_drive_cooldown_debug = true
    Config.settings.log_attacker_display = true
    Config.settings.log_defender_display = true
    Config.settings.log_start_finish_values = true
    Config.settings.log_settings_changed = true
    Config.settings.log_display_update = true
    Config.settings.log_display_clear = true
end
function Config.reset_column_visibility_defaults()
    for _, key in ipairs({ "column_visibility_p1", "column_visibility_p2" }) do
        if type(Config.settings[key]) ~= "table" then
            Config.settings[key] = {}
        end

        for _, column in ipairs(COLUMN_DEFS) do
            Config.settings[key][column.id] = column.default_visible ~= false
        end
    end
end

function Config.reset_position_defaults(defaults)
    Config.ensure_position_settings()
    Config.settings.toggle_mirror_column_order = true
    Config.settings.position_mirror_y_axis = true
    Config.settings.position_match_vertical = true
    Config.settings.position_mode = "percent"
    for _, def in ipairs(POSITION_DEFS) do
        local default_coords = defaults and defaults[def.id] or nil
        Config.settings.position_coords[def.id].x = default_coords and default_coords.x or nil
        Config.settings.position_coords[def.id].y = default_coords and default_coords.y or nil
    end
end

function Config.unit_defaults_selected()
    local unit_display = Config.settings.unit_display
    if type(unit_display) ~= "table" then return false end

    for _, unit in ipairs(UNIT_DEFS) do
        if unit_display[unit.id] ~= (DEFAULT_UNIT_MODES[unit.id] or DEFAULT_UNIT_MODE) then
            return false
        end
    end

    if Config.settings.reduce_drive ~= false then return false end
    if Config.settings.reduce_super ~= false then return false end

    return true
end

function Config.attack_info_defaults_selected()
    if Config.settings.toggle_all ~= true then return false end
    if Config.settings.toggle_p1 ~= true then return false end
    if Config.settings.toggle_p2 ~= true then return false end
    if Config.settings.toggle_minimal_view_p1 ~= true then return false end
    if Config.settings.toggle_minimal_view_p2 ~= true then return false end
    if not Config.updating_defaults_selected() then return false end
    if not Config.display_defaults_selected() then return false end
    if not Config.unit_defaults_selected() then return false end
    if not Config.column_visibility_defaults_selected() then return false end
    local _, defaults = UI.ensure_position_coords()
    if not Config.position_defaults_selected(defaults) then return false end
    if Config.settings.toggle_enable_debug_logging ~= false then return false end
    if Config.settings.toggle_enable_drive_cooldown_debug ~= true then return false end
    if Config.settings.log_attacker_display ~= true then return false end
    if Config.settings.log_defender_display ~= true then return false end
    if Config.settings.log_start_finish_values ~= true then return false end
    if Config.settings.log_settings_changed ~= true then return false end
    if Config.settings.log_display_update ~= true then return false end
    if Config.settings.log_display_clear ~= true then return false end
    return true
end

function Config.updating_defaults_selected()
    return Config.settings.toggle_show_blocked_attacks == true
        and (tonumber(Config.settings.string_gap) or DEFAULT_STRING_GAP) == DEFAULT_STRING_GAP
        and Config.get_combo_end_mode() == DEFAULT_COMBO_END_MODE
        and Config.settings.toggle_clear_on_damage == DEFAULT_CLEAR_ON_DAMAGE
        and Config.settings.toggle_clear_on_block == DEFAULT_CLEAR_ON_BLOCK
        and Config.settings.toggle_update_on_damage == DEFAULT_UPDATE_ON_DAMAGE
        and Config.settings.toggle_update_on_block == DEFAULT_UPDATE_ON_BLOCK
end

function Config.reset_updating_defaults()
    Config.settings.toggle_show_blocked_attacks = true
    Config.settings.string_gap = DEFAULT_STRING_GAP
    Config.settings.combo_end_mode = DEFAULT_COMBO_END_MODE
    Config.settings.toggle_clear_on_damage = DEFAULT_CLEAR_ON_DAMAGE
    Config.settings.toggle_clear_on_block = DEFAULT_CLEAR_ON_BLOCK
    Config.settings.toggle_update_on_damage = DEFAULT_UPDATE_ON_DAMAGE
    Config.settings.toggle_update_on_block = DEFAULT_UPDATE_ON_BLOCK
end

function Config.get_combo_end_mode()
    local mode = Config.settings.combo_end_mode
    if not COMBO_END_MODES[mode] then
        return DEFAULT_COMBO_END_MODE
    end
    return mode
end

function Config.display_defaults_selected()
    return (tonumber(Config.settings.display_background_opacity) or DEFAULT_BACKGROUND_OPACITY) == DEFAULT_BACKGROUND_OPACITY
        and (tonumber(Config.settings.display_text_opacity) or DEFAULT_TEXT_OPACITY) == DEFAULT_TEXT_OPACITY
        and (tonumber(Config.settings.display_scale) or DEFAULT_DISPLAY_SCALE) == DEFAULT_DISPLAY_SCALE
        and (tonumber(Config.settings.combo_timer_duration) or DEFAULT_COMBO_TIMER_DURATION) == DEFAULT_COMBO_TIMER_DURATION
        and Config.settings.hide_builtin_attack_data_display == DEFAULT_HIDE_BUILTIN_ATTACK_DATA_DISPLAY
end
function Config.reset_display_defaults()
    Config.settings.display_background_opacity = DEFAULT_BACKGROUND_OPACITY
    Config.settings.display_text_opacity = DEFAULT_TEXT_OPACITY
    Config.settings.display_scale = DEFAULT_DISPLAY_SCALE
    Config.settings.combo_timer_duration = DEFAULT_COMBO_TIMER_DURATION
    Config.settings.hide_builtin_attack_data_display = DEFAULT_HIDE_BUILTIN_ATTACK_DATA_DISPLAY
end
function Config.column_visibility_defaults_selected()
    for _, key in ipairs({ "column_visibility_p1", "column_visibility_p2" }) do
        local visibility = Config.settings[key]
        if type(visibility) ~= "table" then
            return false
        end

        for _, column in ipairs(COLUMN_DEFS) do
            local default_visible = column.default_visible ~= false
            if visibility[column.id] ~= default_visible then
                return false
            end
        end
    end

    return true
end

function Config.position_defaults_selected(defaults)
    if type(defaults) ~= "table" or type(Config.settings.position_coords) ~= "table" then
        return false
    end

    if Config.settings.toggle_mirror_column_order ~= true then
        return false
    end

    if Config.settings.position_mirror_y_axis ~= true then
        return false
    end

    if Config.settings.position_match_vertical ~= true then
        return false
    end

    if Config.settings.position_mode ~= "percent" then
        return false
    end

    for _, def in ipairs(POSITION_DEFS) do
        local coords = Config.settings.position_coords[def.id]
        local default_coords = defaults[def.id]
        if type(coords) ~= "table" or type(default_coords) ~= "table" then
            return false
        end
        if math.floor((tonumber(coords.x) or 0) * 100 + 0.5) / 100 ~= math.floor((default_coords.x or 0) * 100 + 0.5) / 100 then
            return false
        end
        if math.floor((tonumber(coords.y) or 0) * 100 + 0.5) / 100 ~= math.floor((default_coords.y or 0) * 100 + 0.5) / 100 then
            return false
        end
    end

    return true
end

function Config.init()
    if not Config.initialized then
        -- Hook BattleStart on TrainingManager (covers training, story training,
        -- and online training modes) and on the general BattleManager (covers
        -- arcade, versus CPU, story match, and other non-training modes).
        Utils.setup_hook("app.training.TrainingManager", "BattleStart", nil,
            function()
                ComboData.default_state()
                -- Training mode (re)start means the previous session's snapshot
                -- payloads are stale (different characters/stage/state). Clear
                -- both the in-memory snapshots and the on-disk file so that any
                -- subsequent training snapshot load starts with a clean Attack
                -- Info slate.
                ComboData.clear_snapshot_file()
            end, true)
        Utils.setup_hook("app.BattleManager", "BattleStart", nil,
            function() ComboData.default_state() end, true)
        -- Hook SaveSnapShot and LoadSnapShot to save/restore Attack Info display values
        -- per snapshot slot. This preserves Carry/Gap/Drive values when loading a saved
        -- training state mid-combo.
        -- CRITICAL: Do NOT do any managed object access in these hooks. Set flags only.
        -- All actual work happens on on_frame via the hook flags.
        local other_setting_td = sdk.find_type_definition("app.training.tf_OtherSetting")
        ComboData.install_snapshot_hooks(other_setting_td)
        ComboData.default_state()
        -- Load existing snapshot data from disk
        local saved = json.load_file(SNAPSHOT_DATA_PATH)
        if saved then
            ComboData.snapshots = saved
        end
        ComboData.snapshot_debug("Config.init completed loaded_snapshot_data=" .. tostring(saved ~= nil))
        Config.load()
        Config.initialized = true
    end
end

-------------------------
-- Utils
-------------------------

function Utils.deep_copy(original)
    if type(original) ~= 'table' then return original end
    local copy = {}
    for key, value in pairs(original) do copy[key] = Utils.deep_copy(value) end
    return copy
end

function Utils.bitand(a, b)
    local result, bitval = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + bitval end
        bitval, a, b = bitval * 2, math.floor(a / 2), math.floor(b / 2)
    end
    return result
end

function Utils.clamp(value, min_value, max_value)
    return math.max(min_value, math.min(value, max_value))
end

function Utils.setup_hook(type_name, method_name, pre_func, post_func, ignore_caller)
    local type_def = sdk.find_type_definition(type_name)
    if type_def then
        local method = type_def:get_method(method_name)
        if method then sdk.hook(method, pre_func, post_func, false, ignore_caller == true) end
    end
end

function Utils.parse_frame_value(value)
    if type(value) == "number" then return value end
    if type(value) ~= "string" then return 0 end

    local frame_value = string.match(value, "[-+]?%d+")
    return tonumber(frame_value) or 0
end

function Utils.read_sfix(value)
    if value == nil then return 0 end
    if type(value) == "userdata" then
        local ok, text = pcall(function() return value:call("ToString()") end)
        return ok and tonumber(text) or 0
    end
    return tonumber(value) or 0
end

-------------------------
-- GameObjects
-------------------------

-- Singletons that may not exist at script load time are lazy-loaded each frame.
GameObjects.TrainingManager = nil
GameObjects.PauseManager    = nil
GameObjects.bFlowManager    = nil
GameObjects.sSetting        = nil
local _gBattle           = sdk.find_type_definition("gBattle")
GameObjects.PlayerField  = _gBattle:get_field("Player")
GameObjects.TeamField    = _gBattle:get_field("Team")
GameObjects.RoundField   = _gBattle:get_field("Round")
GameObjects.SettingField = _gBattle:get_field("Setting")
GameObjects.GameField    = _gBattle:get_field("Game")

-- Game modes where pause_type_bit == 0 means "unpaused" rather than
-- the usual set of non-zero sentinel values used in normal modes.
local ZERO_UNPAUSED_MODES = { [10] = true, [13] = true }

-- Scene/flow IDs where pause_type_bit == 0 means "not paused", rather than
-- the standard BATTLE flag (bit 64). These use their own overlay system.
-- 29=BHAvatarBattle, 71=eWorldTourOnlineBattle, 79=eAvatarRoomTraining,
-- 86=eBattleHubAvatarBattleIn, 87=eBattleHubAvatarBattleOut.
local ZERO_UNPAUSED_SCENES = { [79] = true, [86] = true, [87] = true, [71] = true, [29] = true }

-- pause_type_bit values that mean "not paused" in normal modes.
local PAUSED_BITS = { [2] = true, [320] = true, [256] = true, [324] = true, [2112] = false, [2368] = true, [4294967616] = true }

function GameObjects.refresh_singletons()
    if not GameObjects.TrainingManager then
        GameObjects.TrainingManager = sdk.get_managed_singleton("app.training.TrainingManager")
    end
    if not GameObjects.PauseManager then
        GameObjects.PauseManager = sdk.get_managed_singleton("app.PauseManager")
    end
    if not GameObjects.bFlowManager then
        GameObjects.bFlowManager = sdk.get_managed_singleton("app.bFlowManager")
    end
end

function GameObjects.get_objects()
    GameObjects.refresh_singletons()
    local sPlayer = GameObjects.PlayerField:get_data()
    if not sPlayer then return nil, nil, nil end
    local sTeam    = GameObjects.TeamField:get_data()
    local sSetting = GameObjects.SettingField:get_data()
    GameObjects.sSetting = sSetting
    return sPlayer, sPlayer.mcPlayer, sTeam and sTeam.mcTeam or nil
end

function GameObjects.get_character_id(player_index)
    local ok, character_id = pcall(function()
        if not GameObjects.PlayerField then return nil end
        local sPlayer = GameObjects.PlayerField:get_data()
        local player_types = sPlayer and sPlayer.mPlayerType or nil
        local player_type = player_types and player_types[player_index] or nil
        return player_type and player_type.mValue or nil
    end)

    if not ok then return nil end
    return character_id
end

-- Returns the current battle game-mode integer, or 0 when unknown.
function GameObjects.get_game_mode_id()
    if GameObjects.TrainingManager then
        local ok, mode = pcall(function() return GameObjects.TrainingManager:get_field("GameMode") end)
        if ok and mode and mode ~= 0 then return mode end
    end
    if GameObjects.sSetting then
        local ok, mode = pcall(function() return GameObjects.sSetting:get_field("GameMode") end)
        if ok and mode and mode ~= 0 then return mode end
    end
    if GameObjects.bFlowManager then
        local ok, mode = pcall(function() return GameObjects.bFlowManager:get_GameMode() end)
        if ok and mode and mode ~= 0 then return mode end
    end
    return 0
end

function GameObjects.get_training_drive_refill_settings(player_index)
    if not GameObjects.TrainingManager then return nil end

    local ok, data = pcall(function()
        local param_func = GameObjects.TrainingManager:call("get_ParamFunc")
        local game_local_data = param_func and param_func._gData or nil
        local player_datas = game_local_data and game_local_data.PlayerDatas or nil
        local player_data = player_datas and player_datas[player_index] or nil
        if not player_data then return nil end

        local target = tonumber(player_data.tempDGgauge)
        if target == nil or target <= 0 then
            target = tonumber(player_data.DG_Point)
        end

        return {
            point_lock = player_data.Is_DG_Point_Lock == true,
            configured_timer = tonumber(player_data.DG_Timer) or 0,
            runtime_timer = tonumber(player_data.dgTimer) or 0,
            target = target,
        }
    end)

    if not ok then return nil end
    return data
end

function GameObjects.is_avatar_battle_mode()
    local mode = GameObjects.get_game_mode_id()
    if ZERO_UNPAUSED_MODES[mode] then
        return true
    end
    if GameObjects.bFlowManager then
        local ok, flow_id = pcall(function() return GameObjects.bFlowManager:get_MainFlowID() end)
        if ok and flow_id and ZERO_UNPAUSED_SCENES[flow_id] then
            return true
        end
    end
    return false
end

function GameObjects.update_builtin_attack_data_display()
    local hide_builtin_attack_data_display = Config.settings.hide_builtin_attack_data_display == true
    if not GameObjects.TrainingManager then return end

    local ok_display, display_func = pcall(function()
        return GameObjects.TrainingManager:call("get_DisplayFunc")
    end)
    if ok_display and display_func then
        pcall(function()
            display_func:call("SetViewAttackInfo", not hide_builtin_attack_data_display)
        end)
    end

    local ok_dict, view_dict = pcall(function()
        return GameObjects.TrainingManager:get_field("_ViewUIWigetDict")
    end)
    if not ok_dict or not view_dict then return end

    local ok_widgets, widget_list = pcall(function()
        return view_dict:call("get_Item", 3)
    end)
    if not ok_widgets or not widget_list then return end

    local ok_count, widget_count = pcall(function()
        return tonumber(widget_list:call("get_Count")) or 0
    end)
    if not ok_count then return end

    for i = 0, math.max(0, widget_count - 1) do
        local ok_widget, widget = pcall(function()
            return widget_list:call("get_Item", i)
        end)
        if ok_widget and widget then
            pcall(function()
                widget:set_IsStopDraw(hide_builtin_attack_data_display)
            end)
        end
    end
end

function GameObjects.get_round_no()
    local battle_round = GameObjects.RoundField and GameObjects.RoundField:get_data() or nil
    if not battle_round then return nil end
    return battle_round.RoundNo
end

function GameObjects.get_combo_id()
    local sGame = GameObjects.GameField and GameObjects.GameField:get_data() or nil
    if not sGame then return 0 end
    local ok, combo_id = pcall(function() return tonumber(sGame.Combo_ID) or 0 end)
    return ok and combo_id or 0
end

-- Returns true only when at least one player has a usable live action engine.
-- Netplay postmatch can keep mcPlayer/mpActParam objects alive after combat has
-- ended, so mpActParam alone is not a safe combat-rendering gate.
function GameObjects.has_active_action_engine(player)
    if not player or not player.mpActParam then return false end

    local ok_action_part, action_part = pcall(function()
        return player.mpActParam.ActionPart
    end)
    if not ok_action_part or not action_part then return false end

    local ok_engine, engine = pcall(function()
        return action_part._Engine
    end)

    return ok_engine and engine ~= nil
end

function GameObjects.resolve_attack_name(action_id, action_frame)
    local id = tonumber(action_id)
    if id == nil then return "unknown" end

    local attack_name = string.format("action_%04d", math.max(0, math.floor(id)))
    local frame = tonumber(action_frame)
    if frame ~= nil and frame >= 0 then
        attack_name = attack_name .. "@" .. tostring(math.floor(frame))
    end

    return attack_name
end

function GameObjects.is_in_battle(cPlayer)
    if not cPlayer then return false end
    for i = 0, 1 do
        local p = cPlayer[i]
        if GameObjects.has_active_action_engine(p) then return true end
    end
    return false
end

function GameObjects.map_player_data(cPlayer, cTeam)
    local data_vals = {}
    for player_index = 0, 1 do
        local player = cPlayer[player_index]
        local training_drive = GameObjects.get_training_drive_refill_settings(player_index)
        -- if not player then
        --     data_vals[player_index] = { hp_current = 0, hp_max = 0, combo_count = 0, incapacitated = false }
        -- else
        local team = cTeam and cTeam[player_index] or nil
        local data = {}
        data.hp_current = player.vital_new or 0
        data.hp_max = player.vital_max or 0
        data.dir = Utils.bitand(player.BitValue or 0, 128) == 128
        data.character_id = GameObjects.get_character_id(player_index)
        data.incapacitated = player.incapacitated or false
        data.drive_adjusted = data.incapacitated and ((player.focus_new or 0) - 60000) or (player.focus_new or 0)
        data.drive_cooldown = player.focus_wait or 0
        data.training_drive_point_lock = training_drive and training_drive.point_lock == true or false
        data.training_drive_target = training_drive and training_drive.target or nil
        data.training_drive_configured_timer = training_drive and training_drive.configured_timer or 0
        data.training_drive_runtime_timer = training_drive and training_drive.runtime_timer or 0
        data.stance = player.pose_st or ""
        data.super = team and team.mSuperGauge or 0
        data.combo_count = team and team.mComboCount or 0
        data.guard_combo_count = player.gard_combo_cnt or 0
        data.guard_time = player.guard_time or 0
        data.death_count = team and team.mDeathCount or 0
        data.combo_damage = team and team.mComboDamage or 0
        data.current_hit_damage = 0
        data.combo_scale_now = 100
        if player.pDmgHitDT then
            data.current_hit_damage = tonumber(player.pDmgHitDT.DmgValue) or 0
        end
        data.is_poisoned = false
        if player.damage_cond then
            local ok, poisoned = pcall(function() return player.damage_cond:call("is_poison()") end)
            if ok then data.is_poisoned = poisoned == true end
        end
        if player.combo_scale then
            data.combo_scale_now = tonumber(player.combo_scale.now) or 100
        end
        data.down_count = team and team.mDownCount or 0
        data.sp_armor = false
        local ok_sp_armor, sp_armor_val = pcall(function() return player.sp_armor end)
        if ok_sp_armor then data.sp_armor = sp_armor_val == true end
        data.armor_now = 0
        data.armor_max = 0
        local ok_armor, astruct = pcall(function() return player.dm_taisei end)
        if ok_armor and astruct then
            data.armor_now = tonumber(astruct.armor_now) or 0
            data.armor_max = tonumber(astruct.armor_max) or 0
        end
        data.pos_x = player.pos and (player.pos.x.v / 65536.0) or 0
        data.gap = (player.vs_distance and player.vs_distance.v or 0) / 65536.0
        data.action_id = 0
        data.action_frame = 0
        data.action_total_frames = 0
        if player.mpActParam and player.mpActParam.ActionPart then
            local engine = player.mpActParam.ActionPart._Engine
            if engine then
                data.action_id = Utils.read_sfix(engine:get_ActionID())
                data.action_frame = Utils.read_sfix(engine:get_ActionFrame())
                local ok_margin, margin_frame = pcall(function()
                    return engine:get_MarginFrame()
                end)
                if ok_margin then
                    data.action_total_frames = Utils.read_sfix(margin_frame)
                end
            end
        end
        data.attack_name = GameObjects.resolve_attack_name(data.action_id, data.action_frame)
        data.act_st = Utils.read_sfix(player.act_st)
        data.advantage = 0
        data.advantage_margin = nil
        if GameObjects.TrainingManager and GameObjects.TrainingManager._tCommon then
            local snap = GameObjects.TrainingManager._tCommon.SnapShotDatas
            if snap and snap[0] then
                local display_data = snap[0]._DisplayData
                local meter = display_data and display_data.FrameMeterSSData and display_data.FrameMeterSSData.MeterDatas or nil
                if meter and meter[player_index] then
                    data.advantage = Utils.parse_frame_value(meter[player_index].StunFrame)
                end

                local player_datas = display_data and display_data.PlayerDatas or nil
                local player_data = player_datas and player_datas[player_index] or nil
                if player_data then
                    local margin = tonumber(player_data.atkFrameMarginFrame)
                    if margin and margin ~= -1 then
                        data.advantage_margin = margin
                    end
                end
            end
        end
        data_vals[player_index] = data
    end
    return data_vals[0], data_vals[1]
end

function GameObjects.is_paused()
    if not GameObjects.PauseManager then return false end
    local pause_type_bit = GameObjects.PauseManager:get_field("_CurrentPauseTypeBit")
    local mode = GameObjects.get_game_mode_id()

    -- Certain scenes (like 79 = eAvatarRoomTraining, 86 = eBattleHubAvatarBattleIn, etc.)
    -- do not have a battle overlay active, so bit=0 means "unpaused" rather
    -- than the usual BATTLE flag (bit 64). Check the scene/flow ID directly.
    local is_zero_bit_mode = ZERO_UNPAUSED_MODES[mode] == true
    if not is_zero_bit_mode and GameObjects.bFlowManager then
        local ok, flow_id = pcall(function() return GameObjects.bFlowManager:get_MainFlowID() end)
        if ok and flow_id then
            is_zero_bit_mode = ZERO_UNPAUSED_SCENES[flow_id] == true
        end
    end

    -- Modes 10 (STORY_TRAINING), 13 (STORY_SPECTATE), and scenes like
    -- 79 (eAvatarRoomTraining), 86 (eBattleHubAvatarBattleIn), and other avatar
    -- battle scenes use bit=0 as their "not paused" sentinel.
    if is_zero_bit_mode then
        return pause_type_bit ~= 0
    end

    -- Standard training modes (2, 18): only the base training bits (64 = BATTLE,
    -- 2112 = BATTLE_TRAINING_PAUSE + BATTLE) mean the view is unobstructed. Any
    -- additional pause bits (e.g. STATUSMENU from the avatar battle hub menu)
    -- mean an overlay menu is open, so we treat the view as paused.
    if mode == 2 or mode == 18 then
        return pause_type_bit ~= 64 and pause_type_bit ~= 2112
    end
    -- All other modes: a known set of non-zero bits signals "paused".
    -- Bitmask check: if the BATTLE flag (64) is absent, an overlay/menu is open.
    if Utils.bitand(pause_type_bit, 64) == 0 then
        return true
    end
    -- Has BATTLE flag. Only unpaused if pure battle or battle+training_pause.
    return pause_type_bit ~= 64 and pause_type_bit ~= 2112
end

-------------------------
-- ComboData Logic
-------------------------

function ComboData.default_state()
    ComboData.player_states = {
        [0] = { started = false, finished = false, attacker = 0, is_blocked = false, is_trade_sequence = false, is_drive_impact_sequence = false, pending_start_drive_impact_sequence = false, pending_poison_was_active = false, ended_in_knockdown = false, ended_in_ko = false, start = {}, finish = {}, prev_finish = nil, pending_start = nil, pending_start_hp_lock = nil, pending_start_ttl = nil, timer_remaining = nil, advantage_settle_remaining = 0, block_end_grace_remaining = 0, defender_recovery_grace_remaining = 0, throw_end_wait_for_exit = false, throw_side_switch_frames = 0, throw_side_switch_last_action_frame = nil, advantage_lock = nil, hit_damage_lock = nil, hit_damage_lock_frozen = false, combo_damage_lock = nil, start_hp_lock = nil, knockdown_drive_settle = false, knockdown_drive_settle_frames = nil, clear_start_advantage = false, poison_was_active = false, last_seen_combo_id = 0, hit_start_hp = nil, ko_carry_finish_p1_x = nil, ko_carry_finish_p2_x = nil, ko_carry_total_p1 = nil, ko_carry_total_p2 = nil },
        [1] = { started = false, finished = false, attacker = 1, hit_start_hp = nil, is_blocked = false, is_trade_sequence = false, is_drive_impact_sequence = false, pending_start_drive_impact_sequence = false, pending_poison_was_active = false, ended_in_knockdown = false, ended_in_ko = false, start = {}, finish = {}, prev_finish = nil, pending_start = nil, pending_start_hp_lock = nil, pending_start_ttl = nil, timer_remaining = nil, advantage_settle_remaining = 0, block_end_grace_remaining = 0, defender_recovery_grace_remaining = 0, throw_end_wait_for_exit = false, throw_side_switch_frames = 0, throw_side_switch_last_action_frame = nil, advantage_lock = nil, hit_damage_lock = nil, hit_damage_lock_frozen = false, combo_damage_lock = nil, start_hp_lock = nil, knockdown_drive_settle = false, knockdown_drive_settle_frames = nil, clear_start_advantage = false, poison_was_active = false, last_seen_combo_id = 0, ko_carry_finish_p1_x = nil, ko_carry_finish_p2_x = nil, ko_carry_total_p1 = nil, ko_carry_total_p2 = nil },
    }
    ComboData.p1_prev, ComboData.p2_prev = {}, {}
    ComboData.resource_baselines = { [0] = nil, [1] = nil }
    ComboData.resource_precombo_baselines = { [0] = nil, [1] = nil }
    ComboData.hook_save_fired = nil
    ComboData.hook_save_payload = nil
    ComboData.hook_load_fired = nil
    ComboData.pending_save_slot = nil
    ComboData.pending_load_slot = nil
    ComboData.snapshot_load_guard_frames = nil
    ComboData.snapshot_load_restored_state = nil
    ComboData.last_snapshot_slot_key = nil
    ComboData.snapshots = {}
    ComboData.runtime_state.match_clear_frames = 0
    ComboData.runtime_state.last_global_combo_id = 0
    ComboData.runtime_state.display_values_logged_hashes = {}
    ComboData.throw_carry_baseline = nil
    ComboData.parry_tracker = { [0] = nil, [1] = nil }
    ComboData.drive_cooldown_peak = { [0] = 0, [1] = 0 }
    ComboData.drive_cooldown_legitimate = { [0] = nil, [1] = nil }
    ComboData.drive_cooldown_pending = { [0] = false, [1] = false }
    ComboData.drive_cooldown_pending_age = { [0] = 0, [1] = 0 }
    ComboData.drive_cooldown_pending_peak = { [0] = 0, [1] = 0 }
    ComboData.drive_cooldown_total_peak = { [0] = 0, [1] = 0 }
    ComboData.drive_cooldown_pending_peak_final = { [0] = 0, [1] = 0 }
    ComboData.runtime_state.drive_cooldown_debug_last = { [0] = nil, [1] = nil }
end

ComboData.runtime_state = {
    was_in_battle = false,
    last_round_no = nil,
    match_clear_frames = 0,
    last_global_combo_id = 0,
    frame_count = 0,
    ko_logged_frame = -999,
    display_values_logged_hashes = {},
    drive_cooldown_debug_last = { [0] = nil, [1] = nil },
    debug_log_queue = {},
    debug_log_flush_skip_counter = 0,
    debug_logging_was_enabled = false,
}

function ComboData.debug_log(message, cat, force)
    if force ~= true and Config.settings.toggle_enable_debug_logging ~= true then return false end
    if force ~= true and cat and Config.settings[cat] == false then
        local linger = ComboData.runtime_state.log_linger_until or 0
        if cat ~= "log_attacker_display" and cat ~= "log_defender_display" or os.time() >= linger then
            return false
        end
    end
    ComboData.runtime_state.frame_count = (ComboData.runtime_state.frame_count or 0) + 1
    local fc = ComboData.runtime_state.frame_count
    table.insert(ComboData.runtime_state.debug_log_queue,
        os.date("%Y-%m-%dT%H:%M:%S") .. " [" .. tostring(fc) .. "] " .. tostring(message) .. "\n")
    return true
end

function ComboData.debug_log_flush()
    local queue = ComboData.runtime_state.debug_log_queue
    if not queue or #queue == 0 then return end
    pcall(function()
        local file = io.open(DEBUG_PATH, "a")
        if file then
            for _, line in ipairs(queue) do
                file:write(line)
            end
            file:close()
        end
    end)
    ComboData.runtime_state.debug_log_queue = {}
end

function ComboData.debug_log_state(prefix, state, cat)
    cat = cat or "log_start_finish_values"
    if not state then
        ComboData.debug_log(prefix .. " state=nil", cat)
        return
    end
    ComboData.debug_log(prefix
        .. " started=" .. tostring(state.started)
        .. " finished=" .. tostring(state.finished)
        .. " is_blocked=" .. tostring(state.is_blocked)
        .. " is_throw=" .. tostring(state.is_throw)
        .. " ended_in_ko=" .. tostring(state.ended_in_ko)
        .. " ended_in_knockdown=" .. tostring(state.ended_in_knockdown)
        .. " combo_damage_lock=" .. tostring(state.combo_damage_lock)
        .. " start_hp_lock=" .. tostring(state.start_hp_lock)
        .. " hit_damage_lock_frozen=" .. tostring(state.hit_damage_lock_frozen)
        .. " hit_damage_lock_provisional=" .. tostring(state.hit_damage_lock_provisional)
        .. " ko_start_hp_locked=" .. tostring(state.ko_start_hp_locked)
        .. " ko_start_snapshot_locked=" .. tostring(state.ko_start_snapshot_locked)
        .. " advantage_settle_remaining=" .. tostring(state.advantage_settle_remaining)
        .. " timer_remaining=" .. tostring(state.timer_remaining)
        .. " poison_was_active=" .. tostring(state.poison_was_active)
        .. " knockdown_drive_settle=" .. tostring(state.knockdown_drive_settle), cat
    )
    if state.hit_damage_lock then
        ComboData.debug_log(prefix .. " hit_damage_lock"
            .. " raw_damage=" .. tostring(state.hit_damage_lock.raw_damage)
            .. " scaling=" .. tostring(state.hit_damage_lock.scaling)
            .. " scaled_damage=" .. tostring(state.hit_damage_lock.scaled_damage)
            .. " combo_damage_total=" .. tostring(state.hit_damage_lock.combo_damage_total)
            .. " first_hit_ko=" .. tostring(state.hit_damage_lock.first_hit_ko_damage_derived_from_combo_damage), cat
        )
    end
    if state.start and state.start.p1 then
        ComboData.debug_log(prefix .. " start.p1 character_id=" .. tostring(state.start.p1.character_id) .. " hp=" .. tostring(state.start.p1.hp_current) .. " drive=" .. tostring(state.start.p1.drive_adjusted) .. " super=" .. tostring(state.start.p1.super) .. " pos_x=" .. tostring(state.start.p1.pos_x) .. " gap=" .. tostring(state.start.p1.gap) .. " sp_armor=" .. tostring(state.start.p1.sp_armor) .. " armor_now=" .. tostring(state.start.p1.armor_now) .. " attack_name=" .. tostring(state.start.p1.attack_name), cat)
    end
    if state.start and state.start.p2 then
        ComboData.debug_log(prefix .. " start.p2 character_id=" .. tostring(state.start.p2.character_id) .. " hp=" .. tostring(state.start.p2.hp_current) .. " drive=" .. tostring(state.start.p2.drive_adjusted) .. " super=" .. tostring(state.start.p2.super) .. " pos_x=" .. tostring(state.start.p2.pos_x) .. " gap=" .. tostring(state.start.p2.gap) .. " sp_armor=" .. tostring(state.start.p2.sp_armor) .. " armor_now=" .. tostring(state.start.p2.armor_now) .. " attack_name=" .. tostring(state.start.p2.attack_name), cat)
    end
    if state.finish and state.finish.p1 then
        ComboData.debug_log(prefix .. " finish.p1 character_id=" .. tostring(state.finish.p1.character_id) .. " hp=" .. tostring(state.finish.p1.hp_current) .. " drive=" .. tostring(state.finish.p1.drive_adjusted) .. " super=" .. tostring(state.finish.p1.super) .. " pos_x=" .. tostring(state.finish.p1.pos_x) .. " gap=" .. tostring(state.finish.p1.gap) .. " combo_damage=" .. tostring(state.finish.p1.combo_damage) .. " current_hit_damage=" .. tostring(state.finish.p1.current_hit_damage) .. " sp_armor=" .. tostring(state.finish.p1.sp_armor) .. " armor_now=" .. tostring(state.finish.p1.armor_now) .. " attack_name=" .. tostring(state.finish.p1.attack_name), cat)
    end
    if state.finish and state.finish.p2 then
        ComboData.debug_log(prefix .. " finish.p2 character_id=" .. tostring(state.finish.p2.character_id) .. " hp=" .. tostring(state.finish.p2.hp_current) .. " drive=" .. tostring(state.finish.p2.drive_adjusted) .. " super=" .. tostring(state.finish.p2.super) .. " pos_x=" .. tostring(state.finish.p2.pos_x) .. " gap=" .. tostring(state.finish.p2.gap) .. " combo_damage=" .. tostring(state.finish.p2.combo_damage) .. " current_hit_damage=" .. tostring(state.finish.p2.current_hit_damage) .. " sp_armor=" .. tostring(state.finish.p2.sp_armor) .. " armor_now=" .. tostring(state.finish.p2.armor_now) .. " attack_name=" .. tostring(state.finish.p2.attack_name), cat)
    end
end

function ComboData.sync_gameplay_state(in_battle, round_no)
    local runtime_state = ComboData.runtime_state

    if runtime_state.was_in_battle ~= in_battle then
        ComboData.debug_log("ROUND_START in_battle=" .. tostring(in_battle) .. " round_no=" .. tostring(round_no), "log_start_finish_values")
        ComboData.default_state()
        UI.begin_fadeout(0)
        UI.begin_fadeout(1)
    elseif in_battle and runtime_state.last_round_no ~= nil and round_no ~= nil and round_no ~= runtime_state.last_round_no then
        ComboData.debug_log("ROUND_START round_no=" .. tostring(round_no) .. " (was " .. tostring(runtime_state.last_round_no) .. ")", "log_start_finish_values")
        ComboData.default_state()
        UI.begin_fadeout(0)
        UI.begin_fadeout(1)
    end

    runtime_state.was_in_battle = in_battle
    runtime_state.last_round_no = in_battle and round_no or nil
end

function ComboData.update_post_match_timer(p1, p2)
    local any_finished = false
    local any_combat = false
    local any_ko = false
    local any_timer_active = false

    for i = 0, 1 do
        local state = ComboData.player_states and ComboData.player_states[i]
        local player = (i == 0 and p1 or p2)

        if state and state.finished and not state.started then
            any_finished = true
            if (tonumber(state.timer_remaining) or 0) > 0 then
                any_timer_active = true
            end
        end

        if player then
            if player.incapacitated or (tonumber(player.hp_current) or 0) <= 0 then
                any_ko = true
            end
            if (tonumber(player.combo_count) or 0) > 0 or (tonumber(player.current_hit_damage) or 0) > 0 then
                any_combat = true
            end
        end
    end

    if any_ko then
        any_combat = false
    end

    if any_finished and not any_combat and any_ko and not any_timer_active then
        ComboData.runtime_state.match_clear_frames = (ComboData.runtime_state.match_clear_frames or 0) + 1
        if ComboData.runtime_state.match_clear_frames >= POST_MATCH_CLEAR_FRAMES then
            for i = 0, 1 do
                local state = ComboData.player_states and ComboData.player_states[i]
                if state then
                    state.finished = false
                    state.timer_remaining = nil
                    state.knockdown_drive_settle = false
                    state.advantage_settle_remaining = 0
                    state.block_end_grace_remaining = 0
                    state.defender_recovery_grace_remaining = 0
                    ComboData.clear_pending_start(state)
                    UI.begin_fadeout(i)
                end
            end
            ComboData.runtime_state.match_clear_frames = 0
        end
    else
        ComboData.runtime_state.match_clear_frames = 0
    end
end

function ComboData.snapshot_debug(message)
    local ok = pcall(function()
        local file = io.open("attack_info_snapshot_debug.log", "a")
        if file then
            file:write(os.date("%Y-%m-%dT%H:%M:%S"), " ", tostring(message), "\n")
            file:close()
        end
    end)
    return ok
end

function ComboData.snapshot_payload_version(payload)
    if type(payload) ~= "table" then return "nil" end
    return tostring(payload.version)
end

function ComboData.snapshot_capture_payload(reason)
    local payload = nil
    local ok, err = pcall(function()
        payload = ComboData.get_serializable_state()
    end)
    if ok then
        ComboData.hook_save_payload = payload
        ComboData.snapshot_debug("capture_payload reason=" .. tostring(reason) .. " version=" .. ComboData.snapshot_payload_version(payload))
    else
        ComboData.snapshot_debug("capture_payload_failed reason=" .. tostring(reason) .. " error=" .. tostring(err))
    end
end

function ComboData.snapshot_mark_load(reason)
    ComboData.hook_load_fired = true
    ComboData.snapshot_debug("load_hook_fired reason=" .. tostring(reason))
end

function ComboData.install_snapshot_hook(type_def, method_name, kind)
    if not type_def then
        ComboData.snapshot_debug("snapshot_hook_type_missing method=" .. tostring(method_name) .. " kind=" .. tostring(kind))
        return false
    end

    local method = nil
    local ok, err = pcall(function()
        method = type_def:get_method(method_name)
    end)

    if not ok or not method then
        ComboData.snapshot_debug("snapshot_hook_method_missing method=" .. tostring(method_name) .. " kind=" .. tostring(kind) .. " error=" .. tostring(err))
        return false
    end

    if kind == "save" then
        sdk.hook(method,
            function(args)
                ComboData.hook_save_fired = true
                ComboData.snapshot_capture_payload(method_name)
            end,
            function(retval) return retval end,
            false, true)
    elseif kind == "load" then
        sdk.hook(method,
            function(args)
                ComboData.snapshot_mark_load(method_name)
            end,
            function(retval) return retval end,
            false, true)
    end

    ComboData.snapshot_debug("snapshot_hook_installed method=" .. tostring(method_name) .. " kind=" .. tostring(kind))
    return true
end

function ComboData.install_snapshot_hooks(type_def)
    ComboData.snapshot_debug("install_snapshot_hooks begin type_def_present=" .. tostring(type_def ~= nil))

    -- SaveSnapShot/LoadSnapShot are the public methods. ToSaveSnapShot and the
    -- Load_SnapShot local helper are also hooked because some training save-state
    -- flows bypass or delay the public wrappers.
    ComboData.install_snapshot_hook(type_def, "SaveSnapShot", "save")
    ComboData.install_snapshot_hook(type_def, "ToSaveSnapShot", "save")
    ComboData.install_snapshot_hook(type_def, "LoadSnapShot", "load")
    ComboData.install_snapshot_hook(type_def, "<Load_SnapShot>g__trainingLoadSnapShot|21_", "load")

    ComboData.snapshot_debug("install_snapshot_hooks end")
end
function ComboData.get_serializable_player_state(player_index)
    local state = ComboData.player_states and ComboData.player_states[player_index]
    if not state then return {} end

    return {
        started = state.started == true,
        finished = state.finished == true,
        attacker = state.attacker,
        is_blocked = state.is_blocked == true,
        is_trade_sequence = state.is_trade_sequence == true,
        is_throw = state.is_throw == true,
        is_drive_impact_sequence = state.is_drive_impact_sequence == true,
        pending_start_drive_impact_sequence = state.pending_start_drive_impact_sequence == true,
        pending_poison_was_active = state.pending_poison_was_active == true,
        ended_in_knockdown = state.ended_in_knockdown == true,
        start = Utils.deep_copy(state.start),
        finish = Utils.deep_copy(state.finish),
        prev_finish = Utils.deep_copy(state.prev_finish),
        pending_start = Utils.deep_copy(state.pending_start),
        pending_start_hp_lock = state.pending_start_hp_lock,
        pending_start_ttl = state.pending_start_ttl,
        timer_remaining = state.timer_remaining,
        advantage_settle_remaining = state.advantage_settle_remaining,
        block_end_grace_remaining = state.block_end_grace_remaining,
        defender_recovery_grace_remaining = state.defender_recovery_grace_remaining,
        advantage_lock = state.advantage_lock,
        hit_damage_lock = Utils.deep_copy(state.hit_damage_lock),
        hit_damage_lock_frozen = state.hit_damage_lock_frozen == true,
        hit_damage_lock_provisional = state.hit_damage_lock_provisional == true,
        hit_damage_lock_combo_damage_total = state.hit_damage_lock_combo_damage_total,
        pending_ko_hit_damage_delta = Utils.deep_copy(state.pending_ko_hit_damage_delta),
        combo_damage_lock = state.combo_damage_lock,
        start_hp_lock = state.start_hp_lock,
        ko_start_hp_locked = state.ko_start_hp_locked == true,
        ko_start_snapshot = Utils.deep_copy(state.ko_start_snapshot),
        ko_start_snapshot_locked = state.ko_start_snapshot_locked == true,
        knockdown_drive_settle = state.knockdown_drive_settle == true,
        clear_start_advantage = state.clear_start_advantage == true,
        poison_was_active = state.poison_was_active == true,
        clear_hidden_reason = state.clear_hidden_reason,
        last_seen_combo_id = state.last_seen_combo_id,
    }
end

function ComboData.get_serializable_state()
    local serializable = { version = 3 }
    for i = 0, 1 do
        serializable[tostring(i)] = ComboData.get_serializable_player_state(i)
    end

    serializable.resource_baselines = {
        [0] = Utils.deep_copy(ComboData.resource_baselines and ComboData.resource_baselines[0] or nil),
        [1] = Utils.deep_copy(ComboData.resource_baselines and ComboData.resource_baselines[1] or nil),
    }
    serializable.resource_precombo_baselines = {
        [0] = Utils.deep_copy(ComboData.resource_precombo_baselines and ComboData.resource_precombo_baselines[0] or nil),
        [1] = Utils.deep_copy(ComboData.resource_precombo_baselines and ComboData.resource_precombo_baselines[1] or nil),
    }

    -- p1_prev/p2_prev are the exact pre-start frame source for Carry/Drive/Super/Damage.
    -- Persisting them prevents a later post-combo endpoint from becoming the loaded start baseline.
    serializable.p1_prev = Utils.deep_copy(ComboData.p1_prev)
    serializable.p2_prev = Utils.deep_copy(ComboData.p2_prev)

    return serializable
end

function ComboData.get_snapshot_indexed_value(table_value, index)
    if type(table_value) ~= "table" then return nil end
    return table_value[index] or table_value[tostring(index)]
end

function ComboData.restore_serializable_player_state(player_index, saved_state)
    local state = ComboData.player_states and ComboData.player_states[player_index]
    if not state or type(saved_state) ~= "table" then return false end

    state.started = saved_state.started == true
    state.finished = saved_state.finished == true
    state.attacker = tonumber(saved_state.attacker) or player_index
    state.is_blocked = saved_state.is_blocked == true
    state.is_trade_sequence = saved_state.is_trade_sequence == true
    state.is_throw = saved_state.is_throw == true
    state.is_drive_impact_sequence = saved_state.is_drive_impact_sequence == true
    state.pending_start_drive_impact_sequence = saved_state.pending_start_drive_impact_sequence == true
    state.pending_poison_was_active = saved_state.pending_poison_was_active == true
    state.ended_in_knockdown = saved_state.ended_in_knockdown == true
    state.start = Utils.deep_copy(saved_state.start) or {}
    state.finish = Utils.deep_copy(saved_state.finish) or {}
    state.prev_finish = Utils.deep_copy(saved_state.prev_finish)
    state.pending_start = Utils.deep_copy(saved_state.pending_start)
    state.pending_start_hp_lock = saved_state.pending_start_hp_lock
    state.pending_start_ttl = saved_state.pending_start_ttl
    state.timer_remaining = saved_state.timer_remaining
    state.advantage_settle_remaining = saved_state.advantage_settle_remaining or 0
    state.block_end_grace_remaining = saved_state.block_end_grace_remaining or 0
    state.defender_recovery_grace_remaining = saved_state.defender_recovery_grace_remaining or 0
    state.advantage_lock = saved_state.advantage_lock
    state.hit_damage_lock = Utils.deep_copy(saved_state.hit_damage_lock)
    state.hit_damage_lock_frozen = saved_state.hit_damage_lock_frozen == true
    state.hit_damage_lock_provisional = saved_state.hit_damage_lock_provisional == true
    state.hit_damage_lock_combo_damage_total = saved_state.hit_damage_lock_combo_damage_total
    state.pending_ko_hit_damage_delta = Utils.deep_copy(saved_state.pending_ko_hit_damage_delta)
    state.combo_damage_lock = saved_state.combo_damage_lock
    state.start_hp_lock = saved_state.start_hp_lock
    state.ko_start_hp_locked = saved_state.ko_start_hp_locked == true
    state.ko_start_snapshot = Utils.deep_copy(saved_state.ko_start_snapshot)
    state.ko_start_snapshot_locked = saved_state.ko_start_snapshot_locked == true
    state.knockdown_drive_settle = saved_state.knockdown_drive_settle == true
    state.clear_start_advantage = saved_state.clear_start_advantage == true
    state.poison_was_active = saved_state.poison_was_active == true
    state.clear_hidden_reason = saved_state.clear_hidden_reason
    state.last_seen_combo_id = saved_state.last_seen_combo_id or 0
    return true
end

function ComboData.set_serializable_state(saved_root)
    if type(saved_root) ~= "table" then return false end

    -- Older snapshot payloads may already contain stale previous-combo endpoints.
    -- Do not restore them into the active display state.
    if (tonumber(saved_root.version) or 0) < 3 then
        return false
    end

    local restored_any = false
    for i = 0, 1 do
        restored_any = ComboData.restore_serializable_player_state(i, saved_root[tostring(i)] or saved_root[i]) or restored_any
    end

    local baselines = saved_root.resource_baselines
    ComboData.resource_baselines = {
        [0] = Utils.deep_copy(ComboData.get_snapshot_indexed_value(baselines, 0)),
        [1] = Utils.deep_copy(ComboData.get_snapshot_indexed_value(baselines, 1)),
    }

    local recent_baselines = saved_root.resource_precombo_baselines
    ComboData.resource_precombo_baselines = {
        [0] = Utils.deep_copy(ComboData.get_snapshot_indexed_value(recent_baselines, 0)),
        [1] = Utils.deep_copy(ComboData.get_snapshot_indexed_value(recent_baselines, 1)),
    }

    ComboData.p1_prev = Utils.deep_copy(saved_root.p1_prev) or {}
    ComboData.p2_prev = Utils.deep_copy(saved_root.p2_prev) or {}

    return restored_any
end

function ComboData.clear_player_sequence_state_for_snapshot_load(player_index)
    local state = ComboData.player_states and ComboData.player_states[player_index]
    if not state then return end

    state.started = false
    state.finished = false
    state.attacker = player_index
    state.is_blocked = false
    state.is_trade_sequence = false
    state.is_throw = false
    state.is_drive_impact_sequence = false
    state.pending_start_drive_impact_sequence = false
    state.pending_poison_was_active = false
    state.ended_in_knockdown = false
    state.ended_in_ko = false
    state.ko_carry_finish_p1_x = nil
    state.ko_carry_finish_p2_x = nil
    state.ko_carry_total_p1 = nil
    state.ko_carry_total_p2 = nil
    state.start = {}
    state.finish = {}
    state.prev_finish = nil
    state.pending_start = nil
    state.pending_start_hp_lock = nil
    state.pending_start_ttl = nil
    state.timer_remaining = nil
    state.advantage_settle_remaining = 0
    state.block_end_grace_remaining = 0
    state.defender_recovery_grace_remaining = 0
    state.throw_end_wait_for_exit = false
    state.throw_side_switch_frames = 0
    state.throw_side_switch_last_action_frame = nil
    state.advantage_lock = nil
    state.hit_damage_lock = nil
    state.hit_damage_lock_frozen = false
    state.hit_damage_lock_provisional = false
    state.hit_damage_lock_combo_damage_total = nil
    state.pending_ko_hit_damage_delta = nil
    state.combo_damage_lock = nil
    state.hit_start_hp = nil
    state.start_hp_lock = nil
    state.ko_start_hp_locked = false
    state.ko_start_snapshot = nil
    state.ko_start_snapshot_locked = false
    state.knockdown_drive_settle = false
    state.knockdown_drive_settle_frames = nil
    state.clear_start_advantage = false
    state.poison_was_active = false
    state.clear_hidden_reason = "snapshot_load"
    state.last_seen_combo_id = 0
    if ComboData.parry_tracker then
        ComboData.parry_tracker[player_index] = nil
    end
end

function ComboData.clear_sequence_state_for_snapshot_load()
    for i = 0, 1 do
        ComboData.clear_player_sequence_state_for_snapshot_load(i)
    end

    ComboData.throw_carry_baseline = nil
    ComboData.parry_tracker = { [0] = nil, [1] = nil }
    ComboData.drive_cooldown_peak = { [0] = 0, [1] = 0 }
    ComboData.drive_cooldown_legitimate = { [0] = nil, [1] = nil }
    ComboData.drive_cooldown_pending = { [0] = false, [1] = false }
    ComboData.drive_cooldown_pending_age = { [0] = 0, [1] = 0 }
    ComboData.drive_cooldown_pending_peak = { [0] = 0, [1] = 0 }
    ComboData.drive_cooldown_total_peak = { [0] = 0, [1] = 0 }
    ComboData.drive_cooldown_pending_peak_final = { [0] = 0, [1] = 0 }
    ComboData.runtime_state.display_values_logged_hashes = {}
    ComboData.runtime_state.last_global_combo_id = 0
end

function ComboData.any_restored_snapshot_sequence_started()
    for i = 0, 1 do
        local state = ComboData.player_states and ComboData.player_states[i]
        if state and state.started == true then
            return true
        end
    end
    return false
end

function ComboData.live_combo_state_visible(p1, p2)
    for _, p in ipairs({ p1, p2 }) do
        if p then
            if (tonumber(p.combo_count) or 0) > 0 then return true end
            if (tonumber(p.combo_damage) or 0) > 0 then return true end
            if (tonumber(p.current_hit_damage) or 0) > 0 then return true end
        end
    end
    return false
end

function ComboData.live_combat_detected(p1, p2)
    for _, player in ipairs({ p1, p2 }) do
        if player then
            if (tonumber(player.combo_count) or 0) > 0
                or (tonumber(player.combo_damage) or 0) > 0
                or (tonumber(player.current_hit_damage) or 0) > 0
                or (tonumber(player.guard_time) or 0) > 0
            then
                return true
            end
        end
    end
    return false
end

function ComboData.clear_snapshot_file()
    -- Remove the persisted snapshot data file so stale Attack Info state from a
    -- previous training session is not restored when a training snapshot is later
    -- loaded. Call this only on TrainingManager.BattleStart (character change /
    -- training restart), not on generic BattleManager.BattleStart (arcade rounds).
    pcall(function()
        os.remove(SNAPSHOT_DATA_PATH)
    end)
    ComboData.snapshots = {}
    ComboData.last_snapshot_slot_key = nil
end

function ComboData.clear_snapshot_load_guard_if_done()
    if (tonumber(ComboData.snapshot_load_guard_frames) or 0) <= 0 then
        ComboData.snapshot_load_guard_frames = nil
        ComboData.snapshot_load_restored_state = nil
    end
end

function ComboData.should_defer_after_snapshot_load(p1, p2)
    if (tonumber(ComboData.snapshot_load_guard_frames) or 0) <= 0 then
        return false
    end

    -- If no valid v3 Attack Info payload was restored, avoid all combo-start processing
    -- while the game applies the training snapshot, then reseed p1_prev/p2_prev from live state.
    -- Freeze p1_prev/p2_prev once combat activity (hit/combo/block) is detected so the
    -- pre-attack baseline is preserved for accurate start values after the guard expires.
    if ComboData.snapshot_load_restored_state ~= true then
        if not ComboData.live_combat_detected(p1, p2) then
            ComboData.p1_prev = p1 and Utils.deep_copy(p1) or {}
            ComboData.p2_prev = p2 and Utils.deep_copy(p2) or {}
        end
        return true
    end

    -- If a valid mid-combo payload was restored, do not let the old pre-load/end-of-combo
    -- game frame mutate the restored start/finish before SF6 exposes the loaded combo state.
    if ComboData.any_restored_snapshot_sequence_started()
        and not ComboData.live_combo_state_visible(p1, p2)
    then
        return not ComboData.live_combat_detected(p1, p2)
    end

    return false
end

function ComboData.after_snapshot_load(restored_serialized_state, live_p1, live_p2)
    ComboData.snapshot_load_guard_frames = 12
    ComboData.snapshot_load_restored_state = restored_serialized_state == true

    if restored_serialized_state then
        local restored_combo_started = ComboData.any_restored_snapshot_sequence_started()
        if restored_combo_started then
            for i = 0, 1 do
                local state = ComboData.player_states and ComboData.player_states[i]
                if state then
                    ComboData.clear_pending_start(state)
                    state.prev_finish = nil
                end
            end
        else
            ComboData.clear_sequence_state_for_snapshot_load()
            if live_p1 or live_p2 then
                ComboData.p1_prev = live_p1 and Utils.deep_copy(live_p1) or {}
                ComboData.p2_prev = live_p2 and Utils.deep_copy(live_p2) or {}
            end
        end
    else
        ComboData.clear_sequence_state_for_snapshot_load()
        ComboData.p1_prev, ComboData.p2_prev = {}, {}
        ComboData.clear_all_resource_baselines()
    end
end

function ComboData.get_training_other_setting()
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if not tm then
        ComboData.snapshot_debug("get_training_other_setting no TrainingManager")
        return nil
    end

    local other_func = nil
    local ok_other, err_other = pcall(function()
        other_func = tm:call("get_OtherFunc")
    end)
    if not ok_other or not other_func then
        ComboData.snapshot_debug("get_training_other_setting no OtherFunc error=" .. tostring(err_other))
        return nil
    end

    local other_setting = nil
    local ok_gdata, err_gdata = pcall(function()
        other_setting = other_func:call("get_GData")
    end)
    if not ok_gdata or not other_setting then
        ComboData.snapshot_debug("get_training_other_setting no GData error=" .. tostring(err_gdata))
        return nil
    end

    return other_setting
end

function ComboData.resolve_snapshot_slot_id(mode)
    local other_setting = ComboData.get_training_other_setting()
    if not other_setting then return nil end

    local method_name = mode == "load" and "GetLoadSlotID" or "GetSaveSlotID"
    local field_name = mode == "load" and "SnapShot_Load_SlotID" or "SnapShot_Save_SlotID"
    local slot_id = nil

    local ok_method, method_value = pcall(function()
        return other_setting:call(method_name)
    end)
    if ok_method and method_value ~= nil then
        slot_id = tonumber(method_value)
        ComboData.snapshot_debug("slot_method mode=" .. tostring(mode) .. " value=" .. tostring(method_value))
    else
        ComboData.snapshot_debug("slot_method_failed mode=" .. tostring(mode) .. " error_or_nil=" .. tostring(method_value))
    end

    if slot_id == nil then
        local ok_field, field_value = pcall(function()
            return other_setting:get_field(field_name)
        end)
        if ok_field and field_value ~= nil then
            slot_id = tonumber(field_value)
            ComboData.snapshot_debug("slot_field mode=" .. tostring(mode) .. " value=" .. tostring(field_value))
        else
            ComboData.snapshot_debug("slot_field_failed mode=" .. tostring(mode) .. " error_or_nil=" .. tostring(field_value))
        end
    end

    return slot_id
end

function ComboData.snapshot_slot_key_from_id(slot_id)
    local n = tonumber(slot_id)
    if n == nil then return nil end
    return tostring(math.floor(n) + 1)
end

function ComboData.choose_snapshot_save_key(actual_slot_id)
    local key = ComboData.snapshot_slot_key_from_id(actual_slot_id)
    if key then return key, "actual" end

    -- Fallback is intentionally stable for one-slot/manual validation flows.
    -- It makes save/load work even when the game-side slot id is not readable.
    return ComboData.last_snapshot_slot_key or "__fallback", "fallback"
end

function ComboData.choose_snapshot_load_key(saved, actual_slot_id)
    local actual_key = ComboData.snapshot_slot_key_from_id(actual_slot_id)
    if actual_key and saved and saved[actual_key] then
        return actual_key, "actual"
    end

    local last_key = saved and saved.__last_slot_key or nil
    if last_key and saved[last_key] then
        return last_key, "last"
    end

    if ComboData.last_snapshot_slot_key and saved and saved[ComboData.last_snapshot_slot_key] then
        return ComboData.last_snapshot_slot_key, "runtime_last"
    end

    if saved and saved.__fallback then
        return "__fallback", "fallback"
    end

    if saved then
        for key, value in pairs(saved) do
            if type(value) == "table" and tonumber(value.version) == 3 then
                return key, "first_v3"
            end
        end
    end

    return actual_key or "__fallback", "missing"
end

function ComboData.save_snapshot(slot_id, state_override)
    local actual_slot_id = slot_id
    if actual_slot_id == nil then
        actual_slot_id = ComboData.resolve_snapshot_slot_id("save")
    end

    local slot_key, key_source = ComboData.choose_snapshot_save_key(actual_slot_id)
    local payload = state_override or ComboData.get_serializable_state()

    if type(ComboData.snapshots) ~= "table" then
        ComboData.snapshots = {}
    end

    ComboData.snapshots[slot_key] = payload
    ComboData.snapshots.__last_slot_key = slot_key
    ComboData.last_snapshot_slot_key = slot_key

    local ok_dump, dump_err = pcall(function()
        json.dump_file(SNAPSHOT_DATA_PATH, ComboData.snapshots)
    end)

    ComboData.snapshot_debug(
        "save_snapshot slot_key=" .. tostring(slot_key)
        .. " key_source=" .. tostring(key_source)
        .. " actual_slot_id=" .. tostring(actual_slot_id)
        .. " payload_version=" .. ComboData.snapshot_payload_version(payload)
        .. " dump_ok=" .. tostring(ok_dump)
        .. " dump_err=" .. tostring(dump_err)
    )

    return actual_slot_id or slot_key
end

function ComboData.load_snapshot(slot_id, live_p1, live_p2)
    local actual_slot_id = slot_id
    if actual_slot_id == nil then
        actual_slot_id = ComboData.resolve_snapshot_slot_id("load")
    end

    local saved = json.load_file(SNAPSHOT_DATA_PATH) or ComboData.snapshots or {}
    local slot_key, key_source = ComboData.choose_snapshot_load_key(saved, actual_slot_id)

    local restored_serialized_state = false
    if saved and saved[slot_key] then
        restored_serialized_state = ComboData.set_serializable_state(saved[slot_key]) == true
    end

    ComboData.snapshot_debug(
        "load_snapshot slot_key=" .. tostring(slot_key)
        .. " key_source=" .. tostring(key_source)
        .. " actual_slot_id=" .. tostring(actual_slot_id)
        .. " restored=" .. tostring(restored_serialized_state)
        .. " saved_present=" .. tostring(saved and saved[slot_key] ~= nil)
        .. " saved_version=" .. ComboData.snapshot_payload_version(saved and saved[slot_key] or nil)
    )

    ComboData.after_snapshot_load(restored_serialized_state, live_p1, live_p2)
    return actual_slot_id or slot_key
end

function ComboData.is_block_snapshot_active(def)
    -- The runtime snapshot can lag the visible block transition by one frame.
    -- Treat `guard_time == 1` as the first non-blocking frame so a string_gap
    -- of 0 does not absorb a one-frame gap.
    return def and (def.guard_time or 0) > 1
end

function ComboData.did_guard_count_advance(def, def_prev)
    if not def or not def_prev then return false end
    local current = def.guard_combo_count or 0
    local previous = def_prev.guard_combo_count or 0
    return current > 0 and current ~= previous
end

function ComboData.get_active_attack_kind(atk, def, def_prev)
    if not atk then return nil end

    local defender_hp = tonumber(def and def.hp_current)
    local defender_prev_hp = tonumber(def_prev and def_prev.hp_current)
    if defender_hp ~= nil and defender_hp <= 0 and defender_prev_hp ~= nil and defender_prev_hp <= 0 then
        return nil
    end

    -- Check throw (CATCH=37) BEFORE combo_count so that throws are correctly
    -- classified as "throw". combo_count becomes > 0 on the same frame as
    -- CATCH for most throws, which would otherwise classify them as "hit" and
    -- bypass the throw-specific lifecycle (carry baseline, end detection).
    if atk and atk.act_st == 37 then
        return "throw"
    end

    if (atk.combo_count or 0) > 0 then
        return "hit"
    end

    -- Armored hits can deal damage without incrementing mComboCount because the
    -- defender doesn't enter hitstun. Detect by HP decrease + current_hit_damage.
    if def and def_prev then
        local hp_decreased = (tonumber(def_prev.hp_current) or 0) > (tonumber(def.hp_current) or 0)
        if hp_decreased then
            local hit_damage = math.max(
                tonumber(atk and atk.current_hit_damage) or 0,
                tonumber(def and def.current_hit_damage) or 0,
                tonumber(def_prev and def_prev.current_hit_damage) or 0
            )
            if hit_damage > 0 then
                return "hit"
            end
        end
    end

    if Config.settings.toggle_show_blocked_attacks and
        (ComboData.is_block_snapshot_active(def) or ComboData.did_guard_count_advance(def, def_prev)) then
        return "block"
    end

    return nil
end

function ComboData.did_precombo_opener_damage_start(atk, atk_prev, def, def_prev)
    if not atk or not def or not def_prev then
        return false
    end

    local previous_hp = tonumber(def_prev.hp_current) or 0
    local current_hp = tonumber(def.hp_current) or 0
    if previous_hp <= 0 or current_hp <= 0 or current_hp >= previous_hp then
        return false
    end

    local current_combo_damage = tonumber(atk.combo_damage) or 0
    local previous_combo_damage = tonumber(atk_prev and atk_prev.combo_damage) or 0
    local current_hit_damage = math.max(
        tonumber(atk.current_hit_damage) or 0,
        tonumber(def.current_hit_damage) or 0,
        tonumber(def_prev.current_hit_damage) or 0
    )

    -- Punish Counter Drive Impact can apply HP/resource changes before the
    -- script sees mComboCount > 0. Treat the first pre-combo HP drop as the
    -- true combo-start snapshot only when it is supported by hit/combo damage
    -- or DI-like Drive cooldown, so normal poison ticks before a combo do not
    -- become combo damage.
    return current_hit_damage > 0
        or current_combo_damage > previous_combo_damage
        or current_combo_damage > 0
        or ((atk.drive_cooldown or 0) > 200)
end

function ComboData.is_trade_start(atk, def)
    if not atk or not def then return false end

    return (tonumber(atk.combo_count) or 0) > 0
        and (tonumber(def.combo_count) or 0) > 0
        and (tonumber(atk.combo_damage) or 0) > 0
        and (tonumber(def.combo_damage) or 0) > 0
end

function ComboData.is_drive_impact_action_id(action_id)
    local id = tonumber(action_id)
    return id ~= nil and id >= DRIVE_IMPACT_ACTION_MIN and id <= DRIVE_IMPACT_ACTION_MAX
end

function ComboData.is_drive_impact_state(player)
    return player ~= nil and ComboData.is_drive_impact_action_id(player.action_id)
end
function ComboData.is_parry_action_id(action_id)
    local id = tonumber(action_id)
    return id ~= nil and id >= PARRY_ACTION_MIN and id <= PARRY_ACTION_MAX
end

function ComboData.is_parry_state(player)
    if not player then return false end
    return ComboData.is_parry_action_id(player.action_id) or (tonumber(player.act_st) or 0) == PARRY_ACT_ST
end

function ComboData.is_neutral_act_st(player)
    if not player then return false end
    local act_st = tonumber(player.act_st) or 0
    return act_st == 0 or act_st == 1 or act_st == 4
end

function ComboData.is_neutral_recovery_state(player)
    if not player then return false end
    return ComboData.is_neutral_act_st(player) and (tonumber(player.action_id) or 0) == 0
end

function ComboData.is_throw_state(player)
    if not player then return false end
    return (tonumber(player.act_st) or 0) == 37
end

function ComboData.clear_pending_start(state)
    if not state then return end

    state.pending_start = nil
    state.pending_start_hp_lock = nil
    state.pending_start_ttl = nil
    state.pending_start_drive_impact_sequence = false
    state.pending_poison_was_active = false
end

function ComboData.refresh_pending_start_ttl(state)
    if not state then return end
    state.pending_start_ttl = PENDING_START_TTL_FRAMES
end

function ComboData.expire_pending_start_if_stale(state, attack_kind, precombo_opener_damage)
    if not state or state.started == true or state.pending_start == nil then
        return
    end

    if attack_kind or precombo_opener_damage then
        ComboData.refresh_pending_start_ttl(state)
        return
    end

    local ttl = (tonumber(state.pending_start_ttl) or 0) - 1
    if ttl <= 0 then
        ComboData.clear_pending_start(state)
    else
        state.pending_start_ttl = ttl
    end
end

function ComboData.update_block_end_grace(state, def, def_prev)
    local string_gap = Config.get_string_gap()
    if ComboData.is_block_snapshot_active(def) then
        state.block_end_grace_remaining = string_gap
        return false
    end

    if (state.block_end_grace_remaining or 0) > 0 then
        state.block_end_grace_remaining = state.block_end_grace_remaining - 1
        if state.block_end_grace_remaining <= 0 then
            ComboData.debug_log("BLOCK_GRACE_EXPIRED p" .. tostring(state.attacker)
                .. " guard_time=" .. tostring(def and def.guard_time)
                .. " guard_combo_count=" .. tostring(def and def.guard_combo_count)
                .. " guard_combo_advance=" .. tostring(ComboData.did_guard_count_advance(def, def_prev))
                .. " string_gap=" .. tostring(string_gap), "log_display_update")
        end
        return false
    end

    ComboData.debug_log("BLOCK_END p" .. tostring(state.attacker)
        .. " guard_time=" .. tostring(def and def.guard_time)
        .. " guard_combo_count=" .. tostring(def and def.guard_combo_count)
        .. " guard_combo_advance=" .. tostring(ComboData.did_guard_count_advance(def, def_prev))
        .. " string_gap=" .. tostring(string_gap), "log_display_update")

    return true
end

function ComboData.update_advantage_if_larger(current_finish, latest)
    if not current_finish or not latest then return end

    local current_advantage = current_finish.advantage or 0
    local latest_advantage = latest.advantage or 0
    if latest_advantage ~= 0 and math.abs(latest_advantage) > math.abs(current_advantage) then
        current_finish.advantage = latest_advantage
    end
end

function ComboData.get_advantage_candidate_value(raw_value)
    local value = tonumber(raw_value)
    if value == nil then return nil end
    if value == 0 or value == -1 then return nil end
    return value
end

function ComboData.get_strongest_advantage_candidate(latest)
    if not latest then return nil end

    local strongest = nil
    for _, raw_value in ipairs({ latest.advantage, latest.advantage_margin }) do
        local candidate = ComboData.get_advantage_candidate_value(raw_value)
        if candidate ~= nil and (strongest == nil or math.abs(candidate) > math.abs(strongest)) then
            strongest = candidate
        end
    end

    return strongest
end

function ComboData.update_hit_advantage_lock(state, attacker_key, current_finish)
    if not state or state.is_blocked then
        return
    end

    local latest = current_finish and current_finish[attacker_key]
    if not latest then return end

    local advantage_lock = ComboData.get_advantage_candidate_value(state.advantage_lock)
    local strongest_candidate = ComboData.get_strongest_advantage_candidate(latest)

    if strongest_candidate ~= nil then
        if advantage_lock == nil then
            state.advantage_lock = strongest_candidate
            advantage_lock = strongest_candidate
        else
            local candidate_sign = strongest_candidate > 0 and 1 or -1
            local lock_sign = advantage_lock > 0 and 1 or -1
            if candidate_sign == lock_sign and math.abs(strongest_candidate) > math.abs(advantage_lock) then
                state.advantage_lock = strongest_candidate
                advantage_lock = strongest_candidate
            end
        end
    end

    if advantage_lock ~= nil then
        latest.advantage = advantage_lock
    end
end

function ComboData.clear_sequence_start_advantage(state, attacker_key, current_finish)
    if not state or not state.clear_start_advantage then
        return
    end

    local latest = current_finish and current_finish[attacker_key]
    if latest then
        latest.advantage = 0
    end

    state.clear_start_advantage = false
end

function ComboData.get_hit_damage_snapshot(state, attacker_key, current_finish, prefer_current_hit_damage)
    local start_defender = state.start and ((attacker_key == "p1" and state.start.p2) or state.start.p1) or nil
    local finish_defender = current_finish and ((attacker_key == "p1" and current_finish.p2) or current_finish.p1) or nil
    local finish_attacker = current_finish and current_finish[attacker_key] or nil

    if state and state.is_blocked then
        local chip_damage = (start_defender and start_defender.hp_current or 0) - (finish_defender and finish_defender.hp_current or 0)
        chip_damage = math.max(0, tonumber(chip_damage) or 0)
        return chip_damage, chip_damage > 0 and 100 or nil, chip_damage
    end

    local start_raw_damage = tonumber(start_defender and start_defender.current_hit_damage) or 0
    local current_raw_damage = math.max(
        tonumber(finish_defender and finish_defender.current_hit_damage) or 0,
        tonumber(finish_attacker and finish_attacker.current_hit_damage) or 0
    )
    local raw_damage = start_raw_damage
    local scaling = finish_defender and finish_defender.combo_scale_now or 100
    local current_raw_damage_is_live = current_raw_damage > 0 and current_raw_damage ~= start_raw_damage

    -- pDmgHitDT.DmgValue can remain populated from the previously displayed hit
    -- in the pre-hit start snapshot. Prefer a non-zero live finish-frame value
    -- when it differs from the start snapshot so new combos/hits can overwrite
    -- stale Source/Scaled Damage-Per-Hit values. KO still forces live data so
    -- the provisional KO path can wait for, or derive, the real hit damage.
    if prefer_current_hit_damage then
        raw_damage = current_raw_damage
    elseif current_raw_damage_is_live then
        raw_damage = current_raw_damage
    elseif raw_damage <= 0 then
        raw_damage = current_raw_damage
    end
    -- Avatar battle mode: per-hit damage from HP delta.
    -- pDmgHitDT.DmgValue reflects base move damage and does not include
    -- World Tour/avatar stat/buff modifiers. Use the defender's HP change
    -- since the last hit boundary (hit_start_hp) to get the actual damage.
    -- Since the HP delta already includes scaling and buffs, set scaling
    -- to 100 so scaled_damage (which = raw * scaling / 100) stays correct.
    if GameObjects.is_avatar_battle_mode() and state and state.hit_start_hp ~= nil and not state.is_blocked then
        local defender_current = tonumber(finish_defender and finish_defender.hp_current) or 0
        local hp_delta = state.hit_start_hp - defender_current
        if hp_delta > 0 then
            raw_damage = hp_delta
            scaling = 100
        end
    end

    scaling = tonumber(scaling) or 100

    if raw_damage <= 0 then
        -- First-hit KO may expose scaling before DmgValue/current_hit_damage is populated.
        -- Keep the scaling visible, but do not synthesize a raw start value here;
        -- update_hit_damage_lock may hold a provisional value until the real hit damage arrives.
        return raw_damage, scaling, 0
    end

    return raw_damage, scaling, math.max(0, math.floor((raw_damage * scaling) / 100))
end

function ComboData.is_pending_ko(atk, def, def_prev)
    local hp_current = tonumber(def and def.hp_current)
    if hp_current == nil or hp_current > 0 then
        return false
    end

    local combo_count = tonumber(atk and atk.combo_count) or 0
    local combo_damage = tonumber(atk and atk.combo_damage) or 0
    local current_hit_damage = math.max(
        tonumber(atk and atk.current_hit_damage) or 0,
        tonumber(def and def.current_hit_damage) or 0,
        tonumber(def_prev and def_prev.current_hit_damage) or 0
    )
    local previous_hp = tonumber(def_prev and def_prev.hp_current) or 0

    return combo_count > 0 or combo_damage > 0 or current_hit_damage > 0 or previous_hp > 0
end

function ComboData.ensure_start_hp_lock(state, attacker_idx, def, def_prev, atk, freeze_lock)
    if not state then return end
    if state.ko_start_hp_locked then return end

    local should_freeze_lock = freeze_lock == true
    local current_lock = tonumber(state.start_hp_lock) or 0

    if current_lock > 0 then
        if should_freeze_lock then
            state.ko_start_hp_locked = true
        end
        return
    end

    local defender_key = attacker_idx == 0 and "p2" or "p1"
    local start_defender = state.start and state.start[defender_key] or nil
    local candidates = {
        start_defender and start_defender.hp_current,
        def_prev and def_prev.hp_current,
        def and def.hp_current,
    }

    local best = current_lock
    for _, candidate in ipairs(candidates) do
        local value = tonumber(candidate) or 0
        if value > best then best = value end
    end

    if best > 0 then
        state.start_hp_lock = best
        if should_freeze_lock then
            state.ko_start_hp_locked = true
        end
    end
end

function ComboData.lock_ko_start_snapshot(state)
    if not state or state.ko_start_snapshot_locked then return end
    state.ko_start_snapshot = Utils.deep_copy(state.start or {})
    state.ko_start_snapshot_locked = true
end

function ComboData.get_start_display_snapshot(state)
    if state and state.ko_start_snapshot_locked and state.ko_start_snapshot then
        return state.ko_start_snapshot
    end

    return state and state.start or {}
end

function ComboData.derive_ko_hit_damage_from_combo_damage(state, latest, scaling, combo_delta_override)
    if not state or not latest then
        return nil
    end

    local finish_combo_damage = tonumber(latest.combo_damage) or 0
    if finish_combo_damage <= 0 then
        return nil
    end

    local combo_delta
    if combo_delta_override ~= nil then
        combo_delta = tonumber(combo_delta_override) or 0
    else
        local previous_combo_damage = tonumber(state.combo_damage_lock) or 0
        combo_delta = finish_combo_damage - previous_combo_damage

        -- First-hit KO can reach this path before combo_damage_lock has ever been
        -- populated. In that case the first hit's scaled damage is the current
        -- combo damage, not zero.
        if combo_delta <= 0 and not state.hit_damage_lock then
            combo_delta = finish_combo_damage
        end
    end

    if combo_delta <= 0 then
        return nil
    end

    local scale = tonumber(scaling) or 100
    local divisor = scale > 0 and scale or 100
    return {
        raw_damage = math.max(1, math.ceil((combo_delta * 100) / divisor)),
        scaling = scale,
        scaled_damage = combo_delta,
        combo_damage_total = finish_combo_damage,
        first_hit_ko_damage_derived_from_combo_damage = true,
    }
end
function ComboData.update_hit_damage_lock(state, attacker_key, current_finish, combo_ended, round_ended, ko_pending)
    if not state then
        return
    end

    local latest = current_finish and current_finish[attacker_key]
    if not latest then return end

    local latest_combo_damage = tonumber(latest.combo_damage) or 0
    local previous_dph_combo_total = tonumber(state.hit_damage_lock_combo_damage_total) or 0
    local ko_dph_combo_delta = latest_combo_damage - previous_dph_combo_total
    local ko_dph_combo_total = latest_combo_damage
    local terminal_freeze = combo_ended or round_ended
    local ko_live_damage_window = ko_pending and not terminal_freeze
    local ko_dph_combo_damage_authoritative = ko_pending and latest_combo_damage > 0 and ko_dph_combo_delta > 0

    -- KO/post-KO Damage-Per-Hit follows combo_damage deltas because Total Damage already receives them reliably.
    -- This avoids races where DmgValue/current_hit_damage lags behind a very-near post-KO follow-up hit.
    if state.hit_damage_lock_frozen
        and not state.hit_damage_lock_provisional
        and not ko_dph_combo_damage_authoritative
    then
        return
    end

    -- Terminal freeze: preserve the existing lock when the combo ends.
    -- With defender_recovery mode the end is detected when the defender's
    -- act_st returns to 0, which can be many frames after the last hit. By
    -- then the game may have already reset combo_scale to 100, cleared
    -- DmgValue, or set DmgValue to the scaled damage. The keep_previous_lock
    -- guard below is too narrow to reliably protect against overwriting the
    -- lock with post-combo data, so freeze early with the last good values.
    if terminal_freeze and state.hit_damage_lock and not state.hit_damage_lock_provisional and not ko_pending then
        state.hit_damage_lock_provisional = false
        state.hit_damage_lock_frozen = true
        return
    end

    if ko_dph_combo_damage_authoritative then
        state.hit_damage_lock_frozen = false
    end

    local prefer_current_hit_damage = ko_pending and (
        ko_dph_combo_damage_authoritative
        or state.hit_damage_lock == nil
        or state.hit_damage_lock_provisional == true
        or (state.hit_damage_lock and state.hit_damage_lock.first_hit_ko_damage_derived_from_combo_damage == true)
    )

    local raw_damage, scaling, scaled_damage = ComboData.get_hit_damage_snapshot(state, attacker_key, current_finish, prefer_current_hit_damage)
    local derived_ko_hit_damage = nil

    if ko_dph_combo_damage_authoritative then
        derived_ko_hit_damage = ComboData.derive_ko_hit_damage_from_combo_damage(state, latest, scaling, ko_dph_combo_delta)
        if derived_ko_hit_damage then
            raw_damage = derived_ko_hit_damage.raw_damage
            scaling = derived_ko_hit_damage.scaling
            scaled_damage = derived_ko_hit_damage.scaled_damage
        else
            scaling = tonumber(scaling) or 100
            local divisor = scaling > 0 and scaling or 100
            raw_damage = math.max(1, math.ceil((ko_dph_combo_delta * 100) / divisor))
            scaled_damage = ko_dph_combo_delta
        end
    elseif ko_pending and (tonumber(raw_damage) or 0) <= 0 then
        derived_ko_hit_damage = ComboData.derive_ko_hit_damage_from_combo_damage(state, latest, scaling)
        if derived_ko_hit_damage then
            raw_damage = derived_ko_hit_damage.raw_damage
            scaling = derived_ko_hit_damage.scaling
            scaled_damage = derived_ko_hit_damage.scaled_damage
            ko_dph_combo_total = latest_combo_damage
        end
    end

    -- Non-KO fallback: when current_hit_damage (pDmgHitDT.DmgValue) is 0
    -- but the combo_damage total has increased (common for throws where
    -- DmgValue is never or intermittently populated), derive hit damage
    -- from the combo_damage delta against the last locked total.
    if raw_damage <= 0 and not state.is_blocked then
        local combo_delta = latest_combo_damage - (tonumber(state.combo_damage_lock) or 0)
        if combo_delta > 0 then
            local divisor = math.max(tonumber(scaling) or 100, 1)
            raw_damage = math.max(1, math.ceil((combo_delta * 100) / divisor))
            scaled_damage = combo_delta
        end
    end

    -- pDmgHitDT.DmgValue can linger from the prior attack when a new sequence
    -- begins. If the game's combo damage advanced by a different amount, trust
    -- that delta for the displayed Damage-Per-Hit value.
    if raw_damage > 0 and not state.is_blocked and not ko_pending and not GameObjects.is_avatar_battle_mode() then
        local combo_delta = latest_combo_damage - (tonumber(state.combo_damage_lock) or 0)

        -- Derive effective scaling from actual damage when the game's
        -- combo_scale.now is unreliable (e.g., Super Art hits whose
        -- internal damage distribution isn't reflected in the standard
        -- combo scaling value).
        if combo_delta > 0 then
            local effective_scaling = math.floor((combo_delta * 100) / raw_damage)
            if effective_scaling > 0 and effective_scaling <= 100 then
                scaling = effective_scaling
                scaled_damage = math.max(0, math.floor((raw_damage * scaling) / 100))
            end
        end

        if combo_delta > 0 and combo_delta ~= (tonumber(scaled_damage) or 0) then
            local divisor = math.max(tonumber(scaling) or 100, 1)
            raw_damage = math.max(1, math.ceil((combo_delta * 100) / divisor))
            scaled_damage = combo_delta
        end
    end

    if ko_pending and raw_damage <= 0 and derived_ko_hit_damage == nil then
        state.hit_damage_lock = nil
        state.hit_damage_lock_frozen = false
        state.hit_damage_lock_provisional = true
        return
    end

    if raw_damage > 0 then
        local previous_lock = state.hit_damage_lock
        local previous_scaling = previous_lock and tonumber(previous_lock.scaling) or nil
        local previous_scaled_damage = previous_lock and (tonumber(previous_lock.scaled_damage) or 0) or 0
        local next_scaling = tonumber(scaling) or 100
        local next_scaled_damage = tonumber(scaled_damage) or 0

        local keep_previous_lock = terminal_freeze
            and not ko_dph_combo_damage_authoritative
            and derived_ko_hit_damage == nil
            and previous_lock ~= nil
            and previous_scaling ~= nil
            and previous_scaling < 100
            and next_scaling >= 100
            and next_scaled_damage > previous_scaled_damage

        if not keep_previous_lock then
            state.hit_damage_lock = {
                raw_damage = raw_damage,
                scaling = scaling,
                scaled_damage = scaled_damage,
                combo_damage_total = ko_dph_combo_total,
                first_hit_ko_damage_derived_from_combo_damage = derived_ko_hit_damage ~= nil or ko_dph_combo_damage_authoritative,
            }

            if ko_pending and ko_dph_combo_total > 0 then
                state.hit_damage_lock_combo_damage_total = ko_dph_combo_total
            end

            state.hit_damage_lock_provisional = false
        end
    elseif not state.hit_damage_lock then
        return
    end

    if terminal_freeze and not ko_dph_combo_damage_authoritative then
        state.hit_damage_lock_provisional = false
        state.hit_damage_lock_frozen = true
    elseif ko_live_damage_window or ko_dph_combo_damage_authoritative then
        state.hit_damage_lock_frozen = false
    end
end
function ComboData.update_combo_damage_lock(state, attacker_key, current_finish)
    if not state or state.is_blocked then
        return
    end

    local latest = current_finish and current_finish[attacker_key]
    if not latest then return end

    local latest_combo_damage = tonumber(latest.combo_damage) or 0
    if latest_combo_damage > 0 then
        state.combo_damage_lock = latest_combo_damage
    end
end
-- BEGIN DPH knockdown scaling freeze
function ComboData.freeze_hit_damage_finish_player(current_player, previous_player)
    if not current_player or not previous_player then return end

    if previous_player.current_hit_damage ~= nil then
        current_player.current_hit_damage = previous_player.current_hit_damage
    end
    if previous_player.combo_scale_now ~= nil then
        current_player.combo_scale_now = previous_player.combo_scale_now
    end
end

function ComboData.freeze_hit_damage_finish_pair(current_finish, previous_finish)
    if not current_finish or not previous_finish then return end

    ComboData.freeze_hit_damage_finish_player(current_finish.p1, previous_finish.p1)
    ComboData.freeze_hit_damage_finish_player(current_finish.p2, previous_finish.p2)
end

function ComboData.freeze_hit_damage_lock(state)
    if state and state.hit_damage_lock and not state.hit_damage_lock_provisional then
        state.hit_damage_lock_provisional = false
        state.hit_damage_lock_frozen = true
    end
end

function ComboData.apply_hit_damage_lock_to_finish(state, attacker_key, current_finish)
    if not state or not current_finish or not state.hit_damage_lock or state.hit_damage_lock_provisional then
        return
    end

    local lock = state.hit_damage_lock
    local finish_attacker = current_finish[attacker_key]
    local finish_defender = attacker_key == "p1" and current_finish.p2 or current_finish.p1
    local locked_raw_damage = tonumber(lock.raw_damage) or 0
    local locked_scaling = tonumber(lock.scaling)

    if finish_defender and locked_scaling ~= nil then
        finish_defender.combo_scale_now = locked_scaling
    end

    if locked_raw_damage > 0 then
        if finish_defender then
            finish_defender.current_hit_damage = locked_raw_damage
        end
        if finish_attacker and (tonumber(finish_attacker.current_hit_damage) or 0) <= 0 then
            finish_attacker.current_hit_damage = locked_raw_damage
        end
    end
end
-- END DPH knockdown scaling freeze
-- BEGIN DPH defender-recovery knockdown freeze
function ComboData.freeze_hit_damage_lock(state)
    if state and state.hit_damage_lock and not state.hit_damage_lock_provisional then
        state.hit_damage_lock_provisional = false
        state.hit_damage_lock_frozen = true
    end
end

function ComboData.should_freeze_hit_damage_during_defender_recovery(state, atk, combo_ended, round_ended, ko_pending, end_mode, ended_in_knockdown)
    if not state then return false end
    if state.is_blocked or state.is_throw then return false end
    if combo_ended or round_ended or ko_pending then return false end
    if (end_mode or "defender_recovery") ~= "defender_recovery" then return false end
    if ended_in_knockdown ~= true then return false end
    if not state.hit_damage_lock or state.hit_damage_lock_provisional then return false end

    -- In Defender Recovery mode, a knockdown combo remains "started" until the
    -- defender returns to neutral. The game's combo count and combo_scale can
    -- reset before that point, so freeze the last valid DPH row as soon as the
    -- combo counter has dropped while knockdown recovery is still pending.
    return (tonumber(atk and atk.combo_count) or 0) <= 0
end
-- END DPH defender-recovery knockdown freeze
function ComboData.freeze_drive_finish(current_finish, latest)
    if not current_finish or not latest then return end

    current_finish.drive_adjusted = latest.drive_adjusted
    current_finish.incapacitated = latest.incapacitated
end

function ComboData.freeze_all_finish_values(current_finish, previous_finish)
    if not current_finish or not previous_finish then return end

    for _, player_key in ipairs({ "p1", "p2" }) do
        local current = current_finish[player_key]
        local previous = previous_finish[player_key]
        if current and previous then
            current.drive_adjusted = previous.drive_adjusted
            current.incapacitated = previous.incapacitated
            current.super = previous.super
            current.pos_x = previous.pos_x
            current.gap = previous.gap
            current.advantage = previous.advantage
            current.hp_current = previous.hp_current
            current.combo_damage = previous.combo_damage
            current.current_hit_damage = previous.current_hit_damage
            current.combo_scale_now = previous.combo_scale_now
        end
    end
end

function ComboData.knockdown_drive_settle_complete(def)
    if not def then return true end

    if ComboData.is_defender_recovered(def) then
        return true
    end

    if (def.drive_cooldown or 0) ~= 0 then
        return false
    end

    if (def.action_frame or 0) ~= 0 then
        return false
    end

    return true
end

function ComboData.is_defender_recovered(def)
    if not def then return true end

    local act_st = tonumber(def.act_st) or 0
    return act_st == 0 or act_st == 1
end

function ComboData.resolve_end_mode(end_mode, state, atk, def)
    if end_mode ~= "latest" then
        return end_mode
    end

    local attacker_recovered = false
    local defender_recovered = ComboData.is_defender_recovered(def)

    if state and state.is_blocked then
        attacker_recovered = atk and atk.act_st == 0
    elseif state and state.is_throw then
        attacker_recovered = atk and atk.act_st ~= 37
    else
        attacker_recovered = atk and ((atk.combo_count or 0) == 0 or ComboData.is_neutral_recovery_state(atk))
    end

    if attacker_recovered and not defender_recovered then
        return "defender_recovery"
    end
    if defender_recovered and not attacker_recovered then
        return "attacker_recovery"
    end

    return "defender_recovery"
end

function ComboData.is_throw_ready_to_start(atk)
    if not atk then return false end
    if (tonumber(atk.combo_count) or 0) > 0 then return true end
    return (tonumber(atk.action_frame) or 0) >= THROW_CONNECT_MIN_ACTION_FRAME
end

function ComboData.settle_finished_advantage(state, p1, p2)
    if not state.finished or not state.advantage_settle_remaining or state.advantage_settle_remaining <= 0 then
        return
    end

    ComboData.update_advantage_if_larger(state.finish.p1, p1)
    ComboData.update_advantage_if_larger(state.finish.p2, p2)
    state.advantage_settle_remaining = state.advantage_settle_remaining - 1
end

function ComboData.any_sequence_started()
    if not ComboData.player_states then return false end

    for i = 0, 1 do
        local state = ComboData.player_states[i]
        if state and state.started == true then
            return true
        end
    end

    return false
end

function ComboData.any_finished_sequence_settling()
    if not ComboData.player_states then return false end

    for i = 0, 1 do
        local state = ComboData.player_states[i]
        if state and state.finished == true and state.started ~= true then
            if state.knockdown_drive_settle == true then
                return true
            end
            if (tonumber(state.advantage_settle_remaining) or 0) > 0 then
                return true
            end
        end
    end

    return false
end

function ComboData.resource_values_changed(prev, current)
    if not prev or not current then return false end

    return (tonumber(prev.drive_adjusted) or 0) ~= (tonumber(current.drive_adjusted) or 0)
        or (prev.incapacitated == true) ~= (current.incapacitated == true)
        or (tonumber(prev.super) or 0) ~= (tonumber(current.super) or 0)
end

function ComboData.touch_precombo_resource_baseline(player_idx, prev, current)
    if not ComboData.resource_precombo_baselines then
        ComboData.resource_precombo_baselines = { [0] = nil, [1] = nil }
    end

    local existing = ComboData.resource_precombo_baselines[player_idx]
    if not existing then
        existing = Utils.deep_copy(prev)
        existing.resource_age = 0
        existing.resource_ttl = PRECOMBO_RESOURCE_BASELINE_FRAMES
        existing.resource_action_id = current and current.action_id or nil
        existing.resource_action_frame = current and current.action_frame or nil
        ComboData.resource_precombo_baselines[player_idx] = existing
        return
    end

    -- Preserve the earliest values that make opener costs/losses/gains visible:
    -- higher Drive before a spend/loss and lower Super before an on-hit gain.
    if prev.drive_adjusted ~= nil and (existing.drive_adjusted == nil or prev.drive_adjusted > existing.drive_adjusted) then
        existing.drive_adjusted = prev.drive_adjusted
        existing.incapacitated = prev.incapacitated
    end
    if prev.super ~= nil and (existing.super == nil or prev.super < existing.super) then
        existing.super = prev.super
    end

    existing.resource_age = 0
    existing.resource_ttl = PRECOMBO_RESOURCE_BASELINE_FRAMES
    existing.resource_action_id = current and current.action_id or existing.resource_action_id
    existing.resource_action_frame = current and current.action_frame or existing.resource_action_frame
end

function ComboData.update_resource_baselines(p1, p2)
    local sequence_started = ComboData.any_sequence_started()
    local sequence_settling = ComboData.any_finished_sequence_settling and ComboData.any_finished_sequence_settling() or false
    local throw_sequence_started = ComboData.is_throw_state(p1) or ComboData.is_throw_state(p2)

    -- Do not let active combos or post-combo settle frames seed resource
    -- baselines for the next sequence. Those stale baselines can make the next
    -- combo's Drive start/total display the previous combo's finish endpoint.
    -- Treat throw startup as live too; throws can spend Drive before combo_count
    -- increments, and letting refill logic keep seeding baselines there hides the
    -- throw's own resource snapshot.
    if sequence_started or sequence_settling or throw_sequence_started then
        ComboData.clear_all_resource_baselines()
        return
    end

    for i = 0, 1 do
        local current = (i == 0 and p1 or p2)
        local prev = (i == 0 and ComboData.p1_prev or ComboData.p2_prev)
        if current then
            if not ComboData.resource_baselines[i] then
                ComboData.resource_baselines[i] = Utils.deep_copy(current)
                ComboData.resource_baselines[i].baseline_action_id = current.action_id
            end

            if prev and (prev.hp_current ~= nil or prev.drive_adjusted ~= nil or prev.super ~= nil) then
                local action_changed = current.action_id ~= prev.action_id
                local action_wrapped = current.action_id == prev.action_id and (current.action_frame or 0) < (prev.action_frame or 0)
                if action_changed or action_wrapped then
                    ComboData.resource_baselines[i] = Utils.deep_copy(prev)
                    ComboData.resource_baselines[i].baseline_action_id = current.action_id
                end

                local recent = ComboData.resource_precombo_baselines and ComboData.resource_precombo_baselines[i] or nil
                if recent then
                    recent.resource_age = (recent.resource_age or 0) + 1
                    recent.resource_ttl = (recent.resource_ttl or PRECOMBO_RESOURCE_BASELINE_FRAMES) - 1
                    if recent.resource_ttl <= 0 then
                        ComboData.resource_precombo_baselines[i] = nil
                        recent = nil
                    end
                end

                if ComboData.resource_values_changed(prev, current) then
                    -- Training Mode refill can reset Drive to a lower value
                    -- (e.g., from 39000 to 30000). The precombo baseline
                    -- preserves the highest Drive seen, but when refill reduces
                    -- Drive, that stale high value produces incorrect combo
                    -- start totals. Detect refill-driven decreases, clear the
                    -- stale baseline, and let the next resource change seed a
                    -- fresh baseline from the current (post-refill) value.
                    local current_drive = tonumber(current.drive_adjusted) or 0
                    local prev_drive = tonumber(prev.drive_adjusted) or 0
                    local drive_decrease = prev_drive - current_drive
                    if drive_decrease > 100 and GameObjects.TrainingManager then
                        ComboData.resource_precombo_baselines[i] = nil
                    else
                        ComboData.touch_precombo_resource_baseline(i, prev, current)
                    end
                end
            end
        end
    end
end
function ComboData.copy_start_resources_from_baseline(start_player, baseline)
    if not start_player or not baseline then return false end

    local changed = false
    local current_start_drive = tonumber(start_player.drive_adjusted)
    local baseline_drive = tonumber(baseline.drive_adjusted)
    if baseline_drive ~= nil and (current_start_drive == nil or baseline_drive > current_start_drive) then
        start_player.drive_adjusted = baseline.drive_adjusted
        if baseline.incapacitated ~= nil then
            start_player.incapacitated = baseline.incapacitated
        end
        changed = true
    end

    local current_start_super = tonumber(start_player.super)
    local baseline_super = tonumber(baseline.super)
    if baseline_super ~= nil and (current_start_super == nil or baseline_super < current_start_super) then
        start_player.super = baseline_super
        changed = true
    end

    return changed
end

function ComboData.merge_start_resources_from_recent_baseline(start_player, recent)
    if not start_player or not recent then return false end

    local changed = false
    local current_start_drive = tonumber(start_player.drive_adjusted)
    local recent_drive = tonumber(recent.drive_adjusted)
    if recent_drive ~= nil and (current_start_drive == nil or recent_drive > current_start_drive) then
        start_player.drive_adjusted = recent_drive
        if recent.incapacitated ~= nil then
            start_player.incapacitated = recent.incapacitated
        end
        changed = true
    end

    local current_start_super = tonumber(start_player.super)
    local recent_super = tonumber(recent.super)
    if recent_super ~= nil and (current_start_super == nil or recent_super < current_start_super) then
        start_player.super = recent_super
        changed = true
    end

    return changed
end

function ComboData.recent_resource_baseline_would_show_drive_spend(player_idx, current, max_age)
    local recent = ComboData.resource_precombo_baselines and ComboData.resource_precombo_baselines[player_idx] or nil
    if not recent then return false end
    if (recent.resource_ttl or 0) <= 0 then return false end
    if max_age ~= nil and (recent.resource_age or 0) > max_age then return false end
    if not current then return false end

    local current_drive = tonumber(current.drive_adjusted) or 0
    local recent_drive = tonumber(recent.drive_adjusted) or current_drive
    return current_drive - recent_drive <= -9000
end

function ComboData.apply_drive_cooldown_resource_fallback(state, start_player, current)
    local cooldown = tonumber(current and current.drive_cooldown) or 0
    local fallback_cost = nil
    if cooldown > 200 and ComboData.is_drive_impact_state(current) then
        fallback_cost = DRIVE_IMPACT_RESOURCE_COST
    elseif cooldown <= -120 then
        if (state and state.is_drive_impact_sequence) or ComboData.is_drive_impact_state(current) then
            fallback_cost = DRIVE_IMPACT_RESOURCE_COST
        else
            fallback_cost = DRIVE_RUSH_RESOURCE_COST
        end
    end
    if not fallback_cost then return false end

    local current_drive = tonumber(current and current.drive_adjusted)
    if current_drive ~= nil then
        start_player.drive_adjusted = current_drive + fallback_cost
    else
        start_player.drive_adjusted = (start_player.drive_adjusted or 0) + fallback_cost
    end
    return true
end

function ComboData.get_training_drive_refill_override_debug(prev, current)
    if not current then return false, "current=nil" end
    if GameObjects.TrainingManager == nil then return false, "training_manager=nil" end
    if ComboData.is_throw_state(current) then return false, "throw_pending=true" end
    if ComboData.any_sequence_started() then return false, "sequence_started=true" end

    local target = tonumber(current.training_drive_target)
    local current_drive = tonumber(current.drive_adjusted)
    if target == nil or target <= 0 then return false, "target<=0" end
    if current_drive == nil then return false, "current_drive=nil" end

    local point_lock = current.training_drive_point_lock == true
    local runtime_timer = tonumber(current.training_drive_runtime_timer) or 0
    local configured_timer = tonumber(current.training_drive_configured_timer) or 0
    if not point_lock and runtime_timer <= 0 then
        return false, "point_lock=false runtime_timer=" .. tostring(runtime_timer)
    end
    if configured_timer <= 0 and runtime_timer <= 0 and not point_lock then
        return false, "configured_timer<=0 runtime_timer<=0"
    end

    local distance_to_target = math.abs(current_drive - target)
    if distance_to_target > 100 then
        return false, "target_distance=" .. tostring(distance_to_target)
    end

    return true,
        "target_distance=" .. tostring(distance_to_target)
            .. " point_lock=" .. tostring(point_lock)
            .. " runtime_timer=" .. tostring(runtime_timer)
            .. " configured_timer=" .. tostring(configured_timer)
end

function ComboData.is_training_drive_refill_override(prev, current)
    local is_override = ComboData.get_training_drive_refill_override_debug(prev, current)
    return is_override == true
end

function ComboData.debug_log_drive_cooldown(player_index, phase, prev, current, legitimacy, note)
    if Config.settings.toggle_enable_drive_cooldown_debug ~= true then return end
    local prev_cd = tonumber(prev and prev.drive_cooldown) or 0
    local current_cd = tonumber(current and current.drive_cooldown) or 0
    local prev_drive = tonumber(prev and prev.drive_adjusted) or 0
    local current_drive = tonumber(current and current.drive_adjusted) or 0
    local lock = current and current.training_drive_point_lock == true or false
    local target = tonumber(current and current.training_drive_target) or 0
    local configured_timer = tonumber(current and current.training_drive_configured_timer) or 0
    local runtime_timer = tonumber(current and current.training_drive_runtime_timer) or 0
    local signature = table.concat({
        tostring(phase),
        tostring(prev_cd),
        tostring(current_cd),
        tostring(prev_drive),
        tostring(current_drive),
        tostring(legitimacy),
        tostring(lock),
        tostring(target),
        tostring(configured_timer),
        tostring(runtime_timer),
        tostring(note),
    }, "|")

    if ComboData.runtime_state.drive_cooldown_debug_last[player_index] == signature then
        return
    end
    ComboData.runtime_state.drive_cooldown_debug_last[player_index] = signature

    ComboData.debug_log(
        "DRIVE_COOLDOWN p" .. tostring(player_index)
            .. " phase=" .. tostring(phase)
            .. " prev_cd=" .. tostring(prev_cd)
            .. " current_cd=" .. tostring(current_cd)
            .. " prev_drive=" .. tostring(prev_drive)
            .. " current_drive=" .. tostring(current_drive)
            .. " legitimacy=" .. tostring(legitimacy)
            .. " point_lock=" .. tostring(lock)
            .. " target=" .. tostring(target)
            .. " configured_timer=" .. tostring(configured_timer)
            .. " runtime_timer=" .. tostring(runtime_timer)
            .. " any_sequence_started=" .. tostring(ComboData.any_sequence_started())
            .. " cd_total_peak=" .. tostring(ComboData.drive_cooldown_total_peak[player_index] or 0)
            .. " note=" .. tostring(note),
        "log_display_update",
        true
    )
end

function ComboData.apply_start_resource_baseline(state, player_idx, current, allow_action_baseline, allow_recent_baseline, recent_max_age)
    local key = player_idx == 0 and "p1" or "p2"
    local start_player = state and state.start and state.start[key] or nil
    if not start_player or not current then return false end

    local changed = false
    if allow_action_baseline ~= false then
        local baseline = ComboData.resource_baselines and ComboData.resource_baselines[player_idx] or nil
        if baseline and baseline.baseline_action_id == current.action_id then
            changed = ComboData.copy_start_resources_from_baseline(start_player, baseline) or changed
        end
    end

    if allow_recent_baseline ~= false then
        local recent = ComboData.resource_precombo_baselines and ComboData.resource_precombo_baselines[player_idx] or nil
        if recent
            and (recent.resource_ttl or 0) > 0
            and (recent_max_age == nil or (recent.resource_age or 0) <= recent_max_age)
        then
            changed = ComboData.merge_start_resources_from_recent_baseline(start_player, recent) or changed
        end
    end

    if changed then
        return true
    end

    if allow_action_baseline == false then
        return false
    end

    -- Fallback for resource spends already reflected before combo count starts.
    -- Positive cooldown identifies DI directly. Negative cooldown can also
    -- appear on DI continuation frames, so DI action ids keep the cost at 10k.
    return ComboData.apply_drive_cooldown_resource_fallback(state, start_player, current)
end

function ComboData.player_start_has_drive_spend(state, player_idx, current)
    local key = player_idx == 0 and "p1" or "p2"
    local start_player = state and state.start and state.start[key] or nil
    if not start_player or not current then return false end

    local drive_delta = (tonumber(current.drive_adjusted) or 0) - (tonumber(start_player.drive_adjusted) or 0)
    return drive_delta <= -9000
end

function ComboData.player_has_known_drive_spend(player_idx, current)
    if not current then return false, "current=nil" end

    if ComboData.recent_resource_baseline_would_show_drive_spend(player_idx, current, PRECOMBO_RESOURCE_BASELINE_FRAMES) then
        return true, "recent_baseline"
    end

    if not ComboData.player_states then return false, "no_player_states" end

    for attacker_idx = 0, 1 do
        local state = ComboData.player_states[attacker_idx]
        if ComboData.player_start_has_drive_spend(state, player_idx, current) then
            return true, "state_start_p" .. tostring(attacker_idx)
        end
    end

    return false, "no_known_spend"
end

function ComboData.get_pending_attack_frames(current)
    if not current then return nil end

    local total = tonumber(current.action_total_frames)
    local frame = tonumber(current.action_frame)
    if total == nil or total <= 0 or frame == nil or frame < 0 then
        return nil
    end

    return math.max(0, total - frame)
end

function ComboData.update_drive_cooldown_pending(player_idx, prev, current)
    if not ComboData.drive_cooldown_pending then
        ComboData.drive_cooldown_pending = { [0] = false, [1] = false }
    end
    if not ComboData.drive_cooldown_pending_age then
        ComboData.drive_cooldown_pending_age = { [0] = 0, [1] = 0 }
    end
    if not ComboData.drive_cooldown_pending_peak then
        ComboData.drive_cooldown_pending_peak = { [0] = 0, [1] = 0 }
    end
    if not ComboData.drive_cooldown_total_peak then
        ComboData.drive_cooldown_total_peak = { [0] = 0, [1] = 0 }
    end
    if not ComboData.drive_cooldown_pending_peak_final then
        ComboData.drive_cooldown_pending_peak_final = { [0] = 0, [1] = 0 }
    end

    if not current then
        ComboData.drive_cooldown_pending[player_idx] = false
        ComboData.drive_cooldown_pending_age[player_idx] = 0
        ComboData.drive_cooldown_pending_peak[player_idx] = 0
        ComboData.drive_cooldown_total_peak[player_idx] = 0
        ComboData.drive_cooldown_pending_peak_final[player_idx] = 0
        return
    end

    local current_cd = tonumber(current.drive_cooldown) or 0
    local pending_frames = ComboData.get_pending_attack_frames(current)
    if current_cd > 0 then
        if ComboData.drive_cooldown_pending[player_idx] == true then
            ComboData.drive_cooldown_pending_peak_final[player_idx] = current_cd
            if Config.settings.toggle_enable_drive_cooldown_debug == true then
                ComboData.debug_log(
                "DRIVE_COOLDOWN_PENDING p" .. tostring(player_idx)
                    .. " phase=handoff"
                    .. " current_cd=" .. tostring(current_cd)
                    .. " pending_frames=" .. tostring(pending_frames)
                    .. " total_peak=" .. tostring(ComboData.drive_cooldown_total_peak[player_idx])
                    .. " pending_peak_final=" .. tostring(ComboData.drive_cooldown_pending_peak_final[player_idx]),
                "log_display_update",
                true
            )
            end
        end
        ComboData.drive_cooldown_pending[player_idx] = false
        ComboData.drive_cooldown_pending_age[player_idx] = 0
        ComboData.drive_cooldown_pending_peak[player_idx] = 0
        return
    end

    local is_override = ComboData.is_training_drive_refill_override(prev, current)
    if is_override then
        ComboData.drive_cooldown_pending[player_idx] = false
        ComboData.drive_cooldown_pending_age[player_idx] = 0
        ComboData.drive_cooldown_pending_peak[player_idx] = 0
        ComboData.drive_cooldown_total_peak[player_idx] = 0
        return
    end

    local prev_drive = tonumber(prev and prev.drive_adjusted) or 0
    local current_drive = tonumber(current.drive_adjusted) or 0
    local drive_drop = prev_drive - current_drive
    if drive_drop > 1000 then
        ComboData.drive_cooldown_pending[player_idx] = true
        ComboData.drive_cooldown_pending_age[player_idx] = 0
        ComboData.drive_cooldown_pending_peak[player_idx] = math.max(
            tonumber(ComboData.drive_cooldown_pending_peak[player_idx]) or 0,
            pending_frames or 0
        )
        ComboData.drive_cooldown_total_peak[player_idx] = math.max(
            tonumber(ComboData.drive_cooldown_total_peak[player_idx]) or 0,
            (pending_frames or 0) + 120
        )
        if Config.settings.toggle_enable_drive_cooldown_debug == true then
            ComboData.debug_log(
                "DRIVE_COOLDOWN_PENDING p" .. tostring(player_idx)
                    .. " phase=spend"
                    .. " action_total_frames=" .. tostring(current.action_total_frames)
                    .. " action_frame=" .. tostring(current.action_frame)
                    .. " pending_frames=" .. tostring(pending_frames)
                    .. " pending_peak=" .. tostring(ComboData.drive_cooldown_pending_peak[player_idx])
                    .. " total_peak=" .. tostring(ComboData.drive_cooldown_total_peak[player_idx]),
                "log_display_update",
                true
            )
        end
        return
    end

    if ComboData.drive_cooldown_pending[player_idx] == true then
        local age = (ComboData.drive_cooldown_pending_age[player_idx] or 0) + 1
        if pending_frames ~= nil and pending_frames > 0 then
            ComboData.drive_cooldown_pending_peak[player_idx] = math.max(
                tonumber(ComboData.drive_cooldown_pending_peak[player_idx]) or 0,
                pending_frames
            )
        end
        local target = tonumber(current.training_drive_target)
        local at_target = target ~= nil and target > 0 and math.abs(current_drive - target) <= 100
        if age > 480 or current_drive > prev_drive + 100 or at_target or (pending_frames ~= nil and pending_frames <= 0) then
            ComboData.drive_cooldown_pending[player_idx] = false
            ComboData.drive_cooldown_pending_age[player_idx] = 0
            ComboData.drive_cooldown_pending_peak[player_idx] = 0
        else
            ComboData.drive_cooldown_pending_age[player_idx] = age
        end
    end
end

function ComboData.is_drive_impact_sequence_still_recovering(state, atk, def)
    if not state or state.is_drive_impact_sequence ~= true then return false end
    if state.is_blocked or state.is_throw then return false end
    if not atk or not def then return false end
    if (tonumber(def.act_st) or 0) == 0 then return false end

    local combo_count = tonumber(atk.combo_count) or 0
    local current_hit_damage = tonumber(atk.current_hit_damage) or 0
    local combo_damage = tonumber(atk.combo_damage) or 0
    local locked_combo_damage = tonumber(state.combo_damage_lock) or 0

    -- Drive Impact routes can leave defender act_st non-zero after recovery.
    -- Treat DI as still recovering only while there is live combo activity or
    -- a newly increasing combo-damage total on the current frame.
    return combo_count > 0
        or current_hit_damage > 0
        or combo_damage > locked_combo_damage
end

function ComboData.clear_recent_resource_baselines()
    if ComboData.resource_precombo_baselines then
        ComboData.resource_precombo_baselines[0] = nil
        ComboData.resource_precombo_baselines[1] = nil
    end
end

function ComboData.clear_all_resource_baselines()
    ComboData.resource_baselines = { [0] = nil, [1] = nil }
    ComboData.clear_recent_resource_baselines()
end

function ComboData.clear_finished_display_box(player_index, reason)
    local state = ComboData.player_states and ComboData.player_states[player_index]
    if not state then return false end

    -- Only clear stale/retained boxes. If this player currently has their own
    -- active combo/blockstring, leave that box alone.
    if state.started == true then return false end
    if state.finished ~= true then return false end

    -- If the combo timer is still running, do not destroy the finished state;
    -- let the timer handle cleanup when it expires (guard for combo_timer_duration > 0).
    -- When a new attack triggers the clear (reason="damage"/"block"), the stale
    -- state must be removed regardless of the timer so the defender's display
    -- shows the incoming attack's data instead of an old attacker combo.
    if state.timer_remaining and state.timer_remaining > 0 then
        if reason ~= "damage" and reason ~= "block" then
            return false
        end
    end

    state.finished = false
    state.timer_remaining = nil
    state.knockdown_drive_settle = false
    state.knockdown_drive_settle_frames = nil
    state.advantage_settle_remaining = 0
    state.block_end_grace_remaining = 0
    state.defender_recovery_grace_remaining = 0
    state.throw_end_wait_for_exit = false
    ComboData.clear_pending_start(state)
    state.clear_hidden_reason = reason or "incoming_attack"
    return true
end

function ComboData.clear_defender_display_box_for_incoming_attack(attacker_index, attack_kind)
    if attack_kind ~= "hit" and attack_kind ~= "block" then return false end

    local should_clear = Config.settings.toggle_clear_on_damage == true
        or (attack_kind == "hit" and Config.settings.toggle_update_on_damage == true)
    if attack_kind == "block" then
        should_clear = Config.settings.toggle_clear_on_block == true
            or Config.settings.toggle_update_on_block == true
    end
    if not should_clear then return false end

    local defender_index = attacker_index == 0 and 1 or 0
    if attack_kind == "hit"
        and UI.should_keep_trade_self_state
        and UI.should_keep_trade_self_state(defender_index, ComboData.player_states[defender_index], ComboData.player_states[attacker_index])
    then
        return false
    end

    return ComboData.clear_finished_display_box(defender_index, attack_kind == "block" and "block" or "damage")
end

function ComboData.update_state(p1, p2)
    if (tonumber(ComboData.snapshot_load_guard_frames) or 0) > 0 then
        ComboData.snapshot_load_guard_frames = (tonumber(ComboData.snapshot_load_guard_frames) or 0) - 1
        if ComboData.should_defer_after_snapshot_load(p1, p2) then
            ComboData.clear_snapshot_load_guard_if_done()
            return
        end
        ComboData.clear_snapshot_load_guard_if_done()
    end

    local current_global_combo_id = GameObjects.get_combo_id()
    ComboData.runtime_state.last_global_combo_id = current_global_combo_id

    ComboData.update_resource_baselines(p1, p2)

    -- Track action wrapping for throw carry baseline.
    -- When a new action begins (action_id changes or loops), capture the
    -- frame-before-startup position/gap values. For throws, this baseline is
    -- used instead of p1_prev/p2_prev so that throw startup movement (run
    -- forward, gap closure) is not baked into the start baseline and correctly
    -- contributes to carry/gap deltas.
    for pi = 0, 1 do
        local curr = (pi == 0 and p1 or p2)
        local prev = (pi == 0 and ComboData.p1_prev or ComboData.p2_prev)
        if curr and prev then
            local curr_action_id = curr.action_id
            local prev_action_id = prev.action_id
            local curr_action_frame = tonumber(curr.action_frame) or 0
            local prev_action_frame = tonumber(prev.action_frame) or 0
            if curr_action_id ~= nil and prev_action_id ~= nil then
                local action_changed = curr_action_id ~= prev_action_id
                    or (curr_action_id == prev_action_id and curr_action_frame < prev_action_frame and prev_action_frame > 0)
                if action_changed then
                    if not ComboData.throw_carry_baseline then
                        ComboData.throw_carry_baseline = {}
                    end
                    ComboData.throw_carry_baseline[pi] = Utils.deep_copy(prev)
                end
            end
        end
    end

    for i = 0, 1 do
        local state = ComboData.player_states[i]
        local atk, def = (i == 0 and p1 or p2), (i == 0 and p2 or p1)
        local def_prev = (i == 0 and ComboData.p2_prev or ComboData.p1_prev)
        local atk_prev = (i == 0 and ComboData.p1_prev or ComboData.p2_prev)
        local attack_kind = ComboData.get_active_attack_kind(atk, def, def_prev)
        if attack_kind then
            ComboData.debug_log("ATTACK_DETECTED p" .. tostring(i)
                .. " kind=" .. tostring(attack_kind)
                .. " atk.hp=" .. tostring(atk and atk.hp_current)
                .. " atk.combo_count=" .. tostring(atk and atk.combo_count)
                .. " atk.combo_damage=" .. tostring(atk and atk.combo_damage)
                .. " atk.current_hit_damage=" .. tostring(atk and atk.current_hit_damage)
                .. " atk.attack_name=" .. tostring(atk and atk.attack_name)
                .. " atk.guard_combo_count=" .. tostring(atk and atk.guard_combo_count)
                .. " atk.guard_time=" .. tostring(atk and atk.guard_time)
                .. " atk.act_st=" .. tostring(atk and atk.act_st)
                .. " def.hp=" .. tostring(def and def.hp_current)
                .. " def.combo_count=" .. tostring(def and def.combo_count)
                .. " def.guard_combo_count=" .. tostring(def and def.guard_combo_count)
                .. " def.guard_time=" .. tostring(def and def.guard_time)
                .. " def.act_st=" .. tostring(def and def.act_st)
                .. " def.attack_name=" .. tostring(def and def.attack_name)
                .. " def.down_count=" .. tostring(def and def.down_count)
                .. " def.sp_armor=" .. tostring(def and def.sp_armor)
                .. " def.armor_now=" .. tostring(def and def.armor_now), "log_display_update"
            )
        end
        -- BEGIN Parry/Drive Rush tracking
        if not ComboData.parry_tracker then
            ComboData.parry_tracker = { [0] = nil, [1] = nil }
        end
        local parry_tracker = ComboData.parry_tracker[i]

        -- Entering Parry: save the pre-Parry Drive value.
        -- Any previous state (attack, block, neutral, walk, etc.) is fine.
        if ComboData.is_parry_state(atk) and not ComboData.is_parry_state(atk_prev) then
            parry_tracker = {
                drive = tonumber(atk_prev.drive_adjusted) or (tonumber(atk.drive_adjusted) or 0),
                active = true,
            }
            ComboData.parry_tracker[i] = parry_tracker
        end

        -- When the player leaves Parry, start a grace counter to keep the
        -- pre-Parry Drive snapshot alive through the Parry -> Drive Rush chain.
        if parry_tracker and parry_tracker.active then
            if not ComboData.is_parry_state(atk) and ComboData.is_parry_state(atk_prev) then
                parry_tracker.post_parry_frames = 15
            elseif parry_tracker.post_parry_frames and parry_tracker.post_parry_frames > 0 then
                parry_tracker.post_parry_frames = parry_tracker.post_parry_frames - 1
            end
        end

        -- Clear the parry tracker only after the post-Parry grace expires and
        -- the player has returned to neutral without attacking.
        if parry_tracker and parry_tracker.active then
            local grace_expired = parry_tracker.post_parry_frames ~= nil and parry_tracker.post_parry_frames <= 0
            if grace_expired and ComboData.is_neutral_act_st(atk) and not ComboData.is_parry_state(atk) then
                ComboData.parry_tracker[i] = nil
                parry_tracker = nil
            end
        end

        -- When an attack connects and a parry tracker is active,
        -- override the pending_start attacker Drive with the pre-Parry value.
        if attack_kind and parry_tracker and parry_tracker.active then
            local pending_start = state.pending_start
            if not pending_start then
                state.pending_start = { p1 = Utils.deep_copy(ComboData.p1_prev), p2 = Utils.deep_copy(ComboData.p2_prev) }
                pending_start = state.pending_start
            end
            local pending_attacker = i == 0 and pending_start.p1 or pending_start.p2
            if pending_attacker then
                pending_attacker.drive_adjusted = parry_tracker.drive
            end
        end
        -- END Parry/Drive Rush tracking

        ComboData.clear_defender_display_box_for_incoming_attack(i, attack_kind)
        if attack_kind == "throw" and not state.started then
            ComboData.clear_pending_start(state)
        end
        -- Clear throw carry baseline for non-throw attacks so stale
        -- position baselines from whiffed actions are not reused.
        if attack_kind and attack_kind ~= "throw" then
            ComboData.throw_carry_baseline = nil
        end
        local current_hit_damage = math.max(
            tonumber(atk and atk.current_hit_damage) or 0,
            tonumber(def and def.current_hit_damage) or 0,
            tonumber(def_prev and def_prev.current_hit_damage) or 0
        )

        local precombo_opener_damage = ComboData.did_precombo_opener_damage_start(atk, atk_prev, def, def_prev)

        ComboData.expire_pending_start_if_stale(state, attack_kind, precombo_opener_damage)

        -- Detect new combo via Combo ID change. When the global combo ID changes
        -- while an attack is active, treat it as a new combo and allow starter
        -- values to be overwritten.
        local combo_id_changed = current_global_combo_id ~= 0 and current_global_combo_id ~= state.last_seen_combo_id

        if attack_kind ~= "throw" then
            state.throw_end_wait_for_exit = false
        end

        local same_finished_catch_action = false
        if state.finished == true and attack_kind == "throw" and atk and (atk.act_st or 0) == 37 then
            local finished_attacker = state.finish and state.finish[i == 0 and "p1" or "p2"] or nil
            local finished_action_id = finished_attacker and finished_attacker.action_id
            local finished_action_frame = tonumber(finished_attacker and finished_attacker.action_frame) or 0
            same_finished_catch_action = finished_action_id ~= nil
                and finished_action_id == atk.action_id
                and (tonumber(atk.action_frame) or 0) >= finished_action_frame
        end

        local suppress_throw_restart = state.finished == true
            and attack_kind == "throw"
            and atk and (atk.act_st or 0) == 37
            and (state.is_throw == true and state.throw_end_wait_for_exit == true or same_finished_catch_action)

        local throw_ready_to_start = attack_kind ~= "throw"
            or ComboData.is_throw_ready_to_start(atk)
            or (state.finished == true and state.is_blocked == true)
            or (state.is_blocked == true and attack_kind == "throw")

        local throw_can_restart_block = attack_kind == "throw"
            and state.started == true
            and (state.is_blocked == true or state.finished == true)

        if throw_ready_to_start
            and not suppress_throw_restart
            and (not state.started or throw_can_restart_block)
            and def_prev.hp_current
            and (attack_kind or precombo_opener_damage)
        then
            if not state.pending_start then
                state.pending_start = { p1 = Utils.deep_copy(ComboData.p1_prev), p2 = Utils.deep_copy(ComboData.p2_prev) }
            end

            local pending_defender = i == 0 and state.pending_start.p2 or state.pending_start.p1
            local pending_hp = tonumber(def_prev and def_prev.hp_current) or 0
            if pending_defender and pending_hp > (tonumber(pending_defender.hp_current) or 0) then
                pending_defender.hp_current = pending_hp
            end
            if pending_defender and def_prev and def_prev.is_poisoned then
                pending_defender.is_poisoned = true
            end
            if (def and def.is_poisoned) or (def_prev and def_prev.is_poisoned) then
                state.pending_poison_was_active = true
            end
            state.pending_start_hp_lock = math.max(
                tonumber(state.pending_start_hp_lock) or 0,
                tonumber(pending_defender and pending_defender.hp_current) or 0,
                pending_hp
            )

            local pending_attacker = i == 0 and state.pending_start.p1 or state.pending_start.p2
            local current_attacker = i == 0 and p1 or p2
            if ComboData.is_drive_impact_state(pending_attacker) or ComboData.is_drive_impact_state(current_attacker) then
                state.pending_start_drive_impact_sequence = true
            end
            if pending_attacker and current_attacker then
                local current_super = tonumber(current_attacker.super)
                local pending_super = tonumber(pending_attacker.super)
                if current_super ~= nil and (pending_super == nil or current_super < pending_super) then
                    pending_attacker.super = current_attacker.super
                end
            end
        end

        if not attack_kind then
            ComboData.settle_finished_advantage(state, p1, p2)
        end

        if throw_ready_to_start
            and not suppress_throw_restart
            and (not state.started or throw_can_restart_block)
            and attack_kind
            and def_prev.hp_current
        then
            ComboData.debug_log("COMBO_START p" .. tostring(i)
                .. " kind=" .. tostring(attack_kind)
                .. " atk.combo_count=" .. tostring(atk and atk.combo_count)
                .. " atk.combo_damage=" .. tostring(atk and atk.combo_damage)
                .. " atk.current_hit_damage=" .. tostring(atk and atk.current_hit_damage)
                .. " atk.hp=" .. tostring(atk and atk.hp_current)
                .. " atk.attack_name=" .. tostring(atk and atk.attack_name)
                .. " atk.drive=" .. tostring(atk and atk.drive_adjusted)
                .. " atk.drive_cooldown=" .. tostring(atk and atk.drive_cooldown)
                .. " atk.super=" .. tostring(atk and atk.super)
                .. " atk.action_id=" .. tostring(atk and atk.action_id)
                .. " atk.act_st=" .. tostring(atk and atk.act_st)
                .. " def.hp=" .. tostring(def and def.hp_current)
                .. " def.drive=" .. tostring(def and def.drive_adjusted)
                .. " def.drive_cooldown=" .. tostring(def and def.drive_cooldown)
                .. " def.super=" .. tostring(def and def.super)
                .. " def.action_id=" .. tostring(def and def.action_id)
                .. " def.attack_name=" .. tostring(def and def.attack_name)
                .. " def.act_st=" .. tostring(def and def.act_st)
                .. " def.sp_armor=" .. tostring(def and def.sp_armor)
                .. " def.armor_now=" .. tostring(def and def.armor_now)
                .. " def_prev.hp=" .. tostring(def_prev and def_prev.hp_current)
                .. " pending_start_hp_lock=" .. tostring(state.pending_start_hp_lock), "log_display_update"
            )
            local pending_start = state.pending_start
            local pending_start_hp_lock = state.pending_start_hp_lock
            local preserve_ko_start_snapshot = state.ko_start_snapshot_locked == true or state.ko_start_hp_locked == true
            local saved_start = preserve_ko_start_snapshot and Utils.deep_copy(state.start) or nil
            local saved_start_hp_lock = preserve_ko_start_snapshot and state.start_hp_lock or nil
            local saved_ko_start_hp_locked = preserve_ko_start_snapshot and state.ko_start_hp_locked or false
            local saved_ko_start_snapshot = preserve_ko_start_snapshot and Utils.deep_copy(state.ko_start_snapshot) or nil
            local saved_ko_start_snapshot_locked = preserve_ko_start_snapshot and state.ko_start_snapshot_locked or false
            local saved_hit_damage_lock = preserve_ko_start_snapshot and Utils.deep_copy(state.hit_damage_lock) or nil
            local saved_hit_damage_lock_frozen = preserve_ko_start_snapshot and state.hit_damage_lock_frozen or false
            local saved_hit_damage_lock_provisional = preserve_ko_start_snapshot and state.hit_damage_lock_provisional or false
            local saved_hit_damage_lock_combo_damage_total = preserve_ko_start_snapshot and state.hit_damage_lock_combo_damage_total or nil
            local saved_pending_ko_hit_damage_delta = preserve_ko_start_snapshot and Utils.deep_copy(state.pending_ko_hit_damage_delta) or nil
            local saved_combo_damage_lock = preserve_ko_start_snapshot and state.combo_damage_lock or nil
            state.started, state.finished = true, false
            state.timer_remaining = nil  -- clear stale timer from previous finished combo
            state.is_blocked = attack_kind == "block"
            state.is_trade_sequence = attack_kind == "hit" and ComboData.is_trade_start(atk, def)
            state.is_throw = attack_kind == "throw"
            state.is_drive_impact_sequence = (not state.is_blocked and not state.is_throw)
                and (state.pending_start_drive_impact_sequence == true or ComboData.is_drive_impact_state(atk))
            state.ended_in_knockdown = false
            state.ended_in_ko = false
            state.ko_carry_finish_p1_x = nil
            state.ko_carry_finish_p2_x = nil
            state.ko_carry_total_p1 = nil
            state.ko_carry_total_p2 = nil
            state.throw_side_switch_frames = 0
            state.throw_side_switch_last_action_frame = nil
            state.knockdown_drive_settle = false
            state.knockdown_drive_settle_frames = nil
            state.block_end_grace_remaining = state.is_blocked and Config.get_string_gap() or 0
            state.defender_recovery_grace_remaining = 0
            state.advantage_settle_remaining = 0
            state.advantage_lock = nil
            state.hit_damage_lock = nil
            state.hit_damage_lock_frozen = false
            state.hit_damage_lock_provisional = false
            state.hit_damage_lock_combo_damage_total = nil
            state.pending_ko_hit_damage_delta = nil
            state.combo_damage_lock = nil
            state.hit_start_hp = nil
            state.start_hp_lock = nil
            state.ko_start_hp_locked = false
            state.ko_start_snapshot = nil
            state.ko_start_snapshot_locked = false
            state.poison_was_active = false
            state.clear_start_advantage = true
            state.prev_finish = nil
            state.start = pending_start or { p1 = Utils.deep_copy(ComboData.p1_prev), p2 = Utils.deep_copy(ComboData.p2_prev) }
            local start_defender = i == 0 and state.start.p2 or state.start.p1
            if pending_start_hp_lock ~= nil then
                if state.pending_poison_was_active and start_defender then
                    local actual_hp = tonumber(def_prev and def_prev.hp_current) or 0
                    if actual_hp > 0 and actual_hp < pending_start_hp_lock then
                        state.start_hp_lock = actual_hp
                        start_defender.hp_current = actual_hp
                    else
                        state.start_hp_lock = pending_start_hp_lock
                    end
                else
                    state.start_hp_lock = pending_start_hp_lock
                end
            else
                state.start_hp_lock = (start_defender and start_defender.hp_current) or 0
            end
            state.last_seen_combo_id = current_global_combo_id
            -- Zero the defender's current_hit_damage (pDmgHitDT.DmgValue) in the
            -- start snapshot so get_hit_damage_snapshot does not fall back to a
            -- stale pre-combo DmgValue when the current frame's DmgValue is 0
            -- (common between hits, during throws, and on non-damage frames).
            if not preserve_ko_start_snapshot and start_defender then
                start_defender.current_hit_damage = 0
            end
            ComboData.clear_pending_start(state)
            -- Clear parry tracker now that the combo has started using the
            -- pre-Parry drive baseline.
            if ComboData.parry_tracker then
                ComboData.parry_tracker[i] = nil
            end
            -- For throws, use the pre-startup carry baseline to set position
            -- values in start that reflect the throw's true initiation point,
            -- not the frame before CATCH. This makes carry/gap/position deltas
            -- include throw startup movement.
            if attack_kind == "throw" and ComboData.throw_carry_baseline and not preserve_ko_start_snapshot then
                local carry_baseline_attacker = ComboData.throw_carry_baseline[i]
                local start_attacker_key = i == 0 and "p1" or "p2"
                local start_attacker = state.start[start_attacker_key]
                if carry_baseline_attacker and start_attacker then
                    start_attacker.pos_x = carry_baseline_attacker.pos_x or start_attacker.pos_x
                    start_attacker.gap = carry_baseline_attacker.gap or start_attacker.gap
                end
                local carry_baseline_defender = ComboData.throw_carry_baseline[1 - i]
                local start_defender_key = i == 0 and "p2" or "p1"
                local start_defender = state.start[start_defender_key]
                if carry_baseline_defender and start_defender then
                    start_defender.pos_x = carry_baseline_defender.pos_x or start_defender.pos_x
                    start_defender.gap = carry_baseline_defender.gap or start_defender.gap
                end
                ComboData.throw_carry_baseline = nil
            end
            local attacker_resources_restored = ComboData.apply_start_resource_baseline(
                state,
                i,
                atk,
                true,
                true,
                PRECOMBO_RESOURCE_BASELINE_FRAMES
            )
            local defender_idx = i == 0 and 1 or 0
            local attacker_di_like_resource_spend = (atk and (atk.drive_cooldown or 0) > 200)
                or ComboData.player_start_has_drive_spend(state, i, atk)
                or ComboData.recent_resource_baseline_would_show_drive_spend(i, atk, PRECOMBO_RESOURCE_BASELINE_FRAMES)
            local defender_recent_age = attacker_di_like_resource_spend
                and PRECOMBO_RESOURCE_BASELINE_FRAMES
                or DEFENDER_PRECOMBO_RESOURCE_BASELINE_FRAMES
            local defender_resources_restored = ComboData.apply_start_resource_baseline(
                state,
                defender_idx,
                def,
                attacker_di_like_resource_spend,
                true,
                defender_recent_age
            )
            if attacker_resources_restored or defender_resources_restored then
                ComboData.clear_recent_resource_baselines()
            end

            if preserve_ko_start_snapshot then
                if saved_start then state.start = saved_start end
                state.start_hp_lock = saved_start_hp_lock
                state.ko_start_hp_locked = saved_ko_start_hp_locked
                state.ko_start_snapshot = saved_ko_start_snapshot
                state.ko_start_snapshot_locked = saved_ko_start_snapshot_locked
                state.hit_damage_lock = saved_hit_damage_lock
                state.hit_damage_lock_frozen = saved_hit_damage_lock_frozen
                state.hit_damage_lock_provisional = saved_hit_damage_lock_provisional
                state.hit_damage_lock_combo_damage_total = saved_hit_damage_lock_combo_damage_total
                state.pending_ko_hit_damage_delta = saved_pending_ko_hit_damage_delta
                state.combo_damage_lock = saved_combo_damage_lock
            end
        end

        if state.started then
            -- Track combo ID changes during an active combo. When the combo ID
                -- changes (new combo started by the same attacker), update the
                -- last_seen_combo_id. Do NOT reset state.start mid-combo — the combo
                -- ID can change on cancels/route changes within the same sequence,
                -- and resetting start would lose the original Drive/Super/Carry baselines.
                if combo_id_changed then
                    state.last_seen_combo_id = current_global_combo_id
                end
    
                local previous_finish = state.finish
                local current_finish = { p1 = Utils.deep_copy(p1), p2 = Utils.deep_copy(p2) }
                local attacker_key = i == 0 and "p1" or "p2"
                local start_def = (i == 0 and state.start.p2 or state.start.p1) or {}
                local ended_in_knockdown = def and (def.down_count or 0) ~= (start_def.down_count or 0)
                if (tonumber(atk and atk.current_hit_damage) or 0) > 0
                    or (tonumber(def and def.current_hit_damage) or 0) > 0
                    or (tonumber(def_prev and def_prev.current_hit_damage) or 0) > 0 then
                    local chd = math.max(
                        tonumber(atk and atk.current_hit_damage) or 0,
                        tonumber(def and def.current_hit_damage) or 0,
                        tonumber(def_prev and def_prev.current_hit_damage) or 0
                    )
                    ComboData.debug_log("HIT_LANDED p" .. tostring(i)
                        .. " current_hit_damage=" .. tostring(chd)
                        .. " atk.combo_count=" .. tostring(atk and atk.combo_count)
                        .. " atk.combo_damage=" .. tostring(atk and atk.combo_damage)
                        .. " atk.combo_scale_now=" .. tostring(atk and atk.combo_scale_now)
                        .. " atk.act_st=" .. tostring(atk and atk.act_st)
                        .. " atk.hp=" .. tostring(atk and atk.hp_current)
                        .. " atk.attack_name=" .. tostring(atk and atk.attack_name)
                        .. " atk.drive=" .. tostring(atk and atk.drive_adjusted)
                        .. " atk.super=" .. tostring(atk and atk.super)
                        .. " def.hp=" .. tostring(def and def.hp_current)
                        .. " def.combo_scale_now=" .. tostring(def and def.combo_scale_now)
                        .. " def.act_st=" .. tostring(def and def.act_st)
                        .. " def.attack_name=" .. tostring(def and def.attack_name)
                        .. " def.down_count=" .. tostring(def and def.down_count)
                        .. " def.sp_armor=" .. tostring(def and def.sp_armor)
                        .. " def.armor_now=" .. tostring(def and def.armor_now)
                        .. " def_prev.hp=" .. tostring(def_prev and def_prev.hp_current)
                        .. " combo_damage_lock=" .. tostring(state.combo_damage_lock)
                        .. " start_hp_lock=" .. tostring(state.start_hp_lock), "log_display_update"
                    )
                end
                -- Track A.K.I.-style poison/DoT damage. mComboDamage can omit poison ticks,
                -- so also mark the sequence when the defender HP delta exceeds the game's
                -- reported combo damage total.
                local hp_start_for_poison = math.max(
                    tonumber(state.start_hp_lock) or 0,
                    tonumber(start_def and start_def.hp_current) or 0
                )
                local hp_current_for_poison = tonumber(def and def.hp_current) or hp_start_for_poison
                local hp_delta_for_poison = math.max(0, hp_start_for_poison - hp_current_for_poison)
                local known_combo_damage_for_poison = math.max(
                    tonumber(state.combo_damage_lock) or 0,
                    tonumber(atk and atk.combo_damage) or 0
                )
                if (def and def.is_poisoned)
                    or (def_prev and def_prev.is_poisoned)
                    or (start_def and start_def.is_poisoned)
                    or (known_combo_damage_for_poison > 0 and hp_delta_for_poison > known_combo_damage_for_poison)
                then
                    state.poison_was_active = true
                end
                -- When a successful attack lands during an active blockstring's
                -- leniency window (block_end_grace still counting), transition
                -- from blocked to hit so accumulated blockstring values count
                -- toward the ongoing combo rather than ending the sequence.
                -- Exception: during burnout, chip damage reduces HP and causes
                -- kind=hit even when blocking. guard_combo_count > 0 means the
                -- defender is still in a guard combo chain, so stay blocked.
                if state.is_blocked and attack_kind == "hit" and not (def and def.guard_combo_count and def.guard_combo_count > 0) then
                    state.is_blocked = false
                    state.block_end_grace_remaining = 0
                end
                local combo_ended = false
                local end_mode = ComboData.resolve_end_mode(Config.get_combo_end_mode(), state, atk, def)
                if state.is_blocked then
                    if end_mode == "attacker_recovery" then
                        combo_ended = atk and atk.act_st == 0
                    else
                        combo_ended = ComboData.update_block_end_grace(state, def, def_prev)
                    end
                elseif state.is_throw then
                    if end_mode == "attacker_recovery" then
                        combo_ended = atk and atk.act_st ~= 37
                    else
                        combo_ended = ComboData.is_defender_recovered(def)
                        -- Fallback for throws: if defender recovery never resolves
                        -- cleanly, end after a short grace once the attacker has
                        -- left CATCH so post-recovery values stop advancing.
                        if not combo_ended and atk and atk.act_st ~= 37 then
                            state.defender_recovery_grace_remaining = (state.defender_recovery_grace_remaining or 0) + 1
                            if state.defender_recovery_grace_remaining >= 30 then
                                combo_ended = true
                            end
                        else
                            state.defender_recovery_grace_remaining = 0
                        end
                    end
                else
                    if end_mode == "attacker_recovery" then
                        combo_ended = atk and ((atk.combo_count or 0) == 0 or ComboData.is_neutral_recovery_state(atk))
                    else
                        combo_ended = ComboData.is_defender_recovered(def)
                        local drive_impact_still_recovering = ComboData.is_drive_impact_sequence_still_recovering(state, atk, def)
                        -- In defender recovery mode, also end the combo when the
                        -- attacker's combo_count has reset AND a new attack is
                        -- detected. This handles the case where the defender acts
                        -- immediately upon recovering and a new combo starts.
                        if not combo_ended and ended_in_knockdown and atk
                            and (atk.combo_count or 0) == 0 and attack_kind
                            and not drive_impact_still_recovering
                        then
                            combo_ended = true
                        end
                        -- Fallback: if act_st never returns to 0 (e.g., defender
                        -- recovers to crouch/jump), end the combo after a grace
                        -- period once the attacker's combo_count has reset.
                        if not combo_ended then
                            if drive_impact_still_recovering then
                                state.defender_recovery_grace_remaining = 0
                            elseif state.is_drive_impact_sequence then
                                -- DI opener sequences should stay open only while the
                                -- defender is still in recovery; once recovery is
                                -- over, do not keep the combo alive with the normal
                                -- post-recovery grace window.
                                combo_ended = true
                            elseif atk and ((atk.combo_count or 0) == 0 or ComboData.is_neutral_recovery_state(atk)) then
                                state.defender_recovery_grace_remaining = (state.defender_recovery_grace_remaining or 0) + 1
                                if state.defender_recovery_grace_remaining >= 30 then
                                    combo_ended = true
                                end
                            elseif (state.defender_recovery_grace_remaining or 0) > 0 then
                                -- Grace was already counting from a prior
                                -- combo_count == 0 frame. A new combo has
                                -- started before the defender recovered or
                                -- the grace expired. End the previous combo
                                -- immediately so values stop accruing.
                                combo_ended = true
                                state.defender_recovery_grace_remaining = 0
                            end
                        end
                    end
                end
                local round_ended = def and def_prev and def.death_count ~= def_prev.death_count
                local ko_pending = not state.is_blocked and ComboData.is_pending_ko(atk, def, def_prev)
                if ko_pending then
                    ComboData.lock_ko_start_snapshot(state)
                    ComboData.ensure_start_hp_lock(state, i, def, def_prev, atk, true)
                end
    

                    -- Knockdowns keep Drive changing through wake-up, so only freeze on
                    -- non-knockdown finishes. The settle pass below handles recovery.
                    -- KO/round-end frames must NOT be frozen from previous_finish: the
                    -- KO frame's live values (HP 0, combo_damage, Drive, Super, Carry
                    -- delta) are the correct combo endpoint and must be preserved for
                    -- the hit_damage/combo_damage locks captured below.
                    --
                    -- On non-knockdown hit combos, also freeze when the game's
                    -- combo_count drops to 0, even if defender recovery (act_st == 0)
                    -- hasn't been detected yet. Blocked sequences do not advance
                    -- combo_count, so they must keep the live finish snapshot here or
                    -- they will inherit stale Drive/Super/Carry values from the frame
                    -- before the block was observed.
                    if not ended_in_knockdown
                        and not state.is_blocked
                        and not state.is_throw
                        and not ko_pending
                        and not round_ended
                        and previous_finish and previous_finish.p1 and previous_finish.p2
                    then
                        local combo_count_done = atk and (atk.combo_count or 0) == 0
                        if combo_ended or combo_count_done then
                            ComboData.freeze_all_finish_values(current_finish, previous_finish)
                        end
                    end

                    ComboData.clear_sequence_start_advantage(state, attacker_key, current_finish)

                    if not state.is_blocked then
                        ComboData.update_hit_advantage_lock(state, attacker_key, current_finish)
                    end

                    if ComboData.should_freeze_hit_damage_during_defender_recovery(state, atk, combo_ended, round_ended, ko_pending, end_mode, ended_in_knockdown) then
                        ComboData.freeze_hit_damage_lock(state)
                    end

                    -- Avatar battle mode: track defender HP at hit boundaries.
                    -- pDmgHitDT.DmgValue reflects base move damage and does not include
                    -- World Tour/avatar stat/buff modifiers. Track the defender's HP
                    -- before each individual hit so get_hit_damage_snapshot can derive
                    -- the actual (buffed) per-hit damage from the HP delta.
                    if GameObjects.is_avatar_battle_mode() and not state.is_blocked then
                        local latest_combo_damage = tonumber(atk and atk.combo_damage) or 0
                        local locked_combo_damage = tonumber(state.combo_damage_lock) or 0
                        if state.hit_start_hp == nil then
                            local start_def = i == 0 and state.start.p2 or state.start.p1
                            state.hit_start_hp = tonumber(start_def and start_def.hp_current) or 0
                        elseif latest_combo_damage > locked_combo_damage then
                            -- New hit in the combo: snapshot defender HP from the frame before
                            -- damage was applied.
                            state.hit_start_hp = tonumber(def_prev and def_prev.hp_current) or 0
                        end
                    end

                    ComboData.update_hit_damage_lock(state, attacker_key, current_finish, combo_ended, round_ended, ko_pending)
                    if combo_ended or round_ended or ko_pending then
                        ComboData.freeze_hit_damage_lock(state)
                        ComboData.apply_hit_damage_lock_to_finish(state, attacker_key, current_finish)
                    end
                    ComboData.update_combo_damage_lock(state, attacker_key, current_finish)

                    if combo_ended or round_ended or ko_pending then
                        state.finished, state.started = true, false
                        state.ended_in_knockdown = ended_in_knockdown == true
                        state.ended_in_ko = (ko_pending or round_ended)
                        state.knockdown_drive_settle = ended_in_knockdown == true and not round_ended and not ko_pending
                        state.throw_end_wait_for_exit = state.is_throw == true and not round_ended and not ko_pending
                        state.advantage_settle_remaining = round_ended and 0 or ADVANTAGE_SETTLE_FRAMES
                        if Config.settings.combo_timer_duration > 0 then
                            state.timer_remaining = Config.settings.combo_timer_duration * 60
                        end
                        ComboData.clear_all_resource_baselines()
                        if state.is_blocked then
                        ComboData.debug_log("BLOCK_END p" .. tostring(i)
                            .. " guard_time=" .. tostring(def and def.guard_time)
                            .. " guard_combo_count=" .. tostring(def and def.guard_combo_count)
                            .. " guard_combo_prev=" .. tostring(def_prev and def_prev.guard_combo_count)
                            .. " act_st=" .. tostring(def and def.act_st)
                            .. " guard_grace=" .. tostring(state.block_end_grace_remaining)
                            .. " block_damage=" .. tostring((def_prev and def_prev.hp_current or 0) - (def and def.hp_current or 0)), "log_display_update"
                            )
                        end
                        ComboData.debug_log("COMBO_END p" .. tostring(i)
                            .. " reason=" .. tostring(combo_ended and "combo_ended" or round_ended and "round_ended" or "ko_pending")
                            .. " ended_in_ko=" .. tostring(state.ended_in_ko)
                            .. " ended_in_knockdown=" .. tostring(state.ended_in_knockdown)
                            .. " combo_damage_lock=" .. tostring(state.combo_damage_lock)
                            .. " start_hp_lock=" .. tostring(state.start_hp_lock)
                            .. " hit_damage_lock_frozen=" .. tostring(state.hit_damage_lock_frozen)
                            .. " advantage_settle_remaining=" .. tostring(state.advantage_settle_remaining)
                            .. " timer_remaining=" .. tostring(state.timer_remaining), "log_display_update"
                        )
                        ComboData.runtime_state.log_linger_until = os.time() + 10
                        -- When ending a knockdown combo because a new attack was detected
                        -- (defender acted immediately upon recovering), capture starter
                        -- values now from p1_prev/p2_prev (still from the pre-attack frame)
                        -- so the next combo's pending_start gets correct baselines.
                        if attack_kind and not state.pending_start then
                            state.pending_start = { p1 = Utils.deep_copy(ComboData.p1_prev), p2 = Utils.deep_copy(ComboData.p2_prev) }
                            local pending_defender = i == 0 and state.pending_start.p2 or state.pending_start.p1
                            local pending_hp = tonumber(def_prev and def_prev.hp_current) or 0
                            if pending_defender and pending_hp > (tonumber(pending_defender.hp_current) or 0) then
                                pending_defender.hp_current = pending_hp
                            end
                            if pending_defender and def_prev and def_prev.is_poisoned then
                                pending_defender.is_poisoned = true
                            end
                            state.pending_start_hp_lock = math.max(
                                tonumber(state.pending_start_hp_lock) or 0,
                                tonumber(pending_defender and pending_defender.hp_current) or 0,
                                pending_hp
                            )
                        end
                    end
                -- On KO, freeze DPH lock, cap combo damage at starting HP,
                -- and force defender finish HP to 0 so the Total column
                -- shows correct values immediately.
                if ko_pending then
                    if state.hit_damage_lock then
                        state.hit_damage_lock_frozen = true
                    end
                    local cap_start_def = (i == 0 and state.start.p2 or state.start.p1) or {}
                    local cap_hp_start = math.max(
                        tonumber(state.start_hp_lock) or 0,
                        tonumber(cap_start_def.hp_current) or 0
                    )
                    if ComboData.runtime_state.ko_logged_frame ~= ComboData.runtime_state.frame_count then
                        ComboData.runtime_state.ko_logged_frame = ComboData.runtime_state.frame_count
                        ComboData.debug_log_state("KO_DETECTED p" .. tostring(i) .. " before_cap", state, "log_display_update")
                        ComboData.debug_log("KO_DETECTED p" .. tostring(i)
                            .. " ko_pending=" .. tostring(ko_pending)
                            .. " round_ended=" .. tostring(round_ended)
                            .. " combo_ended=" .. tostring(combo_ended)
                            .. " atk.combo_damage=" .. tostring(atk and atk.combo_damage)
                            .. " atk.combo_count=" .. tostring(atk and atk.combo_count)
                            .. " atk.attack_name=" .. tostring(atk and atk.attack_name)
                            .. " def.hp_current=" .. tostring(def and def.hp_current)
                            .. " def_prev.hp_current=" .. tostring(def_prev and def_prev.hp_current)
                            .. " def.incapacitated=" .. tostring(def and def.incapacitated)
                            .. " def.attack_name=" .. tostring(def and def.attack_name)
                            .. " cap_hp_start=" .. tostring(cap_hp_start)
                            .. " combo_damage_lock_before_cap=" .. tostring(state.combo_damage_lock), "log_display_update"
                        )
                        if cap_hp_start > 0 and state.combo_damage_lock and state.combo_damage_lock > cap_hp_start then
                            ComboData.debug_log("KO_DETECTED p" .. tostring(i) .. " combo_damage_lock_capped_to=" .. tostring(cap_hp_start), "log_display_update")
                        end
                    end
                    if cap_hp_start > 0 then
                        if state.combo_damage_lock and state.combo_damage_lock > cap_hp_start then
                            state.combo_damage_lock = cap_hp_start
                        end
                    end
                    local ko_def_key = (i == 0) and "p2" or "p1"
                    if current_finish and current_finish[ko_def_key] then
                        current_finish[ko_def_key].hp_current = 0
                    end
                end
                -- Freeze carry end/total as scalar values at KO so the
                -- downed opponent's fall animation can't move them.
                -- Scalar values are immune to deep-copy reference leaks.
                if ko_pending then
                    state.ko_carry_finish_p1_x = current_finish.p1 and current_finish.p1.pos_x
                    state.ko_carry_finish_p2_x = current_finish.p2 and current_finish.p2.pos_x
                    -- Pre-compute carry totals at KO time using frozen finish positions.
                    -- The carry total computation uses start positions and finish
                    -- positions. Start positions are already frozen. We capture the
                    -- finish positions above. Now compute and lock the totals.
                    local start_p1 = state.start.p1 or {}
                    local start_p2 = state.start.p2 or {}
                    local attacker_start = i == 0 and start_p1 or start_p2
                    -- Build minimal finish objects with only pos_x locked
                    local frozen_finish_p1 = { pos_x = state.ko_carry_finish_p1_x or 0, dir = current_finish.p1 and current_finish.p1.dir }
                    local frozen_finish_p2 = { pos_x = state.ko_carry_finish_p2_x or 0, dir = current_finish.p2 and current_finish.p2.dir }
                    local attacker_finish = i == 0 and frozen_finish_p1 or frozen_finish_p2
                    -- Compute carry totals with frozen positions
                    local percent_max_values = UI.get_percent_max_values(state)
                    local throw_side_switch = UI.should_use_side_switch_carry(state, i == 0, start_p1, start_p2)
                    state.ko_carry_total_p1 = UI.get_carry_total_value(start_p1, frozen_finish_p1, attacker_start, attacker_finish, percent_max_values and percent_max_values[7], throw_side_switch)
                    state.ko_carry_total_p2 = UI.get_carry_total_value(start_p2, frozen_finish_p2, attacker_start, attacker_finish, percent_max_values and percent_max_values[8], throw_side_switch)
                    local sign_p1, sign_p2 = UI.apply_side_switch_carry_total_sign_rule(
                        state.ko_carry_total_p1, state.ko_carry_total_p2, i == 0, attacker_start, attacker_finish
                    )
                    state.ko_carry_total_p1 = sign_p1
                    state.ko_carry_total_p2 = sign_p2
                end
                if ko_pending and ComboData.runtime_state.ko_logged_frame ~= ComboData.runtime_state.frame_count then
                    ComboData.runtime_state.ko_logged_frame = ComboData.runtime_state.frame_count
                    ComboData.debug_log_state("KO_FINISH p" .. tostring(i), state, "log_display_update")
                    ComboData.debug_log("KO_FINISH p" .. tostring(i)
                        .. " ko_carry_total_p1=" .. tostring(state.ko_carry_total_p1)
                        .. " ko_carry_total_p2=" .. tostring(state.ko_carry_total_p2)
                        .. " ko_carry_finish_p1_x=" .. tostring(state.ko_carry_finish_p1_x)
                        .. " ko_carry_finish_p2_x=" .. tostring(state.ko_carry_finish_p2_x)
                        .. " atk.attack_name=" .. tostring(atk and atk.attack_name)
                        .. " def.attack_name=" .. tostring(def and def.attack_name), "log_display_update"
                    )
                end
                state.prev_finish = previous_finish
                state.finish = current_finish
        end -- if state.started

        if state.finished and state.knockdown_drive_settle then
            local current_finish = { p1 = Utils.deep_copy(p1), p2 = Utils.deep_copy(p2) }
            local previous_finish = state.finish
            local attacker_key = i == 0 and "p1" or "p2"

            -- Freeze all non-drive values from the previous frame so only
            -- drive gauge changes are tracked during the opponent's
            -- wake-up recover period.
            if previous_finish then
                for _, player_key in ipairs({ "p1", "p2" }) do
                    local current = current_finish[player_key]
                    local previous = previous_finish[player_key]
                    if current and previous then
                        current.super = previous.super
                        current.pos_x = previous.pos_x
                        current.gap = previous.gap
                        current.advantage = previous.advantage
                        current.hp_current = previous.hp_current
                        current.combo_damage = previous.combo_damage
                        current.current_hit_damage = previous.current_hit_damage
                        current.combo_scale_now = previous.combo_scale_now
                    end
                end
            end

            ComboData.freeze_hit_damage_lock(state)
            ComboData.apply_hit_damage_lock_to_finish(state, attacker_key, current_finish)

            -- Track settle duration and enforce a hard timeout so the
            -- loop cannot run indefinitely when drive_cooldown or
            -- action_frame never settle.
            state.knockdown_drive_settle_frames = (state.knockdown_drive_settle_frames or 0) + 1
            local max_settle_frames = 120

            if ComboData.knockdown_drive_settle_complete(def) or state.knockdown_drive_settle_frames >= max_settle_frames then
                -- Freeze drive values too from the previous frame now
                -- that settle has completed (or timed out).
                if previous_finish then
                    for _, player_key in ipairs({ "p1", "p2" }) do
                        local current = current_finish[player_key]
                        local previous = previous_finish[player_key]
                        if current and previous then
                            current.drive_adjusted = previous.drive_adjusted
                            current.incapacitated = previous.incapacitated
                        end
                    end
                end
                state.knockdown_drive_settle = false
                state.knockdown_drive_settle_frames = nil
            end
            state.prev_finish = previous_finish
            state.finish = current_finish
        end
    end
    ComboData.p1_prev = p1 and Utils.deep_copy(p1) or {}
    ComboData.p2_prev = p2 and Utils.deep_copy(p2) or {}
end

-------------------------
-- UI Rendering
-------------------------

UI.prev_key_states = {}
UI.save_pending = false
UI.save_timer = 0
UI.tooltip_timer = 0
UI.tooltip_msg = ""
UI.right_click_this_frame = false
UI.large_font = 30
UI.medium_font = 22
UI.small_font = 17
UI.font_cache = {}
UI.gradient_max = {100, 10000, 60000, 30000, 60000, 30000, 1530, 1530, 490, 80}
UI.hit_damage_scaling_color_smoothing_frames = 40
UI.hit_damage_scaling_color_state = UI.hit_damage_scaling_color_state or {}
UI.hit_damage_scaling_color_active_key = UI.hit_damage_scaling_color_active_key or {}
UI.gradient_color_state = UI.gradient_color_state or {}
UI.gradient_color_active_key = UI.gradient_color_active_key or {}
UI.minimum_combo_window_width = 220
UI.window_padding_width = 44
UI.display_box_rounding = 10
UI.stroke_item_id = 0
UI.FADEOUT_FRAMES = 4
UI.fadeout_alpha_override = nil
UI.fadeout_frame_counter = 0
UI.fadeout_global_frame = 0
UI.fadeout = {
    [0] = { active = false, snapshot = nil, title = nil, is_defense = nil, x = nil, y = nil, anchor = nil, width = nil, minimal = nil, player_index = 0 },
    [1] = { active = false, snapshot = nil, title = nil, is_defense = nil, x = nil, y = nil, anchor = nil, width = nil, minimal = nil, player_index = 1 },
}
UI.fadeout_snapshot = {
    [0] = { state = nil, title = nil, is_defense = nil, x = nil, y = nil, anchor = nil, width = nil, minimal = nil, stamp = -1, snapshot_has_state = false },
    [1] = { state = nil, title = nil, is_defense = nil, x = nil, y = nil, anchor = nil, width = nil, minimal = nil, stamp = -1, snapshot_has_state = false },
}
-- Last fully-rendered combo window size per player index, captured inside
-- draw_combo_window_frame so the next frame can bound the window position to
-- keep it entirely within the game window. nil until the first render.
UI.last_window_size = { [0] = nil, [1] = nil }
UI.confirm_active = {}
function UI.confirm_button(action_key, label, id, callback)
    local display = UI.confirm_active[action_key] and (label .. "?##" .. id) or (label .. "##" .. id)
    if imgui.button(display) then
        if UI.confirm_active[action_key] then
            UI.confirm_active[action_key] = nil
            callback()
        else
            UI.confirm_active[action_key] = true
        end
    end
end
function UI.get_active_draw_list()
    local draw_list = imgui.get_window_draw_list and imgui.get_window_draw_list()
    if not draw_list and imgui.get_foreground_draw_list then
        draw_list = imgui.get_foreground_draw_list()
    end
    return draw_list
end

function UI.was_key_down(i)
    local down = reframework:is_key_down(i)
    local prev = UI.prev_key_states[i]
    UI.prev_key_states[i] = down
    return down and not prev
end

function UI.mark_for_save()
    UI.save_pending = true
    UI.save_timer = SAVE_DELAY
end

function UI.action_notify(msg, category_toggle)
    if Config.settings.hide_all_alerts then return end
    if category_toggle ~= nil and not Config.settings[category_toggle] then return end
    local prepended_msg = MOD_NAME .. ': ' .. msg
    UI.tooltip_msg = prepended_msg
    UI.tooltip_timer = 40
end

function UI.set_hover_tooltip(msg)
    if imgui.is_item_hovered() then
        imgui.set_tooltip(msg)
    end
end

function UI.tooltip_handler()
    if UI.tooltip_timer > 0 then UI.tooltip_timer = UI.tooltip_timer - 1 end
end

function UI.draw_action_notify()
    if UI.tooltip_timer <= 0 then return end
    local display = imgui.get_display_size()
    imgui.set_next_window_pos(Vector2f.new(display.x * 0.5, display.y - 100), 1 << 0, Vector2f.new(0.5, 0.5))
    imgui.begin_window("Notification##attack_info", true, 1|2|4|8|16|43|64|65536|131072)
    UI.get_font_size(30)
    imgui.text(UI.tooltip_msg)
    imgui.pop_font()
    imgui.end_window()
end

function UI.save_handler()
    if UI.save_pending then
        UI.save_timer = UI.save_timer - (1.0 / 60.0)
        if UI.save_timer <= 0 then
            Config.save()
            UI.save_pending = false
        end
    end
end

function UI.get_display_background_opacity()
    local opacity = tonumber(Config.settings.display_background_opacity) or DEFAULT_BACKGROUND_OPACITY
    local v = Utils.clamp(opacity, 0, 100) / 100
    if UI.fadeout_alpha_override ~= nil then v = v * (UI.fadeout_alpha_override or 0) end
    return v
end

function UI.get_display_text_opacity()
    local opacity = tonumber(Config.settings.display_text_opacity) or DEFAULT_TEXT_OPACITY
    local v = Utils.clamp(opacity, 0, 100) / 100
    if UI.fadeout_alpha_override ~= nil then v = v * (UI.fadeout_alpha_override or 0) end
    return v
end

function UI.get_display_scale()
    local scale = tonumber(Config.settings.display_scale) or DEFAULT_DISPLAY_SCALE
    return Utils.clamp(scale, 50, 150) / 100
end

function UI.get_display_box_rounding()
    return math.max(0, math.floor(((tonumber(UI.display_box_rounding) or 10) * UI.get_display_scale()) + 0.5))
end

function UI.get_imgui_style_var(name)
    local style_vars = imgui.ImGuiStyleVar
    if type(style_vars) == "table" and style_vars[name] ~= nil then
        return style_vars[name]
    end
    return imgui["ImGuiStyleVar_" .. tostring(name)]
end

function UI.get_scaled_font_size(size)
    return math.max(1, math.floor((size * UI.get_display_scale()) + 0.5))
end

function UI.get_font_size(size)
    size = math.max(1, math.floor((tonumber(size) or UI.small_font) + 0.5))
    if not UI.font_cache[size] then
        UI.font_cache[size] = imgui.load_font(nil, size)
    end
    return imgui.push_font(UI.font_cache[size])
end

function UI.get_large_font() return UI.get_font_size(UI.get_scaled_font_size(UI.large_font)) end
function UI.get_medium_font() return UI.get_font_size(UI.get_scaled_font_size(UI.medium_font)) end
function UI.get_small_font() return UI.get_font_size(UI.get_scaled_font_size(UI.small_font)) end

function UI.center_content(content_width, column_width, draw_fn)
    local cursor = imgui.get_cursor_pos()
    local offset = (column_width - content_width) * 0.5
    if offset > 0 then
        imgui.set_cursor_pos(Vector2f.new(cursor.x + offset, cursor.y))
    end
    draw_fn()
end

function UI.center_text(text, column_width, draw_fn)
    local text_size = imgui.calc_text_size(text)
    UI.center_content(text_size.x, column_width, draw_fn)
end

function UI.apply_opacity_to_color(color, opacity)
    local alpha = math.floor(Utils.clamp(opacity, 0, 1) * 255 + 0.5)
    return (alpha << 24) + (color % 0x1000000)
end

function UI.hit_damage_scaling_rgb(scaling)
    local value = tonumber(scaling)
    if value == nil or value <= 0 then
        return 255, 255, 255
    end

    local t = (Utils.clamp(value, 10, 100) - 10) / 90
    local r, g
    if t < 0.75 then
        local phase = t / 0.75
        r = 255
        g = math.floor((255 * phase) + 0.5)
    else
        local phase = (t - 0.75) / 0.25
        r = math.floor((255 * (1 - phase)) + 0.5)
        g = 255
    end

    return r, g, 0
end

function UI.rgb_to_hex_color(r, g, b)
    r = Utils.clamp(math.floor((tonumber(r) or 0) + 0.5), 0, 255)
    g = Utils.clamp(math.floor((tonumber(g) or 0) + 0.5), 0, 255)
    b = Utils.clamp(math.floor((tonumber(b) or 0) + 0.5), 0, 255)
    return UI.apply_opacity_to_color(0xFF000000 + (b << 16) + (g << 8) + r, UI.get_display_text_opacity())
end
function UI.value_to_rgb_color(v, max_val)
    -- Total Damage gradient anchors:
    -- red at 0, yellow at 1500, soft green at 3000, full green at 7000.
    local value = tonumber(v) or 0
    return UI.rgb_from_gradient_anchors(value, {
        { 0,    255,   0,   0 }, -- red at 0
        { 1500, 255, 255,   0 }, -- yellow at 1500
        { 3000, 176, 255,   0 }, -- soft green at 3000
        { 7000,   0, 255,   0 }, -- full green at 7000
    })
end

function UI.signed_value_to_rgb_color(v, max_abs)
    max_abs = max_abs or 7500
    local value = Utils.clamp(tonumber(v) or 0, -max_abs, max_abs)
    local t = value / max_abs
    local r, g = 255, 255

    if t < 0 then
        g = 255
        r = math.floor((1 + t) * 255 + 0.5)
    elseif t > 0 then
        r = 255
        g = math.floor((1 - t) * 255 + 0.5)
    end

    return r, g, 0
end

function UI.yellow_to_red_rgb_color(v, max_val)
    max_val = max_val or 7500
    local t = math.max(0, math.min((tonumber(v) or 0) / max_val, 1))
    local r = 255
    local g = math.floor((1 - t) * 255 + 0.5)
    return r, g, 0
end

function UI.smoothed_gradient_rgb_color(key, target_r, target_g, target_b, target_identity)
    key = key or "default"
    target_r = Utils.clamp(math.floor((tonumber(target_r) or 0) + 0.5), 0, 255)
    target_g = Utils.clamp(math.floor((tonumber(target_g) or 0) + 0.5), 0, 255)
    target_b = Utils.clamp(math.floor((tonumber(target_b) or 0) + 0.5), 0, 255)

    local color_key = tostring(target_r) .. ":" .. tostring(target_g) .. ":" .. tostring(target_b)
    local target_key = target_identity and tostring(target_identity) or color_key
    local smoothing_frames = math.max(1, tonumber(UI.hit_damage_scaling_color_smoothing_frames) or 40)

    local smooth = UI.gradient_color_state[key]
    if not smooth then
        smooth = {
            r = target_r,
            g = target_g,
            b = target_b,
            start_r = target_r,
            start_g = target_g,
            start_b = target_b,
            target_r = target_r,
            target_g = target_g,
            target_b = target_b,
            target_key = target_key,
            target_color_key = color_key,
            queued_target_r = nil,
            queued_target_g = nil,
            queued_target_b = nil,
            queued_target_key = nil,
            queued_target_color_key = nil,
            frame = smoothing_frames,
            fast_forward = false,
        }
        UI.gradient_color_state[key] = smooth
        return UI.rgb_to_hex_color(smooth.r, smooth.g, smooth.b)
    end

    local function clear_queue()
        smooth.queued_target_r = nil
        smooth.queued_target_g = nil
        smooth.queued_target_b = nil
        smooth.queued_target_key = nil
        smooth.queued_target_color_key = nil
    end

    local function start_transition(next_r, next_g, next_b, next_key, next_color_key)
        smooth.start_r = smooth.r or next_r
        smooth.start_g = smooth.g or next_g
        smooth.start_b = smooth.b or next_b
        smooth.target_r = next_r
        smooth.target_g = next_g
        smooth.target_b = next_b
        smooth.target_key = next_key
        smooth.target_color_key = next_color_key
        smooth.frame = 0
        smooth.fast_forward = false
    end

    local is_active = (smooth.frame or smoothing_frames) < smoothing_frames

    if smooth.target_key ~= target_key then
        if is_active then
            -- Value changed mid-smoothing. Keep the first smooth effect's
            -- original target, but finish it at 1.33x speed. Once reached,
            -- start the latest queued value's smooth effect at normal speed.
            smooth.queued_target_r = target_r
            smooth.queued_target_g = target_g
            smooth.queued_target_b = target_b
            smooth.queued_target_key = target_key
            smooth.queued_target_color_key = color_key
            smooth.fast_forward = true
        else
            clear_queue()
            start_transition(target_r, target_g, target_b, target_key, color_key)
        end
    elseif smooth.queued_target_key ~= nil then
        clear_queue()
        smooth.fast_forward = false
    end

    is_active = (smooth.frame or smoothing_frames) < smoothing_frames
    if is_active then
        local frame_step = smooth.fast_forward and 1.33 or 1
        smooth.frame = math.min(smoothing_frames, (smooth.frame or 0) + frame_step)
        local t = Utils.clamp(smooth.frame / smoothing_frames, 0, 1)
        smooth.r = smooth.start_r + ((smooth.target_r - smooth.start_r) * t)
        smooth.g = smooth.start_g + ((smooth.target_g - smooth.start_g) * t)
        smooth.b = smooth.start_b + ((smooth.target_b - smooth.start_b) * t)
    else
        smooth.r = smooth.target_r
        smooth.g = smooth.target_g
        smooth.b = smooth.target_b
    end

    if (smooth.frame or smoothing_frames) >= smoothing_frames then
        smooth.r = smooth.target_r
        smooth.g = smooth.target_g
        smooth.b = smooth.target_b

        if smooth.queued_target_key ~= nil and smooth.queued_target_key ~= smooth.target_key then
            local queued_r = smooth.queued_target_r
            local queued_g = smooth.queued_target_g
            local queued_b = smooth.queued_target_b
            local queued_key = smooth.queued_target_key
            local queued_color_key = smooth.queued_target_color_key
            clear_queue()
            start_transition(queued_r, queued_g, queued_b, queued_key, queued_color_key)
        else
            clear_queue()
            smooth.fast_forward = false
        end
    end

    return UI.rgb_to_hex_color(smooth.r, smooth.g, smooth.b)
end

function UI.get_gradient_target_identity(kind, v, max_val)
    local value = tonumber(v) or 0
    local max_value = tonumber(max_val) or 0
    return tostring(kind or "value") .. ":" .. string.format("%.6f", value) .. ":" .. string.format("%.6f", max_value)
end

function UI.get_gradient_color_combo_key(state, column, kind)
    local player_key = "p" .. tostring(((state and state.attacker) or 0) + 1)
    local column_id = tostring((column and column.id) or "unknown_column")
    local kind_id = tostring(kind or "value")
    local active_scope = player_key .. ":" .. column_id .. ":" .. kind_id
    local combo_identity = "no_combo"

    if state then
        combo_identity = tostring(state.start or state.finish or state)
    end

    return active_scope, active_scope .. ":" .. combo_identity
end

function UI.smoothed_gradient_color_for_state(state, column, kind, target_r, target_g, target_b, target_identity)
    local active_scope, combo_key = UI.get_gradient_color_combo_key(state, column, kind)
    local old_key = UI.gradient_color_active_key[active_scope]
    if old_key ~= combo_key then
        if old_key then
            UI.gradient_color_state[old_key] = nil
        end
        UI.gradient_color_active_key[active_scope] = combo_key
    end

    return UI.smoothed_gradient_rgb_color(combo_key, target_r, target_g, target_b, target_identity)
end
function UI.smoothed_value_to_hex_color_for_state(state, column, v, max_val)
    local r, g, b = UI.value_to_rgb_color(v, max_val)
    local target_identity = UI.get_gradient_target_identity("value", v, max_val)
    return UI.smoothed_gradient_color_for_state(state, column, "value", r, g, b, target_identity)
end

function UI.smoothed_signed_value_to_hex_color_for_state(state, column, v, max_abs)
    local r, g, b = UI.signed_value_to_rgb_color(v, max_abs)
    local target_identity = UI.get_gradient_target_identity("signed_value", v, max_abs)
    return UI.smoothed_gradient_color_for_state(state, column, "signed_value", r, g, b, target_identity)
end

function UI.smoothed_yellow_to_red_hex_color_for_state(state, column, v, max_val)
    local r, g, b = UI.yellow_to_red_rgb_color(v, max_val)
    local target_identity = UI.get_gradient_target_identity("yellow_to_red", v, max_val)
    return UI.smoothed_gradient_color_for_state(state, column, "yellow_to_red", r, g, b, target_identity)
end

-- BEGIN role-specific Drive/Super/Carry gradient colors
function UI.rgb_from_gradient_anchors(v, anchors)
    local value = tonumber(v) or 0
    if #anchors == 0 then
        return 255, 255, 255
    end

    if value <= anchors[1][1] then
        return anchors[1][2], anchors[1][3], anchors[1][4]
    end

    for i = 2, #anchors do
        local left = anchors[i - 1]
        local right = anchors[i]
        if value <= right[1] then
            local span = right[1] - left[1]
            local t = span ~= 0 and Utils.clamp((value - left[1]) / span, 0, 1) or 1
            local r = left[2] + ((right[2] - left[2]) * t)
            local g = left[3] + ((right[3] - left[3]) * t)
            local b = left[4] + ((right[4] - left[4]) * t)
            return r, g, b
        end
    end

    local last = anchors[#anchors]
    return last[2], last[3], last[4]
end

function UI.self_drive_to_rgb_color(v)
    local drive_max = 60000
    return UI.rgb_from_gradient_anchors(v, {
        { -drive_max, 255,   0,   0 }, -- fully red at -60000
        { 0,         255, 255,   0 }, -- yellow midpoint at 0
        { 15000,     176, 255,   0 }, -- soft green at +15000
        { 20000,       0, 255,   0 }, -- full green at +20000
    })
end

function UI.opposing_drive_to_rgb_color(v)
    return UI.rgb_from_gradient_anchors(v, {
        { -20000,   0, 255,   0 }, -- full green at -20000
        { -10000, 176, 255,   0 }, -- soft green at -10000
        { 0,      255, 255,   0 }, -- yellow at 0
        { 7500,   255, 128,   0 }, -- orange at +7500
        { 15000,  255,   0,   0 }, -- full red at +15000
    })
end

function UI.self_super_to_rgb_color(v)
    return UI.rgb_from_gradient_anchors(v, {
        { -30000, 255,   0,   0 }, -- fully red at -30000
        { 0,     255, 128,   0 }, -- orange at 0
        { 3000,  255, 255,   0 }, -- yellow at +3000
        { 5000,   64, 255,   0 }, -- mostly green at +5000
        { 13000,   0, 255,   0 }, -- fully green at +13000
    })
end
function UI.carry_total_to_rgb_color(v, max_value)
    local carry_max = math.max(1, tonumber(max_value) or 1530)
    return UI.rgb_from_gradient_anchors(v, {
        { -carry_max * 0.75, 255,   0,   0 }, -- maximum red at -75%
        { -carry_max * 0.10, 255,  96,  96 }, -- soft red at -10%
        { 0,                 255, 255,   0 }, -- yellow at 0
        { carry_max * 0.25,   176, 255,   0 }, -- soft green at +25%
        { carry_max * 0.50,   16, 255,  16 }, -- nearly full green at +50%
        { carry_max * 0.75,    0, 255,   0 }, -- full green at +75%
    })
end

function UI.opposing_carry_total_to_rgb_color(v, max_value)
    local carry_max = math.max(1, tonumber(max_value) or 1530)
    return UI.rgb_from_gradient_anchors(v, {
        { -carry_max * 0.75, 255,   0,   0 }, -- maximum red at -75%
        { -carry_max * 0.10, 255,  96,  96 }, -- soft red at -10%
        { 0,                 255, 255,   0 }, -- yellow at 0
        { carry_max * 0.25,  255, 255,   0 }, -- full yellow at +25%
        { carry_max * 0.50,   176, 255,   0 }, -- soft green at +50%
        { carry_max * 0.75,    0, 255,   0 }, -- full green at +75%
    })
end
function UI.smoothed_self_drive_to_hex_color_for_state(state, column, v)
    local r, g, b = UI.self_drive_to_rgb_color(v)
    local target_identity = UI.get_gradient_target_identity("self_drive", v, 60000)
    return UI.smoothed_gradient_color_for_state(state, column, "self_drive", r, g, b, target_identity)
end

function UI.smoothed_opposing_drive_to_hex_color_for_state(state, column, v)
    local r, g, b = UI.opposing_drive_to_rgb_color(v)
    local target_identity = UI.get_gradient_target_identity("opposing_drive", v, 10000)
    return UI.smoothed_gradient_color_for_state(state, column, "opposing_drive", r, g, b, target_identity)
end

function UI.smoothed_self_super_to_hex_color_for_state(state, column, v)
    local r, g, b = UI.self_super_to_rgb_color(v)
    local target_identity = UI.get_gradient_target_identity("self_super", v, 30000)
    return UI.smoothed_gradient_color_for_state(state, column, "self_super", r, g, b, target_identity)
end
function UI.smoothed_carry_total_to_hex_color_for_state(state, column, v, max_value)
    local carry_max = math.max(1, tonumber(max_value) or 1530)
    local r, g, b = UI.carry_total_to_rgb_color(v, carry_max)
    local target_identity = UI.get_gradient_target_identity("carry_total", v, carry_max)
    return UI.smoothed_gradient_color_for_state(state, column, "carry_total", r, g, b, target_identity)
end

function UI.smoothed_opposing_carry_total_to_hex_color_for_state(state, column, v, max_value)
    local carry_max = math.max(1, tonumber(max_value) or 1530)
    local r, g, b = UI.opposing_carry_total_to_rgb_color(v, carry_max)
    local target_identity = UI.get_gradient_target_identity("opposing_carry_total", v, carry_max)
    return UI.smoothed_gradient_color_for_state(state, column, "opposing_carry_total", r, g, b, target_identity)
end

-- END role-specific Drive/Super/Carry gradient colors

function UI.hit_damage_scaling_color(scaling)
    local r, g, b = UI.hit_damage_scaling_rgb(scaling)
    return UI.rgb_to_hex_color(r, g, b)
end

function UI.smoothed_hit_damage_scaling_color(key, scaling)
    key = key or "default"
    local target_r, target_g, target_b = UI.hit_damage_scaling_rgb(scaling)
    local target_key = tostring(target_r) .. ":" .. tostring(target_g) .. ":" .. tostring(target_b)
    local smoothing_frames = math.max(1, tonumber(UI.hit_damage_scaling_color_smoothing_frames) or 40)

    local smooth = UI.hit_damage_scaling_color_state[key]
    if not smooth then
        smooth = {
            r = target_r,
            g = target_g,
            b = target_b,
            start_r = target_r,
            start_g = target_g,
            start_b = target_b,
            target_r = target_r,
            target_g = target_g,
            target_b = target_b,
            target_key = target_key,
            queued_target_r = nil,
            queued_target_g = nil,
            queued_target_b = nil,
            queued_target_key = nil,
            frame = smoothing_frames,
            fast_forward = false,
        }
        UI.hit_damage_scaling_color_state[key] = smooth
        return UI.rgb_to_hex_color(smooth.r, smooth.g, smooth.b)
    end

    local function clear_queue()
        smooth.queued_target_r = nil
        smooth.queued_target_g = nil
        smooth.queued_target_b = nil
        smooth.queued_target_key = nil
    end

    local function start_transition(next_r, next_g, next_b, next_key)
        smooth.start_r = smooth.r or next_r
        smooth.start_g = smooth.g or next_g
        smooth.start_b = smooth.b or next_b
        smooth.target_r = next_r
        smooth.target_g = next_g
        smooth.target_b = next_b
        smooth.target_key = next_key
        smooth.frame = 0
        smooth.fast_forward = false
    end

    local is_active = (smooth.frame or smoothing_frames) < smoothing_frames

    if smooth.target_key ~= target_key then
        if is_active then
            -- Do not retarget the in-progress transition. Queue the latest target,
            -- then finish the active transition at 1.33x speed so the displayed color
            -- still reaches the gradient color for the first scaling value before
            -- beginning the next transition.
            smooth.queued_target_r = target_r
            smooth.queued_target_g = target_g
            smooth.queued_target_b = target_b
            smooth.queued_target_key = target_key
            smooth.fast_forward = true
        else
            clear_queue()
            start_transition(target_r, target_g, target_b, target_key)
        end
    elseif smooth.queued_target_key ~= nil then
        -- The requested target returned to the active transition target, so the
        -- queued transition is no longer needed.
        clear_queue()
        smooth.fast_forward = false
    end

    is_active = (smooth.frame or smoothing_frames) < smoothing_frames
    if is_active then
        local frame_step = smooth.fast_forward and 1.33 or 1
        smooth.frame = math.min(smoothing_frames, (smooth.frame or 0) + frame_step)
        local t = Utils.clamp(smooth.frame / smoothing_frames, 0, 1)
        smooth.r = smooth.start_r + ((smooth.target_r - smooth.start_r) * t)
        smooth.g = smooth.start_g + ((smooth.target_g - smooth.start_g) * t)
        smooth.b = smooth.start_b + ((smooth.target_b - smooth.start_b) * t)
    else
        smooth.r = smooth.target_r
        smooth.g = smooth.target_g
        smooth.b = smooth.target_b
    end

    if (smooth.frame or smoothing_frames) >= smoothing_frames then
        smooth.r = smooth.target_r
        smooth.g = smooth.target_g
        smooth.b = smooth.target_b

        if smooth.queued_target_key ~= nil and smooth.queued_target_key ~= smooth.target_key then
            local queued_r = smooth.queued_target_r
            local queued_g = smooth.queued_target_g
            local queued_b = smooth.queued_target_b
            local queued_key = smooth.queued_target_key
            clear_queue()
            start_transition(queued_r, queued_g, queued_b, queued_key)
        else
            clear_queue()
            smooth.fast_forward = false
        end
    end

    return UI.rgb_to_hex_color(smooth.r, smooth.g, smooth.b)
end

function UI.get_hit_damage_scaling_color_key(state)
    local player_key = "p" .. tostring(((state and state.attacker) or 0) + 1)
    local combo_identity = "no_combo"
    if state then
        -- state.start is replaced when a new combo sequence begins.
        -- Using it as part of the smoothing key makes the first DPH color
        -- of a new combo snap immediately instead of interpolating from
        -- the previous combo's final color.
        combo_identity = tostring(state.start or state.finish or state)
    end
    return player_key, player_key .. ":" .. combo_identity
end

function UI.smoothed_hit_damage_scaling_color_for_state(state, scaling)
    local player_key, combo_key = UI.get_hit_damage_scaling_color_key(state)
    local old_key = UI.hit_damage_scaling_color_active_key[player_key]
    if old_key ~= combo_key then
        if old_key then
            UI.hit_damage_scaling_color_state[old_key] = nil
        end
        UI.hit_damage_scaling_color_active_key[player_key] = combo_key
    end

    return UI.smoothed_hit_damage_scaling_color(combo_key, scaling)
end

function UI.value_to_hex_color(v, max_val)
    max_val = max_val or 7500
    local t = math.max(0, math.min(v / max_val, 1))
    local r, g = 0, 0
    if t < 0.25 then
        r = 255; g = math.floor((t / 0.25) * 255)
    else
        r = math.floor((1 - (t - 0.25) / 0.75) * 255); g = 255
    end
    return UI.apply_opacity_to_color(0xFF000000 + (g << 8) + r, UI.get_display_text_opacity())
end

function UI.signed_value_to_hex_color(v, max_abs)
    max_abs = max_abs or 7500
    local value = Utils.clamp(tonumber(v) or 0, -max_abs, max_abs)
    local t = value / max_abs
    local r, g = 255, 255

    if t < 0 then
        g = 255
        r = math.floor((1 + t) * 255 + 0.5)
    elseif t > 0 then
        r = 255
        g = math.floor((1 - t) * 255 + 0.5)
    end

    return UI.apply_opacity_to_color(0xFF000000 + (g << 8) + r, UI.get_display_text_opacity())
end

function UI.yellow_to_red_hex_color(v, max_val)
    max_val = max_val or 7500
    local t = math.max(0, math.min((tonumber(v) or 0) / max_val, 1))
    local r = 255
    local g = math.floor((1 - t) * 255 + 0.5)
    return UI.apply_opacity_to_color(0xFF000000 + (g << 8) + r, UI.get_display_text_opacity())
end

function UI.attacker_carry_color(v, max_value)
    local value = math.abs(tonumber(v) or 0)
    local carry_max = math.max(1, tonumber(max_value) or 1530)
    local yellow_start = carry_max * 0.20
    local green_start = carry_max * 0.70
    if value == 0 then
        return UI.apply_opacity_to_color(0xFFFFFFFF, UI.get_display_text_opacity())
    end

    local r, g = 255, 0

    if value < yellow_start then
        local t = (value - 1) / math.max(yellow_start - 1, 1)
        g = math.floor((Utils.clamp(t, 0, 1)) * 255 + 0.5)
    elseif value < green_start then
        local t = (value - yellow_start) / math.max(green_start - yellow_start, 1)
        r = math.floor((1 - Utils.clamp(t, 0, 1)) * 255 + 0.5)
        g = 255
    else
        g = 255
    end

    return UI.apply_opacity_to_color(0xFF000000 + (g << 8) + r, UI.get_display_text_opacity())
end

function UI.advantage_block_color(v)
    local advantage = Utils.clamp(tonumber(v) or 0, -10, 10)
    local r, g = 255, 255

    if advantage < 0 then
        g = math.floor(((advantage + 10) / 10) * 255 + 0.5)
    elseif advantage > 0 then
        r = math.floor((1 - (advantage / 10)) * 255 + 0.5)
    end

    return UI.apply_opacity_to_color(0xFF000000 + (g << 8) + r, UI.get_display_text_opacity())
end

function UI.advantage_hit_color(v)
    local advantage = Utils.clamp(tonumber(v) or 0, -12, 12)
    local r, g = 255, 255

    if advantage < 0 then
        g = math.floor(((advantage + 12) / 12) * 255 + 0.5)
    elseif advantage > 0 then
        r = math.floor((1 - (advantage / 12)) * 255 + 0.5)
    end

    return UI.apply_opacity_to_color(0xFF000000 + (g << 8) + r, UI.get_display_text_opacity())
end

function UI.draw_stroked_text_to_draw_list(draw_list, screen_pos, text, color)
    if not draw_list or not screen_pos then return false end

    local stroke_color = UI.apply_opacity_to_color(0xFF000000, UI.get_display_text_opacity())
    local text_color = color or UI.apply_opacity_to_color(0xFFFFFFFF, UI.get_display_text_opacity())
    -- Match the previous Background Opacity 0% stroke thickness at all background opacities.
    local thickness = 1.5

    if draw_list and (draw_list.add_text or draw_list.AddText) then
        local x_base = screen_pos.x or screen_pos[1] or 0
        local y_base = screen_pos.y or screen_pos[2] or 0
        local t = math.floor(thickness + 0.5)
        local d = math.floor(t * 0.7071 + 0.5)

        -- Fixed symmetric pattern: 8 cardinal+diagonal for t=1, 16 points for t=2
        local offsets = {
            {-t, 0}, {t, 0}, {0, -t}, {0, t},
            {-d, -d}, {d, -d}, {-d, d}, {d, d},
        }
        if t >= 2 then
            offsets[#offsets+1] = {-t, -1}; offsets[#offsets+1] = {t, -1}
            offsets[#offsets+1] = {-t, 1};  offsets[#offsets+1] = {t, 1}
            offsets[#offsets+1] = {-1, -t}; offsets[#offsets+1] = {1, -t}
            offsets[#offsets+1] = {-1, t};  offsets[#offsets+1] = {1, t}
        end

        local function add_at(px, py, clr)
            if draw_list.add_text then
                draw_list:add_text(Vector2f.new(px, py), clr, text)
            else
                draw_list:AddText(Vector2f.new(px, py), clr, text)
            end
        end

        for _, off in ipairs(offsets) do
            add_at(x_base + off[1], y_base + off[2], stroke_color)
        end

        add_at(x_base, y_base, text_color)
        return true
    end

    return false
end

function UI.reserve_drawn_item(id_prefix, size)
    if imgui.invisible_button then
        UI.stroke_item_id = UI.stroke_item_id + 1
        imgui.invisible_button("##" .. id_prefix .. "_" .. tostring(UI.stroke_item_id), size)
    elseif imgui.new_line then
        imgui.new_line()
    end
end
function UI.draw_drive_cooldown_indicator(draw_list, cx, cy, radius, cooldown, peak, scale)
    if not draw_list or not cooldown or cooldown <= 0 then return end
    if not peak or peak <= 0 then return end
    local fraction = Utils.clamp(cooldown / peak, 0, 1)
    if fraction <= 0 then return end

    local num_segments = 32
    local start_angle = -math.pi / 2
    local stroke_width = math.max(1.0, 2.0 * (scale or 1))
    local inner_radius = math.max(1.0, radius - stroke_width)

    -- Circle opacity: current Opacity (BG) + 25%, clamped to 100%
    local circle_opacity = Utils.clamp(UI.get_display_background_opacity() + 0.30, 0, 1)
    local foreground_opacity = Utils.clamp(circle_opacity * 1.20, 0, 1)
    local inner_bg_color = UI.apply_opacity_to_color(0xFF202020, circle_opacity)
    local ring_color = UI.apply_opacity_to_color(0xFFE0E0E0, circle_opacity)

    -- Single solid foreground color based on the cooldown fraction.
    -- fraction=1 (high/peak cooldown) → red,
    -- fraction=0.5 → bright yellow,
    -- fraction=0 (low/expired cooldown) → green.
    -- Packed ABGR: 0xAABBGGRR.
    local function compute_solid_color()
        local t = fraction
        local r, g, b
        if t < 0.5 then
            r = math.floor(255 * (t / 0.5) + 0.5)
            g = 255
            b = 0
        else
            r = 255
            g = math.floor(255 * (1 - (t - 0.5) / 0.5) + 0.5)
            b = 0
        end
        local rgb = (b * 0x10000) + (g * 0x100) + r
        return (math.floor(Utils.clamp(foreground_opacity, 0, 1) * 255 + 0.5) << 24) + rgb
    end

    local function draw_full_circle(color)
        draw_list:path_clear()
        for i = 0, num_segments - 1 do
            local t = i / num_segments
            local angle = start_angle + t * 2 * math.pi
            draw_list:path_line_to(Vector2f.new(cx + math.cos(angle) * inner_radius, cy + math.sin(angle) * inner_radius))
        end
        draw_list:path_fill_convex(color)
    end

    -- Always use dark inner background so there's no color flip at 50%.
    draw_full_circle(inner_bg_color)

    -- Draw the remaining portion as a single filled pie slice from center.
    -- For arcs > 180°, split into two convex halves to satisfy PathFillConvex.
    local elapsed_count = math.floor((1 - fraction) * num_segments + 0.5)
    if elapsed_count < num_segments then
        local solid_color = compute_solid_color()
        local first_seg = elapsed_count
        local last_seg = num_segments - 1
        local total_segs = last_seg - first_seg + 1

        local function fill_arc(seg_start, seg_end)
            draw_list:path_clear()
            draw_list:path_line_to(Vector2f.new(cx, cy))
            for i = seg_start, seg_end do
                local frac_a = i / num_segments
                if i == num_segments - 1 then
                    frac_a = math.min(frac_a + (1 / num_segments) * 0.7, 1.0)
                end
                local angle_a = start_angle + frac_a * 2 * math.pi
                draw_list:path_line_to(Vector2f.new(cx + math.cos(angle_a) * inner_radius, cy + math.sin(angle_a) * inner_radius))
            end
            draw_list:path_fill_convex(solid_color)
        end

        if total_segs <= num_segments / 2 then
            fill_arc(first_seg, last_seg)
        else
            local mid_seg = first_seg + math.floor(total_segs / 2)
            fill_arc(first_seg, mid_seg)
            fill_arc(mid_seg, last_seg)
        end
    end

    -- Draw stroke outline in off-white (no duplicate vertex at seam)
    draw_list:path_clear()
    for i = 0, num_segments - 1 do
        local t = i / num_segments
        local angle = start_angle + t * 2 * math.pi
        draw_list:path_line_to(Vector2f.new(cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    end
    draw_list:path_stroke(ring_color, 1, stroke_width)
end
function UI.draw_text_with_black_stroke(text, color)
    local draw_list = UI.get_active_draw_list()
    local screen_pos = imgui.get_cursor_screen_pos()
    local text_size = imgui.calc_text_size(text)
    if UI.draw_stroked_text_to_draw_list(draw_list, screen_pos, text, color) then
        UI.reserve_drawn_item("attack_info_stroke", text_size)
        return
    end

    local text_color = color or UI.apply_opacity_to_color(0xFFFFFFFF, UI.get_display_text_opacity())
    imgui.text_colored(text, text_color)
end

function UI.get_visibility_key(player_index)
    return (player_index == 0) and "column_visibility_p1" or "column_visibility_p2"
end

function UI.get_visibility_column_label(column)
    if not column then return "" end

    if column.id == "hit_damage" then
        return "Damage (Hit)"
    end

    if column.id == "damage" then
        return "Damage (Total)"
    end

    if column.id == "p1_drive" or column.id == "p2_drive" then
        local role = column.id:sub(1, 2) == "p1" and "Self" or "Opponent"
        return "Drive (" .. role .. ")"
    end

    if column.id == "p1_super" or column.id == "p2_super" then
        local role = column.id:sub(1, 2) == "p1" and "Self" or "Opponent"
        return "Super (" .. role .. ")"
    end

    if column.id == "p1_carry" or column.id == "p2_carry" then
        -- Carry source roles are intentionally inverted relative to Drive/Super:
        -- p1_carry controls the opponent carry display slot.
        -- p2_carry controls the self carry display slot.
        local role = column.id == "p1_carry" and "Opponent" or "Self"
        return "Carry (" .. role .. ")"
    end

    return column.label
end

function UI.get_player_scoped_combo_column_label(player_index, column)
    if not column then return "" end

    local self_prefix = player_index == 0 and "p1" or "p2"
    local opponent_prefix = player_index == 0 and "p2" or "p1"

    if column.id == self_prefix .. "_drive" then return "Drive" end
    if column.id == self_prefix .. "_super" then return "Super" end

    -- Carry labels differ from Drive/Super and follow the current visual role:
    --   the self-prefix carry column is the opponent carry display, shown as Carry.
    --   the opposite-prefix carry column is this player's self carry display.
    if column.id == self_prefix .. "_carry" then return "Carry" end
    if column.id == opponent_prefix .. "_carry" then
        return player_index == 0 and "P1 Carry" or "P2 Carry"
    end

    return column.label
end

function UI.get_column_def_by_id(column_id)
    for i, column in ipairs(COLUMN_DEFS) do
        if column.id == column_id then
            return i, column
        end
    end

    return nil, nil
end

function UI.get_player_absolute_column_id_for_role(player_index, source_column_id)
    local source_prefix, suffix = string.match(source_column_id or "", "^(p[12])_(.+)$")
    if not source_prefix or not suffix then
        return source_column_id
    end

    local self_prefix = player_index == 0 and "p1" or "p2"
    local opponent_prefix = player_index == 0 and "p2" or "p1"
    local target_prefix = source_prefix == "p1" and self_prefix or opponent_prefix

    return target_prefix .. "_" .. suffix
end

function UI.get_visible_columns(player_index)
    local width_scale = UI.get_column_width_scale()

    local function make_visible_column(index, column)
        local base_width = column.width
        if column.percent_width and column.unit_id and UI.get_unit_mode(column.unit_id) == "percent" then
            base_width = column.percent_width
        end

        local label = column.label
        if UI.get_player_scoped_combo_column_label then
            label = UI.get_player_scoped_combo_column_label(player_index, column)
        end

        return {
            index = index,
            id = column.id,
            label = label,
            unit_id = column.unit_id,
            percent_max = column.percent_max,
            color_max = column.color_max,
            width = math.ceil(base_width * width_scale),
        }
    end

    local columns = {}

    if Config.settings.toggle_mirror_column_order ~= false then
        -- Mirror Column Order uses P1's selected columns as the role source:
        --   p1_* means Self, p2_* means Opponent.
        -- P1/left reverses that role order for visual mirroring.
        -- P2/right keeps that role order left-to-right, but maps Self to p2_*
        -- and Opponent to p1_* before values are read by column.index.
        local source_visibility = Config.settings.column_visibility_p1 or {}

        local first, last, step = 1, #COLUMN_DEFS, 1
        if player_index == 0 then
            first, last, step = #COLUMN_DEFS, 1, -1
        end

        for source_index = first, last, step do
            local source_column = COLUMN_DEFS[source_index]
            if source_visibility[source_column.id] ~= false then
                local target_id = UI.get_player_absolute_column_id_for_role(player_index, source_column.id)
                local target_index, target_column = UI.get_column_def_by_id(target_id)

                if target_column then
                    table.insert(columns, make_visible_column(target_index, target_column))
                end
            end
        end

        return columns
    end

    local visibility = Config.settings[UI.get_visibility_key(player_index)] or {}
    for i, column in ipairs(COLUMN_DEFS) do
        if visibility[column.id] ~= false then
            table.insert(columns, make_visible_column(i, column))
        end
    end

    return columns
end

function UI.get_combo_column_label(column, visible_columns)
    if not column then return "" end

    if column.id == "damage" then
        for _, visible_column in ipairs(visible_columns or {}) do
            if visible_column.id == "hit_damage" then
                return "Total"
            end
        end
    end

    return column.label
end

function UI.get_column_width_scale()
    local default_font_scale = 1
    if imgui.get_default_font_size then
        default_font_scale = (imgui.get_default_font_size() or UI.small_font) / UI.small_font
    end
    return UI.get_display_scale() * math.max(default_font_scale, 1)
end

function UI.get_unit_mode(unit_id)
    if not unit_id then return DEFAULT_UNIT_MODE end
    local units = Config.settings.unit_display or {}
    local mode = units[unit_id] or DEFAULT_UNIT_MODE
    return UNIT_MODES[mode] and mode or DEFAULT_UNIT_MODE
end

function UI.format_percent_value(v, percent_max)
    if not percent_max or percent_max == 0 then return UI.format_raw_value(v) end
    if v == nil then return "-" end
    local formatted = string.format("%.0f%%", (v / percent_max) * 100)
    if formatted == "-0%" then
        return "0%"
    end
    return formatted
end

function UI.get_carry_bounds_for_facing(facing_right)
    if facing_right == true then
        return CARRY_RIGHT_FACING_MIN, CARRY_RIGHT_FACING_MAX
    end

    return CARRY_LEFT_FACING_MIN, CARRY_LEFT_FACING_MAX
end

function UI.clamp_carry_position_for_facing(pos, facing_right)
    local min_pos, max_pos = UI.get_carry_bounds_for_facing(facing_right)
    return Utils.clamp(tonumber(pos) or 0, min_pos, max_pos), min_pos, max_pos
end

function UI.get_carry_position_percent(pos, facing_right)
    if pos == nil or facing_right == nil then
        return nil
    end

    local clamped_pos, min_pos, max_pos = UI.clamp_carry_position_for_facing(pos, facing_right)
    local divisor = math.max(1, math.min(math.abs(min_pos), math.abs(max_pos)))
    local percent = (clamped_pos / divisor) * 100

    return Utils.clamp(percent, -100, 100)
end

function UI.get_carry_position_percent_for_player(player, facing_right_override)
    if not player or player.pos_x == nil then
        return nil
    end

    local facing_right = facing_right_override
    if facing_right == nil then
        facing_right = player.dir
    end

    return UI.get_carry_position_percent(player.pos_x, facing_right)
end

function UI.get_carry_space_to_direction_wall(pos, facing_right_reference, move_right)
    local clamped_pos, min_pos, max_pos = UI.clamp_carry_position_for_facing(pos, facing_right_reference)
    if move_right then
        return max_pos - clamped_pos
    end

    return clamped_pos - min_pos
end

function UI.get_player_carry_space_to_direction_wall(player, move_right, facing_right_reference)
    if not player or player.pos_x == nil then
        return nil
    end

    local facing_right = facing_right_reference
    if facing_right == nil then
        facing_right = player.dir
    end

    return UI.get_carry_space_to_direction_wall(player.pos_x, facing_right, move_right)
end

function UI.get_carry_finish_reference_facing(attacker_start_dir, attacker_finish_dir, force_side_switch)
    if force_side_switch == true and attacker_start_dir ~= nil then
        return not (attacker_start_dir == true)
    end

    if attacker_finish_dir ~= nil then
        return attacker_finish_dir == true
    end

    return attacker_start_dir == true
end

function UI.format_carry_percent_value(v, percent_max, carry_percent_mode, carry_percent_override)
    if not percent_max or percent_max == 0 then return UI.format_raw_value(v) end
    if v == nil then return "-" end

    local percent
    if carry_percent_override ~= nil then
        percent = tonumber(carry_percent_override) or 0
    else
        percent = (v / percent_max) * 100
    end

    local formatted = string.format("%.0f%%", percent)
    if formatted == "-0%" then
        return "0%"
    end
    return formatted
end

function UI.format_raw_value(v)
    if v == nil then return "-" end
    local formatted = string.format("%.0f", v)
    if formatted == "-0" then
        return "0"
    end
    return formatted
end

function UI.round_display_value(v)
    local value = tonumber(v) or 0
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

function UI.ko_suppress(state, value)
    if state and state.ended_in_ko then return nil end
    return value
end

function UI.format_column_value(v, column, percent_max, carry_percent_mode, carry_percent_override)
    if column and column.unit_id == "drive" and Config.settings.reduce_drive and v ~= nil then
        v = v / 10
        if percent_max then percent_max = percent_max / 10 end
    end
    if column and column.unit_id == "super" and Config.settings.reduce_super and v ~= nil then
        v = v / 10
        if percent_max then percent_max = percent_max / 10 end
    end

    if column and column.id == "hit_damage" then
        if v == nil then return "-" end
        return UI.format_raw_value(v)
    end

    if column and column.unit_id and UI.get_unit_mode(column.unit_id) == "percent" then
        if column.unit_id == "carry" then
            return UI.format_carry_percent_value(v, percent_max or column.percent_max, carry_percent_mode, carry_percent_override)
        end
        return UI.format_percent_value(v, percent_max or column.percent_max)
    end
    return UI.format_raw_value(v)
end

function UI.format_carry_display_value(v, column, percent_max, carry_percent_mode, carry_percent_override)
    if v == nil then
        return "-"
    end

    if v == 0 then
        return "-"
    end

    return UI.format_column_value(v, column, percent_max, carry_percent_mode, carry_percent_override)
end

function UI.get_carry_facing_arrow(player)
    -- Maximal Carry rows should display position values only, without facing
    -- direction suffixes.
    local _ = player
    return nil
end

function UI.get_carry_facing_arrows(p1_player, p2_player)
    local _ = p1_player
    local __ = p2_player
    return {
        p1_carry = nil,
        p2_carry = nil,
    }
end

-- Drive delta helper.
--
-- drive_adjusted stores two fundamentally different quantities:
--   • Normal state:  the drive gauge value  (0 – 60 000)
--   • Burnout state: the recovery timer shifted by -60 000  (–60 000 – 0)
--
-- Burnout recovery is displayed as a negative gauge that climbs from -60000
-- to 0. When a player enters Burnout during a sequence, keep the finish row's
-- actual burnout value visible, but calculate that player's total as if the
-- finish endpoint was 0. Examples:
--   • Self Drive:     20000 -> burnout displays -20000! in red.
--   • Opponent Drive: 10000 -> burnout displays -10000! in green.
UI.DRIVE_BURNOUT_SELF_ENTRY_MARKER = "__attack_info_drive_burnout_self_entry__:"
UI.DRIVE_BURNOUT_OPPONENT_ENTRY_MARKER = "__attack_info_drive_burnout_opponent_entry__:"
UI.DRIVE_BURNOUT_ENTRY_MARKER = UI.DRIVE_BURNOUT_SELF_ENTRY_MARKER

function UI.make_drive_burnout_entry_value(value, role)
    local marker = role == "opponent" and UI.DRIVE_BURNOUT_OPPONENT_ENTRY_MARKER or UI.DRIVE_BURNOUT_SELF_ENTRY_MARKER
    return marker .. tostring(tonumber(value) or 0)
end

function UI.is_drive_burnout_self_entry_marker(value)
    return type(value) == "string"
        and string.sub(value, 1, string.len(UI.DRIVE_BURNOUT_SELF_ENTRY_MARKER)) == UI.DRIVE_BURNOUT_SELF_ENTRY_MARKER
end

function UI.is_drive_burnout_opponent_entry_marker(value)
    return type(value) == "string"
        and string.sub(value, 1, string.len(UI.DRIVE_BURNOUT_OPPONENT_ENTRY_MARKER)) == UI.DRIVE_BURNOUT_OPPONENT_ENTRY_MARKER
end

function UI.is_drive_burnout_entry_marker(value)
    return UI.is_drive_burnout_self_entry_marker(value) or UI.is_drive_burnout_opponent_entry_marker(value)
end

function UI.get_drive_burnout_entry_value(value)
    if UI.is_drive_burnout_self_entry_marker(value) then
        return tonumber(string.sub(value, string.len(UI.DRIVE_BURNOUT_SELF_ENTRY_MARKER) + 1)) or 0
    end

    if UI.is_drive_burnout_opponent_entry_marker(value) then
        return tonumber(string.sub(value, string.len(UI.DRIVE_BURNOUT_OPPONENT_ENTRY_MARKER) + 1)) or 0
    end

    return tonumber(value) or 0
end

function UI.adjust_drive(finish_val, start_val, finish_incap, start_incap)
    finish_val = tonumber(finish_val) or 0
    start_val = tonumber(start_val) or 0

    if start_incap and not finish_incap then
        return 0 - start_val
    end

    if finish_incap ~= start_incap then
        return 0
    end

    return finish_val - start_val
end

function UI.adjust_drive_total(finish_val, start_val, finish_incap, start_incap, drive_role)
    finish_val = tonumber(finish_val) or 0
    start_val = tonumber(start_val) or 0
    drive_role = drive_role == "opponent" and "opponent" or "self"

    if finish_incap and not start_incap then
        local spend = 0 - start_val
        return UI.make_drive_burnout_entry_value(spend, drive_role)
    end

    return UI.adjust_drive(finish_val, start_val, finish_incap, start_incap)
end

function UI.get_percent_max_values(state)
    local is_p1 = state.attacker == 0
    local defender = is_p1 and state.finish.p2 or state.finish.p1
    local damage_max = defender and defender.hp_max or 10000
    if not damage_max or damage_max <= 0 then damage_max = 10000 end

    return {
        nil,
        damage_max,
        60000, 30000,
        60000, 30000,
        CARRY_TOTAL_MAX, CARRY_TOTAL_MAX,
        490,
        nil,
    }
end

function UI.get_hit_damage_breakdown(state, is_p1)
    if state and state.hit_damage_lock and (state.hit_damage_lock_frozen or (state.finished and not state.started)) then
        return state.hit_damage_lock.raw_damage or 0, state.hit_damage_lock.scaling, state.hit_damage_lock.scaled_damage or 0
    end

    local prefer_current_hit_damage = state
        and state.ko_start_hp_locked == true
        and (state.hit_damage_lock == nil or state.hit_damage_lock_provisional == true)
    local raw_damage, scaling, scaled_damage = ComboData.get_hit_damage_snapshot(
        state, is_p1 and "p1" or "p2", state.finish, prefer_current_hit_damage
    )

    -- Fall back to the non-provisional hit_damage_lock when the live DmgValue
    -- snapshot returns 0. During active combos where pDmgHitDT.DmgValue is
    -- intermittently 0 (common for throws), this prevents flickering between
    -- the correct damage and "-" on every frame.
    if raw_damage <= 0 and state and state.hit_damage_lock and not state.hit_damage_lock_provisional then
        return state.hit_damage_lock.raw_damage or 0, state.hit_damage_lock.scaling, state.hit_damage_lock.scaled_damage or 0
    end

    return raw_damage, scaling, scaled_damage
end

function UI.get_combo_damage_value(state, is_p1)
    if state.is_blocked then
        local start_defender = is_p1 and state.start.p2 or state.start.p1
        local finish_defender = is_p1 and state.finish.p2 or state.finish.p1
        local damage = (start_defender and start_defender.hp_current or 0) - (finish_defender and finish_defender.hp_current or 0)
        return math.max(0, damage)
    end

    local start_def = (is_p1 and state.start.p2 or state.start.p1) or {}
    local finish_def = (is_p1 and state.finish.p2 or state.finish.p1) or {}
    local finish_atk = (is_p1 and state.finish.p1 or state.finish.p2) or {}
    local locked_combo_damage_total = math.max(
        tonumber(state.combo_damage_lock) or 0,
        tonumber(state.hit_damage_lock_combo_damage_total) or 0,
        tonumber(state.hit_damage_lock and state.hit_damage_lock.combo_damage_total) or 0
    )
    local combo_dmg = math.max(locked_combo_damage_total, tonumber(finish_atk.combo_damage) or 0)

    -- When poison/DoT damage is present (A.K.I.), mComboDamage can omit poison
    -- ticks. Prefer the defender HP delta whenever poison was seen or whenever
    -- the HP delta has already outgrown the game's reported combo total.
    local hp_start = math.max(
        tonumber(state.start_hp_lock) or 0,
        tonumber(start_def.hp_current) or 0
    )
    local hp_current = tonumber(finish_def.hp_current) or hp_start
    local hp_delta = math.max(0, hp_start - hp_current)
    local total
    if state.poison_was_active or hp_delta > combo_dmg then
        total = math.max(combo_dmg, hp_delta)
    elseif state and locked_combo_damage_total > 0 and (state.hit_damage_lock_frozen or (state.finished and not state.started)) then
        total = locked_combo_damage_total
    else
        total = combo_dmg
    end

    -- Cap overkill: total cannot exceed defender's starting HP when KO'd.
    if hp_current <= 0 and hp_start > 0 then
        total = math.min(total, hp_start)
    end

    return total
end

function UI.did_carry_position_order_side_switch(attacker_start, defender_start, attacker_finish, defender_finish)
    if not attacker_start or not defender_start or not attacker_finish or not defender_finish then
        return false
    end

    local start_attacker_pos = tonumber(attacker_start.pos_x)
    local start_defender_pos = tonumber(defender_start.pos_x)
    local finish_attacker_pos = tonumber(attacker_finish.pos_x)
    local finish_defender_pos = tonumber(defender_finish.pos_x)
    if not start_attacker_pos or not start_defender_pos or not finish_attacker_pos or not finish_defender_pos then
        return false
    end

    local start_delta = start_attacker_pos - start_defender_pos
    local finish_delta = finish_attacker_pos - finish_defender_pos
    if start_delta == 0 or finish_delta == 0 then
        return false
    end

    return (start_delta > 0 and finish_delta < 0) or (start_delta < 0 and finish_delta > 0)
end

function UI.should_use_side_switch_carry(state, is_p1_attacker, start_p1, start_p2)
    if not state or not state.finish then
        return false
    end

    local attacker_start = is_p1_attacker and start_p1 or start_p2
    local defender_start = is_p1_attacker and start_p2 or start_p1
    local attacker_finish = is_p1_attacker and state.finish.p1 or state.finish.p2
    local defender_finish = is_p1_attacker and state.finish.p2 or state.finish.p1
    if not attacker_start or not attacker_finish then
        return false
    end

    local position_order_swapped = UI.did_carry_position_order_side_switch(
        attacker_start, defender_start, attacker_finish, defender_finish
    )

    if state.is_throw == true then
        local throw_active = state.started == true and state.finished ~= true

        if throw_active then
            local current_throw_frame = tonumber(attacker_finish and attacker_finish.action_frame)

            if not position_order_swapped then
                state.throw_side_switch_frames = 0
                state.throw_side_switch_last_action_frame = current_throw_frame
            elseif current_throw_frame ~= nil then
                if state.throw_side_switch_last_action_frame ~= current_throw_frame then
                    state.throw_side_switch_frames = (tonumber(state.throw_side_switch_frames) or 0) + 1
                    state.throw_side_switch_last_action_frame = current_throw_frame
                end
            else
                state.throw_side_switch_frames = 0
                state.throw_side_switch_last_action_frame = nil
            end

            local confirmed_side_switch = (tonumber(state.throw_side_switch_frames) or 0) >= THROW_SIDE_SWITCH_CONFIRM_FRAMES

            ComboData.debug_log("should_use_side_switch_carry"
                .. " is_p1_atk=" .. tostring(is_p1_attacker)
                .. " atk_start.dir=" .. tostring(attacker_start and attacker_start.dir)
                .. " atk_finish.dir=" .. tostring(attacker_finish and attacker_finish.dir)
                .. " atk_start_x=" .. tostring(attacker_start and attacker_start.pos_x)
                .. " def_start_x=" .. tostring(defender_start and defender_start.pos_x)
                .. " atk_finish_x=" .. tostring(attacker_finish and attacker_finish.pos_x)
                .. " def_finish_x=" .. tostring(defender_finish and defender_finish.pos_x)
                .. " throw_side_switch_frames=" .. tostring(state.throw_side_switch_frames)
                .. " result=" .. tostring(confirmed_side_switch)
                .. " reasons=" .. (position_order_swapped and (confirmed_side_switch and "throw_active_confirmed" or "throw_active_tracking") or "throw_active")
                , "carry_debug"
            )
            return confirmed_side_switch
        end

        -- Some throws briefly swap sides mid-animation, which can flip facing,
        -- but should only count as side-switch carry after the throw has
        -- resolved and the players actually end on opposite sides.
        ComboData.debug_log("should_use_side_switch_carry"
            .. " is_p1_atk=" .. tostring(is_p1_attacker)
            .. " atk_start.dir=" .. tostring(attacker_start and attacker_start.dir)
            .. " atk_finish.dir=" .. tostring(attacker_finish and attacker_finish.dir)
            .. " atk_start_x=" .. tostring(attacker_start and attacker_start.pos_x)
            .. " def_start_x=" .. tostring(defender_start and defender_start.pos_x)
            .. " atk_finish_x=" .. tostring(attacker_finish and attacker_finish.pos_x)
            .. " def_finish_x=" .. tostring(defender_finish and defender_finish.pos_x)
            .. " result=" .. tostring(position_order_swapped)
            .. " reasons=" .. (position_order_swapped and "throw_position_order" or "")
            , "carry_debug"
        )
        return position_order_swapped
    end

    -- Side-switch detection: three complementary checks
    -- 1. Relative position order swapped (position-order check)
    -- 2. Attacker direction flipped between start and finish (dir-flip check)
    -- 3. Defender crossed past the attacker's start position (crossed-start check)
    -- Any one of these indicates a side switch.

    local result = false
    local reasons = {}

    -- Check 1: position-order swap
    if position_order_swapped then
        result = true
        reasons[#reasons + 1] = "position_order"
    end

    -- Check 2: attacker direction flip
    local attacker_start_dir = attacker_start and attacker_start.dir
    local attacker_finish_dir = attacker_finish and attacker_finish.dir
    if not result
        and attacker_start_dir ~= nil
        and attacker_finish_dir ~= nil
        and attacker_start_dir ~= attacker_finish_dir
    then
        result = true
        reasons[#reasons + 1] = "dir_flip"
    end

    -- Check 3: defender crossed past the attacker's start position
    if not result
        and defender_start
        and defender_finish
        and attacker_start
        and attacker_start.pos_x ~= nil
        and defender_start.pos_x ~= nil
        and defender_finish.pos_x ~= nil
    then
        local s_def = tonumber(defender_start.pos_x)
        local f_def = tonumber(defender_finish.pos_x)
        local s_atk = tonumber(attacker_start.pos_x)
        if s_def and f_def and s_atk then
            local def_started_left = s_def < s_atk
            local def_finished_right = f_def > s_atk
            local def_started_right = s_def > s_atk
            local def_finished_left = f_def < s_atk
            if (def_started_left and def_finished_right) or (def_started_right and def_finished_left) then
                result = true
                reasons[#reasons + 1] = "crossed_start"
            end
        end
    end

    ComboData.debug_log("should_use_side_switch_carry"
        .. " is_p1_atk=" .. tostring(is_p1_attacker)
        .. " atk_start.dir=" .. tostring(attacker_start and attacker_start.dir)
        .. " atk_finish.dir=" .. tostring(attacker_finish and attacker_finish.dir)
        .. " atk_start_x=" .. tostring(attacker_start and attacker_start.pos_x)
        .. " def_start_x=" .. tostring(defender_start and defender_start.pos_x)
        .. " atk_finish_x=" .. tostring(attacker_finish and attacker_finish.pos_x)
        .. " def_finish_x=" .. tostring(defender_finish and defender_finish.pos_x)
        .. " result=" .. tostring(result)
        .. " reasons=" .. table.concat(reasons, ",")
        , "carry_debug"
    )

    return result
end

function UI.get_carry_total_value(start_player, finish_player, attacker_start, attacker_finish, percent_max, force_side_switch)
    local start_pos = start_player and start_player.pos_x or 0
    local finish_pos = finish_player and finish_player.pos_x or 0
    start_pos = tonumber(start_pos) or 0
    finish_pos = tonumber(finish_pos) or 0

    local attacker_start_dir = attacker_start and attacker_start.dir
    local attacker_finish_dir = attacker_finish and attacker_finish.dir
    local start_facing_right = attacker_start_dir == true
    local finish_facing_right = UI.get_carry_finish_reference_facing(attacker_start_dir, attacker_finish_dir, force_side_switch)
    local side_switched = force_side_switch == true
        or (
            attacker_start_dir ~= nil
            and attacker_finish_dir ~= nil
            and attacker_start_dir ~= attacker_finish_dir
        )

    if side_switched then
        -- Side-switch totals are not simple screen-space deltas. Measure how
        -- much space remains to the wall the attacker is facing at combo start
        -- versus combo end so corner escapes and corner-to-corner carry stay
        -- large even when the defender's raw position barely changes.
        local _ = percent_max
        if attacker_start_dir == nil then
            return 0
        end

        local start_space = UI.get_carry_space_to_direction_wall(start_pos, start_facing_right, start_facing_right == true)
        local finish_space = UI.get_carry_space_to_direction_wall(finish_pos, finish_facing_right, finish_facing_right == true)
        return start_space - finish_space
    end

    start_pos = UI.clamp_carry_position_for_facing(start_pos, start_facing_right)
    finish_pos = UI.clamp_carry_position_for_facing(finish_pos, start_facing_right)
    local direction_sign = attacker_start_dir == true and 1 or -1
    return (finish_pos - start_pos) * direction_sign
end

function UI.get_carry_total_percent_value(start_player, finish_player, attacker_start, attacker_finish, force_side_switch)
    local attacker_start_dir = attacker_start and attacker_start.dir
    local attacker_finish_dir = attacker_finish and attacker_finish.dir
    if attacker_start_dir == nil then
        return nil
    end

    local side_switched = force_side_switch == true
        or (
            attacker_start_dir ~= nil
            and attacker_finish_dir ~= nil
            and attacker_start_dir ~= attacker_finish_dir
        )

    local start_space
    local finish_space
    if side_switched then
        local start_facing_right = attacker_start_dir == true
        local finish_facing_right = UI.get_carry_finish_reference_facing(attacker_start_dir, attacker_finish_dir, force_side_switch)

        local start_pos = start_player and start_player.pos_x
        local finish_pos = finish_player and finish_player.pos_x
        if start_pos == nil or finish_pos == nil then
            return nil
        end
        start_space = UI.get_carry_space_to_direction_wall(start_pos, start_facing_right, start_facing_right == true)
        finish_space = UI.get_carry_space_to_direction_wall(finish_pos, finish_facing_right, finish_facing_right == true)
    else
        start_space = UI.get_player_carry_space_to_direction_wall(start_player, attacker_start_dir == true, attacker_start_dir == true)
        finish_space = UI.get_player_carry_space_to_direction_wall(finish_player, attacker_start_dir == true, attacker_start_dir == true)
    end

    if start_space == nil or finish_space == nil then
        return nil
    end

    local progress = start_space - finish_space
    return Utils.clamp((progress / CARRY_TOTAL_MAX) * 100, -100, 100)
end

-- Keep old name as backward-compatible redirect
UI.should_use_throw_side_switch_carry = UI.should_use_side_switch_carry

-- BEGIN side-switch Carry total sign rule
function UI.apply_side_switch_carry_total_sign_rule(p1_carry_total, p2_carry_total, is_p1_attacker, attacker_start, attacker_finish)
    -- Side-switch sign is now part of UI.get_carry_total_value. Keep this
    -- function as a no-op compatibility shim for the existing total-row call site.
    local _ = is_p1_attacker
    local __ = attacker_start
    local ___ = attacker_finish
    return p1_carry_total, p2_carry_total
end

-- END side-switch Carry total sign rule

function UI.get_gap_value(gap)
    gap = tonumber(gap) or 0
    if gap <= 70 then return 0 end
    return gap
end

function UI.get_combo_value_rows(state, player_index, is_defense)
    local is_p1 = state.attacker == 0
    local rows = {}
    local percent_max_values = UI.get_percent_max_values(state)
    local start_snapshot = ComboData.get_start_display_snapshot(state)
    local start_p1 = start_snapshot.p1 or state.start.p1 or {}
    local start_p2 = start_snapshot.p2 or state.start.p2 or {}
    local attacker_start = is_p1 and start_p1 or start_p2
    local attacker_finish = is_p1 and state.finish.p1 or state.finish.p2
    local start_hp_locked_after_ko = state and state.ko_start_hp_locked == true
    local start_defender_hp = tonumber(state.start_hp_lock) or 0
    if start_defender_hp <= 0 then
        local start_defender = is_p1 and start_p2 or start_p1
        start_defender_hp = tonumber(start_defender and start_defender.hp_current) or 0
    end
    if start_defender_hp <= 0 and not start_hp_locked_after_ko then
        local live_combo_damage = tonumber(is_p1 and state.finish.p1.combo_damage or state.finish.p2.combo_damage) or 0
        start_defender_hp = math.max(start_defender_hp, tonumber(state.combo_damage_lock) or 0, live_combo_damage)
    end
    if state and not start_hp_locked_after_ko and start_defender_hp <= 0 and state.finished and not state.started and state.combo_damage_lock ~= nil then
        start_defender_hp = tonumber(state.combo_damage_lock) or 0
    end
    local hit_damage_start, hit_damage_finish, hit_damage_total = UI.get_hit_damage_breakdown(state, is_p1)
    local hit_damage_scaling = hit_damage_finish
    local throw_side_switch = UI.should_use_side_switch_carry(state, is_p1, start_p1, start_p2)
    local finish_p1_for_carry = state.finish.p1 or {}
    local finish_p2_for_carry = state.finish.p2 or {}
    if state.ko_carry_finish_p1_x ~= nil then
        finish_p1_for_carry = {
            pos_x = state.ko_carry_finish_p1_x,
            dir = state.finish.p1 and state.finish.p1.dir,
        }
    end
    if state.ko_carry_finish_p2_x ~= nil then
        finish_p2_for_carry = {
            pos_x = state.ko_carry_finish_p2_x,
            dir = state.finish.p2 and state.finish.p2.dir,
        }
    end
    local p1_carry_total
    local p2_carry_total
    if state.ko_carry_total_p1 ~= nil then
        -- Use KO-frozen carry totals (pre-computed scalar values)
        p1_carry_total = state.ko_carry_total_p1
        p2_carry_total = state.ko_carry_total_p2
    else
        p1_carry_total = UI.get_carry_total_value(start_p1, state.finish.p1, attacker_start, attacker_finish, percent_max_values[7], throw_side_switch)
        p2_carry_total = UI.get_carry_total_value(start_p2, state.finish.p2, attacker_start, attacker_finish, percent_max_values[8], throw_side_switch)
    end
    p1_carry_total, p2_carry_total = UI.apply_side_switch_carry_total_sign_rule(
        p1_carry_total, p2_carry_total, is_p1, attacker_start, attacker_finish
    )
    -- Carry columns are intentionally swapped in the total row values:
    --   p1_carry column displays p2_carry_total
    --   p2_carry column displays p1_carry_total
    -- Keep percent overrides aligned with the rendered column payload, not the
    -- raw player-index names, so attacker/self carry and opponent carry both
    -- normalize against the correct start/finish positions.
    local carry_percent_overrides = {
        p1_carry = UI.get_carry_total_percent_value(start_p2, finish_p2_for_carry, attacker_start, attacker_finish, throw_side_switch),
        p2_carry = UI.get_carry_total_percent_value(start_p1, finish_p1_for_carry, attacker_start, attacker_finish, throw_side_switch),
    }

    local combo_damage = UI.get_combo_damage_value(state, is_p1)
    if not state.is_blocked and not state.ended_in_ko then
        local positive_combo_damage = tonumber(combo_damage) or 0
        local positive_hit_total = tonumber(hit_damage_total) or 0
        if positive_combo_damage > 0 and positive_hit_total > positive_combo_damage then
            hit_damage_total = positive_combo_damage
            local divisor = math.max(tonumber(hit_damage_finish) or 100, 1)
            hit_damage_start = math.max(1, math.ceil((positive_combo_damage * 100) / divisor))
        end
    end

    -- Negate damage values in defense mode
    if is_defense then
        if hit_damage_start ~= nil and hit_damage_start > 0 then hit_damage_start = -hit_damage_start end
        if hit_damage_finish ~= nil and hit_damage_finish > 0 then hit_damage_finish = -hit_damage_finish end
        if hit_damage_total ~= nil and hit_damage_total > 0 then hit_damage_total = -hit_damage_total end
        -- hit_damage_scaling stays positive for color purposes
        -- Negate carry totals (defender being pushed back = negative from defender's perspective)
        p1_carry_total = -(p1_carry_total or 0)
        p2_carry_total = -(p2_carry_total or 0)
        if carry_percent_overrides.p1_carry ~= nil then carry_percent_overrides.p1_carry = -carry_percent_overrides.p1_carry end
        if carry_percent_overrides.p2_carry ~= nil then carry_percent_overrides.p2_carry = -carry_percent_overrides.p2_carry end
    end

    if not ((player_index == 0 and Config.settings.toggle_minimal_view_p1) or (player_index == 1 and Config.settings.toggle_minimal_view_p2)) then
        local start_carry_facing_right = attacker_start and attacker_start.dir
        local finish_carry_facing_right = UI.get_carry_finish_reference_facing(
            attacker_start and attacker_start.dir,
            attacker_finish and attacker_finish.dir,
            throw_side_switch
        )
        table.insert(rows, {
            font_size = UI.get_scaled_font_size(UI.medium_font),
            is_color = false,
            percent_max = percent_max_values,
            carry_percent_mode = "position",
            carry_percent_overrides = {
                p1_carry = UI.get_carry_position_percent_for_player(start_p2, start_carry_facing_right),
                p2_carry = UI.get_carry_position_percent_for_player(start_p1, start_carry_facing_right),
            },
            carry_direction_arrows = UI.get_carry_facing_arrows(start_p1, start_p2),
            blank_columns = { adv = true },
            cell_scaling = { hit_damage = hit_damage_scaling },
            values = {
                hit_damage_start,
                start_defender_hp,
                start_p1.drive_adjusted or 0, start_p1.super or 0,
                start_p2.drive_adjusted or 0, start_p2.super or 0,
                start_p2.pos_x or 0, start_p1.pos_x or 0, UI.get_gap_value(start_p1.gap), 0
            }
        })
        table.insert(rows, {
            font_size = UI.get_scaled_font_size(UI.medium_font),
            is_color = false,
            percent_max = percent_max_values,
            carry_percent_mode = "position",
            carry_percent_overrides = {
                p1_carry = UI.get_carry_position_percent_for_player(finish_p2_for_carry, finish_carry_facing_right),
                p2_carry = UI.get_carry_position_percent_for_player(finish_p1_for_carry, finish_carry_facing_right),
            },
            carry_direction_arrows = UI.get_carry_facing_arrows(state.finish.p1, state.finish.p2),
            blank_columns = { adv = true },
            display_modes = { hit_damage = "percent" },
            cell_scaling = { hit_damage = hit_damage_scaling },
            values = {
                hit_damage_finish,
                (is_p1 and state.finish.p2.hp_current or state.finish.p1.hp_current) or 0,
                state.finish.p1.drive_adjusted or 0, state.finish.p1.super or 0,
                state.finish.p2.drive_adjusted or 0, state.finish.p2.super or 0,
                (state.ko_carry_finish_p2_x or state.finish.p2.pos_x or 0), (state.ko_carry_finish_p1_x or state.finish.p1.pos_x or 0), UI.ko_suppress(state, UI.get_gap_value(state.finish.p1.gap)), 0
            }
        })
    end

    -- Total/delta row - negate total damage in defense mode
    local advantage = (is_p1 and state.finish.p1.advantage or state.finish.p2.advantage) or 0
    if is_defense then
        if combo_damage ~= nil and combo_damage > 0 then combo_damage = -combo_damage end
        advantage = -advantage
    end

    table.insert(rows, {
        font_size = UI.get_scaled_font_size(UI.large_font),
        is_color = true,
        percent_max = percent_max_values,
        carry_percent_overrides = carry_percent_overrides,
        cell_scaling = { hit_damage = hit_damage_scaling },
        values = {
            hit_damage_total,
            combo_damage,
            UI.adjust_drive_total(
                state.finish.p1.drive_adjusted or 0,
                start_p1.drive_adjusted or 0,
                state.finish.p1.incapacitated,
                start_p1.incapacitated,
                is_p1 and "self" or "opponent"
            ),
            (state.finish.p1.super or 0) - (start_p1.super or 0),
            UI.adjust_drive_total(
                state.finish.p2.drive_adjusted or 0,
                start_p2.drive_adjusted or 0,
                state.finish.p2.incapacitated,
                start_p2.incapacitated,
                is_p1 and "opponent" or "self"
            ),
            (state.finish.p2.super or 0) - (start_p2.super or 0),
            p2_carry_total,
            p1_carry_total,
            UI.ko_suppress(state, UI.get_gap_value(is_p1 and state.finish.p1.gap or state.finish.p2.gap)),
            advantage,
        }
    })

    return rows
end

function UI.get_combo_table_width_from_columns(visible_columns)
    local width = 0
    for _, column in ipairs(visible_columns) do
        width = width + column.width
    end

    return math.max(width, math.ceil(UI.minimum_combo_window_width * UI.get_column_width_scale()))
end

function UI.get_combo_window_width(state, player_index)
    local visible_columns = UI.get_visible_columns(player_index or state.attacker)
    return UI.get_combo_table_width_from_columns(visible_columns) + math.ceil(UI.window_padding_width * UI.get_column_width_scale())
end

function UI.process_columns(values, is_color, visible_columns, percent_max_values, state, carry_percent_mode, blank_columns, display_modes, cell_scaling, carry_direction_arrows, carry_percent_overrides, player_index, row_index)
    local is_defense = player_index ~= nil and state ~= nil and state.attacker ~= player_index
    local display_values_texts = nil
    for display_index, column in ipairs(visible_columns) do
        imgui.table_set_column_index(display_index - 1)
        local v = values[column.index]
        local is_drive_burnout_entry = UI.is_drive_burnout_entry_marker and UI.is_drive_burnout_entry_marker(v)
        local is_drive_burnout_opponent_entry = UI.is_drive_burnout_opponent_entry_marker and UI.is_drive_burnout_opponent_entry_marker(v)
        local display_v = is_drive_burnout_entry and UI.get_drive_burnout_entry_value(v) or v
        local v_numeric = tonumber(display_v) or 0
        local w = column.width
        local percent_max = percent_max_values and percent_max_values[column.index] or nil
        local carry_percent_override = carry_percent_overrides and carry_percent_overrides[column.id] or nil
        local text
        if is_drive_burnout_entry then
            if display_modes and display_modes[column.id] == "percent" then
                text = UI.format_percent_value(display_v, 100) .. "!"
            else
                text = UI.format_column_value(display_v, column, percent_max, carry_percent_mode) .. "!"
            end
        elseif display_modes and display_modes[column.id] == "percent" then
            text = UI.format_percent_value(display_v, 100)
        elseif blank_columns and blank_columns[column.id] then
            text = ""
        else
            text = UI.format_column_value(display_v, column, percent_max, carry_percent_mode, carry_percent_override)
        end
        local is_p1_window = state and state.attacker == 0
        local is_opposing_drive = (is_p1_window and column.id == "p2_drive") or (not is_p1_window and column.id == "p1_drive")
        local is_opposing_super = (is_p1_window and column.id == "p2_super") or (not is_p1_window and column.id == "p1_super")
        local is_carry = column.id == "p1_carry" or column.id == "p2_carry"
        local is_opposing_carry = is_carry and ((is_p1_window and column.id == "p1_carry") or ((not is_p1_window) and column.id == "p2_carry"))
        local is_window_opponent_drive = (player_index == 0 and column.id == "p2_drive") or (player_index == 1 and column.id == "p1_drive")
        local is_window_opponent_super = (player_index == 0 and column.id == "p2_super") or (player_index == 1 and column.id == "p1_super")
        local is_gap = column.id == "gap"
        local is_dash_placeholder = text == "-" and (column.id == "damage" or is_carry or column.id == "hit_damage" or column.unit_id == "drive" or is_gap)
        local display_v_numeric = v_numeric
        local hit_damage_scaling = cell_scaling and cell_scaling[column.id] or nil
        if column.id == "adv" then
            display_v_numeric = UI.round_display_value(v_numeric)
        end

        if column.id == "adv" and state and (state.started or display_v_numeric == 0 or state.ended_in_ko) then
            text = ""
            display_v_numeric = 0
        end

        if is_carry and state then
            text = UI.format_carry_display_value(v, column, percent_max, carry_percent_mode, carry_percent_override)
            local carry_arrow = carry_direction_arrows and carry_direction_arrows[column.id] or nil
            if carry_arrow and text ~= "" and text ~= "-" then
                text = text .. " " .. carry_arrow
            end
            is_dash_placeholder = text == "-" and (column.id == "damage" or is_carry or column.id == "hit_damage")
        end

        if state and (state.ended_in_ko or (state.finished and not state.started)) then
            display_values_texts = display_values_texts or {}
            table.insert(display_values_texts, column.id .. "=" .. text)
        end

        UI.center_text(text, w, function()
                if is_gap then
                    UI.draw_text_with_black_stroke(text)
                elseif is_dash_placeholder then
                    UI.draw_text_with_black_stroke(text)
                elseif text ~= "" and is_color and not is_dash_placeholder and (is_drive_burnout_entry or display_v_numeric ~= 0 or is_opposing_drive or is_opposing_super or column.unit_id == "super" or is_carry or (column.id == "adv" and state and (state.is_blocked or not state.ended_in_knockdown))) then
                    local color
                    if is_drive_burnout_entry then
                        color = is_drive_burnout_opponent_entry and UI.rgb_to_hex_color(0, 255, 0) or UI.rgb_to_hex_color(255, 0, 0)
                    elseif column.id == "adv" and state and state.is_blocked then
                        color = UI.advantage_block_color(display_v_numeric)
                    elseif column.id == "adv" and state and not state.ended_in_knockdown then
                        color = UI.advantage_hit_color(display_v_numeric)
                    elseif column.id == "hit_damage" then
                        if is_defense then
                            -- Yellow at 15% scaling, red at 100% scaling
                            local scaling_val = tonumber(hit_damage_scaling) or 100
                            local t = Utils.clamp((scaling_val - 15) / 85, 0, 1)
                            local inv_r = 255
                            local inv_g = math.floor(255 * (1 - t) + 0.5)
                            color = UI.rgb_to_hex_color(inv_r, inv_g, 0)
                        else
                            color = UI.smoothed_hit_damage_scaling_color_for_state(state, hit_damage_scaling)
                        end
                    elseif column.id == "damage" then
                        if is_defense and v_numeric < 0 then
                            -- Yellow at -1, orange at -2000, red at -7000
                            local abs_val = math.abs(v_numeric)
                            local dmg_r, dmg_g, dmg_b = UI.rgb_from_gradient_anchors(abs_val, {
                                { 1,    255, 255,   0 },  -- yellow at -1
                                { 2000, 255, 165,   0 },  -- orange at -2000
                                { 7000, 255,   0,   0 },  -- red at -7000
                            })
                            color = UI.rgb_to_hex_color(dmg_r, dmg_g, dmg_b)
                        else
                            color = UI.smoothed_value_to_hex_color_for_state(state, column, v_numeric, column.color_max)
                        end
                    elseif is_defense and is_window_opponent_drive then
                        -- Magnitude of opponent drive usage: yellow at +1, orange at 10000, red at 20000, deep red at 30000
                        local abs_val = math.abs(v_numeric)
                        local dr, dg, db = UI.rgb_from_gradient_anchors(abs_val, {
                            { 1,      255, 255,   0 },  -- yellow at ~0
                            { 10000,  255, 165,   0 },  -- orange at 10000
                            { 20000,  255,   0,   0 },  -- red at 20000
                            { 30000,  180,   0,   0 },  -- deep red at 30000
                        })
                        color = UI.rgb_to_hex_color(dr, dg, db)
                    elseif is_defense and is_window_opponent_super then
                        -- Magnitude of opponent super gauge change: yellow at +1, orange at 4000, red at 8000, deep red at 12000
                        local abs_val = math.abs(v_numeric)
                        local sr, sg, sb = UI.rgb_from_gradient_anchors(abs_val, {
                            { 1,      255, 255,   0 },  -- yellow at ~0
                            { 4000,   255, 165,   0 },  -- orange at 4000
                            { 8000,   255,   0,   0 },  -- red at 8000
                            { 12000,  180,   0,   0 },  -- deep red at 12000
                        })
                        color = UI.rgb_to_hex_color(sr, sg, sb)
                    elseif is_opposing_drive then
                        color = UI.smoothed_opposing_drive_to_hex_color_for_state(state, column, v_numeric)
                    elseif column.unit_id == "drive" then
                        color = UI.smoothed_self_drive_to_hex_color_for_state(state, column, v_numeric)
                    elseif is_opposing_super then
                        color = UI.smoothed_yellow_to_red_hex_color_for_state(state, column, v_numeric, column.color_max)
                    elseif column.unit_id == "super" then
                        color = UI.smoothed_self_super_to_hex_color_for_state(state, column, v_numeric)
                    elseif is_carry and is_defense then
                        -- Yellow at ~0, orange at 25%, red at 50%, deep red at 90%+
                        local abs_val = math.abs(v_numeric)
                        local cmax = math.max(1, tonumber(percent_max or column.color_max) or 1530)
                        local car_r, car_g, car_b = UI.rgb_from_gradient_anchors(abs_val, {
                            { 1,            255, 255,   0 },  -- yellow at ~0%
                            { 0.25 * cmax,  255, 165,   0 },  -- orange at 25%
                            { 0.50 * cmax,  255,   0,   0 },  -- red at 50%
                            { 0.90 * cmax,  180,   0,   0 },  -- deep red at 90%
                        })
                        color = UI.rgb_to_hex_color(car_r, car_g, car_b)
                    elseif is_opposing_carry then
                        color = UI.smoothed_opposing_carry_total_to_hex_color_for_state(state, column, v_numeric, percent_max or column.color_max)
                    elseif is_carry then
                        color = UI.smoothed_carry_total_to_hex_color_for_state(state, column, v_numeric, percent_max or column.color_max)
                    else
                        color = UI.value_to_hex_color(v_numeric, column.color_max)
                    end
                    UI.draw_text_with_black_stroke(text, color)
                else
                    UI.draw_text_with_black_stroke(text)
                end
        end)
    end

    local all_values_texts = nil
    if state and (state.ended_in_ko or (state.finished and not state.started)) then
        for _, all_col in ipairs(COLUMN_DEFS) do
            local all_v = values[all_col.index]
            local is_drive_burnout = UI.is_drive_burnout_entry_marker and UI.is_drive_burnout_entry_marker(all_v)
            local all_display_v = is_drive_burnout and UI.get_drive_burnout_entry_value(all_v) or all_v
            local all_percent_max = percent_max_values and percent_max_values[all_col.index] or nil
            local all_carry_percent_override = carry_percent_overrides and carry_percent_overrides[all_col.id] or nil
            local all_text
            if display_modes and display_modes[all_col.id] == "percent" then
                all_text = UI.format_percent_value(all_display_v, 100)
            else
                all_text = UI.format_column_value(all_display_v, all_col, all_percent_max, carry_percent_mode, all_carry_percent_override)
            end
            all_values_texts = all_values_texts or {}
            table.insert(all_values_texts, all_col.id .. "=" .. all_text)
        end
    end

    if state and (state.ended_in_ko or (state.finished and not state.started)) and display_values_texts and not UI.fadeout_alpha_override then
        local dv_key = "p" .. tostring((player_index or 0) + 1) .. ":" .. tostring(row_index or 0)
        local dv_hash = table.concat(display_values_texts, "\t")
        local prev_hash = ComboData.runtime_state.display_values_logged_hashes[dv_key]
        if prev_hash ~= dv_hash then
            ComboData.runtime_state.display_values_logged_hashes[dv_key] = dv_hash
            local dv_cat = is_defense and "log_defender_display" or "log_attacker_display"
            ComboData.debug_log("DISPLAY_VALUES " .. dv_key
                .. " character_id=" .. tostring(GameObjects.get_character_id(player_index or 0))
                .. " is_defense=" .. tostring(is_defense)
                .. " ended_in_ko=" .. tostring(state.ended_in_ko)
                .. " finished=" .. tostring(state.finished)
                .. " rendered=" .. table.concat(display_values_texts, " | ")
                .. (all_values_texts and (" all=" .. table.concat(all_values_texts, " | ")) or ""),
                dv_cat
            )
        end
    end
end

function UI.render_combo_window_table(state, player_index, is_defense)
    local visible_columns = UI.get_visible_columns(player_index)
    local value_rows = UI.get_combo_value_rows(state, player_index, is_defense)

    if #visible_columns == 0 then
        imgui.text("No columns selected")
        return
    end

    local table_flags = (imgui.TableFlags and imgui.TableFlags.SizingStretchProp) or 24576
    if imgui.begin_table("combo_table_p" .. tostring(state.attacker + 1) .. (is_defense and "_def" or ""), #visible_columns, table_flags, Vector2f.new(0, 0)) then
        for _, column in ipairs(visible_columns) do
            imgui.table_setup_column(UI.get_combo_column_label(column, visible_columns), nil, column.width)
        end

        UI.get_small_font()
        imgui.table_next_row()
        for display_index, column in ipairs(visible_columns) do
            imgui.table_set_column_index(display_index - 1)
            local label = UI.get_combo_column_label(column, visible_columns)
            local label_color = nil
            UI.center_text(label, column.width, function()
                local cursor_before = imgui.get_cursor_screen_pos()
                local text_size = imgui.calc_text_size(label)
                UI.draw_text_with_black_stroke(label, label_color)
                if column.id == "p1_drive" or column.id == "p2_drive" then
                    local player_idx = column.id == "p1_drive" and 0 or 1
                    local cd_value = (column.id == "p1_drive" and ComboData.p1_prev.drive_cooldown)
                                  or (column.id == "p2_drive" and ComboData.p2_prev.drive_cooldown)
                                  or 0
                    local cd_pending = ComboData.drive_cooldown_pending
                        and ComboData.drive_cooldown_pending[player_idx] == true
                    local cd_pending_peak = ComboData.drive_cooldown_pending_peak
                        and (ComboData.drive_cooldown_pending_peak[player_idx] or 0)
                        or 0
                    local cd_pending_frames = ComboData.get_pending_attack_frames(
                        player_idx == 0 and ComboData.p1_prev or ComboData.p2_prev
                    ) or 0
                    local cd_total_peak = ComboData.drive_cooldown_total_peak
                        and (ComboData.drive_cooldown_total_peak[player_idx] or 0)
                        or 0
                    local cd_pending_peak_final = ComboData.drive_cooldown_pending_peak_final
                        and (ComboData.drive_cooldown_pending_peak_final[player_idx] or 0)
                        or 0
                    local cd_legitimate = (column.id == "p1_drive" and ComboData.drive_cooldown_legitimate[0] == true)
                                      or (column.id == "p2_drive" and ComboData.drive_cooldown_legitimate[1] == true)
                    local should_draw = (cd_value and cd_value > 0 and cd_legitimate) or cd_pending
                    if should_draw then
                        local cd_peak = (column.id == "p1_drive" and ComboData.drive_cooldown_peak[0])
                                  or (column.id == "p2_drive" and ComboData.drive_cooldown_peak[1])
                                  or 0
                        local draw_cd_value = cd_value
                        local draw_cd_peak = cd_peak
                        if cd_pending and (not draw_cd_value or draw_cd_value <= 0) then
                            local pending_peak = math.max(cd_pending_peak, cd_pending_frames)
                            draw_cd_value = math.max(0, cd_pending_frames) + 120
                            draw_cd_peak = math.max(1, pending_peak + 120)
                        elseif draw_cd_value and draw_cd_value > 0 then
                            if cd_pending_peak_final and cd_pending_peak_final > 0 then
                                draw_cd_peak = cd_pending_peak_final
                            end
                        end
                        local draw_list = UI.get_active_draw_list()
                        if draw_list and draw_cd_value and draw_cd_value > 0 and draw_cd_peak and draw_cd_peak > 0 then
                            local scale = UI.get_column_width_scale()
                            local circle_radius = math.max(1, math.floor(8 * scale + 0.5))
                            local space_width = imgui.calc_text_size(" ")
                            local space_w = space_width and space_width.x or math.floor(8 * scale + 0.5)
                            local text_right = (cursor_before.x or 0) + text_size.x
                            local cx_val = text_right + space_w + circle_radius
                            local cy_val = (cursor_before.y or 0) + text_size.y / 2 - 1
                            UI.draw_drive_cooldown_indicator(draw_list, cx_val, cy_val, circle_radius, draw_cd_value, draw_cd_peak, scale)
                        end
                    end
                end
            end)
        end
        imgui.pop_font()

        for row_index, row in ipairs(value_rows) do
            imgui.table_next_row()
            UI.get_font_size(row.font_size)
            UI.process_columns(row.values, row.is_color == true, visible_columns, row.percent_max, state, row.carry_percent_mode, row.blank_columns, row.display_modes, row.cell_scaling, row.carry_direction_arrows, row.carry_percent_overrides, player_index, row_index)
            imgui.pop_font()
        end
        imgui.end_table()
    end
end

function UI.draw_combo_window_frame(player_index, title, x, y, anchor_pivot_x, window_width, minimal_setting, state, is_defense)
    local background_opacity = UI.get_display_background_opacity()
    local can_push_style_var = imgui.push_style_var and imgui.pop_style_var
    local window_rounding_style_var = can_push_style_var and UI.get_imgui_style_var("WindowRounding") or nil
    local border_size_style_var = can_push_style_var and UI.get_imgui_style_var("WindowBorderSize") or nil
    local suppress_border = background_opacity <= 0 and border_size_style_var ~= nil
    local style_var_push_count = 0

    local window_title = title
    if UI.fadeout_alpha_override ~= nil then
        window_title = tostring(title) .. "##fadeout_p" .. tostring((player_index or 0) + 1)
    end

    local bound_x, bound_y = UI.bound_window_position(player_index, x, y, anchor_pivot_x, window_width)
    imgui.set_next_window_pos(Vector2f.new(bound_x, bound_y), 1 << 0, Vector2f.new(anchor_pivot_x, 0))
    imgui.set_next_window_size(Vector2f.new(window_width, 0), 1)

    imgui.push_style_color(IMGUI_COL_WINDOW_BG, UI.apply_opacity_to_color(0xFF000000, background_opacity))
    imgui.push_style_color(IMGUI_COL_TEXT, UI.apply_opacity_to_color(0xFFFFFFFF, UI.get_display_text_opacity()))
    if window_rounding_style_var ~= nil then
        imgui.push_style_var(window_rounding_style_var, UI.get_display_box_rounding())
        style_var_push_count = style_var_push_count + 1
    end
    if suppress_border then
        imgui.push_style_var(border_size_style_var, 0)
        style_var_push_count = style_var_push_count + 1
    end

    if imgui.begin_window(window_title, true, 1 | 8 | 32) then
        if UI.fadeout_alpha_override == nil and UI.is_toggle_view_clicked() then
            Config.settings[minimal_setting] = not Config.settings[minimal_setting]

            local side = (player_index == 0) and "P1 " or "P2 "
            local status = Config.settings[minimal_setting] and "Disabled" or "Enabled"
            UI.action_notify(side .. "Minimal View " .. status, "alert_on_minimal")

            UI.mark_for_save()
        end
        UI.render_combo_window_table(state, player_index, is_defense)
        local captured = imgui.get_window_size and imgui.get_window_size()
        if captured then
            UI.last_window_size[player_index] = { x = tonumber(captured.x) or 0, y = tonumber(captured.y) or 0 }
        end
        imgui.end_window()
    end
    if style_var_push_count > 0 then
        imgui.pop_style_var(style_var_push_count)
    end
    imgui.pop_style_color(2)
end

function UI.render_player_combo_window(player_index, title, x, y, anchor_pivot_x, toggle_setting, minimal_setting, state, is_defense)
    if not state or not (state.started or state.finished) then return end
    local window_width = UI.get_combo_window_width(state, player_index)

    if UI.should_hide_combo_window(state) then
        UI.begin_fadeout_from_state(player_index, state, title, is_defense, x, y, anchor_pivot_x, window_width, minimal_setting)
        state.started = false
        state.finished = false
        state.timer_remaining = nil
        return
    end

    UI.store_fadeout_snapshot(player_index, state, title, is_defense, x, y, anchor_pivot_x, window_width, minimal_setting)
    UI.cancel_fadeout(player_index)

    UI.draw_combo_window_frame(player_index, title, x, y, anchor_pivot_x, window_width, minimal_setting, state, is_defense)
end

function UI.handle_hotkeys()
    if UI.was_key_down(F2_KEY) then
        if reframework:is_key_down(CTRL_KEY) then
            local new_state = not Config.settings.toggle_minimal_view_p1
            Config.settings.toggle_minimal_view_p1, Config.settings.toggle_minimal_view_p2 = new_state, new_state
            UI.action_notify("Minimal View " .. (new_state and "Enabled" or "Disabled"), "alert_on_minimal")
        else
            Config.settings.toggle_all = not Config.settings.toggle_all
            UI.action_notify("Display " .. (Config.settings.toggle_all and "Enabled" or "Disabled"), "alert_on_toggle")
            ComboData.debug_log("SETTING_CHANGED toggle_all=" .. tostring(Config.settings.toggle_all), "log_settings_changed")
        end
        UI.mark_for_save()
    end

    if reframework:is_key_down(CTRL_KEY) then
        if UI.was_key_down(KEY_4) then
            Config.settings.toggle_minimal_view_p1 = not Config.settings.toggle_minimal_view_p1
            UI.action_notify("P1 Minimal View " .. (Config.settings.toggle_minimal_view_p1 and "Enabled" or "Disabled"), "alert_on_minimal")
            UI.mark_for_save()
        elseif UI.was_key_down(KEY_5) then
            Config.settings.toggle_minimal_view_p2 = not Config.settings.toggle_minimal_view_p2
            UI.action_notify("P2 Minimal View " .. (Config.settings.toggle_minimal_view_p2 and "Enabled" or "Disabled"), "alert_on_minimal")
            UI.mark_for_save()
        end
    end
end

function UI.get_default_position_coords()
    return {
        self = {
            x = 45,
            y = 20,
        },
        opponent = {
            x = 55,
            y = 20,
        },
    }
end

function UI.ensure_position_coords()
    Config.ensure_position_settings()
    local defaults = UI.get_default_position_coords()
    local changed = false

    for _, def in ipairs(POSITION_DEFS) do
        local coords = Config.settings.position_coords[def.id]
        local default_coords = defaults[def.id]
        local cx = tonumber(coords.x)
        local cy = tonumber(coords.y)
        if cx == nil then
            coords.x = default_coords.x
            changed = true
        elseif cx > 100 then
            local sw = UI.get_screen_dim("x")
            coords.x = math.floor(cx / sw * 100 * 100 + 0.5) / 100
            changed = true
        end
        if cy == nil then
            coords.y = default_coords.y
            changed = true
        elseif cy > 100 then
            local sh = UI.get_screen_dim("y")
            coords.y = math.floor(cy / sh * 100 * 100 + 0.5) / 100
            changed = true
        end
    end

    changed = UI.apply_match_vertical_position(defaults) or changed
    if changed then UI.mark_for_save() end
    return Config.settings.position_coords, defaults
end

function UI.get_position_coord(id, axis, defaults)
    local coords = Config.settings.position_coords and Config.settings.position_coords[id] or nil
    local value = coords and tonumber(coords[axis]) or nil
    if value == nil then
        value = defaults and defaults[id] and defaults[id][axis] or 0
    end
    return UI.percent_to_pixels(value, axis)
end

function UI.get_mirrored_position_x(x)
    local display = imgui.get_display_size()
    local width = display and display.x or 0
    return math.floor((width - (tonumber(x) or 0)) + 0.5)
end

function UI.get_position_mirror_partner(id)
    if id == "self" then return "opponent" end
    if id == "opponent" then return "self" end
    return nil
end

-- Maps a position id ("self"/"opponent") to the player index whose combo window
-- it controls. self == P1 (right-anchored, anchor_pivot_x = 1); opponent == P2
-- (left-anchored, anchor_pivot_x = 0). See UI.render_windows.
function UI.get_position_player_index(id)
    if id == "self" then return 0 end
    if id == "opponent" then return 1 end
    return nil
end

function UI.get_position_anchor_x(id)
    return id == "self" and 1 or 0
end

-- Conservative over-estimate of a combo window's rendered height in pixels,
-- used only on the first frame before a real size has been captured. Over-
-- estimating is safe for clipping prevention (it pushes the window up, never
-- out of bounds). Once UI.last_window_size[player_index] is populated the real
-- height is used instead.
function UI.estimate_combo_window_height(player_index)
    local scale = UI.get_column_width_scale()
    local is_minimal = (player_index == 0 and Config.settings.toggle_minimal_view_p1 ~= false)
        or (player_index == 1 and Config.settings.toggle_minimal_view_p2 ~= false)
    local large = UI.get_scaled_font_size(UI.large_font)
    local medium = UI.get_scaled_font_size(UI.medium_font)
    local rows_height = is_minimal and large or (large + medium * 2)
    local row_count = is_minimal and 1 or 3
    local per_row_pad = math.ceil(20 * scale)
    local window_pad = math.ceil(24 * scale)
    return rows_height + row_count * per_row_pad + window_pad
end

-- Returns (width, height) in pixels for the combo window controlled by the
-- given position id. Width is always computed fresh from the current column
-- config; height uses the last captured render size, falling back to 0 (which
-- only bounds y to >= 0) so stored config values are never over-corrected by a
-- guess before the first render.
function UI.get_position_box_size(id)
    local player_index = UI.get_position_player_index(id)
    if player_index == nil then return 0, 0 end
    local width = UI.get_combo_window_width(nil, player_index)
    local last = UI.last_window_size and UI.last_window_size[player_index] or nil
    local height = (last and tonumber(last.y)) or 0
    return width, height
end

-- Clamps a pixel coordinate for the given position id/axis so the window stays
-- fully on-screen. Used by UI.set_position_coord to keep stored values sane and
-- by UI.get_shared_bounded_position_y for vertical matching.
function UI.get_bounded_position_coord(id, axis, pixel_val)
    local screen_w = UI.get_screen_dim("x")
    local screen_h = UI.get_screen_dim("y")
    local width, height = UI.get_position_box_size(id)
    local anchor_x = UI.get_position_anchor_x(id)
    local val = math.floor((tonumber(pixel_val) or 0) + 0.5)

    if axis == "x" then
        if anchor_x == 1 then
            local min_x = math.min(width, screen_w)
            val = Utils.clamp(val, min_x, screen_w)
        else
            local max_x = math.max(0, screen_w - width)
            val = Utils.clamp(val, 0, max_x)
        end
    else
        local max_y = math.max(0, screen_h - height)
        val = Utils.clamp(val, 0, max_y)
    end

    return val
end

-- Authoritative draw-time bounding. Clamps (x, y) so the combo window for
-- player_index (anchored at anchor_pivot_x) stays entirely within the game
-- window. Uses the freshly-computed window_width for X and the last captured
-- height (or a safe over-estimate on the first frame) for Y.
function UI.bound_window_position(player_index, x, y, anchor_pivot_x, window_width)
    local id = (player_index == 0) and "self" or "opponent"
    local screen_w = UI.get_screen_dim("x")
    local screen_h = UI.get_screen_dim("y")
    local last = UI.last_window_size and UI.last_window_size[player_index] or nil
    local height = (last and tonumber(last.y)) or UI.estimate_combo_window_height(player_index)
    -- Prefer the last captured outer width (includes borders) for exact bounds;
    -- fall back to the freshly-computed window_width on the first frame.
    local width = (last and tonumber(last.x)) or math.max(0, math.floor((tonumber(window_width) or 0) + 0.5))

    local bx = math.floor((tonumber(x) or 0) + 0.5)
    local by = math.floor((tonumber(y) or 0) + 0.5)

    if anchor_pivot_x == 1 then
        local min_x = math.min(width, screen_w)
        bx = Utils.clamp(bx, min_x, screen_w)
    else
        local max_x = math.max(0, screen_w - width)
        bx = Utils.clamp(bx, 0, max_x)
    end

    local max_y = math.max(0, screen_h - height)
    by = Utils.clamp(by, 0, max_y)

    return bx, by
end

function UI.get_shared_bounded_position_y(value, defaults)
    local display = imgui.get_display_size()
    local display_h = math.max(0, tonumber(display and display.y) or 0)
    local fallback = defaults and defaults.self and defaults.self.y or 0
    local rounded = math.floor((tonumber(value) or tonumber(fallback) or 0) + 0.5)
    local max_y = display_h

    if UI.get_position_box_size then
        local _, self_h = UI.get_position_box_size("self")
        local _, opponent_h = UI.get_position_box_size("opponent")
        max_y = math.min(display_h - self_h, display_h - opponent_h)
    end

    if max_y < 0 then
        return 0
    end

    return math.floor(Utils.clamp(rounded, 0, max_y) + 0.5)
end

function UI.get_screen_dim(axis)
    local display = imgui.get_display_size()
    if axis == "x" then
        return math.max(1, tonumber(display and display.x) or 1920)
    end
    return math.max(1, tonumber(display and display.y) or 1080)
end

function UI.percent_to_pixels(percent, axis)
    local screen_dim = UI.get_screen_dim(axis)
    return math.floor((tonumber(percent) or 0) / 100 * screen_dim + 0.5)
end

function UI.format_percent_str(value)
    local formatted = string.format("%.2f", tonumber(value) or 0)
    formatted = formatted:gsub("%.?0+$", "")
    return formatted
end

function UI.apply_match_vertical_position(defaults)
    Config.ensure_position_settings()
    if Config.settings.position_match_vertical == false then
        return false
    end

    local position_coords = Config.settings.position_coords
    local self_coords = position_coords and position_coords.self or nil
    local opponent_coords = position_coords and position_coords.opponent or nil
    if type(self_coords) ~= "table" or type(opponent_coords) ~= "table" then
        return false
    end

    local source_y = tonumber(self_coords.y)
    if source_y == nil then
        source_y = tonumber(opponent_coords.y)
    end
    if source_y == nil then
        return false
    end

    local screen_h = UI.get_screen_dim("y")
    local pixel_y = UI.percent_to_pixels(source_y, "y")
    local shared_pixel_y = UI.get_shared_bounded_position_y(pixel_y, nil)
    local shared_percent
    if shared_pixel_y == pixel_y then
        shared_percent = source_y
    else
        shared_percent = math.floor(shared_pixel_y / screen_h * 100 * 100 + 0.5) / 100
    end

    local changed = false
    if self_coords.y ~= shared_percent then
        self_coords.y = shared_percent
        changed = true
    end
    if opponent_coords.y ~= shared_percent then
        opponent_coords.y = shared_percent
        changed = true
    end

    return changed
end

function UI.set_position_coord(id, axis, value)
    Config.ensure_position_settings()
    local coords = Config.settings.position_coords[id]
    if type(coords) ~= "table" then return end

    local percent = tonumber(value)
    if percent == nil then return end

    percent = math.floor(percent * 100 + 0.5) / 100

    if UI.get_bounded_position_coord then
        local screen_dim = UI.get_screen_dim(axis)
        local pixel_val = UI.percent_to_pixels(percent, axis)
        local bounded_pixel = UI.get_bounded_position_coord(id, axis, pixel_val)
        if bounded_pixel ~= pixel_val then
            percent = math.floor(bounded_pixel / screen_dim * 100 * 100 + 0.5) / 100
        end
    end

    if axis == "y" and Config.settings.position_match_vertical ~= false then
        local screen_h = UI.get_screen_dim("y")
        local pixel_y = UI.percent_to_pixels(percent, "y")
        local bounded_pixel_y = UI.get_shared_bounded_position_y(pixel_y, nil)
        if bounded_pixel_y ~= pixel_y then
            percent = math.floor(bounded_pixel_y / screen_h * 100 * 100 + 0.5) / 100
        end
    end

    local changed = false
    if coords[axis] ~= percent then
        coords[axis] = percent
        changed = true
    end

    if axis == "x" and Config.settings.position_mirror_y_axis ~= false then
        local partner_id = UI.get_position_mirror_partner(id)
        local partner_coords = partner_id and Config.settings.position_coords[partner_id] or nil
        if type(partner_coords) == "table" then
            local screen_w = UI.get_screen_dim("x")
            local pixel_x = UI.percent_to_pixels(percent, "x")
            local mirrored_pixel_x = UI.get_mirrored_position_x(pixel_x)
            if UI.get_bounded_position_coord then
                mirrored_pixel_x = UI.get_bounded_position_coord(partner_id, "x", mirrored_pixel_x)
            end
            local mirrored_percent = math.floor(mirrored_pixel_x / screen_w * 100 * 100 + 0.5) / 100
            if partner_coords.x ~= mirrored_percent then
                partner_coords.x = mirrored_percent
                changed = true
            end
        end
    end

    if axis == "y" and Config.settings.position_match_vertical ~= false then
        local partner_id = UI.get_position_mirror_partner(id)
        local partner_coords = partner_id and Config.settings.position_coords[partner_id] or nil
        if type(partner_coords) == "table" and partner_coords.y ~= percent then
            partner_coords.y = percent
            changed = true
        end
    end

    if changed then
        UI.mark_for_save()
    end
end

function UI.get_state_player_snapshot(state, player_index, snapshot_key)
    local snapshot = state and state[snapshot_key] or nil
    if not snapshot then return nil end
    return player_index == 0 and snapshot.p1 or snapshot.p2
end

function UI.get_player_hp_loss_in_state(state, player_index)
    local start_player = UI.get_state_player_snapshot(state, player_index, "start")
    local finish_player = UI.get_state_player_snapshot(state, player_index, "finish")
    local start_hp = tonumber(start_player and start_player.hp_current)
    local finish_hp = tonumber(finish_player and finish_player.hp_current)
    if start_hp == nil or finish_hp == nil then return 0 end
    return math.max(0, start_hp - finish_hp)
end

function UI.states_share_start_hp(left_state, right_state)
    for player_index = 0, 1 do
        local left_player = UI.get_state_player_snapshot(left_state, player_index, "start")
        local right_player = UI.get_state_player_snapshot(right_state, player_index, "start")
        local left_hp = tonumber(left_player and left_player.hp_current)
        local right_hp = tonumber(right_player and right_player.hp_current)
        if left_hp == nil or right_hp == nil or left_hp ~= right_hp then
            return false
        end
    end

    return true
end

function UI.should_keep_trade_self_state(player_index, own_state, opponent_state)
    if not own_state or not opponent_state then return false end
    if own_state.is_blocked == true or opponent_state.is_blocked == true then return false end
    if own_state.attacker ~= player_index or opponent_state.attacker == player_index then return false end
    if not (own_state.started or own_state.finished) or not (opponent_state.started or opponent_state.finished) then return false end
    if own_state.is_trade_sequence == true and opponent_state.is_trade_sequence == true then return true end

    return UI.get_player_hp_loss_in_state(own_state, 1 - player_index) > 0
        and UI.get_player_hp_loss_in_state(opponent_state, player_index) > 0
        and UI.states_share_start_hp(own_state, opponent_state)
end

function UI.should_damage_taken_override_self_state(player_index, own_state, opponent_state)
    if Config.settings.toggle_update_on_damage ~= true then return false end
    if not own_state or not opponent_state then return false end
    if opponent_state.is_blocked == true then return false end
    if not (opponent_state.started or opponent_state.finished) then return false end
    if own_state.attacker ~= player_index or opponent_state.attacker == player_index then return false end
    if UI.should_keep_trade_self_state(player_index, own_state, opponent_state) then return false end

    -- Armor interactions can leave the failed counterattack's own state active
    -- after the opponent's punish has become the state the player needs to see.
    return UI.get_player_hp_loss_in_state(own_state, player_index) > 0
        and UI.get_player_hp_loss_in_state(opponent_state, player_index) > 0
end

function UI.resolve_player_window_state(panel_label, player_index, own_state, opponent_state)
    local resolved_state = nil
    local resolved_title = nil
    local is_defense = false
    local should_show = false

    if UI.should_keep_trade_self_state(player_index, own_state, opponent_state) then
        resolved_state = own_state
        resolved_title = panel_label .. " Current " .. ((own_state.is_blocked) and "Block" or "Combo")
        should_show = true
        return resolved_state, resolved_title, is_defense, should_show
    end

    if UI.should_damage_taken_override_self_state(player_index, own_state, opponent_state) then
        resolved_state = opponent_state
        resolved_title = panel_label .. " " .. ((opponent_state.is_blocked) and "Block Taken" or "Damage Taken")
        is_defense = true
        should_show = true
        return resolved_state, resolved_title, is_defense, should_show
    end

    -- Keep active self-attacks authoritative.
    if own_state and own_state.started then
        resolved_state = own_state
        resolved_title = panel_label .. " Current " .. ((own_state.is_blocked) and "Block" or "Combo")
        should_show = true
        return resolved_state, resolved_title, is_defense, should_show
    end

    -- Show defense view for an ACTIVE opponent combo (started). For a finished
    -- opponent state, only show defense when the player has no finished own
    -- state — otherwise the attacker would see their own KO/combo damage as
    -- negative, overwritten by a stale opponent finished state.
    local show_defense = false
    if opponent_state then
        if opponent_state.started then
            show_defense = (not opponent_state.is_blocked and Config.settings.toggle_update_on_damage)
                or (opponent_state.is_blocked and Config.settings.toggle_update_on_block)
        elseif opponent_state.finished and (not own_state or not own_state.finished) then
            show_defense = (not opponent_state.is_blocked and Config.settings.toggle_update_on_damage)
                or (opponent_state.is_blocked and Config.settings.toggle_update_on_block)
        end
    end

    if show_defense then
        resolved_state = opponent_state
        resolved_title = panel_label .. " " .. ((opponent_state.is_blocked) and "Block Taken" or "Damage Taken")
        is_defense = true
        should_show = true
    elseif own_state and own_state.finished then
        resolved_state = own_state
        resolved_title = panel_label .. " Current " .. ((own_state.is_blocked) and "Block" or "Combo")
        should_show = true
    end

    return resolved_state, resolved_title, is_defense, should_show
end

function UI.render_windows()
    if not Config.settings.toggle_all then
        UI.begin_fadeout(0)
        UI.begin_fadeout(1)
        return
    end
    if GameObjects.is_paused() then return end
    UI.right_click_this_frame = UI.was_key_down(RIGHT_CLICK)

    local _, defaults = UI.ensure_position_coords()
    local self_x = UI.get_position_coord("self", "x", defaults)
    local self_y = UI.get_position_coord("self", "y", defaults)
    local opponent_x = UI.get_position_coord("opponent", "x", defaults)
    local opponent_y = UI.get_position_coord("opponent", "y", defaults)

    local p1_rendered = false
    local p2_rendered = false

    if Config.settings.toggle_p1 then
        local p1_attack = ComboData.player_states[0]
        local p2_attack = ComboData.player_states[1]
        local p1_state, p1_title, p1_is_defense, p1_show = UI.resolve_player_window_state("P1", 0, p1_attack, p2_attack)

        if p1_show then
            UI.render_player_combo_window(0, p1_title, self_x, self_y, 1, "toggle_p1", "toggle_minimal_view_p1", p1_state, p1_is_defense)
            p1_rendered = true
        end
    end
    if Config.settings.toggle_p2 then
        local p2_attack = ComboData.player_states[1]
        local p1_attack = ComboData.player_states[0]
        local p2_state, p2_title, p2_is_defense, p2_show = UI.resolve_player_window_state("P2", 1, p2_attack, p1_attack)

        if p2_show then
            UI.render_player_combo_window(1, p2_title, opponent_x, opponent_y, 0, "toggle_p2", "toggle_minimal_view_p2", p2_state, p2_is_defense)
            p2_rendered = true
        end
    end

    if not p1_rendered then UI.begin_fadeout(0) end
    if not p2_rendered then UI.begin_fadeout(1) end
end

function UI.is_toggle_view_clicked()
    if not UI.right_click_this_frame then return false end
    local mouse = imgui.get_mouse()
    local pos = imgui.get_window_pos()
    local size = imgui.get_window_size()
    if not mouse or not pos or not size then return false end
    return mouse.x >= pos.x and mouse.x <= pos.x + size.x
       and mouse.y >= pos.y and mouse.y <= pos.y + size.y
end

function UI.update_combo_timers()
    for i = 0, 1 do
        local state = ComboData.player_states[i]
        if state.timer_remaining and state.timer_remaining > 0 then
            state.timer_remaining = state.timer_remaining - 1
        end
    end
end

function UI.should_hide_combo_window(state)
    return Config.settings.combo_timer_duration > 0 and state.timer_remaining and state.timer_remaining <= 0
end

function UI.fadeout_alpha_for_frame(frame)
    local n = UI.FADEOUT_FRAMES
    if n <= 0 then return 0 end
    local t = math.max(0, math.min(tonumber(frame) or 0, n)) / n
    local v = 1 - (t * t)
    if v < 0 then v = 0 end
    if v > 1 then v = 1 end
    return v
end

function UI.store_fadeout_snapshot(player_index, state, title, is_defense, x, y, anchor_pivot_x, window_width, minimal_setting)
    local snap = UI.fadeout_snapshot[player_index]
    if not snap then return end
    snap.state = Utils.deep_copy(state)
    snap.title = title
    snap.is_defense = is_defense
    snap.x = x
    snap.y = y
    snap.anchor = anchor_pivot_x
    snap.width = window_width
    snap.minimal = minimal_setting
    snap.stamp = UI.fadeout_frame_counter
    snap.snapshot_has_state = true
end

function UI.fadeout_active_count()
    local n = 0
    for i = 0, 1 do
        if UI.fadeout[i] and UI.fadeout[i].active then n = n + 1 end
    end
    return n
end

function UI.begin_fadeout(player_index)
    local snap = UI.fadeout_snapshot[player_index]
    local slot = UI.fadeout[player_index]
    if not snap or not slot then return end
    if slot.active then return end
    if not snap.state then return end
    if not snap.snapshot_has_state then return end
    if UI.fadeout_active_count() == 0 then
        UI.fadeout_global_frame = 0
    end
    slot.snapshot = snap.state
    slot.title = snap.title
    slot.is_defense = snap.is_defense
    slot.x = snap.x
    slot.y = snap.y
    slot.anchor = snap.anchor
    slot.width = snap.width
    slot.minimal = snap.minimal
    slot.active = true
end

function UI.begin_fadeout_from_state(player_index, state, title, is_defense, x, y, anchor_pivot_x, window_width, minimal_setting)
    local slot = UI.fadeout[player_index]
    if not slot or slot.active then return end
    if not state or not (state.started or state.finished) then return end
    UI.store_fadeout_snapshot(player_index, state, title, is_defense, x, y, anchor_pivot_x, window_width, minimal_setting)
    local snap = UI.fadeout_snapshot[player_index]
    if UI.fadeout_active_count() == 0 then
        UI.fadeout_global_frame = 0
    end
    slot.snapshot = snap.state
    slot.title = snap.title
    slot.is_defense = snap.is_defense
    slot.x = snap.x
    slot.y = snap.y
    slot.anchor = snap.anchor
    slot.width = snap.width
    slot.minimal = snap.minimal
    slot.active = true
end

function UI.cancel_fadeout(player_index)
    local slot = UI.fadeout[player_index]
    if not slot then return end
    slot.active = false
    slot.snapshot = nil
end

function UI.render_fadeout_window(player_index)
    local slot = UI.fadeout[player_index]
    if not slot or not slot.active or not slot.snapshot then return end
    local alpha = UI.fadeout_alpha_for_frame(UI.fadeout_global_frame)
    UI.fadeout_alpha_override = alpha
    UI.draw_combo_window_frame(player_index, slot.title, slot.x, slot.y, slot.anchor, slot.width, slot.minimal, slot.snapshot, slot.is_defense)
    UI.fadeout_alpha_override = nil
end

function UI.render_fadeouts()
    local any_active = false
    for i = 0, 1 do
        local slot = UI.fadeout[i]
        if slot and slot.active then
            if not slot.snapshot then
                slot.active = false
            else
                any_active = true
            end
        end
    end
    if not any_active then
        UI.fadeout_global_frame = 0
        return
    end
    -- All active panels share one global frame so P1/P2 fade in sync and end
    -- on the same frame. Once the shared clock expires, retire every panel.
    if UI.fadeout_global_frame >= UI.FADEOUT_FRAMES then
        for i = 0, 1 do
            if UI.fadeout[i] then
                UI.fadeout[i].active = false
                UI.fadeout[i].snapshot = nil
            end
            if UI.fadeout_snapshot[i] then
                UI.fadeout_snapshot[i].state = nil
                UI.fadeout_snapshot[i].snapshot_has_state = false
            end
        end
        UI.fadeout_global_frame = 0
        return
    end
    for i = 0, 1 do
        local slot = UI.fadeout[i]
        if slot and slot.active and slot.snapshot then
            UI.render_fadeout_window(i)
        end
    end
    UI.fadeout_global_frame = UI.fadeout_global_frame + 1
end

function UI.set_display_percent(setting_key, value, min_value, max_value)
    Config.settings[setting_key] = math.floor(Utils.clamp(value, min_value, max_value) + 0.5)
    UI.mark_for_save()
end

function UI.render_display_settings()
    if imgui.tree_node("Display") then
        if not Config.display_defaults_selected() then
            imgui.same_line()
            UI.confirm_button("display_defaults", "Defaults", "display_defaults", function()
                Config.settings.display_background_opacity = DEFAULT_BACKGROUND_OPACITY
                Config.settings.display_text_opacity = DEFAULT_TEXT_OPACITY
                Config.settings.display_scale = DEFAULT_DISPLAY_SCALE
                Config.settings.combo_timer_duration = DEFAULT_COMBO_TIMER_DURATION
                Config.settings.hide_builtin_attack_data_display = DEFAULT_HIDE_BUILTIN_ATTACK_DATA_DISPLAY
                UI.mark_for_save()
            end)
        elseif UI.confirm_active.display_defaults then
            UI.confirm_active.display_defaults = nil
        end

		imgui.text("Hide Built-In Attack Data")
        imgui.same_line()
        changed, Config.settings.hide_builtin_attack_data_display = imgui.checkbox("##hide_builtin_attack_data_display", Config.settings.hide_builtin_attack_data_display ~= false)
        if changed then
            ComboData.debug_log("SETTING_CHANGED hide_builtin_attack_data_display=" .. tostring(Config.settings.hide_builtin_attack_data_display), "log_settings_changed")
            UI.mark_for_save()
        end

        imgui.text("Scale")
        imgui.same_line()
        imgui.push_item_width(120)
        local changed, scale = imgui.slider_float("##display_scale", Config.settings.display_scale, 50, 150, "%.0f%%")
        imgui.pop_item_width()
        if changed then UI.set_display_percent("display_scale", scale, 50, 150) end

        imgui.text("Opacity (BG)")
        imgui.same_line()
        imgui.push_item_width(120)
        local opacity
        changed, opacity = imgui.slider_float("##display_background_opacity", Config.settings.display_background_opacity, 0, 100, "%.0f%%")
        imgui.pop_item_width()
        if changed then UI.set_display_percent("display_background_opacity", opacity, 0, 100) end

        imgui.text("Opacity (Text)")
        imgui.same_line()
        imgui.push_item_width(120)
        changed, opacity = imgui.slider_float("##display_text_opacity", Config.settings.display_text_opacity, 0, 100, "%.0f%%")
        imgui.pop_item_width()
        if changed then UI.set_display_percent("display_text_opacity", opacity, 0, 100) end

        imgui.text("Clear After")
        imgui.same_line()
        imgui.push_item_width(30)
        changed, Config.settings.combo_timer_duration = imgui.drag_int("##combo_timer_duration", Config.settings.combo_timer_duration, 1, 0, 120)
        imgui.pop_item_width()
        imgui.same_line()
        imgui.text("Seconds")
        if changed then
            ComboData.debug_log("SETTING_CHANGED combo_timer_duration=" .. tostring(Config.settings.combo_timer_duration), "log_settings_changed")
            UI.mark_for_save()
        end

        imgui.same_line()
        if imgui.button("Clear Now##display_clear_now") then
            ComboData.default_state()
            UI.action_notify("Data Cleared", "alert_on_toggle")
        end

        imgui.tree_pop()
    end
end
function UI.radio_button(label, selected)
    if imgui.radio_button then
        local ok, clicked = pcall(function() return imgui.radio_button(label, selected) end)
        if ok then return clicked end
    end

    local changed, checked = imgui.checkbox(label, selected)
    return changed and checked
end

function UI.set_unit_mode(unit_id, mode)
    if type(Config.settings.unit_display) ~= "table" then
        Config.settings.unit_display = {}
    end
    if Config.settings.unit_display[unit_id] ~= mode then
        Config.settings.unit_display[unit_id] = mode
        UI.mark_for_save()
    end
end

function UI.render_unit_settings()
    local units_open = imgui.tree_node("Units")
    if units_open then
        if not Config.unit_defaults_selected() then
            imgui.same_line()
            UI.confirm_button("unit_defaults", "Defaults", "unit_defaults", function()
                Config.reset_unit_defaults()
                UI.mark_for_save()
            end)
        elseif UI.confirm_active.unit_defaults then
            UI.confirm_active.unit_defaults = nil
        end

        if imgui.begin_table("attack_info_units", 3, 4096 | 8192, Vector2f.new(300, 0)) then
            imgui.table_setup_column("", 4096, 95)
            imgui.table_setup_column("Raw", 4096, 80)
            imgui.table_setup_column("Percent", 4096, 110)

            imgui.table_next_row()
            imgui.table_set_column_index(0)
            imgui.table_set_column_index(1)
            imgui.text("Raw")
            imgui.table_set_column_index(2)
            imgui.text("Percent")

            for _, unit in ipairs(UNIT_DEFS) do
                local mode = UI.get_unit_mode(unit.id)
                imgui.table_next_row()

                imgui.table_set_column_index(0)
                imgui.text(unit.label)

                imgui.table_set_column_index(1)
                if UI.radio_button("##unit_raw_" .. unit.id, mode == "raw") then
                    UI.set_unit_mode(unit.id, "raw")
                end

                imgui.table_set_column_index(2)
                if UI.radio_button("##unit_percent_" .. unit.id, mode == "percent") then
                    UI.set_unit_mode(unit.id, "percent")
                end
            end

            imgui.end_table()
        end

        imgui.separator()
        imgui.text("Reduce")
        UI.set_hover_tooltip("Ignore unused ones digit from Drive/Super values")
        imgui.same_line()
        local reduce_drive_changed
        reduce_drive_changed, Config.settings.reduce_drive = imgui.checkbox("Drive##reduce_drive", Config.settings.reduce_drive)
        if reduce_drive_changed then
            UI.mark_for_save()
        end
        imgui.same_line()
        local reduce_super_changed
        reduce_super_changed, Config.settings.reduce_super = imgui.checkbox("Super##reduce_super", Config.settings.reduce_super)
        if reduce_super_changed then
            UI.mark_for_save()
        end

        imgui.tree_pop()
    end
end

function UI.render_position_coord_inputs(def, defaults)
    local coords = Config.settings.position_coords[def.id]
    if type(coords) ~= "table" then return end
    local is_percent = Config.settings.position_mode == "percent"

    imgui.text(def.label)
    imgui.same_line()
    imgui.text("X")
    imgui.same_line()
    imgui.push_item_width(55)
    local raw_x = tonumber(coords.x) or (defaults and defaults[def.id] and defaults[def.id].x) or 0
    local x_display
    if is_percent then
        x_display = UI.format_percent_str(raw_x)
    else
        x_display = tostring(UI.percent_to_pixels(raw_x, "x"))
    end
    local x_changed, new_x_text = imgui.input_text("##position_" .. def.id .. "_x", x_display)
    imgui.pop_item_width()
    if x_changed then
        if is_percent then
            UI.set_position_coord(def.id, "x", new_x_text)
        else
            local pixel_val = tonumber(new_x_text)
            if pixel_val then
                UI.set_position_coord(def.id, "x", tostring(pixel_val / UI.get_screen_dim("x") * 100))
            end
        end
    end

    imgui.same_line()
    imgui.text("Y")
    imgui.same_line()
    imgui.push_item_width(55)
    local raw_y = tonumber(coords.y) or (defaults and defaults[def.id] and defaults[def.id].y) or 0
    local y_display
    if is_percent then
        y_display = UI.format_percent_str(raw_y)
    else
        y_display = tostring(UI.percent_to_pixels(raw_y, "y"))
    end
    local y_changed, new_y_text = imgui.input_text("##position_" .. def.id .. "_y", y_display)
    imgui.pop_item_width()
    if y_changed then
        if is_percent then
            UI.set_position_coord(def.id, "y", new_y_text)
        else
            local pixel_val = tonumber(new_y_text)
            if pixel_val then
                UI.set_position_coord(def.id, "y", tostring(pixel_val / UI.get_screen_dim("y") * 100))
            end
        end
    end
end

function UI.render_position_settings()
    if imgui.tree_node("Position") then
        local _, defaults = UI.ensure_position_coords()
        if not Config.position_defaults_selected(defaults) then
            imgui.same_line()
            UI.confirm_button("position_defaults", "Defaults", "position_defaults", function()
                Config.reset_position_defaults(defaults)
                UI.mark_for_save()
            end)
        elseif UI.confirm_active.position_defaults then
            UI.confirm_active.position_defaults = nil
        end

        local mirror_column_changed, mirror_column_order = imgui.checkbox("Mirror Column Order##mirror_column_order", Config.settings.toggle_mirror_column_order ~= false)
        if mirror_column_changed then
            Config.settings.toggle_mirror_column_order = mirror_column_order == true
            UI.action_notify("Mirror Column Order " .. (Config.settings.toggle_mirror_column_order and "Enabled" or "Disabled"), "alert_on_toggle")
            UI.mark_for_save()
        end

        local mirror_enabled = Config.settings.position_mirror_y_axis ~= false
        local mirror_changed, new_mirror_enabled = imgui.checkbox("Mirror Across Y Axis##position_mirror_y_axis", mirror_enabled)
        if mirror_changed then
            Config.settings.position_mirror_y_axis = new_mirror_enabled == true
            UI.mark_for_save()
        end

        local match_vertical_enabled = Config.settings.position_match_vertical ~= false
        local match_vertical_changed, new_match_vertical_enabled = imgui.checkbox("Match Vertical Position##position_match_vertical", match_vertical_enabled)
        if match_vertical_changed then
            Config.settings.position_match_vertical = new_match_vertical_enabled == true
            if Config.settings.position_match_vertical then
                UI.apply_match_vertical_position(defaults)
            end
            UI.mark_for_save()
        end

        local current_mode = Config.settings.position_mode == "percent" and "percent" or "pixels"
        local mode_changed = false
        imgui.text("Mode:")
        imgui.same_line()
        local is_percent_mode = current_mode == "percent"
        local pressed_percent = UI.radio_button("Percent##position_mode", is_percent_mode)
        if pressed_percent and not is_percent_mode then
            Config.settings.position_mode = "percent"
            mode_changed = true
        end
        imgui.same_line()
        local pressed_pixels = UI.radio_button("Pixels##position_mode", not is_percent_mode)
        if pressed_pixels and is_percent_mode then
            Config.settings.position_mode = "pixels"
            mode_changed = true
        end
        if mode_changed then
            UI.mark_for_save()
        end

        for _, def in ipairs(POSITION_DEFS) do
            UI.render_position_coord_inputs(def, defaults)
        end

        imgui.tree_pop()
    end
end
function UI.resolve_debug_DEBUG_PATH()
    local function resolve(level)
        local source = debug.getinfo(level, "S").source or ""
        if source:sub(1, 1) == "@" then
            source = source:sub(2)
        end
        source = source:gsub("\\", "/")
        local dir = source:match("^(.*/)") or ""
        local reframework_dir = dir:gsub("autorun/$", ""):gsub("data/$", "")
        return reframework_dir .. "data/attack_info_debug.log"
    end

    local DEBUG_PATH = resolve(1)
    if DEBUG_PATH:match("^[a-zA-Z]:") or DEBUG_PATH:sub(1, 1) == "/" then
        return DEBUG_PATH
    end
    return resolve(2)
end

function UI.clear_debug_log()
    pcall(function()
        local file = io.open("attack_info_debug.log", "w")
        if file then
            file:close()
        end
    end)
end

function UI.read_debug_log_tail(line_count)
    local ok, result = pcall(function()
        local file = io.open("attack_info_debug.log", "r")
        if not file then return "Log file not found" end
        local content = file:read("*a")
        file:close()
        local lines = {}
        for line in content:gmatch("[^\r\n]+") do
            table.insert(lines, line)
        end
        local start = math.max(1, #lines - line_count + 1)
        local tail = {}
        for i = start, #lines do
            table.insert(tail, lines[i])
        end
        return table.concat(tail, "\n")
    end)
    if ok then return result end
    return "Error reading log file"
end

function UI.render_debug_settings()
    if imgui.tree_node("Debug") then
        imgui.same_line()
        UI.confirm_button("clear_debug_log", "Clear Log", "clear_debug_log", function()
            UI.clear_debug_log()
            UI.action_notify("Debug log cleared", "alert_on_toggle")
        end)
        local changed
        changed, Config.settings.toggle_enable_debug_logging = imgui.checkbox("Enable Debug Logging##enable_debug_logging", Config.settings.toggle_enable_debug_logging)
        if changed then
            UI.mark_for_save()
        end

        if imgui.button("Copy Path##debug_DEBUG_PATH") then
            local DEBUG_PATH = UI.resolve_debug_DEBUG_PATH()
            sdk.copy_to_clipboard(DEBUG_PATH)
            UI.tooltip_msg = MOD_NAME .. ': Log path copied to clipboard'
            UI.tooltip_timer = 40
        end

        imgui.same_line()

        if imgui.button("Copy Log##debug_log_content") then
            local content = UI.read_debug_log_tail(1000)
            sdk.copy_to_clipboard(content)
            UI.tooltip_msg = MOD_NAME .. ': Debug log copied to clipboard'
            UI.tooltip_timer = 40
        end

        if imgui.tree_node("Log Options") then
            local logcats = {
                { key = "log_attacker_display", label = "Log Attacker Display" },
                { key = "log_defender_display", label = "Log Defender Display" },
                { key = "log_start_finish_values", label = "Log Start/Finish Values" },
                { key = "log_settings_changed", label = "Log Settings" },
                { key = "log_display_update", label = "Log Display Update" },
                { key = "log_display_clear", label = "Log Display Clear" },
                { key = "toggle_enable_drive_cooldown_debug", label = "Log Drive Cooldown" },
            }
            for _, lc in ipairs(logcats) do
                local lc_changed
                lc_changed, Config.settings[lc.key] = imgui.checkbox(lc.label .. "##" .. lc.key, Config.settings[lc.key] == true)
                if lc_changed then
                    UI.mark_for_save()
                end
            end
            imgui.tree_pop()
        end

        imgui.tree_pop()
    end
end

function UI.render_settings()
    if imgui.tree_node("Attack Info") then
        local changed = false
        if not Config.attack_info_defaults_selected() then
            imgui.same_line()
            UI.confirm_button("attack_info_defaults", "Defaults", "attack_info_defaults", function()
                Config.reset_attack_info_defaults()
                UI.mark_for_save()
            end)
        elseif UI.confirm_active.attack_info_defaults then
            UI.confirm_active.attack_info_defaults = nil
        end

        imgui.text("Enable (F2)")
        imgui.same_line()
        changed, Config.settings.toggle_all = imgui.checkbox("##enable", Config.settings.toggle_all)
        if changed then
            UI.action_notify("Display " .. (Config.settings.toggle_all and "Enabled" or "Disabled"), "alert_on_toggle")
            ComboData.debug_log("SETTING_CHANGED toggle_all=" .. tostring(Config.settings.toggle_all), "log_settings_changed")
            UI.mark_for_save()
        end

        -- DISABLED: Ignore Framekills — hidden until framekill/advantage
        -- engine behavior is better understood.
        --[[
        imgui.text("Ignore Framekills")
        imgui.same_line()
        local framekills_changed
        framekills_changed, Config.settings.toggle_ignore_framekills = imgui.checkbox("##ignore_framekills", Config.settings.toggle_ignore_framekills)
        if framekills_changed then
            UI.action_notify("Framekills " .. (Config.settings.toggle_ignore_framekills and "Ignored" or "Shown"), "alert_on_toggle")
            UI.mark_for_save()
        end
        --]]

        if Config.settings.toggle_all then
            imgui.text("Show/Hide")
            imgui.same_line()
            local changed_p1, changed_p2 = false, false
            changed_p1, Config.settings.toggle_p1 = imgui.checkbox("P1##show_p1", Config.settings.toggle_p1)
            imgui.same_line()
            changed_p2, Config.settings.toggle_p2 = imgui.checkbox("P2##show_p2", Config.settings.toggle_p2)

            if changed_p1 then
                UI.action_notify("P1 Window " .. (Config.settings.toggle_p1 and "Shown" or "Hidden"), "alert_on_toggle")
                UI.mark_for_save()
            end
            if changed_p2 then
                UI.action_notify("P2 Window " .. (Config.settings.toggle_p2 and "Shown" or "Hidden"), "alert_on_toggle")
                UI.mark_for_save()
            end

            imgui.text("Minimal View")
            imgui.same_line()
            local m_changed_p1, m_changed_p2 = false, false
            m_changed_p1, Config.settings.toggle_minimal_view_p1 = imgui.checkbox("P1##minimal_p1", Config.settings.toggle_minimal_view_p1)
            imgui.same_line()
            m_changed_p2, Config.settings.toggle_minimal_view_p2 = imgui.checkbox("P2##minimal_p2", Config.settings.toggle_minimal_view_p2)

            if m_changed_p1 then
                UI.action_notify("P1 Minimal View " .. (Config.settings.toggle_minimal_view_p1 and "Enabled" or "Disabled"), "alert_on_minimal")
                UI.mark_for_save()
            end
            if m_changed_p2 then
                UI.action_notify("P2 Minimal View " .. (Config.settings.toggle_minimal_view_p2 and "Enabled" or "Disabled"), "alert_on_minimal")
                UI.mark_for_save()
            end

            if imgui.tree_node("Updating") then
                if not Config.updating_defaults_selected() then
                    imgui.same_line()
                    UI.confirm_button("updating_defaults", "Defaults", "updating_defaults", function()
                        Config.reset_updating_defaults()
                        UI.mark_for_save()
                    end)
                elseif UI.confirm_active.updating_defaults then
                    UI.confirm_active.updating_defaults = nil
                end

                imgui.text("Update on Opponent Block")
                imgui.same_line()
                local blocked_changed
                blocked_changed, Config.settings.toggle_show_blocked_attacks = imgui.checkbox("##show_blocked_attacks", Config.settings.toggle_show_blocked_attacks)
                if blocked_changed then
                    UI.action_notify("Blocked Attacks " .. (Config.settings.toggle_show_blocked_attacks and "Enabled" or "Disabled"), "alert_on_toggle")
                    UI.mark_for_save()
                end

                if Config.settings.toggle_show_blocked_attacks then
                    imgui.text("Blockstring Leniency")
                    UI.set_hover_tooltip(BLOCKSTRING_TOOLTIP)
                    imgui.same_line()
                    imgui.push_item_width(25)
                    local string_gap_text = tostring(Config.get_string_gap())
                    local string_gap_changed, new_string_gap_text = imgui.input_text("##string_gap", string_gap_text)
                    imgui.pop_item_width()
                    if string_gap_changed then
                        local new_string_gap = math.max(0, math.floor(tonumber(new_string_gap_text) or DEFAULT_STRING_GAP))
                        if new_string_gap ~= Config.get_string_gap() then
                            Config.settings.string_gap = new_string_gap
                            ComboData.debug_log("SETTING_CHANGED string_gap=" .. tostring(new_string_gap), "log_settings_changed")
                            UI.mark_for_save()
                        end
                    end
                end

                imgui.text("Update on Damage Taken")
                imgui.same_line()
                local update_damage_changed
                update_damage_changed, Config.settings.toggle_update_on_damage = imgui.checkbox("##update_on_damage", Config.settings.toggle_update_on_damage)
                if update_damage_changed then
                    if Config.settings.toggle_update_on_damage then
                        Config.settings.toggle_clear_on_damage = false
                    end
                    ComboData.debug_log("SETTING_CHANGED toggle_update_on_damage=" .. tostring(Config.settings.toggle_update_on_damage), "log_settings_changed")
                    UI.mark_for_save()
                end

                imgui.text("Update on Block Taken")
                imgui.same_line()
                local update_block_changed
                update_block_changed, Config.settings.toggle_update_on_block = imgui.checkbox("##update_on_block", Config.settings.toggle_update_on_block)
                if update_block_changed then
                    if Config.settings.toggle_update_on_block then
                        Config.settings.toggle_clear_on_block = false
                    end
                    ComboData.debug_log("SETTING_CHANGED toggle_update_on_block=" .. tostring(Config.settings.toggle_update_on_block), "log_settings_changed")
                    UI.mark_for_save()
                end

                imgui.text("Clear on Damage Taken")
                imgui.same_line()
                local clear_damage_changed, clear_on_damage = imgui.checkbox("##clear_on_damage", Config.settings.toggle_clear_on_damage == true)
                if clear_damage_changed then
                    Config.settings.toggle_clear_on_damage = clear_on_damage == true
                    if Config.settings.toggle_clear_on_damage then
                        Config.settings.toggle_update_on_damage = false
                    end
                    ComboData.debug_log("SETTING_CHANGED toggle_clear_on_damage=" .. tostring(Config.settings.toggle_clear_on_damage), "log_settings_changed")
                    UI.mark_for_save()
                end

                imgui.text("Clear on Block Taken")
                imgui.same_line()
                local clear_block_changed, clear_on_block = imgui.checkbox("##clear_on_block", Config.settings.toggle_clear_on_block == true)
                if clear_block_changed then
                    Config.settings.toggle_clear_on_block = clear_on_block == true
                    if Config.settings.toggle_clear_on_block then
                        Config.settings.toggle_update_on_block = false
                    end
                    ComboData.debug_log("SETTING_CHANGED toggle_clear_on_block=" .. tostring(Config.settings.toggle_clear_on_block), "log_settings_changed")
                    UI.mark_for_save()
                end

                imgui.text("End on Recovery")
                imgui.same_line()
                local current_mode = Config.get_combo_end_mode()
                if UI.radio_button("Latest##end_mode", current_mode == "latest") then
                    Config.settings.combo_end_mode = "latest"
                    ComboData.debug_log("SETTING_CHANGED combo_end_mode=latest", "log_settings_changed")
                    UI.mark_for_save()
                end
                imgui.same_line()
                if UI.radio_button("Attacker##end_mode", current_mode == "attacker_recovery") then
                    Config.settings.combo_end_mode = "attacker_recovery"
                    ComboData.debug_log("SETTING_CHANGED combo_end_mode=attacker_recovery", "log_settings_changed")
                    UI.mark_for_save()
                end
                imgui.same_line()
                if UI.radio_button("Defender##end_mode", current_mode == "defender_recovery") then
                    Config.settings.combo_end_mode = "defender_recovery"
                    ComboData.debug_log("SETTING_CHANGED combo_end_mode=defender_recovery", "log_settings_changed")
                    UI.mark_for_save()
                end

                imgui.tree_pop()
            end

            UI.render_display_settings()
            UI.render_unit_settings()

            if imgui.tree_node("Columns") then
                if not Config.column_visibility_defaults_selected() then
                    imgui.same_line()
                    UI.confirm_button("column_visibility_defaults", "Defaults", "column_visibility_defaults", function()
                        Config.reset_column_visibility_defaults()
                        UI.mark_for_save()
                    end)
                elseif UI.confirm_active.column_visibility_defaults then
                    UI.confirm_active.column_visibility_defaults = nil
                end

                if imgui.begin_table("attack_info_column_visibility", 3, 4096 | 8192, Vector2f.new(260, 0)) then
                    imgui.table_setup_column("", 4096, 120)
                    imgui.table_setup_column("P1", 4096, 55)
                    imgui.table_setup_column("P2", 4096, 55)

                    imgui.table_next_row()
                    imgui.table_set_column_index(0)
                    imgui.table_set_column_index(1)
                    imgui.text("P1")
                    imgui.table_set_column_index(2)
                    imgui.text("P2")

                    for _, column in ipairs(COLUMN_DEFS) do
                        imgui.table_next_row()

                        imgui.table_set_column_index(0)
                        imgui.text(UI.get_visibility_column_label(column))

                        imgui.table_set_column_index(1)
                        local p1_changed, p1_visible = imgui.checkbox("##p1_col_" .. column.id, Config.settings.column_visibility_p1[column.id] ~= false)
                        if p1_changed then
                            Config.settings.column_visibility_p1[column.id] = p1_visible
                            UI.mark_for_save()
                        end

                        imgui.table_set_column_index(2)
                        local p2_changed, p2_visible = imgui.checkbox("##p2_col_" .. column.id, Config.settings.column_visibility_p2[column.id] ~= false)
                        if p2_changed then
                            Config.settings.column_visibility_p2[column.id] = p2_visible
                            UI.mark_for_save()
                        end
                    end

                    imgui.end_table()
                end
                imgui.tree_pop()
            end

            UI.render_position_settings()
            UI.render_debug_settings()
        end
        imgui.tree_pop()
    end
end

-------------------------
-- Main
-------------------------

Config.init()

re.on_draw_ui(function()
    UI.render_settings()
end)

re.on_frame(function()
    UI.fadeout_frame_counter = UI.fadeout_frame_counter + 1
    local sPlayer, cPlayer, cTeam = GameObjects.get_objects()
    local in_battle = GameObjects.is_in_battle(cPlayer)
    local round_no = in_battle and GameObjects.get_round_no() or nil
    UI.handle_hotkeys()
    UI.update_combo_timers()
    GameObjects.update_builtin_attack_data_display()
    UI.tooltip_handler()
    UI.save_handler()
    UI.draw_action_notify()
    ComboData.sync_gameplay_state(in_battle, round_no)

    -- Handle snapshot save/load hooks (processed on_frame for safety, per
    -- snapshot_manager.lua pattern). The hook flags are set in the pre-hook
    -- callbacks to avoid any managed object access during the hook.
    if ComboData.hook_save_fired then
        local save_payload = ComboData.hook_save_payload
        ComboData.snapshot_debug("on_frame_process_save payload_present=" .. tostring(save_payload ~= nil) .. " version=" .. ComboData.snapshot_payload_version(save_payload))
        ComboData.hook_save_fired = nil
        ComboData.hook_save_payload = nil
        ComboData.save_snapshot(nil, save_payload)
    end
    -- Debug log flush: write queued lines to disk once every 30 frames.
    -- When logging is unchecked, drain remaining queue immediately.
    local logging_enabled = Config.settings.toggle_enable_debug_logging == true
    if ComboData.runtime_state.debug_logging_was_enabled and not logging_enabled then
        ComboData.debug_log_flush()
    end
    ComboData.runtime_state.debug_logging_was_enabled = logging_enabled
    local skip = ComboData.runtime_state.debug_log_flush_skip_counter
    ComboData.runtime_state.debug_log_flush_skip_counter = skip + 1
    if ComboData.runtime_state.debug_log_flush_skip_counter >= 30 then
        ComboData.debug_log_flush()
        ComboData.runtime_state.debug_log_flush_skip_counter = 0
    end

    -- Use the combat visibility gate instead of prev_no_push_bit, which is 0
    -- in story-training and other modes even during active gameplay. The gate
    -- now requires a live action engine so retained postmatch objects do not
    -- render stale combat boxes.
    if in_battle then
        local p1, p2 = GameObjects.map_player_data(cPlayer, cTeam)

        if ComboData.hook_load_fired then
            ComboData.snapshot_debug("on_frame_process_load")
            ComboData.hook_load_fired = nil
            ComboData.load_snapshot(nil, p1, p2)
        end

        -- Capture previous frame drive gauge BEFORE update_state overwrites p1_prev/p2_prev.
        -- Used to classify cooldown at start: if gauge decreased when cooldown started,
        -- it's a legitimate spend; otherwise it's artificial (refill system).
        local prev_p1 = ComboData.p1_prev
        local prev_p2 = ComboData.p2_prev
        local prev_p1_drive = (ComboData.p1_prev and ComboData.p1_prev.drive_adjusted) or 0
        local prev_p2_drive = (ComboData.p2_prev and ComboData.p2_prev.drive_adjusted) or 0
        local prev_p1_cd = (ComboData.p1_prev and ComboData.p1_prev.drive_cooldown) or 0
        local prev_p2_cd = (ComboData.p2_prev and ComboData.p2_prev.drive_cooldown) or 0

        ComboData.update_state(p1, p2)
        ComboData.update_post_match_timer(p1, p2)

        -- Track drive cooldown peaks for circular timer display.
        -- Classify cooldown at start: legitimate (from Drive spend) or artificial (from refill).
        local p1_cd = (p1 and p1.drive_cooldown) or 0
        local p2_cd = (p2 and p2.drive_cooldown) or 0
        local p1_drive = (p1 and p1.drive_adjusted) or 0
        local p2_drive = (p2 and p2.drive_adjusted) or 0

        ComboData.update_drive_cooldown_pending(0, prev_p1, p1)
        ComboData.update_drive_cooldown_pending(1, prev_p2, p2)

        -- P1: classify cooldown at start
        if p1_cd > 0 then
            local p1_is_override, p1_override_note = ComboData.get_training_drive_refill_override_debug(prev_p1, p1)
            local p1_known_spend, p1_spend_note = ComboData.player_has_known_drive_spend(0, p1)
            local p1_legitimate = not p1_is_override
            local p1_drive_drop = prev_p1_drive > p1_drive + 1000
            if prev_p1_cd <= 0 then
                if (ComboData.drive_cooldown_total_peak[0] or 0) <= 0 then
                    ComboData.drive_cooldown_total_peak[0] = p1_cd
                    if prev_p1_cd < 0 then
                        ComboData.drive_cooldown_total_peak[0] = math.abs(prev_p1_cd) + p1_cd
                    end
                end
                ComboData.debug_log_drive_cooldown(
                    0,
                    "start",
                    prev_p1,
                    p1,
                    p1_legitimate,
                    "cooldown_started known_spend=" .. tostring(p1_spend_note)
                        .. " drive_drop=" .. tostring(p1_drive_drop)
                        .. " override=" .. tostring(p1_override_note)
                )
            elseif ComboData.drive_cooldown_legitimate[0] ~= p1_legitimate then
                ComboData.debug_log_drive_cooldown(0, "reclassified", prev_p1, p1, p1_legitimate, p1_override_note)
            elseif p1.training_drive_point_lock == true or (tonumber(p1.training_drive_runtime_timer) or 0) > 0 then
                ComboData.debug_log_drive_cooldown(0, "override_check", prev_p1, p1, p1_legitimate, p1_override_note)
            end
            if ComboData.drive_cooldown_total_peak[0] == nil or ComboData.drive_cooldown_total_peak[0] < p1_cd then
                ComboData.drive_cooldown_total_peak[0] = p1_cd
            end
            ComboData.drive_cooldown_legitimate[0] = p1_legitimate
        elseif p1_cd <= 0 then
            if prev_p1_cd > 0 or (prev_p1 and prev_p1.training_drive_point_lock == true) then
                ComboData.debug_log_drive_cooldown(0, "end", prev_p1, p1, ComboData.drive_cooldown_legitimate[0], "cooldown_cleared")
            end
            ComboData.drive_cooldown_legitimate[0] = nil
            ComboData.drive_cooldown_peak[0] = 0
            ComboData.drive_cooldown_total_peak[0] = 0
            ComboData.drive_cooldown_pending_peak_final[0] = 0
        end

        -- P2: classify cooldown at start
        if p2_cd > 0 then
            local p2_is_override, p2_override_note = ComboData.get_training_drive_refill_override_debug(prev_p2, p2)
            local p2_known_spend, p2_spend_note = ComboData.player_has_known_drive_spend(1, p2)
            local p2_legitimate = not p2_is_override
            local p2_drive_drop = prev_p2_drive > p2_drive + 1000
            if prev_p2_cd <= 0 then
                if (ComboData.drive_cooldown_total_peak[1] or 0) <= 0 then
                    ComboData.drive_cooldown_total_peak[1] = p2_cd
                    if prev_p2_cd < 0 then
                        ComboData.drive_cooldown_total_peak[1] = math.abs(prev_p2_cd) + p2_cd
                    end
                end
                ComboData.debug_log_drive_cooldown(
                    1,
                    "start",
                    prev_p2,
                    p2,
                    p2_legitimate,
                    "cooldown_started known_spend=" .. tostring(p2_spend_note)
                        .. " drive_drop=" .. tostring(p2_drive_drop)
                        .. " override=" .. tostring(p2_override_note)
                )
            elseif ComboData.drive_cooldown_legitimate[1] ~= p2_legitimate then
                ComboData.debug_log_drive_cooldown(1, "reclassified", prev_p2, p2, p2_legitimate, p2_override_note)
            elseif p2.training_drive_point_lock == true or (tonumber(p2.training_drive_runtime_timer) or 0) > 0 then
                ComboData.debug_log_drive_cooldown(1, "override_check", prev_p2, p2, p2_legitimate, p2_override_note)
            end
            if ComboData.drive_cooldown_total_peak[1] == nil or ComboData.drive_cooldown_total_peak[1] < p2_cd then
                ComboData.drive_cooldown_total_peak[1] = p2_cd
            end
            ComboData.drive_cooldown_legitimate[1] = p2_legitimate
        elseif p2_cd <= 0 then
            if prev_p2_cd > 0 or (prev_p2 and prev_p2.training_drive_point_lock == true) then
                ComboData.debug_log_drive_cooldown(1, "end", prev_p2, p2, ComboData.drive_cooldown_legitimate[1], "cooldown_cleared")
            end
            ComboData.drive_cooldown_legitimate[1] = nil
            ComboData.drive_cooldown_peak[1] = 0
            ComboData.drive_cooldown_total_peak[1] = 0
            ComboData.drive_cooldown_pending_peak_final[1] = 0
        end

        -- Track peak only for legitimate cooldown
        if p1_cd > 0 and ComboData.drive_cooldown_legitimate[0] == true then
            if p1_cd > ComboData.drive_cooldown_peak[0] then
                ComboData.drive_cooldown_peak[0] = p1_cd
            end
        end

        if p2_cd > 0 and ComboData.drive_cooldown_legitimate[1] == true then
            if p2_cd > ComboData.drive_cooldown_peak[1] then
                ComboData.drive_cooldown_peak[1] = p2_cd
            end
        end
        UI.render_windows()
    end

    UI.render_fadeouts()

    if ComboData.hook_load_fired then
        ComboData.snapshot_debug("on_frame_process_load")
        ComboData.hook_load_fired = nil
        ComboData.load_snapshot()
    end
end)
