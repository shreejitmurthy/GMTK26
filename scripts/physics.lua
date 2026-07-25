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
    physics.arena = nil

    physics.world:addCollisionClass("Player")
    -- Kinematic enemies must not solid-shove the dynamic player (that tunnels through walls
    -- when cornered). Soft resistance + separation handle player↔enemy feel instead.
    -- Kinematic↔kinematic / kinematic↔static also never resolve in Box2D, so wall slide,
    -- trySetEnemyPosition, and clampEnemyToPlayable enforce walls / playable bounds.
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

--- True if the enemy AABB at (cx,cy) overlaps any Wall collider.
function physics.enemyOverlapsWall(enemyCollider, cx, cy)
    if not physics.world or not enemyCollider then
        return false
    end
    cx = cx or enemyCollider:getX()
    cy = cy or enemyCollider:getY()
    local hw = enemyCollider.halfWidth or 0
    local hh = enemyCollider.halfHeight or 0
    local hits = physics.world:queryRectangleArea(cx - hw, cy - hh, hw * 2, hh * 2, { "Wall" })
    return #hits > 0
end

--- Center AABB inset by enemy half-extents so the body stays inside outer walls.
function physics.getEnemyPlayableBounds(enemyCollider)
    local arena = physics.arena
    if not arena then
        return nil
    end
    local hw = (enemyCollider and enemyCollider.halfWidth) or 0
    local hh = (enemyCollider and enemyCollider.halfHeight) or 0
    return {
        minX = arena.innerLeft + hw,
        maxX = arena.innerRight - hw,
        minY = arena.innerTop + hh,
        maxY = arena.innerBottom - hh,
        cx = arena.cx,
        cy = arena.cy,
    }
end

function physics.isEnemyInsidePlayable(enemyCollider, cx, cy)
    cx = cx or enemyCollider:getX()
    cy = cy or enemyCollider:getY()
    local b = physics.getEnemyPlayableBounds(enemyCollider)
    if not b then
        return true
    end
    return cx >= b.minX and cx <= b.maxX and cy >= b.minY and cy <= b.maxY
end

--- Playable interior AND not overlapping a Wall.
function physics.enemyPositionValid(enemyCollider, cx, cy)
    return physics.isEnemyInsidePlayable(enemyCollider, cx, cy)
        and not physics.enemyOverlapsWall(enemyCollider, cx, cy)
end

local function syncEnemyHurtbox(enemyCollider)
    local obj = enemyCollider and enemyCollider.getObject and enemyCollider:getObject()
    if obj and obj.syncHurtbox then
        obj:syncHurtbox()
    end
end

--- Search an open point inside playable bounds, preferring arena center (inward).
--- Never returns a point outside the playable AABB or inside a Wall.
function physics.findEnemyUnstickPosition(enemyCollider, fromX, fromY)
    local b = physics.getEnemyPlayableBounds(enemyCollider)
    if not b then
        return nil
    end

    fromX = fromX or enemyCollider:getX()
    fromY = fromY or enemyCollider:getY()

    local bestX, bestY, bestScore = nil, nil, math.huge
    local toCx, toCy = b.cx - fromX, b.cy - fromY
    local toLen = math.sqrt(toCx * toCx + toCy * toCy)
    if toLen < 0.001 then
        toCx, toCy = 0, -1
    else
        toCx, toCy = toCx / toLen, toCy / toLen
    end

    local function consider(px, py)
        px = math.max(b.minX, math.min(b.maxX, px))
        py = math.max(b.minY, math.min(b.maxY, py))
        if not physics.enemyPositionValid(enemyCollider, px, py) then
            return
        end
        local dx, dy = px - b.cx, py - b.cy
        local distCenter = math.sqrt(dx * dx + dy * dy)
        local ox, oy = px - fromX, py - fromY
        local distMove = math.sqrt(ox * ox + oy * oy)
        local inward = ox * toCx + oy * toCy
        local score = distCenter * 2 + distMove
        if inward > 0 then
            score = score - 20
        end
        if score < bestScore then
            bestScore = score
            bestX, bestY = px, py
        end
    end

    for dist = 2, 56, 2 do
        consider(fromX + toCx * dist, fromY + toCy * dist)
        for i = 0, 15 do
            local a = (i / 16) * math.pi * 2
            consider(fromX + math.cos(a) * dist, fromY + math.sin(a) * dist)
        end
        -- Prefer a nearby inward solution once one exists.
        if bestX and dist >= 12 then
            return bestX, bestY
        end
    end
    if bestX then
        return bestX, bestY
    end

    -- Hard fallback: spiral from arena center (never outward past playable).
    for dist = 0, 96, 4 do
        if dist == 0 then
            consider(b.cx, b.cy)
        else
            for i = 0, 23 do
                local a = (i / 24) * math.pi * 2
                consider(b.cx + math.cos(a) * dist, b.cy + math.sin(a) * dist)
            end
        end
        if bestX then
            return bestX, bestY
        end
    end

    return b.cx, b.cy
end

--- Clamp into playable AABB; if still in a Wall (interior block), unstick inward.
--- Returns true when position changed. Updates pushAnchor to the final valid pos.
function physics.clampEnemyToPlayable(enemyCollider)
    if not enemyCollider or enemyCollider:isDestroyed() then
        return false
    end

    local x, y = enemyCollider:getX(), enemyCollider:getY()
    local b = physics.getEnemyPlayableBounds(enemyCollider)
    local moved = false

    if b then
        local cx = math.max(b.minX, math.min(b.maxX, x))
        local cy = math.max(b.minY, math.min(b.maxY, y))
        if cx ~= x or cy ~= y then
            x, y = cx, cy
            moved = true
        end
    end

    if physics.enemyPositionValid(enemyCollider, x, y) then
        if moved then
            enemyCollider:setPosition(x, y)
            enemyCollider:setLinearVelocity(0, 0)
            enemyCollider.pushAnchorX = x
            enemyCollider.pushAnchorY = y
            syncEnemyHurtbox(enemyCollider)
        elseif not physics.enemyPositionValid(
            enemyCollider,
            enemyCollider.pushAnchorX or x,
            enemyCollider.pushAnchorY or y
        ) then
            enemyCollider.pushAnchorX = enemyCollider:getX()
            enemyCollider.pushAnchorY = enemyCollider:getY()
        end
        return moved
    end

    local rx, ry = physics.findEnemyUnstickPosition(enemyCollider, x, y)
    if not rx then
        return false
    end
    enemyCollider:setPosition(rx, ry)
    enemyCollider:setLinearVelocity(0, 0)
    enemyCollider.pushAnchorX = rx
    enemyCollider.pushAnchorY = ry
    syncEnemyHurtbox(enemyCollider)
    return true
end

--- Set position only when inside playable and clear of Walls. Returns success.
function physics.trySetEnemyPosition(enemyCollider, x, y)
    if not enemyCollider or enemyCollider:isDestroyed() then
        return false
    end
    if not physics.enemyPositionValid(enemyCollider, x, y) then
        return false
    end
    enemyCollider:setPosition(x, y)
    return true
end

function physics.clampAllEnemiesToPlayable()
    for _, enemyCollider in ipairs(physics.enemies) do
        if not enemyCollider:isDestroyed() then
            physics.clampEnemyToPlayable(enemyCollider)
        end
    end
end

--- Nudge an enemy away from contact without giving it velocity. Movement is
--- bounded around its anchor, so sustained pressure cannot shove it far away.
--- Wall / playable constraints always win over maxPushDistance.
function physics.nudgeEnemy(enemyCollider, nx, ny, strength, dt)
    if strength <= 0 or enemyCollider.maxPushDistance <= 0 then
        return
    end

    -- Never nudge from an invalid anchor (would teleport into/through walls).
    if not physics.enemyPositionValid(
        enemyCollider,
        enemyCollider.pushAnchorX,
        enemyCollider.pushAnchorY
    ) then
        physics.clampEnemyToPlayable(enemyCollider)
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

    local function tryOffset(frac)
        local tx = enemyCollider.pushAnchorX + offsetX * frac
        local ty = enemyCollider.pushAnchorY + offsetY * frac
        if physics.trySetEnemyPosition(enemyCollider, tx, ty) then
            enemyCollider:setLinearVelocity(0, 0)
            syncEnemyHurtbox(enemyCollider)
            return true
        end
        return false
    end

    if tryOffset(1) then
        return
    end
    for frac = 0.75, 0.05, -0.125 do
        if tryOffset(frac) then
            return
        end
    end

    -- Cancel nudge; ensure we are not left embedded / OOB.
    physics.clampEnemyToPlayable(enemyCollider)
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

    -- Soft-push must never leave enemies embedded or outside the arena.
    physics.clampAllEnemiesToPlayable()

    return vx, vy
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
        if physics.enemyPositionValid(enemyCollider, probeX, probeY) then
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
        if not physics.enemyPositionValid(enemyCollider, candidateX, candidateY) then
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

local function enemyMotionBlockedAt(enemyCollider, cx, cy)
    return not physics.enemyPositionValid(enemyCollider, cx, cy)
end

--- Zero velocity into walls / OOB (kinematic bodies do not resolve vs static Wall).
--- Embedded recovery searches inward (toward arena center), never ejects outside.
function physics.slideEnemyAgainstWalls(enemyCollider, vx, vy, dt)
    dt = dt or (1 / 60)
    local x, y = enemyCollider:getX(), enemyCollider:getY()

    if enemyMotionBlockedAt(enemyCollider, x, y) then
        physics.clampEnemyToPlayable(enemyCollider)
        return 0, 0
    end

    local nextX, nextY = x + vx * dt, y + vy * dt
    if enemyMotionBlockedAt(enemyCollider, nextX, nextY) then
        if enemyMotionBlockedAt(enemyCollider, nextX, y) then
            vx = 0
        end
        if enemyMotionBlockedAt(enemyCollider, x, nextY) then
            vy = 0
        end
        if enemyMotionBlockedAt(enemyCollider, x + vx * dt, y + vy * dt) then
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

--- Separation + wall/playable slide, then clamp to maxSpeed (no √2 boost from blending).
--- Idle input (near-zero velocity) skips separation so stopped enemies do not drift.
function physics.constrainEnemyMotion(enemyCollider, vx, vy, dt, maxSpeed)
    local inputSpeed = math.sqrt(vx * vx + vy * vy)
    if inputSpeed < 0.01 then
        physics.clampEnemyToPlayable(enemyCollider)
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

--- Static ellipse approximation for Tiled oval objects.
--- Box2D has no ellipse primitive and caps convex polygons at eight vertices.
function physics.addEllipseWall(object)
    local vertices = {}
    local ellipse = object.ellipse

    if ellipse and #ellipse >= 10 then
        -- STI has already applied layer offsets and object rotation. Its first
        -- vertex is the center and its final perimeter point duplicates the
        -- first, so sample eight unique perimeter points.
        local uniquePerimeterVertices = #ellipse - 2
        for index = 0, 7 do
            local vertex = ellipse[
                2 + math.floor(index * uniquePerimeterVertices / 8)
            ]
            vertices[#vertices + 1] = vertex.x
            vertices[#vertices + 1] = vertex.y
        end
    else
        local x, y = object.x, object.y
        local radiusX, radiusY = object.width / 2, object.height / 2
        local centerX, centerY = x + radiusX, y + radiusY
        local rotation = math.rad(object.rotation or 0)
        local cosRotation, sinRotation = math.cos(rotation), math.sin(rotation)

        for index = 0, 7 do
            local angle = index / 8 * math.pi * 2
            local px = centerX + math.cos(angle) * radiusX
            local py = centerY + math.sin(angle) * radiusY
            local dx, dy = px - x, py - y
            vertices[#vertices + 1] = x + cosRotation * dx - sinRotation * dy
            vertices[#vertices + 1] = y + sinRotation * dx + cosRotation * dy
        end
    end

    local wall = physics.world:newPolygonCollider(vertices)
    wall:setType("static")
    wall:setCollisionClass("Wall")
    wall:setObject(object)
    wall.mapObject = object
    physics.walls[#physics.walls + 1] = wall
    return wall
end

--- Build walls from STI object tables (rectangles + ellipses).
--- Skips zero-area / non-collider shapes (points, polylines used as markers).
function physics.addWallsFromObjects(objects)
    if not objects then
        return 0
    end
    local added = 0
    for _, object in ipairs(objects) do
        local shape = object.shape
        if shape == "point" or shape == "polyline" or shape == "polygon" then
            -- Markers / future geometry — not static Wall fixtures here.
        elseif (not shape or shape == "rectangle")
            and (object.width or 0) > 0
            and (object.height or 0) > 0
        then
            physics.addWall(object.x, object.y, object.width, object.height)
            added = added + 1
        elseif shape == "ellipse"
            and (object.width or 0) > 0
            and (object.height or 0) > 0
        then
            physics.addEllipseWall(object)
            added = added + 1
        end
    end
    return added
end

function physics.getWallCount()
    return #physics.walls
end

--- Logical map bounds used by kinematic-enemy clamp helpers.
--- Pass the INTERIOR walkable AABB (inside outer walls), not raw 0..mapSize.
--- Optional thickness is the outer wall depth in px (used by embed recovery tests).
function physics.setPlayableArea(x, y, w, h, thickness)
    physics.arena = {
        cx = x + w / 2,
        cy = y + h / 2,
        left = x,
        top = y,
        width = w,
        height = h,
        -- Outer wall depth; recovery self-test embeds just outside the interior.
        thickness = thickness or 16,
        innerLeft = x,
        innerTop = y,
        innerRight = x + w,
        innerBottom = y + h,
    }
    return physics.arena
end

--- Solid rim just outside the playable interior so the dynamic Player cannot leave
--- the map. Interior props/fountain stay separate; these walls are invisible
--- (no drawW) because courtyard tiles already cover the playable AABB.
function physics.addBoundaryWalls(x, y, w, h, thickness)
    thickness = thickness or 16
    local function edge(wx, wy, ww, wh)
        local wall = physics.world:newRectangleCollider(wx, wy, ww, wh)
        wall:setType("static")
        wall:setCollisionClass("Wall")
        wall.isBoundary = true
        physics.walls[#physics.walls + 1] = wall
        return wall
    end
    -- Outside the interior so every map tile stays walkable.
    edge(x - thickness, y - thickness, w + thickness * 2, thickness) -- top
    edge(x - thickness, y + h, w + thickness * 2, thickness) -- bottom
    edge(x - thickness, y, thickness, h) -- left
    edge(x + w, y, thickness, h) -- right
    return 4
end

--- Hard clamp a dynamic body into the playable AABB (safety net vs tunneling).
function physics.clampColliderToPlayable(collider)
    local arena = physics.arena
    if not arena or not collider then
        return
    end
    local hw = collider.halfWidth or 4
    local hh = collider.halfHeight or 4
    local cx, cy = collider:getX(), collider:getY()
    local nx = math.max(arena.innerLeft + hw, math.min(arena.innerRight - hw, cx))
    local ny = math.max(arena.innerTop + hh, math.min(arena.innerBottom - hh, cy))
    if nx ~= cx or ny ~= cy then
        collider:setPosition(nx, ny)
        local vx, vy = collider:getLinearVelocity()
        if nx ~= cx then
            vx = 0
        end
        if ny ~= cy then
            vy = 0
        end
        collider:setLinearVelocity(vx, vy)
    end
end

--- Draw stub arena walls so solid blockers are visible without F1.
function physics.drawWalls()
    love.graphics.setColor(0.32, 0.32, 0.35, 1)
    for _, wall in ipairs(physics.walls) do
        if wall.drawW and not wall.isBoundary then
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

    -- Playable interior = inside the four outer wall faces. Enemy clamps inset
    -- each collider by halfWidth/halfHeight so bodies never overlap outer walls.
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
