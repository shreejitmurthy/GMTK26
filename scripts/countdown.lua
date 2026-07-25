-- Plague countdown: remaining time IS player health.
-- Owned by gameplay state; combat damage wires later via :damage(seconds).

local countdown = {}
countdown.__index = countdown

local DEFAULT_DURATION = 90
local DAMAGE_PULSE_DURATION = 0.4

--- opts: { duration = seconds } — jam default ~60–120.
function countdown.new(opts)
    opts = opts or {}
    local duration = opts.duration or DEFAULT_DURATION
    local c = setmetatable({}, countdown)
    c.duration = duration
    c.remaining = duration
    c.paused = false
    c.active = true
    -- damagePulse / healPulse: 1 → 0 over DAMAGE_PULSE_DURATION for float UI.
    c.damagePulse = 0
    c.damagePulseAmount = 0
    c.damagePulseTime = 0
    c.healPulse = 0
    c.healPulseAmount = 0
    c.healPulseTime = 0
    return c
end

function countdown:update(dt)
    -- Pulses decay even while paused (so extract / cleanse flash can finish).
    if self.damagePulseTime > 0 then
        self.damagePulseTime = math.max(0, self.damagePulseTime - dt)
        self.damagePulse = self.damagePulseTime / DAMAGE_PULSE_DURATION
    else
        self.damagePulse = 0
    end
    if self.healPulseTime > 0 then
        self.healPulseTime = math.max(0, self.healPulseTime - dt)
        self.healPulse = self.healPulseTime / DAMAGE_PULSE_DURATION
    else
        self.healPulse = 0
    end

    if not self.active or self.paused then
        return
    end
    self.remaining = math.max(0, self.remaining - dt)
end

--- Subtract seconds (clamp at 0). Used by debug key and later combat.
function countdown:damage(seconds)
    seconds = seconds or 0
    if seconds <= 0 then
        return
    end
    self.remaining = math.max(0, self.remaining - seconds)
    self.damagePulseAmount = seconds
    self.damagePulseTime = DAMAGE_PULSE_DURATION
    self.damagePulse = 1
end

--- Refund / reward seconds (clamp to duration). Theme: kill infected → +time.
function countdown:addTime(seconds)
    seconds = seconds or 0
    if seconds <= 0 then
        return
    end
    self.remaining = math.min(self.duration, self.remaining + seconds)
    self.healPulseAmount = seconds
    self.healPulseTime = DAMAGE_PULSE_DURATION
    self.healPulse = 1
end

function countdown:getRemaining()
    return self.remaining
end

function countdown:getDuration()
    return self.duration
end

--- Ratio 0..1 for UI urgency tint / pulse / fuse width.
function countdown:getRatio()
    if self.duration <= 0 then
        return 0
    end
    return math.max(0, math.min(1, self.remaining / self.duration))
end

--- 0..1 flash intensity; amount is last damage seconds (for floating "-Xs").
function countdown:getDamagePulse()
    return self.damagePulse, self.damagePulseAmount
end

--- 0..1 flash intensity; amount is last addTime seconds (for floating "+Xs").
function countdown:getHealPulse()
    return self.healPulse, self.healPulseAmount
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
