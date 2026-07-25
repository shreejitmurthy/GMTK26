-- Plague nest cleanse loop — the countdown game's standout fantasy.
-- Hold E inside radius (no hurt i-frames) to seal; serum cost once per nest.

local game_map = require "scripts.game_map"

local nests = {}

nests.CLEANSE_SECONDS = 2.0
--- Serum exposure paid once when a hold-cleanse attempt first begins on a nest.
nests.CLEANSE_START_COST_SECONDS = 2
nests.PROGRESS_DECAY_PER_SEC = 2.5
--- Hold this key while inside radius to channel (walking alone does not cleanse).
nests.CLEANSE_HOLD_KEY = "e"

local ORDER = { "a", "b", "c" }

local COLORS = {
    a = { 0.55, 0.42, 0.28 }, -- warm soot
    b = { 0.35, 0.62, 0.28 }, -- sick green
    c = { 0.85, 0.45, 0.22 }, -- cold ember
}

local DEFAULT_RADIUS = {
    a = 36,
    b = 36,
    c = 40,
}

function nests.color(id)
    return COLORS[id] or { 0.7, 0.7, 0.7 }
end

function nests.order()
    return ORDER
end

--- Build runtime nest list from map Spawns (nest_a/b/c + cleanseRadius).
function nests.fromMap(map)
    local raw = game_map.getNests(map) or {}
    local list = {}
    for _, id in ipairs(ORDER) do
        local entry = raw[id] or raw["nest_" .. id]
        local x, y, radius
        if entry then
            x, y = entry.x, entry.y
            radius = entry.cleanseRadius or DEFAULT_RADIUS[id]
        else
            if id == "a" then
                x, y = 5 * 16, 15 * 16
            elseif id == "b" then
                x, y = 15 * 16, 12 * 16
            else
                x, y = 25 * 16, 13 * 16
            end
            radius = DEFAULT_RADIUS[id]
        end
        list[#list + 1] = {
            id = id,
            x = x,
            y = y,
            radius = radius,
            cleansed = false,
            progress = 0,
            paidStartCost = false,
            justCleansed = false,
            channeling = false,
            inside = false,
            showPrompt = false,
        }
    end
    return list
end

function nests.countCleansed(list)
    local n = 0
    for _, nest in ipairs(list or {}) do
        if nest.cleansed then
            n = n + 1
        end
    end
    return n
end

function nests.allCleansed(list)
    local list = list or {}
    if #list == 0 then
        return false
    end
    return nests.countCleansed(list) >= #list
end

function nests.remaining(list)
    local list = list or {}
    return #list - nests.countCleansed(list)
end

--- Active nest that should show "Hold E to cleanse" (inside, uncleansed).
function nests.promptNest(list)
    for _, nest in ipairs(list or {}) do
        if nest.showPrompt then
            return nest
        end
    end
    return nil
end

local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

local function holdingCleanse()
    return love.keyboard.isDown(nests.CLEANSE_HOLD_KEY)
end

--- Advance hold-to-cleanse. Walking inside radius alone does NOT channel.
--- state needs: nests, countdown, getActor("player"), onNestCleansed(nest)
function nests.update(state, dt)
    local list = state.nests
    if not list or state.extracted or state.sectorCleared then
        return
    end

    local playerActor = state:getActor("player")
    if not playerActor or not playerActor.collider then
        return
    end

    local px, py = playerActor.collider:getX(), playerActor.collider:getY()
    local inIFrames = (playerActor.hurtIFrame or 0) > 0
    local holding = holdingCleanse()

    for _, nest in ipairs(list) do
        nest.justCleansed = false
        nest.channeling = false
        nest.inside = false
        nest.showPrompt = false
        if nest.cleansed then
            nest.progress = 1
        else
            local inside = dist2(px, py, nest.x, nest.y) <= nest.radius * nest.radius
            nest.inside = inside
            nest.showPrompt = inside
            if inside and holding and not inIFrames then
                nest.channeling = true
                if nest.progress <= 0 and not nest.paidStartCost and state.countdown then
                    -- Theme cost: serum exposure once per nest, only when hold starts.
                    state.countdown:damage(nests.CLEANSE_START_COST_SECONDS)
                    nest.paidStartCost = true
                    print(string.format(
                        "[nest] serum exposure -%ds on nest_%s (%.1fs left)",
                        nests.CLEANSE_START_COST_SECONDS,
                        nest.id,
                        state.countdown:getRemaining()
                    ))
                    if state.countdown:isExpired() then
                        state.extracted = true
                        state.countdown:pause()
                        print("[countdown] EXTRACTED — plague time exhausted")
                        return
                    end
                end
                nest.progress = math.min(
                    1,
                    nest.progress + dt / nests.CLEANSE_SECONDS
                )
                if nest.progress >= 1 then
                    nest.cleansed = true
                    nest.progress = 1
                    nest.justCleansed = true
                    nest.channeling = false
                    nest.showPrompt = false
                    if state.onNestCleansed then
                        state:onNestCleansed(nest)
                    end
                end
            else
                -- Leave radius, release key, or take a hit → progress decays fast.
                if nest.progress > 0 then
                    nest.progress = math.max(
                        0,
                        nest.progress - dt * nests.PROGRESS_DECAY_PER_SEC
                    )
                end
            end
        end
    end

    if nests.allCleansed(list) and not state.sectorCleared then
        state.sectorCleared = true
        if state.countdown then
            state.countdown:pause()
        end
        if state.onSectorCleared then
            state:onSectorCleared()
        end
    end
end

return nests
