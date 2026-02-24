-- Config file handler with nested table support and delayed save
-- Usage: local Config, settings = config(path, settings, init_load)
--   path: path to config file - default is (script_name).json
--   settings: table of settings
--   init_load: load settings on init, default true
--
-- Save behavior:
--   Changes are automatically marked for save with a 0.5 second delay
--   Multiple changes within the delay period are batched into a single save
--   Saves are automatically flushed on script reset and config save events
--
-- Methods:
--   Config.add(key, val, table_name) - Add single setting (top level table default)
--   Config.add(table, table_name) - Add multiple settings
--   Config.remove(key, table_name) - Remove single setting
--   Config.remove(table, table_name) - Remove multiple settings
--   Config.save() - Mark config for delayed save (0.5s)
--   Config.save_now() - Force immediate save, bypassing delay
--   Config.load_all() - Load all settings from file
--   Config.load(key, table_name) - Load single setting from file
--   Config.get_table(table_name) - Get reference to nested table
--
-- Example:
--   local Config, settings = require("config")("my_mod.json", {foo = "bar"})
--   Config.add("new_key", "value")  -- Marks for save with 0.5s delay
--   Config.save_now()                 -- Saves immediately

local SAVE_DELAY = 0.5
local json, fs, re = json, fs, re

local function get_default_path()
    local traceback = debug.traceback(nil, 3)
    local filename = traceback:match("([^\\/:]+)%.lua")
    return filename and filename .. ".json" or "config.json"
end

local function file_exists(path)
    if not path then return false end
    local f = io.open(path, "r")
    if f then io.close(f) return true end
    return false
end

local function is_empty(t) return not t or next(t) == nil end

local function config(path, settings, init_load)
    local self = {
        path = path or get_default_path(),
        settings = settings or {},
        save_pending = false,
        save_timer = 0,
        changed_keys = {},
    }

    function self.save_now()
        if not self.path or is_empty(self.settings) then return false end
        
        local result = json.dump_file(self.path, self.settings)
        if result then 
            self.save_pending = false
            self.changed_keys = {}
        end
        return result
    end

    function self.save()
        self.save_pending = true
        self.save_timer = SAVE_DELAY
        return true
    end

    function self.save_handler()
        if self.save_pending then
            self.save_timer = self.save_timer - (1.0 / 60.0)
            if self.save_timer <= 0 then
                self.save_now()
            end
        end
    end

    function self.get_table(table_name)
        if not table_name then return self.settings end
        
        if not self.settings[table_name] then
            self.settings[table_name] = {}
        elseif type(self.settings[table_name]) ~= 'table' then
            self.settings[table_name] = {}
        end
        return self.settings[table_name]
    end

    function self.add_one(k, v, table_name)
        if not (k and v ~= nil) then return false end
        
        local target = table_name and self.settings[table_name] or self.settings
        
        if table_name and not target then
            target = {}
            self.settings[table_name] = target
        end
        
        if target[k] ~= v then
            target[k] = v
            
            local key_identifier = table_name and (table_name .. "." .. k) or k
            self.changed_keys[key_identifier] = true
            
            return true
        end
        return false
    end

    function self.add_many(t, table_name)
        if not t or is_empty(t) then return false end
        local changed = false
        for k, v in pairs(t) do
            if self.add_one(k, v, table_name) then
                changed = true
            end
        end
        return changed
    end

    function self.add(k_or_t, v_or_table, table_name)
        if not k_or_t then return false end
        local changed = false
        local actual_table_name = nil
        
        if type(k_or_t) == 'table' then
            actual_table_name = type(v_or_table) == 'string' and v_or_table or nil
            changed = self.add_many(k_or_t, actual_table_name)
        elseif type(k_or_t) == 'string' and v_or_table ~= nil then
            actual_table_name = type(table_name) == 'string' and table_name or nil
            changed = self.add_one(k_or_t, v_or_table, actual_table_name)
        end
        
        if changed then return self.save() end 
        return changed
    end

    function self.remove_one(k, table_name)
        local target = table_name and self.settings[table_name] or self.settings
        
        if not k or not target or target[k] == nil then return false end
        
        target[k] = nil
        
        local key_identifier = table_name and (table_name .. "." .. k) or k
        self.changed_keys[key_identifier] = true
        
        return true
    end

    function self.remove_many(t, table_name)
        if not t or is_empty(t) then return false end
        local changed = false
        for _, k in ipairs(t) do
            if self.remove_one(k, table_name) then
                changed = true
            end
        end
        return changed
    end

    function self.remove(k_or_t, table_name)
        if not k_or_t then return false end
        
        local changed = false
        local actual_table_name = nil
        
        if type(k_or_t) == 'table' then
            actual_table_name = type(table_name) == 'string' and table_name or nil
            changed = self.remove_many(k_or_t, actual_table_name)
        elseif type(k_or_t) == 'string' then
            actual_table_name = type(table_name) == 'string' and table_name or nil
            changed = self.remove_one(k_or_t, actual_table_name)
        end
        
        if changed then
            return self.save()
        end
        return changed
    end
    
    function self.load_all()
        if not file_exists(self.path) then return false end
        return json.load_file(self.path)
    end

    function self.load(k, table_name)
        if not k or not file_exists(self.path) then return false end
        local loaded = json.load_file(self.path)
        if not loaded then return false end
        
        local source = table_name and loaded[table_name] or loaded
        local target = table_name and (self.settings[table_name] or {}) or self.settings
        
        if source and source[k] ~= target[k] then
            target[k] = source[k]
            return true
        end
        return false
    end

    if init_load ~= false then self.settings = self.load_all() or {} end

    -- Automatically create the config file if it doesn't exist and the path is valid
    if self.path and not file_exists(self.path) then
        self.save_now()
    end

    re.on_script_reset(function() if self.save_pending then self.save_now() end end)
    re.on_config_save(function() if self.save_pending then self.save_now() end end)
    re.on_frame(function() self.save_handler() end)
    
    return self, self.settings
end

return config