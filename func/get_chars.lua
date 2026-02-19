-- local get_chars = require("func/get_chars")
-- local chars = get_chars()
-- chars.p1.id, chars.p1.name
-- chars.p2.id, chars.p2.name

local ids = {}

local names = {
    [-1] = "None",
    [1]  = "Ryu",       [2]  = "Luke",      [3]  = "Kimberly",
    [4]  = "Chun-Li",   [5]  = "Manon",     [6]  = "Zangief",
    [7]  = "JP",        [8]  = "Dhalsim",   [9]  = "Cammy",
    [10] = "Ken",       [11] = "Dee Jay",   [12] = "Lily",
    [13] = "A.K.I",     [14] = "Rashid",    [15] = "Blanka",
    [16] = "Juri",      [17] = "Marisa",    [18] = "Guile",
    [19] = "Ed",        [20] = "E. Honda",  [21] = "Jamie",
    [22] = "Akuma",     [23] = "M. Bison",  [24] = "Terry",
    [25] = "Sagat",     [28] = "Mai",       [29] = "Elena",
    [30] = "C. Viper",  [150] = "Tong",     [250] = "Avatar",
}

sdk.hook(
    sdk.find_type_definition("app.FBattleMediator"):get_method('UpdateGameInfo'),
    function(args)
        local mediator = sdk.to_managed_object(args[2])
        local arr = mediator and mediator:get_field("PlayerType")
        if not arr then return end

        local p1, p2 = arr:call("GetValue", 0), arr:call("GetValue", 1)
        ids[0] = (p1 and p1:get_field("value__")) or -1
        ids[1] = (p2 and p2:get_field("value__")) or -1
    end,
    function(retval) end
)

local function deep_copy(original)
    if type(original) ~= 'table' then return original end
    local copy = {}
    for key, value in pairs(original) do
        copy[key] = deep_copy(value)
    end
    return copy
end

local function process_ids(ids)
    local _ids = deep_copy(ids)
    return {
        p1 = { id = _ids[0], name = names[_ids[0]] },
        p2 = { id = _ids[1], name = names[_ids[1]] },
    }
end

return process_ids(ids)