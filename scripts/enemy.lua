-- Enemy: Windfield collider owns position; soft barrier + EnemyHit hurtbox.
-- Shared locomotion + typed AI (chaser / fleer / keeper).

require "scripts.actor"
local physics = require "scripts.physics"
local enemy_types = require "scripts.enemy_types"

enemy = {}
setmetatable(enemy, { __index = actor })

local DEFAULT_HIT_W = 14
local DEFAULT_HIT_H = 14

--- Normalize direction, THEN apply speed (same pattern as player.normalizedVelocity).
local function normalizedVelocity(dx, dy, speed)
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then
        dx = dx / length
        dy = dy / length
    end
    return dx * speed, dy * speed
end

--- options: { type = "chaser"|"fleer"|"keeper", AI overrides..., physics soft-contact... }
function enemy:new(x, y, options)
    x = x or 200
    y = y or 150
    options = options or {}

    local e = actor:new(x, y, "enemy")
    setmetatable(e, { __index = enemy })

    enemy_types.apply(e, options)

    if love.filesystem.getInfo("res/images/enemy.png") then
        e.img = love.graphics.newImage("res/images/enemy.png")
    end

    local hitW, hitH = DEFAULT_HIT_W, DEFAULT_HIT_H
    if e.img then
        local spriteW, spriteH = e.img:getWidth(), e.img:getHeight()
        hitW = math.max(8, spriteW * 0.7)
        hitH = math.max(8, spriteH * 0.7)
    end
    e.hitW = hitW
    e.hitH = hitH

    -- BSG takes top-left; our pos is sprite/collider center.
    e.collider = physics.newEnemyCollider(
        x - hitW / 2,
        y - hitH / 2,
        hitW,
        hitH,
        2,
        options
    )
    e.collider:setObject(e)

    -- This separate sensor follows the pushable body and handles attacks.
    e.hurtW = hitW
    e.hurtH = hitH
    e.hurtbox = physics.newSensor(x - e.hurtW / 2, y - e.hurtH / 2, e.hurtW, e.hurtH, "EnemyHit")
    e.hurtbox:setObject(e)
    e.hurtbox:setType("kinematic")

    e.pos = { x = e.collider:getX(), y = e.collider:getY() }
    e.x = e.pos.x
    e.y = e.pos.y

    return e
end

--- Soft-contact anchor must follow intentional AI motion every frame.
function enemy:refreshPushAnchor()
    self.collider.pushAnchorX, self.collider.pushAnchorY =
        self.collider:getX(), self.collider:getY()
end

function enemy:vecToward(tx, ty)
    local x, y = self.collider:getX(), self.collider:getY()
    return tx - x, ty - y
end

function enemy:vecAway(tx, ty)
    local dx, dy = self:vecToward(tx, ty)
    return -dx, -dy
end

function enemy:moveToward(tx, ty, speed, dt)
    speed = speed or self.speed
    local dx, dy = self:vecToward(tx, ty)
    local vx, vy = normalizedVelocity(dx, dy, speed)
    vx, vy = physics.constrainEnemyMotion(self.collider, vx, vy, dt, speed)
    self.collider:setLinearVelocity(vx, vy)
    self:refreshPushAnchor()
    self:syncHurtbox()
end

function enemy:moveAway(tx, ty, speed, dt)
    speed = speed or self.speed
    local dx, dy = self:vecAway(tx, ty)
    local vx, vy = normalizedVelocity(dx, dy, speed)
    vx, vy = physics.constrainEnemyMotion(self.collider, vx, vy, dt, speed)
    self.collider:setLinearVelocity(vx, vy)
    self:refreshPushAnchor()
    self:syncHurtbox()
end

function enemy:stop(dt)
    -- Still separate / unstick from walls while halted so packs do not fuse on the player.
    local x0, y0 = self.collider:getX(), self.collider:getY()
    local vx, vy = physics.constrainEnemyMotion(self.collider, 0, 0, dt, self.speed)
    self.collider:setLinearVelocity(vx, vy)
    local x1, y1 = self.collider:getX(), self.collider:getY()
    -- Refresh only when separation/unstick actually moved us; pure idle keeps the soft anchor.
    if vx ~= 0 or vy ~= 0 or x1 ~= x0 or y1 ~= y0 then
        self:refreshPushAnchor()
    end
    self:syncHurtbox()
end

function enemy:update(dt, player)
    enemy_types.update(self, dt, player)
end

function enemy:syncHurtbox()
    if not self.hurtbox then
        return
    end
    self.hurtbox:setPosition(self.collider:getX(), self.collider:getY())
end

function enemy:syncFromCollider()
    self.pos.x = self.collider:getX()
    self.pos.y = self.collider:getY()
    self.x = self.pos.x
    self.y = self.pos.y
    self:syncHurtbox()
end

function enemy:draw()
    if self.img then
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
    else
        local c = self.color or { 0.25, 0.45, 0.7 }
        love.graphics.setColor(c[1], c[2], c[3], 1)
        love.graphics.rectangle(
            "fill",
            self.pos.x - self.hitW / 2,
            self.pos.y - self.hitH / 2,
            self.hitW,
            self.hitH
        )
        love.graphics.setColor(1, 1, 1, 1)
    end

    if (DEBUG or physics.debug) and self.debugLetter then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(
            self.debugLetter,
            self.pos.x - 3,
            self.pos.y - self.hitH / 2 - 12
        )
    end
end
