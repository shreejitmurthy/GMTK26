-- Clean top-down player: Windfield collider owns position.
-- Decoupled sword swing moves PlayerAttack; damage/timer later.

require "scripts.actor"
local physics = require "scripts.physics"

player = {}
setmetatable(player, { __index = actor })

-- PlayerAttack sensor size (AABB approx of sword volume; rotated with swing).
local ATTACK_W = 22
local ATTACK_H = 8
local SWING_DURATION = 0.2
local SWING_ARC = math.rad(120)
local SWING_START = -math.rad(60)
local SWORD_LENGTH = 22

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

    -- Decoupled swing (independent of player body sprite).
    p.swinging = false
    p.swingT = 0
    p.swingDuration = SWING_DURATION
    p.swingBaseAngle = 0
    p.swingHitEnemies = {}
    p.sword = {
        angle = 0,
        x = 0,
        y = 0,
        baseX = 0,
        baseY = 0,
        tipX = 0,
        tipY = 0,
        length = SWORD_LENGTH,
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

--- Sword pose from swing progress (0..1). Angle+offset relative to facing at swing start.
function player:updateSwordPose(progress)
    local localAngle = SWING_START + SWING_ARC * progress
    local angle = self.swingBaseAngle + localAngle
    local reach = (self.hitW / 2) + 4
    local px, py = self.collider:getX(), self.collider:getY()
    local mid = reach + self.sword.length / 2

    self.sword.angle = angle
    self.sword.x = px + math.cos(angle) * mid
    self.sword.y = py + math.sin(angle) * mid
    self.sword.baseX = px + math.cos(angle) * reach
    self.sword.baseY = py + math.sin(angle) * reach
    self.sword.tipX = px + math.cos(angle) * (reach + self.sword.length)
    self.sword.tipY = py + math.sin(angle) * (reach + self.sword.length)
end

function player:enableAttackHitbox()
    if self.attackHitbox then
        return
    end
    local cx, cy = self.sword.x, self.sword.y
    self.attackHitbox = physics.newSensor(
        cx - self.attackW / 2,
        cy - self.attackH / 2,
        self.attackW,
        self.attackH,
        "PlayerAttack"
    )
    self.attackHitbox:setObject(self)
    self.attackHitbox:setType("kinematic")
    self.attackHitbox:setAngle(self.sword.angle)
end

function player:disableAttackHitbox()
    if not self.attackHitbox then
        return
    end
    self.attackHitbox:destroy()
    self.attackHitbox = nil
end

--- Place PlayerAttack on the current sword volume (not a static facing offset).
function player:syncAttackHitbox()
    if not self.attackHitbox then
        return
    end
    self.attackHitbox:setPosition(self.sword.x, self.sword.y)
    self.attackHitbox:setAngle(self.sword.angle)
end

--- Press Space / click: start short-lived swing. Swing moves PlayerAttack; damage/timer later.
function player:startSwing()
    if self.swinging then
        return
    end

    local fx, fy = self.facing.x, self.facing.y
    local len = math.sqrt(fx * fx + fy * fy)
    if len > 0 then
        fx, fy = fx / len, fy / len
    else
        fx, fy = 1, 0
    end

    self.swinging = true
    self.swingT = 0
    self.swingBaseAngle = math.atan2(fy, fx)
    self.swingHitEnemies = {}

    self:updateSwordPose(0)
    self:enableAttackHitbox()
    self:syncAttackHitbox()
end

function player:updateSwing(dt)
    if not self.swinging then
        return
    end

    self.swingT = self.swingT + dt
    local progress = math.min(1, self.swingT / self.swingDuration)
    self:updateSwordPose(progress)
    self:syncAttackHitbox()

    if progress >= 1 then
        self.swinging = false
        self:disableAttackHitbox()
    end
end

--- After physics.update: PlayerAttack enters EnemyHit → log once per enemy per swing.
function player:pollAttackHits()
    if not self.attackHitbox then
        return
    end
    if self.attackHitbox:enter("EnemyHit") then
        local data = self.attackHitbox:getEnterCollisionData("EnemyHit")
        local other = data and data.collider
        local enemyObj = other and other:getObject()
        if enemyObj and self.swingHitEnemies[enemyObj] then
            return
        end
        if enemyObj then
            self.swingHitEnemies[enemyObj] = true
            if enemyObj.onHitByPlayer then
                enemyObj:onHitByPlayer()
            else
                local label = enemyObj.label or "?"
                local ex, ey = 0, 0
                if enemyObj.pos then
                    ex, ey = enemyObj.pos.x, enemyObj.pos.y
                elseif other then
                    ex, ey = other:getX(), other:getY()
                end
                print(string.format("[hit] PlayerAttack entered EnemyHit (%s @ %.1f, %.1f)", label, ex, ey))
            end
        else
            print("[hit] PlayerAttack entered EnemyHit (?)")
        end
    end
end

--- Step 1 of frame order: read input → normalize → setLinearVelocity; advance swing.
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
    vx, vy = physics.applyEnemyResistance(self.collider, vx, vy, dt)
    self.collider:setLinearVelocity(vx, vy)

    self:updateSwing(dt)
end

--- Step 3 of frame order: copy collider position into draw/camera fields.
function player:syncFromCollider()
    self.pos.x = self.collider:getX()
    self.pos.y = self.collider:getY()
    self.x = self.pos.x
    self.y = self.pos.y
    -- Keep sword + PlayerAttack glued to body if we moved during the swing.
    if self.swinging then
        local progress = math.min(1, self.swingT / self.swingDuration)
        self:updateSwordPose(progress)
        self:syncAttackHitbox()
    end
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

    -- Placeholder sword: line along swing (decoupled from body sprite).
    if self.swinging then
        love.graphics.setColor(0.92, 0.88, 0.55, 1)
        love.graphics.setLineWidth(3)
        love.graphics.line(self.sword.baseX, self.sword.baseY, self.sword.tipX, self.sword.tipY)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
    end
end
