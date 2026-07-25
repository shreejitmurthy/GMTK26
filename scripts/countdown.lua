-- Plague countdown: remaining time IS player health.
-- Owned by gameplay state; combat damage wires later via :damage(seconds).

local countdown = {}
countdown.__index = countdown

local DEFAULT_DURATION = 90

--- opts: { duration = seconds } — jam default ~60–120.
function countdown.new(opts)
    opts = opts or {}
    local duration = opts.duration or DEFAULT_DURATION
    local c = setmetatable({}, countdown)
    c.duration = duration
    c.remaining = duration
    c.paused = false
    c.active = true
    return c
end

function countdown:update(dt)
    if not self.active or self.paused then
        return
    end
    self.remaining = math.max(0, self.remaining - dt)
end

--- Subtract seconds (clamp at 0). Used by debug key and later combat.
function countdown:damage(seconds)
    seconds = seconds or 0
    self.remaining = math.max(0, self.remaining - seconds)
end

function countdown:getRemaining()
    return self.remaining
end

function countdown:getDuration()
    return self.duration
end

--- Ratio 0..1 for UI urgency tint / pulse.
function countdown:getRatio()
    if self.duration <= 0 then
        return 0
    end
    return math.max(0, math.min(1, self.remaining / self.duration))
end

function countdown:isExpired()
    return self.remaining <= 0
end

function countdown:pause()
    self.paused = true
end

function countdown:resume()
    self.paused = false
end

--- M:SS normally; SS.s (tenths) when under 10 seconds.
function countdown:format()
    local t = math.max(0, self.remaining)
    if t < 10 then
        return string.format("%.1f", t)
    end
    local mins = math.floor(t / 60)
    local secs = math.floor(t % 60)
    return string.format("%d:%02d", mins, secs)
end

return countdown
