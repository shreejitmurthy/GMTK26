-- Clean top-down player: Windfield collider owns position.

require "scripts.actor"
local physics = require "scripts.physics"

player = {}
setmetatable(player, { __index = actor })

--- Pure helper for tests / movement: normalize direction, THEN apply speed.
function player.normalizedVelocity(dx, dy, speed)
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then
        dx = dx / length
        dy = dy / length
    end
    return dx * speed, dy * speed
end

function player:new(x, y)
    x = x or 200
    y = y or 150

    local p = actor:new(x, y, "player")
    setmetatable(p, { __index = player })

    p.img = love.graphics.newImage("res/images/player.png")
    p.speed = 120
    p.controls = {
        left  = { "a", "left" },
        right = { "d", "right" },
        up    = { "w", "up" },
        down  = { "s", "down" },
    }

    -- Slightly smaller than sprite for nicer wall sliding.
    local spriteW, spriteH = p.img:getWidth(), p.img:getHeight()
    local hitW = math.max(8, spriteW * 0.7)
    local hitH = math.max(8, spriteH * 0.7)
    p.hitW = hitW
    p.hitH = hitH

    -- BSG takes top-left; our pos is sprite/collider center.
    p.collider = physics.newPlayerCollider(x - hitW / 2, y - hitH / 2, hitW, hitH, 2)
    p.collider:setObject(p)

    p.pos = { x = p.collider:getX(), y = p.collider:getY() }
    p.x = p.pos.x
    p.y = p.pos.y

    return p
end

--- Step 1 of frame order: read input → normalize → setLinearVelocity.
--- (world:update happens in state; then syncFromCollider.)
function player:update(dt)
    local input = { x = 0, y = 0 }

    -- controls.* are key lists (ref2-style); unpack so both WASD and arrows register.
    if love.keyboard.isDown(unpack(self.controls.left)) then
        input.x = -1
    elseif love.keyboard.isDown(unpack(self.controls.right)) then
        input.x = 1
    end

    if love.keyboard.isDown(unpack(self.controls.up)) then
        input.y = -1
    elseif love.keyboard.isDown(unpack(self.controls.down)) then
        input.y = 1
    end

    local vx, vy = player.normalizedVelocity(input.x, input.y, self.speed)
    self.collider:setLinearVelocity(vx, vy)
end

--- Step 3 of frame order: copy collider position into draw/camera fields.
function player:syncFromCollider()
    self.pos.x = self.collider:getX()
    self.pos.y = self.collider:getY()
    self.x = self.pos.x
    self.y = self.pos.y
end

function player:getVelocity()
    return self.collider:getLinearVelocity()
end

function player:getSpeed()
    local vx, vy = self:getVelocity()
    return math.sqrt(vx * vx + vy * vy)
end

function player:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        self.img,
        self.pos.x,
        self.pos.y,
        0,
        1,
        1,
        self.img:getWidth() / 2,
        self.img:getHeight() / 2
    )
end
