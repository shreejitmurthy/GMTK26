-- Clean top-down player: Windfield collider owns position.
-- Decoupled sword swing moves PlayerAttack; damage/timer later.

require "scripts.actor"
local physics = require "scripts.physics"

player = {}
setmetatable(player, { __index = actor })

-- PlayerAttack sensor size (AABB approx of sword volume; rotated with swing).
local ATTACK_W = 22
local ATTACK_H = 8
local SWING_DURATION = 0.35
local SWING_STRETCH = math.rad(10)
local SWING_ARC = math.pi + SWING_STRETCH * 2
local SWING_START = -math.pi / 2 - SWING_STRETCH
local SWORD_LENGTH = 22
local SWING_WINDUP_CONTROL = 0.1
local SWING_END_WEIGHT = 0.2
local SWORD_HILT_GAP = 12
local SWORD_HORIZONTAL_REST_TILT = math.rad(15)
local SWORD_VERTICAL_REST_TILT = math.rad(35)
local ENEMY_HIT_FLASH_DURATION = 0.18

--- Pure helper for tests / movement: normalize direction, THEN apply speed.
function player.normalizedVelocity(dx, dy, speed)
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then
        dx = dx / length
        dy = dy / length
    end
    return dx * speed, dy * speed
end

--- Unit direction from a world-space origin to a target, with a stable fallback.
function player.directionToTarget(px, py, targetX, targetY, fallbackX, fallbackY)
    local dx, dy = targetX - px, targetY - py
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then
        return dx / length, dy / length
    end

    fallbackX, fallbackY = fallbackX or 1, fallbackY or 0
    local fallbackLength = math.sqrt(fallbackX * fallbackX + fallbackY * fallbackY)
    if fallbackLength > 0 then
        return fallbackX / fallbackLength, fallbackY / fallbackLength
    end
    return 1, 0
end

--- Weighted cut with a quintic endpoint correction for a gentle full stop.
function player.weightedSwingEase(t)
    t = math.max(0, math.min(1, t))
    local remaining = 1 - t
    local weightedSwing = 3 * remaining * remaining * t * SWING_WINDUP_CONTROL
        + 3 * remaining * t * t
        + t * t * t
    local cubicEaseOut = 1 - remaining * remaining * remaining
    local easedSwing =
        weightedSwing + (cubicEaseOut - weightedSwing) * SWING_END_WEIGHT

    -- The cubic already reaches zero velocity at t=1, but still has non-zero
    -- acceleration there. This correction keeps its opening motion unchanged
    -- while bringing both velocity and acceleration smoothly to zero.
    local stopCorrection =
        3 * (1 - SWING_END_WEIGHT) * (1 - SWING_WINDUP_CONTROL)
    return easedSwing
        + stopCorrection * t * t * t * remaining * remaining
end

--- Radial sword angle for an already-eased swing value.
function player.swingAngle(baseAngle, easedProgress)
    easedProgress = math.max(0, math.min(1, easedProgress))
    return baseAngle + SWING_START + SWING_ARC * easedProgress
end

--- One continuous turnover keeps the blade on the outside of the hand arc.
function player.wristAngle(baseAngle, arcProgress)
    arcProgress = math.max(0, math.min(1, arcProgress))
    -- Vertical swings finish farther off their straight-behind axis so the
    -- sword rests on a readable diagonal instead of nearly vertical.
    local verticalWeight = math.sin(baseAngle) ^ 2
    local restTilt = SWORD_HORIZONTAL_REST_TILT
        + (SWORD_VERTICAL_REST_TILT - SWORD_HORIZONTAL_REST_TILT) * verticalWeight
    local wristStartAngle = -math.pi + restTilt
    local wristTurn = math.pi * 2 - restTilt * 2
    return baseAngle + wristStartAngle + wristTurn * arcProgress
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
    -- Cardinal components use -1/1: left/right on x, up/down on y.
    -- Keep facing as an alias while attack code migrates to the direction vector.
    p.direction = { x = 1, y = 0 }
    p.facing = p.direction
    p.aimDirection = { x = 1, y = 0 }
    p.attackHitbox = nil
    p.attackW = ATTACK_W
    p.attackH = ATTACK_H

    -- Decoupled swing (independent of player body sprite).
    p.swinging = false
    p.swingT = 0
    p.swingDuration = SWING_DURATION
    p.swingBaseAngle = 0
    p.swingDirection = 1
    p.nextSwingDirection = 1
    p.swingSerial = 0
    p.hasSwung = false
    p.swingHitEnemies = {}
    p.enemyHitCount = 0
    p.enemyHitFlash = 0
    p.attackPose = {
        angle = 0,
        orbitAngle = 0,
        easedProgress = 0,
        progress = 0,
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

--- Enemy hit callback. The countdown-health system is not wired yet, so this
--- records the hit and gives immediate visual/console feedback.
function player:onHitByEnemy(source)
    self.enemyHitCount = self.enemyHitCount + 1
    self.enemyHitFlash = ENEMY_HIT_FLASH_DURATION
    print(string.format(
        "[hit] %s hit player (#%d)",
        (source and source.enemyType) or "enemy",
        self.enemyHitCount
    ))
end

--- Sword pose from swing progress (0..1). Angle+offset relative to facing at swing start.
function player:updateSwordPose(progress)
    local arcProgress = progress
    if self.swingDirection < 0 then
        arcProgress = 1 - progress
    end

    local orbitAngle = player.swingAngle(self.swingBaseAngle, arcProgress)
    local bladeAngle = player.wristAngle(self.swingBaseAngle, arcProgress)
    local bodyRadius = math.max(self.hitW, self.hitH) / 2
    local reach = bodyRadius + SWORD_HILT_GAP
    local px, py = self.collider:getX(), self.collider:getY()

    self.attackPose.angle = bladeAngle
    self.attackPose.orbitAngle = orbitAngle
    self.attackPose.easedProgress = progress
    self.attackPose.progress = arcProgress
    self.attackPose.baseX = px + math.cos(orbitAngle) * reach
    self.attackPose.baseY = py + math.sin(orbitAngle) * reach
    self.attackPose.x =
        self.attackPose.baseX + math.cos(bladeAngle) * self.attackPose.length / 2
    self.attackPose.y =
        self.attackPose.baseY + math.sin(bladeAngle) * self.attackPose.length / 2
    self.attackPose.tipX =
        self.attackPose.baseX + math.cos(bladeAngle) * self.attackPose.length
    self.attackPose.tipY =
        self.attackPose.baseY + math.sin(bladeAngle) * self.attackPose.length
end

--- Screen-space Y ordering: a hilt above the player draws behind it.
function player:isSwordBehind()
    return self.attackPose.baseY < self.pos.y
end

function player:enableAttackHitbox()
    if self.attackHitbox then
        return
    end
    local cx, cy = self.attackPose.x, self.attackPose.y
    self.attackHitbox = physics.newSensor(
        cx - self.attackW / 2,
        cy - self.attackH / 2,
        self.attackW,
        self.attackH,
        "PlayerAttack"
    )
    self.attackHitbox:setObject(self)
    self.attackHitbox:setType("kinematic")
    self.attackHitbox:setAngle(self.attackPose.angle)
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
    self.attackHitbox:setPosition(self.attackPose.x, self.attackPose.y)
    self.attackHitbox:setAngle(self.attackPose.angle)
end

--- Lock a swing toward a world-space mouse target.
function player:startSwing(targetX, targetY)
    if self.swinging then
        return
    end

    local px, py = self.collider:getX(), self.collider:getY()
    local fx, fy
    if targetX and targetY then
        fx, fy = player.directionToTarget(
            px,
            py,
            targetX,
            targetY,
            self.aimDirection.x,
            self.aimDirection.y
        )
    else
        fx, fy = player.directionToTarget(
            0,
            0,
            self.direction.x,
            self.direction.y,
            self.aimDirection.x,
            self.aimDirection.y
        )
    end

    self.aimDirection.x = fx
    self.aimDirection.y = fy
    self.swingDirection = self.nextSwingDirection
    self.nextSwingDirection = -self.nextSwingDirection
    self.swingSerial = self.swingSerial + 1
    self.hasSwung = true
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
    local timeProgress = math.min(1, self.swingT / self.swingDuration)
    local arcProgress = player.weightedSwingEase(timeProgress)
    self:updateSwordPose(arcProgress)
    self:syncAttackHitbox()

    if timeProgress >= 1 then
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
    if self.enemyHitFlash > 0 then
        self.enemyHitFlash = math.max(0, self.enemyHitFlash - dt)
    end
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
        self.direction.x = input.x
        self.direction.y = input.y
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
        local timeProgress = math.min(1, self.swingT / self.swingDuration)
        local arcProgress = player.weightedSwingEase(timeProgress)
        self:updateSwordPose(arcProgress)
        self:syncAttackHitbox()
    elseif self.hasSwung then
        -- Preserve the completed angle while keeping the held sword attached.
        self:updateSwordPose(self.attackPose.easedProgress)
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
    if self.enemyHitFlash > 0 then
        love.graphics.setColor(1, 0.45, 0.45, 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
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
    love.graphics.setColor(1, 1, 1, 1)
end
