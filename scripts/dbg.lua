debug_font = love.graphics.newFont("res/fonts/RobotoMono-VariableFont_wght.ttf")
-- debug_font:setFilter("nearest", "nearest")
local maxWidth = 0
local lineHeight = debug_font:getHeight()
local padding = 5
function addDebugData(components, format, ...)
    local str = string.format(format, ...)
    components[#components+1] = str
end
function drawDebugData(x, y)
    -- required size of the debug box
    for _, str in ipairs(components) do
        local textWidth = debug_font:getWidth(str)
        maxWidth = math.max(maxWidth, textWidth)
    end

    -- background rectangle
    if #components > 0 then
        local boxWidth = maxWidth + padding * 2
        local boxHeight = #components * (lineHeight * love.report[2]) + padding * 2
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", x - padding, y - padding, boxWidth, boxHeight)
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("line", x - padding, y - padding, boxWidth, boxHeight)
        love.graphics.setColor(1, 1, 1, 1)

        for i, str in ipairs(components) do
            love.graphics.print(str, x, y + ((i-1) * lineHeight))
        end
    end
end

love.frame = 0
function profilerReport()
    love.frame = love.frame + 1
    if love.frame % 100 == 0 then
        love.report = love.profiler.report(5)
        love.profiler.reset()
    end
end