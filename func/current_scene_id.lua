-- Int32 current_scene_id()
-- Returns a app.constant.scn.Index.
-- If there is no app.bFlowManager, it returns -1. I believe this only happens during the initial boot process.

local function current_scene_id()
    local bFlowManager = sdk.get_managed_singleton("app.bFlowManager")
    if not bFlowManager then return -1 end
    return sdk.get_managed_singleton("app.bFlowManager"):get_MainFlowID()
end

return current_scene_id