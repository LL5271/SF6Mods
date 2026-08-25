local MAX_SLOTS = 6
local NATIVE_SLOTS = 3
local SLOT_TYPE = "app.training.tf_OtherSetting.LocalSnapShot"
local MENU_TYPE = "app.training.TrainingMenuData"
local SAVE_FUNC = 10 -- app.training.TrainingFuncType.SNAPSHOT_SAVE_SLOT
local LOAD_FUNC = 11 -- app.training.TrainingFuncType.SNAPSHOT_LOAD_SLOT

local state = {
    manager = nil,
    other_func = nil,
    game_data = nil,
    storage_array = nil,
    hooks_installed = false,
    cycle_pending = false,
    current_slot = nil,
    cycle_target = nil,
    context_refresh_frames = 0,
    menu_scan_frames = 0,
}

local function try(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function hook_arg_int(args, index)
    if not args then return nil end
    local value = try(function() return sdk.to_int64(args[index]) end)
    return value and tonumber(value) or nil
end


local function get_training_context()
    if state.manager and state.other_func and state.game_data and state.context_refresh_frames > 0 then
        state.context_refresh_frames = state.context_refresh_frames - 1
        return state.manager, state.other_func, state.game_data
    end

    local manager = try(function()
        return sdk.get_managed_singleton("app.training.TrainingManager")
    end)
    if not manager then
        state.context_refresh_frames = 1
        return nil
    end

    local other_func = try(function() return manager:call("get_OtherFunc") end)
    local game_data = other_func and try(function() return other_func:call("get_GData") end)
    if not other_func or not game_data then
        state.context_refresh_frames = 1
        return nil
    end

    if manager ~= state.manager or game_data ~= state.game_data then
        state.storage_array = nil
        state.current_slot = nil
        state.cycle_target = nil
        state.menu_scan_frames = 0
    end
    state.manager = manager
    state.other_func = other_func
    state.game_data = game_data
    state.context_refresh_frames = 30
    return manager, other_func, game_data
end

local function expand_storage(game_data)
    if state.storage_array then return true end

    local current = try(function() return game_data:get_field("LocalStorages") end)
    if not current then return false end

    local size = try(function() return current:get_size() end, 0)
    if size == MAX_SLOTS then
        state.storage_array = current
        return true
    end
    if size ~= NATIVE_SLOTS then return false end

    local expanded = try(function()
        return sdk.create_managed_array(SLOT_TYPE, MAX_SLOTS):add_ref()
    end)
    if not expanded then return false end

    for index = 0, NATIVE_SLOTS - 1 do
        expanded[index] = current[index]
    end

    for index = NATIVE_SLOTS, MAX_SLOTS - 1 do
        local copy = try(function()
            local object = sdk.create_instance(SLOT_TYPE, true)
            object:call(".ctor(System.Boolean)", true)
            object:call("Init()")
            local work = object:get_field("Work")
            if work then work:call("Setup()") end
            return object:add_ref()
        end)
        if not copy then return false end
        pcall(function() copy:set_field("IsSetup", true) end)
        pcall(function() copy:set_field("IsEnable", false) end)
        pcall(function() copy:set_field("IsActive", false) end)
        pcall(function() copy:set_field("Time", 0) end)
        expanded[index] = copy
    end

    local assigned = try(function()
        game_data:set_field("LocalStorages", expanded)
        return true
    end, false)
    if assigned then state.storage_array = expanded end
    return assigned
end

local function patch_menu_node(node, visited)
    if not node or visited[node] then return end
    visited[node] = true

    local func_type = try(function() return tonumber(node:get_field("_FuncType")) end)
    local children = try(function() return node:get_field("_ChildData") end)
    local count = children and try(function() return children:get_size() end, 0) or 0

    if (func_type == SAVE_FUNC or func_type == LOAD_FUNC) and count == NATIVE_SLOTS then
        local expanded = try(function()
            return sdk.create_managed_array(MENU_TYPE, MAX_SLOTS):add_ref()
        end)
        if expanded then
            for index = 0, NATIVE_SLOTS - 1 do expanded[index] = children[index] end
            for index = NATIVE_SLOTS, MAX_SLOTS - 1 do
                local copy = try(function()
                    return children[NATIVE_SLOTS - 1]:MemberwiseClone():add_ref()
                end)
                if copy then
                    pcall(function() copy:set_field("_SlotID", index) end)
                    expanded[index] = copy
                end
            end
            if try(function() return expanded[MAX_SLOTS - 1] ~= nil end, false) then
                pcall(function() node:set_field("_ChildData", expanded) end)
                children = expanded
                count = MAX_SLOTS
            end
        end
    end

    if children and count > 0 then
        for index = 0, count - 1 do
            patch_menu_node(try(function() return children[index] end), visited)
        end
    end
end

local function patch_menu(manager)
    if state.menu_scan_frames > 0 then
        state.menu_scan_frames = state.menu_scan_frames - 1
        return
    end
    state.menu_scan_frames = 60

    local ui_data = try(function() return manager:get_field("_UIData") end)
    local roots = ui_data and try(function() return ui_data:get_field("_MenuData") end)
    if not roots then return end

    local visited = {}
    local count = try(function() return roots:get_size() end, 0)
    for index = 0, count - 1 do
        patch_menu_node(try(function() return roots[index] end), visited)
    end
end

local function process_cycle(manager)
    if state.current_slot ~= nil and not state.cycle_pending then return end
    local tdata = try(function() return manager:get_field("_tData") end)
    local other_setting = tdata and try(function() return tdata:get_field("OtherSetting") end)
    if not other_setting then return end

    local observed = tonumber(try(function()
        return other_setting:get_field("SnapShot_Save_SlotID")
    end))
    if state.current_slot == nil then
        state.current_slot = observed and math.floor(observed) % MAX_SLOTS or 0
    elseif observed and state.last_written_slot ~= nil and observed ~= state.last_written_slot then
        state.current_slot = math.floor(observed) % MAX_SLOTS
    end
    if not state.cycle_pending then return end
    state.cycle_pending = false

    local next_slot = state.cycle_target or ((state.current_slot + 1) % MAX_SLOTS)
    state.cycle_target = nil
    state.current_slot = next_slot
    state.last_written_slot = next_slot

    pcall(function() other_setting:set_field("SnapShot_Save_SlotID", next_slot) end)
    pcall(function() other_setting:set_field("SnapShot_Load_SlotID", next_slot) end)
    pcall(function() other_setting:set_field("Menu_Save_SlotID", next_slot) end)
    pcall(function() other_setting:set_field("Menu_Load_SlotID", next_slot) end)
end

local function install_hooks()
    if state.hooks_installed then return end

    local func_type = sdk.find_type_definition("app.training.tf_OtherSetting.FuncData")
    local get_slot = func_type and try(function()
        return func_type:get_method("SnapShotGetSlot(System.Int32)")
    end)
    local set_save_slot = func_type and try(function()
        return func_type:get_method("SnapShotSetSaveSlot(System.Int32)")
    end)
    local set_load_slot = func_type and try(function()
        return func_type:get_method("SnapShotSetLoadSlot(System.Int32)")
    end)
    local menu_set_save_slot = func_type and try(function()
        return func_type:get_method("MenuSetSaveSlot(System.Int32)")
    end)
    local menu_set_load_slot = func_type and try(function()
        return func_type:get_method("MenuSetLoadSlot(System.Int32)")
    end)
    local shortcut_type = sdk.find_type_definition("app.training.tf_ShortCutSetting")
    local cycle_method = shortcut_type and try(function()
        return shortcut_type:get_method("_UpdateChangeSnapShotSlot()")
    end)

    if not get_slot or not cycle_method then return end

    local ok_get = pcall(function()
        sdk.hook(get_slot,
            function(args)
                local slot = hook_arg_int(args, 3)
                if slot and slot >= NATIVE_SLOTS and slot < MAX_SLOTS then
                    thread.get_hook_storage().six_slot_query = slot
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end,
            function(retval)
                local storage = thread.get_hook_storage()
                local slot = storage.six_slot_query
                storage.six_slot_query = nil
                if slot == nil then return retval end

                local snapshot = state.storage_array and try(function() return state.storage_array[slot] end)
                local enabled = snapshot and try(function() return snapshot:get_field("IsEnable") end, false) == true
                return sdk.to_ptr(enabled)
            end)
    end)

    local ok_cycle = pcall(function()
        sdk.hook(cycle_method,
            function()
                thread.get_hook_storage().six_slot_cycle = true
                return sdk.PreHookResult.SKIP_ORIGINAL
            end,
            function(retval)
                local storage = thread.get_hook_storage()
                if not storage.six_slot_cycle then return retval end
                storage.six_slot_cycle = nil
                local next_slot = ((state.current_slot or 0) + 1) % MAX_SLOTS
                state.current_slot = next_slot
                state.cycle_target = next_slot
                state.cycle_pending = true
                return sdk.to_ptr(sdk.create_managed_string("Change Save Status Slot: (" .. tostring(next_slot + 1) .. ")"))
            end)
    end)

    local function track_slot(args)
        local slot = hook_arg_int(args, 3)
        if slot and slot >= 0 and slot < MAX_SLOTS then
            state.current_slot = math.floor(slot)
            state.last_written_slot = state.current_slot
        end
    end
    local ok_track = true
    for _, method in ipairs({ set_save_slot, set_load_slot, menu_set_save_slot, menu_set_load_slot }) do
        if method then
            local installed = pcall(function() sdk.hook(method, track_slot) end)
            ok_track = ok_track and installed
        end
    end

    state.hooks_installed = ok_get and ok_cycle and ok_track
end

re.on_frame(function()
    install_hooks()
    local manager, _, game_data = get_training_context()
    if not manager then return end
    expand_storage(game_data)
    patch_menu(manager)
    process_cycle(manager)
end)
