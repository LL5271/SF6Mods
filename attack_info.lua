local MOD_NAME = "Attack Info"
local CONFIG_PATH = "attack_info.json"
local SAVE_DELAY = 0.5
local LEFT_CLICK = 0x01
local RIGHT_CLICK = 0x02
local F2_KEY = 0x71
local CTRL_KEY = 0x11
local KEY_4, KEY_5 = 0x34, 0x35

local Config, Utils, GameObjects, ComboData, UI = {}, {}, {}, {}, {}
local ADVANTAGE_SETTLE_FRAMES = 30
local CARRY_POSITION_MAX = 765
local DEFAULT_STRING_GAP = 2
local DEFAULT_IGNORE_FRAMEKILLS = true
local BLOCKSTRING_TOOLTIP = "Maximum number of non-blocking frames before a blockstring is considered complete."
local DEFAULT_BACKGROUND_OPACITY = 60
local DEFAULT_TEXT_OPACITY = 100
local DEFAULT_DISPLAY_SCALE = 100
local DEFAULT_COMBO_TIMER_DURATION = 30
local DEFAULT_CLEAR_ON_DAMAGE = true
local DEFAULT_CLEAR_ON_BLOCK = false
local DEFAULT_POSITION_OFFSET = 73
local DEFAULT_POSITION_Y = 0
local DEFAULT_UNIT_MODE = "raw"
local DEFAULT_UNIT_MODES = {
    damage = "raw",
    drive = "percent",
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
    { id = "gap",    label = "Gap" },
}
local COLUMN_DEFS = {
    { id = "hit_damage", label = "Damage", width = 76, default_visible = true },
    { id = "damage",   label = "Damage",   width = 76, unit_id = "damage", percent_max = 10000, color_max = 10000 },
    { id = "p1_drive", label = "P1 Drive", width = 92, unit_id = "drive",  percent_max = 60000, color_max = 60000 },
    { id = "p1_super", label = "P1 Super", width = 88, unit_id = "super",  percent_max = 30000, color_max = 30000 },
    { id = "p2_drive", label = "P2 Drive", width = 92, unit_id = "drive",  percent_max = 60000, color_max = 60000 },
    { id = "p2_super", label = "P2 Super", width = 88, unit_id = "super",  percent_max = 30000, color_max = 30000, default_visible = false },
    { id = "p2_carry", label = "P2 Carry", width = 54, percent_width = 58, unit_id = "carry", percent_max = 1530, color_max = 1530, default_visible = false },
    { id = "p1_carry", label = "P1 Carry", width = 54, percent_width = 58, unit_id = "carry", percent_max = 1530, color_max = 1530, default_visible = true },
    { id = "gap",      label = "Gap",      width = 48, percent_width = 54, unit_id = "gap",   percent_max = 490,  color_max = 490 },
    { id = "adv",      label = "Adv",      width = 42, color_max = 80 },
}
local POSITION_DEFS = {
    { id = "self", label = "Coords (Self)" },
    { id = "opponent", label = "Coords (Opponent)" },
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
    hide_all_alerts = false,
    alert_on_toggle = true,
    alert_on_minimal = true,
    display_background_opacity = DEFAULT_BACKGROUND_OPACITY,
    display_text_opacity = DEFAULT_TEXT_OPACITY,
    display_scale = DEFAULT_DISPLAY_SCALE,
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
}

function Config.loaded_settings_missing_defaults(loaded_settings)
    if loaded_settings.toggle_mirror_column_order == nil then
        return true
    end

    if loaded_settings.display_background_opacity == nil or loaded_settings.display_text_opacity == nil or loaded_settings.display_scale == nil then
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
        changed = true
    end

    for _, def in ipairs(POSITION_DEFS) do
        if type(Config.settings.position_coords[def.id]) ~= "table" then
            Config.settings.position_coords[def.id] = { x = nil, y = nil }
            changed = true
        end
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
    changed = Config.ensure_position_settings() or changed
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
end

function Config.reset_attack_info_defaults()
    Config.settings.toggle_all = true
    Config.settings.toggle_p1 = true
    Config.settings.toggle_p2 = true
    Config.settings.toggle_show_blocked_attacks = true
    Config.settings.toggle_ignore_framekills = DEFAULT_IGNORE_FRAMEKILLS
    Config.settings.string_gap = DEFAULT_STRING_GAP
    Config.settings.toggle_minimal_view_p1 = true
    Config.settings.toggle_minimal_view_p2 = true
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

    return true
end

function Config.attack_info_defaults_selected()
    return Config.settings.toggle_all == true
        and Config.settings.toggle_p1 == true
        and Config.settings.toggle_p2 == true
        and Config.settings.toggle_show_blocked_attacks == true
        and Config.settings.toggle_ignore_framekills == DEFAULT_IGNORE_FRAMEKILLS
        and (tonumber(Config.settings.string_gap) or DEFAULT_STRING_GAP) == DEFAULT_STRING_GAP
        and Config.settings.toggle_minimal_view_p1 == true
        and Config.settings.toggle_minimal_view_p2 == true
end
function Config.display_defaults_selected()
    return (tonumber(Config.settings.display_background_opacity) or DEFAULT_BACKGROUND_OPACITY) == DEFAULT_BACKGROUND_OPACITY
        and (tonumber(Config.settings.display_text_opacity) or DEFAULT_TEXT_OPACITY) == DEFAULT_TEXT_OPACITY
        and (tonumber(Config.settings.display_scale) or DEFAULT_DISPLAY_SCALE) == DEFAULT_DISPLAY_SCALE
        and (tonumber(Config.settings.combo_timer_duration) or DEFAULT_COMBO_TIMER_DURATION) == DEFAULT_COMBO_TIMER_DURATION
        and Config.settings.toggle_clear_on_damage == DEFAULT_CLEAR_ON_DAMAGE
        and Config.settings.toggle_clear_on_block == DEFAULT_CLEAR_ON_BLOCK
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

    for _, def in ipairs(POSITION_DEFS) do
        local coords = Config.settings.position_coords[def.id]
        local default_coords = defaults[def.id]
        if type(coords) ~= "table" or type(default_coords) ~= "table" then
            return false
        end
        if math.floor((tonumber(coords.x) or 0) + 0.5) ~= default_coords.x then
            return false
        end
        if math.floor((tonumber(coords.y) or 0) + 0.5) ~= default_coords.y then
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
            function() ComboData.default_state() end)
        Utils.setup_hook("app.BattleManager", "BattleStart", nil,
            function() ComboData.default_state() end)
        ComboData.default_state()
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

function Utils.setup_hook(type_name, method_name, pre_func, post_func)
    local type_def = sdk.find_type_definition(type_name)
    if type_def then
        local method = type_def:get_method(method_name)
        if method then sdk.hook(method, pre_func, post_func) end
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

-- Game modes where pause_type_bit == 0 means "unpaused" rather than
-- the usual set of non-zero sentinel values used in normal modes.
local ZERO_UNPAUSED_MODES = { [10] = true, [13] = true }

-- pause_type_bit values that mean "not paused" in normal modes.
local UNPAUSED_BITS = { [2] = true, [64] = true, [256] = true, [2112] = true }

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

function GameObjects.get_round_no()
    local battle_round = GameObjects.RoundField and GameObjects.RoundField:get_data() or nil
    if not battle_round then return nil end
    return battle_round.RoundNo
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
        -- if not player then
        --     data_vals[player_index] = { hp_current = 0, hp_max = 0, combo_count = 0, incapacitated = false }
        -- else
        local team = cTeam and cTeam[player_index] or nil
        local data = {}
        data.hp_current = player.vital_new or 0
        data.hp_max = player.vital_max or 0
        data.dir = Utils.bitand(player.BitValue or 0, 128) == 128
        data.incapacitated = player.incapacitated or false
        data.drive_adjusted = data.incapacitated and ((player.focus_new or 0) - 60000) or (player.focus_new or 0)
        data.drive_cooldown = player.focus_wait or 0
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
        if player.combo_scale then
            data.combo_scale_now = tonumber(player.combo_scale.now) or 100
        end
        data.down_count = team and team.mDownCount or 0
        data.pos_x = player.pos and (player.pos.x.v / 65536.0) or 0
        data.gap = (player.vs_distance and player.vs_distance.v or 0) / 65536.0
        data.action_id = 0
        data.action_frame = 0
        if player.mpActParam and player.mpActParam.ActionPart then
            local engine = player.mpActParam.ActionPart._Engine
            if engine then
                data.action_id = Utils.read_sfix(engine:get_ActionID())
                data.action_frame = Utils.read_sfix(engine:get_ActionFrame())
            end
        end
        data.advantage = 0
        if GameObjects.TrainingManager and GameObjects.TrainingManager._tCommon then
            local snap = GameObjects.TrainingManager._tCommon.SnapShotDatas
            if snap and snap[0] then
                local meter = snap[0]._DisplayData.FrameMeterSSData.MeterDatas
                if meter and meter[player_index] then
                    data.advantage = Utils.parse_frame_value(meter[player_index].StunFrame)
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
    -- Modes 10 (STORY_TRAINING) and 13 (STORY_SPECTATE) use bit=0 as their
    -- "not paused" sentinel; any non-zero value means the pause menu is open.
    if ZERO_UNPAUSED_MODES[mode] then
        return pause_type_bit ~= 0
    end
    -- All other modes: a known set of non-zero bits signals "not paused".
    return not UNPAUSED_BITS[pause_type_bit]
end

-------------------------
-- ComboData Logic
-------------------------

function ComboData.default_state()
    ComboData.player_states = {
        [0] = { started = false, finished = false, attacker = 0, is_blocked = false, ended_in_knockdown = false, start = {}, finish = {}, prev_finish = nil, pending_start = nil, pending_start_hp_lock = nil, timer_remaining = nil, advantage_settle_remaining = 0, block_end_grace_remaining = 0, advantage_lock = nil, hit_damage_lock = nil, hit_damage_lock_frozen = false, combo_damage_lock = nil, start_hp_lock = nil, knockdown_drive_settle = false, clear_start_advantage = false },
        [1] = { started = false, finished = false, attacker = 1, is_blocked = false, ended_in_knockdown = false, start = {}, finish = {}, prev_finish = nil, pending_start = nil, pending_start_hp_lock = nil, timer_remaining = nil, advantage_settle_remaining = 0, block_end_grace_remaining = 0, advantage_lock = nil, hit_damage_lock = nil, hit_damage_lock_frozen = false, combo_damage_lock = nil, start_hp_lock = nil, knockdown_drive_settle = false, clear_start_advantage = false },
    }
    ComboData.p1_prev, ComboData.p2_prev = {}, {}
    ComboData.resource_baselines = { [0] = nil, [1] = nil }
end

ComboData.runtime_state = {
    was_in_battle = false,
    last_round_no = nil,
}

function ComboData.sync_gameplay_state(in_battle, round_no)
    local runtime_state = ComboData.runtime_state

    if runtime_state.was_in_battle ~= in_battle then
        ComboData.default_state()
    elseif in_battle and runtime_state.last_round_no ~= nil and round_no ~= nil and round_no ~= runtime_state.last_round_no then
        -- Clear retained rows at the round boundary before the next round starts.
        ComboData.default_state()
    end

    runtime_state.was_in_battle = in_battle
    runtime_state.last_round_no = in_battle and round_no or nil
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

    if (atk.combo_count or 0) > 0 then
        return "hit"
    end

    if Config.settings.toggle_show_blocked_attacks and
        (ComboData.is_block_snapshot_active(def) or ComboData.did_guard_count_advance(def, def_prev)) then
        return "block"
    end

    return nil
end

function ComboData.update_block_end_grace(state, def)
    local string_gap = Config.get_string_gap()
    if ComboData.is_block_snapshot_active(def) then
        state.block_end_grace_remaining = string_gap
        return false
    end

    if (state.block_end_grace_remaining or 0) > 0 then
        state.block_end_grace_remaining = state.block_end_grace_remaining - 1
        return false
    end

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

function ComboData.update_hit_advantage_lock(state, attacker_key, current_finish)
    if not state or state.is_blocked or not Config.settings.toggle_ignore_framekills then
        return
    end

    local latest = current_finish and current_finish[attacker_key]
    if not latest then return end

    if state.advantage_lock == nil then
        local latest_advantage = latest.advantage or 0
        if latest_advantage ~= 0 then
            state.advantage_lock = latest_advantage
        end
    end

    if state.advantage_lock ~= nil then
        latest.advantage = state.advantage_lock
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
        state.combo_damage_lock,
        atk and atk.combo_damage,
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


function ComboData.freeze_drive_finish(current_finish, latest)
    if not current_finish or not latest then return end

    current_finish.drive_adjusted = latest.drive_adjusted
    current_finish.incapacitated = latest.incapacitated
end

function ComboData.knockdown_drive_settle_complete(def)
    if not def then return true end

    if (def.drive_cooldown or 0) ~= 0 then
        return false
    end

    if (def.action_frame or 0) ~= 0 then
        return false
    end

    return true
end

function ComboData.settle_finished_advantage(state, p1, p2)
    if not state.finished or not state.advantage_settle_remaining or state.advantage_settle_remaining <= 0 then
        return
    end

    ComboData.update_advantage_if_larger(state.finish.p1, p1)
    ComboData.update_advantage_if_larger(state.finish.p2, p2)
    state.advantage_settle_remaining = state.advantage_settle_remaining - 1
end

function ComboData.update_resource_baselines(p1, p2)
    for i = 0, 1 do
        local current = (i == 0 and p1 or p2)
        local prev = (i == 0 and ComboData.p1_prev or ComboData.p2_prev)
        if current then
            if not ComboData.resource_baselines[i] then
                ComboData.resource_baselines[i] = Utils.deep_copy(current)
                ComboData.resource_baselines[i].baseline_action_id = current.action_id
            end

            if prev then
                local action_changed = current.action_id ~= prev.action_id
                local action_wrapped = current.action_id == prev.action_id and (current.action_frame or 0) < (prev.action_frame or 0)
                if action_changed or action_wrapped then
                    ComboData.resource_baselines[i] = Utils.deep_copy(prev)
                    ComboData.resource_baselines[i].baseline_action_id = current.action_id
                end
            end
        end
    end
end

function ComboData.apply_start_resource_baseline(state, attacker_idx, attacker)
    local key = attacker_idx == 0 and "p1" or "p2"
    local start_player = state.start[key]
    if not start_player or not attacker then return end

    local baseline = ComboData.resource_baselines and ComboData.resource_baselines[attacker_idx] or nil
    if baseline and baseline.baseline_action_id == attacker.action_id then
        if baseline.drive_adjusted ~= nil then start_player.drive_adjusted = baseline.drive_adjusted end
        if baseline.incapacitated ~= nil then start_player.incapacitated = baseline.incapacitated end
        if baseline.super ~= nil then start_player.super = baseline.super end
        return
    end

    -- Fallback for resource spends already reflected before combo count starts.
    -- These thresholds mirror the existing attack-history cooldown correction.
    if (attacker.drive_cooldown or 0) > 200 then
        start_player.drive_adjusted = (start_player.drive_adjusted or 0) + 10000
    elseif (attacker.drive_cooldown or 0) <= -120 then
        start_player.drive_adjusted = (start_player.drive_adjusted or 0) + 20000
    end
end

function ComboData.clear_finished_display_box(player_index, reason)
    local state = ComboData.player_states and ComboData.player_states[player_index]
    if not state then return false end

    -- Only clear stale/retained boxes. If this player currently has their own
    -- active combo/blockstring, leave that box alone.
    if state.started == true then return false end
    if state.finished ~= true then return false end

    state.finished = false
    state.timer_remaining = nil
    state.knockdown_drive_settle = false
    state.advantage_settle_remaining = 0
    state.block_end_grace_remaining = 0
    state.clear_hidden_reason = reason or "incoming_attack"
    return true
end

function ComboData.clear_defender_display_box_for_incoming_attack(attacker_index, attack_kind)
    if Config.settings.toggle_clear_on_damage ~= true then return false end
    if attack_kind ~= "hit" and attack_kind ~= "block" then return false end
    if attack_kind == "block" and Config.settings.toggle_clear_on_block ~= true then return false end

    local defender_index = attacker_index == 0 and 1 or 0
    return ComboData.clear_finished_display_box(defender_index, attack_kind == "block" and "block" or "damage")
end

function ComboData.update_state(p1, p2)
    ComboData.update_resource_baselines(p1, p2)

    for i = 0, 1 do
        local state = ComboData.player_states[i]
        local atk, def = (i == 0 and p1 or p2), (i == 0 and p2 or p1)
        local def_prev = (i == 0 and ComboData.p2_prev or ComboData.p1_prev)
        local attack_kind = ComboData.get_active_attack_kind(atk, def, def_prev)
        ComboData.clear_defender_display_box_for_incoming_attack(i, attack_kind)
        local current_hit_damage = math.max(
            tonumber(atk and atk.current_hit_damage) or 0,
            tonumber(def and def.current_hit_damage) or 0,
            tonumber(def_prev and def_prev.current_hit_damage) or 0
        )

        if not state.started and def_prev.hp_current and (attack_kind or current_hit_damage > 0) then
            state.pending_start = { p1 = Utils.deep_copy(ComboData.p1_prev), p2 = Utils.deep_copy(ComboData.p2_prev) }
            local pending_defender = i == 0 and state.pending_start.p2 or state.pending_start.p1
            state.pending_start_hp_lock = (pending_defender and pending_defender.hp_current) or 0
        end

        if not attack_kind then
            ComboData.settle_finished_advantage(state, p1, p2)
        end

        if not state.started and attack_kind and def_prev.hp_current then
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
            state.is_blocked = attack_kind == "block"
            state.ended_in_knockdown = false
            state.knockdown_drive_settle = false
            state.block_end_grace_remaining = state.is_blocked and Config.get_string_gap() or 0
            state.advantage_settle_remaining = 0
            state.advantage_lock = nil
            state.hit_damage_lock = nil
            state.hit_damage_lock_frozen = false
            state.hit_damage_lock_provisional = false
            state.hit_damage_lock_combo_damage_total = nil
            state.pending_ko_hit_damage_delta = nil
            state.combo_damage_lock = nil
            state.start_hp_lock = nil
            state.ko_start_hp_locked = false
            state.ko_start_snapshot = nil
            state.ko_start_snapshot_locked = false
            state.clear_start_advantage = true
            state.prev_finish = nil
            state.start = pending_start or { p1 = Utils.deep_copy(ComboData.p1_prev), p2 = Utils.deep_copy(ComboData.p2_prev) }
            local start_defender = i == 0 and state.start.p2 or state.start.p1
            state.start_hp_lock = (pending_start_hp_lock ~= nil and pending_start_hp_lock) or ((start_defender and start_defender.hp_current) or 0)
            state.pending_start = nil
            state.pending_start_hp_lock = nil
            ComboData.apply_start_resource_baseline(state, i, atk)
            if (atk.drive_cooldown or 0) > 200 then
                -- Drive Impact opener frames can land one frame before the
                -- defender's drive snapshot settles, so restore the opponent
                -- baseline too when the attacking side has already spent drive.
                ComboData.apply_start_resource_baseline(state, i == 0 and 1 or 0, def)
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
            local previous_finish = state.finish
            local current_finish = { p1 = Utils.deep_copy(p1), p2 = Utils.deep_copy(p2) }
            local attacker_key = i == 0 and "p1" or "p2"
            local start_def = (i == 0 and state.start.p2 or state.start.p1) or {}
            local ended_in_knockdown = def and (def.down_count or 0) ~= (start_def.down_count or 0)
            local combo_ended = false
            if state.is_blocked then
                combo_ended = ComboData.update_block_end_grace(state, def)
            else
                combo_ended = atk and (atk.combo_count or 0) == 0
            end
            local round_ended = def and def_prev and def.death_count ~= def_prev.death_count
            local ko_pending = not state.is_blocked and ComboData.is_pending_ko(atk, def, def_prev)
            if ko_pending then
                ComboData.lock_ko_start_snapshot(state)
                ComboData.ensure_start_hp_lock(state, i, def, def_prev, atk, true)
            end

            -- Knockdowns keep Drive changing through wake-up, so only freeze on
            -- non-knockdown finishes. The settle pass below handles recovery.
            if (round_ended or ko_pending or (combo_ended and not ended_in_knockdown)) and previous_finish and previous_finish.p1 and previous_finish.p2 then
                ComboData.freeze_drive_finish(current_finish.p1, previous_finish.p1)
                ComboData.freeze_drive_finish(current_finish.p2, previous_finish.p2)
            end

            ComboData.clear_sequence_start_advantage(state, attacker_key, current_finish)

            if not state.is_blocked then
                ComboData.update_hit_advantage_lock(state, attacker_key, current_finish)
            end

            ComboData.update_hit_damage_lock(state, attacker_key, current_finish, combo_ended, round_ended, ko_pending)
            ComboData.update_combo_damage_lock(state, attacker_key, current_finish)

            state.prev_finish = previous_finish
            state.finish = current_finish

            if combo_ended or round_ended then
                state.finished, state.started = true, false
                state.ended_in_knockdown = ended_in_knockdown == true
                state.knockdown_drive_settle = ended_in_knockdown == true and not round_ended
                state.advantage_settle_remaining = round_ended and 0 or ADVANTAGE_SETTLE_FRAMES
                if Config.settings.combo_timer_duration > 0 then
                    state.timer_remaining = Config.settings.combo_timer_duration
                end
            end
        end

        if state.finished and state.knockdown_drive_settle then
            local current_finish = { p1 = Utils.deep_copy(p1), p2 = Utils.deep_copy(p2) }
            state.prev_finish = state.finish
            state.finish = current_finish
            if ComboData.knockdown_drive_settle_complete(def) then
                state.knockdown_drive_settle = false
            end
        end
    end
    ComboData.p1_prev, ComboData.p2_prev = p1, p2
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
    return Utils.clamp(opacity, 0, 100) / 100
end

function UI.get_display_text_opacity()
    local opacity = tonumber(Config.settings.display_text_opacity) or DEFAULT_TEXT_OPACITY
    return Utils.clamp(opacity, 0, 100) / 100
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

function UI.format_carry_percent_value(v, percent_max, carry_percent_mode)
    if not percent_max or percent_max == 0 then return UI.format_raw_value(v) end
    if v == nil then return "-" end

    local percent = (v / percent_max) * 100
    if carry_percent_mode == "position" then
        percent = Utils.clamp((v / CARRY_POSITION_MAX) * 100, -100, 100)
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

function UI.format_column_value(v, column, percent_max, carry_percent_mode)
    if column and column.id == "hit_damage" then
        if v == nil or v == 0 then return "-" end
        return UI.format_raw_value(v)
    end

    if column and column.unit_id and UI.get_unit_mode(column.unit_id) == "percent" then
        if column.unit_id == "carry" then
            return UI.format_carry_percent_value(v, percent_max or column.percent_max, carry_percent_mode)
        end
        return UI.format_percent_value(v, percent_max or column.percent_max)
    end
    return UI.format_raw_value(v)
end

function UI.format_carry_display_value(v, column, percent_max, carry_percent_mode)
    if v == nil then
        return "-"
    end

    if v == 0 then
        return "-"
    end

    return UI.format_column_value(v, column, percent_max, carry_percent_mode)
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
        1530, 1530,
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
    return ComboData.get_hit_damage_snapshot(state, is_p1 and "p1" or "p2", state.finish, prefer_current_hit_damage)
end

function UI.get_combo_damage_value(state, is_p1)
    if state.is_blocked then
        local start_defender = is_p1 and state.start.p2 or state.start.p1
        local finish_defender = is_p1 and state.finish.p2 or state.finish.p1
        local damage = (start_defender and start_defender.hp_current or 0) - (finish_defender and finish_defender.hp_current or 0)
        return math.max(0, damage)
    end

    if state and state.combo_damage_lock ~= nil and (state.hit_damage_lock_frozen or (state.finished and not state.started)) then
        return state.combo_damage_lock
    end

    return (is_p1 and state.finish.p1.combo_damage or state.finish.p2.combo_damage) or 0
end

function UI.get_carry_total_value(start_player, finish_player, attacker_start, attacker_finish, percent_max)
    local start_pos = start_player and start_player.pos_x or 0
    local finish_pos = finish_player and finish_player.pos_x or 0
    start_pos = tonumber(start_pos) or 0
    finish_pos = tonumber(finish_pos) or 0

    if attacker_start and attacker_finish
        and attacker_start.dir ~= nil
        and attacker_finish.dir ~= nil
        and attacker_start.dir ~= attacker_finish.dir
    then
        -- Side-switch totals are not simple screen-space deltas. Compare the
        -- amount of space between the player endpoint and the wall the attacker
        -- is facing at combo start versus combo end:
        --   total = start-facing-wall-space - finish-facing-wall-space
        --
        -- This makes back-to-wall side switches large positive values, corner
        -- give-up side switches large negative values, and midscreen switches
        -- comparatively small.
        local _ = percent_max
        local max_pos = math.max(1, tonumber(CARRY_POSITION_MAX) or 765)

        local function space_to_facing_wall(pos, facing_right)
            local clamped_pos = Utils.clamp(tonumber(pos) or 0, -max_pos, max_pos)
            if facing_right then
                return max_pos - clamped_pos
            end
            return clamped_pos + max_pos
        end

        local start_space = space_to_facing_wall(start_pos, attacker_start.dir == true)
        local finish_space = space_to_facing_wall(finish_pos, attacker_finish.dir == true)
        return start_space - finish_space
    end

    local direction_sign = attacker_start and attacker_start.dir and 1 or -1
    return (finish_pos - start_pos) * direction_sign
end

-- BEGIN side-switch Carry total sign rule
function UI.apply_side_switch_carry_total_sign_rule(p1_carry_total, p2_carry_total, is_p1_attacker, attacker_start, attacker_finish)
    -- Side-switch sign is now part of UI.get_carry_total_value's wall-space
    -- delta. Keep this function as a no-op compatibility shim for the existing
    -- total-row call site.
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

function UI.get_combo_value_rows(state)
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
    if state and not start_hp_locked_after_ko and state.finished and not state.started and state.combo_damage_lock ~= nil then
        start_defender_hp = math.max(tonumber(start_defender_hp) or 0, state.combo_damage_lock)
    end
    local hit_damage_start, hit_damage_finish, hit_damage_total = UI.get_hit_damage_breakdown(state, is_p1)
    local hit_damage_scaling = hit_damage_finish
    local p1_carry_total = UI.get_carry_total_value(start_p1, state.finish.p1, attacker_start, attacker_finish, percent_max_values[7])
    local p2_carry_total = UI.get_carry_total_value(start_p2, state.finish.p2, attacker_start, attacker_finish, percent_max_values[8])
    p1_carry_total, p2_carry_total = UI.apply_side_switch_carry_total_sign_rule(
        p1_carry_total, p2_carry_total, is_p1, attacker_start, attacker_finish
    )

    if not ((is_p1 and Config.settings.toggle_minimal_view_p1) or (not is_p1 and Config.settings.toggle_minimal_view_p2)) then
        table.insert(rows, {
            font_size = UI.get_scaled_font_size(UI.medium_font),
            is_color = false,
            percent_max = percent_max_values,
            carry_percent_mode = "position",
            carry_direction_arrows = UI.get_carry_facing_arrows(start_p1, start_p2),
            blank_columns = { adv = true },
            cell_scaling = { hit_damage = hit_damage_scaling },
            values = {
                hit_damage_start,
                start_defender_hp,
                start_p1.drive_adjusted or 0, start_p1.super or 0,
                start_p2.drive_adjusted or 0, start_p2.super or 0,
                start_p1.pos_x or 0, start_p2.pos_x or 0, UI.get_gap_value(start_p1.gap), 0
            }
        })
        table.insert(rows, {
            font_size = UI.get_scaled_font_size(UI.medium_font),
            is_color = false,
            percent_max = percent_max_values,
            carry_percent_mode = "position",
            carry_direction_arrows = UI.get_carry_facing_arrows(state.finish.p1, state.finish.p2),
            blank_columns = { adv = true },
            display_modes = { hit_damage = "percent" },
            cell_scaling = { hit_damage = hit_damage_scaling },
            values = {
                hit_damage_finish,
                (is_p1 and state.finish.p2.hp_current or state.finish.p1.hp_current) or 0,
                state.finish.p1.drive_adjusted or 0, state.finish.p1.super or 0,
                state.finish.p2.drive_adjusted or 0, state.finish.p2.super or 0,
                state.finish.p1.pos_x or 0, state.finish.p2.pos_x or 0, UI.get_gap_value(state.finish.p1.gap), 0
            }
        })
    end

        table.insert(rows, {
            font_size = UI.get_scaled_font_size(UI.large_font),
            is_color = true,
            percent_max = percent_max_values,
            cell_scaling = { hit_damage = hit_damage_scaling },
            values = {
                hit_damage_total,
                UI.get_combo_damage_value(state, is_p1),
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
            p1_carry_total,
            p2_carry_total,
            UI.get_gap_value(is_p1 and state.finish.p1.gap or state.finish.p2.gap),
            (is_p1 and state.finish.p1.advantage or state.finish.p2.advantage) or 0,
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

function UI.get_combo_window_width(state)
    local visible_columns = UI.get_visible_columns(state.attacker)
    return UI.get_combo_table_width_from_columns(visible_columns) + math.ceil(UI.window_padding_width * UI.get_column_width_scale())
end

function UI.process_columns(values, is_color, visible_columns, percent_max_values, state, carry_percent_mode, blank_columns, display_modes, cell_scaling, carry_direction_arrows)
    for display_index, column in ipairs(visible_columns) do
        imgui.table_set_column_index(display_index - 1)
        local v = values[column.index]
        local is_drive_burnout_entry = UI.is_drive_burnout_entry_marker and UI.is_drive_burnout_entry_marker(v)
        local is_drive_burnout_opponent_entry = UI.is_drive_burnout_opponent_entry_marker and UI.is_drive_burnout_opponent_entry_marker(v)
        local display_v = is_drive_burnout_entry and UI.get_drive_burnout_entry_value(v) or v
        local v_numeric = tonumber(display_v) or 0
        local w = column.width
        local percent_max = percent_max_values and percent_max_values[column.index] or nil
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
            text = UI.format_column_value(display_v, column, percent_max, carry_percent_mode)
        end
        local is_p1_window = state and state.attacker == 0
        local is_opposing_drive = (is_p1_window and column.id == "p2_drive") or (not is_p1_window and column.id == "p1_drive")
        local is_opposing_super = (is_p1_window and column.id == "p2_super") or (not is_p1_window and column.id == "p1_super")
        local is_carry = column.id == "p1_carry" or column.id == "p2_carry"
        local is_opposing_carry = is_carry and ((is_p1_window and column.id == "p1_carry") or ((not is_p1_window) and column.id == "p2_carry"))
        local is_gap = column.id == "gap"
        local is_dash_placeholder = text == "-" and (column.id == "damage" or is_carry or column.id == "hit_damage")
        local display_v_numeric = v_numeric
        local hit_damage_scaling = cell_scaling and cell_scaling[column.id] or nil
        if column.id == "adv" then
            display_v_numeric = UI.round_display_value(v_numeric)
        end

        if column.id == "adv" and state and (state.started or display_v_numeric == 0) then
            text = ""
            display_v_numeric = 0
        end

        if is_carry and state then
            text = UI.format_carry_display_value(v, column, percent_max, carry_percent_mode)
            local carry_arrow = carry_direction_arrows and carry_direction_arrows[column.id] or nil
            if carry_arrow and text ~= "" and text ~= "-" then
                text = text .. " " .. carry_arrow
            end
            is_dash_placeholder = text == "-" and (column.id == "damage" or is_carry or column.id == "hit_damage")
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
                        color = UI.smoothed_hit_damage_scaling_color_for_state(state, hit_damage_scaling)
                    elseif column.id == "damage" then
                        color = UI.smoothed_value_to_hex_color_for_state(state, column, v_numeric, column.color_max)
                    elseif is_opposing_drive then
                        color = UI.smoothed_opposing_drive_to_hex_color_for_state(state, column, v_numeric)
                    elseif column.unit_id == "drive" then
                        color = UI.smoothed_self_drive_to_hex_color_for_state(state, column, v_numeric)
                    elseif is_opposing_super then
                        color = UI.smoothed_yellow_to_red_hex_color_for_state(state, column, v_numeric, column.color_max)
                    elseif column.unit_id == "super" then
                        color = UI.smoothed_self_super_to_hex_color_for_state(state, column, v_numeric)
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
end

function UI.render_combo_window_table(state)
    local visible_columns = UI.get_visible_columns(state.attacker)
    local value_rows = UI.get_combo_value_rows(state)

    if #visible_columns == 0 then
        imgui.text("No columns selected")
        return
    end

    local table_flags = (imgui.TableFlags and imgui.TableFlags.SizingStretchProp) or 24576
    if imgui.begin_table("combo_table_p" .. tostring(state.attacker + 1), #visible_columns, table_flags, Vector2f.new(0, 0)) then
        for _, column in ipairs(visible_columns) do
            imgui.table_setup_column(UI.get_combo_column_label(column, visible_columns), nil, column.width)
        end

        UI.get_small_font()
        imgui.table_next_row()
        for display_index, column in ipairs(visible_columns) do
            imgui.table_set_column_index(display_index - 1)
            local label = UI.get_combo_column_label(column, visible_columns)
            UI.center_text(label, column.width, function() UI.draw_text_with_black_stroke(label) end)
        end
        imgui.pop_font()

        for _, row in ipairs(value_rows) do
            imgui.table_next_row()
            UI.get_font_size(row.font_size)
            UI.process_columns(row.values, row.is_color == true, visible_columns, row.percent_max, state, row.carry_percent_mode, row.blank_columns, row.display_modes, row.cell_scaling, row.carry_direction_arrows)
            imgui.pop_font()
        end
        imgui.end_table()
    end
end

function UI.render_player_combo_window(player_index, title, x, y, anchor_pivot_x, toggle_setting, minimal_setting)
    local state = ComboData.player_states[player_index]
    if not state or not (state.started or state.finished) then return end
    local window_width = UI.get_combo_window_width(state)
    local background_opacity = UI.get_display_background_opacity()

    if UI.should_hide_combo_window(state) then
        state.finished = false
        state.timer_remaining = nil
        return
    end

    local can_push_style_var = imgui.push_style_var and imgui.pop_style_var
    local window_rounding_style_var = can_push_style_var and UI.get_imgui_style_var("WindowRounding") or nil
    local border_size_style_var = can_push_style_var and UI.get_imgui_style_var("WindowBorderSize") or nil
    local suppress_border = background_opacity <= 0 and border_size_style_var ~= nil
    local style_var_push_count = 0

    imgui.set_next_window_pos(Vector2f.new(x, y), 1 << 0, Vector2f.new(anchor_pivot_x, 0))
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

    if imgui.begin_window(title, true, 1 | 8 | 32) then
        if UI.is_toggle_view_clicked() then
            Config.settings[minimal_setting] = not Config.settings[minimal_setting]

            local side = (player_index == 0) and "P1 " or "P2 "
            local status = Config.settings[minimal_setting] and "Disabled" or "Enabled"
            UI.action_notify(side .. "Minimal View " .. status, "alert_on_minimal")

            UI.mark_for_save()
        end
        UI.render_combo_window_table(state)
        imgui.end_window()
    end
    if style_var_push_count > 0 then
        imgui.pop_style_var(style_var_push_count)
    end
    imgui.pop_style_color(2)
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
    local display = imgui.get_display_size()
    local center_x = (display and display.x or 0) * 0.5
    return {
        self = {
            x = math.floor(center_x - DEFAULT_POSITION_OFFSET + 0.5),
            y = DEFAULT_POSITION_Y,
        },
        opponent = {
            x = math.floor(center_x + DEFAULT_POSITION_OFFSET + 0.5),
            y = DEFAULT_POSITION_Y,
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
        if tonumber(coords.x) == nil then
            coords.x = default_coords.x
            changed = true
        end
        if tonumber(coords.y) == nil then
            coords.y = default_coords.y
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
    return math.floor(value + 0.5)
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

    local source_y = self_coords.y
    if tonumber(source_y) == nil then
        source_y = opponent_coords.y
    end

    local shared_y = UI.get_shared_bounded_position_y(source_y, defaults)
    local changed = false

    if self_coords.y ~= shared_y then
        self_coords.y = shared_y
        changed = true
    end
    if opponent_coords.y ~= shared_y then
        opponent_coords.y = shared_y
        changed = true
    end

    return changed
end

function UI.set_position_coord(id, axis, value)
    Config.ensure_position_settings()
    local coords = Config.settings.position_coords[id]
    if type(coords) ~= "table" then return end

    local numeric = tonumber(value)
    if numeric == nil then return end

    local rounded
    if UI.get_bounded_position_coord then
        rounded = UI.get_bounded_position_coord(id, axis, numeric)
    else
        rounded = math.floor(numeric + 0.5)
    end

    local changed = false

    if axis == "y" and Config.settings.position_match_vertical ~= false then
        rounded = UI.get_shared_bounded_position_y(numeric)
    end

    if coords[axis] ~= rounded then
        coords[axis] = rounded
        changed = true
    end

    if axis == "x" and Config.settings.position_mirror_y_axis ~= false then
        local partner_id = UI.get_position_mirror_partner(id)
        local partner_coords = partner_id and Config.settings.position_coords[partner_id] or nil
        if type(partner_coords) == "table" then
            local mirrored_x = UI.get_mirrored_position_x(rounded)
            if UI.get_bounded_position_coord then
                mirrored_x = UI.get_bounded_position_coord(partner_id, "x", mirrored_x)
            end
            if partner_coords.x ~= mirrored_x then
                partner_coords.x = mirrored_x
                changed = true
            end
        end
    end

    if axis == "y" and Config.settings.position_match_vertical ~= false then
        local partner_id = UI.get_position_mirror_partner(id)
        local partner_coords = partner_id and Config.settings.position_coords[partner_id] or nil
        if type(partner_coords) == "table" and partner_coords.y ~= rounded then
            partner_coords.y = rounded
            changed = true
        end
    end

    if changed then
        UI.mark_for_save()
    end
end

function UI.render_windows()
    if not Config.settings.toggle_all or GameObjects.is_paused() then return end
    UI.right_click_this_frame = UI.was_key_down(RIGHT_CLICK)

    local _, defaults = UI.ensure_position_coords()
    local self_x = UI.get_position_coord("self", "x", defaults)
    local self_y = UI.get_position_coord("self", "y", defaults)
    local opponent_x = UI.get_position_coord("opponent", "x", defaults)
    local opponent_y = UI.get_position_coord("opponent", "y", defaults)

    if Config.settings.toggle_p1 then
        local p1_state = ComboData.player_states[0]
        UI.render_player_combo_window(0, "P1 Current " .. ((p1_state and p1_state.is_blocked) and "Block" or "Combo"), self_x, self_y, 1, "toggle_p1", "toggle_minimal_view_p1")
    end
    if Config.settings.toggle_p2 then
        local p2_state = ComboData.player_states[1]
        UI.render_player_combo_window(1, "P2 Current " .. ((p2_state and p2_state.is_blocked) and "Block" or "Combo"), opponent_x, opponent_y, 0, "toggle_p2", "toggle_minimal_view_p2")
    end
end

function UI.in_window_range()
    local mouse = imgui.get_mouse()
    local pos, size = imgui.get_window_pos(), imgui.get_window_size()
    return mouse.x >= pos.x and mouse.x <= pos.x + size.x and mouse.y >= pos.y and mouse.y <= pos.y + size.y
end

function UI.is_toggle_view_clicked()
    return UI.in_window_range() and UI.right_click_this_frame
end

function UI.update_combo_timers()
    for i = 0, 1 do
        local state = ComboData.player_states[i]
        if state.timer_remaining and state.timer_remaining > 0 then
            state.timer_remaining = state.timer_remaining - (1.0 / 60.0)
        end
    end
end

function UI.should_hide_combo_window(state)
    return Config.settings.combo_timer_duration > 0 and state.timer_remaining and state.timer_remaining <= 0
end

function UI.set_display_percent(setting_key, value, min_value, max_value)
    Config.settings[setting_key] = math.floor(Utils.clamp(value, min_value, max_value) + 0.5)
    UI.mark_for_save()
end

function UI.render_display_settings()
    if imgui.tree_node("Display") then
        if not Config.display_defaults_selected() then
            imgui.same_line()
            if imgui.button("Defaults##display_defaults") then
                Config.settings.display_background_opacity = DEFAULT_BACKGROUND_OPACITY
                Config.settings.display_text_opacity = DEFAULT_TEXT_OPACITY
                Config.settings.display_scale = DEFAULT_DISPLAY_SCALE
                Config.settings.combo_timer_duration = DEFAULT_COMBO_TIMER_DURATION
                Config.settings.toggle_clear_on_damage = DEFAULT_CLEAR_ON_DAMAGE
                Config.settings.toggle_clear_on_block = DEFAULT_CLEAR_ON_BLOCK
                UI.mark_for_save()
            end
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

        imgui.text("Clear On Damage")
        imgui.same_line()
        local clear_damage_changed, clear_on_damage = imgui.checkbox("##clear_on_damage", Config.settings.toggle_clear_on_damage == true)
        if clear_damage_changed then
            Config.settings.toggle_clear_on_damage = clear_on_damage == true
            if not Config.settings.toggle_clear_on_damage then
                Config.settings.toggle_clear_on_block = false
            end
            UI.mark_for_save()
        end

        if Config.settings.toggle_clear_on_damage == true then
            imgui.text("Clear On Block")
            imgui.same_line()
            local clear_block_changed, clear_on_block = imgui.checkbox("##clear_on_block", Config.settings.toggle_clear_on_block == true)
            if clear_block_changed then
                Config.settings.toggle_clear_on_block = clear_on_block == true
                UI.mark_for_save()
            end
        end

        imgui.text("Clear After:")
        imgui.same_line()
        imgui.push_item_width(30)
        changed, Config.settings.combo_timer_duration = imgui.drag_int("##combo_timer_duration", Config.settings.combo_timer_duration, 1, 0, 120)
        imgui.pop_item_width()
        imgui.same_line()
        imgui.text("Seconds")
        if changed then UI.mark_for_save() end

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
            if imgui.button("Defaults##unit_defaults") then
                Config.reset_unit_defaults()
                UI.mark_for_save()
            end
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

        imgui.tree_pop()
    end
end

function UI.render_position_coord_inputs(def, defaults)
    local coords = Config.settings.position_coords[def.id]
    if type(coords) ~= "table" then return end

    imgui.text(def.label)
    imgui.same_line()
    imgui.text("X")
    imgui.same_line()
    imgui.push_item_width(55)
    local x_text = tostring(UI.get_position_coord(def.id, "x", defaults))
    local x_changed, new_x_text = imgui.input_text("##position_" .. def.id .. "_x", x_text)
    imgui.pop_item_width()
    if x_changed then UI.set_position_coord(def.id, "x", new_x_text) end

    imgui.same_line()
    imgui.text("Y")
    imgui.same_line()
    imgui.push_item_width(55)
    local y_text = tostring(UI.get_position_coord(def.id, "y", defaults))
    local y_changed, new_y_text = imgui.input_text("##position_" .. def.id .. "_y", y_text)
    imgui.pop_item_width()
    if y_changed then UI.set_position_coord(def.id, "y", new_y_text) end
end

function UI.render_position_settings()
    if imgui.tree_node("Position") then
        local _, defaults = UI.ensure_position_coords()
        if not Config.position_defaults_selected(defaults) then
            imgui.same_line()
            if imgui.button("Defaults##position_defaults") then
                Config.reset_position_defaults(defaults)
                UI.mark_for_save()
            end
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

        for _, def in ipairs(POSITION_DEFS) do
            UI.render_position_coord_inputs(def, defaults)
        end

        imgui.tree_pop()
    end
end
function UI.render_settings()
    if imgui.tree_node("Attack Info") then
        local changed = false
        if not Config.attack_info_defaults_selected() then
            imgui.same_line()
            if imgui.button("Defaults##attack_info_defaults") then
                Config.reset_attack_info_defaults()
                UI.mark_for_save()
            end
        end

        imgui.text("Enable (F2)")
        imgui.same_line()
        changed, Config.settings.toggle_all = imgui.checkbox("##enable", Config.settings.toggle_all)
        if changed then
            UI.action_notify("Display " .. (Config.settings.toggle_all and "Enabled" or "Disabled"), "alert_on_toggle")
            UI.mark_for_save()
        end

        imgui.text("Show Blocked")
        imgui.same_line()
        local blocked_changed
        blocked_changed, Config.settings.toggle_show_blocked_attacks = imgui.checkbox("##show_blocked_attacks", Config.settings.toggle_show_blocked_attacks)
        if blocked_changed then
            UI.action_notify("Blocked Attacks " .. (Config.settings.toggle_show_blocked_attacks and "Enabled" or "Disabled"), "alert_on_toggle")
            UI.mark_for_save()
        end

        if Config.settings.toggle_show_blocked_attacks then
            imgui.text("Leniency")
            UI.set_hover_tooltip(BLOCKSTRING_TOOLTIP)
            imgui.same_line()
            imgui.push_item_width(25)
            local string_gap_text = tostring(Config.get_string_gap())
            local string_gap_changed, new_string_gap_text = imgui.input_text("##string_gap", string_gap_text)
            UI.set_hover_tooltip(BLOCKSTRING_TOOLTIP)
            imgui.pop_item_width()
            if string_gap_changed then
                local new_string_gap = math.max(0, math.floor(tonumber(new_string_gap_text) or DEFAULT_STRING_GAP))
                if new_string_gap ~= Config.get_string_gap() then
                    Config.settings.string_gap = new_string_gap
                    UI.mark_for_save()
                end
            end
        end

        imgui.text("Ignore Framekills")
        imgui.same_line()
        local framekills_changed
        framekills_changed, Config.settings.toggle_ignore_framekills = imgui.checkbox("##ignore_framekills", Config.settings.toggle_ignore_framekills)
        if framekills_changed then
            UI.action_notify("Framekills " .. (Config.settings.toggle_ignore_framekills and "Ignored" or "Shown"), "alert_on_toggle")
            UI.mark_for_save()
        end

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

            UI.render_display_settings()
            UI.render_unit_settings()

            if imgui.tree_node("Column Visibility") then
                if not Config.column_visibility_defaults_selected() then
                    imgui.same_line()
                    if imgui.button("Defaults##column_visibility_defaults") then
                        Config.reset_column_visibility_defaults()
                        UI.mark_for_save()
                    end
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
    local sPlayer, cPlayer, cTeam = GameObjects.get_objects()
    local in_battle = GameObjects.is_in_battle(cPlayer)
    local round_no = in_battle and GameObjects.get_round_no() or nil

    UI.handle_hotkeys()
    UI.update_combo_timers()
    UI.tooltip_handler()
    UI.save_handler()
    UI.draw_action_notify()
    ComboData.sync_gameplay_state(in_battle, round_no)

    -- Use the combat visibility gate instead of prev_no_push_bit, which is 0
    -- in story-training and other modes even during active gameplay. The gate
    -- now requires a live action engine so retained postmatch objects do not
    -- render stale combat boxes.
    if in_battle then
        UI.render_windows()
        local p1, p2 = GameObjects.map_player_data(cPlayer, cTeam)
        ComboData.update_state(p1, p2)
    end
end)
