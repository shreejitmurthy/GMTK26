-- Thin type configs + AI update for chaser / fleer / keeper / ranger.
-- Shared locomotion stays on enemy (moveToward / moveAway / stop).

local physics = require "scripts.physics"
local enemy_types = {}

enemy_types.defaults = {
    chaser = {
        speed = 75,
        aggroRange = 140,
        stopDistance = 28,
        stopDeadzone = 6,
        separationDistance = 28,
        separationSpeed = 24,
        color = { 0.85, 0.35, 0.2 },
        letter = "C",
    },
    fleer = {
        speed = 95,
        fleeRange = 90,
        fleeDeadzone = 10,
        color = { 0.35, 0.7, 0.4 },
        letter = "F",
    },
    keeper = {
        speed = 70,
        aggroRange = 160,
        preferredDistance = 70,
        band = 18,
        color = { 0.25, 0.45, 0.75 },
        letter = "K",
    },
    ranger = {
        speed = 65,
        aggroRange = 190,
        safeDistance = 95,
        safeDeadzone = 12,
        losDistanceBuffer = 10,
        losGoalTolerance = 7,
        losProbeDistance = 32,
        losRetreatWeight = 0.65,
        color = { 0.72, 0.35, 0.85 },
        letter = "R",
    },
}

local AI_FIELDS = {
    chaser = {
        "speed",
        "aggroRange",
        "stopDistance",
        "stopDeadzone",
        "separationDistance",
        "separationSpeed",
    },
    fleer = { "speed", "fleeRange", "fleeDeadzone" },
    keeper = { "speed", "aggroRange", "preferredDistance", "band" },
    ranger = {
        "speed",
        "aggroRange",
        "safeDistance",
        "safeDeadzone",
        "losDistanceBuffer",
        "losGoalTolerance",
        "losProbeDistance",
        "losRetreatWeight",
    },
}

function enemy_types.normalizeType(typeId)
    if typeId == "chaser"
        or typeId == "fleer"
        or typeId == "keeper"
        or typeId == "ranger"
    then
        return typeId
    end
    return "chaser"
end

--- Copy type defaults onto instance, then apply option overrides.
function enemy_types.apply(e, options)
    options = options or {}
    local typeId = enemy_types.normalizeType(options.type or options.enemyType)
    local defaults = enemy_types.defaults[typeId]

    e.enemyType = typeId
    e.color = {
        defaults.color[1],
        defaults.color[2],
        defaults.color[3],
    }
    e.debugLetter = defaults.letter

    for _, field in ipairs(AI_FIELDS[typeId]) do
        e[field] = options[field] or defaults[field]
    end

    e._holding = false
    e._fleeing = false
    e._backingAway = false
    e._losStrafeSide = nil
    e._losGoalX = nil
    e._losGoalY = nil
    e._repositioningForLOS = false
    e.hasPlayerLOS = nil
end

local function distToPlayer(e, player)
    if not player or not player.collider then
        return nil, nil, nil
    end
    local px, py = player.collider:getX(), player.collider:getY()
    local dx, dy = e:vecToward(px, py)
    return px, py, math.sqrt(dx * dx + dy * dy)
end

local function updateChaser(e, dt, player)
    local px, py, dist = distToPlayer(e, player)
    if not dist then
        e._holding = false
        e:stop(dt)
        return
    end
    if dist > e.aggroRange then
        e._holding = false
        e:stop(dt)
        return
    end
    if dist <= e.stopDistance then
        e._holding = true
        e:holdApartFrom(px, py, dt)
        return
    end
    -- Hysteresis: stay stopped until clear of deadzone (kills vibrate at stopDistance).
    if e._holding and dist < e.stopDistance + e.stopDeadzone then
        e:holdApartFrom(px, py, dt)
        return
    end
    e._holding = false
    e:moveToward(px, py, e.speed, dt)
end

local function updateFleer(e, dt, player)
    local px, py, dist = distToPlayer(e, player)
    if not dist then
        e._fleeing = false
        e:stop(dt)
        return
    end
    if e._fleeing then
        if dist > e.fleeRange + e.fleeDeadzone then
            e._fleeing = false
            e:stop(dt)
        else
            e:moveAway(px, py, e.speed, dt)
        end
        return
    end
    if dist <= e.fleeRange then
        e._fleeing = true
        e:moveAway(px, py, e.speed, dt)
    else
        e:stop(dt)
    end
end

local function updateKeeper(e, dt, player)
    local px, py, dist = distToPlayer(e, player)
    if not dist then
        e:stop(dt)
        return
    end
    if dist > e.aggroRange then
        e:stop(dt)
        return
    end
    -- Wide band = equilibrium without in/out chatter.
    if dist > e.preferredDistance + e.band then
        e:moveToward(px, py, e.speed, dt)
    elseif dist < e.preferredDistance - e.band then
        e:moveAway(px, py, e.speed, dt)
    else
        e:stop(dt)
    end
end

local function updateRanger(e, dt, player)
    local px, py, dist = distToPlayer(e, player)
    if not dist or dist > e.aggroRange then
        e._backingAway = false
        e._losGoalX, e._losGoalY = nil, nil
        e._repositioningForLOS = false
        e.hasPlayerLOS = nil
        e:stop(dt)
        return
    end

    if e._backingAway then
        if dist >= e.safeDistance + e.safeDeadzone then
            e._backingAway = false
        end
    elseif dist < e.safeDistance then
        e._backingAway = true
    end

    e.hasPlayerLOS = e:hasLineOfSight(px, py)
    if not e.hasPlayerLOS then
        e._repositioningForLOS = true
    end

    if e._repositioningForLOS then
        local goalValid = false
        if e._losGoalX and e._losGoalY then
            local goalDX = e._losGoalX - px
            local goalDY = e._losGoalY - py
            local goalDistance = math.sqrt(goalDX * goalDX + goalDY * goalDY)
            goalValid = goalDistance >= e.safeDistance
                and physics.hasLineOfSight(e._losGoalX, e._losGoalY, px, py)
        end

        if not goalValid then
            e._losGoalX, e._losGoalY, e._losStrafeSide =
                physics.findLineOfSightPosition(
                    e.collider,
                    px,
                    py,
                    e.safeDistance + e.losDistanceBuffer,
                    e._losStrafeSide
                )
        end

        if e._losGoalX and e._losGoalY then
            local goalDX = e._losGoalX - e.collider:getX()
            local goalDY = e._losGoalY - e.collider:getY()
            local distanceToGoal = math.sqrt(goalDX * goalDX + goalDY * goalDY)
            if e.hasPlayerLOS
                and dist >= e.safeDistance
                and distanceToGoal <= e.losGoalTolerance
            then
                e._repositioningForLOS = false
                e._losGoalX, e._losGoalY = nil, nil
                e._backingAway = false
                e:stop(dt)
                return
            end

            e:moveWithoutApproaching(
                px,
                py,
                goalDX,
                goalDY,
                e.speed,
                dt
            )
            return
        end

        -- Fallback if no point on the safe ring is viable: keep circling an
        -- open side, still without allowing any movement toward the player.
        local strafeX, strafeY, side = physics.lineOfSightStrafeDirection(
            e.collider,
            px,
            py,
            e._losStrafeSide,
            e.losProbeDistance
        )
        e._losStrafeSide = side

        -- When unsafe and occluded, blend retreat with the sidestep so restoring
        -- sight never requires the ranger to close distance.
        if e._backingAway then
            local awayX, awayY = e:vecAway(px, py)
            local awayLength = math.sqrt(awayX * awayX + awayY * awayY)
            if awayLength > 0 then
                local weight = e.losRetreatWeight
                strafeX = strafeX + (awayX / awayLength) * weight
                strafeY = strafeY + (awayY / awayLength) * weight
            end
        end
        e:moveWithoutApproaching(px, py, strafeX, strafeY, e.speed, dt)
        return
    end

    if e._backingAway then
        local awayX, awayY = e:vecAway(px, py)
        e:moveWithoutApproaching(px, py, awayX, awayY, e.speed, dt)
    else
        -- Rangers never close distance; at a safe range with LOS, they hold.
        e:stop(dt)
    end
end

local UPDATERS = {
    chaser = updateChaser,
    fleer = updateFleer,
    keeper = updateKeeper,
    ranger = updateRanger,
}

function enemy_types.update(e, dt, player)
    local fn = UPDATERS[e.enemyType] or updateChaser
    fn(e, dt, player)
end

return enemy_types
