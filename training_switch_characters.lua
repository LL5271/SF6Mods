-- training_switch_characters.lua
-- ImGui menu to switch characters in Training Mode.
-- Workflow:
--   1. ChangeFighter() on FuncData (tf_SelectMenu.FuncList)  -- stages changes
--   2. ApplayCharaSelect() on tf_SelectMenu                   -- commits to PlayerDatas
--   3. RestartGame(true) on FuncData                          -- begins transition
--   4. bApply() on tf_SelectMenu                              -- triggers reload
--
-- Access path:
--   TrainingManager._tfFuncs[1] (Dictionary<UInt32, TrainingFuncBase>)
--     -> app.training.tf_SelectMenu
--       -> .FuncList -> app.training.tf_SelectMenu.FuncData
--

local sdk = sdk
local imgui = imgui
local re = re
local log = log

local CHARACTERS = {
    {1,"Ryu"},{2,"Luke"},{3,"Kimberly"},{4,"Chun-Li"},
    {5,"Manon"},{6,"Zangief"},{7,"JP"},{8,"Dhalsim"},
    {9,"Cammy"},{10,"Ken"},{11,"Dee Jay"},{12,"Lily"},
    {13,"A.K.I"},{14,"Rashid"},{15,"Blanka"},{16,"Juri"},
    {17,"Marisa"},{18,"Guile"},{19,"Ed"},{20,"E. Honda"},
    {21,"Jamie"},{22,"Akuma"},{25,"Sagat"},{26,"M. Bison"},
    {27,"Terry"},{28,"Mai"},{29,"Elena"},{30,"C. Viper"},
    {31,"Alex"},{32,"Ingrid"},{33,"Yasmine"},
	{101,"SiRN Akuma"},{102,"SiRN Bison"},{103,"SiRN Ingrid"}
}

-- Build lookup tables
local char_names = {}
local char_id_by_index = {}
local index_by_id = {}
for i, c in ipairs(CHARACTERS) do
    char_names[i] = c[2]
    char_id_by_index[i] = c[1]
    index_by_id[c[1]] = i
end

-- Script state (overridden by sync on first frame with data)
local state = {
    p1_index = 1,
    p2_index = 2,

}

-- Character name from fighter ID
local function id_to_name(fighter_id)
    local idx = index_by_id[fighter_id]
    if idx then return char_names[idx] end
    return "ID" .. tostring(fighter_id)
end

-- Index from fighter ID
local function id_to_index(fighter_id)
    return index_by_id[fighter_id]
end

-- Read current fighter IDs from TrainingManager._tData.SelectMenu.PlayerDatas
local function get_current_fighter_ids()
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")

	local tdata = tm._tData

    local sel = tdata.SelectMenu

    local pds = sel.PlayerDatas

    local pd0 = pds[0]
    local pd1 = pds[1]
    if not pd0 or not pd1 then return nil end

    return pd0.FighterID, pd1.FighterID
end

-- Track whether user has manually changed a dropdown (stops auto-sync)
local user_interacted = false

-- Reset user_interacted after Apply so dropdowns re-sync on next training load
local function reset_user_interaction()
    user_interacted = false
end

--------------------
-- Execute character switch.
-- Protocol (from confirmed WS API workflow):
--   1. ChangeFighter(playerID, ...) on FuncData   -- stages in GameLocalData
--   2. ApplayCharaSelect() on tf_SelectMenu        -- commits to PlayerDatas
--   3. RestartGame(true) on FuncData               -- begins transition
--   4. bApply() on tf_SelectMenu                   -- triggers reload
--------------------

local function apply_switch()
    -- Resolve TrainingManager
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")

    -- Get _tfFuncs dict
    local tf_funcs = tm._tfFuncs

    -- Get tf_SelectMenu from _tfFuncs
    local tf_select = tf_funcs:call("get_Item(System.UInt32)", 1)

    -- Get FuncData from tf_SelectMenu
    local func_data = tf_select.FuncList

    -- Stage P1 (playerID=0)
	local p1_fid = char_id_by_index[state.p1_index]
    func_data:call("ChangeFighter", 0, p1_fid, 0, 0, 0, 0, false, false) -- (playerID, fighterID, colorID, cosutumeID, inputType, preset, isNegativeEdge, lowStickSensitivity)

    -- Stage P2 (playerID=1)
    local p2_fid = char_id_by_index[state.p2_index]
    func_data:call("ChangeFighter", 1, p2_fid, 0, 0, 0, 0, false, false)

    -- Commit staged changes to PlayerDatas
    tf_select:call("ApplayCharaSelect")

    -- Queue restart via FuncData
    func_data:call("RestartGame", true)

    -- Trigger restart
    tf_select:call("bApply")

    -- Re-sync dropoowns after restart
    reset_user_interaction()

    log.info("[switch_characters] applied P1=" .. p1_fid .. " P2=" .. p2_fid)
end

-- Sync dropdown indices from game state
local function sync_dropdowns()
    if user_interacted then return end
    local p1_id, p2_id = get_current_fighter_ids()
    if p1_id and p2_id then
        local i1 = id_to_index(p1_id)
        local i2 = id_to_index(p2_id)
        if i1 then state.p1_index = i1 end
        if i2 then state.p2_index = i2 end
    end
end

-- Build character dropdowns
local function draw_combo(label, cur_idx)
    if not user_interacted then
        sync_dropdowns()
    end

    local changed, new_index = imgui.combo(label, cur_idx, char_names)
    if changed then
        user_interacted = true
        return new_index
    end
    return cur_idx
end

-- Build ImGui window
re.on_frame(function()
    if not sdk.get_managed_singleton("app.training.TrainingManager") then return end

    local visible = imgui.begin_window("##CharacterSwitch", nil, 1 | 2 | 8 | 64)
    if not visible then imgui.end_window(); return end

    local p1_id, p2_id = get_current_fighter_ids()

    -- P1
    imgui.text("P1")
    imgui.same_line()
    imgui.set_next_item_width(125 - imgui.calc_text_size("P1").x - 4)
    local new_p1 = draw_combo("##p1", state.p1_index)
    if new_p1 ~= state.p1_index then state.p1_index = new_p1 end

    -- P2
    imgui.text("P2")
    imgui.same_line()
    imgui.set_next_item_width(125 - imgui.calc_text_size("P2").x - 4)
    local new_p2 = draw_combo("##p2", state.p2_index)
    if new_p2 ~= state.p2_index then state.p2_index = new_p2 end

    imgui.spacing()

	-- Apply
    if p1_id and p2_id then
        local tw = imgui.calc_text_size("Apply").x
        local cursor = imgui.get_cursor_pos()
        imgui.set_cursor_pos(Vector2f.new((imgui.get_window_size().x - tw) * 0.5 - 8, cursor.y))
        if imgui.button("Apply") then apply_switch() end
        if imgui.is_item_hovered() then
            imgui.begin_tooltip()
            imgui.text("Switches characters and restarts training")
            imgui.end_tooltip()
        end
    end

    imgui.end_window()
end)