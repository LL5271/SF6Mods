-- pause_menu_color.lua
-- Recolors the SF6 Training Mode pause menu from its native purple to a
-- selectable palette.  Runtime-confirmed 2026-08-04 on game 2.301.0 / TDB 71.
--
-- METHOD
--   The pause menu's purple identity is a set of per-element via.gui colors
--   (magenta accent 0xFFB51E8F, maroon base 0xBF3A162D, purple gauges
--   0xFF791CCD / 0xFF601CDD, focused-row strip 0xFF720032, ...) plus two large
--   structural elements: the fullscreen dimmer (e_rect_base, via.gui.Rect,
--   black) and the panel background (e_tex_base, via.gui.Scale9Grid, white --
--   the purple is baked into the texture, so a tint MULTIPLIES it into a dark
--   version of the hue).  A hidden additive layer (e_s9g_add) is enabled to
--   brighten the panel toward the hue.
--
--   Discovery: the pause menu GUI (GameObject "ui11200") is located from the
--   `re.on_pre_gui_draw_element` callback (element -> get_GameObject ->
--   get_Components -> via.gui.GUI -> get_View).  The callback cannot read
--   element colors (get_Color returns nil on its wrapper), so it is used only
--   to find the views.  ALL views of the GUI are walked (SF6 re-instantiates
--   the menu view on a refresh cycle, so both the current and buffered views
--   are recolored) and the cache is rebuilt every 30 frames to stay current.
--
--   Colors: via.Color rgba is 0xAABBGGRR (little-endian BGRA); the remap
--   matches the raw low 24 bits and preserves the source alpha.
--
--   Settings: the palette is selectable from the REFramework menu
--   (Script Generated UI -> "Pause Menu Color"): "Default" keeps the native
--   purple, or pick a preset / a custom accent color with the color picker.
--   Settings persist to reframework/data/pause_menu_color.json (saved on
--   change and on REFramework's own config save).
--
--   PERFORMANCE
--   `on_pre_gui_draw_element` fires for EVERY via.gui element of the whole
--   game, every frame, so the steady-state cost is what matters:
--     * When the training pause menu is closed (TrainingManager._MenuState
--       != 4, read once per frame in on_frame) the callback returns before
--       touching the element: ZERO RE calls per element.  A 10-frame hold
--       keeps recoloring during the close transition.
--     * All reads (get_Color/get_Name/get_Size/get_Child/...) return nil on
--       failure instead of throwing (REFramework's documented behavior), so
--       the per-element calls are bare; the whole discovery body and the
--       apply loop are each wrapped in ONE pcall (named functions, no
--       per-call closures) so the callback can never throw -- ScriptRunner
--       disables a callback after a single error.
--     * The apply loop reuses ONE via.Color ValueType (set_field before each
--       set_Color; the C# setter copies the struct at call time) instead of
--       allocating a ValueType + find_type_definition per element per frame.

local DEFAULT_PRESET = "default" -- used until a config file exists
local CONFIG_PATH = "pause_menu_color.json"
local PRESET_KEYS = { "default", "green", "blue", "red", "cyan", "gold", "custom" }
local PRESET_LABELS = { "Default", "Green", "Blue", "Red", "Cyan", "Gold", "Custom" }

local config = {
    preset = DEFAULT_PRESET,
    custom_accent = 0x00FF00, -- 0xRRGGBB, used when preset == "custom"
}

-- Palette RGB (0xRRGGBB; the A byte is copied from the source color).
local PALETTES = {
    green = { accent = 0x00FF00, accent_dim = 0x00B000, accent_light = 0x80FF80,
              mid = 0x00E060, dark = 0x006400, dark_navy = 0x003800,
              dimmer = 0x007000, panel = 0x00FF00, panel_add = 0x9090FF60 },
    blue  = { accent = 0x00A0FF, accent_dim = 0x0060C0, accent_light = 0x80D0FF,
              mid = 0x0060E0, dark = 0x003060, dark_navy = 0x001840,
              dimmer = 0x004070, panel = 0x0000FF, panel_add = 0x90A0E0FF },
    red   = { accent = 0xFF2020, accent_dim = 0xC01010, accent_light = 0xFF8080,
              mid = 0xD02020, dark = 0x801010, dark_navy = 0x500808,
              dimmer = 0x701010, panel = 0xFF0000, panel_add = 0x90FF6060 },
    cyan  = { accent = 0x00FFFF, accent_dim = 0x00B8B8, accent_light = 0x80FFFF,
              mid = 0x00D0D0, dark = 0x006060, dark_navy = 0x003838,
              dimmer = 0x005050, panel = 0x00FFFF, panel_add = 0x90C0FFFF },
    gold  = { accent = 0xFFC800, accent_dim = 0xC09000, accent_light = 0xFFE880,
              mid = 0xD8A800, dark = 0x806000, dark_navy = 0x483800,
              dimmer = 0x705000, panel = 0xFFC800, panel_add = 0x90FFE080 },
}

-- ---- custom palette derivation --------------------------------------
-- All values are 0xRRGGBB (the alpha byte is applied separately where the
-- palette slot carries one, e.g. panel_add).

local function clamp255(v)
    return v < 0 and 0 or (v > 255 and 255 or v)
end

-- Mix two 0xRRGGBB colors: t = 0 -> a, t = 1 -> b.
local function rgb_mix(a, b, t)
    local ar, ag, ab = (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF
    local br, bg, bb = (b >> 16) & 0xFF, (b >> 8) & 0xFF, b & 0xFF
    local r = clamp255(math.floor(ar + (br - ar) * t + 0.5))
    local g = clamp255(math.floor(ag + (bg - ag) * t + 0.5))
    local bl = clamp255(math.floor(ab + (bb - ab) * t + 0.5))
    return (r << 16) | (g << 8) | bl
end

-- Scale a 0xRRGGBB color by a 0..1 factor.
local function rgb_scale(c, f)
    local r = clamp255(math.floor(((c >> 16) & 0xFF) * f + 0.5))
    local g = clamp255(math.floor(((c >> 8) & 0xFF) * f + 0.5))
    local b = clamp255(math.floor((c & 0xFF) * f + 0.5))
    return (r << 16) | (g << 8) | b
end

-- Derive the full palette from one accent color.  Factors mirror the preset
-- palettes (dimmer/dark ~40-44% of the accent, navy ~22%, lights mix toward
-- white) so every slot keeps a coherent tone.
local function make_custom_palette(accent)
    return {
        accent = accent,
        accent_dim = rgb_scale(accent, 0.70),
        accent_light = rgb_mix(accent, 0xFFFFFF, 0.45),
        mid = rgb_mix(accent, 0xFFFFFF, 0.30),
        dark = rgb_scale(accent, 0.40),
        dark_navy = rgb_scale(accent, 0.22),
        dimmer = rgb_scale(accent, 0.44),
        panel = accent,
        panel_add = (0x90 << 24) | rgb_mix(accent, 0xFFFFFF, 0.20),
    }
end

-- Purple-family raw low-24 (BGRA) -> palette slot.
local FAMILY = {
    [0xB51E8F] = "accent",       -- magenta accent: tab borders, category text, slashes, glow
    [0x3A162D] = "dark",         -- maroon: tab base
    [0x791CCD] = "mid",          -- purple: selection/gauge rects
    [0x601CDD] = "mid",          -- purple: selection/gauge rects
    [0x914466] = "accent_dim",   -- pink line
    [0x191952] = "dark_navy",    -- navy purple: shadows, small base textures
    [0xFF55A1] = "accent",       -- pink: slot base
    [0xFF0078] = "accent",       -- hot pink: glow, pagination dot
    [0xFF77DD] = "accent_light", -- light pink: character text
    [0x3F009F] = "dark",         -- deep purple: s9g base
    [0x1E0D36] = "dark",         -- dark purple: rect base
    [0x7E06CE] = "mid",          -- purple: tex base
    [0x000071] = "dark",         -- dark blue-purple: tex effect
    [0x7A06E0] = "mid",          -- purple: s9g glow
    [0x9900FF] = "mid",          -- purple: number glow
    [0x0700AA] = "dark",         -- dark blue-purple: pattern
    [0x501EB5] = "mid",          -- purple: circle base
    [0xDFC4FF] = "accent_light", -- light purple: score text
    [0x720032] = "dark",         -- dark blue-purple: focused-row background strip (e_tex_sub)
    [0x39001A] = "dark_navy",    -- very dark purple: shadow strips
}

local target = PALETTES[DEFAULT_PRESET]

-- Resolve the active palette from the current config.
-- Returns nil for the "default" preset: the native purple is left untouched.
local function resolve_target()
    if config.preset == "default" then return nil end
    if config.preset == "custom" then
        return make_custom_palette(config.custom_accent)
    end
    return PALETTES[config.preset] or PALETTES[DEFAULT_PRESET]
end

local cached = {}     -- list of {el = <walk wrapper>, tgt = rgba, orig = rgba}
local original = {}   -- addr_str -> first-seen (native) color, for restoring "default"
local views = {}      -- addr_str -> view wrapper
local menu_drawn = false
local frame = 0
local last_build = -999

-- Menu-open latch: probe/discover/apply only while the training pause menu is
-- (recently) open, so the per-element draw callback costs nothing otherwise.
local tm = nil
local open_hold = 0
local menu_open = false
local OPEN_HOLD = 10

-- Reused via.Color ValueType for the apply loop (the setter copies the struct
-- at call time, so one instance is safe to mutate before every call).
local via_color_t = sdk.find_type_definition("via.Color")
local color_vt = ValueType.new(via_color_t)

local function apply_one(el, vt)
    return el:call("set_Color", vt)
end

-- One TrainingManager field read per frame; refresh the singleton if it went
-- stale (scene reload) or the read fails.
local function read_menu_state()
    if not tm then tm = sdk.get_managed_singleton("app.training.TrainingManager") end
    local ms = tm and tm:get_field("_MenuState")
    if type(ms) ~= "number" then
        tm = sdk.get_managed_singleton("app.training.TrainingManager")
        ms = tm and tm:get_field("_MenuState")
    end
    return ms
end

-- Tree walk: collect every purple-family element from one view.
-- Each entry keeps the native color (orig) so "default"/disabled can restore
-- it, plus the recolor target when a palette is active.  Reads return nil on
-- failure (no throws); the caller wraps the whole walk in one pcall.
local function collect_view(view)
    local function walk(el)
        if not el then return end
        local col = el:call("get_Color")
        local rgba = nil
        if col then rgba = col:get_field("rgba") end
        local name = el:call("get_Name")
        local sz = el:call("get_Size")
        local w, h
        if sz then
            w = sz:get_field("w")
            h = sz:get_field("h")
        end
        local structural = rgba and (
            (name == "e_tex_base" and type(w) == "number" and w >= 1700 and h >= 900) or -- panel
            (name == "e_rect_base" and type(w) == "number" and w >= 1900 and h >= 1000) or -- dimmer
            (name == "e_mask" and type(w) == "number" and w >= 1400 and h >= 600) or       -- mask
            (name == "e_s9g_add"))                                            -- brightener
        local slot = rgba and FAMILY[rgba & 0xFFFFFF]
        local addr = string.match(tostring(el), "%x+$")
        local prev = addr and original[addr]
        local is_purple_now = rgba and (slot ~= nil or structural)

        if is_purple_now then
            -- keep the native (purple) value for restore: the flow rewrites
            -- elements back to purple, which is the value we want to restore.
            original[addr] = rgba
        end

        -- Match against the RECORDED original color, not the current one:
        -- elements the flow never rewrote stay in the cache (as recolored),
        -- so switching to "default" can restore them too.
        if (prev or is_purple_now) and (prev or rgba) then
            local base = prev or rgba
            local tgt = nil
            if target then
                local s = FAMILY[base & 0xFFFFFF]
                if s then
                    tgt = (base & 0xFF000000) | (target[s] or target.accent)
                elseif structural then
                    if name == "e_tex_base" and type(w) == "number" and w >= 1700 and h >= 900 then
                        tgt = (base & 0xFF000000) | target.panel
                    elseif name == "e_rect_base" and type(w) == "number" and w >= 1900 and h >= 1000 then
                        tgt = (base & 0xFF000000) | target.dimmer
                    elseif name == "e_mask" and type(w) == "number" and w >= 1400 and h >= 600 then
                        tgt = (base & 0xFF000000) | target.dark
                    elseif name == "e_s9g_add" then
                        tgt = target.panel_add
                        el:call("set_Visible", true)
                    end
                end
            end
            cached[#cached + 1] = { el = el, tgt = tgt, orig = base }
        end
        walk(el:call("get_Child"))
        walk(el:call("get_Next"))
    end
    walk(view)
end

local function count_table(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Rebuild the cache from every known view.
local function rebuild()
    cached = {}
    for _, v in pairs(views) do
        collect_view(v)
    end
    log.info("pause_menu_color: cache rebuilt: " .. #cached .. " elements across " .. count_table(views) .. " views")
end

-- Discovery: register every ui11200 view; rebuild at most every 30 frames.
-- Runs only while the pause menu is open; wrapped in one pcall by the
-- callback so it can never throw (ScriptRunner disables a callback after a
-- single error).
local function discover_element(element)
    local go = element:call("get_GameObject")
    if not go then return end
    if go:call("get_Name") ~= "ui11200" then return end
    menu_drawn = true
    if frame - last_build < 30 then return end
    local comps = go:call("get_Components")
    -- SystemArray exposes get_Length; get_count is NOT callable on it (throws
    -- "method 'get_count' is not callable"), so call get_Length directly.
    local len = comps and comps:get_Length()
    if type(len) ~= "number" then return end
    local found = false
    for i = 0, len - 1 do
        local c = comps:get_Item(i)
        if not c then break end
        local ct = c:get_type_definition()
        if ct and ct:get_full_name() == "via.gui.GUI" then
            local v = c:call("get_View")
            if v then
                views[tostring(v)] = v
                found = true
            end
            break
        end
    end
    if found then
        last_build = frame
        pcall(rebuild)
    end
end

local discovery_error_logged = false
re.on_pre_gui_draw_element(function(element)
    if not menu_open then return true end
    local ok, err = pcall(discover_element, element)
    if not ok and not discovery_error_logged then
        discovery_error_logged = true
        log.info("pause_menu_color: discovery error: " .. tostring(err))
    end
    return true
end)

-- Apply the cached overrides every frame while the pause menu draws.
-- Recolor when a palette is active (any preset except "default"); the
-- "default" preset restores the native purple.
re.on_frame(function()
    frame = frame + 1
    local ok, ms = pcall(read_menu_state)
    if ok and ms == 4 then
        open_hold = OPEN_HOLD
    elseif open_hold > 0 then
        open_hold = open_hold - 1
    end
    menu_open = open_hold > 0
    if not menu_drawn or #cached == 0 then return end
    local recolor = target ~= nil
    for i = 1, #cached do
        local c = cached[i]
        color_vt:set_field("rgba", recolor and c.tgt or c.orig)
        pcall(apply_one, c.el, color_vt)
    end
    menu_drawn = false
end)

-- ---- config persistence ---------------------------------------------
local function load_config()
    local loaded = json.load_file(CONFIG_PATH)
    if type(loaded) ~= "table" then return end
    if type(loaded.preset) == "string" then
        for _, name in ipairs(PRESET_KEYS) do
            if loaded.preset == name then
                config.preset = name
                break
            end
        end
    end
    if type(loaded.custom_accent) == "number" then
        config.custom_accent = loaded.custom_accent & 0xFFFFFF
    end
end

local function save_config()
    json.dump_file(CONFIG_PATH, config)
end

-- Apply a UI-driven config change: update the palette and force the
-- next discovery pass to rebuild the cache with the new colors.
local function apply_config_change()
    target = resolve_target()
    last_build = -999
end

-- ---- settings menu ---------------------------------------------------
local function preset_index()
    for i, name in ipairs(PRESET_KEYS) do
        if name == config.preset then return i - 1 end
    end
    return 0
end

re.on_draw_ui(function()
    if imgui.tree_node("Pause Menu Color##pmc") then
        imgui.set_next_item_width(120)
        local idx = preset_index()
        local changed = false
        changed, idx = imgui.combo("Palette##pmc_preset", idx, PRESET_LABELS)
        if changed then
            config.preset = PRESET_KEYS[idx + 1] or DEFAULT_PRESET
            apply_config_change()
            save_config()
        end

        if config.preset == "custom" then
            local accent_v3 = Vector3f.new(
                ((config.custom_accent >> 16) & 0xFF) / 255,
                ((config.custom_accent >> 8) & 0xFF) / 255,
                (config.custom_accent & 0xFF) / 255)
            local picked_changed, picked = imgui.color_picker3("Accent Color##pmc_accent", accent_v3)
            if picked_changed and picked then
                local okr, pr = pcall(function() return picked.x end)
                local okg, pg = pcall(function() return picked.y end)
                local okb, pb = pcall(function() return picked.z end)
                if okr and okg and okb then
                    config.custom_accent =
                        (clamp255(math.floor(pr * 255 + 0.5)) << 16)
                        | (clamp255(math.floor(pg * 255 + 0.5)) << 8)
                        | clamp255(math.floor(pb * 255 + 0.5))
                    apply_config_change()
                    save_config()
                end
            end
            imgui.text("Derives the full menu palette from this accent.")
        end

		imgui.same_line()
        if imgui.button("Reset##pmc_reset") then
            config.preset = DEFAULT_PRESET
            config.custom_accent = 0x00FF00
            apply_config_change()
            save_config()
        end

        imgui.tree_pop()
    end
end)

re.on_config_save(save_config)

load_config()
apply_config_change()

log.info("pause_menu_color.lua loaded: preset=" .. config.preset)