love.profiler = require "lib.profile"
require "scripts.dbg"

sti = require "lib.sti"
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

local function clamp(value, minimum, maximum)
    if minimum > maximum then
        return (minimum + maximum) / 2
    end

    return math.max(minimum, math.min(maximum, value))
end

local function getMapBounds(map)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge

    for _, layer in ipairs(map.layers) do
        if layer.type == "tilelayer" then
            if layer.chunks then
                for _, chunk in ipairs(layer.chunks) do
                    local chunkMinX = layer.x + (chunk.x * map.tilewidth)
                    local chunkMinY = layer.y + (chunk.y * map.tileheight)
                    local chunkMaxX = chunkMinX + (chunk.width * map.tilewidth)
                    local chunkMaxY = chunkMinY + (chunk.height * map.tileheight)

                    minX = math.min(minX, chunkMinX)
                    minY = math.min(minY, chunkMinY)
                    maxX = math.max(maxX, chunkMaxX)
                    maxY = math.max(maxY, chunkMaxY)
                end
            else
                local layerMinX = layer.x
                local layerMinY = layer.y
                local layerMaxX = layerMinX + (layer.width * map.tilewidth)
                local layerMaxY = layerMinY + (layer.height * map.tileheight)

                minX = math.min(minX, layerMinX)
                minY = math.min(minY, layerMinY)
                maxX = math.max(maxX, layerMaxX)
                maxY = math.max(maxY, layerMaxY)
            end
        end
    end

    if minX == math.huge then
        minX = 0
        minY = 0
        maxX = map.width * map.tilewidth
        maxY = map.height * map.tileheight
    end

    return {
        minX = minX,
        minY = minY,
        maxX = maxX,
        maxY = maxY,
        centerX = (minX + maxX) / 2,
        centerY = (minY + maxY) / 2
    }
end

local function expandMapBounds(map, bounds)
    map.width = math.ceil((bounds.maxX - bounds.minX) / map.tilewidth)
    map.height = math.ceil((bounds.maxY - bounds.minY) / map.tileheight)
end

local function getMapDrawOffset()
    local scale = cam and cam.scale or 1
    local halfWidth = love.graphics.getWidth() / (2 * scale)
    local halfHeight = love.graphics.getHeight() / (2 * scale)

    return halfWidth - cam.x, halfHeight - cam.y, scale
end

GAME_STATE = {
    MAIN_MENU = 0,
    GAMEPLAY = 1,
    PAUSE_MENU = 2,
}

state = {
    actors = {},
    canvas = nil,
    map = nil,
    mapBounds = nil,
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
        if self.map then
            self.map:update(dt)
        end

        for _, actor in ipairs(self.actors) do
            actor:update(dt)
        end

        local playerActor = self:getActor("player")
        if playerActor and cam then
            local halfWidth = love.graphics.getWidth() / (2 * cam.scale)
            local halfHeight = love.graphics.getHeight() / (2 * cam.scale)
            local targetX = playerActor.pos.x
            local targetY = playerActor.pos.y

            if self.mapBounds then
                targetX = clamp(targetX, self.mapBounds.minX + halfWidth, self.mapBounds.maxX - halfWidth)
                targetY = clamp(targetY, self.mapBounds.minY + halfHeight, self.mapBounds.maxY - halfHeight)
            end

            cam:lookAt(targetX, targetY)
        end
    end
end

function state:drawMap()
    if self.map then
        local tx, ty, scale = getMapDrawOffset()
        self.map:draw(tx, ty, scale, scale)
    end
end

function state:drawActors()
    for _, actor in ipairs(self.actors) do
        actor:draw()
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
    state.map = sti("res/maps/map.lua")
    state.mapBounds = getMapBounds(state.map)
    expandMapBounds(state.map, state.mapBounds)

    cam = camera(state.mapBounds.centerX, state.mapBounds.centerY, zoom)

    -- Push actors we want in the scene.
    -- This is currently initialising the player **when the game loads**. 
    -- In the future, we want to do this when the scene (room) is loaded (loading enemies at the start of a scene)
    state:init(
        player:new(state.mapBounds.centerX, state.mapBounds.centerY)
    )
end

function love.update(dt)
    state:update(dt)
end

function love.draw()
    love.graphics.setBackgroundColor(0.5, 0.5, 0.5)

    state:drawMap()

    cam:attach()
    state:drawActors()
    cam:detach()
end

function love.keypressed(k)
    if k == "escape" then
        love.event.quit()
    end
end
