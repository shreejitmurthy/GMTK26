-- Windfield physics world helpers (top-down, zero gravity).
-- STI can later feed walls through addWall / addWallsFromObjects.

local wf = require "lib.windfield"

local physics = {
    world = nil,
    walls = {},
    enemies = {},
    debug = false,
}

local CLASS_NAMES = {
    "Player",
    "Enemy",
    "Wall",
    "PlayerAttack",
    "EnemyHit",
}

function physics.init()
    -- Zero gravity top-down world (sleeping enabled).
    physics.world = wf.newWorld(0, 0, true)
    physics.walls = {}
    physics.enemies = {}

    physics.world:addCollisionClass("Player")
    -- Kinematic enemies must not solid-shove the dynamic player (that tunnels through walls
    -- when cornered). Soft resistance + separation handle player↔enemy feel instead.
    -- Kinematic↔kinematic / kinematic↔static also never resolve in Box2D, so wall slide
    -- and enemy separation are applied in constrainEnemyMotion.
    physics.world:addCollisionClass("Enemy", {
        ignores = { "Player" },
    })
    physics.world:addCollisionClass("Wall")
    -- Sensors: detect overlaps but ignore solid resolve with most solids via setSensor.
    -- Register EnemyHit before PlayerAttack (PlayerAttack ignores EnemyHit for Windfield's
    -- sensor enter path; the unmasked sensor fixtures still generate contact).
    physics.world:addCollisionClass("EnemyHit", {
        ignores = { "Enemy", "Wall", "EnemyHit" },
    })
    physics.world:addCollisionClass("PlayerAttack", {
        ignores = { "Player", "Wall", "PlayerAttack", "EnemyHit" },
    })

    return physics.world
end

function physics.getWorld()
    return physics.world
end

function physics.getClassNames()
    return CLASS_NAMES
end

function physics.update(dt)
    if physics.world then
        physics.world:update(dt)
    end
end

function physics.drawDebug(alpha)
    if physics.world and physics.debug then
        physics.world:draw(alpha)
    end
end

function physics.toggleDebug()
    physics.debug = not physics.debug
    return physics.debug
end

function physics.getGravity()
    if not physics.world then
        return nil, nil
    end
    return physics.world:getGravity()
end

--- Dynamic player body. x/y are top-left of the hitbox (Windfield BSG convention).
function physics.newPlayerCollider(x, y, w, h, corner)
    local collider = physics.world:newBSGRectangleCollider(x, y, w, h, corner or 2)
    collider:setFixedRotation(true)
    collider:setCollisionClass("Player")
    collider:setType("dynamic")
    collider.halfWidth = w / 2
    collider.halfHeight = h / 2
    return collider
end

--- Soft enemy body. It blocks the player without receiving collision momentum.
--- x/y are top-left of the hitbox (Windfield BSG convention).
function physics.newEnemyCollider(x, y, w, h, corner, options)
    options = options or {}
    local collider = physics.world:newBSGRectangleCollider(x, y, w, h, corner or 2)
    collider:setFixedRotation(true)
    collider:setCollisionClass("Enemy")
    collider:setType("kinematic")
    collider:setRestitution(0)
    collider:setFriction(options.friction or 0.1)
    collider.halfWidth = w / 2
    collider.halfHeight = h / 2
    collider.softPadding = math.max(0.01, options.softPadding or 10)
    collider.resistanceExponent = math.max(0.01, options.resistanceExponent or 2)
    collider.pushAnchorX = collider:getX()
    collider.pushAnchorY = collider:getY()
    collider.maxPushDistance = math.max(0, options.maxPushDistance or 3)
    collider.pushSpeed = math.max(0, options.pushSpeed or 6)
    -- Stable IDs make head-on avoidance deterministic instead of jittering sides.
    collider.separationId = #physics.enemies + 1
    physics.enemies[#physics.enemies + 1] = collider
    return collider
end

--- Remove only the velocity component aimed into a soft collider.
--- strength 0 leaves velocity unchanged; strength 1 fully blocks inward motion.
function physics.resistInwardVelocity(vx, vy, nx, ny, strength)
    local inwardSpeed = vx * nx + vy * ny
    if inwardSpeed >= 0 then
        return vx, vy
    end

    strength = math.max(0, math.min(1, strength))
    return vx - nx * inwardSpeed * strength,
        vy - ny * inwardSpeed * strength
end

--- Nudge an enemy away from contact without giving it velocity. Movement is
--- bounded around its anchor, so sustained pressure cannot shove it far away.
function physics.nudgeEnemy(enemyCollider, nx, ny, strength, dt)
    if strength <= 0 or enemyCollider.maxPushDistance <= 0 then
        return
    end

    local step = enemyCollider.pushSpeed * dt * math.min(1, strength)
    local nextX = enemyCollider:getX() - nx * step
    local nextY = enemyCollider:getY() - ny * step
    local offsetX = nextX - enemyCollider.pushAnchorX
    local offsetY = nextY - enemyCollider.pushAnchorY
    local offsetLength = math.sqrt(offsetX * offsetX + offsetY * offsetY)

    if offsetLength > enemyCollider.maxPushDistance then
        local scale = enemyCollider.maxPushDistance / offsetLength
        offsetX, offsetY = offsetX * scale, offsetY * scale
    end

    enemyCollider:setPosition(
        enemyCollider.pushAnchorX + offsetX,
        enemyCollider.pushAnchorY + offsetY
    )
    enemyCollider:setLinearVelocity(0, 0)
end

--- Apply increasingly strong resistance as the player approaches an enemy body.
--- At near-contact it also gives the enemy a tiny, position-limited nudge.
--- When overlapping the hard contact radius, add gentle outward separation so
--- chasing enemies (which ignore Player solids) still displace the player without
--- Box2D crushing them through walls.
function physics.applyEnemyResistance(playerCollider, vx, vy, dt)
    local px, py = playerCollider:getX(), playerCollider:getY()
    local playerHalfW = playerCollider.halfWidth or 0
    local playerHalfH = playerCollider.halfHeight or 0
    -- Cap outward push so soft contact cannot launch the player.
    local maxSeparation = 90

    for _, enemyCollider in ipairs(physics.enemies) do
        if not enemyCollider:isDestroyed() then
            local ex, ey = enemyCollider:getX(), enemyCollider:getY()
            local dx, dy = px - ex, py - ey
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance > 0 then
                local nx, ny = dx / distance, dy / distance
                local contactDistance =
                    playerHalfW * math.abs(nx)
                    + playerHalfH * math.abs(ny)
                    + enemyCollider.halfWidth * math.abs(nx)
                    + enemyCollider.halfHeight * math.abs(ny)
                local padding = enemyCollider.softPadding
                local softDistance = contactDistance + padding

                if distance < softDistance then
                    local proximity = math.min(1, (softDistance - distance) / padding)
                    local strength = proximity ^ enemyCollider.resistanceExponent
                    local inwardSpeed = vx * nx + vy * ny
                    if inwardSpeed < 0 then
                        -- Nudge only within the innermost 20% of the cushion.
                        local pushStrength = math.max(0, (proximity - 0.8) / 0.2)
                        physics.nudgeEnemy(enemyCollider, nx, ny, pushStrength, dt)
                    end
                    vx, vy = physics.resistInwardVelocity(vx, vy, nx, ny, strength)

                    if distance < contactDistance then
                        local overlap = 1 - (distance / contactDistance)
                        local sep = maxSeparation * overlap * overlap
                        vx = vx + nx * sep
                        vy = vy + ny * sep
                    end
                end
            end
        end
    end

    return vx, vy
end

local function enemyHitsWallAt(enemyCollider, cx, cy)
    local hw = enemyCollider.halfWidth or 0
    local hh = enemyCollider.halfHeight or 0
    local hits = physics.world:queryRectangleArea(cx - hw, cy - hh, hw * 2, hh * 2, { "Wall" })
    return #hits > 0
end

--- True when no solid Wall collider blocks the segment between two points.
function physics.hasLineOfSight(x1, y1, x2, y2)
    if not physics.world then
        return false
    end
    local blockers = physics.world:queryLine(x1, y1, x2, y2, { "Wall" })
    return #blockers == 0
end

--- Pick a stable tangent around the player for an enemy trying to restore LOS.
--- Prefer a probe position that already has sight; otherwise keep moving along
--- an open side until the wall edge is cleared.
function physics.lineOfSightStrafeDirection(
    enemyCollider,
    targetX,
    targetY,
    preferredSide,
    probeDistance
)
    local x, y = enemyCollider:getX(), enemyCollider:getY()
    local dx, dy = targetX - x, targetY - y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 0.001 then
        return 0, 0, preferredSide or 1
    end

    local leftX, leftY = -dy / distance, dx / distance
    if preferredSide ~= -1 and preferredSide ~= 1 then
        preferredSide = ((enemyCollider.separationId or 1) % 2 == 0) and 1 or -1
    end
    probeDistance = probeDistance or 32

    local sides = { preferredSide, -preferredSide }
    local fallbackSide = nil
    for _, side in ipairs(sides) do
        local probeX = x + leftX * side * probeDistance
        local probeY = y + leftY * side * probeDistance
        if not enemyHitsWallAt(enemyCollider, probeX, probeY) then
            if physics.hasLineOfSight(probeX, probeY, targetX, targetY) then
                return leftX * side, leftY * side, side
            end
            fallbackSide = fallbackSide or side
        end
    end

    local side = fallbackSide or preferredSide
    return leftX * side, leftY * side, side
end

--- Find a visible tactical point on a ring around the target. The ring never
--- comes closer than minDistance and never shrinks the enemy's current radius.
--- One extra visible angular step gives the final position some LOS clearance,
--- rather than stopping on the exact edge of a wall.
function physics.findLineOfSightPosition(
    enemyCollider,
    targetX,
    targetY,
    minDistance,
    preferredSide
)
    local x, y = enemyCollider:getX(), enemyCollider:getY()
    local radialX, radialY = x - targetX, y - targetY
    local currentDistance = math.sqrt(radialX * radialX + radialY * radialY)
    if currentDistance < 0.001 then
        radialX, radialY, currentDistance = 1, 0, 1
    end
    radialX, radialY = radialX / currentDistance, radialY / currentDistance

    if preferredSide ~= -1 and preferredSide ~= 1 then
        preferredSide = ((enemyCollider.separationId or 1) % 2 == 0) and 1 or -1
    end

    local radius = math.max(minDistance or 0, currentDistance)
    local angleStep = math.rad(12)
    local maxSteps = 15
    local clearanceSteps = 1

    local function candidate(side, step)
        local angle = angleStep * step * side
        local cosA, sinA = math.cos(angle), math.sin(angle)
        local dirX = radialX * cosA - radialY * sinA
        local dirY = radialX * sinA + radialY * cosA
        return targetX + dirX * radius, targetY + dirY * radius
    end

    local function visibleCandidate(side, step)
        local candidateX, candidateY = candidate(side, step)
        if enemyHitsWallAt(enemyCollider, candidateX, candidateY) then
            return nil
        end
        if not physics.hasLineOfSight(candidateX, candidateY, targetX, targetY) then
            return nil
        end
        return candidateX, candidateY
    end

    local results = {}
    local sides = { preferredSide, -preferredSide }
    for _, side in ipairs(sides) do
        for step = 1, maxSteps do
            local candidateX, candidateY = visibleCandidate(side, step)
            if candidateX then
                local goalX, goalY = candidateX, candidateY
                for extra = 1, clearanceSteps do
                    local clearX, clearY = visibleCandidate(side, step + extra)
                    if not clearX then
                        break
                    end
                    goalX, goalY = clearX, clearY
                end
                results[#results + 1] = {
                    x = goalX,
                    y = goalY,
                    side = side,
                    entryStep = step,
                }
                break
            end
        end
    end

    if #results == 0 then
        return nil
    end
    table.sort(results, function(a, b)
        if a.entryStep == b.entryStep then
            return a.side == preferredSide
        end
        return a.entryStep < b.entryStep
    end)
    return results[1].x, results[1].y, results[1].side
end

--- Zero velocity into walls (kinematic bodies do not resolve vs static Wall).
function physics.slideEnemyAgainstWalls(enemyCollider, vx, vy, dt)
    dt = dt or (1 / 60)
    local x, y = enemyCollider:getX(), enemyCollider:getY()

    if enemyHitsWallAt(enemyCollider, x, y) then
        -- Already embedded: step out along cardinals, then halt this frame.
        for dist = 2, 28, 2 do
            local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
            for _, dir in ipairs(dirs) do
                local nx, ny = x + dir[1] * dist, y + dir[2] * dist
                if not enemyHitsWallAt(enemyCollider, nx, ny) then
                    enemyCollider:setPosition(nx, ny)
                    return 0, 0
                end
            end
        end
        return 0, 0
    end

    local nextX, nextY = x + vx * dt, y + vy * dt
    if enemyHitsWallAt(enemyCollider, nextX, nextY) then
        if enemyHitsWallAt(enemyCollider, nextX, y) then
            vx = 0
        end
        if enemyHitsWallAt(enemyCollider, x, nextY) then
            vy = 0
        end
        if enemyHitsWallAt(enemyCollider, x + vx * dt, y + vy * dt) then
            vx, vy = 0, 0
        end
    end

    return vx, vy
end

-- Light pack spacing: a little wider than the 14px placeholder enemy body.
physics.enemyMinSep = 28

local function deterministicPairSide(a, b)
    local aId = a.separationId or 0
    local bId = b.separationId or 0
    return ((aId + bId) % 2 == 0) and 1 or -1
end

local function overlapDirection(a, b)
    local aId = a.separationId or 0
    local bId = b.separationId or 0
    local lowId = math.min(aId, bId)
    local highId = math.max(aId, bId)
    local angle = (lowId * 2.399963 + highId * 0.618034) % (math.pi * 2)
    local sign = aId <= bId and 1 or -1
    return math.cos(angle) * sign, math.sin(angle) * sign
end

--- Add a small push-apart into AI velocity. When another enemy is directly in
--- the way, turn most of that push sideways so chargers flow around the pack.
function physics.applyEnemySeparation(enemyCollider, vx, vy, minSep, separationSpeed)
    minSep = minSep or physics.enemyMinSep
    local x, y = enemyCollider:getX(), enemyCollider:getY()
    local sepX, sepY = 0, 0
    local inputSpeed = math.sqrt(vx * vx + vy * vy)
    local dirX, dirY, leftX, leftY
    if inputSpeed > 0.01 then
        dirX, dirY = vx / inputSpeed, vy / inputSpeed
        leftX, leftY = -dirY, dirX
    end

    for _, other in ipairs(physics.enemies) do
        if other ~= enemyCollider and not other:isDestroyed() then
            local ox, oy = other:getX(), other:getY()
            local dx, dy = x - ox, y - oy
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < minSep then
                local weight = (minSep - dist) / minSep
                local awayX, awayY
                if dist > 0.001 then
                    awayX, awayY = dx / dist, dy / dist
                else
                    awayX, awayY = overlapDirection(enemyCollider, other)
                end

                -- A directly-ahead neighbour would otherwise make the follower
                -- keep pushing straight into it after the final speed clamp.
                if dirX and awayX * dirX + awayY * dirY < -0.7 then
                    local lateral = awayX * leftX + awayY * leftY
                    local side
                    if math.abs(lateral) > 0.05 then
                        side = lateral > 0 and 1 or -1
                    else
                        side = deterministicPairSide(enemyCollider, other)
                    end
                    awayX = awayX * 0.35 + leftX * side * 0.65
                    awayY = awayY * 0.35 + leftY * side * 0.65
                    local awayLength = math.sqrt(awayX * awayX + awayY * awayY)
                    awayX, awayY = awayX / awayLength, awayY / awayLength
                end

                sepX = sepX + awayX * weight
                sepY = sepY + awayY * weight
            end
        end
    end

    local sepLen = math.sqrt(sepX * sepX + sepY * sepY)
    if sepLen > 0 then
        -- Keep separation light so packs spread without dominating chase/flee intent.
        local sepBoost = separationSpeed or math.max(30, inputSpeed) * 0.4
        vx = vx + (sepX / sepLen) * sepBoost * math.min(1, sepLen)
        vy = vy + (sepY / sepLen) * sepBoost * math.min(1, sepLen)
    end

    return vx, vy
end

--- Separation + wall slide, then clamp to maxSpeed (no √2 boost from blending).
--- Idle input (near-zero velocity) skips separation so stopped enemies do not drift.
function physics.constrainEnemyMotion(enemyCollider, vx, vy, dt, maxSpeed)
    local inputSpeed = math.sqrt(vx * vx + vy * vy)
    if inputSpeed < 0.01 then
        return 0, 0
    end

    vx, vy = physics.applyEnemySeparation(
        enemyCollider,
        vx,
        vy,
        enemyCollider.separationDistance,
        enemyCollider.separationSpeed
    )
    if maxSpeed and maxSpeed > 0 then
        local speed = math.sqrt(vx * vx + vy * vy)
        if speed > 0 then
            vx = vx / speed * maxSpeed
            vy = vy / speed * maxSpeed
        end
    end
    return physics.slideEnemyAgainstWalls(enemyCollider, vx, vy, dt)
end

--- Static wall rectangle. x/y are top-left. STI-ready drop-in.
function physics.addWall(x, y, w, h)
    local wall = physics.world:newRectangleCollider(x, y, w, h)
    wall:setType("static")
    wall:setCollisionClass("Wall")
    -- Keep top-left dims for visible stub draw (colliders alone are invisible).
    wall.drawX, wall.drawY, wall.drawW, wall.drawH = x, y, w, h
    physics.walls[#physics.walls + 1] = wall
    return wall
end

--- Build walls from STI-like object tables: { x, y, width, height } (and optional shape).
function physics.addWallsFromObjects(objects)
    if not objects then
        return
    end
    for _, object in ipairs(objects) do
        if not object.shape or object.shape == "rectangle" then
            physics.addWall(object.x, object.y, object.width, object.height)
        end
    end
end

function physics.getWallCount()
    return #physics.walls
end

--- Draw stub arena walls so solid blockers are visible without F1.
function physics.drawWalls()
    love.graphics.setColor(0.32, 0.32, 0.35, 1)
    for _, wall in ipairs(physics.walls) do
        if wall.drawW then
            love.graphics.rectangle("fill", wall.drawX, wall.drawY, wall.drawW, wall.drawH)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

--- Sensor hitbox (no solid push). x/y are top-left.
function physics.newSensor(x, y, w, h, collisionClass)
    local sensor = physics.world:newRectangleCollider(x, y, w, h)
    sensor:setType("dynamic")
    sensor:setSensor(true)
    sensor:setCollisionClass(collisionClass or "PlayerAttack")
    sensor:setFixedRotation(true)
    return sensor
end

--- Temporary test arena around a center point (no STI required).
function physics.spawnTestArena(cx, cy)
    local left = cx - 160
    local top = cy - 120
    local width = 320
    local height = 240
    local thickness = 16

    physics.addWall(left, top, width, thickness) -- top
    physics.addWall(left, top + height - thickness, width, thickness) -- bottom
    physics.addWall(left, top, thickness, height) -- left
    physics.addWall(left + width - thickness, top, thickness, height) -- right
    -- Interior blockers so collision is obvious while moving.
    physics.addWall(cx - 10, cy - 70, 20, 40)
    physics.addWall(cx + 40, cy + 20, 48, 16)

    physics.arena = {
        cx = cx,
        cy = cy,
        left = left,
        top = top,
        width = width,
        height = height,
        thickness = thickness,
        innerLeft = left + thickness,
        innerTop = top + thickness,
        innerRight = left + width - thickness,
        innerBottom = top + height - thickness,
    }

    return physics.getWallCount()
end

local function spawnBlockedAt(cx, cy, halfW, halfH)
    if not physics.world then
        return true
    end
    local hits = physics.world:queryRectangleArea(
        cx - halfW,
        cy - halfH,
        halfW * 2,
        halfH * 2,
        { "Wall" }
    )
    return #hits > 0
end

--- Pick a clear point inside the stub arena, away from walls / player / prior spawns.
function physics.pickSpawnPoint(opts)
    opts = opts or {}
    local arena = physics.arena
    if not arena then
        return opts.fallbackX or 200, opts.fallbackY or 150
    end

    local pad = opts.pad or 28
    local halfW = opts.halfW or 8
    local halfH = opts.halfH or 8
    local minPlayerDist = opts.minPlayerDist or 55
    local minEnemyDist = opts.minEnemyDist or 40
    local playerPos = opts.playerPos
    local avoid = opts.avoid or {}

    local x0 = arena.innerLeft + pad
    local y0 = arena.innerTop + pad
    local x1 = arena.innerRight - pad
    local y1 = arena.innerBottom - pad

    for _ = 1, 48 do
        local x = x0 + love.math.random() * (x1 - x0)
        local y = y0 + love.math.random() * (y1 - y0)
        if not spawnBlockedAt(x, y, halfW, halfH) then
            local ok = true
            if playerPos then
                local dx, dy = x - playerPos.x, y - playerPos.y
                if math.sqrt(dx * dx + dy * dy) < minPlayerDist then
                    ok = false
                end
            end
            if ok then
                for _, p in ipairs(avoid) do
                    local dx, dy = x - p.x, y - p.y
                    if math.sqrt(dx * dx + dy * dy) < minEnemyDist then
                        ok = false
                        break
                    end
                end
            end
            if ok then
                return x, y
            end
        end
    end

    -- Fallback: arena center offset (may still be clearer than a wall).
    return arena.cx + (opts.fallbackOffsetX or 0),
        arena.cy + (opts.fallbackOffsetY or 40)
end

return physics
