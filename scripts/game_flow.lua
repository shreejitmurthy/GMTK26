-- Title → narrative → run → pause / extract / cleansed presentation.
-- Keeps Italianno for titles and body; readability via size + contrast + shadow.

local game_map = require "scripts.game_map"
local atmosphere = require "scripts.atmosphere"
local collapse = require "scripts.collapse"
local ui_font = require "scripts.ui_font"

local flow = {}

local FOUNTAIN_X = 15 * 16
local FOUNTAIN_Y = 12 * 16
local WIN_PRESENT_SECONDS = 3.2

local NARRATIVE_STORY = {
    "You are a plague doctor sent into an",
    "infested Victorian courtyard.",
    "The fountain — the Plague Well —",
    "is the heart of the infection.",
    "Your plague tolerance is a countdown.",
    "Time is your life.",
    "Seal all three nests. Cleanse the well.",
}

local NARRATIVE_RULES = {
    "WASD move · Shift dash · Mouse / Space attack",
    "Hold E to cleanse nests",
    "Kills restore time · Hits & cleansing cost it",
    "Cracking ground collapses into the abyss",
}

local function ensureFonts(state)
    if state.hudTimerFont and state.hudSubtitleFont then
        return
    end
    local function loadScriptFont(size)
        return ui_font.new("res/fonts/Italianno-Regular.ttf", size)
    end
    state.hudTimerFont = loadScriptFont(80)
    state.hudLabelFont = loadScriptFont(34)
    state.hudHelpFont = loadScriptFont(30)
    state.hudBodyFont = loadScriptFont(32)
    state.hudSmallFont = loadScriptFont(26)
    state.hudSubtitleFont = ui_font.new(
        "res/fonts/RobotoMono-VariableFont_wght.ttf",
        22
    )
end

function flow.ensureFonts(state)
    ensureFonts(state)
end

--- Soft drop shadow for readable light ink on dark scenes.
function flow.printShadow(font, text, x, y, r, g, b, a)
    a = a or 1
    love.graphics.setFont(font)
    love.graphics.setColor(0, 0, 0, 0.82 * a)
    love.graphics.print(text, x + 2, y + 2)
    love.graphics.setColor(r, g, b, a)
    love.graphics.print(text, x, y)
end

function flow.printfShadow(font, text, x, y, limit, align, r, g, b, a)
    a = a or 1
    love.graphics.setFont(font)
    love.graphics.setColor(0, 0, 0, 0.82 * a)
    love.graphics.printf(text, x + 2, y + 2, limit, align)
    love.graphics.setColor(r, g, b, a)
    love.graphics.printf(text, x, y, limit, align)
end

local function hashNoise(n)
    local x = math.sin(n * 127.1 + 311.7) * 43758.5453
    return x - math.floor(x)
end

--- Worn wood-pulp parchment: jagged edges, dog-ears, stains, fiber noise.
local function drawParchment(x, y, w, h)
    -- Drop shadow
    love.graphics.setColor(0.05, 0.03, 0.02, 0.55)
    love.graphics.rectangle("fill", x + 5, y + 7, w - 2, h - 2)

    -- Jagged outer silhouette via short edge segments.
    love.graphics.setColor(0.72, 0.6, 0.4, 1)
    love.graphics.rectangle("fill", x + 3, y + 3, w - 6, h - 6)

    local function jaggedEdge(horizontal, atStart)
        local steps = horizontal and math.floor(w / 14) or math.floor(h / 14)
        for i = 0, steps do
            local t = i / math.max(1, steps)
            local n = hashNoise(i * 17 + (horizontal and 1 or 3) * 41 + (atStart and 0 or 9))
            local jag = (n - 0.5) * 5
            if horizontal then
                local px = x + t * w
                local py = atStart and (y + 1 + jag) or (y + h - 4 + jag)
                love.graphics.setColor(0.78 - n * 0.08, 0.66 - n * 0.06, 0.45, 1)
                love.graphics.rectangle("fill", px, py, 15, 4)
            else
                local px = atStart and (x + 1 + jag) or (x + w - 4 + jag)
                local py = y + t * h
                love.graphics.setColor(0.76 - n * 0.07, 0.64 - n * 0.05, 0.43, 1)
                love.graphics.rectangle("fill", px, py, 4, 15)
            end
        end
    end
    jaggedEdge(true, true)
    jaggedEdge(true, false)
    jaggedEdge(false, true)
    jaggedEdge(false, false)

    -- Main pulp face
    love.graphics.setColor(0.8, 0.7, 0.5, 1)
    love.graphics.rectangle("fill", x + 8, y + 8, w - 16, h - 16)

    -- Fiber / grain noise
    for i = 1, 55 do
        local n1 = hashNoise(i * 3.1)
        local n2 = hashNoise(i * 7.7 + 2)
        local n3 = hashNoise(i * 11.3 + 5)
        local fx = x + 10 + n1 * (w - 20)
        local fy = y + 10 + n2 * (h - 20)
        love.graphics.setColor(0.62, 0.5, 0.32, 0.08 + n3 * 0.1)
        love.graphics.rectangle("fill", fx, fy, 6 + n3 * 10, 1)
    end

    -- Stains
    local stains = {
        { 0.18, 0.22, 18, 0.1 },
        { 0.72, 0.35, 14, 0.08 },
        { 0.4, 0.78, 16, 0.09 },
        { 0.85, 0.7, 12, 0.07 },
    }
    for _, s in ipairs(stains) do
        love.graphics.setColor(0.55, 0.42, 0.22, s[4])
        love.graphics.circle("fill", x + w * s[1], y + h * s[2], s[3])
    end

    -- Dog-eared corners
    love.graphics.setColor(0.62, 0.5, 0.34, 1)
    love.graphics.polygon("fill", x + 8, y + 8, x + 28, y + 8, x + 8, y + 28)
    love.graphics.setColor(0.5, 0.38, 0.22, 0.55)
    love.graphics.line(x + 8, y + 28, x + 28, y + 8)
    love.graphics.setColor(0.6, 0.48, 0.32, 1)
    love.graphics.polygon(
        "fill",
        x + w - 8,
        y + h - 8,
        x + w - 30,
        y + h - 8,
        x + w - 8,
        y + h - 30
    )

    -- Fold crease
    love.graphics.setColor(0.5, 0.38, 0.22, 0.18)
    love.graphics.rectangle("fill", x + w * 0.48, y + 12, 2, h - 24)

    -- Inner ink frame (thin)
    love.graphics.setColor(0.35, 0.22, 0.12, 0.55)
    love.graphics.rectangle("line", x + 14.5, y + 14.5, w - 29, h - 29)
end

local function drawInkText(font, text, x, y, limit, align)
    love.graphics.setFont(font)
    love.graphics.setColor(0.26, 0.15, 0.08, 1)
    love.graphics.printf(text, x, y, limit, align or "center")
end

local function lineStep(font)
    return font:getHeight() + 8
end

function flow.resetWin(state)
    state.winPresenting = false
    state.winReady = false
    state.winTimer = 0
    atmosphere.setCleanse(0)
end

function flow.beginWinPresentation(state)
    state.winPresenting = true
    state.winReady = false
    state.winTimer = 0
    atmosphere.setCleanse(0)
    -- Hold camera on the fountain for the cleanse beat.
    state._freezeCamX = FOUNTAIN_X
    state._freezeCamY = FOUNTAIN_Y
end

function flow.updateWin(state, dt)
    if not state.sectorCleared then
        return
    end
    if not state.winPresenting and not state.winReady then
        flow.beginWinPresentation(state)
    end
    if state.winReady then
        return
    end
    state.winTimer = (state.winTimer or 0) + dt
    local t = math.min(1, state.winTimer / WIN_PRESENT_SECONDS)
    atmosphere.setCleanse(t)
    if state.winTimer >= WIN_PRESENT_SECONDS then
        state.winPresenting = false
        state.winReady = true
        atmosphere.setCleanse(1)
    end
end

--- Title / narrative backdrop: courtyard map focused on the fountain.
function flow.loadBackdrop(state)
    ensureFonts(state)
    if not state.gameMap then
        state.gameMap = game_map.load("res/maps/map.lua")
    end
    if not state.nests then
        local nests = require "scripts.nests"
        state.nests = nests.fromMap(state.gameMap)
    end
    atmosphere.load(state.nests)
    atmosphere.setCleanse(0)
    collapse.load(state.gameMap, state.nests)
    if not cam then
        cam = camera(FOUNTAIN_X, FOUNTAIN_Y, zoom or 3)
    else
        cam:lookAt(FOUNTAIN_X, FOUNTAIN_Y)
    end
    state.actors = state.actors or {}
end

function flow.enterTitle(state)
    ensureFonts(state)
    flow.loadBackdrop(state)
    flow.resetWin(state)
    state.extracted = false
    state.sectorCleared = false
    state.extractReason = nil
    state.gameState = GAME_STATE.TITLE
    if state.countdown then
        state.countdown:pause()
    end
end

function flow.enterNarrative(state)
    ensureFonts(state)
    flow.loadBackdrop(state)
    state.gameState = GAME_STATE.NARRATIVE
end

function flow.drawWorldBackdrop(state)
    if not state.gameMap or not cam then
        return
    end
    cam:lookAt(FOUNTAIN_X, FOUNTAIN_Y)
    cam:attach()
    local function noActors() end
    -- No collapse/gameplay hooks on the title card — intact courtyard only.
    game_map.drawWithActors(state.gameMap, noActors, {})
    atmosphere.drawWorld()
    atmosphere.drawCleanseWorld()
    cam:detach()
    atmosphere.drawGrade()
    -- Soft vignette so title/parchment text stays readable.
    local sw, sh = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
end

function flow.drawTitle(state)
    local sw, sh = love.graphics.getDimensions()
    flow.drawWorldBackdrop(state)
    local labelFont = state.hudLabelFont
    local helpFont = state.hudHelpFont
    flow.printfShadow(
        labelFont,
        "Your time is your life.",
        0,
        sh * 0.36,
        sw,
        "center",
        0.9,
        0.82,
        0.68,
        1
    )
    flow.printfShadow(
        helpFont,
        "Play  ·  any key or click",
        0,
        sh * 0.56,
        sw,
        "center",
        0.92,
        0.88,
        0.78,
        1
    )
    flow.printfShadow(
        state.hudSmallFont or helpFont,
        "Esc  Quit",
        0,
        sh * 0.64,
        sw,
        "center",
        0.85,
        0.78,
        0.65,
        0.95
    )
    love.graphics.setColor(1, 1, 1, 1)
end

function flow.drawNarrative(state)
    local sw, sh = love.graphics.getDimensions()
    flow.drawWorldBackdrop(state)

    local titleFont = state.hudLabelFont
    local body = state.hudBodyFont or state.hudHelpFont
    local footerFont = state.hudHelpFont
    local pad = 36
    local innerW = math.min(640, sw - 120)
    local storyStep = lineStep(body)
    local titleH = titleFont:getHeight() + 16
    local storyH = #NARRATIVE_STORY * storyStep
    local rulesH = #NARRATIVE_RULES * storyStep
    local gap = 18
    local footerH = footerFont:getHeight() + 8
    local contentH = titleH + storyH + gap + rulesH + gap + footerH
    local panelH = contentH + pad * 2 + 24
    local panelW = innerW + pad * 2
    local px = (sw - panelW) / 2
    local py = (sh - panelH) / 2
    drawParchment(px, py, panelW, panelH)

    local textW = panelW - pad * 2
    local textX = px + pad
    local y = py + pad + 8

    drawInkText(titleFont, "Briefing", textX, y, textW, "center")
    y = y + titleH

    for _, line in ipairs(NARRATIVE_STORY) do
        drawInkText(body, line, textX, y, textW, "center")
        y = y + storyStep
    end
    y = y + gap

    for _, line in ipairs(NARRATIVE_RULES) do
        drawInkText(body, line, textX, y, textW, "center")
        y = y + storyStep
    end
    y = y + gap

    drawInkText(
        footerFont,
        "Continue  ·  Enter / Space / click",
        textX,
        y,
        textW,
        "center"
    )
    love.graphics.setColor(1, 1, 1, 1)
end

function flow.drawPause(state)
    local sw, sh = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, 0.62)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    local body = state.hudBodyFont or state.hudHelpFont
    local titleFont = state.hudLabelFont
    local lines = {
        "Resume   ·  Esc",
        "Restart  ·  R",
        "Quit     ·  Q",
    }
    local step = lineStep(body)
    local panelW, panelH = 440, 56 + titleFont:getHeight() + #lines * step + 40
    local px, py = (sw - panelW) / 2, (sh - panelH) / 2
    drawParchment(px, py, panelW, panelH)
    local y = py + 36
    drawInkText(titleFont, "Paused", px + 24, y, panelW - 48, "center")
    y = y + titleFont:getHeight() + 20
    for _, line in ipairs(lines) do
        drawInkText(body, line, px + 24, y, panelW - 48, "center")
        y = y + step
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function flow.drawVictory(state)
    local sw, sh = love.graphics.getDimensions()
    local titleFont = state.hudTimerFont
    local labelFont = state.hudLabelFont
    local body = state.hudBodyFont or state.hudHelpFont
    local footerFont = state.hudHelpFont
    local lines = {
        "Time remaining  " .. (state.countdown and state.countdown:format() or "0"),
        "The infection is broken.",
        "The courtyard breathes again.",
    }
    local step = lineStep(body)
    local panelW = 660
    local panelH = 48
        + titleFont:getHeight()
        + 12
        + labelFont:getHeight()
        + 8
        + #lines * step
        + footerFont:getHeight()
        + 36
    local px, py = (sw - panelW) / 2, (sh - panelH) / 2 - 10
    drawParchment(px, py, panelW, panelH)
    local y = py + 28
    drawInkText(titleFont, "THE WELL IS CLEANSED", px + 20, y, panelW - 40, "center")
    y = y + titleFont:getHeight() + 10
    for _, line in ipairs(lines) do
        drawInkText(body, line, px + 24, y, panelW - 48, "center")
        y = y + step
    end
    y = y + 10
    drawInkText(
        footerFont,
        "R  Descend Again     Esc  Quit",
        px + 20,
        y,
        panelW - 40,
        "center"
    )
    love.graphics.setColor(1, 1, 1, 1)
end

function flow.drawExtract(state)
    local sw, sh = love.graphics.getDimensions()
    local titleFont = state.hudTimerFont
    local body = state.hudBodyFont or state.hudHelpFont
    local footerFont = state.hudHelpFont
    local nestsMod = require "scripts.nests"
    local reason = state.extractReason == "abyss"
        and "You fell into the abyss."
        or "Plague tolerance exhausted."
    local lines = {
        reason,
        string.format("Nests remaining: %d", nestsMod.remaining(state.nests)),
    }
    local step = lineStep(body)
    local panelW = 640
    local panelH = 48
        + titleFont:getHeight()
        + 16
        + #lines * step
        + footerFont:getHeight()
        + 40
    local px, py = (sw - panelW) / 2, (sh - panelH) / 2
    drawParchment(px, py, panelW, panelH)
    local y = py + 28
    drawInkText(titleFont, "EXTRACTED", px + 20, y, panelW - 40, "center")
    y = y + titleFont:getHeight() + 14
    for _, line in ipairs(lines) do
        drawInkText(body, line, px + 24, y, panelW - 48, "center")
        y = y + step
    end
    y = y + 12
    drawInkText(
        footerFont,
        "R  Descend Again     Esc  Quit",
        px + 20,
        y,
        panelW - 40,
        "center"
    )
    love.graphics.setColor(1, 1, 1, 1)
end

function flow.fountainFocus()
    return FOUNTAIN_X, FOUNTAIN_Y
end

return flow
