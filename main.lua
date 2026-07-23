love.profiler = require "lib.profile"
require "scripts.dbg"

require "lib.spritesheet"
camera = require "lib.camera"

require "scripts.actor"
local physics = require "scripts.physics"
require "scripts.player"
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
--   1) actors setLinearVelocity from input (no manual pos writes)
--   2) physics.world:update(dt)
--   3) actors sync visual pos from collider:getX/Y
--   4) camera follows synced player pos
function state:update(dt)
    if state.gameState == GAME_STATE.GAMEPLAY then
        for _, actor in ipairs(self.actors) do
            actor:update(dt)
        end

        physics.update(dt)

        for _, actor in ipairs(self.actors) do
            if actor.syncFromCollider then
                actor:syncFromCollider()
            end
        end

        local playerActor = self:getActor("player")
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
    love.graphics.print("Move: WASD / Arrows | F1: physics debug | F2: selftest | Esc: quit", 10, 28)

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
    cam = camera(playerActor.pos.x, playerActor.pos.y, zoom)

    -- Push actors we want in the scene.
    -- Currently initialising the player when the game loads.
    -- Later: spawn when the scene/room loads (enemies too).
    state:init(playerActor)

    physics_selftest.run(playerActor)
end

function love.update(dt)
    state:update(dt)
end

function love.draw()
    love.graphics.setBackgroundColor(0.5, 0.5, 0.5)

    cam:attach()
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
        physics_selftest.run(state:getActor("player"))
    end
end
