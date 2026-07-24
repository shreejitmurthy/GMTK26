-- Clean top-down player: Windfield collider owns position.
-- Temporary Space-held PlayerAttack sensor for hit detect (no sword / damage yet).

require "scripts.actor"
local physics = require "scripts.physics"

player = {}
setmetatable(player, { __index = actor })

local ATTACK_W = 18
local ATTACK_H = 14

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
    p.facing = { x = 1, y = 0 }
    p.attackHitbox = nil
    p.attackW = ATTACK_W
    p.attackH = ATTACK_H

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

function player:getAttackTopLeft()
    local fx, fy = self.facing.x, self.facing.y
    local len = math.sqrt(fx * fx + fy * fy)
    if len > 0 then
        fx, fy = fx / len, fy / len
    else
        fx, fy = 1, 0
    end

    local reach = (self.hitW / 2) + (self.attackW / 2) + 2
    local cx = self.collider:getX() + fx * reach
    local cy = self.collider:getY() + fy * reach
    return cx - self.attackW / 2, cy - self.attackH / 2
end

function player:enableAttackHitbox()
    if self.attackHitbox then
        return
    end
    local x, y = self:getAttackTopLeft()
    self.attackHitbox = physics.newSensor(x, y, self.attackW, self.attackH, "PlayerAttack")
    self.attackHitbox:setObject(self)
    self.attackHitbox:setType("kinematic")
end

function player:disableAttackHitbox()
    if not self.attackHitbox then
        return
    end
    self.attackHitbox:destroy()
    self.attackHitbox = nil
end

function player:syncAttackHitbox()
    if not self.attackHitbox then
        return
    end
    local x, y = self:getAttackTopLeft()
    self.attackHitbox:setPosition(x + self.attackW / 2, y + self.attackH / 2)
end

--- After physics.update: one log per EnemyHit enter.
function player:pollAttackHits()
    if not self.attackHitbox then
        return
    end
    if self.attackHitbox:enter("EnemyHit") then
        local data = self.attackHitbox:getEnterCollisionData("EnemyHit")
        local other = data and data.collider
        local enemyObj = other and other:getObject()
        local label = (enemyObj and enemyObj.label) or "?"
        local ex, ey = 0, 0
        if enemyObj and enemyObj.pos then
            ex, ey = enemyObj.pos.x, enemyObj.pos.y
        elseif other then
            ex, ey = other:getX(), other:getY()
        end
        print(string.format("[hit] PlayerAttack entered EnemyHit (%s @ %.1f, %.1f)", label, ex, ey))
    end
end

--- Step 1 of frame order: read input → normalize → setLinearVelocity.
--- Also toggles temporary Space attack sensor (create/destroy, no orphans).
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

    if input.x ~= 0 or input.y ~= 0 then
        self.facing.x = input.x
        self.facing.y = input.y
    end

    local vx, vy = player.normalizedVelocity(input.x, input.y, self.speed)
    self.collider:setLinearVelocity(vx, vy)

    if love.keyboard.isDown("space") then
        self:enableAttackHitbox()
        self:syncAttackHitbox()
    else
        self:disableAttackHitbox()
    end
end

--- Step 3 of frame order: copy collider position into draw/camera fields.
function player:syncFromCollider()
    self.pos.x = self.collider:getX()
    self.pos.y = self.collider:getY()
    self.x = self.pos.x
    self.y = self.pos.y
    self:syncAttackHitbox()
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
