love.profiler = require "lib.profile"
require "scripts.dbg"

require "lib.spritesheet"
wf = require "lib.windfield"
camera = require "lib.camera"

require "scripts.actor"

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
        self.actors[#self.actors+1] = actor
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

function state:update(dt)
    if state.gameState == GAME_STATE.GAMEPLAY then
        for _, actor in ipairs(self.actors) do
            actor:update(dt)
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

function state:drawPlayerPosition()
    local playerActor = self:getActor("player")
    if playerActor then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(
            string.format("Player position: %.1f, %.1f", playerActor.pos.x, playerActor.pos.y),
            10,
            10
        )
    end
end

-- function state:drawPauseMenu()
--     love.graphics.setColor(0, 0, 0, 0.5)
--     love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

--     love.graphics.setColor(1, 1, 1)
--     love.graphics.printf("Game Paused", 0, love.graphics.getHeight() / 2, love.graphics.getWidth(), "center")
-- end

-- PLAYER

player = {}
setmetatable(player, {__index = actor})

function player:new(x, y)
    local k = actor.new(self, 350, 200, "player")
    setmetatable(k, {__index = player})
    -- Basic rectangle player asset. Can implement animations pre easily.
    k.img = love.graphics.newImage("res/images/player.png")
    k.pos = {x = x or 100, y = y or 100}
    k.x = k.pos.x
    k.y = k.pos.y
    k.speed = 50
    return k
end

function player:update(dt)
    -- self.rot = self.rot + math.rad(90) * dt

    if love.keyboard.isDown("left") then
        self.pos.x = self.pos.x - self.speed * dt
    elseif love.keyboard.isDown("right") then
        self.pos.x = self.pos.x + self.speed * dt
    end

    if love.keyboard.isDown("up") then
        self.pos.y = self.pos.y - self.speed * dt
    elseif love.keyboard.isDown("down") then
        self.pos.y = self.pos.y + self.speed * dt
    end

    self.x = self.pos.x
    self.y = self.pos.y
end

function player:draw()
    love.graphics.draw(self.img, self.pos.x, self.pos.y, 0, 1, 1, self.img:getWidth() / 2, self.img:getHeight() / 2)
end

function love.load()
    local playerActor = player:new()
    cam = camera(playerActor.pos.x, playerActor.pos.y, zoom)

    -- Push actors we want in the scene.
    -- This is currently initialising the player **when the game loads**. 
    -- In the future, we want to do this when the scene (room) is loaded (loading enemies at the start of a scene)
    state:init(
        playerActor
    )
end

function love.update(dt)
    state:update(dt)
end

function love.draw()
    love.graphics.setBackgroundColor(0.5, 0.5, 0.5)

    cam:attach()
    state:drawActors()
    cam:detach()

    state:drawPlayerPosition()
end

function love.keypressed(k)
    if k == "escape" then
        love.event.quit()
    end
end
