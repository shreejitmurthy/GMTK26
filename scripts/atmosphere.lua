-- Living decay for the infested courtyard.
-- Nest-tied motes + sigils; worsens as plague tolerance falls.
-- Must not obscure the top-center countdown HUD.

local nestsMod = require "scripts.nests"

local atmosphere = {}

local TILE = 16
local FOUNTAIN_CX = 14.5 * TILE
local FOUNTAIN_CY = 11.5 * TILE

local particles = {}
local drips = {}
local nestList = {}
local ratio = 1
local t = 0
local sealFlash = 0

local TORCHES = {
    { 22.5 * TILE, 4.5 * TILE },
    { 27.5 * TILE, 4.5 * TILE },
    { 26.5 * TILE, 10.5 * TILE },
    { 22.5 * TILE, 18.5 * TILE },
}

local function nestById(id)
    for _, nest in ipairs(nestList) do
        if nest.id == id then
            return nest
        end
    end
    return nil
end

local function cleansed(id)
    local nest = nestById(id)
    return nest and nest.cleansed
end

local function spawnParticle(kind, x, y)
    local p = {
        kind = kind,
        x = x,
        y = y,
        vx = (love.math.random() - 0.5) * 10,
        vy = 4 + love.math.random() * 12,
        size = 0.6 + love.math.random() * 1.4,
        a = 0.1 + love.math.random() * 0.2,
        life = 2 + love.math.random() * 3,
    }
    if kind == "plague" then
        p.vx = (love.math.random() - 0.5) * 6
        p.vy = -4 - love.math.random() * 8
        p.r, p.g, p.b = 0.4, 0.7, 0.3
    elseif kind == "ash" then
        p.r, p.g, p.b = 0.72, 0.68, 0.62
    elseif kind == "ember" then
        p.vx = (love.math.random() - 0.5) * 4
        p.vy = -6 - love.math.random() * 10
        p.r, p.g, p.b = 1.0, 0.45, 0.18
        p.a = 0.15 + love.math.random() * 0.25
        p.life = 1 + love.math.random() * 1.5
    end
    particles[#particles + 1] = p
end

local function seedAround(kind, cx, cy, radius, count)
    for _ = 1, count do
        local ang = love.math.random() * math.pi * 2
        local rad = love.math.random() * radius
        spawnParticle(kind, cx + math.cos(ang) * rad, cy + math.sin(ang) * rad)
    end
end

function atmosphere.load(nests)
    nestList = nests or {}
    particles = {}
    drips = {}
    t = 0
    ratio = 1
    sealFlash = 0

    local a = nestById("a")
    local b = nestById("b")
    local c = nestById("c")
    if a then
        seedAround("ash", a.x, a.y, a.radius * 0.9, 18)
    end
    if b then
        seedAround("plague", b.x, b.y, b.radius * 0.85, 16)
    end
    if c then
        for _, torch in ipairs(TORCHES) do
            seedAround("ember", torch[1], torch[2], 18, 3)
        end
    end
    -- Light courtyard ash so the yard never feels sterile.
    seedAround("ash", 15 * TILE, 12 * TILE, 140, 12)
end

function atmosphere.setNests(nests)
    nestList = nests or nestList
end

function atmosphere.notifyNestCleansed(nest)
    sealFlash = 0.45
    -- Calm: cull a chunk of that nest's motes.
    local kind = nest.id == "b" and "plague" or (nest.id == "c" and "ember" or "ash")
    local kept = {}
    for _, p in ipairs(particles) do
        local dx, dy = p.x - nest.x, p.y - nest.y
        local near = dx * dx + dy * dy < (nest.radius * 1.2) ^ 2
        if not (near and p.kind == kind and love.math.random() < 0.65) then
            kept[#kept + 1] = p
        end
    end
    particles = kept
end

--- Short ash/dust puff at a world point (collapse cracks / drops).
function atmosphere.burstAt(x, y, kind, count)
    kind = kind or "ash"
    count = count or 4
    for _ = 1, count do
        spawnParticle(
            kind,
            x + (love.math.random() - 0.5) * 10,
            y + (love.math.random() - 0.5) * 10
        )
    end
end

--- ratio: countdown:getRatio(); nests: runtime nest list (for cleansed flags).
function atmosphere.update(dt, plagueRatio, nests)
    t = t + dt
    ratio = plagueRatio or ratio
    if nests then
        nestList = nests
    end
    if sealFlash > 0 then
        sealFlash = math.max(0, sealFlash - dt)
    end

    local urgency = 0
    if ratio < 0.5 then
        urgency = urgency + (0.5 - ratio) * 0.8
    end
    if ratio < 0.25 then
        urgency = urgency + (0.25 - ratio) * 1.2
    end
    if ratio < 0.1 then
        urgency = urgency + (0.1 - ratio) * 2.0
    end

    local aNest = nestById("a")
    local bNest = nestById("b")
    local cNest = nestById("c")

    -- Respawn rates calm after cleanse; climb as tolerance fails.
    local ashRate = (cleansed("a") and 2 or 8) + urgency * 10
    local plagueRate = (cleansed("b") and 1 or 7) + urgency * 4
    local emberRate = (cleansed("c") and 1 or 5) + urgency * 3

    if aNest and love.math.random() < ashRate * dt then
        local ang = love.math.random() * math.pi * 2
        local rad = love.math.random() * aNest.radius
        spawnParticle(
            "ash",
            aNest.x + math.cos(ang) * rad,
            aNest.y + math.sin(ang) * rad
        )
    end
    if bNest and love.math.random() < plagueRate * dt then
        local ang = love.math.random() * math.pi * 2
        local rad = love.math.random() * bNest.radius * 0.8
        spawnParticle(
            "plague",
            bNest.x + math.cos(ang) * rad,
            bNest.y + math.sin(ang) * rad
        )
    end
    if cNest and love.math.random() < emberRate * dt then
        local torch = TORCHES[love.math.random(1, #TORCHES)]
        spawnParticle("ember", torch[1], torch[2])
    end

    -- Fountain drips while Nest B is live.
    if bNest and not bNest.cleansed and love.math.random() < (1.8 + urgency) * dt then
        drips[#drips + 1] = {
            x = FOUNTAIN_CX + (love.math.random() - 0.5) * 20,
            y = FOUNTAIN_CY - 8,
            vy = 20 + love.math.random() * 30,
            life = 0.45 + love.math.random() * 0.25,
            a = 0.35,
        }
    end

    local speedMul = 1 + urgency * 0.5
    for i = #particles, 1, -1 do
        local p = particles[i]
        local calm = 1
        if p.kind == "ash" and cleansed("a") then
            calm = 0.45
        elseif p.kind == "plague" and cleansed("b") then
            calm = 0.35
            p.r, p.g, p.b = 0.45, 0.5, 0.42
        elseif p.kind == "ember" and cleansed("c") then
            calm = 0.4
        end
        p.x = p.x + p.vx * dt * calm * speedMul
            + math.sin(t * 0.7 + p.y * 0.05) * 3 * dt
        p.y = p.y + p.vy * dt * calm * speedMul
        p.life = p.life - dt
        if p.life <= 0 or #particles > 55 then
            table.remove(particles, i)
        end
    end

    for i = #drips, 1, -1 do
        local d = drips[i]
        d.y = d.y + d.vy * dt
        d.life = d.life - dt
        d.a = d.a * 0.98
        if d.life <= 0 then
            table.remove(drips, i)
        end
    end
end

local function drawSigil(nest)
    local col = nestsMod.color(nest.id)
    local baseR = math.min(28, nest.radius * 0.35)
    local prevWidth = love.graphics.getLineWidth()
    love.graphics.setLineWidth(1)
    if nest.cleansed then
        -- Single thin sealed mark — discreet.
        love.graphics.setColor(col[1], col[2], col[3], 0.18)
        love.graphics.circle("line", nest.x, nest.y, baseR)
    else
        local pulse = 0.5 + 0.5 * math.sin(t * 2.2 + nest.id:byte(1))
        local alpha = 0.08 + 0.06 * pulse
        love.graphics.setColor(col[1], col[2], col[3], alpha)
        love.graphics.circle("line", nest.x, nest.y, baseR + pulse)
        -- Thin cleanse arc only while holding E.
        if nest.channeling and nest.progress > 0 then
            love.graphics.setColor(col[1], col[2], col[3], 0.35)
            love.graphics.arc(
                "line",
                "open",
                nest.x,
                nest.y,
                baseR + 3,
                -math.pi / 2,
                -math.pi / 2 + nest.progress * math.pi * 2,
                24
            )
        end
    end
    love.graphics.setLineWidth(prevWidth)
end

--- World-space: discreet sigils + motes. Fountain/torch TILE art stays the hero.
function atmosphere.drawWorld()
    for _, nest in ipairs(nestList) do
        drawSigil(nest)
    end

    -- Tiny soft well hint only — never a green blob over the fountain stamp.
    local bLive = not cleansed("b")
    if bLive then
        local pulse = 0.015 + 0.015 * (0.5 + 0.5 * math.sin(t * 1.4))
        love.graphics.setColor(0.35, 0.55, 0.28, pulse)
        love.graphics.circle("fill", FOUNTAIN_CX, FOUNTAIN_CY, 18 + 2 * math.sin(t * 1.1))
    end

    for _, d in ipairs(drips) do
        love.graphics.setColor(0.4, 0.7, 0.32, d.a * 0.7)
        love.graphics.circle("fill", d.x, d.y, 1.0)
    end

    -- Tiny torch dots; embers carry the “alive” read.
    for i, pos in ipairs(TORCHES) do
        local live = not cleansed("c")
        local flick = (live and 0.08 or 0.03)
            + (live and 0.04 or 0.015) * (0.5 + 0.5 * math.sin(t * 9 + i * 2.1))
        love.graphics.setColor(1.0, 0.55, 0.2, math.min(0.12, flick))
        love.graphics.circle("fill", pos[1], pos[2], 3.5 + 0.8 * math.sin(t * 11 + i))
    end

    for _, p in ipairs(particles) do
        local a = p.a
        if p.kind == "ash" and cleansed("a") then
            a = a * 0.45
        elseif p.kind == "plague" and cleansed("b") then
            a = a * 0.4
        elseif p.kind == "ember" and cleansed("c") then
            a = a * 0.4
        end
        love.graphics.setColor(p.r, p.g, p.b, a)
        love.graphics.rectangle("fill", p.x, p.y, p.size, p.size)
    end

    if sealFlash > 0 then
        love.graphics.setColor(0.9, 0.85, 0.7, sealFlash * 0.12)
        love.graphics.rectangle("fill", 0, 0, 30 * TILE, 24 * TILE)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

--- Screen-space grade; leave top HUD band alone. Soft unless tolerance is failing.
function atmosphere.drawGrade()
    local w, h = love.graphics.getDimensions()
    local top = h * 0.14
    local base = 0.035
    love.graphics.setColor(0.08, 0.1, 0.14, base)
    love.graphics.rectangle("fill", 0, top, w, h - top)

    -- Urgency vignette only when ratio < 0.25.
    if ratio < 0.25 then
        local urgency = (0.25 - ratio) / 0.25
        if ratio < 0.1 then
            urgency = urgency + (0.1 - ratio) * 2.0
        end
        urgency = math.min(1, urgency)
        local bands = 4
        for i = 0, bands - 1 do
            local a = urgency * 0.22 * (1 - i / bands)
            local inset = i * 16
            love.graphics.setColor(0.12, 0.04, 0.05, a)
            love.graphics.rectangle("fill", 0, top + inset, w, 12)
            love.graphics.rectangle("fill", 0, h - 12 - inset, w, 12)
            love.graphics.rectangle("fill", inset, top, 12, h - top)
            love.graphics.rectangle("fill", w - 12 - inset, top, 12, h - top)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return atmosphere
