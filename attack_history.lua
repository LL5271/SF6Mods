local sdk = sdk
local imgui = imgui
local re = re
local fs = fs
local json = json
local reframework = reframework

local SAVE_DIR = "combo_data/"
local CONFIG_PATH = SAVE_DIR .. "config.json"
local COMBO_DATA_PATH = SAVE_DIR .. "combo_data.json"
local MOVE_DICT_DIR = "move_dicts/"
local F3_KEY = 0x72

local Utils = {}
local GameData = {}
local ComboManager = {}
local UI = {}
local Config = {}
local SceneTracker = {}

-----------------------------------------------------------------------------
-- Utils
-----------------------------------------------------------------------------
function Utils.deep_copy(original)
    if type(original) ~= 'table' then return original end
    local copy = {}
    for key, value in pairs(original) do
        copy[key] = Utils.deep_copy(value)
    end
    return copy
end

function Utils.bitand(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a / 2)
        b = math.floor(b / 2)
    end
    return result
end

function Utils.format_action_id(action_id)
    if action_id == nil then return "0000" end
    local id_str = tostring(action_id)
    while #id_str < 4 do
        id_str = "0" .. id_str
    end
    return id_str
end

function Utils.format_action_id_list(action_id_list)
    local formatted_action_id_list = {}
    local formatted_id
    for k, v in pairs(action_id_list) do
        formatted_id = Utils.format_action_id(v)
        table.insert(formatted_action_id_list, formatted_id)
    end
    return formatted_action_id_list
end

function Utils.format_named_action_list(formatted_id_list, char_dict)
    local named_action_list = {}
    local named_action = ""
    for k, v in pairs(formatted_id_list) do
        if v then
            named_action = char_dict[v]    
        end
        table.insert(named_action_list, named_action)
    end
    return named_action_list
end

function Utils.serialize(val)
    local type_val = type(val)
    if type_val == "number" or type_val == "boolean" then
        return tostring(val)
    elseif type_val == "string" then
        return string.format("%q", val)
    elseif type_val == "table" then
        local s = "{\n"
        for k, v in pairs(val) do
            local key_str
            if type(k) == "number" then
                key_str = string.format("[%d]", k)
            else
                key_str = string.format("[%q]", k)
            end
            s = s .. key_str .. " = " .. Utils.serialize(v) .. ",\n"
        end
        s = s .. "}"
        return s
    else
        return "nil"
    end
end

function Utils.parse_timestamp(ts)
    if not ts or type(ts) ~= "string" or #ts ~= 13 then return 0 end
    local h, m, s, y, mon, d = ts:match("(%d%d)(%d%d)(%d%d)_(%d%d)(%d%d)(%d%d)")
    if not h then return 0 end
    return os.time({
        hour = tonumber(h),
        min = tonumber(m),
        sec = tonumber(s),
        year = 2000 + tonumber(y),
        month = tonumber(mon),
        day = tonumber(d)
    })
end

-----------------------------------------------------------------------------
-- SceneTracker
-----------------------------------------------------------------------------
SceneTracker.current_scene_id = -1

function SceneTracker.get_scene_id()
    local bFlowManager = sdk.get_managed_singleton("app.bFlowManager")
    if not bFlowManager then return -1 end
    return bFlowManager:get_MainFlowID()
end

function SceneTracker.check_scene_change()
    local new_scene_id = SceneTracker.get_scene_id()
    if new_scene_id ~= SceneTracker.current_scene_id and SceneTracker.current_scene_id ~= -1 then        
        SceneTracker.current_scene_id = new_scene_id
        SceneTracker.on_scene_change()
        return true
    end
    SceneTracker.current_scene_id = new_scene_id
    return false
end

function SceneTracker.on_scene_change()
    if SceneTracker.current_scene_id == 2 or SceneTracker.current_scene_id == 24 then
        -- Scene changed, trigger save if autosave is enabled and there are session combos
        if Config.settings.autosave and ComboManager and ComboManager.session_combos and #ComboManager.session_combos > 0 then
            log.info(string.format("Scene changed from %d to %d, saving %d session combos", 
                SceneTracker.current_scene_id, new_scene_id, #ComboManager.session_combos))
            ComboManager.save_to_file()

        -- Clear combo windows
        ComboManager.clear_combo_windows()
        
        -- Clear session combos for the new scene
        ComboManager.session_combos = {}
        ComboManager.update_all_combos()
        
        -- Increment group ID and reset local index for the new scene
        ComboManager.current_group_id = ComboManager.current_group_id + 1
        ComboManager.group_combo_index = 0
        end
    end
end

-----------------------------------------------------------------------------
-- Config
-----------------------------------------------------------------------------
Config.settings = {
    autosave = true,
    save_training = true,
    show_history = true,
    history_limit = 100,
    sort_col = "Time",
    sort_dir = "desc",
    show_session_window = false
}

function Config.load()
    local loaded_settings = json.load_file(CONFIG_PATH)
    if loaded_settings then
        -- Merge loaded settings with defaults to ensure new settings are present
        for k, v in pairs(loaded_settings) do
            Config.settings[k] = v
        end
    else
        -- If no config file, save the defaults
        Config.save()
    end
end

function Config.save()
    json.dump_file(CONFIG_PATH, Config.settings)
end

-----------------------------------------------------------------------------
-- GameData
-----------------------------------------------------------------------------
GameData.char_id_table = {
    [0] = "",
    [1] = "Ryu", 
    [2] = "Luke", 
    [3] = "Kimberly", 
    [4] = "ChunLi", 
    [5] = "Manon", 
    [6] = "Zangief", 
    [7] = "JP", 
    [8] = "Dhalsim", 
    [9] = "Cammy", 
    [10] = "Ken", 
    [11] = "DeeJay", 
    [12] = "Lily", 
    [13] = "AKI", 
    [14] = "Rashid", 
    [15] = "Blanka", 
    [16] = "Juri", 
    [17] = "Marisa", 
    [18] = "Guile", 
    [19] = "Ed",
    [20] = "EHonda", 
    [21] = "Jamie", 
    [22] = "Akuma", 
    [26] = "MBison", 
    [27] = "Terry",
    [28] = "Mai",
    [29] = "Elena",
    [25] = "Sagat",
    [30] = "CViper",
    [31] = "Alex",
    [32] = "Ingrid",
    [33] = "Yasmine"
}

GameData.TrainingManager = sdk.get_managed_singleton("app.training.TrainingManager")
GameData.gBattle = sdk.find_type_definition("gBattle")
GameData.PlayerField = GameData.gBattle:get_field("Player")
GameData.TeamField = GameData.gBattle:get_field("Team")
GameData.StatsField = GameData.gBattle:get_field("Stats")
GameData.ConfigField = GameData.gBattle:get_field("Config")
GameData.RoundField = GameData.gBattle:get_field("Round")

function GameData.get_char_dict(char_id)
    local move_dict_path = tostring(char_id) .. ".json"
    return json.load_file(MOVE_DICT_DIR .. move_dict_path) or {}
end

function GameData.get_objects()
    local sPlayer = GameData.PlayerField:get_data()
    if not sPlayer then return nil, nil, nil end
    
    local cPlayer = sPlayer.mcPlayer
    local sTeam = GameData.TeamField:get_data()
    local cTeam = sTeam and sTeam.mcTeam or nil
    
    return sPlayer, cPlayer, cTeam
end

function GameData.map_match_data()
    local battle_config = GameData.ConfigField:get_data()
    local battle_round = GameData.RoundField:get_data()
    
    if not battle_config or not battle_round then return {} end

    local data = {}

    data.game_mode = battle_config._GameMode or nil
    data.round = battle_round.RoundNo or nil

    data.timer = {}
    data.timer.seconds = battle_round.play_timer or 0
    data.timer.extra_frames = battle_round.play_timer_ms or 0
    data.timer.total_frames_remaining = ((data.timer.seconds * 60) + (data.timer.extra_frames or 0)) or 0
    data.timer.seconds_remaining = (data.timer.total_frames_remaining / 60) or 0
    
    return data
end

function GameData.map_player_data(player_index, cPlayer, cTeam, frame_meter)
    local player = cPlayer[player_index]
    if not player then return {} end
    
    local sStats = GameData.StatsField:get_data()
    local stats = sStats and sStats.Info or {}
    local team = cTeam and cTeam[player_index] or nil
    local opponent = cPlayer[1 - player_index]
    
    local data = {}
    
    -- Action/Engine Data
    if player.mpActParam and player.mpActParam.ActionPart then
        data.char_id = player.mpActParam.ActionPart._CharaID
        local engine = player.mpActParam.ActionPart._Engine
        if engine then
            data.action_id = engine:get_ActionID()
            data.action_frame = engine:get_ActionFrame()
            data.end_frame = engine:get_ActionFrameNum()
            data.margin_frame = engine:get_MarginFrame()
            if engine.mParam and engine.mParam.action and engine.mParam.action.ActionFrame then
                data.main_frame = engine.mParam.action.ActionFrame.MainFrame
                data.follow_frame = engine.mParam.action.ActionFrame.FollowFrame
            end
        end
    end

    -- Drive Usage
    if not stats[player_index] then return data end

    data.gauge_dg = stats[player_index].Gauge_DG or 0
    data.gauge_di = stats[player_index].Gauge_DI or 0
    data.gauge_ex = stats[player_index].Gauge_EX or 0
    data.gauge_rush_p = stats[player_index].Gauge_RushP or 0
    data.gauge_rush_c = stats[player_index].Gauge_RushC or 0
    data.gauge_dr = stats[player_index].Gauge_DR or 0
    data.gauge_other = stats[player_index].Gauge_Other or 0

    -- Super Usage
    data.gauge_super_1 = stats[player_index].Super_1 or 0
    data.gauge_super_2 = stats[player_index].Super_2 or 0
    data.gauge_super_3 = stats[player_index].Super_3 or 0
    data.gauge_super_35 = stats[player_index].Super_35 or 0

    -- Misc info
    data.parry = stats[player_index].Parry or 0
    data.perfect_parry = stats[player_index].ParryJust or 0
    data.throw_parry = stats[player_index].ThrowParry or 0
    data.drive_reversal = stats[player_index].DrvRev or 0
    data.di_hit = stats[player_index].DrvImp_Hit or 0
    data.di_punish = stats[player_index].DrvImp_Punish or 0
    data.throw = stats[player_index].Throw or 0
    data.throw_tech = stats[player_index].ThrowTech or 0
    data.stun = stats[player_index].Stun or 0

    -- Frame Advantage Data
    if frame_meter then
        data.stun_frame = frame_meter.StunFrame
        local stun_frame_str = string.gsub(data.stun_frame or "0", "F", "")
        data.advantage = tonumber(stun_frame_str) or 0
    end
    
    -- Vitality/Drive/Super Data
    data.hp_cap = player.heal_new or 0
    data.hp_current = player.vital_new or 0
    data.hp_cooldown = player.healing_wait or 0
    data.dir = Utils.bitand(player.BitValue or 0, 128) == 128
    data.burnout = player.incapacitated or false
    data.drive = player.focus_new or 0
    data.drive_adjusted = data.burnout and (data.drive - 60000) or data.drive
    data.drive_cooldown = player.focus_wait or 0
    data.super = team and team.mSuperGauge or 0
    data.combo_damage = team and team.mComboDamage or 0
    data.combo_count = team and team.mComboCount or 0
    data.death_count = team and team.mDeathCount or 0
    data.buff = player.style_timer or 0
    data.debuff_timer = player.damage_cond and player.damage_cond.timer or 0
    
    -- Position/Physics Data
    data.gap = (player.vs_distance and player.vs_distance.v or 0) / 65536.0
    data.intangible = player.muteki_time or 0
    data.throw_invul = player.catch_muteki or 0
    
    if player.pos and player.pos.x then
        data.pos_x = player.pos.x.v / 65536.0
        data.pos_y = player.pos.y.v / 65536.0
    else
        data.pos_x = 0
        data.pos_y = 0
    end
     
    -- Character selection
    data.char_id = data.char_id or 0
    data.char_name = GameData.char_id_table[data.char_id] or "Unknown"
    data.char_dict_file = MOVE_DICT_DIR .. tostring(data.char_id) .. ".json"
    
    return data
end

function GameData.process_battle_info()
    local sPlayer, cPlayer, cTeam = GameData.get_objects()
    if not sPlayer then return nil, nil, nil end

    local frame_meter = nil
    if GameData.TrainingManager then
        local tCommon = GameData.TrainingManager._tCommon
        if tCommon and tCommon.SnapShotDatas and tCommon.SnapShotDatas[0] then
            frame_meter = tCommon.SnapShotDatas[0]._DisplayData.FrameMeterSSData.MeterDatas
        end
    end

    local p1_data = GameData.map_player_data(0, cPlayer, cTeam, frame_meter and frame_meter[0] or nil)
    local p2_data = GameData.map_player_data(1, cPlayer, cTeam, frame_meter and frame_meter[1] or nil)
    local match_data = GameData.map_match_data()
    
    return p1_data, p2_data, match_data, frame_meter
end

-----------------------------------------------------------------------------
-- ComboManager
-----------------------------------------------------------------------------

local ComboManager = {
    MAX_COMBOS_TO_LOAD = 100,
    MAX_COMBOS_TO_SAVE = 200,
    
    all_combos = {},
    historical_combos = {},
    session_combos = {},
    current_combo_index = 0,
    current_group_id = 1,
    group_combo_index = 0,
    current_game_mode = nil,
    show_saved_combos = true,
    
    p1_prev = {},
    p2_prev = {},
    match_prev = {},
}

-- ============================================================================
-- Player State Management
-- ============================================================================

local function create_player_state(attacker_idx, defender_idx)
    return {
        started = false,
        finished = false,
        attacker = attacker_idx,
        defender = defender_idx,
        start = { p1 = {}, p2 = {}, match = {} },
        finish = { p1 = {}, p2 = {}, match = {} },
        p1_inputs = {},
        p2_inputs = {},
    }
end

ComboManager.player_states = {
    [0] = create_player_state(0, 1),
    [1] = create_player_state(1, 0),
}

-- ============================================================================
-- Sorting & Filtering
-- ============================================================================

local function get_sort_value(combo, column)
    local totals = combo.totals
    local start = combo.start
    
    local sort_handlers = {
        Date = function() return combo.time or 0 end,
        Time = function() return combo.time or 0 end,
        Round = function() 
            return (start.match and start.match.round) or 0 
        end,
        GameTime = function() 
            return (start.match and start.match.timer and start.match.timer.seconds) or 0 
        end,
        Char = function()
            return (totals.attacker == 0) and (totals.p1_char_name or "") or (totals.p2_char_name or "")
        end,
        Dmg = function() return totals.damage or 0 end,
        P1Drive = function() return totals.p1_drive or 0 end,
        P1Super = function() return totals.p1_super or 0 end,
        P2Drive = function() return totals.p2_drive or 0 end,
        P2Super = function() return totals.p2_super or 0 end,
        P1Pos = function()
            local pos = totals.p1_position or 0
            local dir = (totals.attacker == 0) and totals.p1_dir or totals.p2_dir
            return dir and pos or -pos
        end,
        P2Pos = function()
            local pos = totals.p2_position or 0
            local dir = (totals.attacker == 0) and totals.p1_dir or (not totals.p2_dir)
            return dir and pos or -pos
        end,
        Adv = function()
            return (totals.attacker == 0) and (totals.p1_advantage or 0) or (totals.p2_advantage or 0)
        end,
        Gap = function() return totals.gap or 0 end,
    }
    
    local handler = sort_handlers[column]
    return handler and handler() or 0
end

function ComboManager.sort_combos(combos, column, direction)
    if not column or not direction then return end
    
    table.sort(combos, function(a, b)
        local val_a = get_sort_value(a, column)
        local val_b = get_sort_value(b, column)
        
        if direction == "asc" then
            return val_a < val_b
        else
            return val_a > val_b
        end
    end)
end

function ComboManager.update_all_combos()
    local result = {}
    
    for _, combo in ipairs(ComboManager.session_combos) do
        table.insert(result, combo)
    end
    
    if Config.settings.show_history then
        local limit = Config.settings.history_limit
        for _, combo in ipairs(ComboManager.historical_combos) do
            if limit == 0 or #result < limit then
                table.insert(result, combo)
            end
        end
    end
    
    ComboManager.sort_combos(result, Config.settings.sort_col, Config.settings.sort_dir)
    ComboManager.all_combos = result
end

-- ============================================================================
-- File I/O
-- ============================================================================

function ComboManager.load_combos()
    local file_path = SAVE_DIR .. "combo_history.lua"
    local content = fs.read(file_path)
    
    ComboManager.historical_combos = {}
    
    if content then
        local chunk, err = load(content)
        if chunk then
            local status, data = pcall(chunk)
            if status and data then
                for _, combo in ipairs(data) do
                    -- Convert old timestamp format
                    if not combo.time and combo.timestamp then
                        combo.time = Utils.parse_timestamp(combo.timestamp)
                    end
                    table.insert(ComboManager.historical_combos, combo)
                end
            end
        end
    end
    
    ComboManager.current_combo_index = #ComboManager.historical_combos
    
    local max_group = 0
    for _, combo in ipairs(ComboManager.historical_combos) do
        if combo.group_id and combo.group_id > max_group then
            max_group = combo.group_id
        end
    end
    ComboManager.current_group_id = max_group + 1
    ComboManager.group_combo_index = 0
    
    ComboManager.update_all_combos()
end

function ComboManager.save_to_file()
    if ComboManager.current_game_mode == 2 and not Config.settings.save_training then
        return false
    end
    
    local all_to_save = {}
    for _, combo in ipairs(ComboManager.session_combos) do
        table.insert(all_to_save, combo)
    end
    for _, combo in ipairs(ComboManager.historical_combos) do
        table.insert(all_to_save, combo)
    end
    
    if #all_to_save > ComboManager.MAX_COMBOS_TO_SAVE then
        local limited = {}
        for i = 1, ComboManager.MAX_COMBOS_TO_SAVE do
            table.insert(limited, all_to_save[i])
        end
        all_to_save = limited
    end
    
    local data_str = "return " .. Utils.serialize(all_to_save)
    fs.write(COMBO_DATA_PATH, data_str)
    return true
end

function ComboManager.backup_history(name)
    local combo_save_path = SAVE_DIR .. name
    
    local all_to_backup = {}
    for _, combo in ipairs(ComboManager.session_combos) do
        table.insert(all_to_backup, combo)
    end
    for _, combo in ipairs(ComboManager.historical_combos) do
        table.insert(all_to_backup, combo)
    end
    
    local data_str = "return " .. Utils.serialize(all_to_backup)
    fs.write(combo_save_path, data_str)
end

-- ============================================================================
-- Data Management
-- ============================================================================

function ComboManager.refresh_history()
    ComboManager.all_combos = {}
    ComboManager.load_combos()
end

function ComboManager.clear_combo_windows()
    ComboManager.p1_prev = {}
    ComboManager.p2_prev = {}
    
    for i = 0, 1 do
        ComboManager.player_states[i].started = false
        ComboManager.player_states[i].finished = false
    end
end

function ComboManager.clear_all_combos()
    ComboManager.historical_combos = {}
    ComboManager.session_combos = {}
    ComboManager.all_combos = {}
    ComboManager.current_combo_index = 0
end

function ComboManager.delete_history()
    ComboManager.clear_all_combos()
    ComboManager.save_to_file()
end

-- ============================================================================
-- Combo Detection & Saving
-- ============================================================================

local function is_defender_grounded(p1, p2, attacker_idx)
    local defender = (attacker_idx == 0) and p2 or p1
    return defender.pos_y == 0
end

local function is_duplicate_combo(finish_match, session_combos)
    local current_round = finish_match and finish_match.round or -1
    local current_timer = (finish_match and finish_match.timer and finish_match.timer.total_frames_remaining) or -1
    
    for _, existing_combo in ipairs(session_combos) do
        if existing_combo.finish and existing_combo.finish.match then
            local ex_round = existing_combo.finish.match.round or -1
            local ex_timer = (existing_combo.finish.match.timer and existing_combo.finish.match.timer.total_frames_remaining) or -1
            
            if current_round == ex_round and current_timer == ex_timer then
                log.info(string.format("Duplicate combo detected (Round %d, Timer %d), skipping save", current_round + 1, current_timer))
                return true
            end
        end
    end
    
    return false
end

local function calculate_damage(state)
    local attacker_idx = state.attacker
    local total_damage, damage_pct = 0, 0
    
    if attacker_idx == 0 then
        total_damage = state.finish.p1.combo_damage
        damage_pct = (total_damage / state.finish.p2.hp_cap) * 100
    elseif attacker_idx == 1 then
        total_damage = state.finish.p2.combo_damage
        damage_pct = (total_damage / state.finish.p1.hp_cap) * 100
    end
    
    return total_damage, damage_pct
end

local function adjust_drive_gauge(start_gauge, end_gauge)
    if start_gauge > 0 and end_gauge < 0 then
        return -(start_gauge) + (60000 + end_gauge)
    end
    return end_gauge - start_gauge
end

local function create_combo_data(state)
    local total_damage, damage_pct = calculate_damage(state)
    local p1_char_dict = GameData.get_char_dict(tostring(state.finish.p1.char_id))
    local p2_char_dict = GameData.get_char_dict(tostring(state.finish.p2.char_id))
    local p1_action_ids = Utils.format_action_id_list(state.finish.p1.inputs)
    local p2_action_ids = Utils.format_action_id_list(state.finish.p2.inputs)
    
    local combo_data = {
        index = ComboManager.current_combo_index,
        group_id = ComboManager.current_group_id,
        group_index = ComboManager.group_combo_index,
        time = os.time(),
        start = {
            p1 = Utils.deep_copy(state.start.p1),
            p2 = Utils.deep_copy(state.start.p2),
            match = Utils.deep_copy(state.start.match)
        },
        finish = {
            p1 = Utils.deep_copy(state.finish.p1),
            p2 = Utils.deep_copy(state.finish.p2),
            match = Utils.deep_copy(state.finish.match)
        },
        totals = {
            gap = state.finish.p1.gap or 0,
            attacker = state.attacker,
            damage = total_damage,
            damage_pct = damage_pct,
            
            -- P1 data
            p1_char_id = state.finish.p1.char_id,
            p1_char_name = state.finish.p1.char_name,
            p1_dir = state.finish.p1.dir,
            p1_advantage = state.finish.p1.advantage,
            p1_drive = adjust_drive_gauge(
                state.start.p1.drive_adjusted or 0,
                state.finish.p1.drive_adjusted or 0
            ),
            p1_super = (state.finish.p1.super or 0) - (state.start.p1.super or 0),
            p1_position = (state.finish.p1.pos_x or 0) - (state.start.p1.pos_x or 0),
            p1_actions = p1_action_ids,
            p1_actions_named = Utils.format_named_action_list(p1_action_ids, p1_char_dict) or {},
            
            -- P2 data
            p2_char_id = state.finish.p2.char_id,
            p2_char_name = state.finish.p2.char_name,
            p2_dir = state.finish.p2.dir,
            p2_advantage = state.finish.p2.advantage,
            p2_drive = adjust_drive_gauge(
                state.start.p2.drive_adjusted or 0,
                state.finish.p2.drive_adjusted or 0
            ),
            p2_super = (state.finish.p2.super or 0) - (state.start.p2.super or 0),
            p2_position = (state.finish.p2.pos_x or 0) - (state.start.p2.pos_x or 0),
            p2_actions = p2_action_ids,
            p2_actions_named = Utils.format_named_action_list(p2_action_ids, p2_char_dict) or {},
        }
    }
    
    return combo_data
end

function ComboManager.save_combo(player_idx)
    local state = ComboManager.player_states[player_idx]
    
    if not (state.finished and state.start.p1 and state.start.p2 and state.finish.p1 and state.finish.p2) then
        return false
    end
    
    local game_mode = state.start.match.game_mode
    
    if game_mode and game_mode ~= 2 then
        if is_duplicate_combo(state.finish.match, ComboManager.session_combos) then
            return false
        end
    end
    
    local combo_data = create_combo_data(state)
    
    table.insert(ComboManager.session_combos, 1, combo_data)
    ComboManager.current_combo_index = ComboManager.current_combo_index + 1
    ComboManager.group_combo_index = ComboManager.group_combo_index + 1
    ComboManager.update_all_combos()
    
    return true
end

-- ============================================================================
-- Combo Tracking
-- ============================================================================

local function adjust_drive_for_cooldown(state, p1, p2, attacker_idx)
    if attacker_idx == 0 then
        if p1.drive_cooldown > 200 then
            state.start.p1.drive_adjusted = state.start.p1.drive_adjusted + 10000
        elseif p1.drive_cooldown <= -120 then
            state.start.p1.drive_adjusted = state.start.p1.drive_adjusted + 20000
        end
    elseif attacker_idx == 1 then
        if p2.drive_cooldown > 200 then
            state.start.p2.drive_adjusted = state.start.p2.drive_adjusted + 10000
        elseif p2.drive_cooldown <= -120 then
            state.start.p2.drive_adjusted = state.start.p2.drive_adjusted + 20000
        end
    end
end

function ComboManager.on_combo_start(p1, p2, match_data, attacker_idx, defender_idx)
    local state = ComboManager.player_states[attacker_idx]
    
    state.attacker = attacker_idx
    state.defender = defender_idx
    state.started = true
    state.finished = false
    state.p1_inputs = {}
    state.p2_inputs = {}
    
    state.start.p1 = Utils.deep_copy(ComboManager.p1_prev)
    state.start.p2 = Utils.deep_copy(ComboManager.p2_prev)
    state.start.match = Utils.deep_copy(ComboManager.match_prev)
    
    adjust_drive_for_cooldown(state, p1, p2, attacker_idx)
end

function ComboManager.track_inputs(p1, p2, player_idx)
    local state = ComboManager.player_states[player_idx]
    
    if state.p1_inputs[#state.p1_inputs] ~= p1.action_id then
        table.insert(state.p1_inputs, p1.action_id)
    end
    
    if state.p2_inputs[#state.p2_inputs] ~= p2.action_id then
        table.insert(state.p2_inputs, p2.action_id)
    end
end

function ComboManager.on_combo_update(p1, p2, match_data, player_idx)
    local state = ComboManager.player_states[player_idx]
    
    state.finish.p1 = Utils.deep_copy(p1)
    state.finish.p1.inputs = state.p1_inputs
    state.finish.p2 = Utils.deep_copy(p2)
    state.finish.p2.inputs = state.p2_inputs
    state.finish.match = Utils.deep_copy(match_data)
end

function ComboManager.on_combo_finish(p1, p2, match_data, player_idx)
    local state = ComboManager.player_states[player_idx]
    
    ComboManager.on_combo_update(p1, p2, match_data, player_idx)
    state.finished = true
    state.started = false
    
    ComboManager.save_combo(player_idx)
    
    state.p1_inputs = {}
    state.p2_inputs = {}
end

-- ============================================================================
-- Main Update Loop
-- ============================================================================

function ComboManager.check_started(p1, p2, match_data)
    for i = 0, 1 do
        local state = ComboManager.player_states[i]
        local player = (i == 0) and p1 or p2
        local opponent = (i == 0) and p2 or p1
        
        if not state.started and player.combo_count > 0 and opponent.hp_current > 0 then
            ComboManager.on_combo_start(p1, p2, match_data, i, 1 - i)
        end
    end
end

function ComboManager.check_finished(p1, p2, match_data)
    for i = 0, 1 do
        local state = ComboManager.player_states[i]
        
        if state.started then
            local player = (i == 0) and p1 or p2
            local opponent = (i == 0) and p2 or p1
            local opponent_prev = (i == 0) and ComboManager.p2_prev or ComboManager.p1_prev
            
            local is_finished = opponent.death_count ~= opponent_prev.death_count
            local is_knockdown = player.combo_count == 0
            
            if is_finished or is_knockdown then
                ComboManager.on_combo_finish(p1, p2, match_data, i)
            else
                ComboManager.on_combo_update(p1, p2, match_data, i)
            end
        end
    end
end

function ComboManager.update_state(p1, p2, match_data)
    ComboManager.check_started(p1, p2, match_data)
    
    for i = 0, 1 do
        local state = ComboManager.player_states[i]
        if state.started and not state.finished then
            ComboManager.track_inputs(p1, p2, i)
        end
    end
    
    ComboManager.check_finished(p1, p2, match_data)
    
    -- Update previous frame data
    ComboManager.p1_prev = p1
    ComboManager.p2_prev = p2
    ComboManager.match_prev = match_data
    ComboManager.current_game_mode = match_data.game_mode
end

-----------------------------------------------------------------------------
-- UI
-----------------------------------------------------------------------------
UI.prev_key_states = {}
UI.hide = false
UI.show_session = false
UI.display_size = imgui.get_display_size()
UI.max_session_window_height = 1000

function UI.tooltip_debugger(t)
    imgui.begin_tooltip()
    imgui.text(t)
    imgui.end_tooltip()
end

function UI.was_key_down(i)
    local down = reframework:is_key_down(i)
    local prev = UI.prev_key_states[i] or false
    UI.prev_key_states[i] = down
    return down and not prev
end

function UI.format_time(unix_time)
    if not unix_time or unix_time == 0 then return "N/A" end
    return os.date("%m/%d/%y %H:%M:%S", unix_time)
end

function UI.format_combo_time(combo)
    if combo.start and combo.start.match and combo.start.match.game_mode then
        local game_mode = combo.start.match.game_mode
        
        if game_mode == 2 then
            return UI.format_time(combo.time)
        elseif game_mode == 24 then
            local round = (combo.start.match and combo.start.match.round) or 0
            return string.format("Round %d", round + 1)
        else
            if combo.start.match.timer and combo.start.match.timer.seconds_remaining then
                return string.format("%.0fs", combo.start.match.timer.seconds_remaining)
            end
        end
    end
    
    return UI.format_time(combo.time)
end

function UI.color(val)
    if val > 0 then
        imgui.text_colored(string.format("%.0f", val), 0xFF00FF00)
    elseif val < 0 then
        imgui.text_colored(string.format("%.0f", val), 0xFFDDF527)
    else
        imgui.text("0")
    end
end

function UI.copy_combo_to_clipboard(combo)
    local rounded_carry = math.floor((combo.totals.p2_position / 10) + 0.5)
    local gap_on_backroll = combo.totals.gap + 120

    local clipboard_string = string.format("%.0f\t%.0f\t%.0f\t%.0f\t%d\t%.0f\t%.0f", 
        combo.totals.damage, 
        combo.totals.p1_drive, 
        combo.totals.p1_super, 
        combo.totals.p1_advantage, 
        rounded_carry, 
        combo.totals.gap, 
        gap_on_backroll)
    
    sdk.copy_to_clipboard(clipboard_string)
    return true
end

function UI.render_combo_window_columns(start_idx, p1_drive, p1_super, p2_drive, p2_super, p1_pos, p2_pos, adv, gap, is_diff)
    imgui.table_set_column_index(start_idx)
    if is_diff then UI.color(p1_drive or 0) else imgui.text(tostring(p1_drive or 0)) end

    imgui.table_set_column_index(start_idx + 1)
    if is_diff then UI.color(p1_super or 0) else imgui.text(tostring(p1_super or 0)) end

    imgui.table_set_column_index(start_idx + 2)
    if is_diff then UI.color(p2_drive or 0) else imgui.text(tostring(p2_drive or 0)) end

    imgui.table_set_column_index(start_idx + 3)
    if is_diff then UI.color(p2_super or 0) else imgui.text(tostring(p2_super or 0)) end

    imgui.table_set_column_index(start_idx + 4)
    if is_diff then 
        UI.color(p1_pos or 0) 
    else 
        imgui.text(string.format("%.0f", p1_pos or 0))
    end

    imgui.table_set_column_index(start_idx + 5)
    if is_diff then 
        UI.color(p2_pos or 0) 
    else 
        imgui.text(string.format("%.0f", p2_pos or 0))
    end
    
    imgui.table_set_column_index(start_idx + 6)
    imgui.text(tostring(adv or 0))

    imgui.table_set_column_index(start_idx + 7)
    imgui.text(string.format("%.0f", gap or 0))
end

function UI.render_popup_row(label, value, use_color)
    imgui.table_next_row()
    imgui.table_set_column_index(0); imgui.text(label)
    imgui.table_set_column_index(1)
    if use_color then
        UI.color(value)
    else
        imgui.text(tostring(value or 0))
    end
end

function UI.render_popup_separator()
    imgui.table_next_row()
    imgui.table_set_column_index(0); imgui.text("")
    imgui.table_set_column_index(1); imgui.text("")
end

function UI.render_popup_content(combo, id_suffix)
    local timestamp_str = UI.format_time(combo.time)
    local group_idx = combo.group_index or 0
    local group_str = combo.group_id and string.format(" (Group %d)", combo.group_id + 1) or ""
    imgui.text(string.format("Combo #%d%s - %s", (group_idx + 1), group_str, timestamp_str))
    imgui.separator()
    
    if imgui.begin_table("combo_details_table_" .. (id_suffix or "default"), 2, 0) then
        imgui.table_setup_column("Label", nil, 120)
        imgui.table_setup_column("Value", nil, 150)
        
        local game_mode_str = "N/A"
        local is_training = false
        
        if combo.start and combo.start.match and combo.start.match.game_mode then
            local game_mode = combo.start.match.game_mode
            if game_mode == 2 then
                game_mode_str = "Training"
                is_training = true
            elseif game_mode == 24 then
                game_mode_str = "Replay"
            else
                game_mode_str = tostring(game_mode)
            end
        end
        
        UI.render_popup_row("Mode:", game_mode_str)
        
        if not is_training then
            local round = "N/A"
            local timer_value = "N/A"
            
            if combo.start and combo.start.match then
                round = tostring(combo.start.match.round or "N/A")
                
                if combo.start.match.timer and combo.start.match.timer.seconds then
                    timer_value = tostring(combo.start.match.timer.seconds)
                end
            end
            
            local round_val = tonumber(round)
            local round_display = (round_val and tostring(round_val + 1)) or "N/A"
            UI.render_popup_row("Round:", round_display)
            
            local tv_num = tonumber(timer_value)
            local time_display = (tv_num and string.format("%.0fs", tv_num)) or "N/A"
            UI.render_popup_row("Time:", time_display)
        end
        
        UI.render_popup_separator()
        
        local attacker_name = ""
        local defender_name = ""
        
        if combo.totals.attacker == 0 then
            attacker_name = string.format("%s (P1)", combo.finish.p1.char_name)
            defender_name = combo.finish.p2.char_name
        elseif combo.totals.attacker == 1 then
            attacker_name = string.format("%s (P2)", combo.finish.p2.char_name)
            defender_name = combo.finish.p1.char_name
        end
        
        UI.render_popup_row("Attacker:", attacker_name)
        UI.render_popup_row("Defender:", defender_name)

        UI.render_popup_separator()
        
        if combo.totals.attacker == 0 then
            UI.render_popup_row("Start P2 HP:", combo.start.p2.hp_current)
            UI.render_popup_row("Finish P2 HP:", combo.finish.p2.hp_current)
        elseif combo.totals.attacker == 1 then
            UI.render_popup_row("Start P1 HP:", combo.start.p1.hp_current)
            UI.render_popup_row("Finish P1 HP:", combo.finish.p1.hp_current)
        end
        
        UI.render_popup_row("Total Damage:", combo.totals.damage, true)

        UI.render_popup_separator()
        
        UI.render_popup_row("Start P1 Drive:", combo.start.p1.drive_adjusted)
        UI.render_popup_row("Finish P1 Drive:", combo.finish.p1.drive_adjusted)
        UI.render_popup_row("Total P1 Drive:", combo.totals.p1_drive, true)

        UI.render_popup_separator()
        
        UI.render_popup_row("Start P1 Super:", combo.start.p1.super)
        UI.render_popup_row("Finish P1 Super:", combo.finish.p1.super)
        UI.render_popup_row("Total P1 Super:", combo.totals.p1_super, true)

        UI.render_popup_separator()

        UI.render_popup_row("Start P2 Drive:", combo.start.p2.drive_adjusted)
        UI.render_popup_row("Finish P2 Drive:", combo.finish.p2.drive_adjusted)
        UI.render_popup_row("Total P2 Drive:", combo.totals.p2_drive, true)

        UI.render_popup_separator()
        
        UI.render_popup_row("Start P2 Super:", combo.start.p2.super)
        UI.render_popup_row("Finish P2 Super:", combo.finish.p2.super)
        UI.render_popup_row("Total P2 Super:", combo.totals.p2_super, true)

        UI.render_popup_separator()
        
        UI.render_popup_row("Start P1 Pos:", string.format("%.1f", combo.start.p1.pos_x or 0))
        UI.render_popup_row("Finish P1 Pos:", string.format("%.1f", combo.finish.p1.pos_x or 0))

        local p1_pos_val = 0
        if combo.totals.attacker == 0 then
            if not combo.totals.p1_dir then p1_pos_val = -1 * combo.totals.p1_position else p1_pos_val = combo.totals.p1_position end
        elseif combo.totals.attacker == 1 then
            if not combo.totals.p2_dir then p1_pos_val = -1 * combo.totals.p1_position else p1_pos_val = combo.totals.p1_position end
        end
        UI.render_popup_row("P1 Pos Δ:", p1_pos_val, true)

        UI.render_popup_separator()

        UI.render_popup_row("Start P2 Pos:", string.format("%.1f", combo.start.p2.pos_x or 0))
        UI.render_popup_row("Finish P2 Pos:", string.format("%.2f", combo.finish.p2.pos_x or 0))
        
        local p2_pos_val = 0
        if combo.totals.attacker == 0 then
            if not combo.totals.p1_dir then p2_pos_val = -1 * combo.totals.p2_position else p2_pos_val = combo.totals.p2_position end
        elseif combo.totals.attacker == 1 then
            if not combo.totals.p2_dir then p2_pos_val = -1 * combo.totals.p2_position else p2_pos_val = combo.totals.p2_position end
        end
        UI.render_popup_row("P2 Pos Δ:", p2_pos_val, true)

        UI.render_popup_separator()

        local adv_val = (combo.totals.attacker == 0) and combo.totals.p1_advantage or combo.totals.p2_advantage
        UI.render_popup_row("Advantage:", adv_val)
        UI.render_popup_row("Gap:", combo.totals.gap)

        UI.render_popup_separator()

        local p1_inputs = ""
        for k, v in pairs(combo.finish.p1.inputs) do p1_inputs = tostring(p1_inputs) .. v .. " " end
        UI.render_popup_row("P1 Actions:", p1_inputs)

        local p2_inputs = ""
        for k, v in pairs(combo.finish.p2.inputs) do p2_inputs = tostring(p2_inputs) .. v .. " " end
        UI.render_popup_row("P2 Actions:", p2_inputs)

        UI.render_popup_separator()

        local p1_named = ""
        if combo.totals.p1_actions_named then
            for k, v in pairs(combo.totals.p1_actions_named) do p1_named = tostring(p1_named) .. v .. " " end
        end
        UI.render_popup_row("P1 Action Names:", p1_named)
        
        imgui.end_table()
    end
end

function UI.render_popup_window(combo, i)
    if imgui.begin_popup("combo_details_popup_" .. i) then
        UI.render_popup_content(combo, i)
        imgui.end_popup()
    end
end

function UI.render_session_table_row(combo, i)
    imgui.table_next_row()
    
    local is_replay = (ComboManager.current_game_mode == 24)
    
    if not is_replay then
        imgui.table_set_column_index(0)
        imgui.text(os.date("%m/%d", combo.time or 0))
        
        imgui.table_set_column_index(1)
        imgui.text(os.date("%H:%M:%S", combo.time or 0))
    else
        imgui.table_set_column_index(0)
        local round = (combo.start and combo.start.match and combo.start.match.round) or 0
        imgui.text(tostring(round + 1))
        
        imgui.table_set_column_index(1)
        local timer = (combo.start and combo.start.match and combo.start.match.timer and combo.start.match.timer.seconds) or 0
        imgui.text(string.format("%.0f", timer))
    end
    
    imgui.table_set_column_index(2)
    local char_name = ""
    if combo.totals.attacker == 0 then
        char_name = combo.totals.p1_char_name
    elseif combo.totals.attacker == 1 then
        char_name = combo.totals.p2_char_name
    end
    imgui.text(char_name or "N/A")
    
    imgui.table_set_column_index(3)
    imgui.text(combo.totals.damage)
    
    local p1_pos_val, p2_pos_val
    if combo.totals.attacker == 0 then
        if combo.totals.p1_dir then p1_pos_val = combo.totals.p1_position else p1_pos_val = -1 * combo.totals.p1_position end
        if combo.totals.p1_dir then p2_pos_val = combo.totals.p2_position else p2_pos_val = -1 * combo.totals.p2_position end
    elseif combo.totals.attacker == 1 then
        if combo.totals.p2_dir then p1_pos_val = combo.totals.p1_position else p1_pos_val = -1 * combo.totals.p1_position end
        if not combo.totals.p2_dir then p2_pos_val = -1 * combo.totals.p2_position else p2_pos_val = combo.totals.p2_position end
    end
    
    local adv = (combo.totals.attacker == 0) and combo.totals.p1_advantage or combo.totals.p2_advantage
    
    UI.render_combo_window_columns(4, 
        combo.totals.p1_drive, combo.totals.p1_super,
        combo.totals.p2_drive, combo.totals.p2_super,
        p1_pos_val, p2_pos_val,
        adv, combo.totals.gap,
        true)
    
    imgui.table_set_column_index(12)
    if imgui.small_button("View##combo_" .. i) then
        imgui.open_popup("combo_details_popup_" .. i)
    end
    
    if imgui.is_item_hovered() then
        if not imgui.is_popup_open("combo_details_popup_" .. i) then
            imgui.begin_tooltip()
            UI.render_popup_content(combo, "tooltip_" .. i)
            imgui.end_tooltip()
        end
    end

    imgui.table_set_column_index(13)
    if imgui.small_button("Copy##copy_" .. i) then
        UI.copy_combo_to_clipboard(combo)
    end
    
    UI.render_popup_window(combo, i)
end

function UI.render_session_table(cm)
    local table_flags = 0
    table_flags = table_flags + (imgui.TableFlags and imgui.TableFlags.RowBg or 0)
    table_flags = table_flags + (imgui.TableFlags and imgui.TableFlags.SizingFixedFit or 0)
    
    local is_replay = (ComboManager.current_game_mode == 24)
    local headers = {}
    if not is_replay then
        headers = {"Date", "Time", "Char", "Dmg", "P1Drive", "P1Super", "P2Drive", "P2Super", "P1Pos", "P2Pos", "Adv", "Gap"}
    else
        headers = {"Round", "Time", "Char", "Dmg", "P1Drive", "P1Super", "P2Drive", "P2Super", "P1Pos", "P2Pos", "Adv", "Gap"}
    end

    if imgui.begin_table("saved_combos_table", 14, table_flags) then
        if not is_replay then
            imgui.table_setup_column(headers[1], nil, 40)
            imgui.table_setup_column(headers[2], nil, 50)
        elseif is_replay then
            imgui.table_setup_column(headers[1], nil, 41)
            imgui.table_setup_column(headers[2], nil, 35)
        end
        imgui.table_setup_column(headers[3], nil, 55)
        imgui.table_setup_column(headers[4], nil, 40)
        imgui.table_setup_column(headers[5], nil, 55)
        imgui.table_setup_column(headers[6], nil, 55)
        imgui.table_setup_column(headers[7], nil, 55)
        imgui.table_setup_column(headers[8], nil, 55)
        imgui.table_setup_column(headers[9], nil, 45)
        imgui.table_setup_column(headers[10], nil, 45)
        imgui.table_setup_column(headers[11], nil, 25)
        imgui.table_setup_column(headers[12], nil, 25)
        imgui.table_setup_column("", nil, 40)
        imgui.table_setup_column("", nil, 40)
        
        imgui.table_next_row()
        for j, header in ipairs(headers) do
            imgui.table_set_column_index(j-1)
            local label = header
            if Config.settings.sort_col == header then
                label = label .. (Config.settings.sort_dir == "asc" and " ^" or " v")
            end
            if imgui.small_button(label .. "##header_" .. header) then
                if Config.settings.sort_col == header then
                    Config.settings.sort_dir = (Config.settings.sort_dir == "asc") and "desc" or "asc"
                else
                    Config.settings.sort_col = header
                    Config.settings.sort_dir = "desc" -- First click descending
                end
                Config.save()
                cm.update_all_combos()
            end
        end
        -- Remaining two columns (buttons) have no headers
        imgui.table_set_column_index(12); imgui.text(" ")
        imgui.table_set_column_index(13); imgui.text(" ")
        
        imgui.separator()
        
        for i, combo in ipairs(cm.all_combos) do
            UI.render_session_table_row(combo, i)
        end 
        imgui.end_table()
    end
end

function UI.render_session_window()
    local cm = ComboManager
    
    if not UI.show_session then return end

    if #cm.all_combos > 0 then
        if #cm.all_combos < 10 then
            imgui.set_next_window_size(200, 0, 1 << 1)
        else
            imgui.set_next_window_size(200, UI.max_session_window_height, 0 << 1)
        end
        imgui.begin_window("Session", true, 1|8)
        imgui.spacing()
        UI.render_session_table(cm)
    else
        imgui.text("No combos in session.")
    end
    imgui.end_window()
end

function UI.render_windows()
    local cm = ComboManager

    window_font = imgui.load_font(nil, 20)
    imgui.push_font(window_font)
    
    if UI.was_key_down(F3_KEY) then
        Config.settings.show_session_window = not Config.settings.show_session_window
        Config.save()
        UI.show_session = Config.settings.show_session_window
    end
    
    -- Sync UI flags with config settings
    UI.show_session = Config.settings.show_session_window
    
    if UI.hide then
        imgui.pop_font()
        return
    end

    if #cm.all_combos > 0 then
        UI.render_session_window()
    end

    imgui.pop_font()
end

function UI.render_settings()
    local cm = ComboManager
    if imgui.tree_node("Combo Data") then
        local changed = false
        
        imgui.separator()
        imgui.text("Session Window")
        
        changed, Config.settings.show_session_window = imgui.checkbox("Toggle (F3)", Config.settings.show_session_window)
        if changed then
            Config.save()
            UI.show_session = Config.settings.show_session_window
        end

        changed, Config.settings.autosave = imgui.checkbox("Save Sessions", Config.settings.autosave)
        if changed then
            Config.save()
        end
            
        changed, Config.settings.save_training = imgui.checkbox("Save Training Combos", Config.settings.save_training)
        if changed then
            Config.save()
        end
        changed, Config.settings.show_history = imgui.checkbox("Load History", Config.settings.show_history)
        if changed then
            Config.save()
            cm.update_all_combos()
        end

        if Config.settings.show_history then
            imgui.same_line()
            imgui.set_next_item_width(60)
            changed, Config.settings.history_limit = imgui.drag_int("Limit", Config.settings.history_limit, 1, 0, 1000)
            if changed then
                Config.save()
                cm.update_all_combos()
            end
        end

        local total_count = #cm.session_combos + #cm.historical_combos
        if total_count > 0 then
            if imgui.button("Delete History") then
                imgui.open_popup("Delete Confirmation")
            end
            
            if imgui.begin_popup("Delete Confirmation") then
                imgui.text(string.format("Are you sure you want to delete %d %s?", total_count, total_count == 1 and "combo" or "combos"))
                imgui.text("This action cannot be undone.")
                if imgui.button("Yes") then
                    cm.delete_history()
                    imgui.close_current_popup()
                end
                imgui.same_line()
                if imgui.button("No") then
                    imgui.close_current_popup()
                end
                imgui.end_popup()
            end

            imgui.same_line()
            if imgui.button("Back Up") then
                UI.backup_name = os.date("%y%m%d_%H%M%S") .. "_backup.lua"
                imgui.open_popup("Back Up")
            end

            if imgui.begin_popup("Back Up") then
                imgui.text("Enter a name for the backup:")
                _, UI.backup_name = imgui.input_text("##backupname", UI.backup_name)
                if imgui.button("Save") then
                    cm.backup_history(UI.backup_name)
                    imgui.close_current_popup()
                end
                imgui.same_line()
                if imgui.button("Cancel") then
                    imgui.close_current_popup()
                end
                imgui.end_popup()
            end
        end
        imgui.separator()
        imgui.tree_pop()
    end
end

-----------------------------------------------------------------------------
-- Main
-----------------------------------------------------------------------------

Config.load()
ComboManager.load_combos()

UI.show_session = Config.settings.show_session_window

re.on_script_reset(function()
    ComboManager.save_to_file()
    ComboManager.clear_all_combos()
end)

re.on_draw_ui(function()
    UI.render_settings()
end)

re.on_frame(function()   
    local sPlayer, _, _ = GameData.get_objects()
    if not sPlayer then return end

    if sPlayer.prev_no_push_bit ~= 0 then
        SceneTracker.check_scene_change()
        local p1, p2, match_data = GameData.process_battle_info()
        if p1 and p2 then
            ComboManager.update_state(p1, p2, match_data)
            UI.render_windows()
        end
    end
end)