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

-- Frame order during gameplay:
--   1) actors setLinearVelocity / sync sensors (no manual pos writes)
--   2) physics.world:update(dt)
--   3) poll PlayerAttack :enter("EnemyHit") hit logs
--   4) actors sync visual pos from collider:getX/Y
--   5) camera follows synced player pos
function state:update(dt)
    if state.gameState == GAME_STATE.GAMEPLAY then
        local playerActor = self:getActor("player")

        -- Timer-as-health ticks every gameplay frame until extract.
        if self.countdown and not self.extracted then
            self.countdown:update(dt)
            if self.countdown:isExpired() then
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

function state:drawHud()
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()

    -- Hero HUD: plague timer (health) top-center.
    if self.countdown then
        local font = self.hudTimerFont
        local prevFont = love.graphics.getFont()
        if font then
            love.graphics.setFont(font)
        end

        local text = self.countdown:format()
        local ratio = self.countdown:getRatio()
        local r, g, b, a = 0.95, 0.92, 0.85, 1
        if ratio < 0.25 then
            -- Warmer / redder under a quarter of plague resistance left.
            local t = 1 - (ratio / 0.25)
            r = 0.95 + 0.05 * t
            g = 0.92 - 0.55 * t
            b = 0.85 - 0.70 * t
        end
        local scale = 1
        if ratio < 0.1 and not self.extracted then
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 6)
            a = 0.65 + 0.35 * pulse
            scale = 1 + 0.04 * pulse
        end

        local tw = love.graphics.getFont():getWidth(text)
        local x = sw / 2
        local y = 28
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.scale(scale, scale)
        love.graphics.setColor(0, 0, 0, 0.45 * a)
        love.graphics.print(text, -tw / 2 + 2, 2)
        love.graphics.setColor(r, g, b, a)
        love.graphics.print(text, -tw / 2, 0)
        love.graphics.pop()

        if font then
            love.graphics.setFont(prevFont)
        end
    end

    if self.extracted then
        local msg = "EXTRACTED"
        local prevFont = love.graphics.getFont()
        if self.hudTimerFont then
            love.graphics.setFont(self.hudTimerFont)
        end
        local tw = love.graphics.getFont():getWidth(msg)
        local th = love.graphics.getFont():getHeight()
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 0, sh / 2 - th, sw, th * 2.4)
        love.graphics.setColor(0.95, 0.85, 0.7, 1)
        love.graphics.print(msg, (sw - tw) / 2, sh / 2 - th / 2)
        love.graphics.setFont(prevFont)
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.printf("Esc to quit", 0, sh / 2 + th * 0.7, sw, "center")
    end

    local playerActor = self:getActor("player")
    if not playerActor then
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    -- Debug / help stays lower-left so it does not compete with the timer.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        string.format("Player position: %.1f, %.1f", playerActor.pos.x, playerActor.pos.y),
        10,
        sh - 72
    )
    love.graphics.print(
        "Move: WASD / Arrows | Space/Click: swing | H: debug -3s | F1: physics debug | F2: selftest | Esc: quit",
        10,
        sh - 54
    )

    if physics.debug then
        local vx, vy = playerActor:getVelocity()
        local speed = playerActor:getSpeed()
        love.graphics.print(
            string.format(
                "DEBUG physics | collider: %.1f, %.1f | vel: %.1f, %.1f | |v|: %.2f",
                playerActor.collider:getX(),
                playerActor.collider:getY(),
                vx,
                vy,
                speed
            ),
            10,
            sh - 36
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
                "enemies C:%d F:%d K:%d R:%d | nearest: %s",
                counts.chaser,
                counts.fleer,
                counts.keeper,
                counts.ranger,
                nearest and string.format("%.1f", nearest) or "-"
            ),
            10,
            sh - 18
        )
    end
end

function love.load()
    physics.init()

    -- Plague resistance window (seconds). Timer IS health.
    state.countdown = countdown.new({ duration = 90 })
    state.extracted = false
    state.hudTimerFont = love.graphics.newFont(48)

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
        -- Debug plague damage (real enemy drain wires next).
        if state.countdown and not state.extracted then
            state.countdown:damage(3)
            print(string.format(
                "[countdown] damage 3.0 → %.1fs left",
                state.countdown:getRemaining()
            ))
            if state.countdown:isExpired() then
                state.extracted = true
                state.countdown:pause()
                print("[countdown] EXTRACTED — plague time exhausted")
            end
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
