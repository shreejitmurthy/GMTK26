love.profiler = require "lib.profile"
require "scripts.dbg"

require "lib.spritesheet"
camera = require "lib.camera"

require "scripts.actor"
local physics = require "scripts.physics"
require "scripts.player"
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
    gameState = GAME_STATE.GAMEPLAY
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
        for _, actor in ipairs(self.actors) do
            if actor.label == "enemy" then
                actor:update(dt, playerActor)
            else
                actor:update(dt)
            end
        end

        physics.update(dt)

        if playerActor and playerActor.pollAttackHits then
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
    for _, actor in ipairs(self.actors) do
        actor:draw()
    end
end

function state:drawHud()
    local playerActor = self:getActor("player")
    if not playerActor then
        return
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        string.format("Player position: %.1f, %.1f", playerActor.pos.x, playerActor.pos.y),
        10,
        10
    )
    love.graphics.print("Move: WASD / Arrows | Space/Click: swing | F1: physics debug | F2: selftest | Esc: quit", 10, 28)

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
            46
        )
        love.graphics.print(
            "Compare |v| while holding Right vs Up+Right — magnitudes should match.",
            10,
            64
        )
    end
end

function love.load()
    physics.init()

    local spawnX, spawnY = 200, 150
    physics.spawnTestArena(spawnX, spawnY)

    local playerActor = player:new(spawnX, spawnY)
    -- Inside stub arena (center ~200,150); clear of interior wall blocks.
    -- Temporary: all enemies chase for locomotion validation (Prompt 2: typed behaviors).
    local enemies = {
        enemy:new(120, 100),
        enemy:new(280, 100),
        enemy:new(120, 200),
    }
    cam = camera(playerActor.pos.x, playerActor.pos.y, zoom)

    -- Push actors we want in the scene (player + enemies).
    state:init(playerActor, unpack(enemies))

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
    elseif k == "space" then
        local playerActor = state:getActor("player")
        if playerActor and playerActor.startSwing then
            playerActor:startSwing()
        end
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then
        local playerActor = state:getActor("player")
        if playerActor and playerActor.startSwing then
            playerActor:startSwing()
        end
    end
end
