local sdk = sdk
local re = re
local log = log
local thread = thread

local LOG_PREFIX = "[ShowHP] "

local CONFIG_PATH = "show_hp_config.json"
local config = json.load_file(CONFIG_PATH) or {}
config.show_total = config.show_total ~= false
config.show_max = config.show_max ~= false
config.show_percentage = config.show_percentage ~= false

local function save_config()
    json.dump_file(CONFIG_PATH, config)
end

local HIDE_PLAYER1 = false
local HIDE_PLAYER2 = false

local state = {
    pending_player_name_hud = nil,
    pending_player_name_probe = nil,
    configured_hud_address = nil,
    player_name_hud = nil,
    player1_text_control = nil,
    player2_text_control = nil,
    last_player1_text = nil,
    last_player2_text = nil,
    logged_update_error = false,
    reacquire_cooldown = 0,
    current_frame = 0,
    start_frame = 0,
}

-- When the script is reset or reloaded (e.g. while a battle is active), the
-- dying instance must stop using its cached battle HUD text controls: they can
-- be freed while the battle HUD is being torn down, and writing to a freed
-- control raises an error that disables the whole main Lua state.
re.on_script_reset(function()
    state.pending_player_name_hud = nil
    state.pending_player_name_probe = nil
    state.configured_hud_address = nil
    state.player_name_hud = nil
    state.player1_text_control = nil
    state.player2_text_control = nil
    state.last_player1_text = nil
    state.last_player2_text = nil
end)

local g_battle
local player_field

local function info(message)
    log.info(LOG_PREFIX .. tostring(message))
end

-- Calls a managed method without letting an exception raised by the call (e.g.
-- a stale/freed object) escape into the callback runner, which would disable
-- all main-state Lua callbacks. Returns the method's return value, or nil if
-- the call raised.
local function safe_call(object, method_name, ...)
    local args = { ... }
    local ok, result = pcall(function()
        return object:call(method_name, table.unpack(args))
    end)
    if not ok then
        return nil
    end
    return result
end

-- Resolves a managed object's full type name, tolerating stale/freed objects
-- (dereferencing their type raises).
local function get_type_name(object)
    if not object then
        return nil
    end

    local ok, name = pcall(function()
        return object:get_type_definition():get_full_name()
    end)
    if not ok then
        return nil
    end

    return name
end

local function configure_text(text, hidden)
    if not text then return end

    safe_call(text, "set_Visible", not hidden)
    safe_call(text, "set_ForceInvisible", hidden)
end

-- Returns the new last-message value when the text is (or already is) up to
-- date, or nil when the control is missing or stale so the caller drops it and
-- the reacquire path re-syncs.
local function apply_message_if_changed(text, message, last_message)
    if not text then
        return nil
    end

    if message == last_message then
        return last_message
    end

    if not safe_call(text, "set_Message(System.String)", message) then
        return nil
    end

    safe_call(text, "refresh()")

    return message
end

local function format_hp_display(current, max, player_index)
    local percent = max > 0 and (current * 100.0 / max) or 0.0
    local percent_number = string.format("%.1f", percent)
    local hidden_tenths = percent_number:sub(-2) == ".0"
    if hidden_tenths then
        percent_number = percent_number:sub(1, -3)
    end
    local percent_bare = percent_number .. "%"
    local current_text = tostring(current)
    local max_text = config.show_max and tostring(max) or nil
    local fraction_text = max_text and (current_text .. " / " .. max_text) or current_text
    local text = ""

    if config.show_total and config.show_percentage then
        local percent_text = "(" .. percent_bare .. ")"
        if config.mirrored_layout then
            text = player_index == 0
                and fraction_text .. "  " .. percent_text
                or percent_text .. "  " .. fraction_text
        else
            text = fraction_text .. "  " .. percent_text
        end
    elseif config.show_total then
        text = fraction_text
    elseif config.show_percentage then
        text = percent_bare
    else
        text = ""
    end

    return text
end

g_battle = sdk.find_type_definition("gBattle")
if g_battle then
    player_field = g_battle:get_field("Player")
end

local function get_display_text(player_index)
    local ok, text = pcall(function()
        local player = nil

        if player_field then
            local s_player = player_field:get_data(nil)
            if s_player then
                player = s_player:call(player_index == 0 and "get1P" or "get2P")
            end
        end

        if player then
            local current = tonumber(player:call("getVitalNew"))
            local max = tonumber(player:call("getVitalMax"))

            if current ~= nil and max ~= nil then
                return format_hp_display(current, max, player_index)
            end
        end

        return ""
    end)

    if not ok then
        return ""
    end

    return text
end

local function update_cached_text_controls()
    local player1_text = get_display_text(0)
    local player2_text = get_display_text(1)

    local last1 = apply_message_if_changed(
        state.player1_text_control,
        player1_text,
        state.last_player1_text
    )
    if last1 then
        state.last_player1_text = last1
    elseif state.player1_text_control then
        -- Stale/dead control; drop it and let the reacquire path re-sync.
        state.player1_text_control = nil
        state.last_player1_text = nil
    end

    local last2 = apply_message_if_changed(
        state.player2_text_control,
        player2_text,
        state.last_player2_text
    )
    if last2 then
        state.last_player2_text = last2
    elseif state.player2_text_control then
        -- Stale/dead control; drop it and let the reacquire path re-sync.
        state.player2_text_control = nil
        state.last_player2_text = nil
    end
end

-- Fetches a text control from the HUD's mTextName array, validating that the
-- slot holds a live via.gui.Text (battle HUD text objects can be freed, or not
-- yet created, while the HUD is being set up or torn down).
local function get_text_control(array, index)
    local ok, text = pcall(function()
        return array:call("GetValue", index)
    end)
    if not ok then
        return nil
    end

    if not text or text:get_address() == 0 then
        return nil
    end

    if get_type_name(text) ~= "via.gui.Text" then
        return nil
    end

    return text
end

local function apply_to_hud(hud, configure_layout)
    local ok, array = pcall(function()
        return hud:get_field("mTextName")
    end)
    if not ok or not array then
        return
    end

    local text1 = get_text_control(array, 0)
    local text2 = get_text_control(array, 1)
    if not text1 or not text2 then
        return
    end

    state.player_name_hud = hud
    state.player1_text_control = text1
    state.player2_text_control = text2
    state.last_player1_text = nil
    state.last_player2_text = nil

    configure_text(state.player1_text_control, HIDE_PLAYER1)
    configure_text(state.player2_text_control, HIDE_PLAYER2)
    update_cached_text_controls()

    if configure_layout then
        state.configured_hud_address = hud:get_address()
    end
end

local function apply_pending()
    local address = state.pending_player_name_hud
    state.pending_player_name_hud = nil
    if not address then return end

    local hud = sdk.to_managed_object(address)
    if hud and get_type_name(hud) == "app.UIBattleHud_PlayerName" then
        apply_to_hud(hud, true)
    end
end

local function find_player_name_hud(list, nested)
    if not list then return nil end
    local count = tonumber(list:call("get_Count")) or 0
    for index = 0, count - 1 do
        local item = list:call("get_Item", index)
        local hud = item
        if nested then
            local widget_ctrl = item:get_field("<WidgetCtrl>k__BackingField")
            hud = widget_ctrl and widget_ctrl:get_field("<Hud>k__BackingField")
        end

        if get_type_name(hud) == "app.UIBattleHud_PlayerName" then
            return hud
        end
    end

    return nil
end

local function try_reacquire_existing_hud()
    if state.reacquire_cooldown > 0 then
        state.reacquire_cooldown = state.reacquire_cooldown - 1
        return
    end

    state.reacquire_cooldown = 30

    local ok, err = pcall(function()
        local gui_manager = sdk.get_managed_singleton("app.GuiManager")
        if not gui_manager then return end

        local gui_hud = gui_manager:get_field("<Hud>k__BackingField")
        if not gui_hud then return end

        local battle_hud_manager = gui_hud:call("GetHudManagerBase", 0)
        if not battle_hud_manager then return end

        local history_huds = battle_hud_manager:get_field("HistoryHuds")
        local hud = find_player_name_hud(history_huds, false)
        if not hud then
            local manage_units = battle_hud_manager:get_field("mManageUnits")
            hud = find_player_name_hud(manage_units, true)
        end

        if hud then
            apply_to_hud(hud, true)
        end
    end)

    if not ok then
        info("reacquire failed: " .. tostring(err))
    end
end

local function capture_pending(args, field_name)
    local storage = thread.get_hook_storage()
    if storage then
        storage[field_name] = args[2]
    end
end

local function consume_pending(field_name)
    local storage = thread.get_hook_storage()
    if not storage then
        return nil
    end

    local value = storage[field_name]
    storage[field_name] = nil
    return value
end

local function setup_hook(method_name, pre, post)
    local type_definition = sdk.find_type_definition("app.UIBattleHud_PlayerName")
    local method = type_definition and type_definition:get_method(method_name)
    if method then
        sdk.hook(method, pre, post)
    end
end


setup_hook("FlowEvent_Setup", function(args)
    capture_pending(args, "show_hp_setup")
end, function(retval)
    apply_pending()
    return retval
end)

setup_hook("SetupByBattleType", function(args)
    capture_pending(args, "show_hp_setup")
end, function()
    apply_pending()
end)

setup_hook("ActivateBattleHud", function(args)
    capture_pending(args, "show_hp_setup")
end, function()
    apply_pending()
end)

setup_hook("IsDispDisable", function(args)
    capture_pending(args, "show_hp_probe")
end, function(retval)
    local address = consume_pending("show_hp_probe")
    if not address then
        return retval
    end

    local hud = sdk.to_managed_object(address)
    if hud and get_type_name(hud) == "app.UIBattleHud_PlayerName" then
        if address ~= state.configured_hud_address
            or not state.player1_text_control
            or not state.player2_text_control then
            apply_to_hud(hud, true)
        else
            state.player_name_hud = hud
        end
    end

    return retval
end)

re.on_pre_application_entry("UpdateBehavior", function()
    state.current_frame = state.current_frame + 1

    if not state.player1_text_control
        or not state.player2_text_control then
        try_reacquire_existing_hud()
        return
    end

    update_cached_text_controls()
end)

local function calc_combo_content_width(items)
    local max_w = 0
    for _, item in ipairs(items) do
        local text_size = imgui.calc_text_size(item)
        if text_size and text_size.x > max_w then
            max_w = text_size.x
        end
    end

    return max_w + 30
end

local layout_items = {"Mirrored", "Consistent"}

re.on_draw_ui(function()
    if imgui.tree_node("Show HP") then
        local changed = false

        changed, config.show_total = imgui.checkbox("Total", config.show_total)
        if changed then save_config() end

        if config.show_total then
            imgui.same_line()
            local max_changed, max_val = imgui.checkbox("Max", config.show_max)
            if max_changed then
                config.show_max = max_val
                save_config()
            end
        end

        changed, config.show_percentage = imgui.checkbox("Percentage", config.show_percentage)
        if changed then save_config() end

        local layout_current = config.mirrored_layout and 1 or 2
        imgui.text("Layout")
        imgui.same_line()
        imgui.set_next_item_width(calc_combo_content_width(layout_items))
        local layout_changed, layout_new_idx = imgui.combo("##Layout", layout_current, layout_items)
        if layout_changed then
            config.mirrored_layout = (layout_new_idx == 1)
            save_config()
        end

        imgui.tree_pop()
    end
end)

state.start_frame = state.current_frame
info("Loaded")