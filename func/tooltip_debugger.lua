local imgui = imgui

local function tooltip_debugger(t)
    imgui.begin_tooltip()
    imgui.set_tooltip(t)
    imgui.end_tooltip()
end

return tooltip_debugger