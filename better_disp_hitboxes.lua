local MOD_NAME = "Better Hitbox Viewer"
local state = {initialized = false}

-- Utilities

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

-- Game Objects & Context

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
		state.sWork = state.sWork or
            gBattle:get_field("Work"):get_data(nil)
		state.sPlayer = state.sPlayer or
            gBattle:get_field("Player"):get_data(nil)
        state.sSetting = state.sSetting or
            gBattle:get_field("Setting"):get_data(nil)
		return
	end

	gBattle = sdk.find_type_definition("gBattle")
end

local GAME_MODES = {
    [0] = "NONE", [1] = "ARCADE",
    [2] = "TRAINING", [3] = "VERSUS_2P",
    [4] = "VERSUS_CPU", [5] = "TUTORIAL",
    [6] = "CHARACTER_GUIDE", [7] = "MISSION",
    [8] = "DEATHMATCH", [9] = "STORY",
    [10] = "STORY_TRAINING", [11] = "STORY_MATCH",
    [12] = "STORY_TUTORIAL", [13] = "STORY_SPECTATE",
    [14] = "RANKED_MATCH", [15] = "PLAYER_MATCH",
    [16] = "CABINET_MATCH", [17] = "CUSTOM_ROOM_MATCH",
    [18] = "ONLINE_TRAINING", [19] = "TEAMBATTLE",
    [20] = "EXAM_CPU_MATCH", [21] = "CABINET_CPU_MATCH",
    [22] = "LEARNING_AI_MATCH", [23] = "LEARNING_AI_SPECTATE",
    [24] = "REPLAY", [25] = "SPECTATE",
    [26] = "LOCAL_MATCH", [27] = "STORY_LOCAL_MATCH",
    [28] = "JOY_MATCH", [29] = "JOY_BATTLE",
}

local TRAINING_MODES = { [2]=true, [10]=true, [18]=true }

local REPLAY_MODES = { [24]=true }

local SPECTATE_MODES = { [13]=true, [23]=true, [25]=true }

local SINGLE_PLAYER_MODES = {
    [1]=true, [4]=true, [5]=true, 
    [6]=true, [7]=true, [9]=true,
    [10]=true, [11]=true, [12]=true, 
    [13]=true, [26]=true, [27]=true
}

local function get_scene_id()
    if not bFlowManager then return nil end
    return bFlowManager:get_GameMode() or 0
end

local function is_training_mode()
    if not TrainingManager then return false end
    local mode = TrainingManager:get_field("GameMode")
    return TRAINING_MODES[mode] == true
end

local function is_in_battle()
    if not state.sPlayer then return false end
    for _, player in pairs(state.sPlayer.mcPlayer) do
        if player.mpActParam then return true end
    end
    return false
end

local function get_game_mode_id()
    if not is_in_battle() then return 0 end
    if TrainingManager then
        local mode = TrainingManager:get_field("GameMode")
        if mode and mode ~= 0 then return mode end
    end
    if state.sSetting then
        local mode = state.sSetting:get_field("GameMode")
        if mode and mode ~= 0 then return mode end
    end
    if bFlowManager then
        local mode = bFlowManager:get_GameMode()
        if mode and mode ~= 0 then return mode end
    end
    return 0
end

local function read_training_display_super_freeze_state()
    if not TrainingManager or not TrainingManager._tCommon then
        return false, 0, 0, nil, 0, 0
    end

    local snap = TrainingManager._tCommon.SnapShotDatas
    if not snap or not snap[0] or not snap[0]._DisplayData then
        return false, 0, 0, nil, 0, 0
    end

    local display = snap[0]._DisplayData
    local fm_stop_frame = tonumber(display.FMStopFrame) or 0
    local stop_attack_frame = tonumber(display.StopAttackFrame) or 0
    local special_state = display.SpecialState
    local special_state_value = type(special_state) == "number" and special_state or nil
    local player_datas = display.PlayerDatas or {}
    local p1_data = player_datas[0] or player_datas["0"]
    local p2_data = player_datas[1] or player_datas["1"]
    local p1_hitstop_own = tonumber(p1_data and p1_data.hitStopOwnFrame) or 0
    local p2_hitstop_own = tonumber(p2_data and p2_data.hitStopOwnFrame) or 0

    if special_state_value == nil and special_state ~= nil then
        local ok_enum, enum_value = pcall(function() return special_state.value__ end)
        if ok_enum then
            special_state_value = tonumber(enum_value)
        end
    end

    return fm_stop_frame > 0, fm_stop_frame, stop_attack_frame, special_state_value, p1_hitstop_own, p2_hitstop_own
end

local function is_mode_allowed()
    local mode = get_game_mode_id()
    if TRAINING_MODES[mode] then
        return state.config.options.mode_training
    end
    if REPLAY_MODES[mode]   then
        return state.config.options.mode_replay
    end
    if SPECTATE_MODES[mode] then
        return state.config.options.mode_spectate
    end
    if SINGLE_PLAYER_MODES[mode] then
        return state.config.options.mode_single_player 
    end
    return state.config.options.mode_other
end

local PAUSE_TYPE_BITS = {
    [2]=true, [320]=true, [256]=true,
    [324]=true, [2112]=false, [2368]=true, [4294967616]=true
}

-- Modes where pause_type_bit=0 means unpaused and any non-zero value means paused.
-- (Most modes use specific non-zero bits to signal unpaused states, but these
-- modes use 0 as their unpaused sentinel instead.)
local ZERO_UNPAUSED_MODES = { [10]=true, [13]=true }

local function is_pause_menu_closed()
    if not PauseManager then return true end
    local pause_type_bit = PauseManager:get_field("_CurrentPauseTypeBit")
    local mode = get_game_mode_id()
    if ZERO_UNPAUSED_MODES[mode] then
        -- bit=0 → unpaused (closed); any non-zero bit → paused (open)
        return pause_type_bit == 0
    end
    return not PAUSE_TYPE_BITS[pause_type_bit]
end

-- Hotkeys (hk)

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

	local registered_actions     = {}  -- {name=action_name, fn=callback}
	local registered_raw_actions = {}  -- fn() called unconditionally each frame

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

	-- Converts internal key names to user-friendly display strings.
	-- "Alpha1" → "1", "Alpha2" → "2", etc.  All other names pass through unchanged.
	local function fmt_key_display(key_name)
		if not key_name or key_name == "[Not Bound]" then
			return ""
		end
		return (key_name:gsub("^Alpha(%d+)$", "%1"))
	end

	local function get_button_string(action_name)
		local modifier = hotkeys[action_name.."_$"]
		modifier = modifier and modifier ~= "[Not Bound]" and fmt_key_display(modifier).." + " or ""
		local main = fmt_key_display(hotkeys[action_name])
		local result = modifier .. main
		return result ~= "" and result or nil
	end

	local function reset_from_defaults_tbl(default_hotkey_table)
		for key, value in pairs(default_hotkey_table) do
			hotkeys[key] = value
			if not default_hotkey_table[key.."_$"] then
				hotkeys[key.."_$"] = "[Not Bound]"
				hk_data.modifier_actions[key.."_$"] = "[Not Bound]"
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
				local modifier_active = hotkeys[action_name.."_$"] and hotkeys[action_name.."_$"] ~= "[Not Bound]"
				hotkeys_down[action_name] = (kb_state.down[keys[key_name ] ]  or gp_state.down[buttons[key_name ] ] or mb_state.down[mbuttons[key_name ] ]) and (not modifier_active or check_hotkey(action_name.."_$", true))
			end
			return hotkeys_down[action_name]
		elseif check_triggered or type(check_down) ~= "nil" then
			local modifier_active = hotkeys[action_name.."_$"] and hotkeys[action_name.."_$"] ~= "[Not Bound]"
			if hotkeys_trig[action_name] == nil then
				hotkeys_trig[action_name] = (kb_state.triggered[keys[key_name ] ]  or gp_state.triggered[buttons[key_name ] ] or mb_state.triggered[mbuttons[key_name ] ]) and (not modifier_active or check_hotkey(action_name.."_$", true))
			end
			return hotkeys_trig[action_name]
		elseif hotkeys_up[action_name] == nil then
			local modifier_active = hotkeys[action_name.."_$"] and hotkeys[action_name.."_$"] ~= "[Not Bound]"
			hotkeys_up[action_name] = (kb_state.released[keys[key_name ] ]  or gp_state.released[buttons[key_name ] ] or mb_state.released[mbuttons[key_name ] ]) and (not modifier_active or check_hotkey(action_name.."_$", true))
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

	-- Returns the set of key names considered equivalent to key_name for conflict
	-- checking.  Handles the three modifier families where a logical name ("Control")
	-- and its physical variants ("LControl", "RControl") are interchangeable.
	local function get_key_family(key_name)
		if key_name == "LControl" or key_name == "RControl" or key_name == "Control" then
			return {LControl=true, RControl=true, Control=true}
		elseif key_name == "LAlt" or key_name == "RAlt" or key_name == "Alt" then
			return {LAlt=true, RAlt=true, Alt=true}
		elseif key_name == "LShift" or key_name == "RShift" then
			return {LShift=true, RShift=true}
		end
		return {[key_name]=true}
	end

	-- Returns true when key_name (or any family member) is already used in a slot
	-- that does not belong to the action currently being rebound.
	--
	-- Rule for modifier slots (_$): other modifier slots are skipped — the same
	-- modifier key may be shared across multiple hotkeys.  Main binding slots of
	-- other actions still block (can't use a key as both a main binding and a
	-- modifier of a different action).
	--
	-- Rule for main binding slots: all foreign slots (main + modifier) are checked,
	-- so a key in use as anyone's modifier cannot become a main binding.
	local function is_key_bound_elsewhere(key_name, current_action)
		local family = get_key_family(key_name)
		local base = current_action
		if base:sub(-2) == "_$" then base = base:sub(1, -3) end
		local own = { [base]=true, [base.."_$"]=true }
		local current_is_mod = (current_action:sub(-2) == "_$")
		for name, bound_key in pairs(hotkeys) do
			if not own[name] and family[bound_key] then
				-- When binding a modifier slot, skip other modifier slots
				-- (shared modifier keys are allowed; combo uniqueness is enforced separately).
				if current_is_mod and name:sub(-2) == "_$" then
					-- allowed — do not flag as conflict
				else
					return true
				end
			end
		end
		return false
	end

	-- Returns true when key_name (or any family member) matches this action's own
	-- modifier.  Only meaningful for main binding slots; modifier slots have no
	-- modifier of their own.
	local function is_key_own_modifier_family(key_name, action_name)
		if action_name:sub(-2) == "_$" then return false end
		local own_mod = hotkeys[action_name .. "_$"]
		if not own_mod or own_mod == "[Not Bound]" or own_mod == "[Press Input]" then
			return false
		end
		return get_key_family(own_mod)[key_name] ~= nil
	end

	-- When binding a modifier slot, checks that the resulting combo (candidate
	-- modifier + this action's main key) is not already in use by another action.
	-- E.g. if "Ctrl+Left" is taken, binding "Ctrl" as the modifier for any other
	-- action whose main key is "Left" is rejected.
	local function is_combo_bound_elsewhere(modifier_key, action_name)
		if action_name:sub(-2) ~= "_$" then return false end
		local base = action_name:sub(1, -3)
		local main_key = hotkeys[base]
		if not main_key or main_key == "[Not Bound]" or main_key == "[Press Input]" then
			return false
		end
		local mod_family = get_key_family(modifier_key)
		for name, bound_key in pairs(hotkeys) do
			-- Check all main binding slots other than this action's own base
			if name:sub(-2) ~= "_$" and name ~= base and bound_key == main_key then
				local their_mod = hotkeys[name .. "_$"]
				if their_mod and their_mod ~= "[Not Bound]" and their_mod ~= "[Press Input]" then
					if mod_family[their_mod] then
						return true
					end
				end
			end
		end
		return false
	end

	local function hotkey_setter(action_name, hold_action_name, fake_name, title_tooltip)

		local key_updated = false
		local is_down = check_hotkey(action_name, true) and (not hold_action_name or check_hotkey(hold_action_name, true))
		local disp_name = (fake_name and ((type(fake_name)~="string") and "" or fake_name)) or action_name
		local is_mod_1 = (action_name:sub(-2, -1) == "_$")
		local default = default_hotkeys[action_name]

		local had_hold = not not hold_action_name
		hold_action_name = hold_action_name and ((hotkeys[hold_action_name] ~= "[Not Bound]") and (hotkeys[hold_action_name] ~= "[Press Input]")) and hold_action_name
		local modifier_hotkey = hold_action_name and get_button_string(hold_action_name)
		modifiers[action_name] = hold_action_name

		if is_down then imgui.begin_rect(); imgui.begin_rect() end
		imgui.push_id(action_name)
			hotkeys[action_name] = hotkeys[action_name] or default
			if not hotkeys[action_name] then hotkeys[action_name] = "[Not Bound]" end
			if hotkeys[action_name] == "[Press Input]" then
				local up = pad and pad:call("get_ButtonUp")
				if up and up ~= 0 then
					for button_name, id in pairs(buttons) do
						if (up | id) == up then
							if not is_key_bound_elsewhere(button_name, action_name)
							   and not is_key_own_modifier_family(button_name, action_name)
							   and not is_combo_bound_elsewhere(button_name, action_name) then
								hotkeys[action_name] = button_name
								key_updated = true
								goto exit
							end
						end
					end
				end
				if not is_mod_1 and mouse and m_up and m_up ~= 0 then
					for button_name, id in pairs(mbuttons) do
						if (m_up | id) == m_up then
							-- L Mouse and R Mouse are reserved for UI interaction
							if button_name ~= "L Mouse" and button_name ~= "R Mouse"
							   and not is_key_bound_elsewhere(button_name, action_name)
							   and not is_key_own_modifier_family(button_name, action_name)
							   and not is_combo_bound_elsewhere(button_name, action_name) then
								hotkeys[action_name] = button_name
								key_updated = true
								goto exit
							end
						end
					end
				end
				for key_name, id in pairs(keys) do
					-- F1 is a fixed system hotkey and cannot be rebound to any action
					if key_name ~= "F1" and kb and kb:call("isRelease", id) then
						if (not is_mod_1) or valid_modifier_keys[key_name] then
							if not is_key_bound_elsewhere(key_name, action_name)
							   and not is_key_own_modifier_family(key_name, action_name)
							   and not is_combo_bound_elsewhere(key_name, action_name) then
								hotkeys[action_name] = key_name
								key_updated = true
								goto exit
							end
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

		if not is_mod_1 and (hotkeys[action_name.."_$"] ~= nil or default_hotkeys[action_name.."_$"] ~= nil) then
			if hotkey_setter(action_name.."_$", nil, true) then key_updated = true end
			imgui.same_line()
			imgui.text("+")
			imgui.same_line()
		end

			if imgui.button( ((modifier_hotkey and (modifier_hotkey .. " + ")) or "") .. fmt_key_display(hotkeys[action_name])) then
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
						if not hotkeys[action_name] then hotkeys[action_name] = "[Not Bound]" end
						if not hotkeys[action_name.."_$"] then hotkeys[action_name.."_$"] = "[Not Bound]" end
						json.dump_file("Hotkeys_data.json", hk_data)
					else
						hotkeys[action_name] = "[Not Bound]"
					end
					key_updated = true
					setup_active_keys_tbl()
					trigger_hotkey_change_callbacks()
				end
				if default_hotkeys[action_name] and imgui.menu_item("Reset to Default") then
					hotkeys[action_name] = default_hotkeys[action_name]
					key_updated = true
					setup_active_keys_tbl()
					trigger_hotkey_change_callbacks()
				end
				if not is_mod_1 and hotkeys[action_name] ~= "[Not Bound]" and imgui.menu_item((hotkeys[action_name.."_$"] and hotkeys[action_name.."_$"] ~= "[Not Bound]" and "Disable " or "Enable ") .. "Modifier") then
					hotkeys[action_name.."_$"] = not hotkeys[action_name.."_$"] and ((pad and pad:get_Connecting() and "LT (L2)") or "LAlt") or "[Not Bound]"
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

	hk = hk or {
		kb = kb,
		mouse = mouse,
		pad = pad,
		keys = keys,
		buttons = buttons,
		mbuttons = mbuttons,
		hotkeys = hotkeys,
		default_hotkeys = default_hotkeys,
		kb_state = kb_state,
		gp_state = gp_state,
		mb_state = mb_state,
		recurse_def_settings = recurse_def_settings,
		find_index = find_index,
		merge_tables = merge_tables,
		merge_tables_recursively = merge_tables_recursively,
		generate_statics = generate_statics,
		setup_hotkeys = setup_hotkeys,
		reset_from_defaults_tbl = reset_from_defaults_tbl,
		update_hotkey_table = update_hotkey_table,
		get_button_string = get_button_string,
		hotkey_setter = hotkey_setter,
		check_hotkey = check_hotkey,
		check_doubletap = check_doubletap,
		check_hold = check_hold,
		chk_up = chk_up,
		chk_down = chk_down,
		chk_trig = chk_trig,
		check_kb_key = check_kb_key,
		check_mouse_button = check_mouse_button,
		check_pad_button = check_pad_button,

		-- Register a callback to fire each frame when action_name's hotkey triggers.
		-- Must be called after hk is fully initialised (e.g. from initialize()).
		register_action = function(action_name, callback)
			table.insert(registered_actions, {name = action_name, fn = callback})
		end,

		-- Register a raw per-frame callback that runs unconditionally (e.g. F1 failsafe).
		register_raw_action = function(fn)
			table.insert(registered_raw_actions, fn)
		end,

		-- Call once per frame (replaces the standalone hotkey_handler).
		-- Fires all raw actions first, then all registered hotkey actions.
		run_actions = function()
			for _, fn in ipairs(registered_raw_actions) do
				pcall(fn)
			end
			for _, entry in ipairs(registered_actions) do
				if check_hotkey(entry.name) then
					pcall(entry.fn)
				end
			end
		end,

		-- Returns the title-bar hotkey hint string for the main menu toggle.
		-- Reads from the live hotkeys table so it always reflects the current binding.
		get_toggle_hotkey_display = function()
			local bound = hotkeys["hotkeys_toggle_menu"]
			if bound and bound ~= "[Not Bound]" then
				return " (" .. bound .. " / F1)"
			end
			return " (F1)"
		end,

		-- Returns true when every hotkey matches its default value.
		are_hotkeys_default = function()
			for key, default_val in pairs(default_hotkeys) do
				if hotkeys[key] ~= default_val then return false end
			end
			return true
		end,

		-- Returns true when any hotkey slot is currently awaiting input.
		is_any_hotkey_rebinding = function()
			for _, value in pairs(hotkeys) do
				if value == "[Press Input]" then return true end
			end
			return false
		end,

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

-- Config Management

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
			hitbox_tick_duration = 60,
			hitbox_tick_fade_speed = 1.0,
			property_text_duration = 20,
			property_text_fade_speed = 1.0,
			hide_all_alerts = false,
			alert_on_toggle = true,
			alert_on_presets = true,
			alert_on_save = true,
			notify_duration = 2.0,
			hotkey_minimizes = false,
			color_wall_splat = true,
			mode_training = true,
			mode_replay = true,
			mode_spectate = true,
			mode_single_player = false,
			mode_other = false,
            enable_debug_menu = false,
            remember_window_pos = false,
		},
		hotkeys = {
			hotkeys_toggle_menu = "[Not Bound]",
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
			hotkeys_discard_preset = "Z",
			["hotkeys_discard_preset_$"] = "Control",
			hotkeys_toggle_sync = "C",
			["hotkeys_toggle_sync_$"] = "Control",
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

local FACTORY_PRESET_NAMES = {
    ["Dark"] = true, ["Default"] = true, ["Hitbox Ticks"] = true,
    ["Light"] = true, ["Outlines"] = true,
}

local function reset_defaults(category, player)
    local default_cfg = create_default_config()
    local target_players = player and {player} or {"p1", "p2"}

    local preset_src = nil
    local cur = state.current_preset_name
    if FACTORY_PRESET_NAMES[cur] then
        local factory = create_default_presets()
        preset_src = factory[cur]
    end

    for _, p in ipairs(target_players) do
        if category == "all" then
            local src = preset_src and preset_src[p] or default_cfg[p]
            state.config[p].toggle  = deep_copy(src.toggle)
            state.config[p].opacity = deep_copy(src.opacity)
        else
            local src = preset_src and preset_src[p] or default_cfg[p]
            state.config[p][category] = deep_copy(src[category])
        end
    end

    mark_for_save()
    return state.config
end

-- Notifications

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

-- Preset Management

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

local function init_preset_name()
    state.current_preset_name = get_preset_name()
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
			reset_defaults("all")
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

-- Hitbox Drawing

local RIGHT_SPLAT_POS = 585.2
local LEFT_SPLAT_POS = -1 * RIGHT_SPLAT_POS


-- Property text persistence: each entry keyed by "player_key|text"
-- Stores the last-seen screen position and counts down for 20 frames after
-- the source hitbox disappears.
-- prop_persist: { [key] = {text,x,y,base_opacity,player_key,timer,last_live_frame} }
-- prop_persist_frame: monotonic counter; incremented once per live hitbox pass

state.range_ticks = {
    p1 = { active = nil, ghosts = {} },
    p2 = { active = nil, ghosts = {} },
}
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

local function get_rect_field(rect, field_name)
    if not rect or not field_name then return nil end
    local ok, value = pcall(rect.get_field, rect, field_name)
    if ok then return value end
    return nil
end

local function get_rect_attr_value(rect)
    local value = get_rect_field(rect, "Attribute")
    if value == nil then
        value = get_rect_field(rect, "Attr")
    end
    return value
end

local function is_projectile_owner_entity(entity)
    if not entity then return false end
    local owner_add = entity.owner_add
    if owner_add == nil then return false end
    return tostring(owner_add) ~= tostring(entity)
end

local is_super_freeze_active
local is_strict_super_freeze_active

-- Classifies a hitbox rect and returns all draw data without touching the GPU.
-- Returns nil if the rect has no valid screen projection or is unknown.
local function classify_hitbox(rect, player_config, entity_context)
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
    local base_color, fill_key, outline_key, toggle_key, prop_text, box_kind
    local attr_value = get_rect_attr_value(rect)
    local is_projectile_owner = entity_context and entity_context.is_projectile_owner or false

    if rect:get_field("HitPos") ~= nil then
        if rect.TypeFlag > 0 then
            base_color, fill_key, outline_key, toggle_key = 0x0040C0, "hitbox", "hitbox_outline", "hitboxes"
            box_kind = "hitbox"
            if tog.properties then prop_text = build_hit_properties(rect.CondFlag, rect) end
        elseif (rect.TypeFlag == 0 and rect.PoseBit > 0) or rect.CondFlag == 0x2C0 then
            base_color, fill_key, outline_key, toggle_key = 0xD080FF, "throwbox", "throwbox_outline", "throwboxes"
            box_kind = "throwbox"
            if tog.properties then prop_text = build_hit_properties(rect.CondFlag, rect) end
        elseif rect.GuardBit == 0 then
            base_color, fill_key, outline_key, toggle_key = 0x3891E6, "clashbox", "clashbox_outline", "clashboxes"
            box_kind = "clashbox"
        else
            base_color, fill_key, outline_key, toggle_key = 0x5b5b5b, "proximitybox", "proximitybox_outline", "proximityboxes"
            box_kind = "proximitybox"
        end
    elseif get_rect_field(rect, "Attr") ~= nil or get_rect_field(rect, "Attribute") ~= nil then
        if is_projectile_owner then
            base_color, fill_key, outline_key, toggle_key = 0x3891E6, "clashbox", "clashbox_outline", "clashboxes"
            box_kind = "clashbox"
        else
            base_color, fill_key, outline_key, toggle_key = 0x00FFFF, "pushbox", "pushbox_outline", "pushboxes"
            box_kind = "pushbox"
        end
    elseif rect:get_field("HitNo") ~= nil then
        if rect.TypeFlag > 0 then
            base_color = (rect.Type == 2 or rect.Type == 1) and 0xFF0080 or 0x00FF00
            fill_key, outline_key, toggle_key = "hurtbox", "hurtbox_outline", "hurtboxes"
            box_kind = "hurtbox"
            if tog.properties then prop_text = build_hurt_properties(rect.TypeFlag, rect.Immune) end
        else
            base_color, fill_key, outline_key, toggle_key = 0xFF0000, "throwhurtbox", "throwhurtbox_outline", "throwhurtboxes"
            box_kind = "throwhurtbox"
        end
    elseif rect:get_field("KeyData") ~= nil then
        base_color, fill_key, outline_key, toggle_key = 0xEEFF00, "uniquebox", "uniquebox_outline", "uniqueboxes"
        box_kind = "uniquebox"
    else
        base_color, fill_key, outline_key, toggle_key = 0xFF0000, "throwhurtbox", "throwhurtbox_outline", "throwhurtboxes"
        box_kind = "throwhurtbox"
    end

    if not base_color then return nil end

    return {
        x               = x,
        y               = y,
        w               = w,
        h               = h,
        base_color      = base_color,
        box_kind        = box_kind,
        show_fill       = ((box_kind ~= "pushbox" and box_kind ~= "proximitybox") or not is_strict_super_freeze_active()) and (tog[toggle_key] or false),
        show_outline    = ((box_kind ~= "pushbox" and box_kind ~= "proximitybox") or not is_strict_super_freeze_active()) and (tog[toggle_key .. "_outline"] or false),
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
local super_freeze_linger_frames = 0
local frozen_draw_calls = {}   -- last pre-timestop frame's draw calls
local draw_call_buffer = nil   -- non-nil while recording a normal frame

is_super_freeze_active = function()
    return super_freeze_linger_frames > 0
end

is_strict_super_freeze_active = function()
    return timestop_total_frames ~= nil
       and timestop_total_frames == 11
       and timestop_frame ~= nil
       and timestop_frame > 0
       and timestop_frame < timestop_total_frames
end



local function draw_union_fills(boxes, full_color, box_kind)
    if #boxes == 0 then return end

    -- Fast path: single box, no overlap possible.
    if #boxes == 1 then
        local b = boxes[1]
        if draw_call_buffer then
            draw_call_buffer[#draw_call_buffer+1] = {"filled_rect", b.x, b.y, b.w, b.h, full_color, box_kind}
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
                        draw_call_buffer[#draw_call_buffer+1] = {"filled_rect", uxs[i], uys[j], cw, ch, full_color, box_kind}
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

local DEFAULT_PROP_PERSIST_TOTAL = 20
local DEFAULT_PROP_PERSIST_SLOW_RATIO = 5 / 20
local DEFAULT_PROP_PERSIST_SHARP_RATIO = 10 / 20

local DEFAULT_RANGE_TICK_TOTAL = 60
local DEFAULT_RANGE_TICK_DIM_WINDOW_RATIO = 19 / 60
local DEFAULT_RANGE_TICK_MOVE_HOLD_RATIO = 35 / 60
local DEFAULT_RANGE_TICK_MOVE_WINDOW_RATIO = 20 / 60

local function get_display_duration_frames(option_key, fallback)
    local value = tonumber(state.config and state.config.options and state.config.options[option_key]) or fallback
    return math.max(1, math.floor(value + 0.5))
end

local function get_display_fade_speed(option_key)
    local value = tonumber(state.config and state.config.options and state.config.options[option_key]) or 1.0
    return math.max(0.1, value)
end

local function apply_fade_speed_to_progress(progress, fade_speed)
    progress = math.min(math.max(progress or 0, 0), 1)
    fade_speed = math.max(fade_speed or 1.0, 0.1)
    return 1.0 - ((1.0 - progress) ^ fade_speed)
end

-- Property Text Persistence

-- Returns an alpha multiplier in [0, 1] given the remaining lifetime timer.
-- The default configuration matches the original 20-frame decay and fade curve.
local function prop_persist_fade(timer)
    local total = get_display_duration_frames("property_text_duration", DEFAULT_PROP_PERSIST_TOTAL)
    local slow = total * DEFAULT_PROP_PERSIST_SLOW_RATIO
    local sharp = total * DEFAULT_PROP_PERSIST_SHARP_RATIO
    local age = total - timer
    local progress = age / total
    local scaled_age = apply_fade_speed_to_progress(progress, get_display_fade_speed("property_text_fade_speed")) * total

    if scaled_age <= slow then
        return 1.0
    elseif scaled_age <= sharp then
        -- Slow stage: ease from 1.0 down to 0.7 through the middle portion.
        local t = (scaled_age - slow) / math.max(sharp - slow, 0.001)
        return 1.0 - 0.3 * t
    else
        -- Sharp stage: drop from 0.7 to 0 over the remaining frames.
        local t = (scaled_age - sharp) / math.max(total - sharp, 0.001)
        return 0.7 * (1.0 - t)
    end
end

-- Called instead of draw_text_buffered for every property label.
-- Draws the text immediately (including into the timestop buffer) and
-- registers/refreshes the entry in the persist table so it can ghost
-- for the configured property text duration after the hitbox is gone.
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
        entry.timer          = get_display_duration_frames("property_text_duration", DEFAULT_PROP_PERSIST_TOTAL)
        entry.last_live_frame = state.prop_persist_frame
    else
        state.prop_persist[key] = {
            text            = text,
            x               = x,
            y               = y,
            base_opacity    = base_opacity,
            player_key      = player_key,
            timer           = get_display_duration_frames("property_text_duration", DEFAULT_PROP_PERSIST_TOTAL),
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

local function draw_hitboxes(work, actParam, player_config, player_key, entity_context)
    local col = actParam.Collision

    -- Pass 1: classify every rect into pure data — no GPU calls yet.
    local classified = {}
    for _, rect in reverse_pairs(col.Infos._items) do
        local info = classify_hitbox(rect, player_config, entity_context)
        if info then classified[#classified+1] = info end
    end

    -- Pass 2: group fills by (base_color × opacity) and draw the union of each
    -- group so that overlapping rects of the same type paint their shared region
    -- at the same opacity as a single rect, not compounded alpha.
    local fill_groups = {}
    for _, info in ipairs(classified) do
        if info.show_fill then
            local gkey = tostring(info.box_kind) .. "_" .. tostring(info.base_color) .. "_" .. tostring(info.fill_opacity)
            if not fill_groups[gkey] then
                fill_groups[gkey] = {
                    full_color = apply_opacity(info.fill_opacity, info.base_color),
                    box_kind   = info.box_kind,
                    boxes      = {},
                }
            end
            local g = fill_groups[gkey].boxes
            g[#g+1] = {x = info.x, y = info.y, w = info.w, h = info.h}
        end
    end
    for _, group in pairs(fill_groups) do
        draw_union_fills(group.boxes, group.full_color, group.box_kind)
    end

    -- Pass 3: draw each rect's outline individually — unaffected by the union.
    for _, info in ipairs(classified) do
        if info.show_outline then
            local outline_color = apply_opacity(info.outline_opacity, info.base_color)
            if draw_call_buffer then
                draw_call_buffer[#draw_call_buffer+1] = {"outline_rect", info.x, info.y, info.w, info.h, outline_color, info.box_kind}
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

local RANGE_TICK_MOVE_EPSILON = 0.5

local function clone_range_tick(tick)
    if not tick then return nil end
    return {
        ox = tick.ox,
        fy = tick.fy,
        fx = tick.fx,
        timer = tick.timer,
        age = tick.age,
    }
end

local function range_tick_changed(prev_tick, ox, fy, fx)
    if not prev_tick then return false end
    return math.abs((prev_tick.ox or 0) - ox) > RANGE_TICK_MOVE_EPSILON
        or math.abs((prev_tick.fy or 0) - fy) > RANGE_TICK_MOVE_EPSILON
        or math.abs((prev_tick.fx or 0) - fx) > RANGE_TICK_MOVE_EPSILON
end

local function update_range_tick(entity, player_key)
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
        local tick_state = state.range_ticks[player_key]
        if not tick_state then
            tick_state = { active = nil, ghosts = {} }
            state.range_ticks[player_key] = tick_state
        end

		local current_age = 0
		local prev_tick = tick_state.active
		if prev_tick and prev_tick.timer > 0 then
			current_age = prev_tick.age or 0
            if range_tick_changed(prev_tick, origin.x, far_sy, far_sx) then
                tick_state.ghosts[#tick_state.ghosts + 1] = clone_range_tick(prev_tick)
            end
		end

		tick_state.active = {
			ox = origin.x,
			fy = far_sy,
			fx = far_sx,
			timer = get_display_duration_frames("hitbox_tick_duration", DEFAULT_RANGE_TICK_TOTAL),
			age = current_age + 1
		}
	end
end

local function process_entity(entity, draw_pos)
    local config = nil
    local player_key = nil
    local entity_context = {
        is_projectile_owner = is_projectile_owner_entity(entity)
    }
    if entity:get_IsTeam1P() then
        config = state.config.p1
        player_key = "p1"
    elseif entity:get_IsTeam2P() then
        config = state.config.p2
        player_key = "p2"
    end
    if not config or not config.toggle.toggle_show then return end
    draw_hitboxes(entity, entity.mpActParam, config, player_key, entity_context)
    if draw_pos then
        draw_position_marker(entity, config)
        update_range_tick(entity, player_key)
    end
end

local function draw_range_ticks()
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

    local function draw_single_tick(tick, player_config)
        if not tick or tick.timer <= 0 then return false end

        local ox, fy, fx = tick.ox, tick.fy, tick.fx
        local opacity = player_config.opacity.hitbox_tick or 25
        local total = get_display_duration_frames("hitbox_tick_duration", DEFAULT_RANGE_TICK_TOTAL)
        local progress = (total - tick.timer) / total
        local scaled_progress = apply_fade_speed_to_progress(progress, get_display_fade_speed("hitbox_tick_fade_speed"))

        -- Default values reproduce the original timing curve.
        local dim_fade = math.min(math.max(1.0 - (scaled_progress / DEFAULT_RANGE_TICK_DIM_WINDOW_RATIO), 0), 1)

        -- Movement begins near the end of the tick lifetime, then retracts inward.
        local move_fade = math.min(math.max(
            (DEFAULT_RANGE_TICK_MOVE_HOLD_RATIO - scaled_progress) / DEFAULT_RANGE_TICK_MOVE_WINDOW_RATIO,
            0), 1)

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
        return tick.timer > 0
    end

	for player_key, tick_state in pairs(state.range_ticks) do
		local player_config = state.config[player_key]
		if not player_config or not player_config.toggle.hitbox_ticks then
            state.range_ticks[player_key] = { active = nil, ghosts = {} }
        else
            if tick_state.active and not draw_single_tick(tick_state.active, player_config) then
                tick_state.active = nil
            end

            local next_ghosts = {}
            for _, ghost_tick in ipairs(tick_state.ghosts or {}) do
                if draw_single_tick(ghost_tick, player_config) then
                    next_ghosts[#next_ghosts + 1] = ghost_tick
                end
            end
            tick_state.ghosts = next_ghosts
		end
	end
end

-- Timestop 

local function update_timestop_state()
    local ok, BattleChronos = pcall(function()
        return gBattle:get_field("Chronos"):get_data(nil)
    end)
    if not ok or not BattleChronos then return end
    local frame, frames = BattleChronos.WorldElapsed, BattleChronos.WorldNotch
    local training_super_freeze_active = false
    local ok_training, active, fm_stop_frame = pcall(function()
        return read_training_display_super_freeze_state()
    end)
    if ok_training then
        training_super_freeze_active = active and true or false
    end
    local chronos_active = frames ~= nil
        and frame ~= nil
        and frames > 0
        and frame > 0
        and frame < frames
    local chronos_finished = frames ~= nil
        and frame ~= nil
        and frames > 0
        and frame == frames
    local is_super_freeze_step = frames ~= nil
        and frames == 11
        and frame ~= nil
        and frame > 0
        and frame < frames
    if not is_super_freeze_step and chronos_active and training_super_freeze_active then
        is_super_freeze_step = true
    end
    if is_super_freeze_step then
        super_freeze_linger_frames = (frames == 11) and 2 or 1
    elseif chronos_finished or not chronos_active then
        super_freeze_linger_frames = 0
    else
        super_freeze_linger_frames = math.max(0, super_freeze_linger_frames - 1)
    end
    local current_frame, total_frames = frame, frames
    if frame > 0 and frames > 0 and frame == frames then
        current_frame, total_frames = 0, 0
    end
    timestop_frame, timestop_total_frames = current_frame, total_frames
end

local function replay_frozen_draw_calls()
    for _, call in ipairs(frozen_draw_calls) do
        local box_kind = call[7]
        if is_super_freeze_active() and (box_kind == "pushbox" or box_kind == "proximitybox") then
            goto continue
        end
        if call[1] == "filled_rect" then
            draw.filled_rect(call[2], call[3], call[4], call[5], call[6])
        elseif call[1] == "outline_rect" then
            draw.outline_rect(call[2], call[3], call[4], call[5], call[6])
        elseif call[1] == "text" then
            draw.text(call[2], call[3], call[4], call[5])
        elseif call[1] == "circle" then
            draw.filled_circle(call[2], call[3], call[4], call[5], call[6])
        end
        ::continue::
    end
end

local function should_replay_frozen_draw_calls()
    -- Two distinct Chronos states need the previous stable draw buffer:
    -- 1. The original 11F super-freeze case this script already supported.
    -- 2. Training mode at 50% speed, which appears to present as a 2-step
    --    repeated render of the same gameplay frame.
    --
    -- Broader replay causes stale screen-space hitboxes to drift away from
    -- characters during cinematic freezes, so keep this narrowly targeted.
    if timestop_total_frames == nil then
        return false
    end
    if timestop_frame == nil or timestop_frame <= 0 then
        return false
    end
    if timestop_frame >= timestop_total_frames then
        return false
    end
    if timestop_total_frames ~= 2 and timestop_total_frames ~= 11 then
        return false
    end
    return #frozen_draw_calls > 0
end

local function process_hitboxes()
    update_timestop_state()

	-- Hold the previous stable frame across Chronos subframes so hitboxes stay
	-- visible during slow-motion and other repeated-render states.
    if should_replay_frozen_draw_calls() then
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
state.debug_panel_was_visible = false
state.debug_force_sys_open    = false
state.slider_mouse_active          = false  -- was any drag_int active last frame?
state.slider_mouse_active_this_frame = false  -- accumulator reset each frame
-- Unified single-row hover tracker. Only one row across all sections can be
-- highlighted at a time. hov_cur is written this frame by any hovered widget;
-- hov_prev is the result from last frame used for pre-widget style decisions.
-- Structure: {section = "toggle"|"preset"|"header", key = row_idx|preset_name|nil, col = col_num}
state.hov_prev = nil
state.hov_cur  = nil

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
    slider_active  = false, -- currently editing an opacity slider
    slider_orig    = nil,   -- value before slider edit started (for cancel)
    slider_rep     = 0,
    SLIDER_STEP    = 3,     -- opacity units per tick when editing
    SLIDER_DELAY   = 10,    -- frames before slider repeat starts
    SLIDER_RATE    = 3,     -- frames per repeat tick while held
    just_moved     = false, -- true for exactly one frame after nav cursor moves (legacy, kept for compat)
    nav_lock       = 0,     -- frames remaining where mouse hover cannot override gamepad/KB nav
    NAV_LOCK_FRAMES = 20,   -- how long to suppress hover after a gamepad/KB navigation
    sync_mod_active = false, -- true when the modifier key force-enabled sync (so release can undo it)
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

-- Keyboard equivalents for mouse-hover navigation.
-- Only meaningful when menu_nav_handler is reached (i.e. mouse is over window).
local function _kb_trig(key) return hk.check_kb_key(key, nil, true) end
local function _kb_held(key) return hk.check_kb_key(key, true) end

-- Sync modifier: Ctrl (keyboard) or LT/L2 (gamepad).
local function _nav_sync_mod_held()
    local lt_mask = (hk and hk.buttons and hk.buttons["LT (L2)"]) or 0
    return (lt_mask ~= 0 and _nav_btn_held(lt_mask)) or _kb_held("Control")
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

-- ============================================================================
-- Nav / Widget Style Constants
-- Shared by build.toggle.column, build.toggle.sync_button, and any future
-- widgets that need to match the controller-nav selection appearance.
-- All colours are packed ABGR (same as imgui/draw APIs).
-- ============================================================================

-- ImGuiCol indices used for push_style_color
local IC_FRAME_BG        = 7   -- drag_int / checkbox background
local IC_FRAME_HOV       = 8   -- same, hovered
local IC_CHECKMARK       = 18  -- checkbox tick
local IC_SLIDER_GRAB     = 19  -- drag_int grab handle
local IC_SLIDER_GRAB_ACT = 20  -- drag_int grab handle while dragging
local IC_BUTTON          = 21  -- imgui.button face
local IC_BUTTON_HOV      = 22  -- imgui.button face, hovered

-- Cursor resting on a cell (selected, not yet activated)
local C_NAV_FRAME  = 0x8000D0FF   -- gold, 50% opacity
local C_NAV_HOV    = 0xA000D0FF   -- gold, 63% opacity
local C_NAV_MARK   = 0xFF00E0FF   -- gold, fully opaque (checkmark / grab)

-- Slider actively being dragged (more pronounced than just selected)
local C_EDIT_FRAME    = 0xCC00D8FF   -- gold, 80% opacity
local C_EDIT_HOV      = 0xE000E0FF   -- gold, 88% opacity
local C_EDIT_GRAB     = 0xFF10F0FF   -- bright gold grab handle
local C_EDIT_GRAB_ACT = 0xFFFFFFFF   -- white while the grab is held

-- Sync-active state: dark green at opacities matching the gold nav palette.
-- Used for the Sync button face, toggle-table row backgrounds, and per-cell
-- highlights whenever sync is enabled.  All colours are packed ABGR.
local C_SYNC_FRAME = 0x8000A000   -- dark green, 50% opacity
local C_SYNC_HOV   = 0xA000B800   -- dark green, 63% opacity
local C_SYNC_MARK  = 0xFF00C800   -- dark green, fully opaque

-- ============================================================================
-- Unified hover helpers
-- is_hov(section, key, col)  →  true when hov_prev matches all non-nil args
-- set_hov(section, key, col) →  write into hov_cur (last write per frame wins)
-- ============================================================================
local function is_hov(section, key, col)
    local h = state.hov_prev
    if not h or h.section ~= section then return false end
    if key ~= nil and h.key ~= key then return false end
    if col ~= nil and h.col ~= col then return false end
    return true
end

local function set_hov(section, key, col)
    state.hov_cur = {section = section, key = key, col = col}
end

-- Maintains row background highlight when the mouse is inside the row's Y band.
-- Fires whether or not a widget in the row has already claimed hov_cur this frame,
-- EXCEPT when hov_cur already belongs to this exact row (element hover takes
-- precedence so its col information is preserved for per-element styling).
-- This ensures the row background is drawn whenever any part of the row is hovered,
-- even if the mouse is directly over a widget inside it.
local ROW_H = 23
local function row_hover_check(row_y_local, section, key)
    if not state.menu_window_focused or not state.menu_window_pos then return end
    -- If hov_cur is already set for THIS row an element in it was hovered; preserve
    -- that col-specific state so per-element highlighting continues to work.
    local existing = state.hov_cur
    if existing and existing.section == section and existing.key == key then return end
    local wpos  = state.menu_window_pos
    local wsize = imgui.get_window_size()
    local mouse = imgui.get_mouse()
    local sy = wpos.y + row_y_local - imgui.get_scroll_y()
    if mouse.y >= sy and mouse.y < sy + ROW_H
       and mouse.x >= wpos.x and mouse.x < wpos.x + wsize.x then
        set_hov(section, key, nil)
    end
end

-- Draws a filled background highlight rect behind a tree-node header row,
-- using the previous frame's hover state so it renders beneath the row's widgets.
-- Call BEFORE any widgets on the row.
local function treerow_bg(label)
    if not is_hov("treerow", label) then return end
    local wpos  = imgui.get_window_pos()
    local wsize = imgui.get_window_size()
    local cy    = imgui.get_cursor_pos().y
    if not imgui.get_window_draw_list then return end
    local dl    = imgui.get_window_draw_list()
    if not dl then return end
    dl:add_rect_filled(wpos.x, wpos.y + cy, wpos.x + wsize.x, wpos.y + cy + ROW_H, C_NAV_FRAME)
end

-- Button with per-element highlight for tree-node inline buttons.
-- col is an integer slot distinguishing sibling buttons on the same row.
-- size is an optional {w, h} table passed through to imgui.button.
local function treerow_hov_button(btn_label, row_key, col, size)
    local highlighted = is_hov("treerow", row_key, col)
    if highlighted then
        imgui.push_style_color(IC_BUTTON,     C_NAV_FRAME)
        imgui.push_style_color(IC_BUTTON_HOV, C_NAV_HOV)
        imgui.begin_rect()
    end
    local clicked = imgui.button(btn_label, size)
    if imgui.is_item_hovered() then set_hov("treerow", row_key, col) end
    if highlighted then
        imgui.end_rect(1)
        imgui.pop_style_color(2)
    end
    return clicked
end

-- Checkbox with per-element highlight for tree-node inline checkboxes.
local function treerow_hov_checkbox(cb_label, row_key, col, val)
    local highlighted = is_hov("treerow", row_key, col)
    if highlighted then
        imgui.push_style_color(IC_FRAME_BG,  C_NAV_FRAME)
        imgui.push_style_color(IC_FRAME_HOV, C_NAV_HOV)
        imgui.push_style_color(IC_CHECKMARK, C_NAV_MARK)
        imgui.begin_rect()
        imgui.begin_rect()
    end
    local changed, new_val = imgui.checkbox(cb_label, val)
    if changed then mark_for_save() end
    if imgui.is_item_hovered() then set_hov("treerow", row_key, col) end
    if highlighted then
        imgui.end_rect(1)
        imgui.end_rect(3)
        imgui.pop_style_color(3)
    end
    return changed, new_val
end




-- Loaded from func/better_disp_hitboxes_debugger.lua.
-- If the file is missing or contains a syntax/runtime error the debug panel
-- is silently disabled: Ctrl+F1 and the options toggle do nothing, and all
-- other functionality continues normally.
-- ============================================================================
local _debugger_module = nil
local _debugger        = nil   -- fully initialised instance (set in init_debugger)

do
    local ok, result = pcall(require, "func/better_disp_hitboxes_debugger")
    if ok and type(result) == "table" and type(result.init) == "function" then
        _debugger_module = result
    else
        -- Log the failure without crashing; debug mode will stay disabled.
        local err_msg = type(result) == "string" and result or "(unknown error)"
        pcall(log.info, "[BetterHitboxViewer] debugger module failed to load: " .. err_msg)
    end
end

-- Returns true only when the debugger is fully operational.
local function debugger_available()
    return _debugger ~= nil
end

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
    if menu_nav.nav_lock > 0 then menu_nav.nav_lock = menu_nav.nav_lock - 1 end

    if not state.config.options.display_menu or not state.menu_window_focused then
        menu_nav.active = false
        menu_nav.rep_timer = 0
        menu_nav.slider_active = false
        return
    end
    -- Keep active so mouse-hover outlines continue to work.
    menu_nav.active = true

    -- ── Slider editing mode (no gamepad/keyboard delta; mouse drag handles it) ─
    if menu_nav.slider_active then return end
    -- (No gamepad/keyboard movement — mouse hover drives selected/column.)
end

-- build.toggle functions

function build.toggle.sync_button()
    -- Use a dedicated "sync" section so is_hov("header") on the P1/P2 header row
    -- never fires when the sync row is the one that is nav-selected.
    local is_nav_on_sync   = is_hov("sync")
    local was_sync_enabled = state.sync_enabled
    local sync_hk     = hk.hotkeys["hotkeys_toggle_sync"]
    local sync_hk_str = (sync_hk and sync_hk ~= "[Not Bound]") and " (" .. hk.get_button_string("hotkeys_toggle_sync") .. ")" or ""
    local btn_label   = was_sync_enabled and ("Syncing Changes" .. sync_hk_str .. "##sync_btn") or ("Sync P1/P2 Changes" .. sync_hk_str .. "##sync_btn")

    -- Style colours are mutually exclusive per state so we track push count.
    local n_colors = 0
    if was_sync_enabled then
        -- Active-sync state: green button face + double-border active indicator.
        imgui.push_style_color(IC_BUTTON,     C_SYNC_FRAME)
        imgui.push_style_color(IC_BUTTON_HOV, C_SYNC_HOV)
        n_colors = 2
        imgui.begin_rect()  -- paired with end_rect(1)
        imgui.begin_rect()  -- paired with end_rect(3)
    elseif is_nav_on_sync then
        -- Nav-selected (not yet enabled): gold button face, matching table row bg.
        imgui.push_style_color(IC_BUTTON,     C_NAV_FRAME)
        imgui.push_style_color(IC_BUTTON_HOV, C_NAV_HOV)
        n_colors = 2
    end
    -- Single border for any nav-on-sync state (enabled or just selected).
    if is_nav_on_sync then imgui.begin_rect() end  -- paired with end_rect(2)

    if imgui.button(btn_label, {-1, 0}) then
        state.sync_enabled = not state.sync_enabled
    end

    if imgui.is_item_hovered() then
        set_hov("sync", nil, nil)
    end

    if is_nav_on_sync   then imgui.end_rect(2) end
    if was_sync_enabled then
        imgui.end_rect(1)
        imgui.end_rect(3)
    end
    if n_colors > 0 then imgui.pop_style_color(n_colors) end
end

function build.toggle.column_header_sync()
    build.toggle.sync_button()
end

function build.checkbox(label, val)
    local changed, new_val = imgui.checkbox(label, val)
    if changed then mark_for_save() end
    return changed, new_val
end

function build.display_menu_checkbox()
	local changed
    changed, state.config.options.display_menu = build.checkbox(
        "Better Hitbox Display: Show Menu", state.config.options.display_menu
    )
end

function build.toggle.opacity_slider(label, val, speed, min, max)
    val = math.max(0, math.min(100, val))
    local changed, new_val = imgui.drag_int(label, val, speed or 1.0, min or 0, max or 100)
    if changed then
        new_val = math.max(0, math.min(100, new_val))
        mark_for_save()
    end
    return changed, new_val
end

local function handle_toggle_column_header_player_notify(changed, player_str, new_val)
    if not changed then return end
    action_notify(player_str .. " Hitboxes " .. (new_val and "Enabled" or "Disabled"), "alert_on_toggle")
end

function build.toggle.column_header_player(label, id, player_key, nav_col)
    local conf = state.config[player_key].toggle.toggle_show

    -- Real-time column X check: only show widget highlight when mouse is in this column.
    local col_x = imgui.get_cursor_pos().x
    local win_x = state.menu_window_pos and state.menu_window_pos.x or 0
    local mx    = imgui.get_mouse().x - win_x
    local is_mouse_in_col = mx >= col_x - 4 and mx < col_x + 170
    local is_highlighted = is_hov("header", nil, nav_col) and is_mouse_in_col

    -- Sync-mirror: the OTHER player's header is hovered and sync is live.
    -- No column-X check here — mirrors intentionally highlight across columns.
    local other_nav_col  = (nav_col == 1) and 2 or 1
    local is_sync_mirror = state.sync_enabled and is_hov("header", nil, other_nav_col)

    if is_highlighted then
        imgui.push_style_color(IC_FRAME_BG,  state.sync_enabled and C_SYNC_FRAME or C_NAV_FRAME)
        imgui.push_style_color(IC_FRAME_HOV, state.sync_enabled and C_SYNC_HOV   or C_NAV_HOV)
        imgui.push_style_color(IC_CHECKMARK, state.sync_enabled and C_SYNC_MARK  or C_NAV_MARK)
        imgui.begin_rect()
        imgui.begin_rect()
    elseif is_sync_mirror then
        imgui.push_style_color(IC_FRAME_BG,  C_SYNC_FRAME)
        imgui.push_style_color(IC_FRAME_HOV, C_SYNC_HOV)
        imgui.push_style_color(IC_CHECKMARK, C_SYNC_MARK)
        imgui.begin_rect()
        imgui.begin_rect()
    end

    -- Checkbox first, at the natural column position, so it aligns with the
    -- checkboxes in the rows below.  Label text follows to the right.
    local changed, new_val
    changed, new_val = build.checkbox(id, conf)
    if changed then
        state.config[player_key].toggle.toggle_show = new_val
        build.on_sync(function()
            local other_key = (player_key == "p1") and "p2" or "p1"
            state.config[other_key].toggle.toggle_show = new_val
        end, true)
    end
    if imgui.is_item_hovered() then
        set_hov("header", nil, nav_col)
        local hk_action = "hotkeys_toggle_" .. player_key
        local hk_key = hk.hotkeys[hk_action]
        if hk_key and hk_key ~= "[Not Bound]" then
            imgui.set_tooltip("Toggle " .. label .. " (" .. hk.get_button_string(hk_action) .. ")")
        end
    end

    imgui.same_line()
    imgui.text(label)
    if imgui.is_item_hovered() then set_hov("header", nil, nav_col) end

    if is_highlighted or is_sync_mirror then
        imgui.end_rect(1)
        imgui.end_rect(3)
        imgui.pop_style_color(3)
    end

    handle_toggle_column_header_player_notify(changed, label, new_val)
end

function build.toggle.column_headers()
    imgui.table_next_row()
    local row_y = imgui.get_cursor_pos().y

    if is_hov("header") then
        imgui.table_set_bg_color(2, state.sync_enabled and C_SYNC_FRAME or C_NAV_FRAME)
    end

    -- column 0 intentionally blank; Sync button lives above the table

    imgui.table_set_column_index(1)
    build.toggle.column_header_player(
        "P1",
        "##p1_HideAllHeader",
        "p1",
        1
    )

    imgui.table_set_column_index(3)
    build.toggle.column_header_player(
        "P2",
        "##p2_HideAllHeader",
        "p2",
        2
    )

    row_hover_check(row_y, "header", nil)
end

function build.toggle.column(player_index, visible, toggle_tbl, opacity_tbl, toggle_key, opacity_key, row_idx)
    if not visible then return end
    imgui.table_set_column_index(player_index)

    -- Real-time mouse X check: suppress widget-level highlight when the mouse is
    -- not actually in this player's column, eliminating the one-frame hov_prev lag.
    -- get_cursor_pos() returns window-local coords; get_mouse() returns screen coords.
    local col_x = imgui.get_cursor_pos().x
    local win_x = state.menu_window_pos and state.menu_window_pos.x or 0
    local mx    = imgui.get_mouse().x - win_x
    -- Span covers checkbox (~20px) + spacing + optional 70px slider + cell padding.
    local is_mouse_in_col = mx >= col_x - 4 and mx < col_x + 170

    -- 4-column nav scheme: P1 toggle=1, P1 opacity=2, P2 toggle=3, P2 opacity=4
    local toggle_col_nav  = player_index == 1 and 1 or 3
    local opacity_col_nav = player_index == 1 and 2 or 4

    -- The OTHER player's matching nav columns — used for sync-mirror highlight.
    local other_toggle_col_nav  = player_index == 1 and 3 or 1
    local other_opacity_col_nav = player_index == 1 and 4 or 2

    -- Direct hover: only active when mouse is in this column.
    local is_toggle_nav  = is_hov("toggle", row_idx, toggle_col_nav)  and is_mouse_in_col
    local is_opacity_nav = is_hov("toggle", row_idx, opacity_col_nav) and is_mouse_in_col

    -- Sync-mirror: cursor is on the OTHER player's matching cell and sync is live.
    -- No column check here — mirrors intentionally highlight across columns.
    local is_sync_mirror_toggle  = state.sync_enabled and is_hov("toggle", row_idx, other_toggle_col_nav)
    local is_sync_mirror_opacity = state.sync_enabled and is_hov("toggle", row_idx, other_opacity_col_nav)

    -- ── Checkbox ─────────────────────────────────────────────────────────────
    if is_toggle_nav then
        imgui.push_style_color(IC_FRAME_BG,  state.sync_enabled and C_SYNC_FRAME or C_NAV_FRAME)
        imgui.push_style_color(IC_FRAME_HOV, state.sync_enabled and C_SYNC_HOV   or C_NAV_HOV)
        imgui.push_style_color(IC_CHECKMARK, state.sync_enabled and C_SYNC_MARK  or C_NAV_MARK)
        imgui.begin_rect()
        imgui.begin_rect()
    elseif is_sync_mirror_toggle then
        imgui.push_style_color(IC_FRAME_BG,  C_SYNC_FRAME)
        imgui.push_style_color(IC_FRAME_HOV, C_SYNC_HOV)
        imgui.push_style_color(IC_CHECKMARK, C_SYNC_MARK)
        imgui.begin_rect()
        imgui.begin_rect()
    end

    local id = string.format("##p%.0f_", player_index) .. toggle_key
    local _raw_chg, _raw_val = imgui.checkbox(id, toggle_tbl[toggle_key])
    if _raw_chg then
        toggle_tbl[toggle_key] = _raw_val
        mark_for_save()
    end

    if imgui.is_item_hovered() then
        set_hov("toggle", row_idx, toggle_col_nav)
    end

    if is_toggle_nav then
        imgui.end_rect(1)
        imgui.end_rect(3)
        imgui.pop_style_color(3)
    elseif is_sync_mirror_toggle then
        imgui.end_rect(1)
        imgui.end_rect(3)
        imgui.pop_style_color(3)
    end

    -- ── Opacity slider ────────────────────────────────────────────────────────
    local has_slider = opacity_key
                    and opacity_tbl ~= nil
                    and opacity_tbl[opacity_key] ~= nil
                    and toggle_tbl[toggle_key]

    if has_slider then
        imgui.push_item_width(70); imgui.same_line()
        local opacity_id = string.format("##p%.0f_", player_index) .. opacity_key .. "Opacity"

        if is_opacity_nav then
            imgui.push_style_color(IC_FRAME_BG,  state.sync_enabled and C_SYNC_FRAME or C_NAV_FRAME)
            imgui.push_style_color(IC_FRAME_HOV, state.sync_enabled and C_SYNC_HOV   or C_NAV_HOV)
            imgui.begin_rect()
            imgui.begin_rect()
        elseif is_sync_mirror_opacity then
            imgui.push_style_color(IC_FRAME_BG,  C_SYNC_FRAME)
            imgui.push_style_color(IC_FRAME_HOV, C_SYNC_HOV)
            imgui.begin_rect()
            imgui.begin_rect()
        end

        local op_changed, new_val = imgui.drag_int(opacity_id, opacity_tbl[opacity_key], 0.5, 0, 100)
        if op_changed then
            new_val = math.max(0, math.min(100, new_val))
            opacity_tbl[opacity_key] = new_val
            mark_for_save()
            build.on_sync(function()
                local other = (player_index == 1) and state.config.p2.opacity or state.config.p1.opacity
                other[opacity_key] = new_val
            end, op_changed)
        end

        if imgui.is_item_active() then
            state.slider_mouse_active_this_frame = true
            set_hov("toggle", row_idx, opacity_col_nav)
        elseif imgui.is_item_hovered() then
            set_hov("toggle", row_idx, opacity_col_nav)
        end

        imgui.pop_item_width()

        if is_opacity_nav then
            imgui.end_rect(2)
            imgui.end_rect(1)
            imgui.pop_style_color(2)
        elseif is_sync_mirror_opacity then
            imgui.end_rect(2)
            imgui.end_rect(1)
            imgui.pop_style_color(2)
        end
    end

    build.on_sync(function()
        local other_toggle = (player_index == 1) and state.config.p2.toggle or state.config.p1.toggle
        other_toggle[toggle_key] = toggle_tbl[toggle_key]
        if not opacity_key then return end
        local other_opacity = (player_index == 1) and state.config.p2.opacity or state.config.p1.opacity
        other_opacity[opacity_key] = opacity_tbl[opacity_key]
    end, _raw_chg)
end

function build.toggle.columns(label, toggle_key, opacity_key, row_idx)
    if is_hov("toggle", row_idx) then
        imgui.table_set_bg_color(2, state.sync_enabled and C_SYNC_FRAME or C_NAV_FRAME)
    end
    imgui.table_set_column_index(0)
    imgui.text(label)
    if imgui.is_item_hovered() then
        set_hov("toggle", row_idx, nil)
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
    local row_y = imgui.get_cursor_pos().y
    build.toggle.columns(label, toggle_key, opacity_key, row_idx)
    row_hover_check(row_y, "toggle", row_idx)
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
    end, true)

    mark_for_save()
end

function build.toggle.all_click_toggle(toggle_tbl, player_index, checked, row_idx, is_mouse_in_col)
    local toggle_col_nav = player_index == 1 and 1 or 3
    local is_toggle_nav  = is_hov("toggle", row_idx, toggle_col_nav) and (is_mouse_in_col ~= false)

    if is_toggle_nav then
        imgui.push_style_color(IC_FRAME_BG,  state.sync_enabled and C_SYNC_FRAME or C_NAV_FRAME)
        imgui.push_style_color(IC_FRAME_HOV, state.sync_enabled and C_SYNC_HOV   or C_NAV_HOV)
        imgui.push_style_color(IC_CHECKMARK, state.sync_enabled and C_SYNC_MARK  or C_NAV_MARK)
        imgui.begin_rect()
        imgui.begin_rect()
    end

    local changed
    changed, checked = build.checkbox("##p"..player_index.."_ToggleAll", checked)

    if imgui.is_item_hovered() then
        set_hov("toggle", row_idx, toggle_col_nav)
    end

    if is_toggle_nav then
        imgui.end_rect(1)
        imgui.end_rect(3)
        imgui.pop_style_color(3)
    end

    if not changed then return end
    build.toggle.handle_toggle_all(toggle_tbl, player_index, checked)
end

function build.toggle.player_toggle_all(player_index, toggle_tbl, opacity_tbl, row_idx)
    if not toggle_tbl.toggle_show then return end
    imgui.table_set_column_index(player_index)

    -- Real-time column X check shared by the checkbox and opacity slider below.
    local col_x = imgui.get_cursor_pos().x
    local win_x = state.menu_window_pos and state.menu_window_pos.x or 0
    local mx    = imgui.get_mouse().x - win_x
    local is_mouse_in_col = mx >= col_x - 4 and mx < col_x + 170

    local opacity_col_nav = player_index == 1 and 2 or 4

    local checked
    for k, v in pairs(toggle_tbl) do
        checked = k~= "toggle_show" and v
        if checked then break end
    end

    build.toggle.all_click_toggle(toggle_tbl, player_index, checked, row_idx, is_mouse_in_col)
    if not checked then return end

    imgui.push_item_width(70); imgui.same_line()
    local first, all_same
    for _, v in pairs(opacity_tbl) do
        first = first or v
        all_same = v == v or first
        if all_same then break end
    end

    local is_opacity_nav = is_hov("toggle", row_idx, opacity_col_nav) and is_mouse_in_col

    if is_opacity_nav then
        imgui.push_style_color(IC_FRAME_BG,  state.sync_enabled and C_SYNC_FRAME or C_NAV_FRAME)
        imgui.push_style_color(IC_FRAME_HOV, state.sync_enabled and C_SYNC_HOV   or C_NAV_HOV)
        imgui.begin_rect()
        imgui.begin_rect()
    end

    local changed
    local current = (all_same and first) or 50
    changed, current = build.toggle.opacity_slider("##p"..player_index.."_GlobalOpacity", current, 0.5, 0, 100)

    if imgui.is_item_active() then
        state.slider_mouse_active_this_frame = true
        set_hov("toggle", row_idx, opacity_col_nav)
    elseif imgui.is_item_hovered() then
        set_hov("toggle", row_idx, opacity_col_nav)
    end

    if is_opacity_nav then
        imgui.end_rect(2)
        imgui.end_rect(1)
        imgui.pop_style_color(2)
    end

    imgui.pop_item_width()

    if not changed then return end

    for k, _ in pairs(opacity_tbl) do
        opacity_tbl[k] = current
    end

    build.on_sync(function()
        local other = (player_index == 1) and state.config.p2.opacity or state.config.p1.opacity
        for k, _ in pairs(other) do other[k] = current end
    end, changed)

    mark_for_save()
end

function build.toggle.all_row()
    local row_idx = #build.toggle.rows_list + 1

    imgui.table_next_row()
    local row_y = imgui.get_cursor_pos().y

    if is_hov("toggle", row_idx) then
        imgui.table_set_bg_color(2, state.sync_enabled and C_SYNC_FRAME or C_NAV_FRAME)
    end

    imgui.table_set_column_index(0)
    imgui.text("All")
    if imgui.is_item_hovered() then
        set_hov("toggle", row_idx, nil)
    end

    build.toggle.player_toggle_all(1, state.config.p1.toggle, state.config.p1.opacity, row_idx)
    imgui.table_set_column_index(2)
    build.toggle.player_toggle_all(3, state.config.p2.toggle, state.config.p2.opacity, row_idx)

    row_hover_check(row_y, "toggle", row_idx)
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
    -- Full-width Sync button row rendered above the table (always visible).
    build.toggle.sync_button()

    imgui.set_next_item_open(true, 1 << 3)
    if not imgui.begin_table("ToggleTable", 4) then return end
    build.setup_columns({160, 100, 30, 125}, nil, {"", "P1", "", "P2"})
    build.toggle.column_headers()
    build.toggle.rows()
    imgui.end_table()
end

-- build.preset functions

function build.preset.rename_input(preset_name)
    local highlighted = is_hov("preset", preset_name, 5)
    if highlighted then
        imgui.push_style_color(IC_FRAME_BG,  C_NAV_FRAME)
        imgui.push_style_color(IC_FRAME_HOV, C_NAV_HOV)
    end
    local changed
    changed, state.rename_temp_name = imgui.input_text("##rename_" .. preset_name, state.rename_temp_name, 32)
    if imgui.is_item_hovered() then set_hov("preset", preset_name, 5) end
    if highlighted then imgui.pop_style_color(2) end
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

-- Renders a button with C_NAV_FRAME highlight when it was hovered last frame,
-- records hover into hov_cur, and returns click state.
local function preset_hov_button(label, preset_name, col)
    local is_highlighted = is_hov("preset", preset_name, col)
    if is_highlighted then
        imgui.push_style_color(IC_BUTTON,     C_NAV_FRAME)
        imgui.push_style_color(IC_BUTTON_HOV, C_NAV_HOV)
    end

    local clicked = imgui.button(label, {0, 0})

    if imgui.is_item_hovered() then
        set_hov("preset", preset_name, col)
    end

    if is_highlighted then imgui.pop_style_color(2) end
    return clicked
end

function build.preset.name_column(preset_name)
    imgui.table_set_column_index(0)

    if state.rename_mode == preset_name then
        build.preset.rename_input(preset_name)
        return
    end

    build.preset.name_with_color(preset_name)
    if imgui.is_item_hovered() then
        set_hov("preset", preset_name, 0)
    end
end

function build.preset.action_column(preset_name)
    imgui.table_set_column_index(1)

    if state.rename_mode == preset_name then
        if preset_hov_button("Rename##conf_" .. preset_name, preset_name, 1) then save_rename(preset_name) end
    elseif is_disabled_state() or preset_name ~= state.current_preset_name then
        if preset_hov_button("Load##load_" .. preset_name, preset_name, 1) then switch_preset(preset_name) end
    end
end

function build.preset.rename_column(preset_name)
    imgui.table_set_column_index(2)

    if state.rename_mode == preset_name then
        if preset_hov_button("Cancel##canc_" .. preset_name, preset_name, 2) then cancel_rename_mode() end
        return
    end
    if preset_hov_button("Rename##ren_" .. preset_name, preset_name, 2) then start_rename_mode(preset_name) end
end

function build.preset.duplicate_column(preset_name)
    imgui.table_set_column_index(3)

    if state.rename_mode == preset_name then return end
    if preset_hov_button("Duplicate##dup_" .. preset_name, preset_name, 3) then duplicate_preset(preset_name) end
end

function build.preset.delete_column(preset_name)
    imgui.table_set_column_index(4)

    if state.rename_mode == preset_name then return end
    if state.delete_confirm_name ~= preset_name then
        if preset_hov_button("Delete##del_" .. preset_name, preset_name, 4) then start_delete_confirm(preset_name) end
        return
    end

    if preset_hov_button("Delete?##del_" .. preset_name, preset_name, 4) then
        delete_preset(preset_name)
        state.delete_confirm_name = false
    elseif imgui.is_mouse_clicked(0) and not imgui.is_item_hovered() then
        state.delete_confirm_name = false
    end
end

function build.preset.row(preset_name)
    imgui.table_next_row()
    local row_y = imgui.get_cursor_pos().y

    if is_hov("preset", preset_name) then
        imgui.table_set_bg_color(2, C_NAV_FRAME)
    end

    build.preset.name_column(preset_name)
    build.preset.action_column(preset_name)
    build.preset.rename_column(preset_name)
    build.preset.duplicate_column(preset_name)
    build.preset.delete_column(preset_name)
    row_hover_check(row_y, "preset", preset_name)
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
    if treerow_hov_button("<", "Presets", 1, {20, 0}) then load_previous_preset() end
    if imgui.is_item_hovered() then
        imgui.set_tooltip("Previous (" .. hk.get_button_string("hotkeys_prev_preset") .. ")")
    end
    imgui.same_line()
    if treerow_hov_button(">", "Presets", 2, {20, 0}) then load_next_preset() end
    if imgui.is_item_hovered() then
        imgui.set_tooltip("Next (" .. hk.get_button_string("hotkeys_next_preset") .. ")")
    end
end

function build.preset.nav_status()
    if state.current_preset_name == "" then return end
    imgui.same_line()
    imgui.text("Current: ")
    if imgui.is_item_hovered() then set_hov("treerow", "Presets", nil) end
    imgui.same_line()
    build.preset.name_with_color(state.current_preset_name)
    if imgui.is_item_hovered() then set_hov("treerow", "Presets", nil) end
end

function build.preset.nav_reload_button()
    if not is_disabled_state() or state.current_preset_name == "" or not state.presets[state.current_preset_name] then return end
    imgui.same_line()
    if treerow_hov_button("Reload##reload_nav", "Presets", 5) then
        load_preset(state.current_preset_name)
        action_notify("Reloaded Preset " .. state.current_preset_name, "alert_on_presets")
    end
    if imgui.is_item_hovered() then imgui.set_tooltip("Reset to saved values") end
end

function build.preset.nav_save_buttons()
    if is_disabled_state() then return end
    if preset_has_unsaved_changes() then
        imgui.same_line()
        if treerow_hov_button("Save##save_nav", "Presets", 3) then save_current_preset(state.current_preset_name) end
        if imgui.is_item_hovered() then imgui.set_tooltip("Save Changes (Ctrl + Space)") end
        imgui.same_line()
        if treerow_hov_button("x##disc_nav", "Presets", 4) then
            load_preset(state.current_preset_name)
            action_notify("Changes Discarded", "alert_on_presets")
        end
        if imgui.is_item_hovered() then imgui.set_tooltip("Discard Changes (" .. hk.get_button_string("hotkeys_discard_preset") .. ")") end
    end
end

function build.preset.nav_new_button()
    if is_disabled_state() or not preset_has_unsaved_changes() then
        imgui.same_line()
        if treerow_hov_button("New##create_new", "Presets", 6) then start_create_new_mode() end
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
    local highlighted = is_hov("treerow", "Presets", 7)
    if highlighted then
        imgui.push_style_color(IC_FRAME_BG,  C_NAV_FRAME)
        imgui.push_style_color(IC_FRAME_HOV, C_NAV_HOV)
    end
    local changed
    changed, state.new_preset_name = imgui.input_text("##preset_name", state.new_preset_name)
    if imgui.is_item_hovered() then set_hov("treerow", "Presets", 7) end
    if highlighted then imgui.pop_style_color(2) end
end

function build.preset.create_buttons()
    if state.new_preset_name == "" then
        if treerow_hov_button("New##new_blank", "Presets", 3) then create_new_blank_preset() end
        imgui.same_line()
        if treerow_hov_button("Cancel##cancel_blank", "Presets", 4) then cancel_blank_preset() end
    else
        if treerow_hov_button("Create##save_new", "Presets", 3) then save_new_preset() end
        imgui.same_line()
        if treerow_hov_button("x##cancel_new", "Presets", 4) then cancel_new_preset() end
    end
end

function build.preset.creator()
    if not state.create_new_mode then return end
    imgui.same_line()
    imgui.text("New:")
    if imgui.is_item_hovered() then set_hov("treerow", "Presets", nil) end
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
    local row_y = imgui.get_cursor_pos().y
    treerow_bg("Presets")
    local preset_open = build.tree_node_stateful("Presets", true)
    -- Register hover on the tree-node label itself so the row highlights even
    -- when the mouse is over the "Presets" text rather than a button or widget.
    if imgui.is_item_hovered() then set_hov("treerow", "Presets", nil) end
    if not preset_open then
        build.preset.display()
        row_hover_check(row_y, "treerow", "Presets")
        return
    end
    build.preset.display()
    row_hover_check(row_y, "treerow", "Presets")
    build.preset.table()
    imgui.tree_pop()
end

-- build.backup functions (merged Backup/Reset)

function build.backup.menu()
    local row_y = imgui.get_cursor_pos().y
    treerow_bg("Backup/Reset")
    if not build.tree_node_stateful("Backup/Reset") then
        row_hover_check(row_y, "treerow", "Backup/Reset")
        return
    end
    row_hover_check(row_y, "treerow", "Backup/Reset")
    build.option.reset()
    build.option.backup()
    imgui.tree_pop()
end

-- build.option functions

function build.option.copy_rows()
    imgui.same_line(); imgui.spacing(); imgui.same_line()
    if treerow_hov_button("P1 to P2##p1_to_p2", "Copy", 1, {0, 0}) then
        state.config.p2 = deep_copy(state.config.p1)
    end
    imgui.same_line(); imgui.spacing(); imgui.same_line()
    if treerow_hov_button("P2 to P1##p2_to_p1", "Copy", 2, {0, 0}) then
        state.config.p1 = deep_copy(state.config.p2)
    end
end

function build.option.copy()
    local row_y = imgui.get_cursor_pos().y
    treerow_bg("Copy")
    if not build.tree_node_stateful("Copy") then
        row_hover_check(row_y, "treerow", "Copy")
        return
    end
    build.option.copy_rows()
    row_hover_check(row_y, "treerow", "Copy")
    imgui.tree_pop()
end

function build.option.reset_row(col_name, category)
    local handler_str = "P%.0f##%s_p%.0f"
    local handler_p1, handler_p2 = string.format(handler_str, 1, string.lower(col_name), 1), string.format(handler_str, 2, string.lower(col_name), 2)
    local handler_all = string.format("All##%s_all", string.lower(col_name))
    
    imgui.table_next_row()
    imgui.table_set_column_index(0)
    imgui.text(col_name)
    imgui.table_set_column_index(1)
    if imgui.button(handler_p1, {nil, 16}) then reset_defaults(category, 'p1') end
    imgui.table_set_column_index(2)
    if imgui.button(handler_p2, {nil, 16}) then reset_defaults(category, 'p2') end
    imgui.table_set_column_index(3)
    if imgui.button(handler_all, {nil, 16}) then reset_defaults(category) end
end

function build.option.reset_rows()
    build.option.reset_row("Toggles", "toggle")
    build.option.reset_row("Opacity", "opacity")
    build.option.reset_row("All", "all")
end

function build.option.reset_table()
	if not imgui.begin_table("ResetTable", 4) then return end
	build.option.reset_rows()
	imgui.end_table()
    imgui.spacing()
end

function build.option.reset()
    local row_y = imgui.get_cursor_pos().y
    treerow_bg("Reset")
    if not build.tree_node_stateful("Reset") then
        row_hover_check(row_y, "treerow", "Reset")
        return
    end
    row_hover_check(row_y, "treerow", "Reset")

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
    changed, state.config.options.hide_all_alerts = treerow_hov_checkbox("Hide##hide_all_alerts", "Alerts", 1, state.config.options.hide_all_alerts)
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
    local row_y = imgui.get_cursor_pos().y
    treerow_bg("Alerts")
    if not build.tree_node_stateful("Alerts") then
        row_hover_check(row_y, "treerow", "Alerts")
        return
    end
    build.option.alerts_hide_checkbox()
    row_hover_check(row_y, "treerow", "Alerts")
    build.option.alerts_duration_slider()
    if not state.config.options.hide_all_alerts then
        build.option.alerts_rows()
    end
    imgui.tree_pop()
end

local function reset_display_options_to_defaults()
    local default = create_default_config()
    state.config.options.hitbox_tick_duration = default.options.hitbox_tick_duration
    state.config.options.hitbox_tick_fade_speed = default.options.hitbox_tick_fade_speed
    state.config.options.property_text_duration = default.options.property_text_duration
    state.config.options.property_text_fade_speed = default.options.property_text_fade_speed
    mark_for_save()
end

local function display_option_int_slider(label, option_key, min_val, max_val, format)
    imgui.text(label)
    imgui.same_line()
    imgui.push_item_width(100)
    local changed
    changed, state.config.options[option_key] = imgui.slider_int("##" .. option_key, state.config.options[option_key], min_val, max_val, format or "%d")
    if changed then mark_for_save() end
    imgui.pop_item_width()
end

local function display_option_float_slider(label, option_key, min_val, max_val, format)
    imgui.text(label)
    imgui.same_line()
    imgui.push_item_width(100)
    local changed
    changed, state.config.options[option_key] = imgui.slider_float("##" .. option_key, state.config.options[option_key], min_val, max_val, format or "%.1f")
    if changed then mark_for_save() end
    imgui.pop_item_width()
end

function build.option.display()
    local row_y = imgui.get_cursor_pos().y
    treerow_bg("Display")
    if not build.tree_node_stateful("Display") then
        row_hover_check(row_y, "treerow", "Display")
        return
    end
    imgui.same_line()
    if treerow_hov_button("Defaults##display", "Display", 1) then
        reset_display_options_to_defaults()
    end
    row_hover_check(row_y, "treerow", "Display")

    display_option_int_slider("Tick Mark Duration:", "hitbox_tick_duration", 1, 180, "%d f")
    display_option_float_slider("Tick Mark Fade Speed:", "hitbox_tick_fade_speed", 0.1, 3.0, "%.1fx")
    display_option_int_slider("Property Text Duration:", "property_text_duration", 1, 120, "%d f")
    display_option_float_slider("Property Text Fade Speed:", "property_text_fade_speed", 0.1, 3.0, "%.1fx")

    imgui.tree_pop()
end

function build.option.hotkeys_reset_button()
    imgui.same_line()

    if state.confirm_restore_hotkeys == nil then state.confirm_restore_hotkeys = false end

    if hk.is_any_hotkey_rebinding() then
        if treerow_hov_button("Restore Defaults", "Hotkeys", 1) then
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
            if treerow_hov_button("Restore Defaults?", "Hotkeys", 1) then
                hk.reset_from_defaults_tbl(hk.default_hotkeys)
                state.confirm_restore_hotkeys = false
            end
            if imgui.is_mouse_clicked(0) and not imgui.is_item_hovered() then
                state.confirm_restore_hotkeys = false
            end
        else
            if treerow_hov_button("Restore Defaults", "Hotkeys", 1) then
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

local C_GROUP_LABEL = 0xFF888888  -- muted grey for hotkey group headers

function build.option.hotkey_buttons()
	build.option.hotkeys_reset_button()

    imgui.text_colored("Toggles", C_GROUP_LABEL)
    -- Toggle Menu has a user-bindable hotkey; F1 always works as a failsafe
    -- regardless of what is bound here (or whether anything is bound at all).
    build.option.hotkey_button("Toggle Menu: F1 or", "hotkeys_toggle_menu")
    build.option.hotkey_button("P1:", "hotkeys_toggle_p1")
    build.option.hotkey_button("P2:", "hotkeys_toggle_p2")
    build.option.hotkey_button("All:", "hotkeys_toggle_all")
    build.option.hotkey_button("Sync:", "hotkeys_toggle_sync")

    imgui.spacing()
    imgui.text_colored("Presets", C_GROUP_LABEL)
    build.option.hotkey_button("Last:", "hotkeys_prev_preset")
    build.option.hotkey_button("Next:", "hotkeys_next_preset")

    imgui.spacing()
    imgui.text_colored("Changes", C_GROUP_LABEL)
    build.option.hotkey_button("Save:", "hotkeys_save_preset")
    build.option.hotkey_button("Discard:", "hotkeys_discard_preset")
end


function build.option.hotkeys()
    local row_y = imgui.get_cursor_pos().y
    treerow_bg("Hotkeys")
    if not build.tree_node_stateful("Hotkeys") then
        row_hover_check(row_y, "treerow", "Hotkeys")
        return
    end
    imgui.same_line()
    imgui.spacing()
    build.option.hotkey_buttons()
    row_hover_check(row_y, "treerow", "Hotkeys")
    imgui.tree_pop()
end

function build.option.modes()
    local row_y = imgui.get_cursor_pos().y
    treerow_bg("Modes")
    local open = build.tree_node_stateful("Modes")
    if not open then
        row_hover_check(row_y, "treerow", "Modes")
        return
    end
    imgui.same_line()
    if treerow_hov_button("Defaults##modes", "Modes", 1) then
        local default = create_default_config()
        state.config.options.mode_training      = default.options.mode_training
        state.config.options.mode_replay        = default.options.mode_replay
        state.config.options.mode_spectate      = default.options.mode_spectate
        state.config.options.mode_single_player = default.options.mode_single_player
        state.config.options.mode_other         = default.options.mode_other
        mark_for_save()
    end
    row_hover_check(row_y, "treerow", "Modes")
    local changed
    changed, state.config.options.mode_training      = build.checkbox("Training",      state.config.options.mode_training)
    changed, state.config.options.mode_replay        = build.checkbox("Replay",        state.config.options.mode_replay)
    changed, state.config.options.mode_spectate      = build.checkbox("Spectate",      state.config.options.mode_spectate)
    changed, state.config.options.mode_single_player = build.checkbox("Single Player", state.config.options.mode_single_player)
    changed, state.config.options.mode_other         = build.checkbox("Other",         state.config.options.mode_other)
    imgui.tree_pop()
end

function build.option.misc()
    local row_y = imgui.get_cursor_pos().y
    treerow_bg("Misc")
    if not build.tree_node_stateful("Misc") then
        row_hover_check(row_y, "treerow", "Misc")
        return
    end
    row_hover_check(row_y, "treerow", "Misc")
    local changed
    changed, state.config.options.remember_window_pos = build.checkbox("Remember window position", state.config.options.remember_window_pos)
    changed, state.config.options.color_wall_splat = build.checkbox("Adjust Position marker color in wall splat range", state.config.options.color_wall_splat)

    -- The debug panel option is disabled (greyed out) when the debugger module
    -- could not be loaded.  The enable_debug_menu flag is also forced off so
    -- that a previously-saved true value from a working install doesn't open
    -- a non-functional window.
    if not debugger_available() then
        state.config.options.enable_debug_menu = false
        imgui.begin_disabled()
        imgui.checkbox("Show Debug panel  (Ctrl+F1)  [debugger unavailable]", false)
        imgui.end_disabled()
    else
        changed, state.config.options.enable_debug_menu = build.checkbox("Show Debug Panel  (Ctrl+F1)", state.config.options.enable_debug_menu)
        if changed then mark_for_save() end
    end

    imgui.tree_pop()
end

function build.option.backup_row()
    imgui.text("File:")
    imgui.push_item_width(200); imgui.same_line()
    local highlighted = is_hov("treerow", "Backup", 2)
    if highlighted then
        imgui.push_style_color(IC_FRAME_BG,  C_NAV_FRAME)
        imgui.push_style_color(IC_FRAME_HOV, C_NAV_HOV)
    end
    local changed, new_name = imgui.input_text("##backup_filename", state.backup_filename, 256)
    if imgui.is_item_hovered() then set_hov("treerow", "Backup", 2) end
    if highlighted then imgui.pop_style_color(2) end
    if changed then state.backup_filename = new_name end
    imgui.pop_item_width(); imgui.same_line()
    if treerow_hov_button("Export", "Backup", 1) then perform_backup(state.backup_filename) end
end

function build.option.backup()
    local row_y = imgui.get_cursor_pos().y
    treerow_bg("Backup")
    if not build.tree_node_stateful("Backup") then
        row_hover_check(row_y, "treerow", "Backup")
        return
    end
    if state.backup_filename == "" then
        state.backup_filename = generate_default_backup_filename()
    end
    imgui.same_line()
	build.option.backup_row()
    row_hover_check(row_y, "treerow", "Backup")
    imgui.tree_pop()
end

function build.option.menu()
    local row_y = imgui.get_cursor_pos().y
    treerow_bg("Options")
    if not build.tree_node_stateful("Options") then
        row_hover_check(row_y, "treerow", "Options")
        return
    end
    row_hover_check(row_y, "treerow", "Options")
    imgui.unindent(15)
    build.option.display()
    build.option.copy()
    build.backup.menu()   -- merged Backup/Reset group
    build.option.alerts()
    build.option.hotkeys()
    build.option.modes()
    build.option.misc()
    imgui.tree_pop()
    imgui.indent(15)
end

-- ============================================================================
-- Debug Interface
-- All implementation lives in func/better_disp_hitboxes_debugger.lua.
-- This section initialises the module (once all required locals exist) and
-- provides thin stubs so callers are never left with nil references.
-- ============================================================================

-- table_count is still used elsewhere in this file (option menus, etc.)
local function table_count(t)
    local c = 0
    if type(t) == "table" then
        for _ in pairs(t) do c = c + 1 end
    end
    return c
end

-- Shared debug sub-table on `build`.  Always exists; functions are overwritten
-- by the debugger module when available, and are no-ops otherwise.
build.debug = {}
function build.debug.inspector()  end
function build.debug.entities()   end
function build.debug.globals()    end
function build.debug.evaluator()  end
function build.debug.custom_debug() end
function build.debug.menu()       end   -- legacy stub

state.debug = state.debug or { eval_input = "", eval_output = "Ready." }

-- Initialise the debugger module now that all locals it references exist.
-- This is deferred to here (rather than the top of the file) so that closures
-- in the context table correctly capture the final upvalue references.
local function init_debugger()
    if not _debugger_module then return end

    local ctx = {
        -- Data accessors (lambda-wrapped so they always read the live value).
        get_state            = function() return state     end,
        get_build            = function() return build     end,
        get_game_mode_id     = get_game_mode_id,
        GAME_MODES           = GAME_MODES,
        get_gBattle          = function() return gBattle          end,
        get_PauseManager     = function() return PauseManager     end,
        get_bFlowManager     = function() return bFlowManager     end,
        is_facing_right      = is_facing_right,
        is_in_battle         = is_in_battle,
        get_menu_nav         = function() return menu_nav         end,
        get_timestop         = function() return timestop_frame, timestop_total_frames end,
        get_super_freeze_debug = read_training_display_super_freeze_state,
        get_frozen_draw_calls = function() return frozen_draw_calls end,
        table_count          = table_count,
        mark_for_save        = mark_for_save,
    }

    local ok, result = pcall(_debugger_module.init, ctx)
    if ok and type(result) == "table" then
        _debugger = result
    else
        local err = type(result) == "string" and result or "(unknown)"
        pcall(log.info, "[BetterHitboxViewer] debugger init failed: " .. err)
    end
end

-- build_debug_window: delegates to the module when loaded, silently skips
-- otherwise (state.config.options.enable_debug_menu will also be locked out).
local function build_debug_window()
    if not debugger_available() then return end
    _debugger.build_debug_window()
end

-- ---------------------------------------------------------------------------
-- run_custom_debug(fn)
-- Register a custom per-frame capture function from anywhere in this file.
-- fn(state) should return a string, table, or nil.  The debugger stores each
-- non-nil return value in an in-memory log that can be copied or exported as
-- JSON from the Custom Debug panel inside the developer window.
--
-- Pass nil to unregister.  If the debugger module is not loaded this is a
-- safe no-op.
-- ---------------------------------------------------------------------------
local function run_custom_debug(fn)
    if not debugger_available() then return end
    _debugger.run_custom_debug(fn)
end

local function build_menu()
    -- Swap unified hover state so this frame's widgets see last frame's hover.
    state.hov_prev = state.hov_cur
    state.hov_cur  = nil

    local title = "Hitboxes" .. hk.get_toggle_hotkey_display()
    state.force_tree_restore = (title ~= state.last_menu_title)
    state.last_menu_title = title

    -- Pin the menu's top-right corner to the top-right corner of the game window
    -- whenever the menu appears, unless the user has opted to remember its position.
    if not state.config.options.remember_window_pos then
        local display = imgui.get_display_size()
        imgui.set_next_window_pos(Vector2f.new(display.x, 0), 1 << 3, Vector2f.new(1, 0))
    end

    -- While a drag_int slider is being mouse-dragged, add ImGuiWindowFlags_NoMove (4)
    -- so the window body drag doesn't fight with slider dragging.
    -- We use the value captured at the END of the previous frame; the accumulator
    -- for this frame is reset here and re-filled during widget rendering below.
    local window_flags = state.slider_mouse_active and 64 + 16384 + 4 or 64 + 16384
    state.slider_mouse_active_this_frame = false   -- reset accumulator for this frame

    imgui.begin_window(title, true, window_flags)
    state.menu_window_pos = imgui.get_window_pos()
    local wpos  = imgui.get_window_pos()
    local wsize = imgui.get_window_size()
    local mouse = imgui.get_mouse()

    if state.last_mouse_x ~= mouse.x or state.last_mouse_y ~= mouse.y then
        state.mouse_moved_this_frame = true
        state.last_mouse_x = mouse.x
        state.last_mouse_y = mouse.y
    else
        state.mouse_moved_this_frame = false
    end

    state.menu_window_focused = mouse.x >= wpos.x and mouse.x <= wpos.x + wsize.x
                             and mouse.y >= wpos.y and mouse.y <= wpos.y + wsize.y
    build.toggle.table()
    build.preset.menu()
    build.option.menu()

    imgui.end_window()
    state.force_tree_restore = false
    -- Persist slider-active state for next frame's begin_window flags.
    state.slider_mouse_active = state.slider_mouse_active_this_frame
end

local function all_toggles_hidden()
    return state.config.p1.toggle.toggle_show or state.config.p2.toggle.toggle_show
end

local function gui_handler()
    if state.config.options.display_menu then build_menu() end
    build_debug_window()
    if not is_in_battle() then return end
    if not is_pause_menu_closed() then return end
    if not all_toggles_hidden() then return end
    if not is_mode_allowed() then return end
    process_hitboxes()
end

-- Hotkey Action Registration
--
-- All per-frame hotkey responses are registered here and dispatched by
-- hk.run_actions() in the frame loop.  This keeps action dispatch logic
-- consolidated inside the hk module rather than spread across the file.

local function register_hotkey_actions()
    -- F1 / Ctrl+F1 are always-active failsafe hotkeys that cannot be rebound
    -- and fire regardless of what is set in hotkeys_toggle_menu.
    -- Plain F1       → toggle main menu (failsafe)
    -- Ctrl + F1      → toggle debug panel (when debugger module is loaded)
    hk.register_raw_action(function()
        if hk.check_kb_key("F1", nil, true) then
            local ctrl = hk.check_kb_key("LControl", true)
                      or hk.check_kb_key("RControl", true)
                      or hk.check_kb_key("Control",  true)
            if ctrl then
                -- Ctrl+F1 toggles the debug panel only when the debugger module
                -- loaded successfully; otherwise the keypress is silently ignored.
                if debugger_available() then
                    state.config.options.enable_debug_menu = not state.config.options.enable_debug_menu
                    mark_for_save()
                end
            else
                state.config.options.display_menu = not state.config.options.display_menu
                mark_for_save()
            end
        end
    end)

    -- hotkeys_toggle_menu is the user-bindable counterpart to the F1 failsafe.
    -- F1 cannot be assigned here (the hotkey setter blocks it), so the two
    -- paths never double-fire.
    hk.register_action("hotkeys_toggle_menu", function()
        state.config.options.display_menu = not state.config.options.display_menu
        mark_for_save()
    end)
    hk.register_action("hotkeys_toggle_p1", function()
        state.config.p1.toggle.toggle_show = not state.config.p1.toggle.toggle_show
        action_notify("P1 Hitboxes " .. (state.config.p1.toggle.toggle_show and "Enabled" or "Disabled"), "alert_on_toggle")
        mark_for_save()
    end)
    hk.register_action("hotkeys_toggle_p2", function()
        state.config.p2.toggle.toggle_show = not state.config.p2.toggle.toggle_show
        action_notify("P2 Hitboxes " .. (state.config.p2.toggle.toggle_show and "Enabled" or "Disabled"), "alert_on_toggle")
        mark_for_save()
    end)
    hk.register_action("hotkeys_toggle_all", function()
        local any_active = state.config.p1.toggle.toggle_show or state.config.p2.toggle.toggle_show
        state.config.p1.toggle.toggle_show = not any_active
        state.config.p2.toggle.toggle_show = not any_active
        action_notify("All Hitboxes " .. (not any_active and "Enabled" or "Disabled"), "alert_on_toggle")
        mark_for_save()
    end)
    hk.register_action("hotkeys_toggle_sync", function()
        state.sync_enabled = not state.sync_enabled
    end)
    hk.register_action("hotkeys_prev_preset", function()
        load_previous_preset()
    end)
    hk.register_action("hotkeys_next_preset", function()
        load_next_preset()
    end)
    hk.register_action("hotkeys_save_preset", function()
        save_current_preset(state.current_preset_name)
    end)
    hk.register_action("hotkeys_discard_preset", function()
        if preset_has_unsaved_changes() then
            load_preset(state.current_preset_name)
            action_notify("Changes Discarded", "alert_on_presets")
        end
    end)
end

local function hotkey_handler()
    hk.run_actions()
end

-- Main Initialization and Frame Loop

local function initialize()
    load_config()
    if state.current_preset_name == "" then
        init_preset_name()
    end
    register_hotkey_actions()
    init_debugger()
    state.initialized = true
end

local function on_draw_ui_handler()
    build.display_menu_checkbox()
end

local function on_frame_handler()
	object_handler()
	save_handler()
	hotkey_handler()
	menu_nav_handler()
	gui_handler()
	tooltip_handler()
	action_notify_handler()
end

re.on_draw_ui(on_draw_ui_handler)

re.on_frame(on_frame_handler)

if not state.initialized then initialize() end
