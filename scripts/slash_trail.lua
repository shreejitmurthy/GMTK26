-- Procedural sword ribbon. Two instances split historical samples across the
-- player's behind/front draw layers while sharing the same attack pose source.

require "scripts.actor"

slashTrail = {}
setmetatable(slashTrail, { __index = actor })

local TRAIL_LIFETIME = 0.16
local MAX_SAMPLES = 24
local INNER_BLADE_FRACTION = 0.35
local RIBBON_ALPHA = 0.34
local EDGE_ALPHA = 0.65

local function sampleAlpha(sample)
    local remaining = math.max(0, 1 - sample.age / TRAIL_LIFETIME)
    return remaining * remaining
end

function slashTrail:new(owner, behind)
    assert(owner, "slashTrail:new requires an owner")

    local label = behind and "slash_trail_behind" or "slash_trail_front"
    local trail = actor:new(owner.pos.x, owner.pos.y, label)
    setmetatable(trail, { __index = slashTrail })

    trail.owner = owner
    trail.behind = behind == true
    trail.samples = {}
    trail.visible = true

    return trail
end

function slashTrail:update(dt)
    for index = #self.samples, 1, -1 do
        local sample = self.samples[index]
        sample.age = sample.age + dt
        if sample.age >= TRAIL_LIFETIME then
            table.remove(self.samples, index)
        end
    end
end

function slashTrail:addSample()
    local pose = self.owner.attackPose
    local innerX = pose.baseX + (pose.tipX - pose.baseX) * INNER_BLADE_FRACTION
    local innerY = pose.baseY + (pose.tipY - pose.baseY) * INNER_BLADE_FRACTION

    self.samples[#self.samples + 1] = {
        innerX = innerX,
        innerY = innerY,
        tipX = pose.tipX,
        tipY = pose.tipY,
        age = 0,
        swingSerial = self.owner.swingSerial,
    }

    while #self.samples > MAX_SAMPLES do
        table.remove(self.samples, 1)
    end
end

--- State calls this after the player has synchronized its post-physics pose.
function slashTrail:syncFromCollider()
    self.x = self.owner.pos.x
    self.y = self.owner.pos.y

    if not self.owner.swinging then
        return
    end

    local poseIsBehind = self.owner:isSwordBehind()
    if poseIsBehind == self.behind then
        self:addSample()
    end
end

function slashTrail:getDrawDepth()
    if self.behind then
        return self.owner.pos.y - 0.75
    end
    return self.owner.pos.y + 0.25
end

function slashTrail:drawRibbonSegment(previous, current, alpha)
    love.graphics.setColor(0.58, 0.32, 0.86, alpha * RIBBON_ALPHA)
    love.graphics.polygon(
        "fill",
        previous.innerX,
        previous.innerY,
        previous.tipX,
        previous.tipY,
        current.tipX,
        current.tipY
    )
    love.graphics.polygon(
        "fill",
        previous.innerX,
        previous.innerY,
        current.tipX,
        current.tipY,
        current.innerX,
        current.innerY
    )
end

function slashTrail:drawEdgeSegment(previous, current, alpha)
    love.graphics.setColor(0.96, 0.86, 1, alpha * EDGE_ALPHA)
    love.graphics.line(previous.tipX, previous.tipY, current.tipX, current.tipY)
end

function slashTrail:draw()
    if not self.visible or #self.samples < 2 then
        return
    end

    love.graphics.setBlendMode("alpha")
    for index = 2, #self.samples do
        local previous = self.samples[index - 1]
        local current = self.samples[index]
        if previous.swingSerial == current.swingSerial then
            local alpha = (sampleAlpha(previous) + sampleAlpha(current)) / 2
            self:drawRibbonSegment(previous, current, alpha)
        end
    end

    love.graphics.setBlendMode("add")
    love.graphics.setLineWidth(1.25)
    for index = 2, #self.samples do
        local previous = self.samples[index - 1]
        local current = self.samples[index]
        if previous.swingSerial == current.swingSerial then
            local alpha = (sampleAlpha(previous) + sampleAlpha(current)) / 2
            self:drawEdgeSegment(previous, current, alpha)
        end
    end

    love.graphics.setLineWidth(1)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end
