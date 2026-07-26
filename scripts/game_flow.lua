-- Title → narrative → run → pause / extract / cleansed presentation.
-- Italianno is reserved for display titles; longer copy uses Cinzel Decorative.

local game_map = require "scripts.game_map"
local atmosphere = require "scripts.atmosphere"
local collapse = require "scripts.collapse"
local ui_font = require "scripts.ui_font"

local flow = {}

local FOUNTAIN_X = 15 * 16
local FOUNTAIN_Y = 12 * 16
--- Staged cleanse beat: flash → daylight recovery → victory UI.
local WIN_PRESENT_SECONDS = 5.4
local WIN_FLASH_END = 0.6
local WIN_DAYLIGHT_END = 2.5

local PANEL_MARGIN = 28
local PAD = 8
local GAP = 12
local NARRATIVE_PANEL_MAX_H = 560
local UI_STYLE = "italianno_titles_cinzel_true_4x_v3"

local NARRATIVE_STORY = {
    "You are a plague doctor sent into an",
    "infested Victorian courtyard.",
    "Collect all three sealed plague potions",
    "scattered through the districts.",
    "Only then can you cleanse the Plague Well",
    "at the fountain — and break the infection.",
    "Your plague tolerance is a countdown.",
    "Time is your life.",
}

local NARRATIVE_RULES = {
    "WASD move · Shift dash · Mouse / Space attack",
    "Hold E to collect potions · Well unlocks at 3/3",
    "Then Hold E at the fountain to cleanse the Well",
    "Kills restore time · Hits & cleansing cost it",
    "Cracking ground collapses into the abyss",
}

local function ensureFonts(state)
    if state.hudTimerFont and state.uiStyle == UI_STYLE then
        return
    end
    local function loadScript(size)
        return ui_font.new("res/fonts/Italianno-Regular.ttf", size)
    end
    local function loadBody(size)
        return ui_font.new("res/fonts/CinzelDecorative-Bold.ttf", size)
    end
    state.uiStyle = UI_STYLE
    state.hudTimerFont = loadScript(80)
    state.hudTitleFont = loadScript(48)
    state.hudLabelFont = loadScript(30)
    state.hudBodyFont = loadBody(18)
    state.hudHelpFont = loadBody(16)
    state.hudSmallFont = loadScript(24)
    state.hudSubtitleFont = loadBody(16)
end

function flow.ensureFonts(state)
    ensureFonts(state)
end

--- Soft dark plate for HUD clusters on busy cobble.
function flow.drawHudPlate(x, y, w, h, alpha)
    alpha = alpha or 0.62
    love.graphics.setColor(0.05, 0.04, 0.03, alpha)
    love.graphics.rectangle("fill", x, y, w, h, 6, 6)
    love.graphics.setColor(0.9, 0.85, 0.7, 0.1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 6, 6)
end

--- Soft drop shadow for readable light ink on dark scenes.
function flow.printShadow(font, text, x, y, r, g, b, a)
    a = a or 1
    love.graphics.setColor(0, 0, 0, 0.82 * a)
    ui_font.print(font, text, x + 2, y + 2)
    love.graphics.setColor(r, g, b, a)
    ui_font.print(font, text, x, y)
end

function flow.printfShadow(font, text, x, y, limit, align, r, g, b, a)
    a = a or 1
    love.graphics.setColor(0, 0, 0, 0.82 * a)
    ui_font.printf(font, text, x + 2, y + 2, limit, align)
    love.graphics.setColor(r, g, b, a)
    ui_font.printf(font, text, x, y, limit, align)
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
    for i = 1, 40 do
        local n1 = hashNoise(i * 3.1)
        local n2 = hashNoise(i * 7.7 + 2)
        local n3 = hashNoise(i * 11.3 + 5)
        local fx = x + 10 + n1 * (w - 20)
        local fy = y + 10 + n2 * (h - 20)
        love.graphics.setColor(0.62, 0.5, 0.32, 0.06 + n3 * 0.07)
        love.graphics.rectangle("fill", fx, fy, 6 + n3 * 10, 1)
    end

    local stains = {
        { 0.18, 0.22, 16, 0.08 },
        { 0.72, 0.35, 12, 0.06 },
        { 0.85, 0.78, 11, 0.06 },
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
    love.graphics.setColor(0.22, 0.13, 0.07, 1)
    ui_font.printf(font, text, x, y, limit, align or "center")
end

local function lineStep(font, extra)
    return ui_font.getHeight(font) + (extra or 10)
end

local function blockHeight(font, text, limit)
    local _, lines = ui_font.getWrap(font, text, limit)
    return math.max(1, #lines) * ui_font.getHeight(font)
end

local function fitPanel(sw, sh, wantW, wantH)
    local maxW = sw - PANEL_MARGIN * 2
    local maxH = sh - PANEL_MARGIN * 2
    local w = math.min(wantW, maxW)
    local h = math.min(wantH, maxH)
    local px = (sw - w) / 2
    local py = (sh - h) / 2
    return px, py, w, h
end

function flow.resetWin(state)
    state.winPresenting = false
    state.winReady = false
    state.winTimer = 0
    atmosphere.setCleanse(0)
    if atmosphere.setWinFlash then
        atmosphere.setWinFlash(0)
    end
end

function flow.beginWinPresentation(state)
    state.winPresenting = true
    state.winReady = false
    state.winTimer = 0
    atmosphere.setCleanse(0)
    atmosphere.setWinFlash(0)
    -- Hold camera on the fountain for the cleanse beat.
    state._freezeCamX = FOUNTAIN_X
    state._freezeCamY = FOUNTAIN_Y
    local sfx = require "scripts.sound_effects"
    if sfx.playWellCleansed then
        sfx.playWellCleansed()
    end
end

function flow.updateWin(state, dt)
    if not state.sectorCleared then
        return
    end
    if not state.winPresenting and not state.winReady then
        flow.beginWinPresentation(state)
    end
    if state.winReady then
        atmosphere.setWinFlash(0)
        atmosphere.setCleanse(1)
        return
    end
    state.winTimer = (state.winTimer or 0) + dt
    local t = state.winTimer
    local flash, cleanse = 0, 0
    if t < WIN_FLASH_END then
        -- Stage A: hard white/warm flash peaking near-opaque, then easing out.
        local u = t / WIN_FLASH_END
        if u < 0.32 then
            flash = (u / 0.32) ^ 0.65
        else
            local v = (u - 0.32) / 0.68
            flash = 1.0 - 0.3 * (v * v)
        end
        cleanse = 0.15 * u
    elseif t < WIN_DAYLIGHT_END then
        -- Stage B: flash decays into strong daylight / recovery wash.
        local u = (t - WIN_FLASH_END) / (WIN_DAYLIGHT_END - WIN_FLASH_END)
        flash = 0.7 * ((1 - u) ^ 2.2)
        cleanse = 0.15 + 0.85 * u
    else
        -- Stage C: full recovery; victory UI rides on top.
        flash = 0
        cleanse = 1
    end
    atmosphere.setWinFlash(flash)
    atmosphere.setCleanse(cleanse)
    if t >= WIN_PRESENT_SECONDS then
        state.winPresenting = false
        state.winReady = true
        atmosphere.setWinFlash(0)
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
    if atmosphere.setWinFlash then
        atmosphere.setWinFlash(0)
    end
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
    state.narrativeScroll = 0
    state.narrativeMaxScroll = 0
    state.gameState = GAME_STATE.NARRATIVE
end

function flow.scrollNarrative(state, delta)
    if state.gameState ~= GAME_STATE.NARRATIVE then
        return
    end
    local maxScroll = state.narrativeMaxScroll or 0
    state.narrativeScroll = math.max(
        0,
        math.min(maxScroll, (state.narrativeScroll or 0) + delta)
    )
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
    local titleFont = state.hudLabelFont
    local helpFont = state.hudHelpFont
    flow.printfShadow(
        titleFont,
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
    local pad = 32
    local panelW = math.min(560, sw - PANEL_MARGIN * 2)
    local panelH = math.min(
        NARRATIVE_PANEL_MAX_H,
        sh - PANEL_MARGIN * 2,
        sh * 0.88
    )
    local px = (sw - panelW) / 2
    local py = (sh - panelH) / 2
    drawParchment(px, py, panelW, panelH)

    local textW = panelW - pad * 2
    local textX = px + pad
    local titleBlock = ui_font.getHeight(titleFont) + 10
    local footerH = ui_font.getHeight(footerFont) + 8

    local contentH = GAP * 0.35
    for _, line in ipairs(NARRATIVE_STORY) do
        contentH = contentH + blockHeight(body, line, textW) + 6
    end
    for _, line in ipairs(NARRATIVE_RULES) do
        contentH = contentH + blockHeight(body, line, textW) + 4
    end
    local viewTop = py + pad + titleBlock
    local viewBottom = py + panelH - pad - footerH - 8
    local viewH = math.max(40, viewBottom - viewTop)
    local maxScroll = math.max(0, contentH - viewH)
    state.narrativeMaxScroll = maxScroll
    state.narrativeScroll = math.max(
        0,
        math.min(maxScroll, state.narrativeScroll or 0)
    )
    local scroll = state.narrativeScroll

    -- Fixed title (never clipped by scroll).
    drawInkText(titleFont, "Briefing", textX, py + pad - 2, textW, "center")

    love.graphics.setScissor(textX - 2, viewTop, textW + 4, viewH)
    local y = viewTop - scroll
    for _, line in ipairs(NARRATIVE_STORY) do
        drawInkText(body, line, textX, y, textW, "center")
        y = y + blockHeight(body, line, textW) + 6
    end
    y = y + GAP * 0.35
    for _, line in ipairs(NARRATIVE_RULES) do
        drawInkText(body, line, textX, y, textW, "center")
        y = y + blockHeight(body, line, textW) + 4
    end
    love.graphics.setScissor()

    local footerY = py + panelH - pad - footerH
    local footer = "Continue  ·  Enter / Space / click"
    if maxScroll > 0 then
        footer = (scroll < maxScroll - 1)
            and "Scroll  ·  wheel / W S"
            or "Continue  ·  Enter / Space / click"
        -- Tiny scroll thumb.
        local trackH = viewH
        local thumbH = math.max(18, trackH * (viewH / (contentH + 1)))
        local thumbT = (maxScroll > 0) and (scroll / maxScroll) or 0
        local trackX = px + panelW - 18
        love.graphics.setColor(0.35, 0.22, 0.12, 0.35)
        love.graphics.rectangle("fill", trackX, viewTop, 3, trackH, 1, 1)
        love.graphics.setColor(0.28, 0.16, 0.08, 0.7)
        love.graphics.rectangle(
            "fill",
            trackX,
            viewTop + (trackH - thumbH) * thumbT,
            3,
            thumbH,
            1,
            1
        )
    end
    drawInkText(
        footerFont,
        footer,
        textX,
        footerY,
        textW,
        "center"
    )
    love.graphics.setColor(1, 1, 1, 1)
end

function flow.drawPause(state)
    local sw, sh = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, 0.62)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    local body = state.hudBodyFont or state.hudSubtitleFont
    local titleFont = state.hudTitleFont or state.hudLabelFont
    local lines = {
        "Resume   ·  Esc",
        "Restart  ·  R",
        "Quit     ·  Q",
    }
    local step = lineStep(body, 8)
    local wantW = 420
    local wantH = 48 + ui_font.getHeight(titleFont) + GAP + #lines * step + 36
    local px, py, panelW, panelH = fitPanel(sw, sh, wantW, wantH)
    drawParchment(px, py, panelW, panelH)
    local y = py + 32
    drawInkText(titleFont, "Paused", px + 24, y, panelW - 48, "center")
    y = y + ui_font.getHeight(titleFont) + GAP
    for _, line in ipairs(lines) do
        drawInkText(body, line, px + 24, y, panelW - 48, "center")
        y = y + step
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function flow.drawVictory(state)
    local sw, sh = love.graphics.getDimensions()
    -- Title uses mid display size — timer font (80) wraps and collides with body.
    local titleFont = state.hudTitleFont or state.hudLabelFont or state.hudTimerFont
    local body = state.hudBodyFont or state.hudHelpFont
    local footerFont = state.hudHelpFont or body
    local timeLeft = state.countdown and state.countdown:format() or "0:00"

    love.graphics.setColor(0.05, 0.08, 0.04, 0.35)
    love.graphics.rectangle("fill", 0, 0, sw, sh * 0.18)
    love.graphics.rectangle("fill", 0, sh * 0.78, sw, sh * 0.22)
    love.graphics.setColor(0.08, 0.1, 0.06, 0.22)
    love.graphics.rectangle("fill", 0, 0, sw * 0.12, sh)
    love.graphics.rectangle("fill", sw * 0.88, 0, sw * 0.12, sh)

    local titleLines = {
        "THE WELL IS",
        "CLEANSED",
    }
    local bodyLines = {
        "Time remaining  " .. timeLeft,
        "The infection is broken. The courtyard breathes again.",
    }
    local footer = "R  Descend Again     Esc  Quit"
    local pad = 28
    local gapTitle = 18
    local gapBody = 10
    local gapFooter = 20
    local panelW = math.min(640, sw - PANEL_MARGIN * 2)
    local textW = panelW - pad * 2
    local contentH = 0
    for _, line in ipairs(titleLines) do
        contentH = contentH + blockHeight(titleFont, line, textW)
    end
    contentH = contentH + gapTitle
    for _, line in ipairs(bodyLines) do
        contentH = contentH + blockHeight(body, line, textW) + gapBody
    end
    contentH = contentH + gapFooter + blockHeight(footerFont, footer, textW)
    local panelH = contentH + pad * 2
    local px, py
    px, py, panelW, panelH = fitPanel(sw, sh, panelW, panelH)
    textW = panelW - pad * 2

    love.graphics.setColor(0.06, 0.08, 0.05, 0.55)
    love.graphics.rectangle("fill", px, py, panelW, panelH, 8, 8)
    love.graphics.setColor(0.95, 0.97, 0.88, 0.18)
    love.graphics.rectangle("fill", px, py, panelW, panelH, 8, 8)
    love.graphics.setColor(1, 1, 1, 0.14)
    love.graphics.rectangle("line", px + 1, py + 1, panelW - 2, panelH - 2, 8, 8)

    local y = py + pad
    for _, line in ipairs(titleLines) do
        flow.printfShadow(
            titleFont,
            line,
            px + pad,
            y,
            textW,
            "center",
            0.12,
            0.18,
            0.1,
            1
        )
        y = y + blockHeight(titleFont, line, textW)
    end
    y = y + gapTitle
    for i, line in ipairs(bodyLines) do
        flow.printfShadow(
            body,
            line,
            px + pad,
            y,
            textW,
            "center",
            0.2,
            0.28,
            0.14,
            0.95
        )
        y = y + blockHeight(body, line, textW)
        if i < #bodyLines then
            y = y + gapBody
        end
    end
    y = y + gapFooter
    flow.printfShadow(
        footerFont,
        footer,
        px + pad,
        y,
        textW,
        "center",
        0.22,
        0.28,
        0.16,
        0.85
    )
    love.graphics.setColor(1, 1, 1, 1)
end

function flow.drawExtract(state)
    local sw, sh = love.graphics.getDimensions()
    local titleFont = state.hudTitleFont or state.hudLabelFont or state.hudTimerFont
    local body = state.hudBodyFont or state.hudHelpFont
    local footerFont = state.hudHelpFont or body
    local nestsMod = require "scripts.nests"
    local reason = state.extractReason == "abyss"
        and "You fell into the abyss."
        or "Plague tolerance exhausted."
    local lines = {
        reason,
        string.format(
            "Potions + Well remaining: %d",
            nestsMod.remaining(state.nests)
        ),
    }
    local footer = "R  Descend Again     Esc  Quit"
    local pad = 28
    local gap = 14
    local wantW = 560
    local textW = wantW - pad * 2
    local contentH = blockHeight(titleFont, "EXTRACTED", textW) + gap
    for _, line in ipairs(lines) do
        contentH = contentH + blockHeight(body, line, textW) + 8
    end
    contentH = contentH + gap + blockHeight(footerFont, footer, textW)
    local wantH = contentH + pad * 2
    local px, py, panelW, panelH = fitPanel(sw, sh, wantW, wantH)
    textW = panelW - pad * 2
    drawParchment(px, py, panelW, panelH)
    local y = py + pad
    drawInkText(titleFont, "EXTRACTED", px + pad, y, textW, "center")
    y = y + blockHeight(titleFont, "EXTRACTED", textW) + gap
    for _, line in ipairs(lines) do
        drawInkText(body, line, px + pad, y, textW, "center")
        y = y + blockHeight(body, line, textW) + 8
    end
    y = y + gap * 0.5
    drawInkText(footerFont, footer, px + pad, y, textW, "center")
    love.graphics.setColor(1, 1, 1, 1)
end

function flow.fountainFocus()
    return FOUNTAIN_X, FOUNTAIN_Y
end

return flow
