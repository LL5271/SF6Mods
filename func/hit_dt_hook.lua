local sdk = sdk

local function setup_hook(type_name, method_name, pre_func, post_func)
    local type_def = sdk.find_type_definition(type_name)
    if type_def then
        local method = type_def:get_method(method_name)
        if method then
            sdk.hook(method, pre_func, post_func)
        end
    end
end

local hit_dt = {}
local function hook_hit_dt()
    setup_hook('nBattle.cPlayer', 'setDamageInfo', function(args)
        table.insert(hit_dt, sdk.to_managed_object(args[3]))
        table.insert(hit_dt, sdk.to_managed_object(args[4]))
        return args
    end)
    return hit_dt
end

return hook_hit_dt