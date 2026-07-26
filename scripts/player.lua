-- Clean top-down player: Windfield collider owns position.
-- Decoupled sword swing moves PlayerAttack; hits drain plague countdown via state.

require "scripts.actor"
require "lib.spritesheet"
local physics = require "scripts.physics"

player = {}
setmetatable(player, { __index = actor })

-- PlayerAttack sensor size (AABB approx of sword volume; rotated with swing).
local ATTACK_W = 22
local ATTACK_H = 8
local SWING_DURATION = 0.35
local SWING_SETTLE_DURATION = 0.16
local SWING_STRETCH = math.rad(10)
local SWING_ARC = math.pi + SWING_STRETCH * 2
local SWING_START = -math.pi / 2 - SWING_STRETCH
local RIGHT_BOTTOM_SWING_LIMIT = 0.9
local SWORD_LENGTH = 22
local SWING_WINDUP_CONTROL = 0.1
local SWING_END_WEIGHT = 0.2
local SWORD_HILT_GAP = 0
local SWORD_HORIZONTAL_REST_TILT = math.rad(15)
local SWORD_VERTICAL_REST_TILT = math.rad(35)
local ENEMY_HIT_FLASH_DURATION = 0.18
local PLAYER_SHEET_PATH = "res/images/plagueDoctorSheet.png"
local PLAYER_MAX_FRAME_W = 25
local PLAYER_MAX_FRAME_H = 32
local PLAYER_FRAME_COUNT = 6
local PLAYER_SHEET_ROW_HEIGHT = 32
local PLAYER_RUN_FRAME_DELAY = 0.1
local PLAYER_IDLE_FRAME_DELAY = 0.3

-- Every row occupies 32 pixels in the combined image. Shorter frames are
-- bottom-aligned within that row, so their top offset includes the difference.
local PLAYER_ANIMATION_SPECS = {
    run = {
        right = { row = 1, width = 25, height = 32 },
        left = { row = 2, width = 25, height = 32 },
        down = { row = 3, width = 17, height = 30 },
        up = { row = 4, width = 17, height = 31 },
    },
    idle = {
        right = { row = 5, width = 20, height = 30 },
        left = { row = 6, width = 20, height = 30 },
        down = { row = 7, width = 19, height = 31 },
        -- Row eight is another up-facing idle until the art is corrected.
        up = { row = 8, width = 19, height = 31 },
    },
}

local function newDirectionalAnimation(baseSpritesheet, spec, delay)
    local rowTop = (spec.row - 1) * PLAYER_SHEET_ROW_HEIGHT
        + (PLAYER_SHEET_ROW_HEIGHT - spec.height)
    local spritesheet = baseSpritesheet:newView(
        spec.width,
        spec.height,
        0,
        rowTop
    )

    return {
        spritesheet = spritesheet,
        animation = spritesheet:newAnimation(
            { 1, 1 },
            { 1, PLAYER_FRAME_COUNT },
            delay
        ),
    }
end

local function newPlayerAnimations(spritesheet)
    local animations = { run = {}, idle = {} }

    for direction, spec in pairs(PLAYER_ANIMATION_SPECS.run) do
        animations.run[direction] =
            newDirectionalAnimation(spritesheet, spec, PLAYER_RUN_FRAME_DELAY)
    end
    for direction, spec in pairs(PLAYER_ANIMATION_SPECS.idle) do
        animations.idle[direction] =
            newDirectionalAnimation(spritesheet, spec, PLAYER_IDLE_FRAME_DELAY)
    end

    return animations
end

local function animationDirection(dx, dy)
    if math.abs(dx) > math.abs(dy) then
        return dx > 0 and "right" or "left"
    end
    return dy > 0 and "down" or "up"
end

-- Tunables: enemy hit drain (seconds) + invuln window after a hit.
player.HIT_DAMAGE_SECONDS = 5
player.HURT_IFRAME = 0.6
PLAYER_HIT_DAMAGE_SECONDS = player.HIT_DAMAGE_SECONDS
PLAYER_HURT_IFRAME = player.HURT_IFRAME

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

--- Eased arc progress with a fixed real-time terminal deceleration.
function player.swingProgress(elapsed, duration, settleDuration)
    elapsed = math.max(0, elapsed or 0)
    duration = math.max(0, duration or 0)
    settleDuration = math.max(0, settleDuration or SWING_SETTLE_DURATION)

    if settleDuration == 0 then
        if duration == 0 then
            return 1
        end
        return player.weightedSwingEase(math.min(1, elapsed / duration))
    end

    -- The main phase and fixed settle phase meet with matching velocity and
    -- acceleration. The tail's 2u - 2u^3 + u^4 motion only decelerates.
    local curveCutoff = 0
    if duration > 0 then
        curveCutoff = 2 * duration / (settleDuration + 2 * duration)
    end

    local curveProgress
    if duration > 0 and elapsed < duration then
        curveProgress = curveCutoff * elapsed / duration
    else
        local settleProgress = math.min(1, (elapsed - duration) / settleDuration)
        local deceleratingTail = 2 * settleProgress
            - 2 * settleProgress * settleProgress * settleProgress
            + settleProgress * settleProgress * settleProgress * settleProgress
        curveProgress =
            curveCutoff + (1 - curveCutoff) * deceleratingTail
    end

    return player.weightedSwingEase(curveProgress)
end

function player.swingTotalDuration(duration, settleDuration)
    return math.max(0, duration or 0)
        + math.max(0, settleDuration or SWING_SETTLE_DURATION)
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

    p.spritesheet = newSpritesheet(
        PLAYER_SHEET_PATH,
        PLAYER_MAX_FRAME_W,
        PLAYER_MAX_FRAME_H
    )
    p.img = p.spritesheet.image
    p.spriteW = PLAYER_MAX_FRAME_W
    p.spriteH = PLAYER_MAX_FRAME_H
    p.animations = newPlayerAnimations(p.spritesheet)
    p.animationDirection = "right"
    p.current_animation_data = p.animations.idle[p.animationDirection]
    p.current_animation = p.current_animation_data.animation
    p.current_spritesheet = p.current_animation_data.spritesheet
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
    p.swingSettleDuration = SWING_SETTLE_DURATION
    p.swingBaseAngle = 0
    p.swingDirection = 1
    p.nextSwingDirection = 1
    p.swingArcStart = 0
    p.swingArcEnd = 1
    p.swingSerial = 0
    p.hasSwung = false
    p.swingHitEnemies = {}
    p.enemyHitCount = 0
    p.enemyHitFlash = 0
    p.hurtIFrame = 0
    p.hitDamageSeconds = player.HIT_DAMAGE_SECONDS
    p.hurtIFrameDuration = player.HURT_IFRAME
    -- Set by gameplay (state:applyPlayerDamage) so combat drain stays centralized.
    p.applyDamage = nil
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
    local spriteW, spriteH = p.spriteW, p.spriteH
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

--- Enemy hit callback → plague countdown drain (via state.applyPlayerDamage).
--- I-frames: ignore hits while hurtIFrame > 0 (debug damage bypasses separately).
function player:onHitByEnemy(source)
    if (self.hurtIFrame or 0) > 0 then
        return
    end

    local amount = (source and source.attackDamageSeconds)
        or self.hitDamageSeconds
        or player.HIT_DAMAGE_SECONDS
    local remaining = nil
    if self.applyDamage then
        local ok, left = self.applyDamage(amount, source)
        if not ok then
            return
        end
        remaining = left
    end

    self.enemyHitCount = self.enemyHitCount + 1
    self.enemyHitFlash = ENEMY_HIT_FLASH_DURATION
    if remaining ~= nil then
        print(string.format(
            "[hit] %s hit player (#%d) → %.1fs left",
            (source and source.enemyType) or "enemy",
            self.enemyHitCount,
            remaining
        ))
    else
        print(string.format(
            "[hit] %s hit player (#%d)",
            (source and source.enemyType) or "enemy",
            self.enemyHitCount
        ))
    end
end

--- Sword pose from swing progress (0..1). Angle+offset relative to facing at swing start.
function player:updateSwordPose(progress)
    local arcStart = self.swingArcStart or 0
    local arcEnd = self.swingArcEnd or 1
    if self.swingDirection < 0 then
        arcStart, arcEnd = arcEnd, arcStart
    end
    local arcProgress = arcStart + (arcEnd - arcStart) * progress

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
    self.animationDirection = animationDirection(fx, fy)
    self.swingDirection = self.nextSwingDirection
    self.nextSwingDirection = -self.nextSwingDirection
    self.swingSerial = self.swingSerial + 1
    self.hasSwung = true
    self.swinging = true
    self.swingT = 0
    self.swingBaseAngle = math.atan2(fy, fx)
    self.swingArcStart = 0
    self.swingArcEnd = 1
    if fx > 0 and math.abs(fx) >= math.abs(fy) then
        -- For a rightward attack, progress 1 is the bottom endpoint. Pull both
        -- its hilt orbit and wrist turnover in while leaving the up endpoint.
        self.swingArcEnd = RIGHT_BOTTOM_SWING_LIMIT
    end
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
    local arcProgress =
        player.swingProgress(self.swingT, self.swingDuration, self.swingSettleDuration)
    self:updateSwordPose(arcProgress)
    self:syncAttackHitbox()

    local totalDuration =
        player.swingTotalDuration(self.swingDuration, self.swingSettleDuration)
    if self.swingT >= totalDuration then
        self.swinging = false
        self:disableAttackHitbox()
    end
end

local function pointInRotatedRect(px, py, cx, cy, halfW, halfH, angle)
    local dx, dy = px - cx, py - cy
    local c, s = math.cos(angle), math.sin(angle)
    local localX = dx * c + dy * s
    local localY = -dx * s + dy * c
    return math.abs(localX) <= halfW and math.abs(localY) <= halfH
end

local function swordOverlapsHurtbox(sx, sy, angle, attackW, attackH, hx, hy, hurtW, hurtH)
    local ahw, ahh = attackW / 2, attackH / 2
    local ehw, ehh = hurtW / 2, hurtH / 2
    local c, s = math.cos(angle), math.sin(angle)
    local hurtCorners = {
        { hx - ehw, hy - ehh },
        { hx + ehw, hy - ehh },
        { hx + ehw, hy + ehh },
        { hx - ehw, hy + ehh },
    }
    for i = 1, 4 do
        if pointInRotatedRect(
            hurtCorners[i][1],
            hurtCorners[i][2],
            sx,
            sy,
            ahw,
            ahh,
            angle
        ) then
            return true
        end
    end
    local swordCorners = {
        { sx + (-ahw) * c - (-ahh) * s, sy + (-ahw) * s + (-ahh) * c },
        { sx + (ahw) * c - (-ahh) * s, sy + (ahw) * s + (-ahh) * c },
        { sx + (ahw) * c - (ahh) * s, sy + (ahw) * s + (ahh) * c },
        { sx + (-ahw) * c - (ahh) * s, sy + (-ahw) * s + (ahh) * c },
    }
    for i = 1, 4 do
        local px, py = swordCorners[i][1], swordCorners[i][2]
        if math.abs(px - hx) <= ehw and math.abs(py - hy) <= ehh then
            return true
        end
    end
    -- Centers inside the other volume (covers full containment either way).
    if pointInRotatedRect(hx, hy, sx, sy, ahw, ahh, angle) then
        return true
    end
    if math.abs(sx - hx) <= ehw and math.abs(sy - hy) <= ehh then
        return true
    end
    return false
end

--- After physics.update: sword volume vs enemy hurtboxes → once per enemy per swing.
--- Tests live actors directly; kinematic EnemyHit sensors do not yield reliable enters.
function player:pollAttackHits()
    if not self.attackHitbox then
        return
    end

    local function applyHit(enemyObj)
        if not enemyObj or self.swingHitEnemies[enemyObj] then
            return
        end
        if enemyObj.dead or enemyObj.dying then
            return
        end
        self.swingHitEnemies[enemyObj] = true
        if enemyObj.onHitByPlayer then
            enemyObj:onHitByPlayer(self.swingSerial)
        else
            local label = enemyObj.label or "?"
            local ex, ey = 0, 0
            if enemyObj.pos then
                ex, ey = enemyObj.pos.x, enemyObj.pos.y
            end
            print(string.format(
                "[hit] PlayerAttack entered EnemyHit (%s @ %.1f, %.1f)",
                label,
                ex,
                ey
            ))
        end
    end

    local actors = rawget(_G, "state") and state.actors
    if not actors then
        return
    end

    local x = self.attackPose.x
    local y = self.attackPose.y
    local angle = self.attackPose.angle or 0
    for _, actor in ipairs(actors) do
        if actor.label == "enemy"
            and actor.hurtbox
            and not actor.dead
            and not actor.dying
        then
            local hx, hy = actor.hurtbox:getX(), actor.hurtbox:getY()
            if swordOverlapsHurtbox(
                x,
                y,
                angle,
                self.attackW,
                self.attackH,
                hx,
                hy,
                actor.hurtW or 14,
                actor.hurtH or 14
            ) then
                applyHit(actor)
            end
        end
    end
end

--- Step 1 of frame order: read input → normalize → setLinearVelocity; advance swing.
function player:update(dt)
    if self.enemyHitFlash > 0 then
        self.enemyHitFlash = math.max(0, self.enemyHitFlash - dt)
    end
    if self.hurtIFrame > 0 then
        self.hurtIFrame = math.max(0, self.hurtIFrame - dt)
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
        if not self.swinging then
            self.animationDirection = animationDirection(input.x, input.y)
        end
    end

    local animationState =
        (input.x ~= 0 or input.y ~= 0) and "run" or "idle"
    self.current_animation_data =
        self.animations[animationState][self.animationDirection]
    self.current_animation = self.current_animation_data.animation
    self.current_spritesheet = self.current_animation_data.spritesheet
    self.current_animation:update(dt)

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
        local arcProgress =
            player.swingProgress(self.swingT, self.swingDuration, self.swingSettleDuration)
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

--- Bottom of the sprite is the player's ground contact for scenery sorting.
function player:getGroundDepth()
    return self.pos.y + self.spriteH / 2
end

function player:draw()
    if self.enemyHitFlash > 0 then
        love.graphics.setColor(1, 0.45, 0.45, 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
    local frameWidth = self.current_spritesheet.frameWidth
    local frameHeight = self.current_spritesheet.frameHeight
    self.current_spritesheet:draw(
        self.current_animation,
        self.pos.x - frameWidth / 2,
        self.pos.y + self.spriteH / 2 - frameHeight
    )
    if physics.debug and self.attackHitbox then
        love.graphics.push()
        love.graphics.translate(self.attackPose.x, self.attackPose.y)
        love.graphics.rotate(self.attackPose.angle)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 0.25, 0.85, 0.95)
        love.graphics.rectangle(
            "line",
            -self.attackW / 2,
            -self.attackH / 2,
            self.attackW,
            self.attackH
        )
        love.graphics.pop()
    end
    love.graphics.setColor(1, 1, 1, 1)
end
