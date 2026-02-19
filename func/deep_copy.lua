local copy = {}

function deep_copy(original)
    if type(original) ~= 'table' then return original end
    for key, value in pairs(original) do copy[key] = deep_copy(value) end
    return copy
end

return deep_copy