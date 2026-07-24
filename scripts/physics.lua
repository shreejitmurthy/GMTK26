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
    physics.world:addCollisionClass("Enemy")
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
function physics.applyEnemyResistance(playerCollider, vx, vy, dt)
    local px, py = playerCollider:getX(), playerCollider:getY()
    local playerHalfW = playerCollider.halfWidth or 0
    local playerHalfH = playerCollider.halfHeight or 0

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
                end
            end
        end
    end

    return vx, vy
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

    return physics.getWallCount()
end

return physics
