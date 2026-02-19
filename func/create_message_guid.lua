-- Actually a stinky hack just hooks hMsg.GetMessage and override returns
-- Returns a new guid for a given message string

local my = {}
my.guid_overrides = {}

function my.create_message_guid(str)
    local newGuid = sdk.find_type_definition("System.Guid"):get_field("Empty"):get_data(nil):NewGuid()
    for k, v in pairs(my.guid_overrides) do
        if v == str then
            newGuid:call(".ctor(System.String)", k)
            return newGuid
        end
    end
    my.guid_overrides[newGuid:call("ToString()")] = str
    return newGuid
end

sdk.hook(sdk.find_type_definition("app.helper.hMsg"):get_method("GetMessage(System.Guid)"), function(args)
    local message = my.guid_overrides[sdk.to_valuetype(args[2], "System.Guid"):call("ToString()")]
    if message then
        if type(message) == "function" then
            thread.get_hook_storage()[1] = message()
        else
            thread.get_hook_storage()[1] = message
        end
        return sdk.PreHookResult.SKIP_ORIGINAL
    end
end, function(retval)
    if thread.get_hook_storage()[1] then
        return sdk.to_ptr(sdk.create_managed_string(thread.get_hook_storage()[1]))
    end
    return retval
end)

return my.create_message_guid