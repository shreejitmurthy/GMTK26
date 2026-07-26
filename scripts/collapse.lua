-- Courtyard collapse: floor tiles telegraph, then fall into abyss voids.
-- Pressure scales with plague tolerance. Never closing-wall rings.
--
-- FAIRNESS / DEATH RULE (documented):
--   Cracking telegraph = 1.0s. Selection never starts on the player's cell
--   (Chebyshev ≥ 2). If the player is still on a cell when it becomes fallen,
--   they are EXTRACTED (game over) — abyss, not a soft shove. Enemies on a
--   falling cell are destroyed.

local atmosphere = require "scripts.atmosphere"

local collapse = {}

local MAP_W, MAP_H, TILE = 30, 24, 16
local CRACK_SECONDS = 1.0
local FALL_SECONDS = 0.55
local MAX_FALLEN_RATIO = 0.48
local FIRST_WAVE_TIME = 20
local FIRST_WAVE_RATIO = 0.85
--- Fountain stamp footprint (0-based), matches map_patch_nests.
local FOUNTAIN = { c0 = 13, c1 = 16, r0 = 10, r1 = 13 }

local SAFE, CRACKING, FALLEN = "safe", "cracking", "fallen"

local cells = {}
local falling = {}
local mapRef = nil
local elapsed = 0
local waveCooldown = 0
local started = false
local fallenCount = 0
local rumble = 0
local protected = {}

local function idx(col, row)
    return row * MAP_W + col + 1
end

local function inBounds(col, row)
    return col >= 0 and col < MAP_W and row >= 0 and row < MAP_H
end

local function chebyshev(c0, r0, c1, r1)
    return math.max(math.abs(c0 - c1), math.abs(r0 - r1))
end

local function worldToCell(x, y)
    return math.floor(x / TILE), math.floor(y / TILE)
end

local function cellCenter(col, row)
    return (col + 0.5) * TILE, (row + 0.5) * TILE
end

local function isFountain(col, row)
    return col >= FOUNTAIN.c0 and col <= FOUNTAIN.c1
        and row >= FOUNTAIN.r0 and row <= FOUNTAIN.r1
end

local function protectCorridor(c0, r0, c1, r1, radius)
    radius = radius or 1
    local steps = math.max(math.abs(c1 - c0), math.abs(r1 - r0), 1)
    for s = 0, steps do
        local t = s / steps
        local c = math.floor(c0 + (c1 - c0) * t + 0.5)
        local r = math.floor(r0 + (r1 - r0) * t + 0.5)
        for dr = -radius, radius do
            for dc = -radius, radius do
                if math.abs(dc) + math.abs(dr) <= radius then
                    local cc, rr = c + dc, r + dr
                    if inBounds(cc, rr) then
                        protected[idx(cc, rr)] = true
                    end
                end
            end
        end
    end
end

local function rebuildProtected(nests, ratio)
    protected = {}
    for row = 0, MAP_H - 1 do
        for col = 0, MAP_W - 1 do
            if isFountain(col, row) then
                protected[idx(col, row)] = true
            end
        end
    end

    -- Nest pads never collapse. Wider pad while plague tolerance is still mid/high.
    local nestPad = (ratio >= 0.3) and 2 or 1
    for _, nest in ipairs(nests or {}) do
        local nc, nr = worldToCell(nest.x, nest.y)
        for dr = -nestPad, nestPad do
            for dc = -nestPad, nestPad do
                local c, r = nc + dc, nr + dr
                if inBounds(c, r) then
                    protected[idx(c, r)] = true
                end
            end
        end
    end

    -- Keep approach lanes + nest-to-nest corridors until late game.
    if ratio >= 0.22 then
        local live = {}
        for _, nest in ipairs(nests or {}) do
            if not nest.cleansed then
                live[#live + 1] = nest
            end
        end
        local fx, fy = 14, 11
        for i = 1, #live do
            local c1, r1 = worldToCell(live[i].x, live[i].y)
            protectCorridor(fx, fy, c1, r1, 1)
            for j = i + 1, #live do
                local c2, r2 = worldToCell(live[j].x, live[j].y)
                protectCorridor(c1, r1, c2, r2, 1)
            end
        end
    end
end

local function getFloorTile(col, row)
    if not mapRef then
        return nil
    end
    local layer = mapRef.layers["Floor Layer"]
    if not layer or not layer.data then
        return nil
    end
    local rowData = layer.data[row + 1]
    return rowData and rowData[col + 1] or nil
end

local function clearLayerTile(layerName, col, row)
    if not mapRef or not mapRef.setLayerTile then
        return
    end
    if not mapRef.layers[layerName] then
        return
    end
    -- STI coords are 1-based; gid 0 / nil removes the instance from the batch.
    mapRef:setLayerTile(layerName, col + 1, row + 1, 0)
end

local function clearFloorTile(col, row)
    clearLayerTile("Floor Layer", col, row)
    -- Props/decals must not remain as "black floor tiles" or fake ledges over voids.
    clearLayerTile("Props", col, row)
    clearLayerTile("Props Layer", col, row)
    clearLayerTile("Decals A", col, row)
    clearLayerTile("Decals B", col, row)
    clearLayerTile("Decals C", col, row)
end

--- Floor-grid open for nest-reach BFS (fallen/cracking = blocked).
local function isPathOpen(col, row, extraBlocked)
    if not inBounds(col, row) then
        return false
    end
    local i = idx(col, row)
    if extraBlocked and extraBlocked[i] then
        return false
    end
    local cell = cells[i]
    if not cell then
        return false
    end
    return cell.state == SAFE
end

local function canReachFountain(col, row, extraBlocked)
    if not isPathOpen(col, row, extraBlocked) then
        return false
    end
    local startI = idx(col, row)
    local queue = { { col, row } }
    local seen = { [startI] = true }
    local q = 1
    while q <= #queue do
        local c, r = queue[q][1], queue[q][2]
        q = q + 1
        if isFountain(c, r) then
            return true
        end
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nc, nr = c + d[1], r + d[2]
            local ni = idx(nc, nr)
            if not seen[ni] and isPathOpen(nc, nr, extraBlocked) then
                seen[ni] = true
                queue[#queue + 1] = { nc, nr }
            end
        end
    end
    return false
end

local function uncleansedNestsStillReachable(nests, extraBlocked)
    for _, nest in ipairs(nests or {}) do
        if not nest.cleansed then
            local nc, nr = worldToCell(nest.x, nest.y)
            if not canReachFountain(nc, nr, extraBlocked) then
                return false
            end
        end
    end
    return true
end

local function uncleansedCount(nests)
    local n = 0
    for _, nest in ipairs(nests or {}) do
        if not nest.cleansed then
            n = n + 1
        end
    end
    return n
end

local function edgeScore(col, row)
    return math.min(col, row, MAP_W - 1 - col, MAP_H - 1 - row)
end

local function fountainDist(col, row)
    local fx, fy = 15, 12
    local dx, dy = col + 0.5 - fx, row + 0.5 - fy
    return math.sqrt(dx * dx + dy * dy)
end

local function pickCandidates(playerCol, playerRow, ratio, nests)
    local list = {}
    local maxFallen = math.floor(MAP_W * MAP_H * MAX_FALLEN_RATIO)
    if fallenCount >= maxFallen then
        return list
    end

    for row = 0, MAP_H - 1 do
        for col = 0, MAP_W - 1 do
            local cell = cells[idx(col, row)]
            if cell
                and cell.state == SAFE
                and not protected[idx(col, row)]
                and chebyshev(col, row, playerCol, playerRow) >= 2
            then
                -- Never isolate an uncleansed nest behind voids too early.
                local blocked = { [idx(col, row)] = true }
                if not uncleansedNestsStillReachable(nests, blocked) then
                    -- skip
                else
                    local edge = edgeScore(col, row)
                    local away = fountainDist(col, row)
                    -- Prefer edges + away from fountain; slight noise.
                    local weight = (6 - math.min(edge, 5)) * 3 + away * 0.8
                    weight = weight + love.math.random() * 2
                    if ratio < 0.5 then
                        weight = weight + (5 - edge)
                    end
                    list[#list + 1] = { col = col, row = row, weight = weight }
                end
            end
        end
    end
    return list
end

local function weightedPick(list)
    if #list == 0 then
        return nil
    end
    local sum = 0
    for _, item in ipairs(list) do
        sum = sum + item.weight
    end
    local roll = love.math.random() * sum
    local acc = 0
    for _, item in ipairs(list) do
        acc = acc + item.weight
        if roll <= acc then
            return item
        end
    end
    return list[#list]
end

local function beginCrack(col, row)
    local cell = cells[idx(col, row)]
    if not cell or cell.state ~= SAFE or protected[idx(col, row)] then
        return false
    end
    local tile = getFloorTile(col, row)
    cell.state = CRACKING
    cell.timer = CRACK_SECONDS
    cell.shake = 0
    if tile then
        cell.gid = tile.gid
        cell.quad = tile.quad
        local ts = mapRef.tilesets[tile.tileset]
        cell.image = ts and ts.image or nil
    end
    local cx, cy = cellCenter(col, row)
    if atmosphere.burstAt then
        atmosphere.burstAt(cx, cy, "ash", 4)
    end
    return true
end

local function beginFall(col, row, state)
    local cell = cells[idx(col, row)]
    if not cell or cell.state ~= CRACKING then
        return
    end
    cell.state = FALLEN
    cell.timer = 0
    fallenCount = fallenCount + 1
    clearFloorTile(col, row)

    local x, y = col * TILE, row * TILE
    falling[#falling + 1] = {
        x = x,
        y = y,
        oy = 0,
        alpha = 1,
        vy = 40,
        life = FALL_SECONDS,
        image = cell.image,
        quad = cell.quad,
    }

    if atmosphere.burstAt then
        atmosphere.burstAt(x + TILE * 0.5, y + TILE * 0.5, "ash", 6)
    end

    -- Player on this cell when it drops → EXTRACTED (abyss).
    local playerActor = state and state:getActor("player")
    if playerActor and playerActor.collider and not state.extracted then
        local pc, pr = worldToCell(playerActor.collider:getX(), playerActor.collider:getY())
        if pc == col and pr == row then
            state.extracted = true
            state.extractReason = "abyss"
            falling = {} -- stop mid-fall quads; game over is a hard freeze
            if state.countdown then
                state.countdown:pause()
            end
            if state.pushFloat then
                local cx, cy = cellCenter(col, row)
                state:pushFloat("EXTRACTED", cx, cy - 10, 0.95, 0.82, 0.62, 0.75)
            end
            print("[collapse] EXTRACTED — fell into the abyss")
        end
    end

    -- Enemies on falling cell: destroy physics immediately (no void ghosts / no +time).
    if state and state.actors then
        for i = #state.actors, 1, -1 do
            local actor = state.actors[i]
            if actor.label == "enemy" and not actor.dead and actor.collider then
                local ec, er = worldToCell(actor.collider:getX(), actor.collider:getY())
                if ec == col and er == row then
                    if actor.destroyNow then
                        actor:destroyNow({ reward = false })
                    else
                        state:removeActor(actor)
                    end
                end
            end
        end
    end
end

local function runWave(state, ratio)
    local playerActor = state:getActor("player")
    if not playerActor or not playerActor.collider then
        return
    end
    local pc, pr = worldToCell(playerActor.collider:getX(), playerActor.collider:getY())
    rebuildProtected(state.nests, ratio)

    local uncleansed = uncleansedCount(state.nests)
    local pressure = 1 - ratio
    local drops = 1 + math.floor(pressure * 3)
    if uncleansed >= 2 then
        drops = drops + 1
    end
    if ratio < 0.35 then
        drops = drops + 1
    end
    drops = math.min(drops, 5)

    local candidates = pickCandidates(pc, pr, ratio, state.nests)
    local cracked = 0
    for _ = 1, drops do
        if #candidates == 0 then
            break
        end
        local pick = weightedPick(candidates)
        if not pick then
            break
        end
        -- Re-check isolation against cracks already chosen this wave.
        local blocked = { [idx(pick.col, pick.row)] = true }
        for row = 0, MAP_H - 1 do
            for col = 0, MAP_W - 1 do
                if cells[idx(col, row)].state == CRACKING then
                    blocked[idx(col, row)] = true
                end
            end
        end
        if not uncleansedNestsStillReachable(state.nests, blocked) then
            -- Drop this pick and try others.
            local filteredSkip = {}
            for _, item in ipairs(candidates) do
                if item.col ~= pick.col or item.row ~= pick.row then
                    filteredSkip[#filteredSkip + 1] = item
                end
            end
            candidates = filteredSkip
        elseif beginCrack(pick.col, pick.row) then
            cracked = cracked + 1
            -- Remove picked + nearby from this wave's pool so drops spread.
            local filtered = {}
            for _, item in ipairs(candidates) do
                if chebyshev(item.col, item.row, pick.col, pick.row) > 1 then
                    filtered[#filtered + 1] = item
                end
            end
            candidates = filtered
        else
            local filteredFail = {}
            for _, item in ipairs(candidates) do
                if item.col ~= pick.col or item.row ~= pick.row then
                    filteredFail[#filteredFail + 1] = item
                end
            end
            candidates = filteredFail
        end
    end
    if cracked > 0 then
        print(string.format(
            "[collapse] wave: %d cracking (fallen %d / max ~%d, ratio=%.2f)",
            cracked,
            fallenCount,
            math.floor(MAP_W * MAP_H * MAX_FALLEN_RATIO),
            ratio
        ))
    end
end

function collapse.load(map, nests)
    mapRef = map
    cells = {}
    falling = {}
    elapsed = 0
    waveCooldown = 0
    started = false
    fallenCount = 0
    rumble = 0
    rebuildProtected(nests, 1)
    for row = 0, MAP_H - 1 do
        for col = 0, MAP_W - 1 do
            cells[idx(col, row)] = {
                col = col,
                row = row,
                state = SAFE,
                timer = 0,
                shake = 0,
                gid = 0,
                quad = nil,
                image = nil,
            }
        end
    end
end

function collapse.update(dt, state)
    if not state or state.extracted or state.sectorCleared or state.enemyTestMode then
        rumble = math.max(0, rumble - dt * 3)
        return
    end

    elapsed = elapsed + dt
    if rumble > 0 then
        rumble = math.max(0, rumble - dt * 3)
    end

    local ratio = state.countdown and state.countdown:getRatio() or 1

    if not started then
        if elapsed >= FIRST_WAVE_TIME or ratio < FIRST_WAVE_RATIO then
            started = true
            waveCooldown = 0
            runWave(state, ratio)
            waveCooldown = 3.8
        end
    else
        waveCooldown = waveCooldown - dt
        if waveCooldown <= 0 then
            local pressure = 1 - ratio
            local interval = 4.2 - pressure * 2.8
            if uncleansedCount(state.nests) >= 2 then
                interval = interval - 0.4
            end
            interval = math.max(1.1, interval)
            runWave(state, ratio)
            waveCooldown = interval
        end
    end

    -- Advance cracks → falls.
    for row = 0, MAP_H - 1 do
        for col = 0, MAP_W - 1 do
            local cell = cells[idx(col, row)]
            if cell.state == CRACKING then
                cell.timer = cell.timer - dt
                cell.shake = cell.shake + dt * 28
                if cell.timer <= 0 then
                    beginFall(col, row, state)
                    if state.extracted then
                        return
                    end
                end
            end
        end
    end

    for i = #falling, 1, -1 do
        local f = falling[i]
        f.life = f.life - dt
        f.vy = f.vy + 520 * dt
        f.oy = f.oy + f.vy * dt
        f.alpha = math.max(0, f.life / FALL_SECONDS)
        if f.life <= 0 or f.oy > MAP_H * TILE then
            table.remove(falling, i)
        end
    end

    -- Safety: if somehow standing on already-fallen (teleport edge case).
    local playerActor = state:getActor("player")
    if playerActor and playerActor.collider and not state.extracted then
        local pc, pr = worldToCell(playerActor.collider:getX(), playerActor.collider:getY())
        if inBounds(pc, pr) and cells[idx(pc, pr)].state == FALLEN then
            state.extracted = true
            state.extractReason = "abyss"
            falling = {}
            if state.countdown then
                state.countdown:pause()
            end
            if state.pushFloat then
                local cx, cy = cellCenter(pc, pr)
                state:pushFloat("EXTRACTED", cx, cy - 10, 0.95, 0.82, 0.62, 0.75)
            end
            print("[collapse] EXTRACTED — stood in abyss")
        end
    end
end

--- Plain black hole — crack telegraph, then the tile is gone.
local function drawFallenCell(x, y)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", x, y, TILE, TILE)
end

--- Abyss voids + crack telegraph (draw after Floor / decals / props).
function collapse.drawFloorFx()
    love.graphics.setLineWidth(1)
    for row = 0, MAP_H - 1 do
        for col = 0, MAP_W - 1 do
            local cell = cells[idx(col, row)]
            local x, y = col * TILE, row * TILE
            if cell.state == FALLEN then
                drawFallenCell(x, y)
            elseif cell.state == CRACKING then
                -- Stable crack lines only (no tile shake — that read as jitter).
                local pulse = 0.55 + 0.45 * math.sin(cell.shake)
                love.graphics.setColor(0.06, 0.04, 0.03, 0.2 + 0.12 * pulse)
                love.graphics.rectangle("fill", x, y, TILE, TILE)
                love.graphics.setColor(0.9, 0.65, 0.3, 0.5 + 0.35 * pulse)
                love.graphics.line(x + 3, y + 4, x + 12, y + 13)
                love.graphics.line(x + 11, y + 3, x + 4, y + 14)
                love.graphics.line(x + 2, y + 9, x + 14, y + 8)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

--- Falling tile quads (above floor; call after actors or after floor fx).
function collapse.drawFalling()
    for _, f in ipairs(falling) do
        if f.image and f.quad then
            love.graphics.setColor(1, 1, 1, f.alpha)
            love.graphics.draw(f.image, f.quad, f.x, f.y + f.oy)
        else
            love.graphics.setColor(0.25, 0.28, 0.32, f.alpha * 0.9)
            love.graphics.rectangle("fill", f.x, f.y + f.oy, TILE, TILE)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

--- Keep the black hole visible above the falling cobble quad.
function collapse.drawFallenOverlay()
    for row = 0, MAP_H - 1 do
        for col = 0, MAP_W - 1 do
            if cells[idx(col, row)].state == FALLEN then
                drawFallenCell(col * TILE, row * TILE)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

--- Camera shake disabled — random rumble felt like movement jitter near voids.
function collapse.getRumble()
    return 0, 0
end

--- Debug: crack one safe cell near the player (never under feet).
function collapse.debugCrackNearPlayer(state)
    local playerActor = state and state:getActor("player")
    if not playerActor or not playerActor.collider then
        return false
    end
    local ratio = state.countdown and state.countdown:getRatio() or 1
    rebuildProtected(state.nests, ratio)
    local pc, pr = worldToCell(playerActor.collider:getX(), playerActor.collider:getY())
    local best, bestD
    for row = 0, MAP_H - 1 do
        for col = 0, MAP_W - 1 do
            local d = chebyshev(col, row, pc, pr)
            if d >= 2 and d <= 4
                and cells[idx(col, row)].state == SAFE
                and not protected[idx(col, row)]
            then
                local blocked = { [idx(col, row)] = true }
                if uncleansedNestsStillReachable(state.nests, blocked) then
                    if not bestD or d < bestD then
                        bestD = d
                        best = { col = col, row = row }
                    end
                end
            end
        end
    end
    if best and beginCrack(best.col, best.row) then
        started = true
        -- Avoid an immediate pressure wave right after a manual crack.
        waveCooldown = math.max(waveCooldown, 3.5)
        print(string.format("[collapse] debug crack at %d,%d", best.col, best.row))
        return true
    end
    print("[collapse] debug crack: no candidate near player")
    return false
end

--- Debug / verify: immediately drop a cell (telegraph skipped).
function collapse.debugForceFallAt(col, row, state)
    if not inBounds(col, row) then
        return false
    end
    local cell = cells[idx(col, row)]
    if not cell or cell.state == FALLEN then
        return false
    end
    if cell.state ~= CRACKING then
        if protected[idx(col, row)] then
            return false
        end
        beginCrack(col, row)
    end
    if cells[idx(col, row)].state == CRACKING then
        beginFall(col, row, state)
        return true
    end
    return false
end

--- Debug: crack + instantly drop the cell under the player's center.
function collapse.debugForceFallUnderPlayer(state)
    local playerActor = state and state:getActor("player")
    if not playerActor or not playerActor.collider then
        return false
    end
    local pc, pr = worldToCell(playerActor.collider:getX(), playerActor.collider:getY())
    -- Temporarily allow fall on current cell even if nest-protected for verify.
    local wasProtected = protected[idx(pc, pr)]
    protected[idx(pc, pr)] = nil
    local cell = cells[idx(pc, pr)]
    if cell and cell.state == SAFE then
        beginCrack(pc, pr)
    end
    protected[idx(pc, pr)] = wasProtected or nil
    if cells[idx(pc, pr)].state == CRACKING then
        beginFall(pc, pr, state)
        print(string.format("[collapse] debug force-fall under player at %d,%d", pc, pr))
        return true
    end
    return false
end

function collapse.getFallenCount()
    return fallenCount
end

function collapse.isFallenCell(col, row)
    if not inBounds(col, row) then
        return false
    end
    return cells[idx(col, row)].state == FALLEN
end

function collapse.isCrackingCell(col, row)
    if not inBounds(col, row) then
        return false
    end
    return cells[idx(col, row)].state == CRACKING
end

--- World-space floor reject for spawns (fallen or cracking = unsafe).
function collapse.isUnsafeFloor(x, y)
    local col, row = worldToCell(x, y)
    if not inBounds(col, row) then
        return true
    end
    local s = cells[idx(col, row)].state
    return s == FALLEN or s == CRACKING
end

--- Read-only acceptance hook for map/collapse protection tests.
function collapse.isProtectedCell(col, row)
    return inBounds(col, row) and protected[idx(col, row)] == true
end

return collapse
