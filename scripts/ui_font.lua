-- High-density TrueType font loading with unchanged logical UI dimensions.

local ui_font = {}

ui_font.SUPERSAMPLE = 2

function ui_font.new(path, size, hinting)
    local windowDpiScale = 1
    if love.graphics.getDPIScale then
        windowDpiScale = love.graphics.getDPIScale()
    end

    local font = love.graphics.newFont(
        path,
        size,
        hinting or "normal",
        windowDpiScale * ui_font.SUPERSAMPLE
    )
    font:setFilter("linear", "linear")
    return font
end

return ui_font
