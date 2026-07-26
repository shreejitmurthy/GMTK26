-- Living decay for the infested courtyard.
-- District nests + well are sealed plague vials (dark glass + serum).
-- Must not obscure the top-center countdown HUD.

local nestsMod = require "scripts.nests"

local atmosphere = {}

local TILE = 16
local FOUNTAIN_CX = 15 * TILE
local FOUNTAIN_CY = 12 * TILE

local particles = {}
local drips = {}
local nestList = {}
local ratio = 1
local t = 0
local sealFlash = 0
--- Expanding ring snaps on nest seal (drawn under NEST SEALED float).
local sealBursts = {}
--- 0..1 courtyard recovery after all nests sealed (restart must clear).
local cleanseAmount = 0
--- Well infection amp after districts unlock the fountain (0 locked, 1+ unlocked).
local wellIntensity = 0
local wellUnlockFlash = 0

--- Sealed plague vials (DCSS CC0 potions under res/images/nests/).
local vialImages = {}
local VIAL_FOR_NEST = {
    a = "a",
    b = "b",
    c = "c",
    well = "well",
    d = "well",
}
--- Murky serum accent (thin liquid tint / ring / HUD).
local SERUM = {
    a = { 0.35, 0.55, 0.75 },
    b = { 0.55, 0.28, 0.55 },
    c = { 0.28, 0.55, 0.32 },
    well = { 0.3, 0.55, 0.48 },
}
--- Full-screen win flash 0..1 (set by game_flow during cleanse beat).
local winFlash = 0

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
        p.vx = (love.math.random() - 0.5) * 4
        p.vy = -2 - love.math.random() * 5
        p.r, p.g, p.b = 0.35, 0.5, 0.42
        p.a = 0.12 + love.math.random() * 0.14
        p.size = 0.8 + love.math.random() * 1.1
    elseif kind == "ash" then
        p.vx = (love.math.random() - 0.5) * 5
        p.vy = -3 - love.math.random() * 6
        p.r, p.g, p.b = 0.4, 0.5, 0.6
        p.a = 0.1 + love.math.random() * 0.14
        p.size = 0.7 + love.math.random() * 1.1
        p.life = 1.6 + love.math.random() * 2
    elseif kind == "bone" then
        p.vx = (love.math.random() - 0.5) * 4
        p.vy = -2 - love.math.random() * 5
        p.r, p.g, p.b = 0.45, 0.32, 0.45
        p.a = 0.1 + love.math.random() * 0.14
        p.size = 0.7 + love.math.random() * 1.1
        p.life = 1.6 + love.math.random() * 2
    elseif kind == "ember" then
        p.vx = (love.math.random() - 0.5) * 4
        p.vy = -3 - love.math.random() * 6
        p.r, p.g, p.b = 0.32, 0.45, 0.3
        p.a = 0.1 + love.math.random() * 0.14
        p.size = 0.7 + love.math.random() * 1.1
        p.life = 1.4 + love.math.random() * 1.8
    elseif kind == "grass" then
        p.vx = (love.math.random() - 0.5) * 8
        p.vy = -8 - love.math.random() * 14
        p.r, p.g, p.b = 0.45, 0.75, 0.35
        p.a = 0.25 + love.math.random() * 0.3
        p.size = 1.0 + love.math.random() * 1.6
        p.life = 1.2 + love.math.random() * 1.8
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

function atmosphere.setCleanse(amount)
    cleanseAmount = math.max(0, math.min(1, amount or 0))
end

function atmosphere.getCleanse()
    return cleanseAmount
end

local function ensureVials()
    if next(vialImages) then
        return
    end
    local files = {
        a = "res/images/nests/vial_a.png",
        b = "res/images/nests/vial_b.png",
        c = "res/images/nests/vial_c.png",
        well = "res/images/nests/vial_well.png",
        empty = "res/images/nests/vial_empty.png",
    }
    for key, path in pairs(files) do
        local ok, img = pcall(love.graphics.newImage, path)
        if ok and img then
            img:setFilter("nearest", "nearest")
            vialImages[key] = img
        else
            print("[atmosphere] missing vial image: " .. path)
        end
    end
end

function atmosphere.setWinFlash(amount)
    winFlash = math.max(0, math.min(1, amount or 0))
end

function atmosphere.getWinFlash()
    return winFlash
end

function atmosphere.load(nests)
    nestList = nests or {}
    particles = {}
    drips = {}
    sealBursts = {}
    t = 0
    ratio = 1
    sealFlash = 0
    cleanseAmount = 0
    wellIntensity = 0
    wellUnlockFlash = 0
    winFlash = 0
    ensureVials()

    local a = nestById("a")
    local b = nestById("b")
    local c = nestById("c")
    local well = nestById("well") or nestById("d")
    if a then
        seedAround("ash", a.x, a.y, a.radius * 0.55, 8)
    end
    if b then
        seedAround("bone", b.x, b.y, b.radius * 0.55, 7)
    end
    if c then
        seedAround("ember", c.x, c.y, c.radius * 0.55, 7)
    end
    if well then
        seedAround("plague", well.x, well.y, well.radius * 0.7, 8)
    end
end

function atmosphere.setNests(nests)
    nestList = nests or nestList
end

local function moteKindFor(nest)
    if nestsMod.isWell(nest) then
        return "plague"
    elseif nest.id == "b" then
        return "bone"
    elseif nest.id == "c" then
        return "ember"
    end
    return "ash"
end

function atmosphere.notifyNestCleansed(nest)
    sealFlash = 0.55
    local col = nestsMod.color(nest.id)
    local bx, by = nest.x, nest.y
    if nestsMod.isWell(nest) then
        bx, by = FOUNTAIN_CX, FOUNTAIN_CY
    end
    sealBursts[#sealBursts + 1] = {
        x = bx,
        y = by,
        r = col[1],
        g = col[2],
        b = col[3],
        life = 0.55,
        maxLife = 0.55,
        radius = nest.radius,
    }
    local kind = moteKindFor(nest)
    local kept = {}
    for _, p in ipairs(particles) do
        local dx, dy = p.x - bx, p.y - by
        local near = dx * dx + dy * dy < (nest.radius * 1.25) ^ 2
        if not (near and p.kind == kind and love.math.random() < 0.88) then
            if near and p.kind == kind then
                p.life = math.min(p.life, 0.25)
                p.a = p.a * 0.45
            end
            kept[#kept + 1] = p
        end
    end
    particles = kept
    if nestsMod.isWell(nest) then
        wellIntensity = 0
    end
end

--- Districts sealed 3/3 — fountain infection swells; well becomes channelable.
function atmosphere.notifyWellUnlocked()
    wellIntensity = 1.35
    wellUnlockFlash = 0.85
    sealFlash = math.max(sealFlash, 0.65)
    seedAround("plague", FOUNTAIN_CX, FOUNTAIN_CY, 48, 28)
    for _ = 1, 10 do
        drips[#drips + 1] = {
            x = FOUNTAIN_CX + (love.math.random() - 0.5) * 28,
            y = FOUNTAIN_CY - 10,
            vy = 24 + love.math.random() * 36,
            life = 0.55 + love.math.random() * 0.35,
            a = 0.55,
        }
    end
end

--- World-space camera nudge while channeling a nest (subtle pulse, not rumble).
--- Call after nests.update so channeling flags are current-frame.
function atmosphere.getChannelShake()
    local intensity = 0
    for _, nest in ipairs(nestList) do
        if nest.channeling and nest.progress and nest.progress > 0 then
            intensity = math.max(intensity, 0.45 + nest.progress * 0.9)
        end
    end
    if intensity <= 0 then
        return 0, 0
    end
    local amp = 0.55 * intensity
    return math.sin(t * 26) * amp, math.cos(t * 31) * amp * 0.65
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
    if wellUnlockFlash > 0 then
        wellUnlockFlash = math.max(0, wellUnlockFlash - dt)
    end
    if wellIntensity > 1 then
        wellIntensity = math.max(1, wellIntensity - dt * 0.15)
    end
    for i = #sealBursts, 1, -1 do
        local burst = sealBursts[i]
        burst.life = burst.life - dt
        if burst.life <= 0 then
            table.remove(sealBursts, i)
        end
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
    local wellNest = nestById("well") or nestById("d")
    local wellLive = wellNest and not wellNest.cleansed
    local wellOpen = wellLive and wellNest.locked == false

    -- Sparse murky serum motes (not gem glitter).
    local ashRate = (cleansed("a") and 1 or 6) + urgency * 3
    local boneRate = (cleansed("b") and 1 or 5) + urgency * 2
    local emberRate = (cleansed("c") and 1 or 5) + urgency * 2
    local wellRate = 0
    if wellLive then
        wellRate = (wellOpen and 8 or 3) * (0.7 + wellIntensity * 0.35) + urgency * 2
    end
    -- Recovery grass/light motes while courtyard cleanses.
    if cleanseAmount > 0.15 and love.math.random() < (10 + cleanseAmount * 25) * dt then
        local ang = love.math.random() * math.pi * 2
        local rad = love.math.random() * (40 + 220 * cleanseAmount)
        spawnParticle(
            "grass",
            FOUNTAIN_CX + math.cos(ang) * rad,
            FOUNTAIN_CY + math.sin(ang) * rad
        )
    end

    if aNest and love.math.random() < ashRate * dt then
        local ang = love.math.random() * math.pi * 2
        local rad = love.math.random() * aNest.radius * 0.55
        spawnParticle(
            "ash",
            aNest.x + math.cos(ang) * rad,
            aNest.y + math.sin(ang) * rad - 8
        )
    end
    if bNest and love.math.random() < boneRate * dt then
        local ang = love.math.random() * math.pi * 2
        local rad = love.math.random() * bNest.radius * 0.7
        spawnParticle(
            "bone",
            bNest.x + math.cos(ang) * rad,
            bNest.y + math.sin(ang) * rad
        )
    end
    if cNest and love.math.random() < emberRate * dt then
        local ang = love.math.random() * math.pi * 2
        local rad = love.math.random() * cNest.radius * 0.45
        spawnParticle(
            "ember",
            cNest.x + math.cos(ang) * rad,
            cNest.y + math.sin(ang) * rad - 10
        )
    end
    if wellNest and love.math.random() < wellRate * dt then
        local ang = love.math.random() * math.pi * 2
        local rad = wellNest.radius * (0.45 + love.math.random() * 0.5)
        spawnParticle(
            "plague",
            FOUNTAIN_CX + math.cos(ang) * rad,
            FOUNTAIN_CY + math.sin(ang) * rad
        )
    end

    -- Fountain drips while the Plague Well is uncleansed (surge when unlocked).
    local dripRate = wellLive
        and ((wellOpen and 4.5 or 1.6) + urgency + wellIntensity * 2)
        or 0
    if dripRate > 0 and love.math.random() < dripRate * dt then
        drips[#drips + 1] = {
            x = FOUNTAIN_CX + (love.math.random() - 0.5) * 22,
            y = FOUNTAIN_CY - 8,
            vy = 20 + love.math.random() * 30,
            life = 0.45 + love.math.random() * 0.25,
            a = wellOpen and 0.5 or 0.32,
        }
    end

    local speedMul = 1 + urgency * 0.5
    for i = #particles, 1, -1 do
        local p = particles[i]
        local calm = 1
        if p.kind == "ash" and cleansed("a") then
            calm = 0.45
        elseif p.kind == "bone" and cleansed("b") then
            calm = 0.35
            p.r, p.g, p.b = 0.55, 0.52, 0.48
        elseif p.kind == "plague" and cleansed("well") then
            calm = 0.3
            p.r, p.g, p.b = 0.45, 0.5, 0.42
        elseif p.kind == "ember" and cleansed("c") then
            calm = 0.4
        end
        p.x = p.x + p.vx * dt * calm * speedMul
            + math.sin(t * 0.7 + p.y * 0.05) * 3 * dt
        p.y = p.y + p.vy * dt * calm * speedMul
        p.life = p.life - dt
        if p.life <= 0 or #particles > 120 then
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

local function setCol(r, g, b, a)
    love.graphics.setColor(r, g, b, a)
end

local function serumFor(nest)
    if nestsMod.isWell(nest) then
        return SERUM.well
    end
    return SERUM[nest.id] or SERUM.a
end

local function drawSealCross(x, y, arm, r, g, b, a)
    local prev = love.graphics.getLineWidth()
    love.graphics.setLineWidth(1.5)
    setCol(r, g, b, a)
    love.graphics.line(x - arm, y, x + arm, y)
    love.graphics.line(x, y - arm, x, y + arm)
    love.graphics.setLineWidth(prev)
end

local function drawChannelProgress(nest, cx, cy, r, g, b, pulse)
    if not (nest.channeling and nest.progress and nest.progress > 0) then
        return
    end
    local prev = love.graphics.getLineWidth()
    love.graphics.setLineWidth(2.5)
    setCol(r, g, b, 0.55 + 0.2 * pulse)
    love.graphics.arc(
        "line",
        "open",
        cx,
        cy,
        nest.radius * 0.92,
        -math.pi / 2,
        -math.pi / 2 + nest.progress * math.pi * 2,
        32
    )
    love.graphics.setLineWidth(prev)
end

--- Procedural dark glass vial (fallback if PNG missing).
local function drawProceduralVial(x, y, serum, live, empty)
    local bodyA = empty and 0.35 or 0.85
    setCol(0.12, 0.14, 0.16, bodyA)
    love.graphics.rectangle("fill", x - 6, y - 14, 12, 20, 1, 1)
    setCol(0.08, 0.09, 0.1, bodyA)
    love.graphics.rectangle("line", x - 6, y - 14, 12, 20, 1, 1)
    -- Cork.
    setCol(0.35, 0.22, 0.12, empty and 0.5 or 0.9)
    love.graphics.rectangle("fill", x - 3.5, y - 18, 7, 5)
    if live and not empty then
        setCol(serum[1], serum[2], serum[3], 0.55)
        love.graphics.rectangle("fill", x - 3.5, y - 3, 7, 7)
    end
end

local function drawPlagueVial(nest)
    ensureVials()
    local serum = serumFor(nest)
    local live = not nest.cleansed
    local locked = live and nest.locked
    local open = live and nest.isWell and not nest.locked
    local phase = (nest.id:byte(1) or 1) + (nest.id:byte(2) or 0)
    local pulse = 0.5 + 0.5 * math.sin(t * 2.2 + phase)
    if nest.channeling and nest.progress and nest.progress > 0 then
        pulse = 0.55 + 0.45 * math.sin(t * 7 + phase)
    end

    local x = nest.x
    local y = nest.y
    if nestsMod.isWell(nest) then
        x, y = FOUNTAIN_CX, FOUNTAIN_CY
    end

    -- Dark ground disk so the vial reads against cobble.
    setCol(0.04, 0.04, 0.05, live and 0.6 or 0.3)
    love.graphics.ellipse("fill", x, y + 5, 12, 5.5)
    setCol(0.08, 0.07, 0.06, live and 0.4 or 0.2)
    love.graphics.ellipse("fill", x, y + 5, 8, 3.5)

    -- Thin cleanse-radius ring only (no neon bloom).
    if live then
        local prev = love.graphics.getLineWidth()
        love.graphics.setLineWidth(1.4)
        setCol(serum[1], serum[2], serum[3], 0.24 + 0.12 * pulse + (open and 0.14 or 0))
        love.graphics.circle("line", x, y, nest.radius * 0.9)
        love.graphics.setLineWidth(prev)
    end

    local bob = live and math.sin(t * 2.6 + phase) * 1.4 or 0
    local drawY = y - 4 + bob
    -- ~45px on screen at zoom 3 → world scale ~0.47 of 32px tile.
    local scale = 0.47
    local img = live and vialImages[VIAL_FOR_NEST[nest.id] or "a"] or vialImages.empty
    if nestsMod.isWell(nest) and live then
        img = vialImages.well
        scale = open and 0.55 or 0.47
    end

    if img then
        local iw, ih = img:getWidth(), img:getHeight()
        if locked then
            setCol(0.7, 0.7, 0.75, 0.9)
        elseif live then
            setCol(1, 1, 1, 1)
        else
            setCol(0.85, 0.85, 0.8, 0.75)
        end
        love.graphics.draw(img, x, drawY, 0, scale, scale, iw * 0.5, ih * 0.72)
    else
        drawProceduralVial(x, drawY, serum, live, not live)
    end

    -- Locked well: chain / bars over the vial.
    if locked then
        local prev = love.graphics.getLineWidth()
        love.graphics.setLineWidth(1.7)
        setCol(0.55, 0.48, 0.32, 0.88)
        love.graphics.rectangle("line", x - 9, drawY - 14, 18, 22)
        love.graphics.line(x - 5, drawY - 11, x - 5, drawY + 5)
        love.graphics.line(x + 5, drawY - 11, x + 5, drawY + 5)
        love.graphics.line(x - 7, drawY - 2, x + 7, drawY - 2)
        love.graphics.setLineWidth(prev)
    end

    if not live then
        drawSealCross(x, drawY - 5, 5.5, 0.7, 0.75, 0.55, 0.5)
    elseif not locked then
        drawChannelProgress(nest, x, y, serum[1], serum[2], serum[3], pulse)
    end
end

local function drawNestSite(nest)
    drawPlagueVial(nest)
end

local function drawSealBursts()
    local prevWidth = love.graphics.getLineWidth()
    for _, burst in ipairs(sealBursts) do
        local u = 1 - burst.life / burst.maxLife
        local expand = burst.radius * (0.35 + 0.95 * math.min(1, u * 1.35))
        local a = (1 - u) * 0.75
        love.graphics.setLineWidth(3.2 - u * 1.8)
        setCol(burst.r, burst.g, burst.b, a)
        love.graphics.circle("line", burst.x, burst.y, expand)
        love.graphics.setLineWidth(1.5)
        setCol(0.92, 0.88, 0.72, a * 0.55)
        love.graphics.circle("line", burst.x, burst.y, expand * 0.72)
        if u < 0.35 then
            setCol(burst.r, burst.g, burst.b, (0.35 - u) * 0.9)
            love.graphics.circle("fill", burst.x, burst.y, burst.radius * 0.18)
        end
    end
    love.graphics.setLineWidth(prevWidth)
end

--- World-space: plague vials + sparse serum motes.
function atmosphere.drawWorld()
    for _, nest in ipairs(nestList) do
        drawNestSite(nest)
    end
    drawSealBursts()

    for _, d in ipairs(drips) do
        setCol(0.35, 0.5, 0.4, d.a * 0.45)
        love.graphics.circle("fill", d.x, d.y, 1.0)
    end

    for _, p in ipairs(particles) do
        local a = p.a
        if p.kind == "grass" then
            a = a * (0.5 + 0.5 * cleanseAmount)
        elseif p.kind == "ash" and cleansed("a") then
            a = a * 0.25
        elseif p.kind == "bone" and cleansed("b") then
            a = a * 0.25
        elseif p.kind == "plague" and cleansed("well") then
            a = a * 0.2
        elseif p.kind == "ember" and cleansed("c") then
            a = a * 0.25
        end
        setCol(p.r, p.g, p.b, a)
        love.graphics.rectangle("fill", p.x, p.y, p.size, p.size)
    end

    if wellUnlockFlash > 0 then
        setCol(0.35, 0.55, 0.4, wellUnlockFlash * 0.1)
        love.graphics.rectangle("fill", 0, 0, 30 * TILE, 24 * TILE)
    end
    if sealFlash > 0 then
        setCol(0.85, 0.8, 0.65, sealFlash * 0.12)
        love.graphics.rectangle("fill", 0, 0, 30 * TILE, 24 * TILE)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

--- Screen-space edge chevrons toward uncleansed objectives.
--- Districts until 3/3; then fountain well only.
function atmosphere.drawNestChevrons(cam, nests)
    if not cam or not nests then
        return
    end
    local sw, sh = love.graphics.getDimensions()
    local margin = 34
    local topPad = sh * 0.16
    local districtsDone = nestsMod.districtsSealed(nests)
    local targets = {}

    if districtsDone then
        local well = nestsMod.getWell(nests)
        if well and not well.cleansed then
            targets[#targets + 1] = well
        end
    else
        for _, nest in ipairs(nests) do
            if not nestsMod.isWell(nest) and not nest.cleansed then
                targets[#targets + 1] = nest
            end
        end
    end

    for _, nest in ipairs(targets) do
        local wx = nest.x
        local wy = nest.y
        if nestsMod.isWell(nest) then
            wx, wy = FOUNTAIN_CX, FOUNTAIN_CY
        end
        local sx, sy = cam:cameraCoords(wx, wy)
        local inside = sx > margin
            and sx < sw - margin
            and sy > topPad
            and sy < sh - margin
        if not inside then
            local cx = math.max(margin, math.min(sw - margin, sx))
            local cy = math.max(topPad, math.min(sh - margin, sy))
            local dx, dy = sx - cx, sy - cy
            local len = math.sqrt(dx * dx + dy * dy)
            if len < 1 then
                dx, dy = wx - cam.x, wy - cam.y
                len = math.sqrt(dx * dx + dy * dy)
            end
            if len > 0.1 then
                dx, dy = dx / len, dy / len
            else
                dx, dy = 0, -1
            end
            local col = nestsMod.color(nest.id)
            local pulse = 0.55 + 0.45 * math.sin(t * 5 + (nest.id:byte(1) or 1))
            local size = 12
            local px = cx - dx * 6
            local py = cy - dy * 6
            local px2 = px - dx * size
            local py2 = py - dy * size
            local ox, oy = -dy * (size * 0.55), dx * (size * 0.55)
            setCol(col[1], col[2], col[3], 0.55 + 0.35 * pulse)
            love.graphics.polygon(
                "fill",
                px, py,
                px2 + ox, py2 + oy,
                px2 - ox, py2 - oy
            )
            setCol(0.05, 0.04, 0.03, 0.55)
            love.graphics.setLineWidth(1.5)
            love.graphics.polygon(
                "line",
                px, py,
                px2 + ox, py2 + oy,
                px2 - ox, py2 - oy
            )
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

--- Recovery wash from the fountain — strong enough to read as a new time of day.
function atmosphere.drawCleanseWorld()
    if cleanseAmount <= 0 then
        return
    end
    local c = cleanseAmount
    local maxR = 50 + 320 * c
    for i = 8, 1, -1 do
        local u = i / 8
        local r = maxR * u
        local a = 0.16 * c * (1.1 - u)
        love.graphics.setColor(0.28, 0.55, 0.26, a)
        love.graphics.circle("fill", FOUNTAIN_CX, FOUNTAIN_CY, r)
    end
    -- Sunlit grass rings.
    for i = 4, 1, -1 do
        local u = i / 4
        love.graphics.setColor(0.42, 0.72, 0.32, 0.1 * c * u)
        love.graphics.circle(
            "fill",
            FOUNTAIN_CX,
            FOUNTAIN_CY,
            (60 + 180 * c) * u
        )
    end
    -- Clear bright water core (stamp stays readable).
    love.graphics.setColor(0.7, 0.92, 0.95, 0.28 * c)
    love.graphics.circle("fill", FOUNTAIN_CX, FOUNTAIN_CY, 18 + 10 * c)
    love.graphics.setColor(0.92, 0.98, 0.95, 0.35 * c)
    love.graphics.circle("fill", FOUNTAIN_CX, FOUNTAIN_CY, 10 + 6 * c)
    love.graphics.setColor(1, 1, 1, 0.2 * c)
    love.graphics.circle("line", FOUNTAIN_CX, FOUNTAIN_CY, 26 + 8 * c)
    love.graphics.setColor(1, 1, 1, 1)
end

--- Screen-space grade + daylight lift. Plague fog dies as cleanse rises.
function atmosphere.drawGrade()
    local w, h = love.graphics.getDimensions()
    local top = h * 0.12
    local plagueFade = 1 - cleanseAmount * 0.98
    local base = 0.04 * plagueFade
    if base > 0.002 then
        love.graphics.setColor(0.08, 0.1, 0.14, base)
        love.graphics.rectangle("fill", 0, top, w, h - top)
    end

    if ratio < 0.25 and cleanseAmount < 0.35 then
        local urgency = (0.25 - ratio) / 0.25
        if ratio < 0.1 then
            urgency = urgency + (0.1 - ratio) * 2.0
        end
        urgency = math.min(1, urgency) * (1 - cleanseAmount * 2.5)
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

    -- Daylight grade: lift shadows, warm greens/yellows (not a sticker tint).
    if cleanseAmount > 0 then
        local c = cleanseAmount
        -- Soften plague shadow base with a lifted midtone wash.
        love.graphics.setColor(0.88, 0.9, 0.78, 0.18 * c)
        love.graphics.rectangle("fill", 0, top, w, h - top)
        love.graphics.setColor(0.95, 0.92, 0.68, 0.16 * c)
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.setColor(0.5, 0.82, 0.4, 0.14 * c)
        love.graphics.rectangle("fill", 0, top, w, h - top)
        love.graphics.setColor(1.0, 0.98, 0.86, 0.18 * c)
        love.graphics.rectangle("fill", 0, 0, w, h * 0.4)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

--- Stage A blinding flash (screen space, full frame).
function atmosphere.drawWinFlash()
    if winFlash <= 0 then
        return
    end
    local w, h = love.graphics.getDimensions()
    -- Warm-white peak; near-opaque at 1.
    love.graphics.setColor(1.0, 0.98, 0.92, winFlash * 0.96)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, winFlash * 0.35)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1)
end

return atmosphere
