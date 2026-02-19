local gBattle, Config

local function get_game_mode()
    gBattle = sdk.find_type_definition("gBattle")
    Config = gBattle and gBattle:get_field("Config")
    if not Config then return end

    local data = Config:get_data()
    return data._GameMode
end

return get_game_mode