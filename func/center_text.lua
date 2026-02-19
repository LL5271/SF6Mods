local function center_text(text, column_width)
    local text_size = imgui.calc_text_size(text)
    local cursor = imgui.get_cursor_pos()
    return imgui.set_cursor_pos(Vector2f.new(
        cursor.x + (column_width - text_size.x) * 0.5,
        cursor.y
    ))
end
return center_text