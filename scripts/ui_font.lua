-- True oversized-font rendering with unchanged logical UI dimensions.

local ui_font = {}

ui_font.RASTER_SCALE = 4

local logicalScales = setmetatable({}, { __mode = "k" })

function ui_font.new(path, size, hinting)
    local windowDpiScale = 1
    if love.graphics.getDPIScale then
        windowDpiScale = love.graphics.getDPIScale()
    end

    local rasterSize = math.max(
        1,
        math.floor(size * ui_font.RASTER_SCALE + 0.5)
    )
    local font = love.graphics.newFont(
        path,
        rasterSize,
        hinting or "normal",
        windowDpiScale
    )
    font:setFilter("linear", "linear")
    logicalScales[font] = size / rasterSize
    return font
end

function ui_font.getScale(font)
    return logicalScales[font] or 1
end

function ui_font.getWidth(font, text)
    return font:getWidth(text) * ui_font.getScale(font)
end

function ui_font.getHeight(font)
    return font:getHeight() * ui_font.getScale(font)
end

function ui_font.getAscent(font)
    return font:getAscent() * ui_font.getScale(font)
end

function ui_font.getDescent(font)
    return font:getDescent() * ui_font.getScale(font)
end

function ui_font.getWrap(font, text, limit)
    local scale = ui_font.getScale(font)
    local width, lines = font:getWrap(text, limit / scale)
    return width * scale, lines
end

--- Draw a high-resolution font at its requested logical size.
function ui_font.print(font, text, x, y, rotation, sx, sy, ox, oy, kx, ky)
    local scale = ui_font.getScale(font)
    sx = (sx or 1) * scale
    sy = (sy or (sx / scale)) * scale
    love.graphics.print(
        text,
        font,
        x,
        y,
        rotation or 0,
        sx,
        sy,
        (ox or 0) / scale,
        (oy or 0) / scale,
        kx or 0,
        ky or 0
    )
end

function ui_font.printf(font, text, x, y, limit, align)
    local scale = ui_font.getScale(font)
    love.graphics.printf(
        text,
        font,
        x,
        y,
        limit / scale,
        align or "left",
        0,
        scale,
        scale
    )
end

return ui_font
