local CONFIG_PATH = "better_disp_hitboxes.json"
local SAVE_DELAY = 0.5
local KEY_CTRL = 0x11
local KEY_F1 = 0x70
local KEY_1 = 0x31
local KEY_2 = 0x32
local KEY_LEFT = 0x25
local KEY_RIGHT = 0x27
local KEY_3 = 0x33
local KEY_SPACE = 0x20

local this, gBattle, pause_manager = {}
this.prev_key_states, this.presets, this.preset_names, this.string_buffer = {}, {}, {}, {}
this.current_preset_name, this.previous_preset_name, this.new_preset_name, this.rename_temp_name = "", "", "", ""
this.initialized, this.rename_mode, this.create_new_mode, this.delete_confirm_name = false, false, false, false
this.key_ready, this.save_pending, this.save_timer, this.config = nil, nil, nil, nil
this.tooltip_timer, this.tooltip_msg = 0, ""

-- Utils

local function deep_copy(obj)
	if type(obj) ~= 'table' then return obj end
	local copy = {}
	for k, v in pairs(obj) do copy[k] = deep_copy(v) end
	return copy
end

local function bitand(a, b) return (a % (b + b) >= b) and b or 0 end

-- Config

local function mark_for_save() this.save_pending = true; this.save_timer = SAVE_DELAY; end

local function create_default_config()
	local toggle_options = {
		toggle_show = true,
		hitboxes = true, hitboxes_outline = true,
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
			alert_on_save = true
		},
		p1 = {toggle = deep_copy(toggle_options), opacity = deep_copy(opacity_options)},
		p2 = {toggle = deep_copy(toggle_options), opacity = deep_copy(opacity_options)}
	}
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
		presets = this.presets,
		current_preset = this.current_preset_name,
		config = this.config
	}; json.dump_file(CONFIG_PATH, data_to_save); this.save_pending = false
end

local function rebuild_preset_names()
	this.preset_names = {}
	for name, _ in pairs(this.presets) do table.insert(this.preset_names, name) end
	table.sort(this.preset_names, function(a, b) return string.lower(a) < string.lower(b) end)
end

local function load_config()
	local loaded = json.load_file(CONFIG_PATH)
	if loaded then
		if loaded.presets then
			this.presets = loaded.presets
			rebuild_preset_names()
		end
		if loaded.current_preset then this.current_preset_name = loaded.current_preset end
		if loaded.config then this.config = validate_config(loaded.config)
		else this.config = validate_config(loaded) end
	else
		this.config = create_default_config()
		this.presets, this.current_preset_name, this.preset_names = {}, "", {}
		mark_for_save()
	end
end

local function save_handler()
	if this.save_pending then
		this.save_timer = this.save_timer - (1.0 / 60.0)
		if this.save_timer <= 0 then save_config() end
	end
end

local function reset_all_default(player)
	local default = create_default_config()
	if player == nil then
		this.config.p1 = deep_copy(default.p1)
		this.config.p2 = deep_copy(default.p2)
	elseif player == "p1" or player == "p2" then
		this.config[player] = deep_copy(default[player]) end
	mark_for_save(); return this.config
end

local function reset_toggle_default(player)
	local default = create_default_config()
	if player == nil then
		this.config.p1.toggle = deep_copy(default.p1.toggle)
		this.config.p2.toggle = deep_copy(default.p2.toggle)
	elseif player == "p1" or player == "p2" then
		this.config[player].toggle = deep_copy(default[player].toggle) end
	mark_for_save(); return this.config
end

local function reset_opacity_default(player)
	local default = create_default_config()
	if player == nil then
		this.config.p1.opacity = deep_copy(default.p1.opacity)
		this.config.p2.opacity = deep_copy(default.p2.opacity)
	elseif player == "p1" or player == "p2" then
		this.config[player].opacity = deep_copy(default[player].opacity) end
	mark_for_save(); return this.config
end

local function apply_opacity(opacity, colorWithoutAlpha)
	local alpha = math.floor(opacity * 2.55)
	return alpha * 0x1000000 + colorWithoutAlpha
end

local function is_pause_menu_closed()
	local pause_type_bit = 0
	if not pause_manager then pause_manager = sdk.get_managed_singleton("app.PauseManager")
	elseif pause_manager then pause_type_bit = pause_manager:get_field("_CurrentPauseTypeBit") end
	return pause_type_bit == 64 or pause_type_bit == 2112
end

local function reverse_pairs(aTable)
	local keys = {}
	for k, v in pairs(aTable) do keys[#keys+1] = k end
	table.sort(keys, function (a, b) return a > b end)
	local n = 0
	return function()
		n = n + 1; if n > #keys then return nil, nil end
		return keys[n], aTable[keys[n]] end
end


local function get_vectors(rect)
	local posX, posY = rect.OffsetX.v / 6553600.0, rect.OffsetY.v / 6553600.0
	local sclX, sclY = rect.SizeX.v / 6553600.0 * 2, rect.SizeY.v / 6553600.0 * 2
	posX, posY = posX - sclX / 2, posY - sclY / 2
	local vTL = Vector3f.new(posX - sclX / 2,  posY + sclY / 2, 0)
	local vTR = Vector3f.new(posX + sclX / 2,  posY + sclY / 2, 0)
	local vBL = Vector3f.new(posX - sclX / 2,  posY - sclY / 2, 0)
	local vBR = Vector3f.new(posX + sclX / 2,  posY - sclY / 2, 0)
	return vTL, vTR, vBL, vBR
end

local function get_dimensions(vTL, vTR, vBL, vBR)
	local dw = draw.world_to_screen
	local tl, tr, bl, br = dw(vTL), dw(vTR), dw(vBL), dw(vBR)
	if not (tl and tr and bl and br) then return nil, nil, nil, nil end
	return (tl.x + tr.x) / 2, (bl.y + tl.y) / 2, (tr.x - tl.x), (tl.y - bl.y)
end

local function draw_hitboxes(work, actParam, player_config)
    local col = actParam.Collision
    for _, rect in reverse_pairs(col.Infos._items) do
        if rect ~= nil then
			local vTL, vTR, vBL, vBR = get_vectors(rect)
			local finalPosX, finalPosY, finalSclX, finalSclY = get_dimensions(vTL, vTR, vBL, vBR)
			if (finalPosX and finalPosY and finalSclX and finalSclY) then
				if rect:get_field("HitPos") ~= nil then
					if rect.TypeFlag > 0 then
						if player_config.toggle.hitboxes_outline then
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
								apply_opacity(player_config.opacity.hitbox_outline, 0x0040C0))
						end
						if player_config.toggle.hitboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
								apply_opacity(player_config.opacity.hitbox, 0x0040C0))
						end
						if player_config.toggle.properties then
							local buffer_idx, has_exceptions, has_combo = 0, false, false
							if bitand(rect.CondFlag, 16) == 16 or bitand(rect.CondFlag, 32) == 32 or 
								bitand(rect.CondFlag, 64) == 64 or bitand(rect.CondFlag, 256) == 256 or 
								bitand(rect.CondFlag, 512) == 512 then
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Can't Hit "
								if bitand(rect.CondFlag, 16) == 16 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Standing, " 
								end
								if bitand(rect.CondFlag, 32) == 32 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Crouching, " 
								end
								if bitand(rect.CondFlag, 64) == 64 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Airborne, " 
								end
								if bitand(rect.CondFlag, 256) == 256 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Forward, " 
								end
								if bitand(rect.CondFlag, 512) == 512 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Backwards, " 
								end
								this.string_buffer[buffer_idx] = string.sub(this.string_buffer[buffer_idx], 1, -3)
                                buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "\n"
								has_exceptions = true
							end
							if bitand(rect.CondFlag, 262144) == 262144 or bitand(rect.CondFlag, 524288) == 524288 then
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Combo Only\n"
								has_combo = true
							end
							if has_exceptions or has_combo then
								local fullString = table.concat(this.string_buffer, "", 1, buffer_idx)
								draw.text(fullString, finalPosX, (finalPosY + finalSclY),
									apply_opacity(player_config.opacity.properties, 0xFFFFFF))
							end
						end
					elseif ((rect.TypeFlag == 0 and rect.PoseBit > 0) or rect.CondFlag == 0x2C0) then
						if player_config.toggle.throwboxes_outline then
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
								apply_opacity(player_config.opacity.throwbox_outline, 0xD080FF))
						end
						if player_config.toggle.throwboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
								apply_opacity(player_config.opacity.throwbox, 0xD080FF))
						end
						if player_config.toggle.properties then
							local buffer_idx, has_exceptions, has_combo = 0, false, false
							if bitand(rect.CondFlag, 16) == 16 or bitand(rect.CondFlag, 32) == 32 or 
								bitand(rect.CondFlag, 64) == 64 or bitand(rect.CondFlag, 256) == 256 or 
								bitand(rect.CondFlag, 512) == 512 then
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Can't Hit "
								if bitand(rect.CondFlag, 16) == 16 then
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Standing, " end
								if bitand(rect.CondFlag, 32) == 32 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Crouching, " end
								if bitand(rect.CondFlag, 64) == 64 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Airborne, " end
								if bitand(rect.CondFlag, 256) == 256 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Forward, " end
								if bitand(rect.CondFlag, 512) == 512 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Backwards, " end
								this.string_buffer[buffer_idx] = string.sub(this.string_buffer[buffer_idx], 1, -3)
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "\n"
								has_exceptions = true
							end
							if bitand(rect.CondFlag, 262144) == 262144 or bitand(rect.CondFlag, 524288) == 524288 then
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Combo Only\n"
								has_combo = true
							end
							if has_exceptions or has_combo then
								local fullString = table.concat(this.string_buffer, "", 1, buffer_idx)
								draw.text(fullString, finalPosX, (finalPosY + finalSclY),
									apply_opacity(player_config.opacity.properties, 0xFFFFFF)) end
						end
					elseif rect.GuardBit == 0 then
						if player_config.toggle.clashboxes_outline then
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
								apply_opacity(player_config.opacity.clashbox_outline, 0x3891E6)) end
						if player_config.toggle.clashboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
								apply_opacity(player_config.opacity.clashbox, 0x3891E6)) end
					else
						if player_config.toggle.proximityboxes_outline then
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
								apply_opacity(player_config.opacity.proximitybox_outline, 0x5b5b5b)) end
						if player_config.toggle.proximityboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
								apply_opacity(player_config.opacity.proximitybox, 0x5b5b5b)) end
					end
				elseif rect:get_field("Attr") ~= nil then
					if player_config.toggle.pushboxes_outline then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
							apply_opacity(player_config.opacity.pushbox_outline, 0x00FFFF)) end
					if player_config.toggle.pushboxes then
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
							apply_opacity(player_config.opacity.pushbox, 0x00FFFF)) end
				elseif rect:get_field("HitNo") ~= nil then
					if rect.TypeFlag > 0 then
						if player_config.toggle.hurtboxes or player_config.toggle.hurtboxes_outline then
							if rect.Type == 2 or rect.Type == 1 then
								if player_config.toggle.hurtboxes_outline then
									draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
										apply_opacity(player_config.opacity.hurtbox_outline, 0xFF0080)) end
								if player_config.toggle.hurtboxes then
									draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
										apply_opacity(player_config.opacity.hurtbox, 0xFF0080)) end
							else
								if player_config.toggle.hurtboxes_outline then
									draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
										apply_opacity(player_config.opacity.hurtbox_outline, 0x00FF00)) end
								if player_config.toggle.hurtboxes then
									draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
										apply_opacity(player_config.opacity.hurtbox, 0x00FF00)) end
							end
							if player_config.toggle.properties then
								local buffer_idx = 0
								if rect.TypeFlag == 1 then
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Projectile Invulnerable\n"
								elseif rect.TypeFlag == 2 then
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Strike Invulnerable\n" end
								local has_immune = false
								if bitand(rect.Immune, 1) == 1 or bitand(rect.Immune, 2) == 2 or 
									bitand(rect.Immune, 4) == 4 or bitand(rect.Immune, 64) == 64 or 
									bitand(rect.Immune, 128) == 128 then
									has_immune = true
									if bitand(rect.Immune, 1) == 1 then 
										buffer_idx = buffer_idx + 1
										this.string_buffer[buffer_idx] = "Stand, " end
									if bitand(rect.Immune, 2) == 2 then 
										buffer_idx = buffer_idx + 1
										this.string_buffer[buffer_idx] = "Crouch, " end
									if bitand(rect.Immune, 4) == 4 then 
										buffer_idx = buffer_idx + 1
										this.string_buffer[buffer_idx] = "Air, " end
									if bitand(rect.Immune, 64) == 64 then 
										buffer_idx = buffer_idx + 1
										this.string_buffer[buffer_idx] = "Behind, " end
									if bitand(rect.Immune, 128) == 128 then 
										buffer_idx = buffer_idx + 1
										this.string_buffer[buffer_idx] = "Reverse, " end
									this.string_buffer[buffer_idx] = string.sub(this.string_buffer[buffer_idx], 1, -3)
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = " Attack Intangible\n"
								end
								if buffer_idx > 0 then
									local fullString = table.concat(this.string_buffer, "", 1, buffer_idx)
									draw.text(fullString, finalPosX, (finalPosY + finalSclY),
										apply_opacity(player_config.opacity.properties, 0xFFFFFF)) end
							end
						end
					elseif player_config.toggle.throwhurtboxes or player_config.toggle.throwhurtboxes_outline then
						if player_config.toggle.throwhurtboxes_outline then
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
								apply_opacity(player_config.opacity.throwhurtbox_outline, 0xFF0000)) end
						if player_config.toggle.throwhurtboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
								apply_opacity(player_config.opacity.throwhurtbox, 0xFF0000)) end
						end
				end
			elseif rect:get_field("KeyData") ~= nil then
				if player_config.toggle.uniqueboxes_outline then
					draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
						apply_opacity(player_config.opacity.uniquebox_outline, 0xEEFF00)) end
				if player_config.toggle.uniqueboxes then
					draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
						apply_opacity(player_config.opacity.uniquebox, 0xEEFF00)) end
			else
				if player_config.toggle.throwhurtboxes_outline then
					draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
						apply_opacity(player_config.opacity.throwhurtbox_outline, 0xFF0000)) end
				if player_config.toggle.throwhurtboxes then
					draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
						apply_opacity(player_config.opacity.throwhurtbox, 0xFF0000)) end
			end
        end
    end
    this.string_buffer = {}
end

local function draw_position_marker(entity, player_config)
    if not player_config.toggle.position then return end
    if not entity.pos or not entity.pos.x or not entity.pos.y then return end
    local x, y = entity.pos.x.v, entity.pos.y.v
    if not x or not y or (x == 0 and y == 0) then return end -- Prevent 0,0,0 midscreen glitch frame
    local vPos = Vector3f.new(x / 6553600.0, y / 6553600.0, 0)
    local screenPos = draw.world_to_screen(vPos)
    if screenPos then draw.filled_circle(screenPos.x, screenPos.y, 10,
		apply_opacity(player_config.opacity.position, 0xFFFFFF), 10)
    end
end

local function process_entity(entity)
    local config = nil
    if entity:get_IsTeam1P() then config = this.config.p1
    elseif entity:get_IsTeam2P() then config = this.config.p2 end
    if not config or not config.toggle.toggle_show then return end
    draw_hitboxes(entity, entity.mpActParam, config); draw_position_marker(entity, config)
end

local function toggle_setter(label, val)
	local changed, new_val = imgui.checkbox(label, val)
	if changed then mark_for_save() end; return changed, new_val
end

local function opacity_setter(label, val, speed, min, max)
	val = math.max(0, math.min(100, val))
	local changed, new_val = imgui.drag_int(label, val, speed or 1.0, min or 0, max or 100)
	if changed then mark_for_save() end; return changed, new_val
end

local function process_hitboxes()
    local sWork, sPlayer = gBattle:get_field("Work"):get_data(nil), gBattle:get_field("Player"):get_data(nil)
    for _, obj in pairs(sWork.Global_work) do
        if obj.mpActParam and not obj:get_IsR0Die() then process_entity(obj) end end
    for _, player in pairs(sPlayer.mcPlayer) do
        if player.mpActParam then process_entity(player, player.mpActParam) end end
end

local function is_disabled_state()
	return not this.config.p1.toggle.toggle_show and not this.config.p2.toggle.toggle_show
end

-- Notifications

local function action_notify(msg, category_toggle)
	if this.config.options.hide_all_alerts then return end
	if category_toggle ~= nil and not this.config.options[category_toggle] then return end
	this.tooltip_msg = msg; this.tooltip_timer = 60
end

local function tooltip_handler()
	if this.tooltip_timer > 0 then this.tooltip_timer = this.tooltip_timer - 1 end
end

local function draw_action_notify()
	if this.tooltip_timer <= 0 then return end  -- Move this check to the TOP
	
	local display = imgui.get_display_size()
	imgui.set_next_window_pos(Vector2f.new(display.x * 0.5, display.y - 60), 1 << 0)
	imgui.set_next_window_size(Vector2f.new(0, 0), 0, 1 << 1)
	
	imgui.begin_window("Notification", true, 1|2|4|8|16|43|64|65536|131072)
	imgui.push_font(imgui.load_font(nil, 30))
	imgui.text(this.tooltip_msg)
	imgui.pop_font()
	imgui.end_window()
end

-- Presets

local function is_preset_loaded(preset_name)
	if not preset_name or preset_name == "" or not this.presets[preset_name] then return false end
	local preset = this.presets[preset_name]
	for _, player in ipairs({"p1", "p2"}) do
		local config_p, preset_p = this.config[player], preset[player]
		for _, category in ipairs({"toggle", "opacity"}) do
			local current_cat, preset_cat = config_p[category], preset_p[category]
			for k, v in pairs(preset_cat) do if current_cat[k] ~= v then return false end end
			for k, _ in pairs(current_cat) do if preset_cat[k] == nil then return false end end
		end
	end; return true
end

local function preset_has_unsaved_changes()
	if this.current_preset_name == "" or not this.presets[this.current_preset_name] then return end
	return not is_preset_loaded(this.current_preset_name)
end

local function get_preset_name()
	local base_name, i = "Preset ", 1
	while true do local candidate = base_name .. i
		if not this.presets[candidate] then return candidate end; i = i + 1; end
end

local function save_current_preset(name)
	if not name or name == "" then return false, "Invalid preset name" end
	if is_preset_loaded(name) then return true, "Data identical, skipping save" end
	
	this.presets[name] = {p1 = deep_copy(this.config.p1), p2 = deep_copy(this.config.p2)}
	rebuild_preset_names()
	this.current_preset_name, this.previous_preset_name = name, ""
	action_notify("Preset Saved: " .. name, "alert_on_save")
	mark_for_save(); return true, "Saved"
end

local function load_preset(name)
	if this.presets[name] then
		local default, preset = create_default_config(), this.presets[name]
		for _, player in ipairs({"p1", "p2"}) do
			local merged_toggle = deep_copy(default[player].toggle)
			if preset[player].toggle then
				for k, v in pairs(preset[player].toggle) do
					merged_toggle[k] = v end
			end
			this.config[player].toggle = merged_toggle
			local merged_opacity = deep_copy(default[player].opacity)
			if preset[player].opacity then
				for k, v in pairs(preset[player].opacity) do
					merged_opacity[k] = v end
			end
			this.config[player].opacity = merged_opacity
		end
		this.current_preset_name, this.previous_preset_name = name, ""
		mark_for_save(); return true
	end; return false, "Preset not found"
end

local function delete_preset(name)
	if not this.presets[name] then return false, "Preset not found" end
	
	local fallback = nil
	if this.current_preset_name == name then
		for _, p_name in ipairs(this.preset_names) do
			if p_name ~= name then
				fallback = p_name
				break
			end
		end
	end

	this.presets[name] = nil
	rebuild_preset_names()
	
	if this.rename_mode == name then this.rename_mode, this.rename_temp_name = false, "" end
	
	if this.current_preset_name == name then
		this.create_new_mode, this.rename_mode = false, false
		if fallback then
			load_preset(fallback)
		else
			reset_all_default()
			this.current_preset_name = get_preset_name()
			save_current_preset(this.current_preset_name)
		end
	end
	
	mark_for_save()
	return true
end

local function rename_preset(old_name, new_name)
	if not old_name or old_name == "" then return false, "No preset selected" end
	if not new_name or new_name == "" then return false, "New name cannot be empty" end
	if new_name == old_name then return false, "New name is the same as the old name" end
	if this.presets[new_name] then return false, "A preset with this name already exists" end
	if this.presets[old_name] then
		this.presets[new_name], this.presets[old_name] = this.presets[old_name], nil
		rebuild_preset_names()
		if this.current_preset_name == old_name then
			this.current_preset_name, this.previous_preset_name = new_name, "" end
		mark_for_save(); return true
	end; return false, "Preset not found"
end

local function get_duplicate_preset_name(name)
	local i = 1
	while true do
		local candidate = name .. "_" .. i
		if not this.presets[candidate] then return candidate end
		i = i + 1
	end
end

local function duplicate_preset(name)
	if not this.presets[name] then return false, "Preset not found" end
	local new_name = get_duplicate_preset_name(name)
	this.presets[new_name] = deep_copy(this.presets[name])
	rebuild_preset_names()
	mark_for_save()
	return true
end

local function update_current_preset_name(new_name)
	if new_name == this.current_preset_name then return end
	if new_name == "" then
		this.current_preset_name = ""
		this.create_new_mode, this.rename_mode = false, false
	elseif this.presets[new_name] then
		this.current_preset_name, this.create_new_mode, this.rename_mode = new_name, false, false
	else
		if this.previous_preset_name == "" then this.previous_preset_name = this.current_preset_name end
		this.create_new_mode, this.new_preset_name, this.rename_mode = true, new_name, false
	end
end

local function start_create_new_mode()
	this.create_new_mode = true
	this.rename_mode = false
	if this.previous_preset_name == "" then this.previous_preset_name = this.current_preset_name end
	this.new_preset_name = get_preset_name()
end

local function start_rename_mode(preset_name)
	this.rename_mode = preset_name
	this.rename_temp_name = preset_name
	this.create_new_mode = false
end

local function cancel_rename_mode()
	this.rename_mode, this.rename_temp_name = false, ""
end

local function switch_preset(preset_name)
	load_preset(preset_name)
	action_notify("Loaded Preset: " .. preset_name, "alert_on_presets")
	this.create_new_mode, this.rename_mode, this.new_preset_name, this.rename_temp_name = false, false, "", ""
end

local function start_delete_confirm(preset_name)
	this.delete_confirm_name = preset_name
end

local function save_rename(old_name)
	if this.rename_temp_name == "" then
	elseif this.rename_temp_name == old_name then
		this.rename_mode, this.rename_temp_name = false, ""
	elseif this.presets[this.rename_temp_name] then
	else
		local success, error_msg = rename_preset(old_name, this.rename_temp_name)
		if success then this.rename_mode, this.rename_temp_name = false, "" end
	end
end

local function save_new_preset()
	if this.new_preset_name == "" then
	elseif this.presets[this.new_preset_name] then
		this.current_preset_name = this.new_preset_name
		this.create_new_mode, this.new_preset_name = false, ""
	else
		local default = create_default_config()
		this.presets[this.new_preset_name] = {p1 = deep_copy(default.p1), p2 = deep_copy(default.p2)}
		rebuild_preset_names()
		this.config.p1 = deep_copy(default.p1)
		this.config.p2 = deep_copy(default.p2)
		local created_name = this.new_preset_name
		this.current_preset_name, this.previous_preset_name = created_name, ""
		this.create_new_mode, this.new_preset_name = false, ""
		action_notify("Preset Created: " .. created_name, "alert_on_presets")
		mark_for_save()
	end
end

local function cancel_new_preset()
	this.create_new_mode, this.new_preset_name = false, ""
	if this.previous_preset_name ~= "" then
		this.current_preset_name, this.previous_preset_name = this.previous_preset_name, "" end
end

local function create_new_blank_preset()
	if this.previous_preset_name == "" then this.previous_preset_name = this.current_preset_name end
	this.new_preset_name = get_preset_name()
	this.should_focus_new = true
end

local function cancel_blank_preset()
	this.create_new_mode, this.new_preset_name = false, ""
	if this.previous_preset_name ~= "" then
		this.current_preset_name, this.previous_preset_name = this.previous_preset_name, ""
	else this.current_preset_name = "" end
end


local function get_current_preset_index()
	for i, name in ipairs(this.preset_names) do
		if name == this.current_preset_name then return i end
	end
	return 1
end

local function load_next_preset()
	if #this.preset_names <= 1 then return end
	local index = get_current_preset_index()
	index = index + 1
	if index > #this.preset_names then index = 1 end
	switch_preset(this.preset_names[index])
end

local function load_previous_preset()
	if #this.preset_names <= 1 then return end
	local index = get_current_preset_index()
	index = index - 1
	if index < 1 then index = #this.preset_names end
	switch_preset(this.preset_names[index])
end

local function format_preset_with_color(preset_name)
	if preset_name == this.current_preset_name then
		local color = 0xFF00FF00 -- Green
		if is_disabled_state() then
			color = 0xFF0000FF -- Red
		elseif preset_has_unsaved_changes() then
			color = 0xFF00FFFF -- Yellow
		end
		imgui.text_colored(preset_name, color)
	else
		imgui.text(preset_name)
	end
end

-- GUI

local function build_menu_columns(widths, flags, names)
	for i, width in ipairs(widths) do
		local label = (names and names[i]) or ""
		imgui.table_setup_column(label, flags or 0, width)
	end
end

local function build_toggle_header(player_int, func)
	if player_int == 2 then col_index = 3 else col_index = 1 end
	imgui.table_set_column_index(col_index)
	if not player_int then return end
	local imgui_text, header_name = string.format("P%.0f", player_int), string.format("##p%.0f_HideAllHeader", player_int)
	imgui.text(imgui_text); imgui.same_line()
	local cursor_pos = imgui.get_cursor_pos()
	imgui.set_cursor_pos(Vector2f.new(cursor_pos.x + 20, cursor_pos.y))
	return toggle_setter(header_name, func)
end

local function build_toggle_headers()
	if not (this.config.p1.toggle.toggle_show or this.config.p2.toggle.toggle_show) then 
		imgui.table_set_column_index(0)
		imgui.text("Show Hidden Elements:")
	end
	local changed
	changed, this.config.p1.toggle.toggle_show = build_toggle_header(1, this.config.p1.toggle.toggle_show)
	changed, this.config.p2.toggle.toggle_show = build_toggle_header(2, this.config.p2.toggle.toggle_show)
end

local function build_toggle_column(player_index, visible_func, toggle_func, opacity_func, config_suffix, opacity_suffix)
    imgui.table_set_column_index(player_index)
    if visible_func then
        local id = string.format("##p%.0f_", player_index) .. config_suffix
        local changed
        changed, toggle_func[config_suffix] = toggle_setter(id, toggle_func[config_suffix])
        if opacity_suffix and opacity_func[opacity_suffix] ~= nil and toggle_func[config_suffix] then
            imgui.same_line(); imgui.push_item_width(70)
            changed, opacity_func[opacity_suffix] = opacity_setter(
                string.format("##p%.0f_", player_index) .. opacity_suffix .. "Opacity",
                opacity_func[opacity_suffix], 0.5, 0, 100
            )
            imgui.pop_item_width()
        end
    end
end

local function build_toggle_columns(label, config_suffix, opacity_suffix)
	imgui.table_set_column_index(0); imgui.text(label)
	build_toggle_column(1, this.config.p1.toggle.toggle_show, this.config.p1.toggle, this.config.p1.opacity, config_suffix, opacity_suffix)
	build_toggle_column(3, this.config.p2.toggle.toggle_show, this.config.p2.toggle, this.config.p2.opacity, config_suffix, opacity_suffix)
end

local function build_toggle_row(label, config_suffix, opacity_suffix)
	imgui.table_next_row(); build_toggle_columns(label, config_suffix, opacity_suffix)
end

local function build_toggle_all_row()
	imgui.table_next_row()
	imgui.table_set_column_index(0); imgui.text("All")
	imgui.table_set_column_index(1)
	if this.config.p1.toggle.toggle_show then
		local all_checked, any_checked = false, false
		for toggle_name, toggle_value in pairs(this.config.p1.toggle) do
			if toggle_name ~= "toggle_show" then
				if toggle_value then any_checked = true end end
		end
		all_checked = any_checked
		local changed
		changed, all_checked = toggle_setter("##p1_ToggleAll", all_checked)
		if changed then
			for toggle_name, _ in pairs(this.config.p1.toggle) do
				if toggle_name ~= "toggle_show" then
					this.config.p1.toggle[toggle_name] = all_checked end
			end
		mark_for_save(); end
		if all_checked then
			imgui.same_line(); imgui.push_item_width(70)
			local current_opacity_slider, all_same, first_opacity = 50, true, nil
			for opacity_name, opacity_value in pairs(this.config.p1.opacity) do
				if first_opacity == nil then first_opacity = opacity_value
				elseif opacity_value ~= first_opacity then all_same = false break end
			end
			if all_same and first_opacity ~= nil then
				current_opacity_slider = first_opacity
			else current_opacity_slider = 50 end
			local changed
			changed, current_opacity_slider = opacity_setter("##p1_GlobalOpacity", current_opacity_slider, 0.5, 0, 100)
			if changed then
				for opacity_name, _ in pairs(this.config.p1.opacity) do
					this.config.p1.opacity[opacity_name] = current_opacity_slider end
			mark_for_save(); end; imgui.pop_item_width()
		end
	end
	imgui.table_set_column_index(3)
	if this.config.p2.toggle.toggle_show then
		local all_checked, any_checked = false, false
		for toggle_name, toggle_value in pairs(this.config.p2.toggle) do
			if toggle_name ~= "toggle_show" then
				if toggle_value then any_checked = true end end
		end
		all_checked = any_checked
		local changed
		changed, all_checked = toggle_setter("##p2_ToggleAll", all_checked)
		if changed then
			for toggle_name, _ in pairs(this.config.p2.toggle) do
				if toggle_name ~= "toggle_show" then
					this.config.p2.toggle[toggle_name] = all_checked end
			end
		mark_for_save(); end
		if all_checked then
			imgui.same_line(); imgui.push_item_width(70)
			local current_opacity_slider = 50
			local all_same = true
			local first_opacity = nil
			for opacity_name, opacity_value in pairs(this.config.p2.opacity) do
				if first_opacity == nil then first_opacity = opacity_value
				elseif opacity_value ~= first_opacity then all_same = false break end
			end
			if all_same and first_opacity ~= nil then
				current_opacity_slider = first_opacity
			else current_opacity_slider = 50 end
			local changed
			changed, current_opacity_slider = opacity_setter("##p2_GlobalOpacity", current_opacity_slider, 0.5, 0, 100)
			if changed then
				for opacity_name, _ in pairs(this.config.p2.opacity) do
					this.config.p2.opacity[opacity_name] = current_opacity_slider
				end
			mark_for_save()
			end
		imgui.pop_item_width()
		end
	end
end

local function build_toggle_rows()
	imgui.indent(6)
	build_toggle_row("Hitbox", "hitboxes", "hitbox")
	build_toggle_row("Hitbox Outline", "hitboxes_outline", "hitbox_outline")
	build_toggle_row("Hurtbox", "hurtboxes", "hurtbox")
	build_toggle_row("Hurtbox Outline", "hurtboxes_outline", "hurtbox_outline")
	build_toggle_row("Pushbox", "pushboxes", "pushbox")
	build_toggle_row("Pushbox Outline", "pushboxes_outline", "pushbox_outline")
	build_toggle_row("Throwbox", "throwboxes", "throwbox")
	build_toggle_row("Throwbox Outline", "throwboxes_outline", "throwbox_outline")
	build_toggle_row("Throw Hurtbox", "throwhurtboxes", "throwhurtbox")
	build_toggle_row("Throw Hurtbox Outline", "throwhurtboxes_outline", "throwhurtbox_outline")
	build_toggle_row("Proximity Box", "proximityboxes", "proximitybox")
	build_toggle_row("Proximity Box Outline", "proximityboxes_outline", "proximitybox_outline")
	build_toggle_row("Proj. Clash Box", "clashboxes", "clashbox")
	build_toggle_row("Proj. Clash Box Outline", "clashboxes_outline", "clashbox_outline")
	build_toggle_row("Unique Box", "uniqueboxes", "uniquebox")
	build_toggle_row("Unique Box Outline", "uniqueboxes_outline", "uniquebox_outline")
	build_toggle_row("Properties", "properties", "properties")
	build_toggle_row("Position", "position", "position")
	build_toggle_all_row()
end

local function build_toggle_menu()
	imgui.set_next_item_open(true, 1 << 3)
	if not imgui.begin_table("ToggleTable", 4) then return end
	
	build_menu_columns({160, 100, 0, 125}, nil, {"", "P1", "P2"})
	imgui.table_next_row()
	build_toggle_headers()
	
	if this.config.p1.toggle.toggle_show or this.config.p2.toggle.toggle_show then
		build_toggle_rows()
	end
	imgui.end_table()
end

local function build_preset_name_column(preset_name)
	imgui.table_set_column_index(0)
	if this.rename_mode == preset_name then
		local changed
		changed, this.rename_temp_name = imgui.input_text("##rename_" .. preset_name, this.rename_temp_name, 32)
	else
		format_preset_with_color(preset_name)
	end
end

local function build_preset_action_column(preset_name)
	imgui.table_set_column_index(1)
	if this.rename_mode == preset_name then
		if imgui.button("Rename##conf_" .. preset_name, {0, 0}) then save_rename(preset_name) end
	elseif is_disabled_state() or preset_name ~= this.current_preset_name then
		if imgui.button("Load##load_" .. preset_name, {0, 0}) then switch_preset(preset_name) end
	end
end

local function build_preset_rename_column(preset_name)
	imgui.table_set_column_index(2)
	if this.rename_mode == preset_name then
		if imgui.button("Cancel##canc_" .. preset_name, {0, 0}) then cancel_rename_mode() end
	else
		if imgui.button("Rename##ren_" .. preset_name, {0, 0}) then start_rename_mode(preset_name) end
	end
end

local function build_preset_duplicate_column(preset_name)
	imgui.table_set_column_index(3)
	if this.rename_mode ~= preset_name then
		if imgui.button("Duplicate##dup_" .. preset_name, {0, 0}) then duplicate_preset(preset_name) end
	end
end

local function build_preset_delete_column(preset_name)
	imgui.table_set_column_index(4)
	if this.rename_mode ~= preset_name then
		if this.delete_confirm_name == preset_name then
			if imgui.button("Delete?##del_" .. preset_name, {0, 0}) then
				delete_preset(preset_name)
				this.delete_confirm_name = false
			elseif imgui.is_mouse_clicked(0) and not imgui.is_item_hovered() then
				this.delete_confirm_name = false
			end
		else
			if imgui.button("Delete##del_" .. preset_name, {0, 0}) then start_delete_confirm(preset_name) end
		end
	end
end

local function build_preset_row(preset_name)
	imgui.table_next_row()
	build_preset_name_column(preset_name)
	build_preset_action_column(preset_name)
	build_preset_rename_column(preset_name)
	build_preset_duplicate_column(preset_name)
	build_preset_delete_column(preset_name)
end

local function build_preset_rows()
	if imgui.begin_table("PresetTable", 5, 64) then
		build_menu_columns({110, 60, 0, 0, 0})
		for _, preset_name in ipairs(this.preset_names) do
			build_preset_row(preset_name)
		end; imgui.end_table()
	end
end

local function build_preset_switcher()
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

local function build_current_preset_status()
	if this.current_preset_name == "" then return end
	imgui.same_line(); imgui.text("Current: ")
	imgui.same_line(); format_preset_with_color(this.current_preset_name)
end

local function build_reload_preset_button()
	if not is_disabled_state() or this.current_preset_name == "" or not this.presets[this.current_preset_name] then return end
	imgui.same_line()
	if imgui.button("Reload##reload_nav") then 
		load_preset(this.current_preset_name)
		action_notify("Reloaded Preset: " .. this.current_preset_name, "alert_on_presets")
	end
	if imgui.is_item_hovered() then imgui.set_tooltip("Reset to saved values") end
end

local function build_save_changes_buttons()
	if is_disabled_state() then return end
	if preset_has_unsaved_changes() then
		imgui.same_line()
		if imgui.button("Save##save_nav") then save_current_preset(this.current_preset_name) end
		if imgui.is_item_hovered() then imgui.set_tooltip("Save Changes (Ctrl + Space)") end
		imgui.same_line()
		if imgui.button("x##disc_nav") then 
			load_preset(this.current_preset_name)
			action_notify("Changes Discarded", "alert_on_presets")
		end
	end
end

local function build_new_preset_button()
	if is_disabled_state() or not preset_has_unsaved_changes() then
		imgui.same_line(); if imgui.button("New##create_new") then start_create_new_mode() end
	end
end

local function build_preset_navigation()
	if this.create_new_mode then return end
	build_preset_switcher()
	build_current_preset_status()
	build_save_changes_buttons()
	build_reload_preset_button()
	build_new_preset_button()
end

local function build_create_preset_name_input()
	local changed
	changed, this.new_preset_name = imgui.input_text("##preset_name", this.new_preset_name)
end

local function build_create_preset_buttons()
	if this.new_preset_name == "" then
		if imgui.button("New##new_blank") then create_new_blank_preset() end
		imgui.same_line(); if imgui.button("Cancel##cancel_blank") then cancel_blank_preset() end
	else
		if imgui.button("Create##save_new") then save_new_preset() end
		imgui.same_line(); if imgui.button("Cancel##cancel_new") then cancel_new_preset() end
	end
end

local function build_preset_creator()
	if not this.create_new_mode then return end
	imgui.same_line(); imgui.text("New:")
	imgui.same_line(); imgui.push_item_width(100)
	build_create_preset_name_input()
	imgui.pop_item_width()
	imgui.same_line()
	build_create_preset_buttons()
end

local function build_preset_display()
	if this.create_new_mode then build_preset_creator() else build_preset_navigation() end
end

local function build_presets_menu()
	imgui.set_next_item_open(true, 1 << 3)
	imgui.unindent(10)
	if not imgui.tree_node("Presets") then
		build_preset_display()
		return
	end

	build_preset_display()
	build_preset_rows()
	imgui.tree_pop()
end

local function build_copy_options_rows()
	imgui.same_line()
	if imgui.button("P1 to P2##p1_to_p2", {nil, 16}) then 
		this.config.p2 = deep_copy(this.config.p1)
	end
	imgui.same_line()
	if imgui.button("P2 to P1##p2_to_p1", {nil, 16}) then 
		this.config.p1 = deep_copy(this.config.p2)
	end
end

local function build_copy_options() -- imgui.set_next_item_open(true, 1 << 3)
	if not imgui.tree_node("Copy") then return end
	build_copy_options_rows()
	imgui.tree_pop()
end

local function build_reset_options_row(col_name, func)
	local handler_str = "P%.0f##%s_p%.0f"
	local handler_p1, handler_p2 = string.format(handler_str, 1, string.lower(col_name), 1), string.format(handler_str, 2, string.lower(col_name), 2)
	local handler_all = string.format("All##%s_all", string.lower(col_name))
	imgui.table_next_row()
	imgui.table_set_column_index(0); imgui.text(col_name)
	imgui.table_set_column_index(1); if imgui.button(handler_p1, {nil, 16}) then func('p1') end
	imgui.table_set_column_index(2); if imgui.button(handler_p2, {nil, 16}) then func('p2') end
	imgui.table_set_column_index(3); if imgui.button(handler_all, {nil, 16}) then func() end
end

local function build_reset_options_rows()
	build_reset_options_row("Toggles", reset_toggle_default)
	build_reset_options_row("Opacity", reset_opacity_default)
	build_reset_options_row("All", reset_all_default)
end

local function build_reset_options() -- imgui.set_next_item_open(true, 1 << 3)
	if not imgui.tree_node("Reset") then return end
	if not imgui.begin_table("ResetTable", 4) then return end
	build_reset_options_rows()
	imgui.end_table()
	imgui.tree_pop()
end

local function build_alerts_options_row(label, config_key)
	local changed
	changed, this.config.options[config_key] = toggle_setter(label .. "##" .. config_key, this.config.options[config_key])
end

local function build_alerts_options_rows()
	build_alerts_options_row("Toggle Overlay", "alert_on_toggle")
	imgui.same_line()
	build_alerts_options_row("Preset Switch", "alert_on_presets")
	imgui.same_line()
	build_alerts_options_row("Save", "alert_on_save")
end

local function build_show_alerts_options_checkbox()
	imgui.same_line()
	if not imgui.checkbox("Hide All##hide_all_alerts", this.config.options.hide_all_alerts) then return end
	this.config.options.hide_all_alerts = not this.config.options.hide_all_alerts
end

local function build_alerts_options() -- imgui.set_next_item_open(true, 1 << 3)
	if not imgui.tree_node("Alerts") then return end
	build_show_alerts_options_checkbox()
	if not this.config.options.hide_all_alerts then
		build_alerts_options_rows()
	end
	imgui.tree_pop()
end

local function build_options_menu() -- imgui.set_next_item_open(true, 1 << 3)
    if not imgui.tree_node("Options") then return end
	imgui.unindent(15)
	build_copy_options(); build_reset_options(); build_alerts_options()
	imgui.tree_pop()
	imgui.indent(15)
end

local function build_menu()
	imgui.begin_window("Hitboxes", true, 64)
	build_toggle_menu(); build_presets_menu(); build_options_menu();
	imgui.end_window()
end

local function build_gui()
	if this.config.options.display_menu then build_menu() end
	if is_pause_menu_closed() and (this.config.p1.toggle.toggle_show or this.config.p2.toggle.toggle_show) then process_hitboxes() end
end

local function initialize()
	load_config()
	if this.current_preset_name == "" then this.current_preset_name = get_preset_name() end
	this.initialized = true
end

-- Hotkeys

local function setup_hotkeys()
	if not this.key_ready and not reframework:is_key_down(KEY_1) and not reframework:is_key_down(KEY_2) and not reframework:is_key_down(KEY_3) and not reframework:is_key_down(KEY_F1) and not reframework:is_key_down(KEY_LEFT) and not reframework:is_key_down(KEY_RIGHT) and not reframework:is_key_down(KEY_SPACE) then this.key_ready = true end
	if this.key_ready and reframework:is_key_down(KEY_F1) then
		this.config.options.display_menu = not this.config.options.display_menu
		this.key_ready = false; mark_for_save() end
	if this.key_ready and reframework:is_key_down(KEY_CTRL) and reframework:is_key_down(KEY_1) then
		this.config.p1.toggle.toggle_show = not this.config.p1.toggle.toggle_show
		action_notify("P1 Hitboxes " .. (this.config.p1.toggle.toggle_show and "Enabled" or "Disabled"), "alert_on_toggle")
		this.key_ready = false; mark_for_save() end
	if this.key_ready and reframework:is_key_down(KEY_CTRL) and reframework:is_key_down(KEY_2) then
		this.config.p2.toggle.toggle_show = not this.config.p2.toggle.toggle_show
		action_notify("P2 Hitboxes " .. (this.config.p2.toggle.toggle_show and "Enabled" or "Disabled"), "alert_on_toggle")
		this.key_ready = false; mark_for_save() end
	if this.key_ready and reframework:is_key_down(KEY_CTRL) and reframework:is_key_down(KEY_3) then
		local any_active = this.config.p1.toggle.toggle_show or this.config.p2.toggle.toggle_show
		this.config.p1.toggle.toggle_show = not any_active
		this.config.p2.toggle.toggle_show = not any_active
		action_notify("All Hitboxes " .. (not any_active and "Enabled" or "Disabled"), "alert_on_toggle")
		this.key_ready = false; mark_for_save() end
	if this.key_ready and reframework:is_key_down(KEY_CTRL) and reframework:is_key_down(KEY_LEFT) then
		load_previous_preset()
		this.key_ready = false end
	if this.key_ready and reframework:is_key_down(KEY_CTRL) and reframework:is_key_down(KEY_RIGHT) then
		load_next_preset()
		this.key_ready = false end
	if this.key_ready and reframework:is_key_down(KEY_CTRL) and reframework:is_key_down(KEY_SPACE) then
		save_current_preset(this.current_preset_name)
		this.key_ready = false end
end

-- Main

if not this.initialized then initialize() end

re.on_draw_ui(function()
	if not imgui.tree_node("Hitbox Viewer") then return end
	local changed
	changed, this.config.options.display_menu = toggle_setter("Display Options Menu (F1)", this.config.options.display_menu)
	imgui.tree_pop()
end)

re.on_frame(function()
	if not gBattle then gBattle = sdk.find_type_definition("gBattle") else
		save_handler(); setup_hotkeys(); build_gui(); tooltip_handler(); draw_action_notify()
	end
end)