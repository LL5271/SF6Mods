local MOD_NAME = "Better Info Display"
local CONFIG_PATH = "better_info_display.json"
local SAVE_DELAY = 0.5

-- 
-- Begin Hotkeys.lua
-- 

local kb, mouse, pad
local m_up, m_down, m_trig
local gp_up, gp_down, gp_trig 
local kb_state = {down = {}, released = {}, triggered={}}
local gp_state = {down = {}, released = {}, triggered={}}
local mb_state = {down = {}, released = {}, triggered={}}
local modifiers = {}
local temp_data = {}

--Merge hashed dictionaries. table_b will be merged into table_a
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

--Merge hashed dictionaries. table_b will be merged into table_a
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

--Gets an enum
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
	
	for action_name, key_name in pairs(hotkeys) do
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

local hk_data = recurse_def_settings(json.load_file("Hotkeys_data.json") or {}, def_hk_data)

for act_name, button_name in pairs(hk_data.modifier_actions) do
	hotkeys[act_name] = button_name
end

--Find the index containing a value (or value as a field) in a table
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
end

local function update_hotkey_table(hotkey_table)
	for key, value in pairs(hotkeys) do
		hotkey_table[key] = value
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

--Checks if an action's binding is down
local function chk_down(action_name)
	if hotkeys_down[action_name] == nil then
		local key_name = hotkeys[action_name]
		hotkeys_down[action_name] = kb_state.down[keys[key_name ] ]  or gp_state.down[buttons[key_name ] ] or mb_state.down[mbuttons[key_name ] ]
	end
	return hotkeys_down[action_name]
end

--Checks if an action's binding is released
local function chk_up(action_name)
	if hotkeys_up[action_name] == nil then 
		local key_name = hotkeys[action_name]
		hotkeys_up[action_name] = kb_state.released[keys[key_name ] ]  or gp_state.released[buttons[key_name ] ] or mb_state.released[mbuttons[key_name ] ]
	end
	return hotkeys_up[action_name]
end

--Checks if an action's binding is just down
local function chk_trig(action_name)
	if hotkeys_trig[action_name] == nil then 
		local key_name = hotkeys[action_name]
		hotkeys_trig[action_name] = kb_state.triggered[keys[key_name ] ]  or gp_state.triggered[buttons[key_name ] ] or mb_state.triggered[mbuttons[key_name ] ]
	end
	return hotkeys_trig[action_name]
end

--Checks if an action's binding is released or down
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

--Checks if an action's binding has been pressed twice in the past 0.25 seconds
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

--Checks if an action's binding has been held down for 'time_limit' seconds
--'check_down' specifies if the function should keep returning true while the button continues to be held
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

--Displays an imgui button that you can click then and press a button to assign a button to an action
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
			if mouse and m_up and m_up ~= 0 then
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
					hotkeys[action_name] = key_name
					key_updated = true
					goto exit
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
		end
		
		if not is_mod_2 and hotkeys[action_name.."_$"] then
			hotkey_setter(action_name.."_$", nil, true)
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
			if hotkeys[action_name] ~= "[Not Bound]" and not hotkeys[action_name.."_$_$"] and imgui.menu_item("Clear") then
				if is_mod_1 then
					hotkeys[action_name], hk_data.modifier_actions[action_name], hotkeys[action_name.."_$"], hk_data.modifier_actions[action_name.."_$"]  = hotkeys[action_name.."_$"], hk_data.modifier_actions[action_name.."_$"]
					json.dump_file("Hotkeys_data.json", hk_data)
				else
					hotkeys[action_name] = "[Not Bound]"
				end
				key_updated = true
			end
			if not is_mod_2 and default_hotkeys[action_name] and imgui.menu_item("Reset to Default") then 
				hotkeys[action_name] = default_hotkeys[action_name]
				key_updated = true
			end
			if not is_mod_2 and hotkeys[action_name] ~= "[Not Bound]" and imgui.menu_item((hotkeys[action_name.."_$"] and "Disable " or "Enable ") .. "Modifier") then
				hotkeys[action_name.."_$"] = not hotkeys[action_name.."_$"] and ((pad and pad:get_Connecting() and ((is_mod_1 and "LB (L1)") or "LT (L2)")) or ((is_mod_1 and "LShift") or "LAlt")) or nil
				hotkeys[action_name.."_$_$"], hk_data.modifier_actions[action_name.."_$_$"] = nil
				hk_data.modifier_actions[action_name.."_$"] = hotkeys[action_name.."_$"]
				json.dump_file("Hotkeys_data.json", hk_data)
			end
			imgui.end_popup() 
		end
		--[[if not is_mod_1 and not hotkeys[action_name.."_$"] and hotkeys[action_name] ~= "[Not Bound]" then
			local names = "\n"
			for act_name, key_name in pairs(hotkeys) do 
				if act_name ~= action_name and key_name == hotkeys[action_name] and key_name ~= "[Press Input]" and (not hold_action_name or modifiers[act_name] == hold_action_name) then
					if names == "\n" then
						imgui.same_line()
						imgui.text_colored("*", 0xFF00FFFF)
					end
					names = names .. "	" .. act_name .. "\n"
					if imgui.is_item_hovered() then
						imgui.set_tooltip("Shared with:" .. names)
					end
					--break
				end
			end
		end]]
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

local function write()
	
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
}

-- 
-- End Hotkeys.lua
-- 

local initialized, changed, p1_hit_dt, p2_hit_dt, training_manager, pause_manager, display_data
local config, p1, p2 = {}, {}, {}
local save_pending, save_timer = false, 0

local gBattle = sdk.find_type_definition("gBattle")
local sPlayer = gBattle:get_field("Player"):get_data(nil)
local cPlayer = sPlayer.mcPlayer
local BattleTeam = gBattle:get_field("Team"):get_data(nil)
local cTeam = BattleTeam.mcTeam

local default_config = { 
	options = { 
		display_player_info = true, 
		display_vitals = true,
		display_p1_section = true,
		display_p2_section = true,
		display_p1_general = true,
		display_p2_general = true,
		display_p1_state = true,
		display_p2_state = true,
		display_p1_movement = true,
		display_p2_movement = true,
		display_p1_attack = true,
		display_p2_attack = true,
		display_p1_latest_attack = true,
		display_p2_latest_attack = true,
		display_p1_charge = false,
		display_p2_charge = false,
		display_p1_projectiles = false,
		display_p2_projectiles = false
	},
	hotkeys = { 
		toggle_player_info = "F5", 
		toggle_vitals = "V", 
		["toggle_vitals_$"] = "Control",
		toggle_p1 = "1",
		["toggle_p1_$"] = "Shift",
		toggle_p2 = "2",
		["toggle_p2_$"] = "Shift"
	}
}

local left_wall_dr_splat_pos = -585.2
local right_wall_dr_splat_pos = 585.2

-- Charge Info
local storageData = gBattle:get_field("Command"):get_data(nil).StorageData
local p1ChargeInfo = storageData.UserEngines[0].m_charge_infos
local p2ChargeInfo = storageData.UserEngines[1].m_charge_infos
-- Fireball
local sWork = gBattle:get_field("Work"):get_data(nil)
local cWork = sWork.Global_work

local function is_paused()
	if not pause_manager then
		pause_manager = sdk.get_managed_singleton("app.PauseManager")
	end
	
	local pause_type_bit = pause_manager:get_field("_CurrentPauseTypeBit")
	if pause_type_bit == 64 or pause_type_bit == 2112 then
		return false
	end
	return true
end

local function mark_for_save() save_pending = true; save_timer = SAVE_DELAY end

local function save_config() json.dump_file(CONFIG_PATH, config); save_pending = false end

local function save_handler()
	if save_pending then
		save_timer = save_timer - (1.0 / 60.0)
		if save_timer <= 0 then save_config() end
	end
end

local function initialize()
	if not initialized then
		local init_config = json.load_file(CONFIG_PATH)
		if not init_config then config = default_config; mark_for_save()
		else config = init_config end
		config = hk.recurse_def_settings(config, default_config)
		for k, v in pairs(default_config.hotkeys) do
			if config.hotkeys[k] == nil then config.hotkeys[k] = v end
		end

		hk.setup_hotkeys(config.hotkeys, default_config.hotkeys)
		initialized = true
	end
end

local function bitand(a, b) return (a % (b + b) >= b) and b or 0 end

local function reverse_pairs(aTable)
	local keys = {}

	for k,v in pairs(aTable) do keys[#keys+1] = k end
	table.sort(keys, function (a, b) return a>b end)

	local n = 0

    return function ( )
        n = n + 1
        if n > #keys then return nil, nil end
        return keys[n], aTable[keys[n] ]
    end
end

local function abs(num)
	if num < 0 then return num * -1
	else return num end
end

local function read_sfix(sfix_obj)
    if sfix_obj.w then
        return Vector4f.new(tonumber(sfix_obj.x:call("ToString()")), tonumber(sfix_obj.y:call("ToString()")), tonumber(sfix_obj.z:call("ToString()")), tonumber(sfix_obj.w:call("ToString()")))
    elseif sfix_obj.z then
        return Vector3f.new(tonumber(sfix_obj.x:call("ToString()")), tonumber(sfix_obj.y:call("ToString()")), tonumber(sfix_obj.z:call("ToString()")))
    elseif sfix_obj.y then
        return Vector2f.new(tonumber(sfix_obj.x:call("ToString()")), tonumber(sfix_obj.y:call("ToString()")))
    end
    return tonumber(sfix_obj:call("ToString()"))
end

function imgui.multi_color(first_text, second_text, second_text_color)
    imgui.text_colored(first_text, 0xFFAAFFFF) 
    imgui.same_line()
	if second_text_color then
	    imgui.text_colored(second_text, second_text_color)
	else
		imgui.text(second_text)
	end
end

local function get_drive_color(drive)
	if drive >= -60000 and drive < -50001 then
		return 0xFFFF0073
	elseif drive >= -50000 and drive < -40001 then
		return 0XFFF7318B
	elseif drive >= -40000 and drive < -30001 then
		return 0XFFF74A99
	elseif drive >= -30000 and drive < -20001 then
		return 0XFFFC68AB
	elseif drive >= -20000 and drive < -10001 then
		return 0XFFF786B9
	elseif drive >= - 10000 and drive < -1 then
		return 0XFFFCAED2
	elseif drive >= 0 and drive < 9999 then
		return 0xFFF55727
	elseif drive >= 10000 and drive < 19999 then
		return 0xFFF5A927
	elseif drive >= 20000 and drive < 29999 then
		return 0xFFF5DD27
	elseif drive >= 30000 and drive < 39999 then
		return 0xFFDDF527
	elseif drive >= 40000 and drive < 49999 then
		return 0xFFBBF527
	elseif drive >= 50000 then
		return 0xFF5EF527
	else
		return 0xFFAAFFFF
	end
end

local function get_super_color(super)
	if super >= 0 and super < 4999 then
		return 0xFFF55727
	elseif super >= 5000 and super < 9999 then
		return 0xFFF5A927
	elseif super >= 10000 and super < 14999 then
		return 0xFFF5DD27
	elseif super >= 15000 and super < 19999 then
		return 0xFFDDF527
	elseif super >= 20000 and super < 24999 then
		return 0xFFBBF527
	elseif super >= 25000 then
		return 0xFF5EF527
	else
		return 0xFFAAFFFF
	end
end

local function get_hitbox_range(player, actParam, list)
	local facingRight = bitand(player.BitValue, 128) == 128
	local maxHitboxEdgeX = nil
	if actParam ~= nil then
		local col = actParam.Collision
		   for j, rect in reverse_pairs(col.Infos._items) do
			if rect ~= nil then
				local posX = rect.OffsetX.v / 65536.0
				local posY = rect.OffsetY.v / 65536.0
				local sclX = rect.SizeX.v / 65536.0 * 2
				local sclY = rect.SizeY.v / 65536.0 * 2
				if rect:get_field("HitPos") ~= nil then
					local hitbox_X
					if rect.TypeFlag > 0 or (rect.TypeFlag == 0 and rect.PoseBit > 0) then
                        if facingRight then
                            hitbox_X = posX + sclX / 2
                        else
                            hitbox_X = posX - sclX / 2
                        end
						if maxHitboxEdgeX == nil then
							maxHitboxEdgeX = hitbox_X
						end
						if maxHitboxEdgeX ~= nil then
							if facingRight and hitbox_X > maxHitboxEdgeX then
								maxHitboxEdgeX = hitbox_X
							elseif hitbox_X < maxHitboxEdgeX then
								maxHitboxEdgeX = hitbox_X
							end
						end
					end
				end
			end
		end
		if maxHitboxEdgeX ~= nil then
			local playerPosX = player.pos.x.v / 65536.0
			local playerStartPosX = player.act_root.x.v / 65536.0
            list.absolute_range = abs(maxHitboxEdgeX - playerStartPosX)
            list.relative_range = abs(maxHitboxEdgeX - playerPosX)
		end
	end
end

local function player_data_handler()
	training_manager = sdk.get_managed_singleton("app.training.TrainingManager")
	local snap = training_manager
	if snap then
		local t_common = snap._tCommon
		if t_common and t_common.SnapShotDatas then
			display_data = t_common.SnapShotDatas[0]._DisplayData or {}
		end
	end
	-- Action Engine
	local p1Engine = cPlayer[0].mpActParam.ActionPart._Engine
	local p2Engine = cPlayer[1].mpActParam.ActionPart._Engine
	-- P1 ActID, Current Frame, Final Frame, IASA Frame
	p1.mActionId = p1Engine:get_ActionID()
	p1.mActionFrame = p1Engine:get_ActionFrame()
	p1.mEndFrame = p1Engine:get_ActionFrameNum()
	p1.mMarginFrame = p1Engine:get_MarginFrame()
	-- P2 ActID, Current Frame, Final Frame, IASA Frame
	p2.mActionId = p2Engine:get_ActionID()
	p2.mActionFrame = p2Engine:get_ActionFrame()
	p2.mEndFrame = p2Engine:get_ActionFrameNum()
	p2.mMarginFrame = p2Engine:get_MarginFrame()
	-- P1 Startup/Active/Recovery Frame
	p1.mMainFrame = p1Engine.mParam.action.ActionFrame.MainFrame
	p1.mFollowFrame = p1Engine.mParam.action.ActionFrame.FollowFrame
	-- P2 Startup/Active/Recovery Frame
	p2.mMainFrame = p2Engine.mParam.action.ActionFrame.MainFrame
	p2.mFollowFrame = p2Engine.mParam.action.ActionFrame.FollowFrame
	-- KD Info from Frame Meter
	p1.whole_frame = display_data.FrameMeterSSData.MeterDatas[0].WholeFrame or ""
	p1.meaty_frame = display_data.FrameMeterSSData.MeterDatas[0].MeatyFrame or ""
	p1.apper_frame = display_data.FrameMeterSSData.MeterDatas[0].ApperFrame or ""
	p1.apper_frame_str = string.gsub(p1.apper_frame, "F", "")
	p1.apper_frame_int = tonumber(p1.apper_frame_str) or 0
	p1.stun_frame = display_data.FrameMeterSSData.MeterDatas[0].StunFrame or ""
	p1.stun_frame_str = string.gsub(p1.stun_frame, "F", "")
	p1.stun_frame_int = tonumber(p1.stun_frame_str) or 0
	p2.whole_frame = display_data.FrameMeterSSData.MeterDatas[1].WholeFrame or ""
	p2.meaty_frame = display_data.FrameMeterSSData.MeterDatas[1].MeatyFrame or ""
	p2.apper_frame = display_data.FrameMeterSSData.MeterDatas[1].ApperFrame or ""
	p2.apper_frame_str = string.gsub(p2.apper_frame, "F", "")
	p2.apper_frame_int = tonumber(p2.apper_frame_str) or 0
	p2.stun_frame = display_data.FrameMeterSSData.MeterDatas[1].StunFrame or ""
	p2.stun_frame_str = string.gsub(p2.stun_frame, "F", "")
	p2.stun_frame_int = tonumber(p2.stun_frame_str) or 0
	
	p1_hit_dt = cPlayer[1].pDmgHitDT
	p2_hit_dt = cPlayer[0].pDmgHitDT
	
	-- P1 Data
	p1.HP_cap = cPlayer[0].heal_new
	p1.current_HP = cPlayer[0].vital_new
	p1.HP_cooldown = cPlayer[0].healing_wait
	p1.dir = bitand(cPlayer[0].BitValue, 128) == 128
	p1.curr_hitstop = cPlayer[0].hit_stop
	p1.max_hitstop = cPlayer[0].hit_stop_org
	p1.curr_hitstun = cPlayer[0].damage_time
	p1.max_hitstun = cPlayer[0].damage_info.time
	p1.curr_blockstun = cPlayer[0].guard_time
	p1.stance = cPlayer[0].pose_st
	p1.throw_invuln = cPlayer[0].catch_muteki
	p1.full_invuln = cPlayer[0].muteki_time
	p1.juggle = cPlayer[0].combo_dm_air
	p1.burnout =cPlayer[0].incapacitated or false
	p1.startup_frames = p1.apper_frame_int
	p1.active_frames = p1.mFollowFrame - p1.mMainFrame -- TODO Make reliable
	p1.recovery_frames = read_sfix(p1.mMarginFrame) - p1.mFollowFrame -- TODO Make reliable
	p1.total_frames = read_sfix(p1.mMarginFrame) -- TODO Make reliable
	p1.advantage = p1.stun_frame_int
	p1.drive = cPlayer[0].focus_new
	p1.drive_cooldown = cPlayer[0].focus_wait
	p1.super = cTeam[0].mSuperGauge
	p1.buff = cPlayer[0].style_timer
	p1.debuff_timer = cPlayer[0].damage_cond.timer
	p1.chargeInfo = p1ChargeInfo
	p1.posX = cPlayer[0].pos.x.v / 65536.0
	p1.posY = cPlayer[0].pos.y.v / 65536.0
	p1.spdX = cPlayer[0].speed.x.v / 65536.0
	p1.spdY = cPlayer[0].speed.y.v / 65536.0
	p1.aclX = cPlayer[0].alpha.x.v / 65536.0
	p1.aclY = cPlayer[0].alpha.y.v / 65536.0
	p1.pushback = cPlayer[0].vector_zuri.speed.v / 65536.0
	p1.self_pushback = cPlayer[0].vs_vec_zuri.zuri.speed.v / 65536.0
	p1.gap = cPlayer[0].vs_distance.v / 65536.0
	p1.gap_pct = ((p1.gap - 70) / 420) * 100
	p1.combo_attack_count = cPlayer[1].combo_scale.count
	p1.combo_hit_count = cPlayer[1].combo_dm_cnt
	p1.combo_scale_now = cPlayer[1].combo_scale.now
	p1.combo_scale_start = cPlayer[1].combo_scale.start
	p1.combo_scale_buff = cPlayer[1].combo_scale.buff
	
	-- P2 Data
	p2.HP_cap = cPlayer[1].heal_new
	p2.current_HP = cPlayer[1].vital_new
	p2.HP_cooldown = cPlayer[1].healing_wait
	p2.dir = bitand(cPlayer[1].BitValue, 128) == 128
	p2.curr_hitstop = cPlayer[1].hit_stop
	p2.max_hitstop = cPlayer[1].hit_stop_org
	p2.curr_hitstun = cPlayer[1].damage_time
	p2.max_hitstun = cPlayer[1].damage_info.time
	p2.curr_blockstun = cPlayer[1].guard_time
	p2.stance = cPlayer[1].pose_st
	p2.throw_invuln = cPlayer[1].catch_muteki
	p2.full_invuln = cPlayer[1].muteki_time
	p2.juggle = cPlayer[1].combo_dm_air
	p2.burnout =cPlayer[1].incapacitated or false
	p1.startup_frames = p1.apper_frame_int
	p2.active_frames = p2.mFollowFrame - p2.mMainFrame -- TODO Make reliable
	p2.recovery_frames = read_sfix(p2.mMarginFrame) - p2.mFollowFrame -- TODO Make reliable
	p2.total_frames = read_sfix(p2.mMarginFrame) -- TODO Make reliable
	p1.advantage = p1.stun_frame_int
	p2.drive = cPlayer[1].focus_new
	p2.drive_cooldown = cPlayer[1].focus_wait
	p2.super = cTeam[1].mSuperGauge
	p2.buff = cPlayer[1].style_timer
	p2.debuff_timer = cPlayer[1].damage_cond.timer
	p2.chargeInfo = p2ChargeInfo
	p2.posX = cPlayer[1].pos.x.v / 65536.0
	p2.posY = cPlayer[1].pos.y.v / 65536.0
	p2.spdX = cPlayer[1].speed.x.v / 65536.0
	p2.spdY = cPlayer[1].speed.y.v / 65536.0
	p2.aclX = cPlayer[1].alpha.x.v / 65536.0
	p2.aclY = cPlayer[1].alpha.y.v / 65536.0
	p2.pushback = cPlayer[1].vector_zuri.speed.v / 65536.0
	p2.self_pushback = cPlayer[1].vs_vec_zuri.zuri.speed.v / 65536.0
	p2.gap = cPlayer[1].vs_distance.v / 65536.0
	p2.combo_attack_count = cPlayer[0].combo_scale.count
	p2.combo_hit_count = cPlayer[0].combo_dm_cnt
	p2.combo_scale_now = cPlayer[0].combo_scale.now
	p2.combo_scale_start = cPlayer[0].combo_scale.start
	p2.combo_scale_buff = cPlayer[0].combo_scale.buff

	if p1.burnout then
		p1.drive_adjusted = p1.drive - 60000
	else
		p1.drive_adjusted = p1.drive
	end

	if p2.burnout then
		p2.drive_adjusted = p2.drive - 60000
	else
		p2.drive_adjusted = p2.drive
	end
	
	if p1.max_blockstun == nil then
		p1.max_blockstun = 0
	end
	if p1.curr_blockstun > p1.max_blockstun then
		p1.max_blockstun = p1.curr_blockstun
	elseif p1.curr_blockstun == 0 then
		p1.max_blockstun = 0
	end

	if p2.max_blockstun == nil then
		p2.max_blockstun = 0
	end
	if p2.curr_blockstun > p2.max_blockstun then
		p2.max_blockstun = p2.curr_blockstun
	elseif p2.curr_blockstun == 0 then
		p2.max_blockstun = 0
	end
end

local indentation_unit = 9

local function build_options()
	changed, config.options.display_player_info = imgui.checkbox(string.format("Display Main Window", hk.hotkeys.toggle_player_info), config.options.display_player_info)
	if changed then mark_for_save() end
	imgui.same_line(); if hk.hotkey_setter("toggle_player_info", nil, "") then hk.update_hotkey_table(config.hotkeys); mark_for_save() end

	changed, config.options.display_vitals = imgui.checkbox(string.format("Display Vitals", hk.hotkeys.toggle_vitals), config.options.display_vitals)
	if changed then mark_for_save() end
	imgui.same_line(); if hk.hotkey_setter("toggle_vitals", nil, "") then hk.update_hotkey_table(config.hotkeys); mark_for_save() end

	changed, config.options.display_p1_section = imgui.checkbox(string.format("Display P1 Section", hk.hotkeys.toggle_p1), config.options.display_p1_section)
	if changed then mark_for_save() end
	imgui.same_line(); if hk.hotkey_setter("toggle_p1", nil, "") then hk.update_hotkey_table(config.hotkeys); mark_for_save() end

	changed, config.options.display_p2_section = imgui.checkbox(string.format("Display P2 Section", hk.hotkeys.toggle_p2), config.options.display_p2_section)
	if changed then mark_for_save() end
	imgui.same_line(); if hk.hotkey_setter("toggle_p2", nil, "") then hk.update_hotkey_table(config.hotkeys); mark_for_save() end
end

local function build_options_menu()
    if not imgui.tree_node("Info Display") then return end
	build_options()
	imgui.tree_pop()
end

local function build_vitals_section()
	local hk_str = hk.get_button_string("toggle_vitals") or ""
	local subbed = string.gsub(hk_str, "%s*Alpha%s*", "")
	
	if not config.options.display_vitals then
		if imgui.button("Vitals (" .. subbed .. ")") then
			config.options.display_vitals = true
			mark_for_save()
		end
		return
	else
		if imgui.button("Hide Vitals (" .. subbed .. ")") then
			config.options.display_vitals = false
			mark_for_save()
		end
	end
	
	imgui.indent(indentation_unit)
	imgui.multi_color("Gap:", string.format("%.0f", p1.gap) .. " (" .. string.format("%.0f", p1.gap_pct) .. "%)")
	imgui.multi_color("Advantage:", p1.advantage)
	if (p1.dir and p1.posX <= left_wall_dr_splat_pos) or (not p1.dir and p1.posX >= right_wall_dr_splat_pos) then
		imgui.multi_color("P1 Pos:", string.format("%.1f", p1.posX) or "", 0XFFFFEA00)
	else
		imgui.multi_color("P1 Pos:", string.format("%.1f", p1.posX) or "")
	end
	imgui.multi_color("P1 Drive:", p1.drive_adjusted, get_drive_color(p1.drive_adjusted))
	imgui.multi_color("P1 Super:", p1.super, get_super_color(p2.super))
	if (p2.dir and p2.posX <= left_wall_dr_splat_pos) or (not p2.dir and p2.posX >= right_wall_dr_splat_pos) then
		imgui.multi_color("P2 Pos:", string.format("%.1f", p2.posX) or "", 0XFFFFEA00)
	else
		imgui.multi_color("P2 Pos:", string.format("%.1f", p2.posX) or "")
	end
	imgui.multi_color("P2 Drive:", p2.drive_adjusted, get_drive_color(p2.drive_adjusted))
	imgui.multi_color("P2 Super:", p2.super, get_super_color(p2.super))
end

local function build_player_show_buttons(player_index, func)
	local player_name = "P" .. (player_index + 1)
	local hk_name = player_index == 0 and "toggle_p1" or "toggle_p2"
	
	local hk_str = hk.get_button_string(hk_name) or ""
	local subbed = string.gsub(hk_str, "%s*Alpha%s*", "")
	build_visibility_toggle_buttons(player_name, func, hk_name)
end

local function build_general_section(player_name, general_config_key, player_data)
	if imgui.button(string.format("General (%s)##%s_general_info", config.options[general_config_key] and "Hide" or "Show", player_name)) then
		config.options[general_config_key] = not config.options[general_config_key]
		mark_for_save()
	end

	if config.options[general_config_key] then
		imgui.indent(indentation_unit)
		imgui.multi_color("HP Current:", player_data.current_HP)
		imgui.multi_color("HP Cap:", player_data.HP_cap)
		imgui.multi_color("HP Percent:", string.format("%.1f", player_data.current_HP / player_data.HP_cap * 100))
		imgui.multi_color("HP Regen Cooldown:", player_data.HP_cooldown)
		imgui.multi_color("Burnout:", tostring(player_data.burnout))
		imgui.multi_color("Drive Gauge:", player_data.drive_adjusted)
		imgui.multi_color("Drive Percentage:", string.format("%.1f", player_data.drive_adjusted / 60000 * 100))
		imgui.multi_color("Drive Cooldown:", player_data.drive_cooldown)
		imgui.multi_color("Super Gauge:", player_data.super)
		imgui.multi_color("Buff Duration:", player_data.buff)
		imgui.multi_color("Debuff Duration:", player_data.debuff_timer)
		imgui.unindent(indentation_unit)
	end
	imgui.unindent(indentation_unit)
end

local function build_player_section(player_index, player_data, hit_dt)
	local cplayer = cPlayer[player_index]
	local cteam = cTeam[player_index]
	local player_name = player_index == 0 and "P1" or "P2"
	local opp_index = player_index == 0 and 1 or 0
	local opp_player_data = player_index == 0 and p2 or p1
	local projectile_filter = player_index
	
	local config_key = player_index == 0 and "display_p1_section" or "display_p2_section"
	local opp_config_key = player_index == 0 and "display_p2_section" or "display_p1_section"
	local hk_name = player_index == 0 and "toggle_p1" or "toggle_p2"
	
	local hk_str = hk.get_button_string(hk_name) or ""
	local subbed = string.gsub(hk_str, "%s*[Aa]lpha%s*", "")
	
	if not config.options[config_key] then
		if imgui.button(player_name .. " (" .. subbed .. ")") then
			config.options[config_key] = true
			mark_for_save()
		end
		if not config.options[opp_config_key] and not config.options[config_key] then
			imgui.same_line()
		end
		return
	else
		if imgui.button("Hide " .. player_name .. " (" .. subbed .. ")") then
			config.options[config_key] = false
			mark_for_save()
		end
	end
	
	local general_config_key = player_index == 0 and "display_p1_general" or "display_p2_general"
	imgui.indent(indentation_unit)
	build_general_section(player_name, general_config_key, player_data)

	local state_config_key = player_index == 0 and "display_p1_state" or "display_p2_state"

	imgui.indent(indentation_unit)
	local label = string.format("State (%s)##%s_state_info", config.options[state_config_key] and "Hide" or "Show", player_name)
	local subbed = label.gsub(label, " (Show)", "")
	if imgui.button(subbed) then
		config.options[state_config_key] = not config.options[state_config_key]
		mark_for_save()
	end
	
	if config.options[state_config_key] then
		imgui.indent(indentation_unit)
		imgui.multi_color("Action ID:", player_data.mActionId)
		imgui.multi_color("Frame:", math.floor(read_sfix(player_data.mActionFrame)) .. " / " .. math.floor(read_sfix(player_data.mMarginFrame)) .. " (" .. math.floor(read_sfix(player_data.mEndFrame)) .. ")")
		imgui.multi_color("Hitstop:", player_data.curr_hitstop .. " / " .. player_data.max_hitstop)
		imgui.multi_color("Hitstun:", player_data.curr_hitstun .. " / " .. player_data.max_hitstun)
		imgui.multi_color("Blockstun:", player_data.curr_blockstun .. " / " .. player_data.max_blockstun)
		imgui.multi_color("Throw Invul Timer:", player_data.throw_invuln)
		imgui.multi_color("Intangible Timer:", player_data.full_invuln)
		imgui.unindent(indentation_unit)
	end
	imgui.unindent(indentation_unit)
	
	local movement_config_key = player_index == 0 and "display_p1_movement" or "display_p2_movement"
	
	imgui.indent(indentation_unit)
	if imgui.button(string.format("Movement (%s)##%s_movement_info", config.options[movement_config_key] and "Hide" or "Show", player_name)) then
		config.options[movement_config_key] = not config.options[movement_config_key]
		mark_for_save()
	end
	
	if config.options[movement_config_key] then
		imgui.indent(indentation_unit)
		if player_data.dir == true then
			imgui.multi_color("Facing:", "Right") 
		else 
			imgui.multi_color("Facing:", "Left")
		end
		if player_data.stance == 0 then
			imgui.multi_color("Stance:", "Standing")
		elseif player_data.stance == 1 then
			imgui.multi_color("Stance:", "Crouching")
		else
			imgui.multi_color("Stance:", "Jumping")
		end
		imgui.multi_color("Position X:", string.format("%.2f", player_data.posX))
		imgui.multi_color("Position Y:", string.format("%.2f", player_data.posY))
		imgui.multi_color("Speed X:", string.format("%.2f", player_data.spdX))
		imgui.multi_color("Speed Y:", string.format("%.2f", player_data.spdY))
		imgui.multi_color("Accel X:", string.format("%.2f", player_data.aclX))
		imgui.multi_color("Accel Y:", string.format("%.2f", player_data.aclY))
		imgui.multi_color("Pushback:", string.format("%.2f", player_data.pushback))
		imgui.multi_color("Self Pushback:", string.format("%.2f", player_data.self_pushback))
		imgui.multi_color("Opponent Gap:", player_data.gap)
		imgui.unindent(indentation_unit)
	end
	imgui.unindent(indentation_unit)

	local attack_config_key = player_index == 0 and "display_p1_attack" or "display_p2_attack"

	imgui.indent(indentation_unit)
	if imgui.button(string.format("Attack (%s)##%s_attack_info", config.options[attack_config_key] and "Hide" or "Show", player_name)) then
		config.options[attack_config_key] = not config.options[attack_config_key]
		mark_for_save()
	end
	
	if config.options[attack_config_key] then
		imgui.indent(indentation_unit)
		get_hitbox_range(cplayer, cplayer.mpActParam, player_data or nil)
		imgui.multi_color("Startup Frames:", player_data.startup_frames)
		imgui.multi_color("Active Frames:", player_data.active_frames)
		imgui.multi_color("Recovery Frames:", string.format("%.0f", player_data.recovery_frames))
		imgui.multi_color("Total Frames:", string.format("%.0f", player_data.total_frames))
		imgui.multi_color("Advantage:", player_data.advantage)
		imgui.multi_color("Absolute Range:", string.format("%.2f", player_data.absolute_range or 0))
		imgui.multi_color("Relative Range:", string.format("%.2f", player_data.relative_range or 0))
		imgui.multi_color("Juggle Counter:", opp_player_data.juggle)
		imgui.multi_color("Combo Hit Count:", player_data.combo_hit_count)
		imgui.multi_color("Combo Attack Count:", player_data.combo_attack_count)
		imgui.multi_color("Starter Scaling:", 100 - player_data.combo_scale_start .. "%")
		imgui.multi_color("Current Scaling:", player_data.combo_scale_now .. "%")

		local next_hit_scaling_calc = 100
		if player_data.combo_attack_count == 1 then
			if player_data.combo_scale_buff == 10 then
				next_hit_scaling_calc = (100 - player_data.combo_scale_start)
			else
				next_hit_scaling_calc = (100 - player_data.combo_scale_start) - player_data.combo_scale_buff
			end
		elseif player_data.combo_attack_count > 1 then
			next_hit_scaling_calc = (100 - player_data.combo_scale_start) - player_data.combo_scale_buff
		else
			next_hit_scaling_calc = 100 - player_data.combo_scale_buff
		end
		imgui.multi_color("Next Hit Scaling:", next_hit_scaling_calc .. "%")
		imgui.unindent(indentation_unit)
	end
	imgui.unindent(indentation_unit)

	local latest_attack_config_key = player_index == 0 and "display_p1_latest_attack" or "display_p2_latest_attack"
	
	if config.options[attack_config_key] then
		imgui.indent(indentation_unit)
		if imgui.button(string.format("Latest Attack (%s)##%s_latest_attack_info", config.options[latest_attack_config_key] and "Hide" or "Show", player_name)) then
			config.options[latest_attack_config_key] = not config.options[latest_attack_config_key]
			mark_for_save()
		end
		
		if config.options[latest_attack_config_key] then
			imgui.indent(indentation_unit)
			if hit_dt == nil then
				imgui.text_colored("No hit yet", 0xFFAAFFFF)
			else
				imgui.multi_color("Damage:", hit_dt.DmgValue)
				imgui.multi_color("Self Drive Gain:", hit_dt.FocusOwn)
				imgui.multi_color("Opponent Drive Gain:", hit_dt.FocusTgt)
				imgui.multi_color("Self Super Gain:", hit_dt.SuperOwn)
				imgui.multi_color("Opponent Super Gain:", hit_dt.SuperTgt)
				imgui.multi_color("Self Hitstop:", hit_dt.HitStopOwner)
				imgui.multi_color("Opponent Hitstop:", hit_dt.HitStopTarget)
				imgui.multi_color("Stun:", hit_dt.HitStun)
				imgui.multi_color("Knockdown Duration:", hit_dt.DownTime)
				imgui.multi_color("Juggle Limit:", hit_dt.JuggleLimit)
				imgui.multi_color("Juggle Increase:", hit_dt.JuggleAdd)
				imgui.multi_color("Juggle Start:", hit_dt.Juggle1st)
			end
			imgui.unindent(indentation_unit)
		end
		imgui.unindent(indentation_unit)
	end

	if player_data.chargeInfo:get_Count() > 0 then
		local charge_config_key = player_index == 0 and "display_p1_charge" or "display_p2_charge"
		
		imgui.indent(indentation_unit)
		if imgui.button(string.format("Charge (%s)##%s_charge_info", config.options[charge_config_key] and "Hide" or "Show", player_name)) then
			config.options[charge_config_key] = not config.options[charge_config_key]
			mark_for_save()
		end
		
		if config.options[charge_config_key] then
			imgui.indent(indentation_unit)
			for i=0,player_data.chargeInfo:get_Count() - 1 do
				local value = player_data.chargeInfo:get_Values()._dictionary._entries[i].value
				if value ~= nil then
					imgui.unindent(5)
					imgui.multi_color("","Move " .. i + 1)
					imgui.indent(10)
					imgui.multi_color("Charge Time:", value.charge_frame)
					imgui.multi_color("Keep Time:", value.keep_frame)
					imgui.unindent(10)
					imgui.indent(5)
				end
			end
			imgui.unindent(indentation_unit)
		end
		imgui.unindent(indentation_unit)
	end

	local projectiles_config_key = player_index == 0 and "display_p1_projectiles" or "display_p2_projectiles"
	
	imgui.indent(indentation_unit)
	if imgui.button(string.format("Projectiles (%s)##%s_projectiles", config.options[projectiles_config_key] and "Hide" or "Show", player_name)) then
		config.options[projectiles_config_key] = not config.options[projectiles_config_key]
		mark_for_save()
	end
	
	if config.options[projectiles_config_key] then
		imgui.indent(indentation_unit)
		for i, obj in pairs(cWork) do
			if obj.owner_add ~= nil and obj.pl_no == projectile_filter then
				local objEngine = obj.mpActParam.ActionPart._Engine
				imgui.text("Projectile " .. i)
				imgui.indent(indentation_unit)
				imgui.multi_color("Action ID:", obj.mActionId)
				imgui.multi_color("Action Frame:", math.floor(read_sfix(objEngine:get_ActionFrame())) .. " / " .. math.floor(read_sfix(objEngine:get_MarginFrame())) .. " (" .. math.floor(read_sfix(objEngine:get_ActionFrameNum())) .. ")")
				imgui.multi_color("Position X:", obj.pos.x.v / 65536.0)
				imgui.multi_color("Position Y:", obj.pos.y.v / 65536.0)
				imgui.multi_color("Speed X:", obj.speed.x.v / 65536.0)
				imgui.multi_color("Speed Y:", obj.speed.y.v / 65536.0)
				imgui.multi_color("Current Hitstop:", obj.hit_stop .. " / " .. obj.hit_stop_org)
				imgui.unindent(indentation_unit)
			end
		end
		imgui.unindent(indentation_unit)
	end
	imgui.unindent(indentation_unit)
end

local function build_player_info_window()
	imgui.set_next_window_size({220, 0})
	imgui.begin_window("Player Info", true, 8|64)
	build_vitals_section()
	build_player_section(0, p1, p1_hit_dt)
	build_player_section(1, p2, p2_hit_dt)
	imgui.end_window()
end

local function build_handler()
	if config.options.display_player_info and not is_paused() then build_player_info_window() end
end

local function hotkey_handler()
	if hk.check_hotkey("toggle_player_info") then
		config.options.display_player_info = not config.options.display_player_info
		mark_for_save()
	end
	if hk.check_hotkey("toggle_vitals") then
		config.options.display_vitals = not config.options.display_vitals
		mark_for_save()
	end
	if hk.check_hotkey("toggle_p1") then
		config.options.display_p1_section = not config.options.display_p1_section
		mark_for_save()
	end
	if hk.check_hotkey("toggle_p2") then
		config.options.display_p2_section = not config.options.display_p2_section
		mark_for_save()
	end
end

initialize()

re.on_draw_ui(function() build_options_menu() end)

re.on_frame(function()
    if sPlayer.prev_no_push_bit == 0 then return end
	save_handler(); hotkey_handler(); player_data_handler(); build_handler()
end)