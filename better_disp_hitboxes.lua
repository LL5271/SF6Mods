local MOD_NAME = "Better Hitbox Viewer"
local state = {}

-- ============================================================================
-- General Utilities
-- ============================================================================

local function deep_copy(obj)
	if type(obj) ~= 'table' then return obj end
	local copy = {}
	for k, v in pairs(obj) do copy[k] = deep_copy(v) end
	return copy
end

local function bitand(a, b) return (a % (b + b) >= b) and b or 0 end

local function reverse_pairs(aTable)
    local keys = {}
    for k, _ in pairs(aTable) do keys[#keys+1] = k end
    table.sort(keys, function(a, b) return a > b end)
    local n = 0
    return function()
        n = n + 1
        if n > #keys then return nil, nil end
        return keys[n], aTable[keys[n]]
    end
end

local function is_facing_right(entity)
    local bitval = entity:get_field("BitValue")
    if bitval and type(bitval) == "number" then
        return (bitand(bitval, 128) == 128)
    end
    return true
end

local function is_disabled_state()
	return not state.config.p1.toggle.toggle_show and not state.config.p2.toggle.toggle_show
end

local function setup_hook(type_name, method_name, pre_func, post_func)
	local type_def = sdk.find_type_definition(type_name)
	if type_def then
		local method = type_def:get_method(method_name)
		if method then
			sdk.hook(method, pre_func, post_func)
		end
	end
end

-- ============================================================================
-- Game Objects
-- ============================================================================

local gBattle, PauseManager, TrainingManager, bFlowManager

local function object_handler()
	if not PauseManager then 
		PauseManager = sdk.get_managed_singleton("app.PauseManager")
	end

	if not TrainingManager then
		TrainingManager = sdk.get_managed_singleton("app.training.TrainingManager")
	end

    if not bFlowManager then
        bFlowManager = sdk.get_managed_singleton("app.bFlowManager")
    end

    if gBattle then
		state.sWork = gBattle:get_field("Work"):get_data(nil)
		state.sPlayer = gBattle:get_field("Player"):get_data(nil)
        state.sSetting = gBattle:get_field("Setting"):get_data(nil)
		return
	end

	gBattle = sdk.find_type_definition("gBattle")
end

local TRAINING_MODES = {
    [1]  = true,  -- TRAINING
    [2]  = true,  -- ONLINE_TRAINING
    [10] = true,  -- WT_TRAINING
}

local function is_any_training_mode()
    if not TrainingManager then return false end
    TrainingManager:get_field("GameMode")
    return TRAINING_MODES[mode] == true
end

-- app::EGameMode
local GAME_MODES = {
    [0]  = "NONE",
    [1]  = "ARCADE",
    [2]  = "TRAINING",
    [3]  = "VERSUS_2P",
    [4]  = "VERSUS_CPU",
    [5]  = "TUTORIAL",
    [6]  = "CHARACTER_GUIDE",
    [7]  = "MISSION",
    [8]  = "DEATHMATCH",
    [9]  = "STORY",
    [10] = "STORY_TRAINING",
    [11] = "STORY_MATCH",
    [12] = "STORY_TUTORIAL",
    [13] = "STORY_SPECTATE",
    [14] = "RANKED_MATCH",
    [15] = "PLAYER_MATCH",
    [16] = "CABINET_MATCH",
    [17] = "CUSTOM_ROOM_MATCH",
    [18] = "ONLINE_TRAINING",
    [19] = "TEAMBATTLE",
    [20] = "EXAM_CPU_MATCH",
    [21] = "CABINET_CPU_MATCH",
    [22] = "LEARNING_AI_MATCH",
    [23] = "LEARNING_AI_SPECTATE",
    [24] = "REPLAY",
    [25] = "SPECTATE",
    [26] = "LOCAL_MATCH",
    [27] = "STORY_LOCAL_MATCH",
    [28] = "JOY_MATCH",
    [29] = "JOY_BATTLE",
}

local SINGLE_PLAYER_MODES = {
    1, 3, 4, 5, 6, 7, 8, 9, 10, 
    11, 12, 13, 24, 25, 26, 27
}

local function get_scene_id()
    if not bFlowManager then return nil end
    return bFlowManager:get_GameMode() or 0
end

local function is_in_battle()
    if not state.sPlayer then return false end
    for _, player in pairs(state.sPlayer.mcPlayer) do
        if player.mpActParam then return true end
    end
    return false
end

local function get_game_mode_id()
    if not state.sSetting then return 0 end
    if not is_in_battle() then return 0 end
    return state.sSetting:get_field("GameMode") or 0
end

local function get_game_mode_name()
    local mode_id = get_game_mode_id()
    return GAME_MODES[mode_id]
end

local function is_training_mode()
    local scene = get_game_mode_id()
    return scene == 2  -- TRAINING
        or scene == 18 -- ONLINE_TRAINING
        or scene == 10 -- STORY_TRAINING
end

local function is_single_player_mode()
    local mode_id = get_game_mode_id()
    return SINGLE_PLAYER_MODES[mode_id]
end

local function is_mode_allowed()
    local mode = get_game_mode_id()
    -- Training (offline, online, story)
    if mode == 2 or mode == 18 or mode == 10 then
        return state.config.options.mode_training
    end
    -- Replays
    if mode == 24 then
        return state.config.options.mode_replay
    end
    -- Local Versus (2P, local match, story local)
    if mode == 3 or mode == 26 or mode == 27 then
        return state.config.options.mode_local_versus
    end
    -- Everything else (arcade, vs cpu, tutorial, story, spectate, etc.)
    return state.config.options.mode_single_player
end

local function is_pause_menu_closed()
    local pause_type_bit = 0
    if not PauseManager then return end
    pause_type_bit = PauseManager:get_field("_CurrentPauseTypeBit")
    return pause_type_bit == 64 or pause_type_bit == 2112
end

-- ============================================================================
-- Hotkey System (hk)
-- ============================================================================
if not hk then
	local kb, mouse, pad
	local m_up, m_down, m_trig
	local gp_up, gp_down, gp_trig
	local kb_state = {down = {}, released = {}, triggered={}}
	local gp_state = {down = {}, released = {}, triggered={}}
	local mb_state = {down = {}, released = {}, triggered={}}

	local function merge_tables(table_a, table_b, no_overwrite)
		table_a = table_a or {}
		table_b = table_b or {}
		if no_overwrite then
			for key_b, value_b in pairs(table_b) do
				if table_a[key_b] == nil then
					table_a[key_b] = value_b
				end
			end
		else
			for key_b, value_b in pairs(table_b) do table_a[key_b] = value_b end
		end
		return table_a
	end

	local function merge_tables_recursively(table_a, table_b, no_overwrite)
		local searched = {}

		local function recurse(tbl_a, tbl_b)
			if searched[tbl_b] then return searched[tbl_b] end
			searched[tbl_b] = tbl_a

			if no_overwrite then
				for key_b, value_b in pairs(tbl_b) do
					if tbl_a[key_b] == nil then
						tbl_a[key_b] = type(value_b)=="table" and recurse({}, value_b) or value_b
					end
				end
			else
				for key_b, value_b in pairs(tbl_b) do
					tbl_a[key_b] = type(value_b)=="table" and recurse((type(tbl_a[key_b])=="table" and tbl_a[key_b] or {}), value_b) or value_b
				end
			end
			return tbl_a
		end
		return recurse(table_a, table_b)
	end

	local function generate_statics(typename)
		local t = sdk.find_type_definition(typename)
		local fields = t:get_fields()
		local enum = {}
		local names = {}
		for i, field in ipairs(fields) do
			if field:is_static() then
				local raw_value = field:get_data(nil)
				if raw_value ~= nil then
					local name = field:get_name()
					enum[name] = raw_value
					table.insert(names, name)
				end
			end
		end
		return enum, names
	end

	local hotkeys = {}
	local modifiers = {}
	local default_hotkeys = {}
	local backup_hotkeys = {}
	local hotkeys_down = {}
	local hotkeys_up = {}
	local hotkeys_trig = {}
	local hold_dn_times = {}
	local hold_times = {}
	local dt_rel_times = {}
	local dt_times = {}

	local keys = generate_statics("via.hid.KeyboardKey")
	local buttons = generate_statics("via.hid.GamePadButton")
	local mbuttons = generate_statics("via.hid.MouseButton")

	keys.DefinedEnter = nil
	keys.Shift = nil
	keys.LAlt, keys.RAlt, keys.Alt = keys.LMenu, keys.RMenu, keys.Menu
	keys.LMenu, keys.RMenu, keys.Menu = nil
	mbuttons.NONE = nil
	mbuttons["R Mouse"] = mbuttons.R
	mbuttons["L Mouse"] = mbuttons.L
	mbuttons["M Mouse"] = mbuttons.C
	mbuttons.R, mbuttons.L, mbuttons.C = nil
	buttons.None = nil
	buttons.RDown = 131104
	buttons.RRight = 262272
	buttons.Select = buttons.CLeft
	buttons.Start = buttons.CRight
	buttons["X (Square)"] = buttons.RLeft
	buttons["Y (Triangle)"] = buttons.RUp
	buttons["A (X)"] = buttons.RDown or buttons.Decide
	buttons["B (Circle)"] = buttons.RRight
	buttons["RB (R1)"] = buttons.RTrigTop
	buttons["RT (R2)"] = buttons.RTrigBottom
	buttons["LB (L1)"] = buttons.LTrigTop
	buttons["LT (L2)"] = buttons.LTrigBottom
	buttons.LTrigTop, buttons.RTrigTop, buttons.RTrigBottom, buttons.LTrigBottom = nil
	buttons.CLeft, buttons.CRight, buttons.RLeft, buttons.RUp, buttons.RDown, buttons.RRight, buttons.Cancel = nil

	local function setup_active_keys_tbl()
		kb_state.down = {}
		kb_state.released = {}
		kb_state.triggered = {}
		mb_state.down = {}
		mb_state.released = {}
		mb_state.triggered = {}
		gp_state.down = {}
		gp_state.released = {}
		gp_state.triggered = {}

		for _, key_name in pairs(hotkeys) do
			if buttons[key_name] ~= nil then
				gp_state.down[buttons[key_name] ] = false
				gp_state.released[buttons[key_name] ] = false
				gp_state.triggered[buttons[key_name] ] = false
			end
			if keys[key_name] ~= nil then
				kb_state.down[keys[key_name] ] = false
				kb_state.released[keys[key_name] ] = false
				kb_state.triggered[keys[key_name] ] = false
			end
			if mbuttons[key_name] ~= nil then
				mb_state.down[mbuttons[key_name] ] = false
				mb_state.released[mbuttons[key_name] ] = false
				mb_state.triggered[mbuttons[key_name] ] = false
			end
		end
	end

	local def_hk_data = {modifier_actions={}}

	local function recurse_def_settings(main_tbl, defaults_tbl)
		local searched = {}
		local function recurse(tbl, d_tbl)
			for key, value in pairs(d_tbl) do
				if type(tbl[key]) ~= type(value) then
					if type(value) == "table" and not searched[value] then
						searched[value] = true
						tbl[key] = recurse({}, value)
					else
						tbl[key] = value
					end
				elseif type(value) == "table" and not searched[value] then
					searched[value] = true
					tbl[key] = recurse(tbl[key], value)
				end
			end
			return tbl
		end
		return recurse(main_tbl, defaults_tbl)
	end

	local hk_data = def_hk_data

	local hotkey_change_callbacks = {}

	local function trigger_hotkey_change_callbacks()
		for _, cb in ipairs(hotkey_change_callbacks) do
			pcall(cb)
		end
	end

	local function find_index(tbl, value, key)
		if key ~= nil then
			for i, item in ipairs(tbl) do
				if item[key] == value then
					return i
				end
			end
		else
			for i, item in ipairs(tbl) do
				if item == value then
					return i
				end
			end
		end
	end

	local function get_button_string(action_name)
		local b1 = hotkeys[action_name.."_$_$"]; b1 = b1 and b1.." + " or ""
		local b2 = hotkeys[action_name.."_$"]; b2 = b2 and b2.." + " or ""
		return b1 .. b2 .. hotkeys[action_name]
	end

	local function reset_from_defaults_tbl(default_hotkey_table)
		for key, value in pairs(default_hotkey_table) do
			hotkeys[key] = value
			if not default_hotkey_table[key.."_$_$"] then
				hk_data.modifier_actions[key.."_$"], hk_data.modifier_actions[key.."_$_$"] = nil
			end
			if not default_hotkey_table[key.."_$"] then
				hotkeys[key.."_$"], hotkeys[key.."_$_$"] = nil
			end
		end
		json.dump_file("Hotkeys_data.json", hk_data)
		setup_active_keys_tbl()
		trigger_hotkey_change_callbacks()
	end

	local function update_hotkey_table(hotkey_table)
		for key, value in pairs(hotkeys) do
			hotkey_table[key] = value
		end
		for key in pairs(hotkey_table) do
			if hotkeys[key] == nil then
				hotkey_table[key] = nil
			end
		end
	end

	local function setup_hotkeys(hotkey_table, default_hotkey_table)
		if not default_hotkey_table then
				default_hotkey_table = {}
			for key, value in pairs(hotkey_table) do
				default_hotkey_table[key] = value or nil
			end
		end
		default_hotkeys = merge_tables(default_hotkeys, default_hotkey_table)
		for key, value in pairs(default_hotkey_table) do
			if hotkey_table[key] == nil then
				hotkey_table[key] = value or nil
			end
		end
		hotkeys = merge_tables(hotkeys, hotkey_table)
		setup_active_keys_tbl()
	end

	local function check_kb_key(key_str, check_down, check_triggered)
		local key = keys[key_str]
		if not key or not kb then return end
		local method_name = check_down==true and "isDown" or (check_down or check_triggered) and "isTrigger" or "isRelease"
		return kb:call(method_name, key)
	end

	local function check_pad_button(button_str, check_down, check_triggered)
		local button = buttons[button_str]
		if not button or not pad then return end
		local gp_button = check_down==true and gp_down or (check_down or check_triggered) and gp_trig or gp_up
		return (gp_button | button) == gp_button
	end

	local function check_mouse_button(button_str, check_down, check_triggered)
		local button = mbuttons[button_str]
		if not button or not mouse then return end
		local m_button = check_down==true and m_down or (check_down or check_triggered) and m_trig or m_up
		return (m_button | button) == m_button
	end

	local function chk_down(action_name)
		if hotkeys_down[action_name] == nil then
			local key_name = hotkeys[action_name]
			hotkeys_down[action_name] = kb_state.down[keys[key_name ] ]  or gp_state.down[buttons[key_name ] ] or mb_state.down[mbuttons[key_name ] ]
		end
		return hotkeys_down[action_name]
	end

	local function chk_up(action_name)
		if hotkeys_up[action_name] == nil then
			local key_name = hotkeys[action_name]
			hotkeys_up[action_name] = kb_state.released[keys[key_name ] ]  or gp_state.released[buttons[key_name ] ] or mb_state.released[mbuttons[key_name ] ]
		end
		return hotkeys_up[action_name]
	end

	local function chk_trig(action_name)
		if hotkeys_trig[action_name] == nil then
			local key_name = hotkeys[action_name]
			hotkeys_trig[action_name] = kb_state.triggered[keys[key_name ] ]  or gp_state.triggered[buttons[key_name ] ] or mb_state.triggered[mbuttons[key_name ] ]
		end
		return hotkeys_trig[action_name]
	end

	local function check_hotkey(action_name, check_down, check_triggered)
		local key_name = hotkeys[action_name]
		if key_name == "[Not Bound]" then return false end
		if check_down == true then
			if hotkeys_down[action_name] == nil then
				hotkeys_down[action_name] = (kb_state.down[keys[key_name ] ]  or gp_state.down[buttons[key_name ] ] or mb_state.down[mbuttons[key_name ] ]) and (not hotkeys[action_name.."_$"] or check_hotkey(action_name.."_$", true))
			end
			return hotkeys_down[action_name]
		elseif check_triggered or type(check_down) ~= "nil" then
			if hotkeys_trig[action_name] == nil then
				hotkeys_trig[action_name] = (kb_state.triggered[keys[key_name ] ]  or gp_state.triggered[buttons[key_name ] ] or mb_state.triggered[mbuttons[key_name ] ]) and (not hotkeys[action_name.."_$"] or check_hotkey(action_name.."_$", true))
			end
			return hotkeys_trig[action_name]
		elseif hotkeys_up[action_name] == nil then
			hotkeys_up[action_name] = (kb_state.released[keys[key_name ] ]  or gp_state.released[buttons[key_name ] ] or mb_state.released[mbuttons[key_name ] ]) and (not hotkeys[action_name.."_$"] or check_hotkey(action_name.."_$", true))
		end
		return hotkeys_up[action_name]
	end

	local function check_doubletap(action_name, check_released)
		if check_hotkey(action_name, nil, not check_released) then
			local times = check_released and dt_rel_times or dt_times
			local start = times[action_name]
			if start and os.clock() - start < 0.25 then
				return true
			end
			times[action_name] = os.clock()
		end
	end

	local function check_hold(action_name, check_down, time_limit)
		local times = check_down and hold_dn_times or hold_times
		if check_hotkey(action_name, true) then
			local start = times[action_name]
			times[action_name] = start or os.clock()
			if start and start ~= 0 and os.clock() - start >= (time_limit or 0.5) then
				if not check_down then  times[action_name] = 0  end
				return true
			end
		else
			times[action_name] = nil
		end
	end

	-- Keys permitted in modifier slots: Ctrl, Shift, Alt variants only (gamepad buttons always allowed)
	local valid_modifier_keys = {
		LControl=true, RControl=true, Control=true,
		LShift=true, RShift=true,
		LAlt=true, RAlt=true, Alt=true,
	}

	local function hotkey_setter(action_name, hold_action_name, fake_name, title_tooltip)

		local key_updated = false
		local is_down = check_hotkey(action_name, true) and (not hold_action_name or check_hotkey(hold_action_name, true))
		local disp_name = (fake_name and ((type(fake_name)~="string") and "" or fake_name)) or action_name
		local is_mod_1 = (action_name:sub(-2, -1) == "_$")
		local is_mod_2 = (action_name:sub(-4, -1) == "_$_$")
		local default = default_hotkeys[action_name]

		local had_hold = not not hold_action_name
		hold_action_name = hold_action_name and ((hotkeys[hold_action_name] ~= "[Not Bound]") and (hotkeys[hold_action_name] ~= "[Press Input]")) and hold_action_name
		local modifier_hotkey = hold_action_name and get_button_string(hold_action_name)
		modifiers[action_name] = hold_action_name

		if is_down then imgui.begin_rect(); imgui.begin_rect() end
		imgui.push_id(action_name)
			hotkeys[action_name] = hotkeys[action_name] or default
			if hotkeys[action_name] == "[Press Input]" then
				local up = pad and pad:call("get_ButtonUp")
				if up and up ~= 0 then
					for button_name, id in pairs(buttons) do
						if (up | id) == up then
							hotkeys[action_name] = button_name
							key_updated = true
							goto exit
						end
					end
				end
				if not (is_mod_1 or is_mod_2) and mouse and m_up and m_up ~= 0 then
					for button_name, id in pairs(mbuttons) do
						if (m_up | id) == m_up then
							hotkeys[action_name] = button_name
							key_updated = true
							goto exit
						end
					end
				end
				for key_name, id in pairs(keys) do
					if kb and kb:call("isRelease", id) then
						if (not (is_mod_1 or is_mod_2)) or valid_modifier_keys[key_name] then
							hotkeys[action_name] = key_name
							key_updated = true
							goto exit
						end
					end
				end

			end
			::exit::

			if disp_name ~= "" then
				imgui.text((disp_name) .. ": ")
				if title_tooltip and imgui.is_item_hovered() then
					imgui.set_tooltip(title_tooltip)
				end
				imgui.same_line()
			end

			if key_updated then
				if is_mod_1 then
					hk_data.modifier_actions[action_name] = hotkeys[action_name]
					json.dump_file("Hotkeys_data.json", hk_data)
				end
				setup_active_keys_tbl()
				trigger_hotkey_change_callbacks()
			end

			if not is_mod_2 and hotkeys[action_name.."_$"] then
				if hotkey_setter(action_name.."_$", nil, true) then key_updated = true end
				imgui.same_line()
				imgui.text("+")
				imgui.same_line()
			end

			if imgui.button( ((modifier_hotkey and (modifier_hotkey .. " + ")) or "") .. hotkeys[action_name]) then
				if hotkeys[action_name] == "[Press Input]" then
					hotkeys[action_name] = backup_hotkeys[action_name]
				else
					for name, action_n in pairs(hotkeys) do
						if action_n == "[Press Input]" then
							hotkeys[name] = backup_hotkeys[name]
						end
					end
					backup_hotkeys[action_name] = hotkeys[action_name]
					hotkeys[action_name] = "[Press Input]"
				end
			end
			if imgui.is_item_hovered() then
				imgui.set_tooltip(hotkeys[action_name]=="[Press Input]" and "Click to cancel" or "Set " .. (is_mod_1 and "Modifier" or "Hotkey").."\nRight click for options")
			end
			if imgui.begin_popup_context_item(action_name) then
				if hotkeys[action_name] ~= "[Not Bound]" and imgui.menu_item("Clear") then
					if is_mod_1 then
						hotkeys[action_name], hk_data.modifier_actions[action_name], hotkeys[action_name.."_$"], hk_data.modifier_actions[action_name.."_$"]  = hotkeys[action_name.."_$"], hk_data.modifier_actions[action_name.."_$"]
						json.dump_file("Hotkeys_data.json", hk_data)
					else
						hotkeys[action_name] = "[Not Bound]"
					end
					key_updated = true
					setup_active_keys_tbl()
					trigger_hotkey_change_callbacks()
				end
				if not is_mod_2 and default_hotkeys[action_name] and imgui.menu_item("Reset to Default") then
					hotkeys[action_name] = default_hotkeys[action_name]
					key_updated = true
					setup_active_keys_tbl()
					trigger_hotkey_change_callbacks()
				end
				if not is_mod_1 and not is_mod_2 and hotkeys[action_name] ~= "[Not Bound]" and imgui.menu_item((hotkeys[action_name.."_$"] and "Disable " or "Enable ") .. "Modifier") then
					hotkeys[action_name.."_$"] = not hotkeys[action_name.."_$"] and ((pad and pad:get_Connecting() and "LT (L2)") or "LAlt") or nil
					hk_data.modifier_actions[action_name.."_$"] = hotkeys[action_name.."_$"]
					json.dump_file("Hotkeys_data.json", hk_data)
					setup_active_keys_tbl()
					trigger_hotkey_change_callbacks()
					key_updated = true
				end
				imgui.end_popup()
			end
		imgui.pop_id()
		if is_down then imgui.end_rect(1); imgui.end_rect(2) end

		return key_updated
	end

	local kb_singleton = sdk.get_native_singleton("via.hid.Keyboard")
	local gp_singleton = sdk.get_native_singleton("via.hid.Gamepad")
	local mb_singleton = sdk.get_native_singleton("via.hid.Mouse")
	local kb_typedef = sdk.find_type_definition("via.hid.Keyboard")
	local gp_typedef = sdk.find_type_definition("via.hid.GamePad")
	local mb_typedef = sdk.find_type_definition("via.hid.Mouse")

	local function update_states()
		hk.kb = sdk.call_native_func(kb_singleton, kb_typedef, "get_Device")
		hk.pad = sdk.call_native_func(gp_singleton, gp_typedef, "getMergedDevice", 0)
		hk.mouse = sdk.call_native_func(mb_singleton, mb_typedef, "get_Device")
		kb, pad, mouse = hk.kb, hk.pad, hk.mouse
		hotkeys_down, hotkeys_up, hotkeys_trig = {}, {}, {}

		if kb then
			for key, state in pairs(kb_state.released) do
				kb_state.released[key]  = kb:call("isRelease", key)
				kb_state.down[key] 		= kb:call("isDown", key)
				kb_state.triggered[key] = kb:call("isTrigger", key)
			end
		end

		if mouse then
			m_up, m_down, m_trig = mouse:call("get_ButtonUp"), mouse:call("get_Button"), mouse:call("get_ButtonDown")
			for button, state in pairs(mb_state.released) do
				mb_state.released[button]	= ((m_up | button) == m_up)
				mb_state.down[button] 		= ((m_down | button) == m_down)
				mb_state.triggered[button]  = ((m_trig | button) == m_trig)
			end
		end

		if pad then
			gp_up, gp_down, gp_trig = pad:call("get_ButtonUp"), pad:call("get_Button"), pad:call("get_ButtonDown")
			for button, state in pairs(gp_state.released) do
				gp_state.released[button] 	= ((gp_up | button) == gp_up)
				gp_state.down[button] 		= ((gp_down | button) == gp_down)
				gp_state.triggered[button]  = ((gp_trig | button) == gp_trig)
			end
		end
	end

	re.on_application_entry("UpdateHID", function()
		update_states()
	end)

	-- Script functionality:
	hk = hk or {
		kb = kb, 													-- Keyboard device Managed Object, updated every frame
		mouse = mouse, 												-- Mouse device Managed Object, updated every frame
		pad = pad, 													-- Gamepad device Managed Object, updated every frame

		keys = keys, 												-- Enum of keyboard key names vs key IDs (some tweaked names)
		buttons = buttons, 											-- Enum of gamepad button names vs button IDs (some tweaked names)
		mbuttons = mbuttons, 										-- Enum of mouse button names vs button IDs (some tweaked names)

		hotkeys = hotkeys, 											-- Table of current action names vs button strings
		default_hotkeys = default_hotkeys, 							-- Table of default action names vs button strings

		kb_state = kb_state,										-- Table with state (up/down/triggered) of all used keyboard keys, updated every frame
		gp_state = gp_state, 										-- Table with state (up/down/triggered) of all used gamepad buttons, updated every frame
		mb_state = mb_state, 										-- Table with state (up/down/triggered) of all used mouse buttons, updated every frame

		recurse_def_settings = recurse_def_settings, 				-- Fn takes a table 'tbl' and its paired 'defaults_tbl' and copies mismatched/missing fields from defaults_tbl to tbl, then does the same for any child tables of defaults_tbl
		find_index = find_index, 									-- Fn takes a table and a value (and optionally a key), then finds the index containing a value (or of the value containing that value as a field 'key') in that table
		merge_tables = merge_tables,								-- Fn takes table A and B then merges table A into table B
		merge_tables_recursively = merge_tables_recursively,		-- Fn takes table A and B then merges table A into table B and does the same for any child tables in the table
		generate_statics = generate_statics, 						-- Fn takes a typedef name for a System.Enum and returns a lua table from it

		setup_hotkeys = setup_hotkeys, 								-- Fn takes a table of hotkeys (action names vs button names) and a paired table of default_hotkeys and sets them up for use in this script
		reset_from_defaults_tbl = reset_from_defaults_tbl, 			-- Fn takes a defaults table and resets all matching hotkeys in this script to the button strings from it
		update_hotkey_table = update_hotkey_table, 					-- Fn takes a table of hotkeys (action names vs button names) from an outside script and updates the keys internally in this script to match
		get_button_string = get_button_string, 						-- Fn takes and action name and returns the full button combination required to trigger an action, including modifiers if they exist

		hotkey_setter = hotkey_setter, 								-- Fn takes an action name and displays an imgui button that you can click then and press an input to assign that input to that action name. Returns true if updated

		check_hotkey = check_hotkey, 								-- Fn checks if an input (by action name) is just released, and also if its modifiers are down (if they exist). Send "true" as 2nd argument to check if input is down, "1" or use argument#3 to check if just-triggered
		check_doubletap = check_doubletap,							-- Fn uses 'check_hotkey' to check if an input (by action name) has been pressed twice in the past 0.25 seconds
		check_hold = check_hold,									-- Fn uses 'check_hotkey' to check if an input (by action name) has been held for as long as its argument#2

		chk_up = chk_up, 											-- Fn checks if an input (by action name) is released
		chk_down = chk_down, 										-- Fn checks if an input (by action name) is down
		chk_trig = chk_trig, 										-- Fn checks if an input (by action name) is just pressed

		check_kb_key = check_kb_key,								-- Fn checks if a keyboard input is released, down or triggered (by key name)
		check_mouse_button = check_mouse_button,					-- Fn checks if a mouse input is released, down or triggered (by mbutton name)
		check_pad_button = check_pad_button,						-- Fn checks if a gamepad input is released, down or triggered (by button name) (such as imgui focus) was removed mid-frame

		register_hotkey_change_callback = function(cb)
			table.insert(hotkey_change_callbacks, cb)
		end,

		sync_modifiers_from_hotkeys = function()
			hk_data.modifier_actions = {}
			for action, key in pairs(hotkeys) do
				if action:match("_%$$$") then
					hk_data.modifier_actions[action] = key
				end
			end
			json.dump_file("Hotkeys_data.json", hk_data)
		end,
	}
end

-- ============================================================================
-- Configuration Management
-- ============================================================================

local CONFIG_PATH = "better_disp_hitboxes.json"
local SAVE_DELAY = 0.5

state.save_pending = nil
state.save_timer = nil
state.config = nil

local function mark_for_save()
	state.save_pending = true
	state.save_timer = SAVE_DELAY
end

local function create_default_config()
	local toggle_options = {
		toggle_show = true,
		hitboxes = true, hitboxes_outline = true,
		hitbox_ticks = true,
		hurtboxes = true, hurtboxes_outline = true,
		pushboxes = true, pushboxes_outline = true,
		throwboxes = true, throwboxes_outline = true,
		throwhurtboxes = true, throwhurtboxes_outline = true,
		proximityboxes = true, proximityboxes_outline = true,
		clashboxes = true, clashboxes_outline = true,
		uniqueboxes = true, uniqueboxes_outline = true,
		properties = true, position = true
	}

	local opacity_options = {
		hitbox = 25, hitbox_outline = 25,
		hitbox_tick = 25,
		hurtbox = 25, hurtbox_outline = 25,
		pushbox = 25, pushbox_outline = 25,
		throwbox = 25, throwbox_outline = 25,
		throwhurtbox = 25, throwhurtbox_outline = 25,
		proximitybox = 25, proximitybox_outline = 25,
		clashbox = 25, clashbox_outline = 25,
		uniquebox = 25, uniquebox_outline = 25,
		properties = 100, position = 100
	}

	return {
		options = {
			display_menu = true,
			hide_all_alerts = false,
			alert_on_toggle = true,
			alert_on_presets = true,
			alert_on_save = true,
			notify_duration = 2.0,
			hotkey_minimizes = false,
			color_wall_splat = true,
			range_ticks_show = true,
			mode_training = true,
			mode_replay = true,
			mode_local_versus = false,
			mode_single_player = false,
		},
		hotkeys = {
			hotkeys_toggle_menu = "F1",
			hotkeys_toggle_p1 = "Alpha1",
			["hotkeys_toggle_p1_$"] = "Control",
			hotkeys_toggle_p2 = "Alpha2",
			["hotkeys_toggle_p2_$"] = "Control",
			hotkeys_toggle_all = "Alpha3",
			["hotkeys_toggle_all_$"] = "Control",
			hotkeys_prev_preset = "Left",
			["hotkeys_prev_preset_$"] = "Control",
			hotkeys_next_preset = "Right",
			["hotkeys_next_preset_$"] = "Control",
			hotkeys_save_preset = "Space",
			["hotkeys_save_preset_$"] = "Control",
			hotkeys_toggle_sync = "Y (Triangle)",
		},
		p1 = {toggle = deep_copy(toggle_options), opacity = deep_copy(opacity_options)},
		p2 = {toggle = deep_copy(toggle_options), opacity = deep_copy(opacity_options)}
	}
end

local function create_default_presets()
    local function make_toggle(overrides)
        local t = {
            toggle_show = true,
            hitboxes = true, hitboxes_outline = true,
            hitbox_ticks = false,
            hurtboxes = true, hurtboxes_outline = true,
            pushboxes = true, pushboxes_outline = true,
            throwboxes = true, throwboxes_outline = true,
            throwhurtboxes = true, throwhurtboxes_outline = true,
            proximityboxes = true, proximityboxes_outline = true,
            clashboxes = true, clashboxes_outline = true,
            uniqueboxes = true, uniqueboxes_outline = true,
            properties = true, position = true
        }
        if overrides then for k, v in pairs(overrides) do t[k] = v end end
        return t
    end

    local function make_opacity(fill, outline, props, pos)
        return {
            hitbox = fill, hitbox_outline = outline,
            hitbox_tick = fill,
            hurtbox = fill, hurtbox_outline = outline,
            pushbox = fill, pushbox_outline = outline,
            throwbox = fill, throwbox_outline = outline,
            throwhurtbox = fill, throwhurtbox_outline = outline,
            proximitybox = fill, proximitybox_outline = outline,
            clashbox = fill, clashbox_outline = outline,
            uniquebox = fill, uniquebox_outline = outline,
            properties = props or 100, position = pos or 100
        }
    end

    local light_toggle = make_toggle({properties = false, throwhurtboxes_outline = false})
    local light_opacity = {
        hitbox = 15, hitbox_outline = 15,
        hitbox_tick = 15,
        hurtbox = 10, hurtbox_outline = 15,
        pushbox = 5,  pushbox_outline = 15,
        throwbox = 15, throwbox_outline = 5,
        throwhurtbox = 5, throwhurtbox_outline = 20,
        proximitybox = 10, proximitybox_outline = 15,
        clashbox = 10, clashbox_outline = 15,
        uniquebox = 10, uniquebox_outline = 15,
        properties = 15, position = 35
    }

    local outlines_toggle = make_toggle({
        hitboxes = false, hurtboxes = false, pushboxes = false,
        throwboxes = false, throwhurtboxes = false, proximityboxes = false,
        clashboxes = false, uniqueboxes = false, properties = false
    })
    local outlines_opacity = make_opacity(25, 75, 100, 80)

    local presets = {
        ["Default"] = {
            p1 = {toggle = make_toggle({hitbox_ticks = false}), opacity = make_opacity(25, 25)},
            p2 = {toggle = make_toggle({hitbox_ticks = false}), opacity = make_opacity(25, 25)}
        },
        ["Dark"] = {
            p1 = {toggle = make_toggle({hitbox_ticks = false}), opacity = make_opacity(50, 50)},
            p2 = {toggle = make_toggle({hitbox_ticks = false}), opacity = make_opacity(50, 50)}
        },
        ["Light"] = {
            p1 = {toggle = deep_copy(light_toggle), opacity = deep_copy(light_opacity)},
            p2 = {toggle = deep_copy(light_toggle), opacity = deep_copy(light_opacity)}
        },
        ["Outlines"] = {
            p1 = {toggle = deep_copy(outlines_toggle), opacity = deep_copy(outlines_opacity)},
            p2 = {toggle = deep_copy(outlines_toggle), opacity = deep_copy(outlines_opacity)}
        },
        ["Hitbox Ticks"] = {
            p1 = {toggle = make_toggle({hitbox_ticks = true}), opacity = make_opacity(25, 25)},
            p2 = {toggle = make_toggle({hitbox_ticks = true}), opacity = make_opacity(25, 25)}
        },
    }
    return presets
end

local function validate_config(cfg)
	if not cfg.options then cfg.options = { display_menu = true } end
	if not cfg.p1 then cfg.p1 = { toggle = {}, opacity = {} } end
	if not cfg.p2 then cfg.p2 = { toggle = {}, opacity = {} } end
	local default = create_default_config()
	for _, player in ipairs({"p1", "p2"}) do
		if not cfg[player].toggle then cfg[player].toggle = {} end
		if not cfg[player].opacity then cfg[player].opacity = {} end
		for k, v in pairs(default[player].toggle) do
			if cfg[player].toggle[k] == nil then cfg[player].toggle[k] = v end end
		for k, v in pairs(default[player].opacity) do
			if cfg[player].opacity[k] == nil then cfg[player].opacity[k] = v end end
	end
	for k, v in pairs(default.options) do
		if cfg.options[k] == nil then cfg.options[k] = v end end
	return cfg
end

local function save_config()
	local data_to_save = {
		presets = state.presets,
		current_preset = state.current_preset_name,
		config = state.config
	}
	json.dump_file(CONFIG_PATH, data_to_save)
	state.save_pending = false
end

local function rebuild_preset_names()
	state.preset_names = {}
	for name, _ in pairs(state.presets) do
		table.insert(state.preset_names, name)
	end
	table.sort(state.preset_names, function(a, b) return string.lower(a) < string.lower(b) end)
end

local function load_config()
	local loaded = json.load_file(CONFIG_PATH)
	if loaded then
		if loaded.presets then
			state.presets = loaded.presets
			rebuild_preset_names()
		end
		if loaded.current_preset then state.current_preset_name = loaded.current_preset end
		if loaded.config then state.config = validate_config(loaded.config)
		else state.config = validate_config(loaded) end
	else
        state.config = create_default_config()
        state.presets = create_default_presets()
        state.current_preset_name = "Default"
        rebuild_preset_names()
        mark_for_save()
    end

	local defaults = create_default_presets()
    for name, data in pairs(defaults) do
        if not state.presets[name] then
            state.presets[name] = data
            rebuild_preset_names()
            mark_for_save()
        end
    end

	local default = create_default_config()
	state.config.hotkeys = state.config.hotkeys or {}
	for k, v in pairs(default.hotkeys) do
		if state.config.hotkeys[k] == nil then
			local is_modifier = k:sub(-2) == "_$"
			if not is_modifier then
				state.config.hotkeys[k] = v
			elseif state.config.hotkeys[k:sub(1, -3)] == nil then
				-- Only restore modifier default if base key is also absent (first run)
				state.config.hotkeys[k] = v
			end
		end
	end
	hk.setup_hotkeys(state.config.hotkeys, default.hotkeys)
	hk.sync_modifiers_from_hotkeys()
	hk.register_hotkey_change_callback(function()
		hk.update_hotkey_table(state.config.hotkeys)
		mark_for_save()
	end)
end

local function save_handler()
	if state.save_pending then
		state.save_timer = state.save_timer - (1.0 / 60.0)
		if state.save_timer <= 0 then save_config() end
	end
end

local function reset_all_default(player)
	local default = create_default_config()
	if player == nil then
		state.config.p1 = deep_copy(default.p1)
		state.config.p2 = deep_copy(default.p2)
	elseif player == "p1" or player == "p2" then
		state.config[player] = deep_copy(default[player]) end
	mark_for_save()
	return state.config
end

local function reset_toggle_default(player)
	local default = create_default_config()
	if player == nil then
		state.config.p1.toggle = deep_copy(default.p1.toggle)
		state.config.p2.toggle = deep_copy(default.p2.toggle)
	elseif player == "p1" or player == "p2" then
		state.config[player].toggle = deep_copy(default[player].toggle) end
	mark_for_save()
	return state.config
end

local function reset_opacity_default(player)
	local default = create_default_config()
	if player == nil then
		state.config.p1.opacity = deep_copy(default.p1.opacity)
		state.config.p2.opacity = deep_copy(default.p2.opacity)
	elseif player == "p1" or player == "p2" then
		state.config[player].opacity = deep_copy(default[player].opacity) end
	mark_for_save()
	return state.config
end

-- ============================================================================
-- Notifications
-- ============================================================================

state.tooltip_timer = 0
state.tooltip_msg = ""

local function action_notify(msg, category_toggle)
    if state.config.options.hide_all_alerts then return end
    if category_toggle ~= nil and not state.config.options[category_toggle] then return end
    state.tooltip_msg = MOD_NAME .. ': ' .. msg
    state.tooltip_timer = math.floor(state.config.options.notify_duration * 60 + 0.5)
end

local function tooltip_handler()
	if state.tooltip_timer > 0 then state.tooltip_timer = state.tooltip_timer - 1 end
end

local function action_notify_handler()
    if state.tooltip_timer <= 0 then return end

    local display = imgui.get_display_size()
    imgui.set_next_window_pos(
        Vector2f.new(display.x * 0.5, display.y - 100),
        1 << 0,
        Vector2f.new(0.5, 0.5)
    )

    imgui.set_next_window_size(Vector2f.new(0, 0), 1 << 0)
    imgui.begin_window("Notification", true, 1|2|4|8|16|43|64|65536|131072)
    imgui.push_font(imgui.load_font(nil, 30))
    imgui.text(state.tooltip_msg)
    imgui.pop_font()
    imgui.end_window()
end

-- ============================================================================
-- Preset Management
-- ============================================================================

state.presets = {}
state.preset_names = {}
state.current_preset_name = ""
state.previous_preset_name = ""
state.new_preset_name = ""
state.rename_temp_name = ""
state.rename_mode = false
state.create_new_mode = false
state.delete_confirm_name = false
state.restore_presets_confirm = false
state.backup_filename = ""

local function is_preset_loaded(preset_name)
	if not preset_name or preset_name == "" or not state.presets[preset_name] then return false end
	local preset = state.presets[preset_name]
	for _, player in ipairs({"p1", "p2"}) do
		local config_p, preset_p = state.config[player], preset[player]
		for _, category in ipairs({"toggle", "opacity"}) do
			local current_cat, preset_cat = config_p[category], preset_p[category]
			for k, v in pairs(preset_cat) do if current_cat[k] ~= v then return false end end
			for k, _ in pairs(current_cat) do if preset_cat[k] == nil then return false end end
		end
	end
	return true
end

local function preset_has_unsaved_changes()
	if state.current_preset_name == "" or not state.presets[state.current_preset_name] then return end
	return not is_preset_loaded(state.current_preset_name)
end

local function get_preset_name()
	local base_name, i = "Preset ", 1
	while true do
		local candidate = base_name .. i
		if not state.presets[candidate] then return candidate end
		i = i + 1
	end
end

local function save_current_preset(name)
	if not name or name == "" then return false, "Invalid preset name" end
	if is_preset_loaded(name) then return true, "Data identical, skipping save" end

	state.presets[name] = {p1 = deep_copy(state.config.p1), p2 = deep_copy(state.config.p2)}
	rebuild_preset_names()
	state.current_preset_name, state.previous_preset_name = name, ""
	action_notify("Preset Saved: " .. name, "alert_on_save")
	mark_for_save()
	return true, "Saved"
end

local function load_preset(name)
	if state.presets[name] then
		local default, preset = create_default_config(), state.presets[name]
		for _, player in ipairs({"p1", "p2"}) do
			local merged_toggle = deep_copy(default[player].toggle)
			if preset[player].toggle then
				for k, v in pairs(preset[player].toggle) do
					merged_toggle[k] = v end
			end
			state.config[player].toggle = merged_toggle
			local merged_opacity = deep_copy(default[player].opacity)
			if preset[player].opacity then
				for k, v in pairs(preset[player].opacity) do
					merged_opacity[k] = v end
			end
			state.config[player].opacity = merged_opacity
		end
		state.current_preset_name, state.previous_preset_name = name, ""
		mark_for_save()
		return true
	end
	return false, "Preset not found"
end

local function delete_preset(name)
	if not state.presets[name] then return false, "Preset not found" end

	local fallback = nil
	if state.current_preset_name == name then
		for _, p_name in ipairs(state.preset_names) do
			if p_name ~= name then
				fallback = p_name
				break
			end
		end
	end

	state.presets[name] = nil
	rebuild_preset_names()

	if state.rename_mode == name then
		state.rename_mode, state.rename_temp_name = false, ""
	end

	if state.current_preset_name == name then
		state.create_new_mode, state.rename_mode = false, false
		if fallback then
			load_preset(fallback)
		else
			reset_all_default()
			state.current_preset_name = get_preset_name()
			save_current_preset(state.current_preset_name)
		end
	end

	mark_for_save()
	return true
end

local function rename_preset(old_name, new_name)
	if not old_name or old_name == "" then return false, "No preset selected" end
	if not new_name or new_name == "" then return false, "New name cannot be empty" end
	if new_name == old_name then return false, "New name is the same as the old name" end
	if state.presets[new_name] then return false, "A preset with this name already exists" end
	if state.presets[old_name] then
		state.presets[new_name], state.presets[old_name] = state.presets[old_name], nil
		rebuild_preset_names()
		if state.current_preset_name == old_name then
			state.current_preset_name, state.previous_preset_name = new_name, "" end
		mark_for_save()
		return true
	end
	return false, "Preset not found"
end

local function get_duplicate_preset_name(name)
	local i = 1
	while true do
		local candidate = name .. "_" .. i
		if not state.presets[candidate] then return candidate end
		i = i + 1
	end
end

local function duplicate_preset(name)
	if not state.presets[name] then return false, "Preset not found" end
	local new_name = get_duplicate_preset_name(name)
	state.presets[new_name] = deep_copy(state.presets[name])
	rebuild_preset_names()
	mark_for_save()
	return true
end

local function start_create_new_mode()
	state.create_new_mode = true
	state.rename_mode = false
	if state.previous_preset_name == "" then state.previous_preset_name = state.current_preset_name end
	state.new_preset_name = get_preset_name()
end

local function start_rename_mode(preset_name)
	state.rename_mode = preset_name
	state.rename_temp_name = preset_name
	state.create_new_mode = false
end

local function cancel_rename_mode()
	state.rename_mode, state.rename_temp_name = false, ""
end

local function switch_preset(preset_name)
	load_preset(preset_name)
	action_notify("Loaded Preset " .. preset_name, "alert_on_presets")
	state.create_new_mode, state.rename_mode, state.new_preset_name, state.rename_temp_name = false, false, "", ""
end

local function start_delete_confirm(preset_name)
	state.delete_confirm_name = preset_name
end

local function save_rename(old_name)
	if state.rename_temp_name == "" then
	elseif state.rename_temp_name == old_name then
		state.rename_mode, state.rename_temp_name = false, ""
	elseif state.presets[state.rename_temp_name] then
	else
		local success, error_msg = rename_preset(old_name, state.rename_temp_name)
		if success then state.rename_mode, state.rename_temp_name = false, "" end
	end
end

local function save_new_preset()
	if state.new_preset_name == "" then
	elseif state.presets[state.new_preset_name] then
		state.current_preset_name = state.new_preset_name
		state.create_new_mode, state.new_preset_name = false, ""
	else
		local default = create_default_config()
		state.presets[state.new_preset_name] = {p1 = deep_copy(default.p1), p2 = deep_copy(default.p2)}
		rebuild_preset_names()
		state.config.p1 = deep_copy(default.p1)
		state.config.p2 = deep_copy(default.p2)
		local created_name = state.new_preset_name
		state.current_preset_name, state.previous_preset_name = created_name, ""
		state.create_new_mode, state.new_preset_name = false, ""
		action_notify("Preset Created: " .. created_name, "alert_on_presets")
		mark_for_save()
	end
end

local function cancel_new_preset()
	state.create_new_mode, state.new_preset_name = false, ""
	if state.previous_preset_name ~= "" then
		state.current_preset_name, state.previous_preset_name = state.previous_preset_name, "" end
end

local function create_new_blank_preset()
	if state.previous_preset_name == "" then state.previous_preset_name = state.current_preset_name end
	state.new_preset_name = get_preset_name()
end

local function cancel_blank_preset()
	state.create_new_mode, state.new_preset_name = false, ""
	if state.previous_preset_name ~= "" then
		state.current_preset_name, state.previous_preset_name = state.previous_preset_name, ""
	else state.current_preset_name = "" end
end

local function get_current_preset_index()
	for i, name in ipairs(state.preset_names) do
		if name == state.current_preset_name then return i end
	end
	return 1
end

local function load_next_preset()
	if #state.preset_names <= 1 then return end
	local index = get_current_preset_index()
	index = index + 1
	if index > #state.preset_names then index = 1 end
	switch_preset(state.preset_names[index])
end

local function load_previous_preset()
	if #state.preset_names <= 1 then return end
	local index = get_current_preset_index()
	index = index - 1
	if index < 1 then index = #state.preset_names end
	switch_preset(state.preset_names[index])
end

local function generate_default_backup_filename()
    local t = os.date("*t")
    local datetime = string.format("%04d%02d%02d_%02d%02d%02d",
        t.year, t.month, t.day, t.hour, t.min, t.sec)
    return "hitbox_backup" .. datetime .. ".json"
end

local function perform_backup(filename)
    if not filename or filename == "" then
        action_notify("Backup failed: no filename", nil)
        return
    end
    if not filename:match("%.json$") then
        filename = filename .. ".json"
    end
    local data = {
        presets = state.presets,
        current_preset = state.current_preset_name,
        config = state.config
    }
    json.dump_file(filename, data)
    action_notify("Backup saved to " .. filename, "alert_on_save")
end

local function restore_presets()
    local default = create_default_config()
    state.config.p1 = deep_copy(default.p1)
    state.config.p2 = deep_copy(default.p2)
    local factory = create_default_presets()
    for name, data in pairs(factory) do
        state.presets[name] = data
    end
    rebuild_preset_names()
    state.current_preset_name = "Default"
    load_preset("Default")
    action_notify("Presets Restored", "alert_on_presets")
    mark_for_save()
end

-- ============================================================================
-- Hitbox Drawing Logic
-- ============================================================================

local RIGHT_SPLAT_POS = 585.2
local LEFT_SPLAT_POS = -1 * RIGHT_SPLAT_POS


-- Property text persistence: each entry keyed by "player_key|text"
-- Stores the last-seen screen position and counts down for 20 frames after
-- the source hitbox disappears.
-- prop_persist: { [key] = {text,x,y,base_opacity,player_key,timer,last_live_frame} }
-- prop_persist_frame: monotonic counter; incremented once per live hitbox pass

state.range_ticks = { p1 = nil, p2 = nil }
state.prop_persist = {}
state.prop_persist_frame = 0

local function apply_opacity(opacity, colorWithoutAlpha)
	local alpha = math.floor(opacity * 2.55)
	return alpha * 0x1000000 + (colorWithoutAlpha % 0x1000000)
end

local function get_vectors(rect)
    local posX, posY = rect.OffsetX.v / 6553600.0, rect.OffsetY.v / 6553600.0
    local sclX, sclY = rect.SizeX.v / 6553600.0 * 2, rect.SizeY.v / 6553600.0 * 2
    posX, posY = posX - sclX / 2, posY - sclY / 2
    local vTL = Vector3f.new(posX - sclX / 2, posY + sclY / 2, 0)
    local vTR = Vector3f.new(posX + sclX / 2, posY + sclY / 2, 0)
    local vBL = Vector3f.new(posX - sclX / 2, posY - sclY / 2, 0)
    local vBR = Vector3f.new(posX + sclX / 2, posY - sclY / 2, 0)
    return vTL, vTR, vBL, vBR
end

local function get_dimensions(vTL, vTR, vBL, vBR)
    local dw = draw.world_to_screen
    local tl, tr, bl, br = dw(vTL), dw(vTR), dw(vBL), dw(vBR)
    if not (tl and tr and bl and br) then return nil, nil, nil, nil end
    return (tl.x + tr.x) / 2, (bl.y + tl.y) / 2, (tr.x - tl.x), (tl.y - bl.y)
end

local function property_flag(parts, idx, bit, str, rect)
    if bitand(rect.CondFlag, bit) == bit then
        idx = idx + 1
        parts[idx] = str
    end
    return idx
end

local function build_hit_properties(condFlag, rect)
	if not rect then return end
    local parts = {}
    local idx = 0
    idx = property_flag(parts, idx, 16, "Standing, ", rect)
    idx = property_flag(parts, idx, 32, "Crouching, ", rect)
    idx = property_flag(parts, idx, 64, "Airborne, ", rect)
    idx = property_flag(parts, idx, 256, "Can't Hit Forward, ", rect)
    idx = property_flag(parts, idx, 512, "Can't Hit Backward, ", rect)
    if idx > 0 then
        parts[idx] = string.sub(parts[idx], 1, -3)
        idx = idx + 1
        parts[idx] = "\n"
    end

    if bitand(condFlag, 262144) == 262144 or bitand(condFlag, 524288) == 524288 then
        idx = idx + 1
        parts[idx] = "Combo Only\n"
    end

    if idx > 0 then return table.concat(parts, "", 1, idx) end
    return nil
end

local function build_hurt_properties(typeFlag, immune)
    local parts = {}
    local idx = 0

    if typeFlag == 1 then
        idx = idx + 1
        parts[idx] = "Projectile Invulnerable\n"
    elseif typeFlag == 2 then
        idx = idx + 1
        parts[idx] = "Strike Invulnerable\n"
    end

    local intangible = false
    if bitand(immune, 1) == 1 then
        idx = idx + 1
        parts[idx] = "Stand, "
        intangible = true
    end
    if bitand(immune, 2) == 2 then
        idx = idx + 1
        parts[idx] = "Crouch, "
        intangible = true
    end
    if bitand(immune, 4) == 4 then
        idx = idx + 1
        parts[idx] = "Air, "
        intangible = true
    end
    if bitand(immune, 64) == 64 then
        idx = idx + 1
        parts[idx] = "Behind, "
        intangible = true
    end
    if bitand(immune, 128) == 128 then
        idx = idx + 1
        parts[idx] = "Reverse, "
        intangible = true
    end
    if intangible then
        parts[idx] = string.sub(parts[idx], 1, -3)
        idx = idx + 1
        parts[idx] = " Attack Intangible\n"
    end

    if idx > 0 then
        return table.concat(parts, "", 1, idx)
    end
    return nil
end

-- Classifies a hitbox rect and returns all draw data without touching the GPU.
-- Returns nil if the rect has no valid screen projection or is unknown.
local function classify_hitbox(rect, player_config)
    if not rect then return nil end
    local vTL, vTR, vBL, vBR = get_vectors(rect)
    local x, y, w, h = get_dimensions(vTL, vTR, vBL, vBR)
    if not (x and y and w and h) then return nil end
    -- get_dimensions returns h = tl.y - bl.y which is negative in screen space
    -- (Y increases downward).  Normalise so w and h are always positive; the
    -- origin shifts to the geometric top-left corner.
    if w < 0 then x, w = x + w, -w end
    if h < 0 then y, h = y + h, -h end

    local tog, opa = player_config.toggle, player_config.opacity
    local base_color, fill_key, outline_key, toggle_key, prop_text

    if rect:get_field("HitPos") ~= nil then
        if rect.TypeFlag > 0 then
            base_color, fill_key, outline_key, toggle_key = 0x0040C0, "hitbox", "hitbox_outline", "hitboxes"
            if tog.properties then prop_text = build_hit_properties(rect.CondFlag, rect) end
        elseif (rect.TypeFlag == 0 and rect.PoseBit > 0) or rect.CondFlag == 0x2C0 then
            base_color, fill_key, outline_key, toggle_key = 0xD080FF, "throwbox", "throwbox_outline", "throwboxes"
            if tog.properties then prop_text = build_hit_properties(rect.CondFlag, rect) end
        elseif rect.GuardBit == 0 then
            base_color, fill_key, outline_key, toggle_key = 0x3891E6, "clashbox", "clashbox_outline", "clashboxes"
        else
            base_color, fill_key, outline_key, toggle_key = 0x5b5b5b, "proximitybox", "proximitybox_outline", "proximityboxes"
        end
    elseif rect:get_field("Attr") ~= nil then
        base_color, fill_key, outline_key, toggle_key = 0x00FFFF, "pushbox", "pushbox_outline", "pushboxes"
    elseif rect:get_field("HitNo") ~= nil then
        if rect.TypeFlag > 0 then
            base_color = (rect.Type == 2 or rect.Type == 1) and 0xFF0080 or 0x00FF00
            fill_key, outline_key, toggle_key = "hurtbox", "hurtbox_outline", "hurtboxes"
            if tog.properties then prop_text = build_hurt_properties(rect.TypeFlag, rect.Immune) end
        else
            base_color, fill_key, outline_key, toggle_key = 0xFF0000, "throwhurtbox", "throwhurtbox_outline", "throwhurtboxes"
        end
    elseif rect:get_field("KeyData") ~= nil then
        base_color, fill_key, outline_key, toggle_key = 0xEEFF00, "uniquebox", "uniquebox_outline", "uniqueboxes"
    else
        base_color, fill_key, outline_key, toggle_key = 0xFF0000, "throwhurtbox", "throwhurtbox_outline", "throwhurtboxes"
    end

    if not base_color then return nil end

    return {
        x               = x,
        y               = y,
        w               = w,
        h               = h,
        base_color      = base_color,
        show_fill       = tog[toggle_key]                  or false,
        show_outline    = tog[toggle_key .. "_outline"]    or false,
        fill_opacity    = opa[fill_key]                    or 25,
        outline_opacity = opa[outline_key]                 or 25,
        prop_text       = prop_text,
    }
end


-- Draws the filled union of a set of screen-space AABBs using coordinate
-- compression so that overlapping regions are painted exactly once.
-- All cells share the same pre-computed full_color (alpha already embedded).
-- Pre-merged "filled_rect" entries are written to draw_call_buffer for
-- correct timestop replay.

local timestop_frame = 0
local timestop_total_frames = 0
local frozen_draw_calls = {}   -- last pre-timestop frame's draw calls
local draw_call_buffer = nil   -- non-nil while recording a normal frame

local function draw_union_fills(boxes, full_color)
    if #boxes == 0 then return end

    -- Fast path: single box, no overlap possible.
    if #boxes == 1 then
        local b = boxes[1]
        if draw_call_buffer then
            draw_call_buffer[#draw_call_buffer+1] = {"filled_rect", b.x, b.y, b.w, b.h, full_color}
        end
        draw.filled_rect(b.x, b.y, b.w, b.h, full_color)
        return
    end

    -- Collect and sort all unique X and Y boundary coordinates.
    local xs, ys = {}, {}
    for _, b in ipairs(boxes) do
        xs[#xs+1] = b.x;       xs[#xs+1] = b.x + b.w
        ys[#ys+1] = b.y;       ys[#ys+1] = b.y + b.h
    end
    table.sort(xs); table.sort(ys)
    -- Deduplicate into compressed axis arrays.
    local uxs, uys = {xs[1]}, {ys[1]}
    for i = 2, #xs do if xs[i] ~= xs[i-1] then uxs[#uxs+1] = xs[i] end end
    for i = 2, #ys do if ys[i] ~= ys[i-1] then uys[#uys+1] = ys[i] end end

    -- For each cell in the compressed grid, draw it if any source rect covers
    -- its centre point.  break as soon as a covering rect is found.
    for i = 1, #uxs - 1 do
        local cx = (uxs[i] + uxs[i+1]) * 0.5
        for j = 1, #uys - 1 do
            local cy = (uys[j] + uys[j+1]) * 0.5
            for _, b in ipairs(boxes) do
                if cx >= b.x and cx <= b.x + b.w and cy >= b.y and cy <= b.y + b.h then
                    local cw = uxs[i+1] - uxs[i]
                    local ch = uys[j+1] - uys[j]
                    if draw_call_buffer then
                        draw_call_buffer[#draw_call_buffer+1] = {"filled_rect", uxs[i], uys[j], cw, ch, full_color}
                    end
                    draw.filled_rect(uxs[i], uys[j], cw, ch, full_color)
                    break
                end
            end
        end
    end
end

local function draw_text_buffered(text, x, y, color)
    if draw_call_buffer then
        draw_call_buffer[#draw_call_buffer + 1] = {"text", text, x, y, color}
    end
    draw.text(text, x, y, color)
end

-- ============================================================================
-- Property Text Persistence
-- ============================================================================

-- Total lifetime of a ghost label after its hitbox disappears.
local PROP_PERSIST_TOTAL  = 20
-- Frame thresholds that control the two-stage fade curve.
-- Stage 1 (frames 1-5):   full opacity — no fade.
-- Stage 2 (frames 6-10):  slow fade starts, alpha eases from 1.0 → ~0.7.
-- Stage 3 (frames 11-20): sharp fade, alpha drops quickly from ~0.7 → 0.
local PROP_PERSIST_SLOW   = 5
local PROP_PERSIST_SHARP  = 10

-- Returns an alpha multiplier in [0, 1] given the remaining lifetime timer.
-- timer == PROP_PERSIST_TOTAL  →  start of decay, age 0  →  multiplier 1.0
-- timer == 0                   →  end of decay, age 20   →  multiplier 0.0
local function prop_persist_fade(timer)
    local age = PROP_PERSIST_TOTAL - timer  -- how many frames since decay began (0-based)
    if age <= PROP_PERSIST_SLOW then
        return 1.0
    elseif age <= PROP_PERSIST_SHARP then
        -- Slow stage: ease from 1.0 down to 0.7 over PROP_PERSIST_SLOW frames
        local t = (age - PROP_PERSIST_SLOW) / (PROP_PERSIST_SHARP - PROP_PERSIST_SLOW)
        return 1.0 - 0.3 * t
    else
        -- Sharp stage: drop from 0.7 to 0 over the remaining frames
        local t = (age - PROP_PERSIST_SHARP) / (PROP_PERSIST_TOTAL - PROP_PERSIST_SHARP)
        return 0.7 * (1.0 - t)
    end
end

-- Called instead of draw_text_buffered for every property label.
-- Draws the text immediately (including into the timestop buffer) and
-- registers/refreshes the entry in the persist table so it can ghost
-- for PROP_PERSIST_TOTAL frames after the hitbox is gone.
-- player_key must be "p1" or "p2".
local function record_prop_persist(text, x, y, base_opacity, player_key)
    -- Immediate draw path (unchanged behaviour, also fills draw_call_buffer).
    draw_text_buffered(text, x, y, apply_opacity(base_opacity, 0xFFFFFF))

    -- Keyed by player + text so that distinct property strings get independent
    -- ghost timers while the same string on the same player merges into one entry.
    local key   = player_key .. "|" .. text
    local entry = state.prop_persist[key]
    if entry then
        -- Refresh: update live position and reset countdown.
        entry.x              = x
        entry.y              = y
        entry.base_opacity   = base_opacity
        entry.timer          = PROP_PERSIST_TOTAL
        entry.last_live_frame = state.prop_persist_frame
    else
        state.prop_persist[key] = {
            text            = text,
            x               = x,
            y               = y,
            base_opacity    = base_opacity,
            player_key      = player_key,
            timer           = PROP_PERSIST_TOTAL,
            last_live_frame = state.prop_persist_frame,
        }
    end
end

-- Iterates the persist table once per live frame (not during timestop).
-- Entries seen this frame are skipped (already drawn by record_prop_persist).
-- Entries not seen this frame are drawn with a fading alpha and ticked down.
local function draw_prop_persist()
    for key, entry in pairs(state.prop_persist) do
        local player_config = state.config[entry.player_key]

        -- Purge if the player toggled properties off.
        if not player_config or not player_config.toggle.properties then
            state.prop_persist[key] = nil

        elseif entry.last_live_frame < state.prop_persist_frame then
            -- Source hitbox absent this frame: advance decay and draw ghost.
            entry.timer = entry.timer - 1
            if entry.timer <= 0 then
                state.prop_persist[key] = nil
            else
                local fade          = prop_persist_fade(entry.timer)
                local faded_opacity = math.max(0, math.floor(entry.base_opacity * fade))
                draw.text(entry.text, entry.x, entry.y,
                    apply_opacity(faded_opacity, 0xFFFFFF))
            end
        end
        -- last_live_frame == prop_persist_frame → already drawn this frame, nothing to do.
    end
end

local function draw_hitboxes(work, actParam, player_config, player_key)
    local col = actParam.Collision

    -- Pass 1: classify every rect into pure data — no GPU calls yet.
    local classified = {}
    for _, rect in reverse_pairs(col.Infos._items) do
        local info = classify_hitbox(rect, player_config)
        if info then classified[#classified+1] = info end
    end

    -- Pass 2: group fills by (base_color × opacity) and draw the union of each
    -- group so that overlapping rects of the same type paint their shared region
    -- at the same opacity as a single rect, not compounded alpha.
    local fill_groups = {}
    for _, info in ipairs(classified) do
        if info.show_fill then
            local gkey = tostring(info.base_color) .. "_" .. tostring(info.fill_opacity)
            if not fill_groups[gkey] then
                fill_groups[gkey] = {
                    full_color = apply_opacity(info.fill_opacity, info.base_color),
                    boxes      = {},
                }
            end
            local g = fill_groups[gkey].boxes
            g[#g+1] = {x = info.x, y = info.y, w = info.w, h = info.h}
        end
    end
    for _, group in pairs(fill_groups) do
        draw_union_fills(group.boxes, group.full_color)
    end

    -- Pass 3: draw each rect's outline individually — unaffected by the union.
    for _, info in ipairs(classified) do
        if info.show_outline then
            local outline_color = apply_opacity(info.outline_opacity, info.base_color)
            if draw_call_buffer then
                draw_call_buffer[#draw_call_buffer+1] = {"outline_rect", info.x, info.y, info.w, info.h, outline_color}
            end
            draw.outline_rect(info.x, info.y, info.w, info.h, outline_color)
        end
    end

    -- Pass 4: property text drawn at the top-left corner of each box.
    for _, info in ipairs(classified) do
        if info.prop_text then
            record_prop_persist(info.prop_text, info.x, info.y, player_config.opacity.properties, player_key)
        end
    end
end

local function draw_position_marker(entity, player_config)
    if not player_config.toggle.position then return end
    if not entity.pos or not entity.pos.x or not entity.pos.y then return end

    local x_val = entity.pos.x.v
    local y_val = entity.pos.y.v
    if type(x_val) ~= "number" or type(y_val) ~= "number" then return end
    if x_val == 0 and y_val == 0 then return end

    local vPos = Vector3f.new(x_val / 6553600.0, y_val / 6553600.0, 0)
    local screenPos = draw.world_to_screen(vPos)
    if screenPos then
	local color = 0xFFFFFF
			if state.config.options.color_wall_splat then
				local facing_right = is_facing_right(entity)
				local scaled_x = x_val / 65536.0
				
				if (facing_right and scaled_x <= LEFT_SPLAT_POS) or (not facing_right and scaled_x >= RIGHT_SPLAT_POS) then
					color = 0xB729FF
				end
			end
        local circle_color = apply_opacity(player_config.opacity.position, color)
        if draw_call_buffer then
            draw_call_buffer[#draw_call_buffer + 1] = {"circle", screenPos.x, screenPos.y, 10, circle_color, 10}
        end
        draw.filled_circle(screenPos.x, screenPos.y, 10, circle_color, 10)
    end
end

local function get_farthest_hitbox_reach(entity)
	local col = entity.mpActParam.Collision
	if not col or not col.Infos or not col.Infos._items then return nil, nil end

	local facing_right = is_facing_right(entity)
	local farthest_edge = nil
	local inside_edge = nil
	local y_midpoints = {}

	for _, rect in pairs(col.Infos._items) do
		if rect and rect:get_field("HitPos") ~= nil and rect.TypeFlag > 0 then
			local vTL, vTR, vBL, vBR = get_vectors(rect)
			local x, y, w, h = get_dimensions(vTL, vTR, vBL, vBR)

			if x and y and w and h then
				local edge = facing_right and (x + w) or x
				local current_mid_y = y + (h / 2)

				if farthest_edge ~= nil and math.abs(edge - farthest_edge) < 0.001 then
					table.insert(y_midpoints, current_mid_y)
				elseif farthest_edge == nil or (facing_right and edge > farthest_edge) or (not facing_right and edge < farthest_edge) then
					farthest_edge = edge
					inside_edge = facing_right and x or (x + w)
					y_midpoints = { current_mid_y }
				end
			end
		end
	end

	local average_y = nil
	if #y_midpoints > 0 then
		local sum_y = 0
		for _, y_val in ipairs(y_midpoints) do sum_y = sum_y + y_val end
		average_y = sum_y / #y_midpoints
	end

	return farthest_edge, average_y
end

local function update_range_tick(entity, player_key)
	if not state.config.options.range_ticks_show then return end
	local player_config = state.config[player_key]
	if not player_config or not player_config.toggle.hitbox_ticks then return end

	local x_val = entity.pos and entity.pos.x and entity.pos.x.v
	local y_val = entity.pos and entity.pos.y and entity.pos.y.v
	if not x_val or not y_val then return end

	local vOrigin = Vector3f.new(x_val / 6553600.0, y_val / 6553600.0, 0)
	local origin = draw.world_to_screen(vOrigin)
	if not origin then return end

	local far_sx, far_sy = get_farthest_hitbox_reach(entity)
	if far_sx and far_sy then
		local current_age = 0
		local prev_tick = state.range_ticks[player_key]
		if prev_tick and prev_tick.timer > 0 then
			current_age = prev_tick.age or 0
		end

		state.range_ticks[player_key] = {
			ox = origin.x,
			fy = far_sy,
			fx = far_sx,
			timer = 60,
			age = current_age + 1
		}
	end
end

local function process_entity(entity, draw_pos)
    local config = nil
    local player_key = nil
    if entity:get_IsTeam1P() then
        config = state.config.p1
        player_key = "p1"
    elseif entity:get_IsTeam2P() then
        config = state.config.p2
        player_key = "p2"
    end
    if not config or not config.toggle.toggle_show then return end
    draw_hitboxes(entity, entity.mpActParam, config, player_key)
    if draw_pos then
        draw_position_marker(entity, config)
        update_range_tick(entity, player_key)
    end
end

local function draw_range_ticks()
	if not state.config.options.range_ticks_show then return end

	local TICK_HALF_HEIGHT = 10
	local BORDER_THICKNESS = 0

    local function thick_hline(x1, y, x2, col)
        for dy = -2, 2 do
            draw.line(x1, y + dy, x2, y + dy, col)
        end
    end

    local function thick_vline(x, y1, y2, col)
        for dx = -2, 2 do
            draw.line(x + dx, y1, x + dx, y2, col)
        end
    end

	for player_key, tick in pairs(state.range_ticks) do
		local player_config = state.config[player_key]
		if tick and tick.timer > 0 and player_config and player_config.toggle.hitbox_ticks then
			local ox, fy, fx = tick.ox, tick.fy, tick.fx
			local opacity = player_config.opacity.hitbox_tick or 25

			-- Full opacity on frame 1, fades out completely by frame 20
			local dim_fade = math.min(math.max(tick.timer - 41, 0) / 19, 1)

			-- Movement: only begins retracting in the last 20 frames
			local move_fade = math.min(math.max(tick.timer - 5, 0) / 20.0, 1)

			-- Line and tick mark grow/shrink spatially from origin outward
			local cur_ox = fx - move_fade * (fx - ox)

			local line_max = opacity * 0.625
			local LINE_COLOR = apply_opacity(math.floor(line_max * dim_fade), 0xFF0000FF)
			local TICK_COLOR = apply_opacity(math.floor(opacity * dim_fade), 0xFF0000FF)
			local BORDER_COLOR = apply_opacity(math.floor(opacity * dim_fade), 0x000000)

			-- Shift tick inward to sit on the inside face of the far edge
			local inward = ox < fx and -2 or 2
			local tick_x = fx + inward

			for offset = -BORDER_THICKNESS, BORDER_THICKNESS do
				draw.line(cur_ox, fy + offset, tick_x, fy + offset, BORDER_COLOR)
			end

			for x_off = -BORDER_THICKNESS, BORDER_THICKNESS do
				thick_vline(tick_x + x_off,
					fy - TICK_HALF_HEIGHT - BORDER_THICKNESS,
					fy + TICK_HALF_HEIGHT + BORDER_THICKNESS,
					BORDER_COLOR)
			end

			thick_hline(cur_ox, fy, tick_x, LINE_COLOR)
			thick_vline(tick_x, fy - TICK_HALF_HEIGHT, fy + TICK_HALF_HEIGHT, TICK_COLOR)

			tick.timer = tick.timer - 1
		else
			state.range_ticks[player_key] = nil
		end
	end
end

local function update_timestop_state()
    local ok, BattleChronos = pcall(function()
        return gBattle:get_field("Chronos"):get_data(nil)
    end)
    if not ok or not BattleChronos then return end
    local frame, frames = BattleChronos.WorldElapsed, BattleChronos.WorldNotch
    local current_frame, total_frames = frame, frames
    if frame > 0 and frames > 0 and frame == frames then
        current_frame, total_frames = 0, 0
    end
    timestop_frame, timestop_total_frames = current_frame, total_frames
end

local function replay_frozen_draw_calls()
    for _, call in ipairs(frozen_draw_calls) do
        if call[1] == "filled_rect" then
            draw.filled_rect(call[2], call[3], call[4], call[5], call[6])
        elseif call[1] == "outline_rect" then
            draw.outline_rect(call[2], call[3], call[4], call[5], call[6])
        elseif call[1] == "text" then
            draw.text(call[2], call[3], call[4], call[5])
        elseif call[1] == "circle" then
            draw.filled_circle(call[2], call[3], call[4], call[5], call[6])
        end
    end
end

local function process_hitboxes()
    update_timestop_state()

	-- DR 11F timestop: Keep drawing
    if timestop_total_frames == 11 and not (timestop_frame == timestop_total_frames) then
        replay_frozen_draw_calls()
        draw_range_ticks()
        return
    end

    draw_call_buffer = {}
    state.prop_persist_frame = state.prop_persist_frame + 1

	if not state.sWork or not state.sPlayer then return end
    
    for _, obj in pairs(state.sWork.Global_work) do
        if obj.mpActParam and not obj:get_IsR0Die() then process_entity(obj, false) end
    end
    for _, player in pairs(state.sPlayer.mcPlayer) do
        if player.mpActParam then process_entity(player, true) end
    end

    frozen_draw_calls = draw_call_buffer
    draw_call_buffer = nil
    draw_prop_persist()
    draw_range_ticks()
end

state.tree_open = {}
state.sync_enabled = false
state.syncing = false
state.menu_window_pos = nil
state.last_menu_title = ""
state.last_menu_hotkey_display = ""
state.force_tree_restore = false
state.confirm_restore_hotkeys = false
state.menu_window_focused = false

-- Controller Menu Navigation

-- Left-stick / D-pad digital bitmask constants
-- (via.hid.GamePadButton LUp/LDown/LLeft/LRight)
local NAV_UP, NAV_DOWN, NAV_LEFT, NAV_RIGHT = 1, 2, 4, 8

local menu_nav = {
    active        = false,
    selected      = 1,     -- 0 = header row, 1..n = toggle rows
    column        = 1,     -- header: 0=sync, 1=P1, 2=P2
                           -- rows:   1=P1_toggle, 2=P1_opacity, 3=P2_toggle, 4=P2_opacity
    rep_timer     = 0,
    prev_dy       = 0,
    prev_dx       = 0,
    REP_DELAY     = 22,
    REP_RATE      = 7,
    slider_active = false, -- currently editing an opacity slider
    slider_orig   = nil,   -- value before slider edit started (for cancel)
    slider_rep    = 0,
    SLIDER_STEP   = 3,     -- opacity units per tick when editing
    SLIDER_DELAY  = 10,    -- frames before slider repeat starts
    SLIDER_RATE   = 3,     -- frames per repeat tick while held
    just_moved    = false, -- true for exactly one frame after nav cursor moves
}
local _nav_reading = false

local function _nav_raw_down()
    if not hk or not hk.pad then return 0 end
    local ok, v = pcall(function() return hk.pad:call("get_ButtonDown") end)
    return (ok and v) or 0
end

local function _nav_raw_held()
    if not hk or not hk.pad then return 0 end
    local ok, v = pcall(function() return hk.pad:call("get_Button") end)
    return (ok and v) or 0
end

local function _nav_btn_trig(mask)
    _nav_reading = true
    local v = _nav_raw_down()
    _nav_reading = false
    return v % (mask + mask) >= mask
end

local function _nav_btn_held(mask)
    _nav_reading = true
    local v = _nav_raw_held()
    _nav_reading = false
    return v % (mask + mask) >= mask
end

local function _nav_axis()
    if not hk or not hk.pad then return 0, 0 end
    _nav_reading = true
    local ok, v = pcall(function() return hk.pad:call("get_AxisL") end)
    _nav_reading = false
    if not ok or not v then return 0, 0 end
    local DEAD = 0.5
    local dy = v.y < -DEAD and -1 or v.y > DEAD and 1 or 0
    local dx = v.x > DEAD and 1 or v.x < -DEAD and -1 or 0
    return dy, dx
end

-- GUI Builders

local build = {
    toggle = {},
    preset = {},
    option = {},
    backup = {},
}

function build.on_sync(to_sync, condition)
    if not condition or not state.sync_enabled then return end
    state.syncing = true
    to_sync()
    state.syncing = false
end

function build.setup_columns(widths, flags, names)
    for i, width in ipairs(widths) do
        local label = (names and names[i]) or ""
        imgui.table_setup_column(label, flags or 0, width)
    end
end

function build.tree_node_stateful(label, default_open)
    if state.force_tree_restore then
        local saved = state.tree_open[label]
        imgui.set_next_item_open(
            saved ~= nil and saved or (default_open or false),
            1
        )
    end
    local open = imgui.tree_node(label)
    state.tree_open[label] = open
    return open
end


local function menu_nav_handler()
    menu_nav.just_moved = false

    if not state.config.options.display_menu or not state.menu_window_focused then
        menu_nav.active = false
        menu_nav.rep_timer = 0
        menu_nav.slider_active = false
        return
    end
    menu_nav.active = true

    local n = #build.toggle.rows_list

    local axis_dy, axis_dx = _nav_axis()
    local axis_dy_trig = axis_dy ~= 0 and axis_dy ~= menu_nav.prev_dy
    local axis_dx_trig = axis_dx ~= 0 and axis_dx ~= menu_nav.prev_dx
    menu_nav.prev_dy, menu_nav.prev_dx = axis_dy, axis_dx

    local a_mask = (hk and hk.buttons and hk.buttons["A (X)"])      or 131104
    local b_mask = (hk and hk.buttons and hk.buttons["B (Circle)"]) or 262272

    -- ── Sync toggle via configurable hotkey (Y by default) ───────────────────
    if hk.check_hotkey("hotkeys_toggle_sync", nil, true) then
        state.sync_enabled = not state.sync_enabled
    end

    -- ── Slider editing mode ──────────────────────────────────────────────────
    -- In row columns: 2 = P1 opacity, 4 = P2 opacity
    local on_opacity_col = (menu_nav.column == 2 or menu_nav.column == 4)
    if menu_nav.slider_active and on_opacity_col then
        local trig_dx2 = (_nav_btn_trig(NAV_LEFT) and -1 or _nav_btn_trig(NAV_RIGHT) and 1 or 0)
        if trig_dx2 == 0 and axis_dx_trig then trig_dx2 = axis_dx end

        local held_dx2 = (_nav_btn_held(NAV_LEFT) and -1 or _nav_btn_held(NAV_RIGHT) and 1 or 0)
        if held_dx2 == 0 and axis_dx ~= 0 then held_dx2 = axis_dx end

        local delta = 0
        if trig_dx2 ~= 0 then
            delta = trig_dx2
            menu_nav.slider_rep = 0
        elseif held_dx2 ~= 0 then
            menu_nav.slider_rep = menu_nav.slider_rep + 1
            if menu_nav.slider_rep >= menu_nav.SLIDER_DELAY then
                menu_nav.slider_rep = menu_nav.SLIDER_DELAY - menu_nav.SLIDER_RATE
                delta = held_dx2
            end
        else
            menu_nav.slider_rep = 0
        end

        if delta ~= 0 then
            -- column 2 = P1 opacity, column 4 = P2 opacity
            local on_p1 = (menu_nav.column == 2)
            local cfg = on_p1 and state.config.p1 or state.config.p2
            local row = build.toggle.rows_list[menu_nav.selected]
            if row and row[3] and cfg and cfg.opacity[row[3]] ~= nil then
                local new_op = math.max(0, math.min(100, cfg.opacity[row[3]] + delta * menu_nav.SLIDER_STEP))
                cfg.opacity[row[3]] = new_op
                -- Live-sync to other player, matching mouse-drag behaviour
                if state.sync_enabled then
                    local other = on_p1 and state.config.p2 or state.config.p1
                    if other.opacity[row[3]] ~= nil then
                        other.opacity[row[3]] = new_op
                    end
                end
            end
        end

        -- A: confirm & save (with sync)
        if _nav_btn_trig(a_mask) then
            local on_p1 = (menu_nav.column == 2)
            local cfg   = on_p1 and state.config.p1 or state.config.p2
            local row   = build.toggle.rows_list[menu_nav.selected]
            if state.sync_enabled and row and row[3] and cfg then
                local other = on_p1 and state.config.p2 or state.config.p1
                if other.opacity[row[3]] ~= nil then
                    other.opacity[row[3]] = cfg.opacity[row[3]]
                end
            end
            mark_for_save()
            menu_nav.slider_active = false
            menu_nav.slider_orig   = nil
        end
        -- B: cancel & restore original value (and sync the restore)
        if _nav_btn_trig(b_mask) then
            local on_p1_b = (menu_nav.column == 2)
            local cfg_b = on_p1_b and state.config.p1 or state.config.p2
            local row_b = build.toggle.rows_list[menu_nav.selected]
            if row_b and row_b[3] and cfg_b and menu_nav.slider_orig ~= nil then
                cfg_b.opacity[row_b[3]] = menu_nav.slider_orig
                if state.sync_enabled then
                    local other_b = on_p1_b and state.config.p2 or state.config.p1
                    if other_b.opacity[row_b[3]] ~= nil then
                        other_b.opacity[row_b[3]] = menu_nav.slider_orig
                    end
                end
            end
            menu_nav.slider_active = false
            menu_nav.slider_orig   = nil
        end
        return
    end

    -- ── Vertical movement ────────────────────────────────────────────────────
    local trig_dy = (_nav_btn_trig(NAV_UP) and -1 or _nav_btn_trig(NAV_DOWN) and 1 or 0)
    if trig_dy == 0 and axis_dy_trig then trig_dy = axis_dy end

    local held_dy = (_nav_btn_held(NAV_UP) and -1 or _nav_btn_held(NAV_DOWN) and 1 or 0)
    if held_dy == 0 and axis_dy ~= 0 then held_dy = axis_dy end

    local prev_sel, prev_col = menu_nav.selected, menu_nav.column

    local function opacity_available(row_idx, col)
        -- col 2 = P1 opacity, col 4 = P2 opacity
        local cfg = (col == 2) and state.config.p1 or state.config.p2
        local row = build.toggle.rows_list[row_idx]
        return row and row[3]
            and cfg.toggle[row[2]]
            and cfg.opacity[row[3]] ~= nil
    end

    local function move_vertical(dy)
        local from_sel = menu_nav.selected
        local from_col = menu_nav.column
        menu_nav.selected = math.max(0, math.min(n, menu_nav.selected + dy))

        local going_to_header = (menu_nav.selected == 0)
        local coming_from_header = (from_sel == 0)

        if going_to_header then
            -- Map row col-space (1=P1tog, 2=P1op, 3=P2tog, 4=P2op) → header col-space (0=sync, 1=P1, 2=P2)
            if from_col == 1 or from_col == 2 then
                menu_nav.column = 1          -- P1 side → P1 header
            elseif from_col == 3 or from_col == 4 then
                menu_nav.column = 2          -- P2 side → P2 header
            end
            -- from_col==0 (sync) stays at 0 (only reachable if coming from the sync col in some edge case)

        elseif coming_from_header then
            -- Map header col-space → row col-space (always land on a toggle column)
            if from_col == 0 or from_col == 1 then
                menu_nav.column = 1          -- sync or P1 header → P1 toggle
            elseif from_col == 2 then
                menu_nav.column = 3          -- P2 header → P2 toggle
            end

        else
            -- Row → row: preserve player side, but check opacity availability
            if from_col == 2 or from_col == 4 then
                if opacity_available(menu_nav.selected, from_col) then
                    menu_nav.column = from_col
                else
                    menu_nav.column = (from_col == 2) and 1 or 3
                end
            end
            -- from_col 1 or 3 (toggle columns) carry over unchanged
        end
    end

    if trig_dy ~= 0 then
        move_vertical(trig_dy)
        menu_nav.rep_timer = 0
    elseif held_dy ~= 0 then
        menu_nav.rep_timer = menu_nav.rep_timer + 1
        if menu_nav.rep_timer >= menu_nav.REP_DELAY then
            menu_nav.rep_timer = menu_nav.REP_DELAY - menu_nav.REP_RATE
            move_vertical(held_dy)
        end
    else
        menu_nav.rep_timer = 0
    end

    -- ── Horizontal movement / slider activation ──────────────────────────────
    -- Column layout:
    --   Header row:  0=sync, 1=P1_header, 2=P2_header
    --   Toggle rows: 1=P1_toggle, 2=P1_opacity, 3=P2_toggle, 4=P2_opacity
    local trig_dx = (_nav_btn_trig(NAV_LEFT) and -1 or _nav_btn_trig(NAV_RIGHT) and 1 or 0)
    if trig_dx == 0 and axis_dx_trig then trig_dx = axis_dx end
    if trig_dx ~= 0 then
        if menu_nav.selected == 0 then
            -- Header row: cycle sync(0) → P1(1) → P2(2) → sync(0)
            menu_nav.column = (menu_nav.column + trig_dx) % 3
        else
            local row = build.toggle.rows_list[menu_nav.selected]
            local col = menu_nav.column

            -- Navigate 4-column layout: P1_toggle(1) ↔ P1_opacity(2)  /  P2_toggle(3) ↔ P2_opacity(4)
            -- Moving right from P1_opacity goes to P2_toggle, left from P2_toggle goes to P1_opacity
            local col_order = {1, 2, 3, 4}
            local col_pos = ({[1]=1,[2]=2,[3]=3,[4]=4})[col] or 1
            local new_col_pos = math.max(1, math.min(4, col_pos + trig_dx))
            local new_col = col_order[new_col_pos]

            -- Check whether the target opacity column actually has a slider to navigate to
            local function has_slider(player_col)
                local cfg = (player_col == 1 or player_col == 2) and state.config.p1 or state.config.p2
                return row and row[3] and cfg
                    and cfg.toggle[row[2]]
                    and cfg.opacity[row[3]] ~= nil
            end

            if (new_col == 2 or new_col == 4) and not has_slider(new_col) then
                -- Skip opacity column if no slider exists
                if trig_dx == 1 and new_col == 2 then new_col = 3       -- P1 opacity → P2 toggle
                elseif trig_dx == -1 and new_col == 2 then new_col = 1  -- already leftmost
                elseif trig_dx == 1 and new_col == 4 then new_col = 4   -- already rightmost
                elseif trig_dx == -1 and new_col == 4 then new_col = 3  -- P2 opacity → P2 toggle
                end
            end

            -- Just move the cursor; slider activation requires an explicit A press
            menu_nav.column        = new_col
            menu_nav.slider_active = false
            menu_nav.slider_orig   = nil
        end
    end

    if menu_nav.selected ~= prev_sel or menu_nav.column ~= prev_col then
        menu_nav.just_moved = true
    end

    -- ── A: activate slider / toggle checkbox ─────────────────────────────────
    if _nav_btn_trig(a_mask) then
        if menu_nav.selected == 0 then
            if menu_nav.column == 0 then
                state.sync_enabled = not state.sync_enabled
            elseif menu_nav.column == 1 then
                local new_val = not state.config.p1.toggle.toggle_show
                state.config.p1.toggle.toggle_show = new_val
                if state.sync_enabled then
                    state.config.p2.toggle.toggle_show = new_val
                end
                mark_for_save()
            elseif menu_nav.column == 2 then
                local new_val = not state.config.p2.toggle.toggle_show
                state.config.p2.toggle.toggle_show = new_val
                if state.sync_enabled then
                    state.config.p1.toggle.toggle_show = new_val
                end
                mark_for_save()
            end
        else
            local row = build.toggle.rows_list[menu_nav.selected]
            if row then
                local on_p1 = (menu_nav.column == 1 or menu_nav.column == 2)
                local cfg = on_p1 and state.config.p1 or state.config.p2

                if (menu_nav.column == 2 or menu_nav.column == 4) then
                    -- On an opacity column: A activates slider-edit mode
                    if cfg and row[3] and cfg.opacity[row[3]] ~= nil
                       and cfg.toggle[row[2]] then
                        menu_nav.slider_active = true
                        menu_nav.slider_orig   = cfg.opacity[row[3]]
                        menu_nav.slider_rep    = 0
                    end
                else
                    -- On a toggle column: A toggles the checkbox and syncs
                    local toggle_key = row[2]
                    if cfg and cfg.toggle[toggle_key] ~= nil then
                        local new_val = not cfg.toggle[toggle_key]
                        cfg.toggle[toggle_key] = new_val
                        if state.sync_enabled then
                            local other = on_p1 and state.config.p2 or state.config.p1
                            other.toggle[toggle_key] = new_val
                        end
                        mark_for_save()
                    end
                end
            end
        end
    end

    -- ── LB / RB: previous / next preset ─────────────────────────────────────
    local lb = (hk and hk.buttons and hk.buttons["LB (L1)"]) or 0
    local rb = (hk and hk.buttons and hk.buttons["RB (R1)"]) or 0
    if lb ~= 0 and _nav_btn_trig(lb) then load_previous_preset() end
    if rb ~= 0 and _nav_btn_trig(rb) then load_next_preset() end

    -- ── B: exit nav ──────────────────────────────────────────────────────────
    if _nav_btn_trig(b_mask) then
        menu_nav.active = false
        state.menu_window_focused = false
    end
end

-- build.toggle functions

function build.toggle.sync_button()
    local is_nav_on_sync = menu_nav.active and menu_nav.selected == 0 and menu_nav.column == 0
    local btn_label = state.sync_enabled and "Syncing Changes##sync_btn" or "Sync P1/P2 Changes##sync_btn"

    if state.sync_enabled then imgui.begin_rect() end
    if is_nav_on_sync     then imgui.begin_rect() end

    if imgui.button(btn_label, {0, 0}) then
        state.sync_enabled = not state.sync_enabled
    end

    -- Hover → update nav position (mouse and controller stay in sync)
    if imgui.is_item_hovered() and not menu_nav.slider_active then
        menu_nav.selected = 0
        menu_nav.column   = 0
    end

    if is_nav_on_sync     then imgui.end_rect(2) end
    if state.sync_enabled then imgui.end_rect(1) end
end

function build.toggle.column_header_sync()
    if not (state.config.p1.toggle.toggle_show or state.config.p2.toggle.toggle_show) then
        imgui.text("Show Hidden Elements:")
        return
    end

    build.toggle.sync_button()
end

function build.checkbox(label, val)
    local changed, new_val = imgui.checkbox(label, val)
    if changed then mark_for_save() end
    return changed, new_val
end

function build.toggle.opacity_slider(label, val, speed, min, max)
    val = math.max(0, math.min(100, val))
    local changed, new_val = imgui.drag_int(label, val, speed or 1.0, min or 0, max or 100)
    if changed then mark_for_save() end
    return changed, new_val
end

local function handle_toggle_column_header_player_notify(changed, player_str)
    if not changed then return end
    action_notify(player_str .. " Hitboxes " .. (state.config.p1.toggle.toggle_show and "Enabled" or "Disabled"), "alert_on_toggle")
end

function build.toggle.column_header_player(label, id, conf, nav_col)
    local is_nav = menu_nav.active and menu_nav.selected == 0 and menu_nav.column == nav_col
    if is_nav then imgui.begin_rect() end
    imgui.text(label)
    imgui.same_line()
    local cursor = imgui.get_cursor_pos()
    local changed
    imgui.set_cursor_pos(Vector2f.new(cursor.x + 20, cursor.y))
    changed, conf = build.checkbox(id, conf)
    -- Hover → update nav position
    if imgui.is_item_hovered() and not menu_nav.slider_active then
        menu_nav.selected = 0
        menu_nav.column   = nav_col
    end
    if is_nav then imgui.end_rect(2) end
    handle_toggle_column_header_player_notify(changed, label)
end

function build.toggle.column_headers()
    imgui.table_next_row()

    imgui.table_set_column_index(0)
    build.toggle.column_header_sync()

    imgui.table_set_column_index(1)
    build.toggle.column_header_player(
        "P1",
        "##p1_HideAllHeader",
        state.config.p1.toggle.toggle_show,
        1
    )

    imgui.table_set_column_index(3)
    build.toggle.column_header_player(
        "P2",
        "##p2_HideAllHeader",
        state.config.p2.toggle.toggle_show,
        2
    )
end

function build.toggle.column(player_index, visible, toggle_tbl, opacity_tbl, toggle_key, opacity_key, row_idx)
    if not visible then return end
    imgui.table_set_column_index(player_index)

    -- 4-column nav scheme: P1 toggle=1, P1 opacity=2, P2 toggle=3, P2 opacity=4
    local toggle_col_nav  = player_index == 1 and 1 or 3
    local opacity_col_nav = player_index == 1 and 2 or 4

    local is_toggle_nav = menu_nav.active
                       and menu_nav.selected == (row_idx or -1)
                       and menu_nav.column   == toggle_col_nav

    local is_opacity_nav = menu_nav.active
                        and menu_nav.selected == (row_idx or -1)
                        and menu_nav.column   == opacity_col_nav

    -- ── Checkbox ─────────────────────────────────────────────────────────────
    if is_toggle_nav then
        imgui.begin_rect()
        imgui.begin_rect()
    end

    local id = string.format("##p%.0f_", player_index) .. toggle_key
    local changed
    changed, toggle_tbl[toggle_key] = build.checkbox(id, toggle_tbl[toggle_key])

    -- Hover → update nav position
    if imgui.is_item_hovered() and not menu_nav.slider_active then
        menu_nav.selected = row_idx or -1
        menu_nav.column   = toggle_col_nav
    end

    if is_toggle_nav then
        imgui.end_rect(1)
        imgui.end_rect(2)
    end

    -- ── Opacity slider ────────────────────────────────────────────────────────
    local has_slider = opacity_key
                    and opacity_tbl ~= nil
                    and opacity_tbl[opacity_key] ~= nil
                    and toggle_tbl[toggle_key]

    if has_slider then
        imgui.push_item_width(70); imgui.same_line()
        local opacity_id     = string.format("##p%.0f_", player_index) .. opacity_key .. "Opacity"
        local is_slider_edit = is_opacity_nav and menu_nav.slider_active

        if is_slider_edit then
            -- Triple nested: very prominent "actively editing" state
            imgui.begin_rect()
            imgui.begin_rect()
            imgui.begin_rect()
        elseif is_opacity_nav then
            -- Double rect: slider is accessible
            imgui.begin_rect()
            imgui.begin_rect()
        end

        local op_changed, new_val = imgui.drag_int(opacity_id, opacity_tbl[opacity_key], 0.5, 0, 100)
        -- Only auto-save from mouse drag; nav-slider edits are saved explicitly via A
        if op_changed and not is_slider_edit then
            opacity_tbl[opacity_key] = new_val
            mark_for_save()
            build.on_sync(function()
                local other = (player_index == 1) and state.config.p2.opacity or state.config.p1.opacity
                other[opacity_key] = new_val
            end, op_changed)
        end

        -- Hover → update nav position (but don't override active slider)
        if imgui.is_item_hovered() and not menu_nav.slider_active then
            menu_nav.selected = row_idx or -1
            menu_nav.column   = opacity_col_nav
        end

        imgui.pop_item_width()

        if is_slider_edit then
            imgui.end_rect(1)
            imgui.end_rect(2)
            imgui.end_rect(1)
        elseif is_opacity_nav then
            imgui.end_rect(2)
            imgui.end_rect(1)
        end
    end

    build.on_sync(function()
        local other_toggle = (player_index == 1) and state.config.p2.toggle or state.config.p1.toggle
        other_toggle[toggle_key] = toggle_tbl[toggle_key]
        if not opacity_key then return end
        local other_opacity = (player_index == 1) and state.config.p2.opacity or state.config.p1.opacity
        other_opacity[opacity_key] = opacity_tbl[opacity_key]
    end, changed)
end

function build.toggle.columns(label, toggle_key, opacity_key, row_idx)
    imgui.table_set_column_index(0)
    -- Highlight row label whenever any column on this row is active
    if menu_nav.active and menu_nav.selected == (row_idx or 0)
       and menu_nav.column >= 1 and menu_nav.column <= 4 then
        imgui.text_colored("-> " .. label, 0xFFFFD040)
    else
        imgui.text(label)
    end

    build.toggle.column(1,
        state.config.p1.toggle.toggle_show,
        state.config.p1.toggle,
        state.config.p1.opacity,
        toggle_key, opacity_key, row_idx)

    build.toggle.column(3,
        state.config.p2.toggle.toggle_show,
        state.config.p2.toggle,
        state.config.p2.opacity,
        toggle_key, opacity_key, row_idx)
end

function build.toggle.row(label, toggle_key, opacity_key, row_idx)
    imgui.table_next_row()
    build.toggle.columns(label, toggle_key, opacity_key, row_idx)
end

function build.toggle.handle_toggle_all(toggle_tbl, player_index, all_checked)
    for k, _ in pairs(toggle_tbl) do
        toggle_tbl[k] = k == "toggle_show" or all_checked
    end

    build.on_sync(function()
        local other = (player_index == 1) and state.config.p2.toggle or state.config.p1.toggle
        for k, _ in pairs(other) do
            other[k] = k == "toggle_show" or all_checked
        end
    end)

    mark_for_save()
end

function build.toggle.all_click_toggle(toggle_tbl, player_index, checked)
    local changed
    changed, checked = build.checkbox("##p"..player_index.."_ToggleAll", checked)
    if not changed then return end

    build.toggle.handle_toggle_all(toggle_tbl, player_index, checked)
end

function build.toggle.player_toggle_all(player_index, toggle_tbl, opacity_tbl)
    if not toggle_tbl.toggle_show then return end
    imgui.table_set_column_index(player_index)

    local checked
    for k, v in pairs(toggle_tbl) do
        checked = k~= "toggle_show" and v
        if checked then break end
    end

    build.toggle.all_click_toggle(toggle_tbl, player_index, checked)
    if not checked then return end

    imgui.push_item_width(70); imgui.same_line()
    local first, all_same
    for _, v in pairs(opacity_tbl) do
        first = first or v
        all_same = v == v or first
        if all_same then break end
    end

    local changed
    local current = (all_same and first) or 50
    changed, current = build.toggle.opacity_slider("##p"..player_index.."_GlobalOpacity", current, 0.5, 0, 100)
    imgui.pop_item_width()

    if not changed then return end

    for k, _ in pairs(opacity_tbl) do
        opacity_tbl[k] = current
    end

    build.on_sync(function()
        local other = (player_index == 1) and state.config.p2.opacity or state.config.p1.opacity
        for k, _ in pairs(other) do other[k] = current end
    end)

    mark_for_save()
end

function build.toggle.all_row()
    imgui.table_next_row()
    imgui.table_set_column_index(0)
    imgui.text("All")
    build.toggle.player_toggle_all(1, state.config.p1.toggle, state.config.p1.opacity)
    imgui.table_set_column_index(2)
    build.toggle.player_toggle_all(3, state.config.p2.toggle, state.config.p2.opacity)
end

build.toggle.rows_list = {
    {"Hitbox", "hitboxes", "hitbox"},
    {"Hitbox Outline", "hitboxes_outline", "hitbox_outline"},
    {"Hitbox Tick Marks", "hitbox_ticks", "hitbox_tick"},
    {"Hurtbox", "hurtboxes", "hurtbox"},
    {"Hurtbox Outline", "hurtboxes_outline", "hurtbox_outline"},
    {"Pushbox", "pushboxes", "pushbox"},
    {"Pushbox Outline", "pushboxes_outline", "pushbox_outline"},
    {"Throwbox", "throwboxes", "throwbox"},
    {"Throwbox Outline", "throwboxes_outline", "throwbox_outline"},
    {"Throw Hurtbox", "throwhurtboxes", "throwhurtbox"},
    {"Throw Hurtbox Outline", "throwhurtboxes_outline", "throwhurtbox_outline"},
    {"Proximity Box", "proximityboxes", "proximitybox"},
    {"Proximity Box Outline", "proximityboxes_outline", "proximitybox_outline"},
    {"Proj. Clash Box", "clashboxes", "clashbox"},
    {"Proj. Clash Box Outline", "clashboxes_outline", "clashbox_outline"},
    {"Unique Box", "uniqueboxes", "uniquebox"},
    {"Unique Box Outline", "uniqueboxes_outline", "uniquebox_outline"},
    {"Properties", "properties", "properties"},
    {"Position", "position", "position"},
}

function build.toggle.rows()
    if not (state.config.p1.toggle.toggle_show or state.config.p2.toggle.toggle_show) then return end
    imgui.indent(6)

    for i, row in ipairs(build.toggle.rows_list) do
        build.toggle.row(row[1], row[2], row[3], i)
    end
    build.toggle.all_row()
end

function build.toggle.table()
    imgui.set_next_item_open(true, 1 << 3)
    if not imgui.begin_table("ToggleTable", 4) then return end
    build.setup_columns({160, 100, 30, 125}, nil, {"", "P1", "", "P2"})
    build.toggle.column_headers()
    build.toggle.rows()
    imgui.end_table()
end

-- build.preset functions

function build.preset.rename_input(preset_name)
    local changed
    changed, state.rename_temp_name = imgui.input_text("##rename_" .. preset_name, state.rename_temp_name, 32)
	if changed then mark_for_save() end
end

function build.preset.name_with_color(preset_name)
    if preset_name ~= state.current_preset_name then
		imgui.text(preset_name)
		return
	end

	local color = 0xFF00FF00
	if is_disabled_state() then color = 0xFF0000FF
	elseif preset_has_unsaved_changes() then color = 0xFF00FFFF end

	imgui.text_colored(preset_name, color)
end

function build.preset.name_column(preset_name)
    imgui.table_set_column_index(0)

    if state.rename_mode == preset_name then
        build.preset.rename_input(preset_name)
		return
	end
	
	build.preset.name_with_color(preset_name)
end

function build.preset.action_column(preset_name)
    imgui.table_set_column_index(1)

    if state.rename_mode == preset_name then
        if imgui.button("Rename##conf_" .. preset_name, {0, 0}) then save_rename(preset_name) end
    elseif is_disabled_state() or preset_name ~= state.current_preset_name then
        if imgui.button("Load##load_" .. preset_name, {0, 0}) then switch_preset(preset_name) end
    end
end

function build.preset.rename_column(preset_name)
	imgui.table_set_column_index(2)

    if state.rename_mode == preset_name then
        if imgui.button("Cancel##canc_" .. preset_name, {0, 0}) then cancel_rename_mode() end
		return
	end
	if imgui.button("Rename##ren_" .. preset_name, {0, 0}) then start_rename_mode(preset_name) end
end

function build.preset.duplicate_column(preset_name)
    imgui.table_set_column_index(3)

    if state.rename_mode == preset_name then return end
	if imgui.button("Duplicate##dup_" .. preset_name, {0, 0}) then duplicate_preset(preset_name) end
end

function build.preset.delete_column(preset_name)
    imgui.table_set_column_index(4)

    if state.rename_mode == preset_name then return end
	if state.delete_confirm_name ~= preset_name then
		if imgui.button("Delete##del_" .. preset_name, {0, 0}) then start_delete_confirm(preset_name) end
		return
	end
	
	if imgui.button("Delete?##del_" .. preset_name, {0, 0}) then
		delete_preset(preset_name)
		state.delete_confirm_name = false
	elseif imgui.is_mouse_clicked(0) and not imgui.is_item_hovered() then
		state.delete_confirm_name = false
	end
end

function build.preset.row(preset_name)
    imgui.table_next_row()
    build.preset.name_column(preset_name)
    build.preset.action_column(preset_name)
    build.preset.rename_column(preset_name)
    build.preset.duplicate_column(preset_name)
    build.preset.delete_column(preset_name)
end

function build.preset.rows()
	for _, preset_name in ipairs(state.preset_names) do
		build.preset.row(preset_name)
	end
end

function build.preset.table()
    if imgui.begin_table("PresetTable", 5, 64) then
        build.setup_columns({110, 60, 0, 0, 0})
		build.preset.rows()
        imgui.end_table()
    end
end

function build.preset.nav_switcher()
    imgui.same_line()
    if imgui.button("<", {20, 0}) then load_previous_preset() end
    if imgui.is_item_hovered() then
        imgui.set_tooltip("Previous (Ctrl + Left Arrow)")
    end
    imgui.same_line()
    if imgui.button(">", {20, 0}) then load_next_preset() end
    if imgui.is_item_hovered() then
        imgui.set_tooltip("Next (Ctrl + Right Arrow)")
    end
end

function build.preset.nav_status()
    if state.current_preset_name == "" then return end
    imgui.same_line()
    imgui.text("Current: ")
    imgui.same_line()
    build.preset.name_with_color(state.current_preset_name)
end

function build.preset.nav_reload_button()
    if not is_disabled_state() or state.current_preset_name == "" or not state.presets[state.current_preset_name] then return end
    imgui.same_line()
    if imgui.button("Reload##reload_nav") then
        load_preset(state.current_preset_name)
        action_notify("Reloaded Preset " .. state.current_preset_name, "alert_on_presets")
    end
    if imgui.is_item_hovered() then imgui.set_tooltip("Reset to saved values") end
end

function build.preset.nav_save_buttons()
    if is_disabled_state() then return end
    if preset_has_unsaved_changes() then
        imgui.same_line()
        if imgui.button("Save##save_nav") then save_current_preset(state.current_preset_name) end
        if imgui.is_item_hovered() then imgui.set_tooltip("Save Changes (Ctrl + Space)") end
        imgui.same_line()
        if imgui.button("x##disc_nav") then
            load_preset(state.current_preset_name)
            action_notify("Changes Discarded", "alert_on_presets")
        end
    end
end

function build.preset.nav_new_button()
    if is_disabled_state() or not preset_has_unsaved_changes() then
        imgui.same_line()
        if imgui.button("New##create_new") then start_create_new_mode() end
    end
end

function build.preset.nav()
    if state.create_new_mode then return end
    build.preset.nav_switcher()
    build.preset.nav_status()
    build.preset.nav_save_buttons()
    build.preset.nav_reload_button()
    build.preset.nav_new_button()
end

function build.preset.create_name_input()
    local changed
    changed, state.new_preset_name = imgui.input_text("##preset_name", state.new_preset_name)
end

function build.preset.create_buttons()
    if state.new_preset_name == "" then
        if imgui.button("New##new_blank") then create_new_blank_preset() end
        imgui.same_line()
        if imgui.button("Cancel##cancel_blank") then cancel_blank_preset() end
    else
        if imgui.button("Create##save_new") then save_new_preset() end
        imgui.same_line()
        if imgui.button("x##cancel_new") then cancel_new_preset() end
    end
end

function build.preset.creator()
    if not state.create_new_mode then return end
    imgui.same_line()
    imgui.text("New:")
    imgui.push_item_width(100); imgui.same_line()
    build.preset.create_name_input()
    imgui.pop_item_width(); imgui.same_line()
    build.preset.create_buttons()
end

function build.preset.display()
    if state.create_new_mode then build.preset.creator() else build.preset.nav() end
end

function build.preset.menu()
    imgui.unindent(10)
    if not build.tree_node_stateful("Presets", true) then
        build.preset.display()
        return
    end
    build.preset.display()
    build.preset.table()
    imgui.tree_pop()
end

-- build.backup functions (merged Backup/Reset)

function build.backup.menu()
    if not build.tree_node_stateful("Backup/Reset") then return end
    build.option.reset()
    build.option.backup()
    imgui.tree_pop()
end

-- build.option functions

function build.option.copy_rows()
    imgui.same_line(); imgui.spacing(); imgui.same_line()
    if imgui.button("P1 to P2##p1_to_p2", {nil, 16}) then
        state.config.p2 = deep_copy(state.config.p1)
    end
    imgui.same_line(); imgui.spacing(); imgui.same_line()
    if imgui.button("P2 to P1##p2_to_p1", {nil, 16}) then
        state.config.p1 = deep_copy(state.config.p2)
    end
end

function build.option.copy()
    if not build.tree_node_stateful("Copy") then return end
    build.option.copy_rows()
    imgui.tree_pop()
end

function build.option.reset_row(col_name, func)
    local handler_str = "P%.0f##%s_p%.0f"
    local handler_p1, handler_p2 = string.format(handler_str, 1, string.lower(col_name), 1), string.format(handler_str, 2, string.lower(col_name), 2)
    local handler_all = string.format("All##%s_all", string.lower(col_name))
    imgui.table_next_row()
    imgui.table_set_column_index(0)
    imgui.text(col_name)
    imgui.table_set_column_index(1)
    if imgui.button(handler_p1, {nil, 16}) then func('p1') end
    imgui.table_set_column_index(2)
    if imgui.button(handler_p2, {nil, 16}) then func('p2') end
    imgui.table_set_column_index(3)
    if imgui.button(handler_all, {nil, 16}) then func() end
end

function build.option.reset_rows()
    build.option.reset_row("Toggles", reset_toggle_default)
    build.option.reset_row("Opacity", reset_opacity_default)
    build.option.reset_row("All", reset_all_default)
end

function build.option.reset_table()
	if not imgui.begin_table("ResetTable", 4) then return end
	build.option.reset_rows()
	imgui.end_table()
    imgui.spacing()
end

function build.option.reset()
    if not build.tree_node_stateful("Reset") then return end

    build.option.reset_table()

    if state.restore_presets_confirm then
        if imgui.button("Delete All Presets And Restore##restore_presets") then
            restore_presets()
            state.restore_presets_confirm = false
        end
        imgui.same_line()
        if imgui.button("Cancel##factory_cancel") then
            state.restore_presets_confirm = false
        end
    else
        if imgui.button("Restore Default Presets##restore_presets") then
            state.restore_presets_confirm = true
        end
    end

    imgui.tree_pop()
end

function build.option.alerts_row(label, config_key)
    local changed
    changed, state.config.options[config_key] = build.checkbox(label .. "##" .. config_key, state.config.options[config_key])
end

function build.option.alerts_hide_checkbox()
	local changed
    imgui.same_line()
    changed, state.config.options.hide_all_alerts =  build.checkbox("Hide##hide_all_alerts", state.config.options.hide_all_alerts)
end

function build.option.alerts_duration_slider()
    if state.config.options.hide_all_alerts then return end
    imgui.text("Duration:")
    imgui.same_line(); imgui.push_item_width(100)
	local changed
    changed, state.config.options.notify_duration = imgui.slider_float("##notify_duration", state.config.options.notify_duration, 0.1, 10.0, "%.1f s")
	if changed then mark_for_save() end
	imgui.pop_item_width()
end

function build.option.alerts_rows()
    imgui.text("Notify:")
    build.option.alerts_row("Overlay Toggled", "alert_on_toggle")
    imgui.same_line()
    build.option.alerts_row("Preset Switched", "alert_on_presets")
    imgui.same_line()
    build.option.alerts_row("Preset Saved", "alert_on_save")
end

function build.option.alerts()
    if not build.tree_node_stateful("Alerts") then return end
    build.option.alerts_hide_checkbox()
    build.option.alerts_duration_slider()
    if not state.config.options.hide_all_alerts then
        build.option.alerts_rows()
    end
    imgui.tree_pop()
end

local function are_hotkeys_default()
    for key, default_val in pairs(hk.default_hotkeys) do
        local current = hk.hotkeys[key]
        if current == "[Press Input]" and current == default_val then end
		return false
    end
    return true
end

local function is_any_hotkey_rebinding()
    for _, value in pairs(hk.hotkeys) do
        if value ~= "[Press Input]" then end
		return true
    end
    return false
end

function build.option.hotkeys_reset_button()
    if are_hotkeys_default() then return end
    imgui.same_line()

    if state.confirm_restore_hotkeys == nil then state.confirm_restore_hotkeys = false end

    if is_any_hotkey_rebinding() then
        if imgui.button("Restore Defaults") then
            for name, value in pairs(hk.hotkeys) do
                if value == "[Press Input]" then
                    hk.hotkeys[name] = hk.default_hotkeys[name] or "[Not Bound]"
                end
            end
            hk.reset_from_defaults_tbl(hk.default_hotkeys)
            state.confirm_restore_hotkeys = false
        end
    else
        if state.confirm_restore_hotkeys then
            if imgui.button("Restore Defaults?") then
                hk.reset_from_defaults_tbl(hk.default_hotkeys)
                state.confirm_restore_hotkeys = false
            end
            if imgui.is_mouse_clicked(0) and not imgui.is_item_hovered() then
                state.confirm_restore_hotkeys = false
            end
        else
            if imgui.button("Restore Defaults") then
                state.confirm_restore_hotkeys = true
            end
        end
    end
end

function build.option.hotkey_button(text, hotkey_str)
    imgui.text(text)
    imgui.same_line()
    if not hk.hotkey_setter(hotkey_str, nil, "") then return end
	hk.update_hotkey_table(state.config.hotkeys)
	mark_for_save()
end

function build.option.hotkey_buttons()
	build.option.hotkeys_reset_button()
    build.option.hotkey_button("Toggle Menu:", "hotkeys_toggle_menu")
    build.option.hotkey_button("Toggle P1:", "hotkeys_toggle_p1")
    build.option.hotkey_button("Toggle P2:", "hotkeys_toggle_p2")
    build.option.hotkey_button("Toggle All:", "hotkeys_toggle_all")
    build.option.hotkey_button("Toggle Sync:", "hotkeys_toggle_sync")
    build.option.hotkey_button("Last Preset:", "hotkeys_prev_preset")
    build.option.hotkey_button("Next Preset:", "hotkeys_next_preset")
    build.option.hotkey_button("Save Preset:", "hotkeys_save_preset")
end


function build.option.hotkeys()
    if not build.tree_node_stateful("Hotkeys") then return end
    imgui.same_line()
    imgui.spacing()
    build.option.hotkey_buttons()
    imgui.tree_pop()
end

function build.option.modes()
    local open = build.tree_node_stateful("Modes")
    if open then
        imgui.same_line()
        if imgui.button("Defaults##modes") then
            local default = create_default_config()
            state.config.options.mode_training      = default.options.mode_training
            state.config.options.mode_replay        = default.options.mode_replay
            state.config.options.mode_local_versus  = default.options.mode_local_versus
            state.config.options.mode_single_player = default.options.mode_single_player
            mark_for_save()
        end
        local changed
        changed, state.config.options.mode_training      = build.checkbox("Training",            state.config.options.mode_training)
        changed, state.config.options.mode_replay        = build.checkbox("Replays",              state.config.options.mode_replay)
        changed, state.config.options.mode_local_versus  = build.checkbox("Local Versus",         state.config.options.mode_local_versus)
        changed, state.config.options.mode_single_player = build.checkbox("Single Player Modes",  state.config.options.mode_single_player)
        imgui.tree_pop()
    end
end

function build.option.misc()
    if not build.tree_node_stateful("Misc") then return end
    local changed
    changed, state.config.options.color_wall_splat = build.checkbox("Adjust Position color in wall splat range", state.config.options.color_wall_splat)
    changed, state.config.options.range_ticks_show = build.checkbox("Show hitbox tick marks", state.config.options.range_ticks_show)
    imgui.tree_pop()
end

function build.option.backup_row()
    imgui.text("File:")
    imgui.push_item_width(200); imgui.same_line()
    local changed, new_name = imgui.input_text("##backup_filename", state.backup_filename, 256)
    if changed then state.backup_filename = new_name end
    imgui.pop_item_width(); imgui.same_line()
    if imgui.button("Export") then perform_backup(state.backup_filename) end
end

function build.option.backup()
    if not build.tree_node_stateful("Backup") then return end
    if state.backup_filename == "" then
        state.backup_filename = generate_default_backup_filename()
    end
    imgui.same_line()
	build.option.backup_row()
    imgui.tree_pop()
end

function build.option.menu()
    if not build.tree_node_stateful("Options") then return end
    imgui.unindent(15)
    build.option.copy()
    build.backup.menu()   -- merged Backup/Reset group
    build.option.alerts()
    build.option.hotkeys()
    build.option.modes()
    build.option.misc()
    imgui.tree_pop()
    imgui.indent(15)
end

local function get_toggle_hotkey_display()
    local hotkey = hk.hotkeys["hotkeys_toggle_menu"]
    if not hotkey or hotkey == "[Not Bound]" then
        state.last_menu_hotkey_display = ""
        return ""
    end
    local full_str = hk.get_button_string("hotkeys_toggle_menu")
    if full_str:find("%[Press Input%]") then
        return state.last_menu_hotkey_display
    end
    local display = " (" .. full_str .. ")"
    state.last_menu_hotkey_display = display
    return display
end

local function build_menu()
    local title = "Hitboxes" .. get_toggle_hotkey_display()
    state.force_tree_restore = (title ~= state.last_menu_title)
    state.last_menu_title = title
    if state.menu_window_pos and state.force_tree_restore then
        imgui.set_next_window_pos(state.menu_window_pos, 1)
    end
    imgui.begin_window(title, true, 64)
    state.menu_window_pos = imgui.get_window_pos()
    local wpos  = imgui.get_window_pos()
    local wsize = imgui.get_window_size()
    local mouse = imgui.get_mouse()
    state.menu_window_focused = mouse.x >= wpos.x and mouse.x <= wpos.x + wsize.x
                             and mouse.y >= wpos.y and mouse.y <= wpos.y + wsize.y
    build.toggle.table()
    build.preset.menu()
    build.option.menu()

    -- Draw controller-nav active outline (sampled after layout so size is final)
    if menu_nav.active then
        local p  = imgui.get_window_pos()
        local sz = imgui.get_window_size()
        local cx, cy = p.x + sz.x * 0.5, p.y + sz.y * 0.5
        draw.outline_rect(cx, cy, sz.x,     sz.y,     0xFFFFD040)
        draw.outline_rect(cx, cy, sz.x - 2, sz.y - 2, 0x80FFD040)
    end

    imgui.end_window()
    state.force_tree_restore = false
end

local function all_toggles_hidden()
    return state.config.p1.toggle.toggle_show or state.config.p2.toggle.toggle_show
end

local function gui_handler()
    if state.config.options.display_menu then build_menu() end
    if not is_in_battle() then return end
    if not is_pause_menu_closed() then return end
    if not all_toggles_hidden() then return end
    if not is_mode_allowed() then return end
    process_hitboxes()
end

local function draw_ui_handler()
    if not imgui.tree_node("Hitbox Viewer") then return end
	local changed
    changed, state.config.options.display_menu = build.checkbox("Display Options Menu", state.config.options.display_menu)
    imgui.tree_pop()
end

-- Hotkey Handling

local function hotkey_handler()
    if hk.check_hotkey("hotkeys_toggle_menu") then
        state.config.options.display_menu = not state.config.options.display_menu
        mark_for_save()
    end
    if hk.check_hotkey("hotkeys_toggle_p1") then
        state.config.p1.toggle.toggle_show = not state.config.p1.toggle.toggle_show
        action_notify("P1 Hitboxes " .. (state.config.p1.toggle.toggle_show and "Enabled" or "Disabled"), "alert_on_toggle")
        mark_for_save()
    end
    if hk.check_hotkey("hotkeys_toggle_p2") then
        state.config.p2.toggle.toggle_show = not state.config.p2.toggle.toggle_show
        action_notify("P2 Hitboxes " .. (state.config.p2.toggle.toggle_show and "Enabled" or "Disabled"), "alert_on_toggle")
        mark_for_save()
    end
    if hk.check_hotkey("hotkeys_toggle_all") then
        local any_active = state.config.p1.toggle.toggle_show or state.config.p2.toggle.toggle_show
        state.config.p1.toggle.toggle_show = not any_active
        state.config.p2.toggle.toggle_show = not any_active
        action_notify("All Hitboxes " .. (not any_active and "Enabled" or "Disabled"), "alert_on_toggle")
        mark_for_save()
    end
    if hk.check_hotkey("hotkeys_prev_preset") then
        load_previous_preset()
    end
    if hk.check_hotkey("hotkeys_next_preset") then
        load_next_preset()
    end
    if hk.check_hotkey("hotkeys_save_preset") then
        save_current_preset(state.current_preset_name)
    end
end

-- Main Initialization and Frame Loop

state.initialized = false

local function initialize()
    load_config()
    if state.current_preset_name == "" then 
        state.current_preset_name = get_preset_name()
    end
    state.initialized = true
end

re.on_draw_ui(draw_ui_handler)

re.on_frame(function()
	object_handler()
	save_handler()
	hotkey_handler()
	menu_nav_handler()
	gui_handler()
	tooltip_handler()
	action_notify_handler()
end)

if not state.initialized then initialize() end