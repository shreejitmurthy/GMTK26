-- Visible sword actor. It follows the player for now, but remains a separate
-- actor so its movement/attacks can diverge later without living in player:draw.

require "scripts.actor"

sword = {}
setmetatable(sword, { __index = actor })

local FRAME_SIZE = 16
local FIRST_FRAME_X = 0
local FIRST_FRAME_Y = 0
local SOURCE_BLADE_ANGLE = -math.pi / 4

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
    local playerW = self.owner.img:getWidth()
    local playerH = self.owner.img:getHeight()
    local playerExtent = math.abs(dx) * playerW / 2 + math.abs(dy) * playerH / 2
    return playerExtent + self.frameW / 2
end

function sword:syncFromOwner()
    if self.owner.hasSwung then
        -- Follow the active pose and keep following its held endpoint afterward.
        self.pos.x = self.owner.attackPose.x
        self.pos.y = self.owner.attackPose.y
        self.rotation = self.owner.attackPose.angle - SOURCE_BLADE_ANGLE
    else
        local dx, dy = self:getUnitDirection()
        local distance = self:getHeldDistance(dx, dy)
        self.pos.x = self.owner.pos.x + dx * distance
        self.pos.y = self.owner.pos.y + dy * distance
        self.rotation = math.atan2(dy, dx) - SOURCE_BLADE_ANGLE
    end

    self.x = self.pos.x
    self.y = self.pos.y
end

function sword:update(dt)
    -- Movement is synchronized after the physics step by syncFromCollider.
end

--- State calls this after physics; this actor has no collider of its own.
function sword:syncFromCollider()
    self:syncFromOwner()
end

--- Follow the hilt's actual screen Y so left-facing arcs layer in reverse.
function sword:getDrawDepth()
    if self.owner.hasSwung and self.owner:isSwordBehind() then
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
        2,
        2,
        self.frameW / 2,
        self.frameH / 2
    )
end
