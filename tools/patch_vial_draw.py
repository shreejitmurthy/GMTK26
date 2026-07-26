from pathlib import Path

path = Path(__file__).resolve().parents[1] / "scripts" / "atmosphere.lua"
text = path.read_text(encoding="utf-8")

# Replace gem header block
old_header = """--- Pixel gem images (res/images/gems).
local gemImages = {}
local GEM_FOR_NEST = {
    a = "blue",
    b = "purple",
    c = "green",
    well = "cyan",
    d = "cyan",
}
local GEM_GLOW = {
    blue = { 0.25, 0.65, 1.0 },
    purple = { 0.75, 0.35, 1.0 },
    green = { 0.25, 0.95, 0.45 },
    cyan = { 0.3, 0.95, 0.9 },
}
"""

new_header = """--- Sealed plague vials (DCSS CC0 potions under res/images/nests/).
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
"""

if old_header not in text:
    raise SystemExit("header block not found")
text = text.replace(old_header, new_header, 1)

text = text.replace(
    """-- Living decay for the infested courtyard.
-- District nests + well are bobbing pixel gemstones with expanding glow.
-- Must not obscure the top-center countdown HUD.""",
    """-- Living decay for the infested courtyard.
-- District nests + well are sealed plague vials (dark glass + serum).
-- Must not obscure the top-center countdown HUD.""",
    1,
)

# Replace particle colors with murky serum
old_particles = """    if kind == "plague" then
        -- Cyan well sparkles.
        p.vx = (love.math.random() - 0.5) * 6
        p.vy = -4 - love.math.random() * 8
        p.r, p.g, p.b = 0.4, 0.95, 0.9
        p.a = 0.35 + love.math.random() * 0.35
        p.size = 1.0 + love.math.random() * 1.6
    elseif kind == "ash" then
        -- Electric blue sparkles (nest A).
        p.vx = (love.math.random() - 0.5) * 8
        p.vy = -10 - love.math.random() * 14
        p.r, p.g, p.b = 0.35, 0.75, 1.0
        p.a = 0.4 + love.math.random() * 0.4
        p.size = 1.1 + love.math.random() * 1.8
        p.life = 1.4 + love.math.random() * 2.2
    elseif kind == "bone" then
        -- Purple sparkles (nest B).
        p.vx = (love.math.random() - 0.5) * 5
        p.vy = -6 - love.math.random() * 10
        p.r, p.g, p.b = 0.8, 0.45, 1.0
        p.a = 0.4 + love.math.random() * 0.35
        p.size = 1.2 + love.math.random() * 2.0
        p.life = 1.8 + love.math.random() * 2.4
    elseif kind == "ember" then
        -- Gem-green sparkles (nest C).
        p.vx = (love.math.random() - 0.5) * 4
        p.vy = -10 - love.math.random() * 14
        p.r, p.g, p.b = 0.35, 1.0, 0.5
        p.a = 0.45 + love.math.random() * 0.4
        p.size = 1.2 + love.math.random() * 1.8
        p.life = 1 + love.math.random() * 1.5
    end"""

new_particles = """    if kind == "plague" then
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
    end"""

if old_particles not in text:
    raise SystemExit("particle block not found")
text = text.replace(old_particles, new_particles, 1)

old_ensure = """local function ensureGems()
    if next(gemImages) then
        return
    end
    local files = {
        blue = "res/images/gems/gem_blue.png",
        purple = "res/images/gems/gem_purple.png",
        green = "res/images/gems/gem_green.png",
        cyan = "res/images/gems/gem_cyan.png",
    }
    for key, path in pairs(files) do
        local ok, img = pcall(love.graphics.newImage, path)
        if ok and img then
            img:setFilter("nearest", "nearest")
            gemImages[key] = img
        else
            print("[atmosphere] missing gem image: " .. path)
        end
    end
end
"""

new_ensure = """local function ensureVials()
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
"""

if old_ensure not in text:
    raise SystemExit("ensureGems not found")
text = text.replace(old_ensure, new_ensure, 1)

text = text.replace("ensureGems()", "ensureVials()", 2)
text = text.replace(
    """    cleanseAmount = 0
    wellIntensity = 0
    wellUnlockFlash = 0
    ensureVials()
""",
    """    cleanseAmount = 0
    wellIntensity = 0
    wellUnlockFlash = 0
    winFlash = 0
    ensureVials()
""",
    1,
)

# Reduce seed counts
text = text.replace(
    """    if a then
        seedAround("ash", a.x, a.y, a.radius * 0.7, 18)
    end
    if b then
        seedAround("bone", b.x, b.y, b.radius * 0.7, 16)
    end
    if c then
        seedAround("ember", c.x, c.y, c.radius * 0.7, 16)
    end
    if well then
        seedAround("plague", well.x, well.y, well.radius * 0.85, 18)
    end
    seedAround("ash", 15 * TILE, 12 * TILE, 140, 10)
""",
    """    if a then
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
""",
    1,
)

# Replace draw block from setCol through drawNestSite
start = text.find("local function setCol(r, g, b, a)")
end = text.find("local function drawSealBursts()")
assert start > 0 and end > start

new_draw = r'''local function setCol(r, g, b, a)
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
    love.graphics.rectangle("fill", x - 3, y - 8, 6, 11, 1, 1)
    setCol(0.08, 0.09, 0.1, bodyA)
    love.graphics.rectangle("line", x - 3, y - 8, 6, 11, 1, 1)
    -- Cork.
    setCol(0.35, 0.22, 0.12, empty and 0.5 or 0.9)
    love.graphics.rectangle("fill", x - 2, y - 11, 4, 3)
    if live and not empty then
        setCol(serum[1], serum[2], serum[3], 0.55)
        love.graphics.rectangle("fill", x - 2, y - 2, 4, 4)
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

    -- Subtle ground shadow.
    setCol(0.04, 0.04, 0.05, live and 0.4 or 0.18)
    love.graphics.ellipse("fill", x, y + 5, 6, 2.5)

    -- Thin cleanse-radius ring only (no neon bloom).
    if live then
        local prev = love.graphics.getLineWidth()
        love.graphics.setLineWidth(1.25)
        setCol(serum[1], serum[2], serum[3], 0.18 + 0.1 * pulse + (open and 0.12 or 0))
        love.graphics.circle("line", x, y, nest.radius * 0.9)
        love.graphics.setLineWidth(prev)
    end

    local bob = live and math.sin(t * 2.6 + phase) * 1.2 or 0
    local drawY = y - 2 + bob
    -- ~16px on screen at zoom 3 → world scale ~0.2 of 32px tile.
    local scale = 0.2
    local img = live and vialImages[VIAL_FOR_NEST[nest.id] or "a"] or vialImages.empty
    if nestsMod.isWell(nest) and live then
        img = vialImages.well
        scale = open and 0.24 or 0.2
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
        love.graphics.setLineWidth(1.4)
        setCol(0.55, 0.48, 0.32, 0.8)
        love.graphics.rectangle("line", x - 5, drawY - 10, 10, 14)
        love.graphics.line(x - 3, drawY - 8, x - 3, drawY + 2)
        love.graphics.line(x + 3, drawY - 8, x + 3, drawY + 2)
        love.graphics.line(x - 4, drawY - 3, x + 4, drawY - 3)
        love.graphics.setLineWidth(prev)
    end

    if not live then
        drawSealCross(x, drawY - 4, 4, 0.7, 0.75, 0.55, 0.45)
    elseif not locked then
        drawChannelProgress(nest, x, y, serum[1], serum[2], serum[3], pulse)
    end
end

local function drawNestSite(nest)
    drawPlagueVial(nest)
end

'''

text = text[:start] + new_draw + text[end:]

path.write_text(text, encoding="utf-8")
print("patched vial draw")
