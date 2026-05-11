local sdk = sdk
local imgui = imgui
local re = re
local thread = thread
local reframework = reframework

local CONFIG_PATH = "replay_id_to_clipboard.json"
local MOD_NAME = "Replay ID To Clipboard"
local FLAG_TRANSPARENT = 0x81
local KEY_CTRL = 0x11
local KEY_N = 0x4E
local KEY_M = 0x4D

local changed
local training_manager
local battle_replay_data_manager
local replay_list
local replay_id
local display_size
local window_pos
local is_replay = false
local this = {}
local window_width = 50

this.config = {}
this.config.window_show = this.config.window_show or true
this.config.prevent_skip = this.config.prevent_skip or false
this.is_opened = false
this.needs_dismiss = false
this.key_ready = true

local function setup_hook(type_name, method_name, pre_func, post_func)
    local type_def = sdk.find_type_definition(type_name)
    if type_def then
        local method = type_def:get_method(method_name)
        if method then
            sdk.hook(method, pre_func, post_func)
        end
    end
end

setup_hook("app.battle.bBattleFlow", "endReplay", nil, function()
    is_replay = false
    this.is_opened = false
    window_pos = nil
end)

setup_hook("app.battle.bBattleFlow", "updateReplayRoundResult", nil, function(retval)
    return is_replay and sdk.to_ptr(2) or retval
end)

setup_hook("app.battle.bBattleFlow", "updateReplayKO", nil, function(retval)
    return (is_replay and not this.config.prevent_skip) and sdk.to_ptr(2) or retval
end)

setup_hook("nBattle.sPlayer", "IsDemoCancel", nil, function(retval)
    return is_replay and sdk.to_ptr(true) or retval
end)

setup_hook("app.esports.bBattleFighterEmoteFlow", "setup", function(args)
    thread.get_hook_storage()["this"] = sdk.to_managed_object(args[2])
end, function(retval)
    local obj = thread.get_hook_storage()["this"]
    if obj and obj.mInputType == 3 and not is_replay then
        is_replay = true
        if this.config.window_show then
            window_pos = nil
            this.is_opened = true
        end
        obj.mWaitTime = 0.0016
    end
    return is_replay and sdk.to_ptr(2) or retval
end)

setup_hook("app.esports.bBattleFighterEmoteFlow", "playTimeline", nil, function(retval)
    return is_replay and sdk.to_ptr(2) or retval
end)

setup_hook("app.esports.bBattleFighterEmoteFlow", "fadeOut", nil, function(retval)
    return is_replay and sdk.to_ptr(2) or retval
end)

setup_hook("app.esports.bBattleFighterEmoteFlow", "releaseWait", nil, function(retval)
    return is_replay and sdk.to_ptr(2) or retval
end)

local function get_game_mode()
    training_manager = sdk.get_managed_singleton("app.training.TrainingManager")
    return training_manager:get_field("_GameMode")
end

-- TODO Find Replay ID value when playing directly from Training Mode
local function get_replay_id()
    battle_replay_data_manager = sdk.get_managed_singleton("app.BattleReplayDataManager")
    if battle_replay_data_manager then
        replay_list = battle_replay_data_manager._ReplayList
        if replay_list and replay_list._items and #replay_list._items > 0 then
            replay_id = replay_list._items[0]:get_field("ReplayID") or ""
        end
    end
end

local function set_window_pos()
    if not window_pos then
        display_size = imgui.get_display_size()
        window_pos = {(display_size.x * .5) - window_width, display_size.y * .004}
        imgui.set_next_window_size(window_width, 0)
        imgui.set_next_window_pos(window_pos)
    end
end

local function build_hotkeys()
    if not this.key_ready and not reframework:is_key_down(KEY_N) and not reframework:is_key_down(KEY_M) then
        this.key_ready = true
    end

    if this.key_ready and reframework:is_key_down(KEY_CTRL) and reframework:is_key_down(KEY_N) then
        sdk.copy_to_clipboard(replay_id)
        this.key_ready = false
    end

    if this.key_ready and reframework:is_key_down(KEY_CTRL) and reframework:is_key_down(KEY_M) then
        this.config.window_show = not this.config.window_show
        changed = true
        this.key_ready = false
        
        if this.config.window_show then
            this.is_opened = true
        else
            this.is_opened = false
            window_pos = nil
        end
    end
end

local function build_window()
    set_window_pos()
    imgui.begin_window(MOD_NAME, nil, 1| 0x10160)
    
    if replay_id and replay_id ~= "" then
        local clicked, value = imgui.button(replay_id, this.config.prevent_skip)
        if clicked then
            sdk.copy_to_clipboard(replay_id)
        end
        
        if imgui.is_item_hovered() then
            imgui.begin_tooltip()
            imgui.text("Click to copy")
            imgui.text("Hotkey: Ctrl+N")
            imgui.end_tooltip()
        end
    end
    
    imgui.end_window()
end

re.on_frame(function()
    if is_replay then
        get_replay_id()        
        build_hotkeys()

        if this.is_opened and this.config.window_show and replay_id ~= "" then
            build_window() 
        end
    end
end)