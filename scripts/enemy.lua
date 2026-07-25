-- Enemy: Windfield collider owns position; soft barrier + EnemyHit hurtbox.
-- Shared locomotion helpers here; typed behaviors come later (Prompt 2).

require "scripts.actor"
local physics = require "scripts.physics"

enemy = {}
setmetatable(enemy, { __index = actor })

local DEFAULT_HIT_W = 14
local DEFAULT_HIT_H = 14
local DEFAULT_SPEED = 70
local CHASE_STOP_DISTANCE = 20

--- Normalize direction, THEN apply speed (same pattern as player.normalizedVelocity).
local function normalizedVelocity(dx, dy, speed)
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then
        dx = dx / length
        dy = dy / length
    end
    return dx * speed, dy * speed
end

--- options may include behavior fields (speed, type) and physics soft-contact tuning.
function enemy:new(x, y, options)
    x = x or 200
    y = y or 150
    options = options or {}

    local e = actor:new(x, y, "enemy")
    setmetatable(e, { __index = enemy })

    e.speed = options.speed or DEFAULT_SPEED
    e.type = options.type or "idle"

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

--- Temporary chase for locomotion feel only. Prompt 2 replaces with typed behaviors.
function enemy:update(dt, player)
    if not player or not player.collider then
        self:stop(dt)
        return
    end

    local px, py = player.collider:getX(), player.collider:getY()
    local dx, dy = self:vecToward(px, py)
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > CHASE_STOP_DISTANCE then
        self:moveToward(px, py, self.speed, dt)
    else
        self:stop(dt)
    end
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
