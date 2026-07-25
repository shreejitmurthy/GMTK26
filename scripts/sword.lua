-- Separate visible sword actor: exact during attacks, inertial while carried.

require "scripts.actor"

sword = {}
setmetatable(sword, { __index = actor })

local FRAME_SIZE = 16
local FIRST_FRAME_X = 0
local FIRST_FRAME_Y = 0
local SOURCE_BLADE_ANGLE = -math.pi / 4
local IDLE_FOLLOW_FREQUENCY = 45
local IDLE_LAYER_HYSTERESIS = 1

--- Exact critically damped response to a target that moved linearly this frame.
function sword.springFollowAxis(position, velocity, previousTarget, target, dt, frequency)
    if dt <= 0 then
        return position, velocity
    end

    local targetVelocity = (target - previousTarget) / dt
    local displacement = position - previousTarget + 2 * targetVelocity / frequency
    local relativeVelocity = velocity - targetVelocity
    local response = relativeVelocity + frequency * displacement
    local decay = math.exp(-frequency * dt)

    displacement = (displacement + response * dt) * decay
    relativeVelocity = (relativeVelocity - frequency * response * dt) * decay

    return target + displacement - 2 * targetVelocity / frequency,
        targetVelocity + relativeVelocity
end

function sword:new(owner)
    assert(owner, "sword:new requires an owner")

    local s = actor:new(owner.pos.x, owner.pos.y, "sword")
    setmetatable(s, { __index = sword })

    s.owner = owner
    s.img = love.graphics.newImage("res/images/sword_atlas.png")
    local atlasW, atlasH = s.img:getDimensions()
    s.frame = love.graphics.newQuad(
        FIRST_FRAME_X,
        FIRST_FRAME_Y,
        FRAME_SIZE,
        FRAME_SIZE,
        atlasW,
        atlasH
    )
    s.frameW = FRAME_SIZE
    s.frameH = FRAME_SIZE
    s.pos = { x = owner.pos.x, y = owner.pos.y }
    s.rotation = 0
    s.sludge_accumulation = 1;
    s.visible = true
    s.followVelocityX = 0
    s.followVelocityY = 0
    s.previousTargetX = nil
    s.previousTargetY = nil
    s.wasSwinging = false
    s.idleBehind = false

    s:syncFromOwner()
    return s
end

function sword:getUnitDirection()
    local direction = self.owner.direction
    local dx, dy = direction.x, direction.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length == 0 then
        return 1, 0
    end
    return dx / length, dy / length
end

--- Keep the held sword outside the edge of the player sprite.
function sword:getHeldDistance(dx, dy)
    local playerW = self.owner.spriteW or self.owner.img:getWidth()
    local playerH = self.owner.spriteH or self.owner.img:getHeight()
    local playerExtent = math.abs(dx) * playerW / 2 + math.abs(dy) * playerH / 2
    return playerExtent + self.frameW / 2
end

function sword:getTargetPose()
    if self.owner.hasSwung then
        return self.owner.attackPose.x,
            self.owner.attackPose.y,
            self.owner.attackPose.angle - SOURCE_BLADE_ANGLE
    end

    local dx, dy = self:getUnitDirection()
    local distance = self:getHeldDistance(dx, dy)
    return self.owner.pos.x + dx * distance,
        self.owner.pos.y + dy * distance,
        math.atan2(dy, dx) - SOURCE_BLADE_ANGLE
end

function sword:snapToTarget(targetX, targetY, targetRotation)
    self.pos.x = targetX
    self.pos.y = targetY
    self.rotation = targetRotation
    self.followVelocityX = 0
    self.followVelocityY = 0
    self.previousTargetX = targetX
    self.previousTargetY = targetY
end

function sword:syncFromOwner(dt)
    local targetX, targetY, targetRotation = self:getTargetPose()
    local enteringOrLeavingSwing = self.owner.swinging or self.wasSwinging

    if not dt or enteringOrLeavingSwing or not self.previousTargetX then
        -- Active attacks stay exact, and the first idle frame captures the true
        -- terminal pose before the carried sword begins floating independently.
        self:snapToTarget(targetX, targetY, targetRotation)
    elseif dt > 0 then
        self.pos.x, self.followVelocityX = sword.springFollowAxis(
            self.pos.x,
            self.followVelocityX,
            self.previousTargetX,
            targetX,
            dt,
            IDLE_FOLLOW_FREQUENCY
        )
        self.pos.y, self.followVelocityY = sword.springFollowAxis(
            self.pos.y,
            self.followVelocityY,
            self.previousTargetY,
            targetY,
            dt,
            IDLE_FOLLOW_FREQUENCY
        )
        self.previousTargetX = targetX
        self.previousTargetY = targetY
        self.rotation = targetRotation
    end

    self.wasSwinging = self.owner.swinging
    self.x = self.pos.x
    self.y = self.pos.y
end

function sword:update(dt)
    -- Movement is synchronized after the physics step by syncFromCollider.
end

--- State calls this after physics; follow the player's newly synchronized pose.
function sword:syncFromCollider(dt)
    self:syncFromOwner(dt)
end

function sword:isBehindPlayer()
    if self.owner.swinging then
        return self.owner:isSwordBehind()
    end

    local bladeAngle = self.rotation + SOURCE_BLADE_ANGLE
    local hiltY =
        self.pos.y - math.sin(bladeAngle) * self.owner.attackPose.length / 2
    local relativeY = hiltY - self.owner.pos.y
    if relativeY < -IDLE_LAYER_HYSTERESIS then
        self.idleBehind = true
    elseif relativeY > IDLE_LAYER_HYSTERESIS then
        self.idleBehind = false
    end
    return self.idleBehind
end

--- Active arcs use their exact hilt; the floating idle pose uses its visual hilt.
function sword:getDrawDepth()
    if self.owner.hasSwung and self:isBehindPlayer() then
        return self.owner.pos.y - 0.5
    end
    return self.owner.pos.y + 0.5
end

function sword:draw()
    if not self.visible or not self.owner.hasSwung then
        return
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        self.img,
        self.frame,
        self.pos.x,
        self.pos.y,
        self.rotation,
        1,
        1,
        self.frameW / 2,
        self.frameH / 2
    )
end
