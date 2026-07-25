-- Thin type configs + AI update for chaser / fleer / keeper.
-- Shared locomotion stays on enemy (moveToward / moveAway / stop).

local enemy_types = {}

enemy_types.defaults = {
    chaser = {
        speed = 75,
        aggroRange = 140,
        stopDistance = 28,
        stopDeadzone = 6,
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
}

local AI_FIELDS = {
    chaser = { "speed", "aggroRange", "stopDistance", "stopDeadzone" },
    fleer = { "speed", "fleeRange", "fleeDeadzone" },
    keeper = { "speed", "aggroRange", "preferredDistance", "band" },
}

function enemy_types.normalizeType(typeId)
    if typeId == "chaser" or typeId == "fleer" or typeId == "keeper" then
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
        e:stop(dt)
        return
    end
    -- Hysteresis: stay stopped until clear of deadzone (kills vibrate at stopDistance).
    if e._holding and dist < e.stopDistance + e.stopDeadzone then
        e:stop(dt)
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

local UPDATERS = {
    chaser = updateChaser,
    fleer = updateFleer,
    keeper = updateKeeper,
}

function enemy_types.update(e, dt, player)
    local fn = UPDATERS[e.enemyType] or updateChaser
    fn(e, dt, player)
end

return enemy_types
