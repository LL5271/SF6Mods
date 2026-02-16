
local CONFIG_PATH = "attack_info.json"
local SAVE_DELAY = 0.5
local LEFT_CLICK = 0x01
local RIGHT_CLICK = 0x02
local F2_KEY = 0x71
local CTRL_KEY = 0x11

local Config, Utils, GameObjects, ComboData, UI = {}, {}, {}, {}, {}

-------------------------
-- Config
-------------------------

Config.initialized = false
Config.settings = {
    toggle_all = true,
    toggle_p1 = true,
    toggle_p2 = true,
    toggle_minimal_view_p1 = true,
    toggle_minimal_view_p2 = true,
    toggle_show_empty_p1 = false,
    toggle_show_empty_p2 = false,
    combo_timer_duration = 10,
}

function Config.load()
    local loaded_settings = json.load_file(CONFIG_PATH)
    if loaded_settings then
        for k, v in pairs(loaded_settings) do Config.settings[k] = v end
    else Config.save() end
end

function Config.save() json.dump_file(CONFIG_PATH, Config.settings) end

function Config.init()
    if not Config.initialized then
        Utils.setup_hook("app.training.TrainingManager", "BattleStart", nil, function() ComboData.default_state() end)
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

function Utils.setup_hook(type_name, method_name, pre_func, post_func)
    local type_def = sdk.find_type_definition(type_name)
    if type_def then
        local method = type_def:get_method(method_name)
        if method then sdk.hook(method, pre_func, post_func) end
    end
end

-------------------------
-- GameObjects
-------------------------

GameObjects.TrainingManager = sdk.get_managed_singleton("app.training.TrainingManager")
GameObjects.PauseManager = sdk.get_managed_singleton("app.PauseManager")
GameObjects.gBattle = sdk.find_type_definition("gBattle")
GameObjects.PlayerField = GameObjects.gBattle:get_field("Player")
GameObjects.TeamField = GameObjects.gBattle:get_field("Team")

function GameObjects.get_objects()
    local sPlayer = GameObjects.PlayerField:get_data()
    if not sPlayer then return nil, nil, nil end
    local sTeam = GameObjects.TeamField:get_data()
    return sPlayer, sPlayer.mcPlayer, sTeam and sTeam.mcTeam or nil
end

function GameObjects.map_player_data(cPlayer, cTeam)
    local data_vals = {}
    for player_index = 0, 1 do
        local player = cPlayer[player_index]
        if not player then return {} end
        local team = cTeam and cTeam[player_index] or nil
        local data = {}
        data.hp_current = player.vital_new or 0
        data.hp_max = player.vital_max or 0
        data.dir = Utils.bitand(player.BitValue or 0, 128) == 128
        data.drive_adjusted = (player.incapacitated) and (player.focus_new - 60000) or player.focus_new
        data.stance = player.pose_st
        data.super = team and team.mSuperGauge or 0
        data.combo_count = team and team.mComboCount or 0
        data.death_count = team and team.mDeathCount or 0
        data.combo_damage = team and team.mComboDamage or 0
        data.down_count = team and team.mDownCount or 0
        data.pos_x = player.pos and (player.pos.x.v / 65536.0) or 0
        data.gap = (player.vs_distance and player.vs_distance.v or 0) / 65536.0
        data.advantage = 0
        if GameObjects.TrainingManager and GameObjects.TrainingManager._tCommon then
            local snap = GameObjects.TrainingManager._tCommon.SnapShotDatas
            if snap and snap[0] then
                local meter = snap[0]._DisplayData.FrameMeterSSData.MeterDatas
                if meter and meter[player_index] then
                    local stun_str = string.gsub(meter[player_index].StunFrame or "0", "F", "")
                    data.advantage = tonumber(stun_str) or 0
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
	return not (pause_type_bit == 64 or pause_type_bit == 2112)
end

-------------------------
-- ComboData Logic
-------------------------

function ComboData.default_state()
    ComboData.player_states = {
        [0] = { started = false, finished = false, attacker = 0, start = {}, finish = {}, timer_remaining = nil },
        [1] = { started = false, finished = false, attacker = 1, start = {}, finish = {}, timer_remaining = nil },
    }
    ComboData.p1_prev, ComboData.p2_prev = {}, {}
end

function ComboData.update_state(p1, p2)
    for i = 0, 1 do
        local state = ComboData.player_states[i]
        local atk, def = (i == 0 and p1 or p2), (i == 0 and p2 or p1)
        local def_prev = (i == 0 and ComboData.p2_prev or ComboData.p1_prev)

        if not state.started and atk.combo_count > 0 and ComboData.p1_prev.hp_current then
            state.started, state.finished = true, false
            state.start = { p1 = Utils.deep_copy(ComboData.p1_prev), p2 = Utils.deep_copy(ComboData.p2_prev) }
        end

        if state.started then
            state.finish = { p1 = Utils.deep_copy(p1), p2 = Utils.deep_copy(p2) }
            if atk.combo_count == 0 or def.death_count ~= def_prev.death_count then
                state.finished, state.started = true, false
                if Config.settings.combo_timer_duration > 0 then
                    state.timer_remaining = Config.settings.combo_timer_duration
                end
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
UI.key_ready = false
UI.right_click_this_frame = false
UI.combo_window_fixed_width = 0
UI.large_font = 28
UI.medium_font = 22
UI.small_font = 15
UI.header_labels = {
    "Damage","P1 Drive","P1 Super","P2 Drive","P2 Super", "P1 Carry","P2 Carry","Gap", "Adv"}
UI.gradient_max = {100, 10000, 60000, 30000, 60000, 30000, 1530, 1530, 490, 80} -- First value is padding
UI.col_widths = {55, 70, 70, 70, 70, 70, 53, 53, 53, 70} -- First value is padding

for _, w in ipairs(UI.col_widths) do
    UI.combo_window_fixed_width = UI.combo_window_fixed_width + w
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

function UI.save_handler()
    if UI.save_pending then
        UI.save_timer = UI.save_timer - (1.0 / 60.0)
        if UI.save_timer <= 0 then Config.save() end
    end
end

function UI.get_font_size(size)
    return imgui.push_font(imgui.load_font(nil, size))
end

function UI.get_large_font() return UI.get_font_size(UI.large_font) end
function UI.get_medium_font() return UI.get_font_size(UI.medium_font) end
function UI.get_small_font() return UI.get_font_size(UI.small_font) end

function UI.center_text(text, column_width, draw_fn)
    local text_size = imgui.calc_text_size(text)
    local cursor = imgui.get_cursor_pos()
    imgui.set_cursor_pos(Vector2f.new(
        cursor.x + (column_width - text_size.x) * 0.5,
        cursor.y
    ))
    draw_fn()
end

function UI.value_to_hex_color(v, max_val)
    max_val = max_val or 7500
    local t = math.max(0, math.min(v / max_val, 1))
    local r, g, b = 0, 0, 0
    
    if t < 0.25 then
        r = 255
        g = math.floor((t / 0.25) * 255)
    else
        r = math.floor((1 - (t - 0.25) / 0.75) * 255)
        g = 255
    end
    
    return 0xFF000000 + (b << 16) + (g << 8) + r
end

function UI.process_columns(values, is_color)
    for i, v in ipairs(values) do
        imgui.table_set_column_index(i - 1)
        local w = UI.col_widths[i]
        if v ~= 0 then
            local text = string.format("%.0f", v)
            if is_color then
                local color = UI.value_to_hex_color(v, UI.gradient_max[i + 1])
                UI.center_text(text, w, function()
                    imgui.text_colored(text, color)
                end)
            else
                UI.center_text(text, w, function()
                    imgui.text(text)
                end)
            end
        elseif v == 0 then
            text = "--"
            UI.center_text(text, w, function()
                imgui.text(text)
            end)
        end
    end
end

function UI.render_combo_window_table(state)
    local is_p1 = state.attacker == 0
    local minimal_view =
        (is_p1 and Config.settings.toggle_minimal_view_p1)
        or (not is_p1 and Config.settings.toggle_minimal_view_p2)

    if imgui.begin_table(
        "combo_table_p" .. tostring(state.attacker + 1),
        9,
        4096 | 8192,
        Vector2f.new(UI.combo_window_fixed_width, 0)
    ) then
        for i, label in ipairs(UI.header_labels) do
            imgui.table_setup_column(label, 4096, UI.col_widths[i])
        end

        UI.get_small_font()
        imgui.table_next_row()
        for i, label in ipairs(UI.header_labels) do
            imgui.table_set_column_index(i - 1)
            UI.center_text(label, UI.col_widths[i], function()
                imgui.text(label)
            end)
        end
        imgui.pop_font()

        imgui.table_next_row()

        if not minimal_view then
            UI.get_medium_font()
            UI.process_columns({
                (is_p1 and state.start.p2.hp_current or state.start.p1.hp_current) or 0,
                state.start.p1.drive_adjusted or 0,
                state.start.p1.super or 0,
                state.start.p2.drive_adjusted or 0,
                state.start.p2.super or 0,
                state.start.p1.pos_x or 0,
                state.start.p2.pos_x or 0,
                0, 0
            }, false)
            imgui.pop_font()

            imgui.table_next_row()
            UI.get_medium_font()
            UI.process_columns({
                (is_p1 and state.finish.p2.hp_current or state.finish.p1.hp_current) or 0,
                state.finish.p1.drive_adjusted or 0,
                state.finish.p1.super or 0,
                state.finish.p2.drive_adjusted or 0,
                state.finish.p2.super or 0,
                state.finish.p1.pos_x or 0,
                state.finish.p2.pos_x or 0,
                0, 0
            }, false)
            imgui.pop_font()
        end

        local function adjust_drive(delta)
            return delta < 0 and (delta + 60000) or delta
        end

        imgui.table_next_row()
        UI.get_large_font()
        local function adjust_finish(finish, start)
            if finish < 0 then finish = finish + 60000 end
            return finish - start
        end
        UI.process_columns({
            (is_p1 and state.finish.p1.combo_damage or state.finish.p2.combo_damage) or 0,
            adjust_finish(state.finish.p1.drive_adjusted or 0, state.start.p1.drive_adjusted or 0),
            (state.finish.p1.super or 0) - (state.start.p1.super or 0),
            adjust_finish(state.finish.p2.drive_adjusted or 0, state.start.p2.drive_adjusted or 0),
            (state.finish.p2.super or 0) - (state.start.p2.super or 0),
            math.abs((state.finish.p1.pos_x or 0) - (state.start.p1.pos_x or 0)),
            math.abs((state.finish.p2.pos_x or 0) - (state.start.p2.pos_x or 0)),
            (is_p1 and state.finish.p1.gap or state.finish.p2.gap) or 0,
            (is_p1 and state.finish.p1.advantage or state.finish.p2.advantage) or 0,
        }, true)
        imgui.pop_font()

        imgui.end_table()
    end
end

function UI.render_player_combo_window(player_index, title, x, y, toggle_setting, minimal_setting)
    local state = ComboData.player_states[player_index]
    if not (state.started or state.finished) then return end
    
    if UI.should_hide_combo_window(state) then
        state.finished = false
        state.timer_remaining = nil
        return
    end

    imgui.set_next_window_pos(Vector2f.new(x, y), 1 << 3)
    imgui.set_next_window_size(Vector2f.new(UI.combo_window_fixed_width, 0), 0, 1 << 1)

    if imgui.begin_window(title, true, 1 | 8 | 32) then
        if UI.is_toggle_view_clicked() then
            Config.settings[minimal_setting] = not Config.settings[minimal_setting]
            UI.mark_for_save()
        end

        UI.render_combo_window_table(state)
        imgui.end_window()
    end
end

function UI.handle_hotkeys()
    if UI.was_key_down(F2_KEY) then
        if reframework:is_key_down(CTRL_KEY) then
            local new_state = not Config.settings.toggle_minimal_view_p1
            Config.settings.toggle_minimal_view_p1 = new_state
            Config.settings.toggle_minimal_view_p2 = new_state
        else
            Config.settings.toggle_all = not Config.settings.toggle_all
        end
        UI.mark_for_save()
    end
end

function UI.render_windows()
    UI.handle_hotkeys()
    if not Config.settings.toggle_all or GameObjects.is_paused() then return end
    UI.right_click_this_frame = UI.was_key_down(RIGHT_CLICK)

    local display = imgui.get_display_size()
    local center_x, window_y = display.x * 0.5, 0
    UI.get_large_font()

    if Config.settings.toggle_p1 then
        UI.render_player_combo_window(0, "P1 Current Combo", center_x - UI.combo_window_fixed_width - 73, window_y, "toggle_p1", "toggle_minimal_view_p1")
    end

    if Config.settings.toggle_p2 then
        UI.render_player_combo_window(1, "P2 Current Combo", (center_x + 73), window_y, "toggle_p2", "toggle_minimal_view_p2")
    end
    
    imgui.pop_font()
end

function UI.in_window_range()
    local mouse = imgui.get_mouse()
    local pos = imgui.get_window_pos()
    local size = imgui.get_window_size()
    return mouse.x >= pos.x and mouse.x <= pos.x + size.x
       and mouse.y >= pos.y and mouse.y <= pos.y + size.y
end

function UI.is_toggle_view_clicked()
    if not UI.in_window_range() then return false end
    return UI.right_click_this_frame
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
    if Config.settings.combo_timer_duration <= 0 then return false end
    if not state.timer_remaining then return false end
    return state.timer_remaining <= 0
end

function UI.get_combo_window_alpha(state)
    if Config.settings.combo_timer_duration <= 0 or not state.timer_remaining then return 1.0 end
    local dim_start = math.max(0, Config.settings.combo_timer_duration - 2)
    local elapsed = Config.settings.combo_timer_duration - state.timer_remaining
    if elapsed < dim_start then
        return 1.0
    else
        return math.max(0, state.timer_remaining / 2)
    end
end

function UI.render_settings()
    if imgui.tree_node("Attack Info") then
        local changed = false
        imgui.text("Enable (F2)")
        imgui.same_line()
        changed, Config.settings.toggle_all = imgui.checkbox("##enable", Config.settings.toggle_all)
        if changed then UI.mark_for_save() end
        if Config.settings.toggle_all then
            imgui.text("Show/Hide")
            imgui.same_line()
            changed, Config.settings.toggle_p1 = imgui.checkbox("P1##show_p1", Config.settings.toggle_p1)
            if changed then UI.mark_for_save() end
            imgui.same_line()
            changed, Config.settings.toggle_p2 = imgui.checkbox("P2##show_p2", Config.settings.toggle_p2)
            if changed then UI.mark_for_save() end
            imgui.text("Minimal View")
            imgui.same_line()
            changed, Config.settings.toggle_minimal_view_p1 = imgui.checkbox("P1##minimal_p1", Config.settings.toggle_minimal_view_p1)
            if changed then UI.mark_for_save() end
            imgui.same_line()
            changed, Config.settings.toggle_minimal_view_p2 = imgui.checkbox("P2##minimal_p2", Config.settings.toggle_minimal_view_p2)
            if changed then UI.mark_for_save() end
            imgui.text("Clear After:")
            imgui.same_line()
            imgui.push_item_width(30)
            changed, Config.settings.combo_timer_duration = imgui.drag_int("##combo_timer_duration", Config.settings.combo_timer_duration, 1, 0, 120)
            imgui.pop_item_width()
            imgui.same_line()
            imgui.text("Seconds")
            if changed then UI.mark_for_save() end
            imgui.same_line()
            changed = imgui.button("Clear Now")
            if changed then ComboData.default_state() end
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
    if not sPlayer then return end

    UI.update_combo_timers()
    if sPlayer.prev_no_push_bit ~= 0 then
        local p1, p2 = GameObjects.map_player_data(cPlayer, cTeam)
        ComboData.update_state(p1, p2)
        UI.render_windows()
        UI.save_handler()
    end
end)