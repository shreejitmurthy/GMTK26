-- Subtle living-decay atmosphere for the infested courtyard.
-- Drawn in world space after the map; light screen grade after camera detach.
-- Must not obscure the top-center countdown HUD.

local atmosphere = {}

local TILE = 16
local FOUNTAIN_CX = 14.5 * TILE
local FOUNTAIN_CY = 11.5 * TILE

local ash = {}
local t = 0

local function seedAsh(count)
    ash = {}
    for i = 1, count do
        ash[i] = {
            x = love.math.random() * 30 * TILE,
            y = love.math.random() * 24 * TILE,
            vx = (love.math.random() - 0.5) * 8,
            vy = 6 + love.math.random() * 10,
            size = 0.6 + love.math.random() * 1.2,
            a = 0.12 + love.math.random() * 0.18,
        }
    end
end

function atmosphere.load()
    seedAsh(28)
    t = 0
end

function atmosphere.update(dt)
    t = t + dt
    local w, h = 30 * TILE, 24 * TILE
    for _, p in ipairs(ash) do
        p.x = p.x + p.vx * dt + math.sin(t * 0.7 + p.y * 0.05) * 4 * dt
        p.y = p.y + p.vy * dt
        if p.y > h + 4 then
            p.y = -4
            p.x = love.math.random() * w
        end
        if p.x < -4 then
            p.x = w + 4
        elseif p.x > w + 4 then
            p.x = -4
        end
    end
end

--- World-space: fountain pulse + torch flicker + drifting ash.
function atmosphere.drawWorld()
    -- Soft plague-well pulse (sick green, very low alpha — fountain stays readable).
    local pulse = 0.04 + 0.03 * (0.5 + 0.5 * math.sin(t * 1.4))
    love.graphics.setColor(0.35, 0.55, 0.28, pulse)
    love.graphics.circle("fill", FOUNTAIN_CX, FOUNTAIN_CY, 36 + 4 * math.sin(t * 1.1))

    -- Torch flicker accents (Watch Yard / sparse market lights).
    local torches = {
        { 22.5 * TILE, 4.5 * TILE },
        { 27.5 * TILE, 4.5 * TILE },
        { 26.5 * TILE, 10.5 * TILE },
        { 22.5 * TILE, 18.5 * TILE },
    }
    for i, pos in ipairs(torches) do
        local flick = 0.08 + 0.06 * (0.5 + 0.5 * math.sin(t * 9 + i * 2.1))
        love.graphics.setColor(1.0, 0.55, 0.2, flick)
        love.graphics.circle("fill", pos[1], pos[2], 10 + 2 * math.sin(t * 11 + i))
    end

    -- Sparse ash / soot motes.
    for _, p in ipairs(ash) do
        love.graphics.setColor(0.75, 0.72, 0.68, p.a)
        love.graphics.rectangle("fill", p.x, p.y, p.size, p.size)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

--- Screen-space grade after HUD-safe world draw; leave top HUD band alone.
function atmosphere.drawGrade()
    local w, h = love.graphics.getDimensions()
    -- Very light cool desat wash; skip top ~14% so timer stays crisp.
    local top = h * 0.14
    love.graphics.setColor(0.08, 0.1, 0.14, 0.07)
    love.graphics.rectangle("fill", 0, top, w, h - top)
    love.graphics.setColor(1, 1, 1, 1)
end

return atmosphere
