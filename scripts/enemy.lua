-- Enemy: Windfield collider owns position; soft barrier + EnemyHit hurtbox.
-- Shared locomotion + typed AI (chaser / fleer / keeper / ranger).

require "scripts.actor"
local physics = require "scripts.physics"
local enemy_types = require "scripts.enemy_types"

enemy = {}
setmetatable(enemy, { __index = actor })

local DEFAULT_HIT_W = 14
local DEFAULT_HIT_H = 14
local HURT_FLASH_DURATION = 0.15
local ATTACK_FLASH_DURATION = 0.12

--- Normalize direction, THEN apply speed (same pattern as player.normalizedVelocity).
local function normalizedVelocity(dx, dy, speed)
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then
        dx = dx / length
        dy = dy / length
    end
    return dx * speed, dy * speed
end

--- options: { type = "chaser"|"fleer"|"keeper"|"ranger", AI overrides..., physics soft-contact... }
function enemy:new(x, y, options)
    x = x or 200
    y = y or 150
    options = options or {}

    local e = actor:new(x, y, "enemy")
    setmetatable(e, { __index = enemy })

    enemy_types.apply(e, options)
    e.facing = { x = 1, y = 0 }
    e.hurtFlash = 0
    e.attackFlash = 0
    e.attackCooldownTimer = 0
    e.attackSerial = 0

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
    e.collider.separationDistance = e.separationDistance
    e.collider.separationSpeed = e.separationSpeed

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

function enemy:updateFacingFromVelocity(vx, vy)
    local speed = math.sqrt(vx * vx + vy * vy)
    if speed > 1 then
        self.facing.x = vx / speed
        self.facing.y = vy / speed
    end
end

function enemy:faceToward(tx, ty)
    local dx, dy = self:vecToward(tx, ty)
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance > 0 then
        self.facing.x = dx / distance
        self.facing.y = dy / distance
    end
end

function enemy:applyVelocity(vx, vy)
    self.collider:setLinearVelocity(vx, vy)
    self:updateFacingFromVelocity(vx, vy)
    if math.abs(vx) > 0.01 or math.abs(vy) > 0.01 then
        self:refreshPushAnchor()
    end
    self:syncHurtbox()
end

function enemy:moveToward(tx, ty, speed, dt)
    speed = speed or self.speed
    local dx, dy = self:vecToward(tx, ty)
    local vx, vy = normalizedVelocity(dx, dy, speed)
    vx, vy = physics.constrainEnemyMotion(self.collider, vx, vy, dt, speed)
    self:applyVelocity(vx, vy)
end

function enemy:moveAway(tx, ty, speed, dt)
    speed = speed or self.speed
    local dx, dy = self:vecAway(tx, ty)
    local vx, vy = normalizedVelocity(dx, dy, speed)
    vx, vy = physics.constrainEnemyMotion(self.collider, vx, vy, dt, speed)
    self:applyVelocity(vx, vy)
end

function enemy:moveInDirection(dx, dy, speed, dt)
    speed = speed or self.speed
    local vx, vy = normalizedVelocity(dx, dy, speed)
    vx, vy = physics.constrainEnemyMotion(self.collider, vx, vy, dt, speed)
    self:applyVelocity(vx, vy)
end

--- Apply steering while guaranteeing that neighbour avoidance cannot turn a
--- retreat/reposition command into motion toward the protected target.
function enemy:moveWithoutApproaching(tx, ty, dx, dy, speed, dt)
    speed = speed or self.speed
    local vx, vy = normalizedVelocity(dx, dy, speed)
    vx, vy = physics.constrainEnemyMotion(self.collider, vx, vy, dt, speed)

    local towardX, towardY = self:vecToward(tx, ty)
    local targetDistance = math.sqrt(towardX * towardX + towardY * towardY)
    if targetDistance > 0 then
        towardX, towardY = towardX / targetDistance, towardY / targetDistance
        local closingSpeed = vx * towardX + vy * towardY
        if closingSpeed > 0 then
            vx = vx - towardX * closingSpeed
            vy = vy - towardY * closingSpeed
        end
    end
    self:applyVelocity(vx, vy)
end

function enemy:hasLineOfSight(tx, ty)
    return physics.hasLineOfSight(
        self.collider:getX(),
        self.collider:getY(),
        tx,
        ty
    )
end

--- Hard idle: zero kinematic velocity every idle frame (no separation drift).
function enemy:stop(dt)
    self.collider:setLinearVelocity(0, 0)
    self:syncHurtbox()
end

--- While holding near a target, use separation as a low-speed shuffle. Remove
--- motion toward the target so spreading cannot squeeze the player more tightly.
function enemy:holdApartFrom(tx, ty, dt)
    local vx, vy = physics.applyEnemySeparation(
        self.collider,
        0,
        0,
        self.separationDistance,
        self.separationSpeed
    )
    local dx, dy = self:vecToward(tx, ty)
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance > 0 then
        local towardX, towardY = dx / distance, dy / distance
        local towardSpeed = vx * towardX + vy * towardY
        if towardSpeed > 0 then
            vx = vx - towardX * towardSpeed
            vy = vy - towardY * towardSpeed
        end
    end

    local speed = math.sqrt(vx * vx + vy * vy)
    local maxSpeed = self.separationSpeed or 0
    if maxSpeed > 0 and speed > maxSpeed then
        vx, vy = vx / speed * maxSpeed, vy / speed * maxSpeed
    end
    vx, vy = physics.slideEnemyAgainstWalls(self.collider, vx, vy, dt)
    self:applyVelocity(vx, vy)
end

--- Hook for player sword hits. No HP/damage yet — flash only.
function enemy:onHitByPlayer()
    local ex, ey = self.pos.x, self.pos.y
    print(string.format(
        "[hit] PlayerAttack hit %s (%s @ %.1f, %.1f)",
        self.enemyType or "enemy",
        self.label or "enemy",
        ex,
        ey
    ))
    self.hurtFlash = HURT_FLASH_DURATION
end

--- Close-range attack hook. Countdown damage can be added in player:onHitByEnemy
--- later; for now the callback supplies visible feedback and a testable hit event.
function enemy:tryAttack(dt, player)
    self.attackCooldownTimer = math.max(
        0,
        (self.attackCooldownTimer or 0) - dt
    )
    if not self.wantsMeleeAttack
        or not player
        or not player.collider
        or self.attackCooldownTimer > 0
    then
        return
    end

    local px, py = player.collider:getX(), player.collider:getY()
    local dx, dy = self:vecToward(px, py)
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance > (self.meleeRange or 0) or not self:hasLineOfSight(px, py) then
        return
    end

    self.attackCooldownTimer = self.meleeCooldown or 0.8
    self.attackFlash = ATTACK_FLASH_DURATION
    self.attackSerial = self.attackSerial + 1
    if player.onHitByEnemy then
        player:onHitByEnemy(self)
    else
        print(string.format(
            "[hit] %s hit player",
            self.enemyType or "enemy"
        ))
    end
end

function enemy:update(dt, player)
    if self.hurtFlash and self.hurtFlash > 0 then
        self.hurtFlash = math.max(0, self.hurtFlash - dt)
    end
    if self.attackFlash and self.attackFlash > 0 then
        self.attackFlash = math.max(0, self.attackFlash - dt)
    end
    enemy_types.update(self, dt, player)
    self:tryAttack(dt, player)
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
    local flashing = self.hurtFlash and self.hurtFlash > 0
    local attacking = self.attackFlash and self.attackFlash > 0
    if self.img then
        local flipX = (self.facing and self.facing.x < 0) and -1 or 1
        if flashing then
            love.graphics.setColor(1, 0.45, 0.45, 1)
        elseif attacking then
            love.graphics.setColor(1, 0.85, 0.3, 1)
        else
            love.graphics.setColor(1, 1, 1, 1)
        end
        love.graphics.draw(
            self.img,
            self.pos.x,
            self.pos.y,
            0,
            flipX,
            1,
            self.img:getWidth() / 2,
            self.img:getHeight() / 2
        )
        love.graphics.setColor(1, 1, 1, 1)
    else
        local c = self.color or { 0.25, 0.45, 0.7 }
        if flashing then
            c = { 1, 0.45, 0.45 }
        elseif attacking then
            c = { 1, 0.85, 0.3 }
        end
        local flipX = (self.facing and self.facing.x < 0) and -1 or 1
        love.graphics.push()
        love.graphics.translate(self.pos.x, self.pos.y)
        love.graphics.scale(flipX, 1)
        love.graphics.setColor(c[1], c[2], c[3], 1)
        love.graphics.rectangle("fill", -self.hitW / 2, -self.hitH / 2, self.hitW, self.hitH)
        love.graphics.pop()
        -- Directional cue makes vertical as well as horizontal facing readable.
        local facing = self.facing or { x = 1, y = 0 }
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.circle(
            "fill",
            self.pos.x + facing.x * (self.hitW / 2 - 1.5),
            self.pos.y + facing.y * (self.hitH / 2 - 1.5),
            1.5
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
