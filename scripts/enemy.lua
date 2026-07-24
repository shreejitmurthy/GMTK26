-- Idle enemy: Windfield collider owns position; solid body + EnemyHit sensor hurtbox.

require "scripts.actor"
local physics = require "scripts.physics"

enemy = {}
setmetatable(enemy, { __index = actor })

local DEFAULT_HIT_W = 14
local DEFAULT_HIT_H = 14

function enemy:new(x, y)
    x = x or 200
    y = y or 150

    local e = actor:new(x, y, "enemy")
    setmetatable(e, { __index = enemy })

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
    e.collider = physics.newEnemyCollider(x - hitW / 2, y - hitH / 2, hitW, hitH, 2)
    e.collider:setObject(e)

    -- Hurtbox sensor (no solid push); same footprint, synced to solid body.
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

--- Idle: keep hurtbox glued to solid collider (no drift).
function enemy:update(dt)
    self:syncHurtbox()
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
        -- Distinct from player.png placeholder (also red).
        love.graphics.setColor(0.25, 0.45, 0.7, 1)
        love.graphics.rectangle(
            "fill",
            self.pos.x - self.hitW / 2,
            self.pos.y - self.hitH / 2,
            self.hitW,
            self.hitH
        )
        love.graphics.setColor(1, 1, 1, 1)
    end
end
