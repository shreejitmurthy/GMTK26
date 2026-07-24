-- Windfield physics world helpers (top-down, zero gravity).
-- STI can later feed walls through addWall / addWallsFromObjects.

local wf = require "lib.windfield"

local physics = {
    world = nil,
    walls = {},
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

    physics.world:addCollisionClass("Player")
    physics.world:addCollisionClass("Enemy")
    physics.world:addCollisionClass("Wall")
    -- Sensors: detect overlaps but ignore solid resolve with most solids via setSensor.
    -- Still register classes so enter/exit queries work consistently.
    physics.world:addCollisionClass("PlayerAttack", {
        ignores = { "Player", "Wall", "PlayerAttack" },
    })
    physics.world:addCollisionClass("EnemyHit", {
        ignores = { "Enemy", "Wall", "EnemyHit" },
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
    return collider
end

--- Enemy body. x/y are top-left of the hitbox (Windfield BSG convention).
--- Static so idle enemies block like walls (not shoved by the player).
function physics.newEnemyCollider(x, y, w, h, corner)
    local collider = physics.world:newBSGRectangleCollider(x, y, w, h, corner or 2)
    collider:setFixedRotation(true)
    collider:setCollisionClass("Enemy")
    collider:setType("static")
    return collider
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
