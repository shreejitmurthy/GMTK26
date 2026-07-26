-- Narrow encounter director: nest pressure → telegraph → capped spawns.
-- Keeps the courtyard populated without waves UI, navmeshes, or new types.

local physics = require "scripts.physics"
local collapse = require "scripts.collapse"
local nestsMod = require "scripts.nests"
local enemy_types = require "scripts.enemy_types"

local encounter_director = {}

---------------------------------------------------------------------------
-- Tuning (all encounter cadence / fairness knobs live here)
---------------------------------------------------------------------------
local TUNING = {
    --- Living + pending global cap. Slightly higher for nest contesting.
    MAX_ACTIVE = 8,
    TYPE_CAPS = {
        chaser = 4,
        fleer = 3,
        keeper = 3,
        ranger = 2,
    },
    --- Per uncleansed nest: seconds between pressure attempts (steady, not spam).
    PRESSURE_INTERVAL = 11.0,
    WELL_PRESSURE_INTERVAL = 6.5,
    --- Stagger so three nests do not fire on the same frame at t=0.
    PRESSURE_STAGGER = 1.8,
    --- First dynamic spawn ≥ 8s after run start.
    PRESSURE_START_DELAY = 8.0,
    --- Retry soon when at cap or no safe point.
    PRESSURE_RETRY = 2.0,
    TELEGRAPH_SECONDS = 0.6,
    MIN_PLAYER_DIST = 120,
    MIN_ENEMY_DIST = 36,
    --- Soft pad outside the camera AABB so spawns are not edge-popping.
    CAMERA_MARGIN = 18,
    SPAWN_HALF_W = 7,
    SPAWN_HALF_H = 7,
    --- Fallback ring around nest when authored points are blocked.
    NEST_RING_MIN = 28,
    NEST_RING_MAX = 72,
    RING_ATTEMPTS = 16,
    RANDOM_ATTEMPTS = 24,
    --- Player-adjacent pressure when cleansing / near an uncleansed site.
    PLAYER_RING_MIN = 128,
    PLAYER_RING_MAX = 200,
    PLAYER_RING_ATTEMPTS = 22,
    HUNT_WAVE_BURSTS = 2,
    WELL_FINALE_BURSTS = 3,
    COMPOSITION = {
        { type = "chaser", weight = 0.45 },
        { type = "fleer", weight = 0.25 },
        { type = "keeper", weight = 0.20 },
        { type = "ranger", weight = 0.10 },
    },
    TIME_REWARDS = {
        chaser = 1.5,
        fleer = 3.0,
        keeper = 2.0,
        ranger = 2.5,
    },
}

encounter_director.TUNING = TUNING

local spawnByNest = {}
local pressure = {}
local pending = {}
local loaded = false

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function encounter_director.timeRewardFor(enemyType)
    return TUNING.TIME_REWARDS[enemyType] or 1.5
end

local function nestUncleansed(state, nestId)
    for _, nest in ipairs(state.nests or {}) do
        if nest.id == nestId then
            return not nest.cleansed
        end
    end
    return false
end

local function countActive(state)
    local n = 0
    for _, actor in ipairs(state.actors or {}) do
        if actor.label == "enemy" and not actor.dead then
            n = n + 1
        end
    end
    return n + #pending
end

--- Living + pending counts by type (authored openers count toward caps).
local function countByType(state)
    local counts = { chaser = 0, fleer = 0, keeper = 0, ranger = 0 }
    for _, actor in ipairs(state.actors or {}) do
        if actor.label == "enemy" and not actor.dead and actor.enemyType then
            local t = actor.enemyType
            if counts[t] ~= nil then
                counts[t] = counts[t] + 1
            end
        end
    end
    for _, entry in ipairs(pending) do
        local t = entry.enemyType
        if counts[t] ~= nil then
            counts[t] = counts[t] + 1
        end
    end
    return counts
end

local function typeAtCap(state, enemyType)
    local cap = TUNING.TYPE_CAPS[enemyType]
    if not cap then
        return true
    end
    local counts = countByType(state)
    return (counts[enemyType] or 0) >= cap
end

local function cameraBounds()
    if not cam or not cam.worldCoords then
        return nil
    end
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()
    local x0, y0 = cam:worldCoords(0, 0)
    local x1, y1 = cam:worldCoords(w, h)
    local minX = math.min(x0, x1) - TUNING.CAMERA_MARGIN
    local maxX = math.max(x0, x1) + TUNING.CAMERA_MARGIN
    local minY = math.min(y0, y1) - TUNING.CAMERA_MARGIN
    local maxY = math.max(y0, y1) + TUNING.CAMERA_MARGIN
    return minX, minY, maxX, maxY
end

local function inCamera(x, y)
    local minX, minY, maxX, maxY = cameraBounds()
    if not minX then
        return false
    end
    return x >= minX and x <= maxX and y >= minY and y <= maxY
end

local function floorClear(x, y)
    local hw, hh = TUNING.SPAWN_HALF_W, TUNING.SPAWN_HALF_H
    if collapse.isUnsafeFloor(x, y) then
        return false
    end
    -- Reject if any corner of the spawn AABB sits on cracking/fallen floor.
    if collapse.isUnsafeFloor(x - hw, y - hh)
        or collapse.isUnsafeFloor(x + hw, y - hh)
        or collapse.isUnsafeFloor(x - hw, y + hh)
        or collapse.isUnsafeFloor(x + hw, y + hh)
    then
        return false
    end
    return true
end

local function pointClearOfActors(x, y, state, ignorePending)
    for _, actor in ipairs(state.actors or {}) do
        if actor.label == "enemy" and not actor.dead and actor.pos then
            if dist(x, y, actor.pos.x, actor.pos.y) < TUNING.MIN_ENEMY_DIST then
                return false
            end
        end
    end
    if not ignorePending then
        for _, p in ipairs(pending) do
            if dist(x, y, p.x, p.y) < TUNING.MIN_ENEMY_DIST then
                return false
            end
        end
    end
    return true
end

--- Full spawn safety: walls/props, playable, floor, player, camera, crowding.
function encounter_director.isSpawnSafe(x, y, state, opts)
    opts = opts or {}
    if not physics.isSpawnClear(x, y, TUNING.SPAWN_HALF_W, TUNING.SPAWN_HALF_H) then
        return false
    end
    if not floorClear(x, y) then
        return false
    end
    local playerActor = state and state:getActor("player")
    if playerActor and playerActor.pos then
        if dist(x, y, playerActor.pos.x, playerActor.pos.y) < TUNING.MIN_PLAYER_DIST then
            return false
        end
    end
    if not opts.allowCamera and inCamera(x, y) then
        return false
    end
    if state and not pointClearOfActors(x, y, state, opts.ignorePending) then
        return false
    end
    return true
end

local function pickCompositionType(state)
    local options = {}
    local sum = 0
    for _, entry in ipairs(TUNING.COMPOSITION) do
        if not typeAtCap(state, entry.type) then
            options[#options + 1] = entry
            sum = sum + entry.weight
        end
    end
    if #options == 0 or sum <= 0 then
        return nil
    end
    local roll = love.math.random() * sum
    local acc = 0
    for _, entry in ipairs(options) do
        acc = acc + entry.weight
        if roll <= acc then
            return entry.type
        end
    end
    return options[#options].type
end

local function nestPosition(state, nestId)
    for _, nest in ipairs(state.nests or {}) do
        if nest.id == nestId then
            return nest.x, nest.y
        end
    end
    return nil, nil
end

local function tryAuthoredPoints(nestId, state)
    local list = spawnByNest[nestId]
    if not list or #list == 0 then
        return nil, nil
    end
    -- Shuffle order without mutating stored list.
    local order = {}
    for i = 1, #list do
        order[i] = list[i]
    end
    for i = #order, 2, -1 do
        local j = love.math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    for _, point in ipairs(order) do
        if encounter_director.isSpawnSafe(point.x, point.y, state) then
            return point.x, point.y
        end
    end
    return nil, nil
end

local function tryNestRing(nestId, state)
    local nx, ny = nestPosition(state, nestId)
    if not nx then
        return nil, nil
    end
    for _ = 1, TUNING.RING_ATTEMPTS do
        local ang = love.math.random() * math.pi * 2
        local rad = TUNING.NEST_RING_MIN
            + love.math.random() * (TUNING.NEST_RING_MAX - TUNING.NEST_RING_MIN)
        local x = nx + math.cos(ang) * rad
        local y = ny + math.sin(ang) * rad
        if encounter_director.isSpawnSafe(x, y, state) then
            return x, y
        end
    end
    return nil, nil
end

local function tryRandomAway(state)
    local playerActor = state:getActor("player")
    local playerPos = playerActor and playerActor.pos or nil
    for _ = 1, TUNING.RANDOM_ATTEMPTS do
        local x, y = physics.pickSpawnPoint({
            halfW = TUNING.SPAWN_HALF_W,
            halfH = TUNING.SPAWN_HALF_H,
            minPlayerDist = TUNING.MIN_PLAYER_DIST,
            minEnemyDist = TUNING.MIN_ENEMY_DIST,
            playerPos = playerPos,
            pad = 24,
        })
        if encounter_director.isSpawnSafe(x, y, state) then
            return x, y
        end
    end
    return nil, nil
end

local function getNest(state, nestId)
    for _, nest in ipairs(state.nests or {}) do
        if nest.id == nestId then
            return nest
        end
    end
    return nil
end

--- Bias toward the player when they are fighting / cleansing that site.
local function shouldBiasPlayer(state, nestId)
    local nest = getNest(state, nestId)
    local playerActor = state:getActor("player")
    if not nest or not playerActor or not playerActor.pos then
        return false
    end
    if nest.channeling then
        return true
    end
    local d = dist(playerActor.pos.x, playerActor.pos.y, nest.x, nest.y)
    return d <= (nest.radius or 36) + 100
end

local function tryNearPlayer(state, allowCamera)
    local playerActor = state:getActor("player")
    if not playerActor or not playerActor.pos then
        return nil, nil
    end
    local px, py = playerActor.pos.x, playerActor.pos.y
    for _ = 1, TUNING.PLAYER_RING_ATTEMPTS do
        local ang = love.math.random() * math.pi * 2
        local rad = TUNING.PLAYER_RING_MIN
            + love.math.random() * (TUNING.PLAYER_RING_MAX - TUNING.PLAYER_RING_MIN)
        local x = px + math.cos(ang) * rad
        local y = py + math.sin(ang) * rad
        if encounter_director.isSpawnSafe(x, y, state, { allowCamera = allowCamera }) then
            return x, y
        end
    end
    return nil, nil
end

local function findSpawnPoint(nestId, state)
    if shouldBiasPlayer(state, nestId) then
        -- Prefer contested floor near the player (still outside MIN_PLAYER_DIST).
        local x, y = tryNearPlayer(state, true)
        if x then
            return x, y
        end
        x, y = tryNearPlayer(state, false)
        if x then
            return x, y
        end
    end
    local x, y = tryAuthoredPoints(nestId, state)
    if x then
        return x, y
    end
    x, y = tryNestRing(nestId, state)
    if x then
        return x, y
    end
    return tryRandomAway(state)
end

local function uncleansedCount(state)
    local n = 0
    for _, nest in ipairs(state.nests or {}) do
        if not nest.cleansed then
            n = n + 1
        end
    end
    return n
end

--- Tighten cadence while many sites remain / plague timer is low.
local function pressureIntervalFor(state, isWell)
    local base = isWell and TUNING.WELL_PRESSURE_INTERVAL or TUNING.PRESSURE_INTERVAL
    local sites = uncleansedCount(state)
    local ratio = 1
    if state.countdown and state.countdown.getRatio then
        ratio = state.countdown:getRatio()
    end
    -- Mild urgency only — keep a fair cadence, not a spawn flood.
    local urgency = math.min(1, (sites / 4) * 0.4 + (1 - ratio) * 0.35)
    return base * (1 - 0.28 * urgency)
end

local function dropPackAggro(state, nestId)
    if not state or not state.actors or not nestId then
        return
    end
    for _, actor in ipairs(state.actors) do
        if actor.label == "enemy"
            and not actor.dead
            and actor.nest == nestId
        then
            actor._aggroed = false
        end
    end
end

local function beginTelegraph(nestId, state)
    if countActive(state) >= TUNING.MAX_ACTIVE then
        return false
    end
    local enemyType = pickCompositionType(state)
    if not enemyType then
        return false
    end
    local x, y = findSpawnPoint(nestId, state)
    if not x then
        return false
    end
    pending[#pending + 1] = {
        x = x,
        y = y,
        nestId = nestId,
        enemyType = enemyType,
        timer = TUNING.TELEGRAPH_SECONDS,
        maxTimer = TUNING.TELEGRAPH_SECONDS,
    }
    print(string.format(
        "[encounter] telegraph %s near nest_%s @ %.0f,%.0f",
        enemyType,
        nestId,
        x,
        y
    ))
    return true
end

local function completeSpawn(entry, state)
    if not encounter_director.isSpawnSafe(entry.x, entry.y, state, { ignorePending = true }) then
        print(string.format(
            "[encounter] cancel spawn %s — site unsafe at resolve",
            entry.enemyType
        ))
        return
    end
    local living = 0
    for _, actor in ipairs(state.actors or {}) do
        if actor.label == "enemy" and not actor.dead then
            living = living + 1
        end
    end
    -- entry was already removed from pending; living + remaining pending must fit.
    if living + #pending >= TUNING.MAX_ACTIVE then
        return
    end
    if typeAtCap(state, entry.enemyType) then
        return
    end

    local e = enemy:new(entry.x, entry.y, { type = entry.enemyType })
    e.nest = entry.nestId
    e.killRewardSeconds = encounter_director.timeRewardFor(entry.enemyType)
    state.actors[#state.actors + 1] = e
    print(string.format(
        "[encounter] spawn %s nest_%s @ %.0f,%.0f (active %d/%d)",
        entry.enemyType,
        entry.nestId,
        entry.x,
        entry.y,
        living + 1,
        TUNING.MAX_ACTIVE
    ))
end

--- Index authored Spawns by nest id and arm pressure timers.
--- Pressure runs on the 3 districts; well pressure arms only after unlock.
function encounter_director.load(state, spawnData)
    spawnByNest = { a = {}, b = {}, c = {}, well = {} }
    pending = {}
    pressure = {}
    loaded = true

    for _, point in ipairs((spawnData and spawnData.enemies) or {}) do
        local nestId = point.nest
        if nestId == "d" then
            nestId = "well"
        end
        if nestId and spawnByNest[nestId] then
            spawnByNest[nestId][#spawnByNest[nestId] + 1] = {
                x = point.x,
                y = point.y,
                type = point.type,
            }
        end
    end

    local order = nestsMod.order()
    for i, nestId in ipairs(order) do
        pressure[nestId] = TUNING.PRESSURE_START_DELAY
            + (i - 1) * TUNING.PRESSURE_STAGGER
    end

    -- Stamp kill rewards on any enemies already in the actor list.
    for _, actor in ipairs(state.actors or {}) do
        if actor.label == "enemy" and actor.enemyType then
            actor.killRewardSeconds = encounter_director.timeRewardFor(actor.enemyType)
        end
    end

    print(string.format(
        "[encounter] director ready (cap %d, authored a=%d b=%d c=%d well=%d)",
        TUNING.MAX_ACTIVE,
        #spawnByNest.a,
        #spawnByNest.b,
        #spawnByNest.c,
        #spawnByNest.well
    ))
end

function encounter_director.reset()
    pending = {}
    pressure = {}
    for _, nestId in ipairs(nestsMod.order()) do
        pressure[nestId] = TUNING.PRESSURE_START_DELAY
    end
end

function encounter_director.onNestCleansed(nest, state)
    if not nest or not nest.id then
        return
    end
    pressure[nest.id] = nil
    dropPackAggro(state, nest.id)
    for i = #pending, 1, -1 do
        if pending[i].nestId == nest.id then
            print(string.format(
                "[encounter] cancel pending %s — nest_%s cleansed",
                pending[i].enemyType,
                nest.id
            ))
            table.remove(pending, i)
        end
    end

    -- District cleanse hunt wave: remaining sites spike so the map stays hot.
    if nestsMod.isWell(nest) or not state then
        return
    end
    local bursts = 0
    for _, other in ipairs(state.nests or {}) do
        if not other.cleansed and other.id ~= nest.id then
            if nestsMod.isWell(other) and other.locked then
                -- Well still sealed — skip until unlock.
            else
                pressure[other.id] = math.min(pressure[other.id] or 99, 0.12 + bursts * 0.18)
                if bursts < TUNING.HUNT_WAVE_BURSTS
                    and countActive(state) < TUNING.MAX_ACTIVE
                    and beginTelegraph(other.id, state)
                then
                    bursts = bursts + 1
                end
            end
        end
    end
    if bursts > 0 then
        print(string.format(
            "[encounter] hunt wave after nest_%s — %d telegraphs",
            nest.id,
            bursts
        ))
    end
end

--- Finale: unlocked well pulses + immediate fountain-approach burst.
function encounter_director.onWellUnlocked(state)
    pressure.well = 0.2
    local bursts = 0
    if state then
        while bursts < TUNING.WELL_FINALE_BURSTS
            and countActive(state) < TUNING.MAX_ACTIVE
        do
            if beginTelegraph("well", state) then
                bursts = bursts + 1
            else
                break
            end
        end
    end
    print(string.format(
        "[encounter] well finale pressure armed (%d burst telegraphs)",
        bursts
    ))
end

function encounter_director.update(state, dt)
    if not loaded
        or not state
        or state.extracted
        or state.sectorCleared
        or state.enemyTestMode
    then
        return
    end

    -- Advance / cancel telegraphs first so floor collapse can void them.
    for i = #pending, 1, -1 do
        local entry = pending[i]
        if not nestUncleansed(state, entry.nestId)
            or not floorClear(entry.x, entry.y)
            or not physics.isSpawnClear(entry.x, entry.y, TUNING.SPAWN_HALF_W, TUNING.SPAWN_HALF_H)
        then
            print(string.format(
                "[encounter] cancel telegraph %s — floor/nest unsafe",
                entry.enemyType
            ))
            table.remove(pending, i)
        else
            entry.timer = entry.timer - dt
            if entry.timer <= 0 then
                table.remove(pending, i)
                completeSpawn(entry, state)
            end
        end
    end

    -- At most one new telegraph per frame (no same-frame multi-spawns).
    -- District nests always; well only after unlock (locked well = no pressure).
    local spawnedThisFrame = false
    for _, nest in ipairs(state.nests or {}) do
        local isWell = nestsMod.isWell(nest)
        if nest.cleansed or (isWell and nest.locked) then
            if nest.cleansed then
                pressure[nest.id] = nil
            end
        else
            local t = pressure[nest.id]
            if t == nil then
                t = isWell and 2.0 or TUNING.PRESSURE_INTERVAL
                pressure[nest.id] = t
            end
            t = t - dt
            if t <= 0 then
                if spawnedThisFrame then
                    pressure[nest.id] = 0
                elseif countActive(state) >= TUNING.MAX_ACTIVE then
                    pressure[nest.id] = TUNING.PRESSURE_RETRY
                elseif beginTelegraph(nest.id, state) then
                    local interval = pressureIntervalFor(state, isWell)
                    pressure[nest.id] = interval
                        + (love.math.random() * 1.6 - 0.4)
                    spawnedThisFrame = true
                else
                    pressure[nest.id] = TUNING.PRESSURE_RETRY
                end
            else
                pressure[nest.id] = t
            end
        end
    end
end

function encounter_director.drawWorld()
    if #pending == 0 then
        return
    end
    for _, entry in ipairs(pending) do
        local defaults = enemy_types.defaults[entry.enemyType]
        local col = defaults and defaults.color or { 0.8, 0.4, 0.3 }
        local progress = 1 - math.max(0, entry.timer) / (entry.maxTimer or TUNING.TELEGRAPH_SECONDS)
        local pulse = 0.55 + 0.45 * math.sin(progress * math.pi * 4)
        local radius = 6 + progress * 8
        love.graphics.setColor(col[1], col[2], col[3], 0.25 + 0.35 * pulse)
        love.graphics.circle("fill", entry.x, entry.y, radius)
        love.graphics.setColor(col[1], col[2], col[3], 0.55 + 0.35 * pulse)
        love.graphics.setLineWidth(1.5)
        love.graphics.circle("line", entry.x, entry.y, radius + 2)
        love.graphics.circle("line", entry.x, entry.y, 3 + progress * 2)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function encounter_director.debugCounts(state)
    return {
        active = countActive(state) - #pending,
        pending = #pending,
        cap = TUNING.MAX_ACTIVE,
    }
end

local function livingEnemies(state)
    local list = {}
    for _, actor in ipairs(state.actors or {}) do
        if actor.label == "enemy" and not actor.dead then
            list[#list + 1] = actor
        end
    end
    return list
end

--- Headless acceptance: 90s pressure sim, cap, floor safety, cleanse stop, restart prep.
function encounter_director.runSelftest(state)
    local ok = true
    local function check(name, cond)
        if cond then
            print("[encounter_selftest] PASS  " .. name)
        else
            print("[encounter_selftest] FAIL  " .. name)
            ok = false
        end
        return cond
    end

    check("director loaded", loaded == true)
    check("isSpawnClear helper", type(physics.isSpawnClear) == "function")
    check("isUnsafeFloor helper", type(collapse.isUnsafeFloor) == "function")
    check("prepareRestart hook", state and type(state.prepareRestart) == "function")

    local playerActor = state:getActor("player")
    check("player present", playerActor ~= nil)

    -- Park on protected fountain so collapse cannot EXTRACT the sim player.
    if playerActor and playerActor.collider then
        local fx, fy = 15 * 16, 12 * 16
        playerActor.collider:setPosition(fx, fy)
        playerActor.pos.x, playerActor.pos.y = fx, fy
    end
    if state.countdown then
        state.countdown:pause()
    end
    state.extracted = false
    state.sectorCleared = false

    local spawned = 0
    local maxSeen = 0
    local emptyStreak = 0
    local maxEmptyStreak = 0
    local unsafeSpawn = false
    local overCap = false
    local nestASpawnsAfterCleanse = 0

    local originalComplete = completeSpawn
    completeSpawn = function(entry, st)
        if not physics.isSpawnClear(entry.x, entry.y, TUNING.SPAWN_HALF_W, TUNING.SPAWN_HALF_H)
            or not floorClear(entry.x, entry.y)
        then
            unsafeSpawn = true
        end
        local before = #livingEnemies(st)
        originalComplete(entry, st)
        local after = #livingEnemies(st)
        if after > before then
            spawned = spawned + 1
            if st._nestACleansed and entry.nestId == "a" then
                nestASpawnsAfterCleanse = nestASpawnsAfterCleanse + 1
            end
        end
    end

    local dt = 0.1
    local simTime = 90
    for t = 0, simTime, dt do
        state.extracted = false
        state.sectorCleared = false
        if playerActor and cam then
            cam:lookAt(playerActor.pos.x, playerActor.pos.y)
        end

        -- Mid-run wipe: pressure must refill (arena never permanently empty).
        if t >= 25 and t < 25 + dt then
            for _, actor in ipairs(livingEnemies(state)) do
                actor:destroyNow({ reward = false })
            end
            pending = {}
            for _, nestId in ipairs(nestsMod.order()) do
                if nestUncleansed(state, nestId) then
                    pressure[nestId] = 0.05
                end
            end
        end

        -- Cleanse nest A at 40s — must stop its pressure permanently.
        if t >= 40 and t < 40 + dt and state.nests then
            for _, nest in ipairs(state.nests) do
                if nest.id == "a" and not nest.cleansed then
                    nest.cleansed = true
                    nest.progress = 1
                    encounter_director.onNestCleansed(nest, state)
                    state._nestACleansed = true
                end
            end
        end

        collapse.update(dt, state)
        encounter_director.update(state, dt)

        local counts = encounter_director.debugCounts(state)
        local total = counts.active + counts.pending
        if total > maxSeen then
            maxSeen = total
        end
        if total > TUNING.MAX_ACTIVE then
            overCap = true
        end
        if counts.active == 0 and counts.pending == 0 then
            emptyStreak = emptyStreak + dt
            if emptyStreak > maxEmptyStreak then
                maxEmptyStreak = emptyStreak
            end
        else
            emptyStreak = 0
        end
    end

    completeSpawn = originalComplete
    state._nestACleansed = nil

    check("never exceeded active cap", not overCap and maxSeen <= TUNING.MAX_ACTIVE)
    check("produced sustained spawns", spawned >= 3)
    check("no wall/fallen/cracking spawns", not unsafeSpawn)
    check("cleansed nest A stopped spawning", nestASpawnsAfterCleanse == 0)
    -- After the wipe at t=25, pressure should refill before a long empty drought.
    check("arena did not stay permanently empty", maxEmptyStreak < 12)

    -- Restart preparation: rebuild must leave a sane director + actor set.
    if state.prepareRestart then
        state:prepareRestart()
        local after = encounter_director.debugCounts(state)
        check("restart restored player", state:getActor("player") ~= nil)
        check("restart under cap", after.active + after.pending <= TUNING.MAX_ACTIVE)
        check("restart pending cleared", after.pending == 0)
    end

    print(string.format(
        "[encounter_selftest] spawned=%d maxActive=%d maxEmpty=%.1fs",
        spawned,
        maxSeen,
        maxEmptyStreak
    ))
    return ok
end

return encounter_director
