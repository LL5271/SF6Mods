-- =============================================================================
-- better_disp_hitboxes_debugger.lua
-- Debug window module for Better Hitbox Viewer.
-- Required by better_disp_hitboxes.lua at runtime.
--
-- If this file cannot be loaded, the main script disables the debug panel
-- toggle (Ctrl+F1 and the options checkbox do nothing) and proceeds normally.
--
-- Usage (from main file):
--   local dbg_mod = require("func/better_disp_hitboxes_debugger")
--   local debugger = dbg_mod.init(ctx)   -- ctx described below
--   debugger.build_debug_window()        -- call each frame inside gui_handler
--   debugger.run_custom_debug(my_fn)     -- register a custom capture function
-- =============================================================================

local M = {}

-- ---------------------------------------------------------------------------
-- Simple JSON serialiser (no external dependency).
-- Handles nil, boolean, number, string, and nested tables.
-- Tables with all-integer consecutive keys are treated as arrays.
-- ---------------------------------------------------------------------------
local function to_json(val, indent, _visited)
    indent   = indent or ""
    _visited = _visited or {}

    local t = type(val)

    if val == nil      then return "null"
    elseif t == "boolean" then return tostring(val)
    elseif t == "number"  then
        if val ~= val then return "null" end          -- NaN
        if val ==  math.huge or val == -math.huge then return "null" end
        return tostring(val)
    elseif t == "string"  then
        -- Escape special characters
        local s = val
            :gsub('\\', '\\\\')
            :gsub('"',  '\\"')
            :gsub('\n', '\\n')
            :gsub('\r', '\\r')
            :gsub('\t', '\\t')
        return '"' .. s .. '"'
    elseif t == "table" then
        if _visited[val] then return '"[circular]"' end
        _visited[val] = true

        -- Detect array vs object
        local n = 0
        local max_n = 0
        for k, _ in pairs(val) do
            n = n + 1
            if type(k) == "number" and k == math.floor(k) and k >= 1 then
                if k > max_n then max_n = k end
            end
        end
        local is_array = (n > 0 and n == max_n)

        local inner_indent = indent .. "  "
        local parts = {}

        if is_array then
            for i = 1, max_n do
                parts[i] = inner_indent .. to_json(val[i], inner_indent, _visited)
            end
            _visited[val] = nil
            if #parts == 0 then return "[]" end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
        else
            local keys = {}
            for k in pairs(val) do keys[#keys+1] = k end
            table.sort(keys, function(a, b)
                return tostring(a) < tostring(b)
            end)
            for _, k in ipairs(keys) do
                local key_str = to_json(tostring(k), inner_indent, _visited)
                local val_str = to_json(val[k],      inner_indent, _visited)
                parts[#parts+1] = inner_indent .. key_str .. ": " .. val_str
            end
            _visited[val] = nil
            if #parts == 0 then return "{}" end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
        end
    else
        -- userdata, function, thread – not serialisable
        return '"[' .. t .. ']"'
    end
end

-- ---------------------------------------------------------------------------
-- Module initialiser.
-- ctx (context) fields the main file must supply:
--
--   ctx.get_state()              → returns the shared `state` table
--   ctx.get_build()              → returns the shared `build` table
--   ctx.get_game_mode_id()       → returns numeric game mode id
--   ctx.GAME_MODES               → the GAME_MODES lookup table
--   ctx.get_gBattle()            → returns gBattle (may be nil)
--   ctx.get_PauseManager()       → returns PauseManager singleton (may be nil)
--   ctx.get_bFlowManager()       → returns bFlowManager singleton (may be nil)
--   ctx.is_facing_right(entity)  → bool
--   ctx.is_in_battle()           → bool
--   ctx.get_menu_nav()           → returns menu_nav table
--   ctx.get_timestop()           → returns timestop_frame, timestop_total_frames
--   ctx.get_frozen_draw_calls()  → returns frozen_draw_calls table
--   ctx.table_count(t)           → counts keys in a table
--   ctx.mark_for_save()          → triggers a config save
-- ---------------------------------------------------------------------------
function M.init(ctx)

    -- Convenience aliases (all read through ctx to stay in sync with the main
    -- file's locals without needing global variables).
    local function S()    return ctx.get_state()  end
    local function B()    return ctx.get_build()   end

    -- ── Custom-debug state ──────────────────────────────────────────────────
    -- Holds the user-registered capture function and its log.
    local custom_debug_fn   = nil      -- set via run_custom_debug(fn)
    local custom_debug_log  = {}       -- { {timestamp, frame, data}, ... }
    local custom_debug_running = false -- whether capture is active
    local custom_debug_max_log = 200   -- maximum retained entries
    local custom_debug_export_name = "custom_debug_log.json"
    local custom_debug_filter = ""     -- simple substring filter for display
    local custom_debug_scroll_to_bottom = false
    local custom_debug_frame_counter = 0

    -- ── Unit-test state ─────────────────────────────────────────────────────
    -- Holds the pasted test source and the results from the last run.
    local unit_test_code        = ""                    -- raw Lua pasted by the user
    local unit_test_results     = {}                    -- { {name, passed, message}, ... }
    local unit_test_summary     = ""                    -- e.g. "3 passed, 1 failed"
    local unit_test_run_count   = 0                     -- increments each run (display IDs)
    local unit_test_export_name = "unit_test_results.json"  -- configurable export filename
    local unit_test_notice      = ""                         -- transient copy/export status (replaced, not appended)

    -- ── Shared helpers (mirrors of main-file locals) ────────────────────────

    local function rect_type_name(rect)
        if not rect then return "nil" end
        if rect:get_field("HitPos") ~= nil then
            if rect.TypeFlag > 0 then
                return "Hitbox"
            elseif (rect.TypeFlag == 0 and rect.PoseBit > 0) or rect.CondFlag == 0x2C0 then
                return "Throwbox"
            elseif rect.GuardBit == 0 then
                return "Clashbox"
            else
                return "Proximity"
            end
        elseif rect:get_field("Attr")    ~= nil then return "Pushbox"
        elseif rect:get_field("HitNo")   ~= nil then
            return rect.TypeFlag > 0 and "Hurtbox" or "Throw Hurtbox"
        elseif rect:get_field("KeyData") ~= nil then return "Unique"
        else return "Unknown"
        end
    end

    local function count_rect_types(actParam)
        local counts = {
            Hitbox=0, Throwbox=0, Clashbox=0, Proximity=0,
            Hurtbox=0, ["Throw Hurtbox"]=0, Pushbox=0, Unique=0, Unknown=0
        }
        local total = 0
        if not (actParam and actParam.Collision and actParam.Collision.Infos) then
            return counts, 0
        end
        for _, rect in pairs(actParam.Collision.Infos._items) do
            total = total + 1
            local t = rect_type_name(rect)
            counts[t] = (counts[t] or 0) + 1
        end
        return counts, total
    end

    local function fmt_pos(entity)
        if entity.pos and entity.pos.x and entity.pos.y then
            return string.format("%.2f", entity.pos.x.v / 65536.0),
                   string.format("%.2f", entity.pos.y.v / 65536.0)
        end
        return "N/A", "N/A"
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Section 1: System State
    -- ────────────────────────────────────────────────────────────────────────
    local function draw_inspector()
        local state = S()
        local build = B()

        if state.debug_force_sys_open then
            imgui.set_next_item_open(true, 1)
            state.debug_force_sys_open = false
        end
        if not build.tree_node_stateful("System State") then return end

        local mode_id   = ctx.get_game_mode_id()
        local mode_name = ctx.GAME_MODES[mode_id] or "UNKNOWN"

        local bfm = ctx.get_bFlowManager()
        local scene_id = "N/A"
        if bfm then
            local ok, v = pcall(bfm.get_GameMode, bfm)
            if ok then scene_id = tostring(v) end
        end

        local pm = ctx.get_PauseManager()
        local pause_bit = pm and pm:get_field("_CurrentPauseTypeBit") or "N/A"

        local chron_elapsed, chron_notch = "N/A", "N/A"
        local gb = ctx.get_gBattle()
        if gb then
            local ok, chron = pcall(function()
                return gb:get_field("Chronos"):get_data(nil)
            end)
            if ok and chron then
                chron_elapsed = tostring(chron.WorldElapsed)
                chron_notch   = tostring(chron.WorldNotch)
            end
        end

        local live_obj_count = 0
        if state.sWork and state.sWork.Global_work then
            for _, obj in pairs(state.sWork.Global_work) do
                if obj.mpActParam and not obj:get_IsR0Die() then
                    live_obj_count = live_obj_count + 1
                end
            end
        end

        local timestop_frame, timestop_total = ctx.get_timestop()
        local fdc = ctx.get_frozen_draw_calls()
        local nav = ctx.get_menu_nav()

        if imgui.begin_table("DebugStateTable", 2) then
            build.setup_columns({180, 220})

            local SEP_KEY = string.rep("─", 20)
            local SEP_VAL = string.rep("─", 22)
            local function row(k, v)
                imgui.table_next_row()
                imgui.table_set_column_index(0); imgui.text(tostring(k))
                imgui.table_set_column_index(1); imgui.text(tostring(v))
            end
            local function sep() row(SEP_KEY, SEP_VAL) end

            row("Preset",           state.current_preset_name)
            row("Sync",             tostring(state.sync_enabled))
            row("Hover Nav",   tostring(nav.active))
            sep()
            row("In Battle",        tostring(ctx.is_in_battle()))
            row("Battle Mode",      mode_id .. "  " .. mode_name)
            row("Scene Mode",       scene_id)
            row("Pause Bit",        tostring(pause_bit))
            sep()
            row("Chronos Elapsed",  chron_elapsed)
            row("Chronos Notch",    chron_notch)
            row("Timestop Frame",   tostring(timestop_frame) .. " / " .. tostring(timestop_total))
            sep()
            row("Frozen Draw Calls", tostring(fdc and #fdc or 0))
            row("Ghost Labels",     tostring(ctx.table_count(state.prop_persist)))
            row("Range Ticks",      tostring(ctx.table_count(state.range_ticks)))
            row("Live Objects",     tostring(live_obj_count))

            imgui.end_table()
        end
        imgui.tree_pop()
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Section 2: Players
    -- ────────────────────────────────────────────────────────────────────────
    local function draw_entities()
        local state = S()
        local build = B()

        if not build.tree_node_stateful("Players") then return end

        if not state.sPlayer or not state.sPlayer.mcPlayer then
            imgui.text_colored("sPlayer not available.", 0xFF0000FF)
            imgui.tree_pop()
            return
        end

        local BOX_ORDER = {
            "Hitbox", "Throwbox", "Clashbox", "Proximity",
            "Hurtbox", "Throw Hurtbox", "Pushbox", "Unique", "Unknown"
        }

        for i, player in pairs(state.sPlayer.mcPlayer) do
            local team  = player:get_IsTeam1P() and "P1"
                       or player:get_IsTeam2P() and "P2" or "?"
            local label = "Player " .. tostring(i) .. "  [" .. team .. "]"

            if imgui.tree_node(label) then
                local px, py  = fmt_pos(player)
                local facing  = ctx.is_facing_right(player) and "Right →" or "← Left"
                local bitval  = player:get_field("BitValue")
                local dead    = (type(player.get_IsR0Die) == "function"
                                 and player:get_IsR0Die()) and "Yes" or "No"

                imgui.text("Ptr:      " .. tostring(player))
                imgui.text("Team:     " .. team)
                imgui.text("Pos:      " .. px .. ",  " .. py)
                imgui.text("Facing:   " .. facing)
                imgui.text("Dead:     " .. dead)
                imgui.text("BitValue: " .. tostring(bitval)
                    .. (type(bitval) == "number"
                        and ("  (0x" .. string.format("%X", bitval) .. ")") or ""))

                imgui.spacing()
                if player.mpActParam then
                    imgui.text_colored("ActParam: loaded", 0xFF80FF80)
                    local counts, total = count_rect_types(player.mpActParam)
                    imgui.text("Total Rects: " .. tostring(total))

                    if total > 0 and imgui.begin_table("RectCounts_p" .. i, 2) then
                        build.setup_columns({180, 40})
                        for _, name in ipairs(BOX_ORDER) do
                            local n = counts[name] or 0
                            if n > 0 then
                                imgui.table_next_row()
                                imgui.table_set_column_index(0); imgui.text("  " .. name)
                                imgui.table_set_column_index(1); imgui.text(tostring(n))
                            end
                        end
                        imgui.end_table()
                    end
                else
                    imgui.text_colored("ActParam: not loaded", 0xFF6060FF)
                end

                imgui.tree_pop()
            end
        end
        imgui.tree_pop()
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Section 3: Global Objects
    -- ────────────────────────────────────────────────────────────────────────
    local function draw_globals()
        local state = S()
        local build = B()

        if not build.tree_node_stateful("Global Objects") then return end

        if not state.sWork or not state.sWork.Global_work then
            imgui.text_colored("sWork not available.", 0xFF0000FF)
            imgui.tree_pop()
            return
        end

        local live = {}
        for _, obj in pairs(state.sWork.Global_work) do
            if obj.mpActParam and not obj:get_IsR0Die() then
                live[#live + 1] = obj
            end
        end

        imgui.text("Live objects with hitboxes: " .. tostring(#live))
        imgui.spacing()

        if #live == 0 then
            imgui.text_colored("(none active)", 0xFFA0A0A0)
            imgui.tree_pop()
            return
        end

        for idx, obj in ipairs(live) do
            local team  = obj:get_IsTeam1P() and "P1"
                       or obj:get_IsTeam2P() and "P2" or "?"
            local label = "Object " .. tostring(idx) .. "  [" .. team .. "]"

            if imgui.tree_node(label) then
                local px, py        = fmt_pos(obj)
                local facing        = ctx.is_facing_right(obj) and "Right →" or "← Left"
                local counts, total = count_rect_types(obj.mpActParam)

                imgui.text("Ptr:    " .. tostring(obj))
                imgui.text("Team:   " .. team)
                imgui.text("Pos:    " .. px .. ",  " .. py)
                imgui.text("Facing: " .. facing)
                imgui.text("Total Rects: " .. tostring(total))

                if total > 0 and imgui.begin_table("RectCounts_g" .. idx, 2) then
                    build.setup_columns({180, 40})
                    for name, n in pairs(counts) do
                        if n > 0 then
                            imgui.table_next_row()
                            imgui.table_set_column_index(0); imgui.text("  " .. name)
                            imgui.table_set_column_index(1); imgui.text(tostring(n))
                        end
                    end
                    imgui.end_table()
                end

                imgui.tree_pop()
            end
        end
        imgui.tree_pop()
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Section 4: Lua Evaluator
    -- ────────────────────────────────────────────────────────────────────────
    local function draw_evaluator()
        local state = S()
        local build = B()

        if not build.tree_node_stateful("Lua Evaluator") then return end

        local changed, new_val = imgui.input_text("##debug_eval_input", state.debug.eval_input)
        if changed then state.debug.eval_input = new_val end

        imgui.same_line()
        if imgui.button("Execute") then
            local func, err = load("return " .. state.debug.eval_input)
            if not func then
                func, err = load(state.debug.eval_input)
            end
            if func then
                local success, result = pcall(func)
                state.debug.eval_output = success
                    and tostring(result)
                    or ("Runtime Error: " .. tostring(result))
            else
                state.debug.eval_output = "Syntax Error: " .. tostring(err)
            end
        end

        imgui.text_colored("Output: " .. state.debug.eval_output, 0xFF00FFFF)
        imgui.tree_pop()
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Section 5: Custom Debug Code
    --
    -- A user-supplied function is called each active frame.  Its return value
    -- is captured and stored in a scrollable, filterable log.  The log can be
    -- copied to the clipboard as JSON or exported to a file.
    --
    -- The function registered via run_custom_debug(fn) may return:
    --   • a string   → stored as-is
    --   • a table    → serialised to JSON
    --   • any other  → tostring'd
    --   • nil        → entry skipped (nothing logged that frame)
    -- ────────────────────────────────────────────────────────────────────────

    -- Build a clean serialisable snapshot of the log for JSON export/copy.
    local function log_to_exportable()
        local out = {}
        for i, entry in ipairs(custom_debug_log) do
            out[i] = {
                index     = i,
                frame     = entry.frame,
                timestamp = entry.timestamp,
                data      = entry.data,
            }
        end
        return out
    end

    -- Append a captured value to the log, trimming oldest if at capacity.
    local function log_append(raw_data)
        local serialised
        local dt = type(raw_data)
        if raw_data == nil then
            return   -- nothing to log
        elseif dt == "table" then
            local ok, s = pcall(to_json, raw_data)
            serialised = ok and s or ("(serialise error) " .. tostring(s))
        elseif dt == "string" then
            serialised = raw_data
        else
            serialised = tostring(raw_data)
        end

        custom_debug_frame_counter = custom_debug_frame_counter + 1
        custom_debug_log[#custom_debug_log + 1] = {
            frame     = custom_debug_frame_counter,
            timestamp = os.date("%H:%M:%S"),
            data      = serialised,
        }

        -- Trim the oldest entry when the log is full.
        if #custom_debug_log > custom_debug_max_log then
            table.remove(custom_debug_log, 1)
        end

        custom_debug_scroll_to_bottom = true
    end

    -- Called every frame (from tick_custom_debug, below) when capture is on.
    local function tick_capture()
        if not custom_debug_running or not custom_debug_fn then return end
        local ok, result = pcall(custom_debug_fn)
        if ok then
            log_append(result)
        else
            log_append("(fn error) " .. tostring(result))
        end
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Unit-test runner
    -- Executes `unit_test_code` in a sandboxed environment that provides a
    -- lightweight xUnit-style API:
    --
    --   test("name", function()           – registers and runs one test case
    --       assert_true(expr)             – fails if expr is falsy
    --       assert_false(expr)            – fails if expr is truthy
    --       assert_eq(a, b)               – fails if a ~= b
    --       assert_ne(a, b)               – fails if a == b
    --       assert_nil(v)                 – fails if v is not nil
    --       assert_not_nil(v)             – fails if v is nil
    --       assert_near(a, b, eps)        – fails if |a-b| > eps  (default 1e-9)
    --       fail(msg)                     – unconditional failure
    --   end)
    --
    -- Any error raised inside a test body (including assertion failures) is
    -- caught and reported as a failure; all other tests continue running.
    -- ────────────────────────────────────────────────────────────────────────
    local function run_unit_tests()
        unit_test_results   = {}
        unit_test_run_count = unit_test_run_count + 1
        unit_test_notice    = ""   -- clear stale copy/export feedback on each new run
        local results = unit_test_results

        -- ── Assertion helpers ──────────────────────────────────────────────
        local function fail(msg)
            error(msg or "explicit fail", 2)
        end
        local function assert_true(v, msg)
            if not v then
                error(msg or ("expected truthy, got " .. tostring(v)), 2)
            end
        end
        local function assert_false(v, msg)
            if v then
                error(msg or ("expected falsy, got " .. tostring(v)), 2)
            end
        end
        local function assert_eq(a, b, msg)
            if a ~= b then
                error(msg or ("expected " .. tostring(a) .. " == " .. tostring(b)), 2)
            end
        end
        local function assert_ne(a, b, msg)
            if a == b then
                error(msg or ("expected " .. tostring(a) .. " ~= " .. tostring(b)), 2)
            end
        end
        local function assert_nil(v, msg)
            if v ~= nil then
                error(msg or ("expected nil, got " .. tostring(v)), 2)
            end
        end
        local function assert_not_nil(v, msg)
            if v == nil then
                error(msg or "expected non-nil value", 2)
            end
        end
        local function assert_near(a, b, eps, msg)
            eps = eps or 1e-9
            if math.abs(a - b) > eps then
                error(msg or string.format("|%s - %s| > %s", tostring(a), tostring(b), tostring(eps)), 2)
            end
        end

        -- ── test() – the primary API exposed to the user's code ────────────
        local function test(name, fn)
            local ok, err = pcall(fn)
            results[#results + 1] = {
                name    = name or ("test #" .. tostring(#results + 1)),
                passed  = ok,
                message = ok and "OK" or tostring(err),
            }
        end

        -- ── Sandbox environment ────────────────────────────────────────────
        -- Provides standard library access plus the test framework.
        -- The user cannot accidentally clobber our locals because we pass the
        -- table as the chunk's _ENV.
        local sandbox_env = setmetatable({
            -- framework
            test          = test,
            fail          = fail,
            assert_true   = assert_true,
            assert_false  = assert_false,
            assert_eq     = assert_eq,
            assert_ne     = assert_ne,
            assert_nil    = assert_nil,
            assert_not_nil = assert_not_nil,
            assert_near   = assert_near,
            -- standard libraries (read-only views via __index)
            math   = math,   string = string, table  = table,
            pairs  = pairs,  ipairs = ipairs, type   = type,
            tostring = tostring, tonumber = tonumber,
            pcall  = pcall,  xpcall = xpcall, error  = error,
            select = select, unpack = table.unpack or unpack,
            print  = function(...) end,  -- silenced; tests use return values
        }, { __index = _G })

        -- ── Load and execute ───────────────────────────────────────────────
        if unit_test_code == "" then
            unit_test_results = {{ name="(none)", passed=false, message="No test code entered." }}
            unit_test_summary = "0 passed, 0 failed — paste some tests first"
            return
        end

        local chunk, load_err = load(unit_test_code, "unit_tests", "t", sandbox_env)
        if not chunk then
            unit_test_results = {{
                name    = "(load error)",
                passed  = false,
                message = tostring(load_err),
            }}
            unit_test_summary = "Syntax error – could not run tests"
            return
        end

        -- Execute the chunk; any top-level (non-test-wrapped) error is caught.
        local ok, exec_err = pcall(chunk)
        if not ok then
            results[#results + 1] = {
                name    = "(runtime error)",
                passed  = false,
                message = tostring(exec_err),
            }
        end

        -- ── Build summary ──────────────────────────────────────────────────
        local passed, failed = 0, 0
        for _, r in ipairs(unit_test_results) do
            if r.passed then passed = passed + 1 else failed = failed + 1 end
        end
        unit_test_summary = string.format(
            "%d passed, %d failed  (%d total)",
            passed, failed, passed + failed
        )
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Section 2: Unit Tests
    -- Top-level debug panel section.  Paste Lua test code into the editor;
    -- results are shown inline and can be copied to a sidecar file or exported
    -- to a named JSON file.
    -- ────────────────────────────────────────────────────────────────────────

    -- Build a clean serialisable snapshot of unit-test results for JSON output.
    local function ut_results_to_exportable()
        local passed, failed = 0, 0
        for _, r in ipairs(unit_test_results) do
            if r.passed then passed = passed + 1 else failed = failed + 1 end
        end
        local rows = {}
        for i, r in ipairs(unit_test_results) do
            rows[i] = {
                index   = i,
                name    = r.name,
                passed  = r.passed,
                message = r.message,
            }
        end
        return {
            summary = unit_test_summary,
            passed  = passed,
            failed  = failed,
            total   = passed + failed,
            results = rows,
        }
    end

    local function draw_unit_tests()
        local build = B()

        if not build.tree_node_stateful("Unit Tests") then return end

        imgui.text_colored(
            "Paste Lua below.  Use  test(\"name\", fn)  with assert_* helpers.",
            0xFFA0C0FF
        )
        imgui.spacing()

        -- ── Code editor (full available width) ────────────────────────────
        -- width = -1 leaves exactly 0px of padding on the right, giving the
        -- widest box the window allows at the current indent level.
        local editor_h = 160
        imgui.push_item_width(0)
        local ch, nv = imgui.input_text_multiline(
            "##ut_code",
            unit_test_code,
            65536,
            Vector2f.new(0, editor_h),
            0
        )
        imgui.pop_item_width()
        if ch then unit_test_code = nv end

        -- ── Run / clear buttons ───────────────────────────────────────────
        imgui.spacing()
        if imgui.button("▶  Run Tests") then
            run_unit_tests()
        end

        imgui.same_line()
        if imgui.button("Clear Results") then
            unit_test_results = {}
            unit_test_summary = ""
            unit_test_notice  = ""
        end

        imgui.same_line()
        if imgui.button("Clear Code") then
            unit_test_code    = ""
            unit_test_results = {}
            unit_test_summary = ""
            unit_test_notice  = ""
        end

        -- ── Copy / export row (shown whenever results exist, pass or fail) ──
        if #unit_test_results > 0 then
            imgui.spacing()

            if imgui.button("Copy Results as JSON") then
                -- REFramework exposes no clipboard API; write a sidecar file
                -- the user can open to copy from.
                local copy_path = "unit_test_results_copy.json"
                local ok, err = pcall(json.dump_file, copy_path, ut_results_to_exportable())
                -- Replace notice each time so repeated clicks don't accumulate text.
                unit_test_notice = ok
                    and ("Copied → " .. copy_path)
                    or  ("Copy error: " .. tostring(err))
            end

            imgui.same_line()
            if imgui.button("Export Results to File") then
                local filename = (unit_test_export_name ~= "")
                    and unit_test_export_name or "unit_test_results.json"
                if not filename:match("%.json$") then filename = filename .. ".json" end
                local ok, err = pcall(json.dump_file, filename, ut_results_to_exportable())
                -- Replace notice each time so repeated clicks don't accumulate text.
                unit_test_notice = ok
                    and ("Exported → " .. filename)
                    or  ("Export error: " .. tostring(err))
            end

            imgui.same_line()
            imgui.push_item_width(0)
            local ech, env = imgui.input_text("##ut_export_name", unit_test_export_name)
            if ech then unit_test_export_name = env end
            imgui.pop_item_width()
            if imgui.is_item_hovered() then
                imgui.set_tooltip("Export filename (JSON)")
            end
        end

        -- ── Summary line ──────────────────────────────────────────────────
        -- Kept clean: only ever contains the pass/fail counts set by run_unit_tests().
        if unit_test_summary ~= "" then
            imgui.spacing()
            -- Colour is derived purely from the count string, never from appended text.
            local c = 0xFF50A0FF   -- blue = some failures
            if unit_test_summary:find("^%d+ passed, 0 failed") then
                c = 0xFF50FF50     -- green = all passed
            elseif not unit_test_summary:find("%d+ passed") then
                c = 0xFFA0A0A0    -- grey = error / no run yet
            end
            imgui.text_colored("Result: " .. unit_test_summary, c)
        end

        -- ── Copy / export notice (separate, replaced on each action) ──────
        if unit_test_notice ~= "" then
            local is_ok = unit_test_notice:find("^Copied") or unit_test_notice:find("^Exported")
            local nc = is_ok and 0xFF80FF80 or 0xFF6080FF
            imgui.text_colored("  " .. unit_test_notice, nc)
        end

        -- ── Per-test result list ──────────────────────────────────────────
        if #unit_test_results > 0 then
            imgui.spacing()
            -- Height grows with test count up to a comfortable cap.
            local row_h    = 18
            local results_h = math.min(#unit_test_results * row_h * 1.6 + 12, 240)
            local child_id  = "##ut_results_" .. tostring(unit_test_run_count)
            imgui.begin_child_window(child_id, Vector2f.new(0, results_h), true, 0)

            for idx, r in ipairs(unit_test_results) do
                if r.passed then
                    imgui.text_colored(
                        string.format("  ✓  [%d]  %s", idx, r.name),
                        0xFF50FF50
                    )
                else
                    imgui.text_colored(
                        string.format("  ✗  [%d]  %s", idx, r.name),
                        0xFF5060FF
                    )
                    if r.message and r.message ~= "OK" then
                        imgui.text_colored(
                            string.format("         → %s", r.message),
                            0xFF8888FF
                        )
                    end
                end
            end

            imgui.end_child_window()
        end

        imgui.tree_pop()
    end

    -- Draw the Custom Debug section inside the debug window.
    local function draw_custom_debug()
        local build = B()

        if not build.tree_node_stateful("Custom Debug") then return end

        -- ── Controls row ─────────────────────────────────────────────────
        local fn_label = custom_debug_fn
            and (custom_debug_running and "■ Stop Capture" or "▶ Start Capture")
            or  "(no function registered)"

        if custom_debug_fn then
            if imgui.button(fn_label) then
                custom_debug_running = not custom_debug_running
                if custom_debug_running then
                    custom_debug_frame_counter = 0
                end
            end

            imgui.same_line()
            if imgui.button("Clear Log") then
                custom_debug_log = {}
                custom_debug_frame_counter = 0
            end

            imgui.same_line()
            if imgui.button("Capture Once") then
                local ok, result = pcall(custom_debug_fn)
                if ok then log_append(result) else log_append("(fn error) " .. tostring(result)) end
            end
        else
            imgui.text_colored(fn_label, 0xFF808080)
        end

        -- ── Export / copy row ─────────────────────────────────────────────
        imgui.spacing()

        if imgui.button("Copy Log as JSON") then
            local ok, s = pcall(to_json, log_to_exportable())
            if ok then
                -- REFramework Lua has no clipboard API; write to a sidecar file
                -- so the user can open it and copy from there.
                local copy_path = "debug_log_copy.json"
                local fok = pcall(json.dump_file, copy_path, log_to_exportable())
                if fok then
                    log_append("(copy) JSON written to " .. copy_path .. "  — open it to copy the contents")
                else
                    log_append("(copy error) could not write " .. copy_path)
                end
            end
        end

        imgui.same_line()
        if imgui.button("Export Log to File") then
            local filename = (custom_debug_export_name ~= "") and custom_debug_export_name
                             or "custom_debug_log.json"
            if not filename:match("%.json$") then filename = filename .. ".json" end
            local ok, err = pcall(json.dump_file, filename, log_to_exportable())
            if not ok then
                -- surface the error in the log itself
                log_append("(export error) " .. tostring(err))
            end
        end

        imgui.same_line()
        imgui.push_item_width(0)
        local ch, nv = imgui.input_text("##dbg_export_name", custom_debug_export_name)
        if ch then custom_debug_export_name = nv end
        imgui.pop_item_width()
        if imgui.is_item_hovered() then
            imgui.set_tooltip("Export filename (JSON)")
        end

        -- ── Filter ────────────────────────────────────────────────────────
        imgui.spacing()
        local fch, fnv = imgui.input_text("Filter##dbg_filter", custom_debug_filter)
        if fch then custom_debug_filter = fnv end

        imgui.same_line()
        imgui.text_colored(
            "Entries: " .. tostring(#custom_debug_log) .. " / " .. tostring(custom_debug_max_log),
            0xFFA0A0A0
        )

        -- ── Log display ───────────────────────────────────────────────────
        imgui.spacing()
        -- Fixed-height child region so the log scrolls independently.
        local child_h = 220
        imgui.begin_child_window("##dbg_log_child", Vector2f.new(0, child_h), true, 0)

        local filter_lower = custom_debug_filter:lower()

        for _, entry in ipairs(custom_debug_log) do
            local line = string.format("[%s | f%d] %s",
                entry.timestamp, entry.frame, entry.data)
            if filter_lower == "" or line:lower():find(filter_lower, 1, true) then
                imgui.text(line)
            end
        end

        -- Auto-scroll only on new entries, not while the user is scrolling up.
        if custom_debug_scroll_to_bottom then
            imgui.set_scroll_here_y(1.0)
            custom_debug_scroll_to_bottom = false
        end

        imgui.end_child_window()

        imgui.tree_pop()
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Public: build_debug_window
    -- Drop-in replacement for the main file's build_debug_window().
    -- ────────────────────────────────────────────────────────────────────────
    local function build_debug_window()
        local state = S()

        if not state.config.options.enable_debug_menu then
            state.debug_panel_was_visible = false
            return
        end

        if not state.debug_panel_was_visible then
            state.debug_force_sys_open = true
        end
        state.debug_panel_was_visible = true

        -- Capture custom data once per frame while the window is open.
        tick_capture()

        imgui.begin_window("Developer Debug  (Ctrl+F1)", true, 64)
        imgui.indent(5)

        draw_inspector()
        draw_unit_tests()
        draw_entities()
        draw_globals()
        draw_evaluator()
        draw_custom_debug()

        imgui.unindent(5)
        imgui.end_window()
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Public: run_custom_debug(fn)
    -- Registers a custom capture function.  The function is called once per
    -- frame while capture is active (or once on "Capture Once" click).
    --
    -- fn may be nil to deregister.
    -- ────────────────────────────────────────────────────────────────────────
    local function run_custom_debug(fn)
        if fn ~= nil and type(fn) ~= "function" then
            error("run_custom_debug expects a function or nil, got " .. type(fn), 2)
        end
        custom_debug_fn      = fn
        custom_debug_running = false   -- always pause when a new fn is loaded
        custom_debug_log     = {}
        custom_debug_frame_counter = 0
    end

    -- Wire the sections into build.debug so the rest of the code that calls
    -- them directly (if any) still works.
    local build = B()
    build.debug                  = build.debug or {}
    build.debug.inspector        = draw_inspector
    build.debug.entities         = draw_entities
    build.debug.globals          = draw_globals
    build.debug.evaluator        = draw_evaluator
    build.debug.custom_debug     = draw_custom_debug
    build.debug.unit_tests       = draw_unit_tests
    build.debug.menu             = function() end  -- legacy stub (no longer used inline)

    -- Initialise the state sub-table if the main file hasn't yet.
    local state = S()
    state.debug = state.debug or { eval_input = "", eval_output = "Ready." }

    return {
        build_debug_window = build_debug_window,
        run_custom_debug   = run_custom_debug,
        run_unit_tests     = run_unit_tests,
        -- Expose the JSON helper so callers can serialise data independently.
        to_json            = to_json,
    }
end

return M