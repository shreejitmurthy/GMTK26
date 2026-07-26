-- Plague nest cleanse loop — 3 district seals, then the locked Plague Well.
-- Hold E inside radius (no hurt i-frames) to seal; serum cost once per site.
-- Win only after the fountain well is cleansed (never at district 3/3 alone).

local game_map = require "scripts.game_map"

local nests = {}

nests.CLEANSE_SECONDS = 2.0
--- District exposure escalates as the doctor carries more sealed plague.
nests.CLEANSE_START_COST_SECONDS = 2
nests.CLEANSE_COST_PER_POTION = 1
nests.WELL_CLEANSE_START_COST_SECONDS = 6
nests.PROGRESS_DECAY_PER_SEC = 2.5
--- Hold this key while inside radius to channel (walking alone does not cleanse).
nests.CLEANSE_HOLD_KEY = "e"

nests.WELL_ID = "well"

--- District nests only (Ash Market / Ossuary / Watch Yard). Not the fountain.
local DISTRICT_ORDER = { "a", "b", "c" }

local COLORS = {
    a = { 0.4, 0.55, 0.72 }, -- blue serum vial
    b = { 0.55, 0.32, 0.55 }, -- magenta serum vial
    c = { 0.32, 0.55, 0.36 }, -- emerald serum vial
    well = { 0.35, 0.55, 0.5 }, -- cyan plague-well vial
}

local DEFAULT_RADIUS = {
    a = 36,
    b = 36,
    c = 40,
    well = 40,
}

local FALLBACK_POS = {
    -- SW Ash Market heap (object TL 3,16 → center).
    a = { 4 * 16, 17 * 16 },
    -- SE Drain Court (object TL 21,18 → center) — off the fountain stamp.
    b = { 22 * 16, 19 * 16 },
    -- NE Watch Yard pyre (object TL 25,5 → center).
    c = { 26 * 16, 6 * 16 },
    -- Plague Well fountain center.
    well = { 15 * 16, 12 * 16 },
}

function nests.color(id)
    return COLORS[id] or { 0.7, 0.7, 0.7 }
end

--- District nest ids for HUD pips / encounter pressure (excludes the well).
function nests.order()
    return DISTRICT_ORDER
end

function nests.isWell(nestOrId)
    local id = nestOrId
    if type(nestOrId) == "table" then
        id = nestOrId.id
    end
    return id == nests.WELL_ID or id == "d"
end

function nests.getWell(list)
    for _, nest in ipairs(list or {}) do
        if nests.isWell(nest) then
            return nest
        end
    end
    return nil
end

function nests.countDistrictCleansed(list)
    local n = 0
    for _, nest in ipairs(list or {}) do
        if nest.cleansed and not nests.isWell(nest) then
            n = n + 1
        end
    end
    return n
end

--- Exposure is paid once when channeling begins: 2s, 3s, 4s, then 6s at the Well.
function nests.exposureCost(list, nest)
    if nests.isWell(nest) then
        return nests.WELL_CLEANSE_START_COST_SECONDS
    end
    return nests.CLEANSE_START_COST_SECONDS
        + nests.countDistrictCleansed(list) * nests.CLEANSE_COST_PER_POTION
end

function nests.districtsSealed(list)
    return nests.countDistrictCleansed(list) >= #DISTRICT_ORDER
end

--- Well is channelable only after all three district nests are sealed.
function nests.wellUnlocked(list)
    return nests.districtsSealed(list)
end

--- Total seals completed (districts + well). Fantasy = 4.
function nests.countCleansed(list)
    local n = 0
    for _, nest in ipairs(list or {}) do
        if nest.cleansed then
            n = n + 1
        end
    end
    return n
end

--- Win condition: Plague Well cleansed (implies districts already sealed).
function nests.allCleansed(list)
    local well = nests.getWell(list)
    return well ~= nil and well.cleansed == true
end

--- Sites still to seal (districts + well). Max 4.
function nests.remaining(list)
    local list = list or {}
    local total = 0
    for _, nest in ipairs(list) do
        total = total + 1
    end
    if total == 0 then
        return 0
    end
    return total - nests.countCleansed(list)
end

local function resolveEntry(raw, id)
    if id == nests.WELL_ID then
        return raw.well or raw.nest_well or raw.d or raw.nest_d
    end
    return raw[id] or raw["nest_" .. id]
end

local function makeNest(id, x, y, radius, isWell)
    return {
        id = id,
        x = x,
        y = y,
        radius = radius,
        isWell = isWell and true or false,
        locked = isWell and true or false,
        cleansed = false,
        progress = 0,
        paidStartCost = false,
        justCleansed = false,
        channeling = false,
        inside = false,
        showPrompt = false,
        promptLocked = false,
    }
end

--- Build runtime nest list: 3 districts + fountain well from map Spawns.
function nests.fromMap(map)
    local raw = game_map.getNests(map) or {}
    local list = {}

    for _, id in ipairs(DISTRICT_ORDER) do
        local entry = resolveEntry(raw, id)
        local x, y, radius
        if entry then
            x, y = entry.x, entry.y
            radius = entry.cleanseRadius or DEFAULT_RADIUS[id]
        else
            local fb = FALLBACK_POS[id]
            x, y = fb[1], fb[2]
            radius = DEFAULT_RADIUS[id]
        end
        list[#list + 1] = makeNest(id, x, y, radius, false)
    end

    local wellEntry = resolveEntry(raw, nests.WELL_ID)
    local wx, wy, wr
    if wellEntry then
        wx, wy = wellEntry.x, wellEntry.y
        wr = wellEntry.cleanseRadius or DEFAULT_RADIUS.well
    else
        local fb = FALLBACK_POS.well
        wx, wy = fb[1], fb[2]
        wr = DEFAULT_RADIUS.well
    end
    list[#list + 1] = makeNest(nests.WELL_ID, wx, wy, wr, true)

    return list
end

--- Active site that should show a cleanse / locked prompt (inside, uncleansed).
function nests.promptNest(list)
    for _, nest in ipairs(list or {}) do
        if nest.showPrompt then
            return nest
        end
    end
    return nil
end

--- Prompt copy for the active site (locked well vs Hold E).
function nests.promptText(list)
    local nest = nests.promptNest(list)
    if not nest then
        return nil
    end
    if nest.isWell and nest.locked then
        return string.format(
            "Collect the three potions first (%d/3)",
            nests.countDistrictCleansed(list)
        )
    end
    if nest.isWell then
        return string.format(
            "Hold E to cleanse the Plague Well (-%ds)",
            nests.exposureCost(list, nest)
        )
    end
    return string.format(
        "Hold E to collect potion (-%ds)",
        nests.exposureCost(list, nest)
    )
end

local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

local function holdingCleanse()
    return love.keyboard.isDown(nests.CLEANSE_HOLD_KEY)
end

local function refreshWellLock(list)
    local unlocked = nests.wellUnlocked(list)
    local well = nests.getWell(list)
    if well and not well.cleansed then
        well.locked = not unlocked
    elseif well then
        well.locked = false
    end
    return unlocked
end

--- Advance hold-to-cleanse. Walking inside radius alone does NOT channel.
--- state needs: nests, countdown, getActor("player"), onNestCleansed(nest)
--- Optional: onWellUnlocked() when districts hit 3/3; onSectorCleared() on well seal.
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
    local unlockedBefore = nests.wellUnlocked(list)

    for _, nest in ipairs(list) do
        nest.justCleansed = false
        nest.channeling = false
        nest.inside = false
        nest.showPrompt = false
        nest.promptLocked = false

        if nest.cleansed then
            nest.progress = 1
            nest.locked = false
        else
            local inside = dist2(px, py, nest.x, nest.y) <= nest.radius * nest.radius
            nest.inside = inside

            local isLockedWell = nest.isWell and not nests.wellUnlocked(list)
            nest.locked = isLockedWell and true or false

            if inside then
                nest.showPrompt = true
                nest.promptLocked = isLockedWell
            end

            -- Locked well: Hold E does nothing and never pays serum.
            if inside and holding and not inIFrames and not isLockedWell then
                nest.channeling = true
                if nest.progress <= 0 and not nest.paidStartCost and state.countdown then
                    local exposureCost = nests.exposureCost(list, nest)
                    state.countdown:damage(exposureCost)
                    nest.paidStartCost = true
                    print(string.format(
                        "[nest] serum exposure -%ds on nest_%s (%.1fs left)",
                        exposureCost,
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
                    nest.locked = false
                    if state.onNestCleansed then
                        state:onNestCleansed(nest)
                    end
                end
            else
                if nest.progress > 0 and not isLockedWell then
                    nest.progress = math.max(
                        0,
                        nest.progress - dt * nests.PROGRESS_DECAY_PER_SEC
                    )
                elseif isLockedWell then
                    nest.progress = 0
                end
            end
        end
    end

    refreshWellLock(list)

    -- District 3/3 unlocks the well — never starts win presentation.
    if not unlockedBefore and nests.wellUnlocked(list) then
        if state.onWellUnlocked then
            state:onWellUnlocked()
        end
        print("[nest] Plague Well unlocked — districts sealed 3/3")
    end

    -- Win ONLY after the fountain well is cleansed.
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
