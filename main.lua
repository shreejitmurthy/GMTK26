love.profiler = require "lib.profile"
require "scripts.dbg"

require "lib.spritesheet"
camera = require "lib.camera"

require "scripts.actor"
local physics = require "scripts.physics"
local countdown = require "scripts.countdown"
require "scripts.player"
require "scripts.sword"
require "scripts.slash_trail"
require "scripts.enemy"
local physics_selftest = require "scripts.physics_selftest"

local zoom = 2
ZOOM_MULT = 0.1
ZOOM_MAX = 2
ZOOM_MIN = 0.1

DEBUG = false

love.graphics.setDefaultFilter("nearest", "nearest")

GAME_STATE = {
    MAIN_MENU = 0,
    GAMEPLAY = 1,
    PAUSE_MENU = 2,
}

state = {
    actors = {},
    canvas = nil,
    gameState = GAME_STATE.GAMEPLAY,
    countdown = nil,
    extracted = false,
    hudTimerFont = nil,
    hudLabelFont = nil,
    hudHelpFont = nil,
}

-- STATE
function state:init(...)
    self.canvas = love.graphics.newCanvas()
    local args = { ... }
    for _, actor in ipairs(args) do
        self.actors[#self.actors + 1] = actor
    end
end

function state:getActor(label)
    for _, actor in ipairs(self.actors) do
        if actor.label == label then
            return actor
        end
    end
    return nil
end

--- Single gameplay entry for plague damage (timer = health).
--- opts.bypassIFrames: debug key may ignore invuln for testing.
--- Returns ok, remainingSeconds.
function state:applyPlayerDamage(amount, source, opts)
    opts = opts or {}
    if self.extracted or not self.countdown then
        return false, 0
    end

    local playerActor = self:getActor("player")
    if not opts.bypassIFrames
        and playerActor
        and (playerActor.hurtIFrame or 0) > 0
    then
        return false, self.countdown:getRemaining()
    end

    amount = amount or 0
    self.countdown:damage(amount)

    if playerActor and not opts.bypassIFrames then
        playerActor.hurtIFrame = playerActor.hurtIFrameDuration or player.HURT_IFRAME
    end

    if self.countdown:isExpired() then
        self.extracted = true
        self.countdown:pause()
        print("[countdown] EXTRACTED — plague time exhausted")
    end

    return true, self.countdown:getRemaining()
end

-- Frame order during gameplay:
--   1) actors setLinearVelocity / sync sensors (no manual pos writes)
--   2) physics.world:update(dt)
--   3) poll PlayerAttack :enter("EnemyHit") hit logs
--   4) actors sync visual pos from collider:getX/Y
--   5) camera follows synced player pos
function state:update(dt)
    if state.gameState == GAME_STATE.GAMEPLAY then
        local playerActor = self:getActor("player")

        -- Timer-as-health: always update (pulse decays even after extract).
        if self.countdown then
            self.countdown:update(dt)
            if not self.extracted and self.countdown:isExpired() then
                self.extracted = true
                self.countdown:pause()
                print("[countdown] EXTRACTED — plague time exhausted")
            end
        end

        -- Freeze player input / enemy AI once the company pulls you out.
        if not self.extracted then
            for _, actor in ipairs(self.actors) do
                if actor.label == "enemy" then
                    actor:update(dt, playerActor)
                else
                    actor:update(dt)
                end
            end
        elseif playerActor and playerActor.collider then
            playerActor.collider:setLinearVelocity(0, 0)
            for _, actor in ipairs(self.actors) do
                if actor.label == "enemy" and actor.collider then
                    actor.collider:setLinearVelocity(0, 0)
                end
            end
        end

        physics.update(dt)
        -- Safety net: kinematic enemies never resolve vs Wall — re-clamp every frame.
        physics.clampAllEnemiesToPlayable()

        if not self.extracted and playerActor and playerActor.pollAttackHits then
            playerActor:pollAttackHits()
        end

        for _, actor in ipairs(self.actors) do
            if actor.syncFromCollider then
                actor:syncFromCollider()
            end
        end

        if playerActor and cam then
            cam:lookAt(playerActor.pos.x, playerActor.pos.y)
        end
    end
end

function state:drawActors()
    local drawList = {}
    for index, sceneActor in ipairs(self.actors) do
        local depth = index
        if sceneActor.getDrawDepth then
            depth = sceneActor:getDrawDepth()
        elseif sceneActor.pos then
            depth = sceneActor.pos.y
        end
        drawList[#drawList + 1] = {
            actor = sceneActor,
            depth = depth,
            index = index,
        }
    end

    table.sort(drawList, function(a, b)
        if a.depth == b.depth then
            return a.index < b.index
        end
        return a.depth < b.depth
    end)

    for _, item in ipairs(drawList) do
        item.actor:draw()
    end
end

--- Soft edge tint when plague tolerance is nearly spent (ratio < 0.15).
local function drawPlagueEdgeTint(sw, sh, strength)
    if strength <= 0 then
        return
    end
    local edge = math.floor(math.min(sw, sh) * 0.12)
    local layers = 5
    for i = 0, layers - 1 do
        local t = i / layers
        local band = edge / layers
        local a = 0.07 * strength * (1 - t)
        love.graphics.setColor(0.55, 0.08, 0.06, a)
        love.graphics.rectangle("fill", 0, i * band, sw, band)
        love.graphics.rectangle("fill", 0, sh - (i + 1) * band, sw, band)
        love.graphics.rectangle("fill", i * band, edge, band, sh - 2 * edge)
        love.graphics.rectangle("fill", sw - (i + 1) * band, edge, band, sh - 2 * edge)
    end
end

function state:drawHud()
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local prevFont = love.graphics.getFont()

    -- Hero HUD: plague timer (health) top-center — dominant readout.
    if self.countdown then
        local ratio = self.countdown:getRatio()
        local dmgPulse, dmgAmount = self.countdown:getDamagePulse()

        if ratio < 0.15 and not self.extracted then
            local urgency = 1 - (ratio / 0.15)
            drawPlagueEdgeTint(sw, sh, urgency)
        end

        local r, g, b, a = 0.96, 0.90, 0.78, 1
        if ratio < 0.25 then
            local t = 1 - (ratio / 0.25)
            r = 0.96 + 0.04 * t
            g = 0.90 - 0.55 * t
            b = 0.78 - 0.65 * t
        end
        -- Damage flash: brief white → red over the digits + fuse.
        if dmgPulse > 0 then
            local flash = dmgPulse
            r = r + (1.0 - r) * flash * 0.85
            g = g + (0.25 - g) * flash
            b = b + (0.20 - b) * flash
            a = 1
        end

        local scale = 1
        if ratio < 0.1 and not self.extracted and dmgPulse <= 0 then
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 6)
            a = 0.65 + 0.35 * pulse
            scale = 1 + 0.04 * pulse
        elseif dmgPulse > 0 then
            scale = 1 + 0.06 * dmgPulse
        end

        local timerFont = self.hudTimerFont or prevFont
        local labelFont = self.hudLabelFont or prevFont
        love.graphics.setFont(timerFont)

        local text = self.countdown:format()
        local tw = timerFont:getWidth(text)
        local th = timerFont:getHeight()
        local cx = sw / 2
        local cy = 22

        love.graphics.push()
        love.graphics.translate(cx, cy)
        love.graphics.scale(scale, scale)
        love.graphics.setColor(0, 0, 0, 0.5 * a)
        love.graphics.print(text, -tw / 2 + 2, 2)
        love.graphics.setColor(r, g, b, a)
        love.graphics.print(text, -tw / 2, 0)
        love.graphics.pop()

        -- Fuse track: same resource as the clock (width = getRatio()), not a heart bar.
        local fuseW = 220
        local fuseH = 5
        local fuseX = cx - fuseW / 2
        local fuseY = cy + th * 0.92
        local filled = fuseW * ratio
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.rectangle("fill", fuseX - 1, fuseY - 1, fuseW + 2, fuseH + 2)
        love.graphics.setColor(r * 0.35, g * 0.28, b * 0.22, 0.7)
        love.graphics.rectangle("fill", fuseX, fuseY, fuseW, fuseH)
        if filled > 0 then
            love.graphics.setColor(r, g, b, 0.9 * a)
            love.graphics.rectangle("fill", fuseX, fuseY, filled, fuseH)
        end
        -- Segment ticks → timer/fuse metaphor (not a solid HP chunk bar).
        local segments = 6
        love.graphics.setColor(0.12, 0.08, 0.06, 0.55)
        for i = 1, segments - 1 do
            local tx = fuseX + (fuseW / segments) * i
            love.graphics.rectangle("fill", tx, fuseY - 1, 1, fuseH + 2)
        end

        love.graphics.setFont(labelFont)
        local label = "PLAGUE TOLERANCE"
        local lw = labelFont:getWidth(label)
        love.graphics.setColor(r, g, b, 0.55 * a)
        love.graphics.print(label, cx - lw / 2, fuseY + fuseH + 4)

        -- Floating damage readout near the timer (~0.4s via damagePulse).
        if dmgPulse > 0 and dmgAmount > 0 then
            love.graphics.setFont(labelFont)
            local floatText = string.format("-%.0fs", dmgAmount)
            local rise = (1 - dmgPulse) * 18
            love.graphics.setColor(1, 0.35, 0.28, dmgPulse)
            love.graphics.print(floatText, cx + tw * 0.42 * scale, cy + 4 - rise)
        end
    end

    if self.extracted then
        local msg = "EXTRACTED"
        if self.hudTimerFont then
            love.graphics.setFont(self.hudTimerFont)
        end
        local tw = love.graphics.getFont():getWidth(msg)
        local th = love.graphics.getFont():getHeight()
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 0, sh / 2 - th, sw, th * 2.4)
        love.graphics.setColor(0.95, 0.85, 0.7, 1)
        love.graphics.print(msg, (sw - tw) / 2, sh / 2 - th / 2)
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.setFont(self.hudHelpFont or prevFont)
        love.graphics.printf("Esc to quit", 0, sh / 2 + th * 0.7, sw, "center")
    end

    local playerActor = self:getActor("player")
    if not playerActor then
        love.graphics.setFont(prevFont)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    -- Secondary help: smaller, dimmer, bottom-left — must not compete with timer.
    local helpFont = self.hudHelpFont or prevFont
    love.graphics.setFont(helpFont)
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.print(
        string.format("pos %.0f, %.0f", playerActor.pos.x, playerActor.pos.y),
        10,
        sh - 40
    )
    love.graphics.print(
        "WASD/Arrows move · Space/Click swing · H -3s · F1 debug · F2 selftest · Esc quit",
        10,
        sh - 24
    )

    if physics.debug then
        love.graphics.setColor(1, 1, 1, 0.7)
        local vx, vy = playerActor:getVelocity()
        local speed = playerActor:getSpeed()
        love.graphics.print(
            string.format(
                "DEBUG | col %.0f,%.0f |v| %.2f",
                playerActor.collider:getX(),
                playerActor.collider:getY(),
                speed
            ),
            10,
            sh - 56
        )

        local counts = { chaser = 0, fleer = 0, keeper = 0, ranger = 0 }
        local nearest = nil
        local px, py = playerActor.pos.x, playerActor.pos.y
        for _, actor in ipairs(self.actors) do
            if actor.label == "enemy" then
                local t = actor.enemyType
                if counts[t] ~= nil then
                    counts[t] = counts[t] + 1
                end
                local dx, dy = actor.pos.x - px, actor.pos.y - py
                local d = math.sqrt(dx * dx + dy * dy)
                if not nearest or d < nearest then
                    nearest = d
                end
            end
        end
        love.graphics.print(
            string.format(
                "C:%d F:%d K:%d R:%d near %s",
                counts.chaser,
                counts.fleer,
                counts.keeper,
                counts.ranger,
                nearest and string.format("%.0f", nearest) or "-"
            ),
            10,
            sh - 72
        )
    end

    love.graphics.setFont(prevFont)
    love.graphics.setColor(1, 1, 1, 1)
end

function love.load()
    physics.init()

    -- Plague resistance window (seconds). Timer IS health.
    state.countdown = countdown.new({ duration = 90 })
    state.extracted = false
    state.hudTimerFont = love.graphics.newFont(56)
    state.hudLabelFont = love.graphics.newFont(12)
    state.hudHelpFont = love.graphics.newFont(13)

    local spawnX, spawnY = 200, 150
    physics.spawnTestArena(spawnX, spawnY)

    local playerActor = player:new(spawnX, spawnY)
    local swordActor = sword:new(playerActor)
    local trailBehind = slashTrail:new(playerActor, true)
    local trailFront = slashTrail:new(playerActor, false)
    -- Inside stub arena (center ~200,150); clear of interior wall blocks.
    local enemies = {
        enemy:new(120, 100, { type = "chaser" }),
        enemy:new(280, 100, { type = "chaser" }),
        enemy:new(120, 200, { type = "fleer" }),
        enemy:new(315, 120, { type = "keeper" }),
        -- Purple ranger starts behind the lower block so its LOS strafe is visible.
        enemy:new(280, 200, { type = "ranger" }),
    }
    cam = camera(playerActor.pos.x, playerActor.pos.y, zoom)

    -- Sword and its split ribbon layers are separate coordinated scene actors.
    state:init(playerActor, swordActor, trailBehind, trailFront, unpack(enemies))

    -- Combat → countdown: player hits call into state (keeps drain logic centralized).
    playerActor.applyDamage = function(amount, source, opts)
        return state:applyPlayerDamage(amount, source, opts)
    end

    physics_selftest.run(playerActor, enemies)
end

function love.update(dt)
    state:update(dt)
end

function love.draw()
    love.graphics.setBackgroundColor(0.5, 0.5, 0.5)

    cam:attach()
    physics.drawWalls()
    state:drawActors()
    physics.drawDebug()
    cam:detach()

    state:drawHud()
end

local function startPlayerSwingAt(screenX, screenY)
    local playerActor = state:getActor("player")
    if not playerActor or not playerActor.startSwing then
        return
    end

    local worldX, worldY = screenX, screenY
    if cam then
        worldX, worldY = cam:worldCoords(screenX, screenY)
    end
    playerActor:startSwing(worldX, worldY)
end

function love.keypressed(k)
    if k == "escape" then
        love.event.quit()
    elseif k == "f1" or k == "`" then
        local on = physics.toggleDebug()
        DEBUG = on
        print("[physics] debug draw: " .. (on and "ON" or "OFF"))
    elseif k == "f2" then
        local enemies = {}
        for _, actor in ipairs(state.actors) do
            if actor.label == "enemy" then
                enemies[#enemies + 1] = actor
            end
        end
        physics_selftest.run(state:getActor("player"), enemies)
    elseif k == "h" then
        -- Debug plague damage (bypasses i-frames for tuning).
        local ok, left = state:applyPlayerDamage(3, "debug", { bypassIFrames = true })
        if ok then
            print(string.format("[countdown] damage 3.0 → %.1fs left", left))
        end
    elseif k == "space" then
        if not state.extracted then
            startPlayerSwingAt(love.mouse.getPosition())
        end
    end
end

function love.mousepressed(x, y, button)
    if button == 1 and not state.extracted then
        startPlayerSwingAt(x, y)
    end
end
