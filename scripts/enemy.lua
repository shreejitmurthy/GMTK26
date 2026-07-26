-- Enemy: Windfield collider owns position; soft barrier + EnemyHit hurtbox.
-- Shared locomotion + typed AI (chaser / fleer / keeper / ranger).

require "scripts.actor"
local physics = require "scripts.physics"
local enemy_types = require "scripts.enemy_types"

enemy = {}
setmetatable(enemy, { __index = actor })

local DEFAULT_HIT_W = 14
local DEFAULT_HIT_H = 14
local DEFAULT_HP = 2
local HURT_FLASH_DURATION = 0.15
local ATTACK_WINDUP_DURATION = 0.18
local DEATH_DURATION = 0.2

local VISUAL_PROFILES = {
    chaser = {
        tint = { 0.82, 0.72, 0.62 },
        saturation = 0.38,
        originX = 16,
        originY = 32,
        gaitRate = 7.8,
        bob = 0.9,
        sway = 0.7,
        lean = math.rad(2.4),
        breath = 0.004,
        breathRate = 0.7,
        attackScale = 0.02,
    },
    fleer = {
        tint = { 0.70, 0.78, 0.61 },
        saturation = 0.32,
        originX = 17,
        originY = 25,
        gaitRate = 11.5,
        bob = 0.32,
        sway = 0.85,
        lean = math.rad(1.4),
        breath = 0.002,
        breathRate = 1.0,
        attackScale = 0.015,
    },
    keeper = {
        tint = { 0.78, 0.67, 0.57 },
        saturation = 0.28,
        originX = 17,
        originY = 32,
        gaitRate = 4.4,
        bob = 0.62,
        sway = 0.42,
        lean = math.rad(0.9),
        breath = 0.006,
        breathRate = 0.5,
        attackScale = 0.025,
        landingSquash = 0.025,
    },
    ranger = {
        tint = { 0.72, 0.62, 0.78 },
        saturation = 0.36,
        originX = 16.5,
        originY = 32,
        gaitRate = 5.4,
        bob = 0.22,
        sway = 0.28,
        lean = math.rad(0.7),
        breath = 0.003,
        breathRate = 0.6,
        attackScale = 0.055,
    },
}

local enemyShader = nil
local enemyShaderFailed = false

local function getEnemyShader()
    if enemyShader or enemyShaderFailed then
        return enemyShader
    end
    local ok, shader = pcall(love.graphics.newShader, [[
        extern vec3 enemyTint;
        extern number enemySaturation;
        extern vec3 enemyFlash;
        extern number enemyFlashAmount;

        vec4 effect(vec4 color, Image texture, vec2 textureCoords, vec2 screenCoords)
        {
            vec4 pixel = Texel(texture, textureCoords);
            number grey = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
            vec3 treated = mix(vec3(grey), pixel.rgb, enemySaturation);
            treated *= enemyTint;
            treated = mix(treated, enemyFlash, enemyFlashAmount);
            return vec4(treated, pixel.a) * color;
        }
    ]])
    if not ok then
        enemyShaderFailed = true
        print("[enemy] warning: colour-treatment shader unavailable: " .. tostring(shader))
        return nil
    end
    enemyShader = shader
    return enemyShader
end

local function loadEnemyImage(path)
    if not path or not love.filesystem.getInfo(path) then
        return nil
    end
    local ok, image = pcall(love.graphics.newImage, path)
    if not ok then
        print(string.format("[enemy] warning: could not load %s: %s", path, tostring(image)))
        return nil
    end
    image:setFilter("nearest", "nearest")
    return image
end

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
    e.attackWindupTimer = 0
    e.pendingAttack = false
    e.attackCooldownTimer = 0
    e.attackSerial = 0
    e.walkTime = (x * 0.013 + y * 0.017) % (math.pi * 2)
    e.visualTime = (x * 0.019 + y * 0.011) % (math.pi * 2)
    e.motionAmount = 0
    e.visualProfile = VISUAL_PROFILES[e.enemyType] or VISUAL_PROFILES.chaser
    e.hp = options.hp or DEFAULT_HP
    e.maxHp = e.hp
    e.dying = false
    e.deathTimer = 0
    e.deathDuration = DEATH_DURATION
    e.readyForRemoval = false
    e.dead = false

    e.img = loadEnemyImage(e.spritePath)

    -- Gameplay dimensions are explicit and never derived from presentation art.
    local hitW = options.hitW or DEFAULT_HIT_W
    local hitH = options.hitH or DEFAULT_HIT_H
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
    -- Unstick / AABB clamp first so we don't re-apply velocity from inside a wall.
    physics.clampEnemyToPlayable(self.collider)
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

--- Begin a presentation-only death; physics is destroyed after the fade.
function enemy:die()
    if self.dead or self.dying then
        return
    end
    self.dying = true
    self.deathTimer = self.deathDuration or DEATH_DURATION
    self.wantsMeleeAttack = false
    self.pendingAttack = false
    self.attackWindupTimer = 0
    self.attackFlash = 0
    if self.collider then
        self.collider:setLinearVelocity(0, 0)
    end
end

function enemy:updateDeath(dt)
    if not self.dying or self.dead then
        return
    end
    if self.collider then
        self.collider:setLinearVelocity(0, 0)
    end
    if self.hurtFlash and self.hurtFlash > 0 then
        self.hurtFlash = math.max(0, self.hurtFlash - dt)
    end
    self.deathTimer = math.max(0, (self.deathTimer or 0) - dt)
    if self.deathTimer <= 0 then
        self.readyForRemoval = true
    end
end

--- Finalize only outside actor iteration so no following actor is skipped.
function enemy:finishDeath()
    if self.dead or not self.readyForRemoval then
        return
    end
    self.dead = true
    if self.collider then
        physics.removeEnemyCollider(self.collider)
        self.collider:destroy()
        self.collider = nil
    end
    if self.hurtbox then
        self.hurtbox:destroy()
        self.hurtbox = nil
    end
    if state and state.onEnemyKilled then
        state:onEnemyKilled(self)
    elseif state and state.removeActor then
        state:removeActor(self)
    end
end

--- Hook for player sword hits. Simple HP: 2 hits → kill → +1s via state.
function enemy:onHitByPlayer()
    if self.dead or self.dying then
        return
    end
    local ex, ey = self.pos.x, self.pos.y
    self.hp = (self.hp or DEFAULT_HP) - 1
    self.hurtFlash = HURT_FLASH_DURATION
    print(string.format(
        "[hit] PlayerAttack hit %s (%s @ %.1f, %.1f) hp=%d",
        self.enemyType or "enemy",
        self.label or "enemy",
        ex,
        ey,
        self.hp
    ))
    if self.hp <= 0 then
        self:die()
    end
end

local function validMeleeTarget(self, player)
    if not self.wantsMeleeAttack or not player or not player.collider then
        return false
    end
    local px, py = player.collider:getX(), player.collider:getY()
    local dx, dy = self:vecToward(px, py)
    local distance = math.sqrt(dx * dx + dy * dy)
    return distance <= (self.meleeRange or 0)
        and self:hasLineOfSight(px, py)
end

--- Telegraph first, then apply close-range damage after the short windup.
function enemy:tryAttack(dt, player)
    self.attackCooldownTimer = math.max(
        0,
        (self.attackCooldownTimer or 0) - dt
    )

    if self.pendingAttack then
        self.attackWindupTimer = math.max(0, self.attackWindupTimer - dt)
        self.attackFlash = self.attackWindupTimer
        if self.attackWindupTimer > 0 then
            return
        end
        self.pendingAttack = false
        if not validMeleeTarget(self, player) then
            return
        end
        self.attackSerial = self.attackSerial + 1
        if player.onHitByEnemy then
            player:onHitByEnemy(self)
        else
            print(string.format(
                "[hit] %s hit player",
                self.enemyType or "enemy"
            ))
        end
        return
    end

    if self.attackCooldownTimer > 0 or not validMeleeTarget(self, player) then
        return
    end
    local px, py = player.collider:getX(), player.collider:getY()
    self:faceToward(px, py)
    self.attackCooldownTimer = self.meleeCooldown or 0.8
    self.pendingAttack = true
    self.attackWindupTimer = ATTACK_WINDUP_DURATION
    self.attackFlash = ATTACK_WINDUP_DURATION
end

function enemy:update(dt, player)
    if self.dead then
        return
    end
    if self.dying then
        self:updateDeath(dt)
        return
    end
    if self.hurtFlash and self.hurtFlash > 0 then
        self.hurtFlash = math.max(0, self.hurtFlash - dt)
    end
    enemy_types.update(self, dt, player)
    self:tryAttack(dt, player)
    self.visualTime = (self.visualTime or 0) + dt
    if self.collider then
        local vx, vy = self.collider:getLinearVelocity()
        local actualSpeed = math.sqrt(vx * vx + vy * vy)
        local referenceSpeed = math.max(1, self.speed or actualSpeed)
        local targetMotion = math.min(1, actualSpeed / referenceSpeed)
        if actualSpeed < 0.5 then
            targetMotion = 0
        end
        local smoothing = 1 - math.exp(-dt * 14)
        self.motionAmount = (self.motionAmount or 0)
            + (targetMotion - (self.motionAmount or 0)) * smoothing
        if targetMotion > 0 then
            local profile = self.visualProfile or VISUAL_PROFILES.chaser
            self.walkTime = (self.walkTime or 0)
                + dt * profile.gaitRate * (0.82 + targetMotion * 0.18)
        end
    end
    if self.collider then
        physics.clampEnemyToPlayable(self.collider)
    end
    self:syncHurtbox()
end

function enemy:syncHurtbox()
    if not self.hurtbox or not self.collider then
        return
    end
    self.hurtbox:setPosition(self.collider:getX(), self.collider:getY())
end

function enemy:syncFromCollider()
    if not self.collider then
        return
    end
    self.pos.x = self.collider:getX()
    self.pos.y = self.collider:getY()
    self.x = self.pos.x
    self.y = self.pos.y
    self:syncHurtbox()
end

function enemy:draw()
    if self.dead then
        return
    end
    local profile = self.visualProfile or VISUAL_PROFILES.chaser
    local flashing = self.hurtFlash and self.hurtFlash > 0
    local attacking = self.attackFlash and self.attackFlash > 0
    local deathProgress = 0
    if self.dying then
        deathProgress = 1 - (self.deathTimer or 0) / (self.deathDuration or DEATH_DURATION)
        deathProgress = math.max(0, math.min(1, deathProgress))
    end
    local alpha = 1 - deathProgress
    local deathScale = 1 - deathProgress * 0.75

    -- Movement presentation is driven only by current collider velocity. The
    -- blend decays smoothly after stopping while the gait phase stays frozen.
    local motion = self.motionAmount or 0
    local motionSuppression = 1
    if self.dying then
        motionSuppression = 0
    elseif flashing then
        motionSuppression = 0.08
    elseif attacking then
        motionSuppression = 0.16
    end
    local activeMotion = motion * motionSuppression
    local gait = self.walkTime or 0
    local step = math.sin(gait)
    local lift = math.abs(step)
    local bob = -lift * profile.bob * activeMotion
    local gaitX = step * profile.sway * activeMotion

    -- The chaser's second, slower rhythm creates a restrained uneven lurch.
    if self.enemyType == "chaser" then
        bob = bob - math.max(0, math.sin(gait * 0.5 + 0.8)) * 0.18 * activeMotion
    end

    local facing = self.facing or { x = 1, y = 0 }
    local lean = facing.x * profile.lean * activeMotion
        + step * math.rad(0.25) * activeMotion

    local effectActive = flashing or attacking or self.dying
    local idleWeight = effectActive and 0 or (1 - motion)
    local breath = math.sin(
        (self.visualTime or 0) * math.pi * 2 * profile.breathRate
    ) * profile.breath * idleWeight

    local squashX, squashY = 1, 1
    if flashing then
        local amount = math.max(0, math.min(1, self.hurtFlash / HURT_FLASH_DURATION))
        squashX = 1 + 0.14 * amount
        squashY = 1 - 0.18 * amount
    end

    local landingSquash = 0
    if profile.landingSquash and activeMotion > 0 then
        landingSquash = math.max(0, 1 - lift * 5)
            * profile.landingSquash
            * activeMotion
    end
    local anticipation = 0
    if attacking and not flashing then
        anticipation = math.max(
            0,
            math.min(1, self.attackFlash / ATTACK_WINDUP_DURATION)
        )
    end
    local attackScale = profile.attackScale * anticipation
    local scaleX = squashX
        * (1 + landingSquash * 0.6)
        * (1 + attackScale)
        * deathScale
    local scaleY = squashY
        * (1 + breath)
        * (1 - landingSquash)
        * (1 - attackScale)
        * deathScale
    local groundY = self.pos.y + self.hitH / 2

    -- Presentation-only shadow; fixed gameplay dimensions remain unchanged.
    love.graphics.setColor(0, 0, 0, 0.28 * alpha)
    love.graphics.ellipse(
        "fill",
        self.pos.x,
        groundY + 1,
        self.hitW * 0.55 * deathScale,
        math.max(2, self.hitH * 0.18 * deathScale)
    )

    local flashColor = { 0.8, 0.75, 0.62 }
    local flashAmount = 0
    if flashing then
        flashColor = { 0.88, 0.43, 0.38 }
        flashAmount = 0.78
    elseif attacking then
        -- Warm warning flash remains readable without restoring fantasy colour.
        local pulse = 0.5 + 0.5 * math.sin((self.attackFlash or 0) * 70)
        flashColor = { 0.9, 0.77, 0.47 }
        local baseAmount = self.enemyType == "ranger" and 0.52 or 0.38
        flashAmount = baseAmount + pulse * 0.12
    end
    local flipX = (self.facing and self.facing.x < 0) and -1 or 1

    love.graphics.push()
    love.graphics.translate(self.pos.x + gaitX, groundY + bob)
    love.graphics.rotate(lean)
    love.graphics.scale(flipX * scaleX, scaleY)
    if self.img then
        local shader = getEnemyShader()
        if shader then
            shader:send("enemyTint", profile.tint)
            shader:send("enemySaturation", profile.saturation)
            shader:send("enemyFlash", flashColor)
            shader:send("enemyFlashAmount", flashAmount)
            love.graphics.setShader(shader)
            love.graphics.setColor(1, 1, 1, alpha)
        else
            local tint = profile.tint
            love.graphics.setColor(tint[1], tint[2], tint[3], alpha)
        end
        love.graphics.draw(
            self.img,
            0,
            0,
            0,
            1,
            1,
            profile.originX or self.img:getWidth() / 2,
            profile.originY or self.img:getHeight()
        )
        love.graphics.setShader()
    else
        -- Missing or invalid PNG: retain the old readable type-colour body.
        local tint = profile.tint
        love.graphics.setColor(
            tint[1] + (flashColor[1] - tint[1]) * flashAmount,
            tint[2] + (flashColor[2] - tint[2]) * flashAmount,
            tint[3] + (flashColor[3] - tint[3]) * flashAmount,
            alpha
        )
        love.graphics.rectangle("fill", -self.hitW / 2, -self.hitH, self.hitW, self.hitH)
        love.graphics.setColor(1, 1, 1, 0.7 * alpha)
        love.graphics.circle("fill", facing.x * (self.hitW / 2 - 1.5), -self.hitH / 2, 1.5)
    end
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)

    if (DEBUG or physics.debug) and self.debugLetter then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(
            self.debugLetter,
            self.pos.x - 3,
            self.pos.y - self.hitH / 2 - 12
        )
    end
end
