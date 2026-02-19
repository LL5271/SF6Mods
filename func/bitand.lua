local function bitand(a, b)
    local result, bitval = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + bitval end
        bitval, a, b = bitval * 2, math.floor(a / 2), math.floor(b / 2)
    end
    return result
end

return bitand