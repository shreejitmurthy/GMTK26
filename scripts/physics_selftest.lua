-- Console PASS/FAIL checks for the physics milestone (no LOVE key simulation needed).

local physics = require "scripts.physics"
require "scripts.player"

local selftest = {}

local function nearlyEqual(a, b, eps)
    return math.abs(a - b) <= (eps or 0.01)
end

local function check(name, ok, detail)
    local mark = ok and "PASS" or "FAIL"
    if detail then
        print(string.format("[physics_selftest] %s: %s (%s)", mark, name, detail))
    else
        print(string.format("[physics_selftest] %s: %s", mark, name))
    end
    return ok
end

function selftest.run(playerActor, enemyActors)
    print("[physics_selftest] running...")
    local allOk = true

    local gx, gy = physics.getGravity()
    allOk = check("gravity is (0,0)", nearlyEqual(gx, 0) and nearlyEqual(gy, 0),
        string.format("got (%.4f, %.4f)", gx or -1, gy or -1)) and allOk

    local classes = physics.getClassNames()
    local expected = { Player = true, Enemy = true, Wall = true, PlayerAttack = true, EnemyHit = true }
    local classOk = #classes == 5
    for _, name in ipairs(classes) do
        if not expected[name] then
            classOk = false
        end
    end
    allOk = check("collision classes registered", classOk, table.concat(classes, ", ")) and allOk

    local wallCount = physics.getWallCount()
    allOk = check("test walls spawned (3-6+)", wallCount >= 3 and wallCount <= 12,
        tostring(wallCount)) and allOk

    if playerActor and playerActor.collider then
        local cx, cy = playerActor.collider:getX(), playerActor.collider:getY()
        allOk = check("player collider exists", true, string.format("pos %.1f, %.1f", cx, cy)) and allOk
        allOk = check("player pos matches collider",
            nearlyEqual(playerActor.pos.x, cx, 0.1) and nearlyEqual(playerActor.pos.y, cy, 0.1)) and allOk
        allOk = check("player collision class",
            playerActor.collider.collision_class == "Player",
            tostring(playerActor.collider.collision_class)) and allOk
    else
        allOk = check("player collider exists", false, "missing playerActor.collider") and allOk
    end

    enemyActors = enemyActors or {}
    local sample = enemyActors[1]
    if sample and sample.collider then
        local cx, cy = sample.collider:getX(), sample.collider:getY()
        allOk = check("enemy collider exists", true,
            string.format("n=%d pos %.1f, %.1f", #enemyActors, cx, cy)) and allOk
        allOk = check("enemy pos matches collider",
            nearlyEqual(sample.pos.x, cx, 0.1) and nearlyEqual(sample.pos.y, cy, 0.1)) and allOk
        allOk = check("enemy collision class",
            sample.collider.collision_class == "Enemy",
            tostring(sample.collider.collision_class)) and allOk
        allOk = check("enemy body cannot accumulate shove momentum",
            sample.collider.body:getType() == "kinematic",
            tostring(sample.collider.body:getType())) and allOk
        allOk = check("enemy locomotion helpers exist",
            type(physics.constrainEnemyMotion) == "function"
                and type(physics.slideEnemyAgainstWalls) == "function"
                and type(physics.applyEnemySeparation) == "function") and allOk
        allOk = check("enemy has non-bouncy soft resistance",
            nearlyEqual(sample.collider:getRestitution(), 0)
                and sample.collider.softPadding > 0
                and sample.collider.resistanceExponent > 0
                and sample.collider.maxPushDistance > 0
                and sample.collider.maxPushDistance <= 3
                and sample.collider.pushSpeed > 0,
            string.format(
                "bounce=%.2f padding=%.1f exponent=%.1f maxPush=%.1f",
                sample.collider:getRestitution(),
                sample.collider.softPadding,
                sample.collider.resistanceExponent,
                sample.collider.maxPushDistance
            )) and allOk

        local farVX = physics.resistInwardVelocity(-100, 0, 1, 0, 0.25)
        local closeVX = physics.resistInwardVelocity(-100, 0, 1, 0, 1)
        allOk = check("pushback strengthens closer to enemy",
            nearlyEqual(farVX, -75) and nearlyEqual(closeVX, 0),
            string.format("far=%.1f boundary=%.1f", farVX, closeVX)) and allOk
    else
        allOk = check("enemy collider exists", false, "missing enemyActors[1].collider") and allOk
    end

    if sample and sample.hurtbox then
        local hx, hy = sample.hurtbox:getX(), sample.hurtbox:getY()
        local cx, cy = sample.collider:getX(), sample.collider:getY()
        allOk = check("enemy EnemyHit hurtbox exists",
            sample.hurtbox.collision_class == "EnemyHit",
            tostring(sample.hurtbox.collision_class)) and allOk
        allOk = check("enemy hurtbox is sensor", sample.hurtbox:isSensor() == true) and allOk
        allOk = check("enemy hurtbox pos matches collider",
            nearlyEqual(hx, cx, 0.1) and nearlyEqual(hy, cy, 0.1),
            string.format("hurtbox %.1f,%.1f body %.1f,%.1f", hx, hy, cx, cy)) and allOk
        allOk = check("enemy hurtbox object is enemy",
            sample.hurtbox:getObject() == sample) and allOk
    else
        allOk = check("enemy EnemyHit hurtbox exists", false, "missing enemyActors[1].hurtbox") and allOk
    end

    if sample and sample.collider then
        allOk = check("enemy has speed",
            type(sample.speed) == "number" and sample.speed > 0,
            tostring(sample.speed)) and allOk
        allOk = check("enemy locomotion API exists",
            type(sample.moveToward) == "function"
                and type(sample.moveAway) == "function"
                and type(sample.stop) == "function"
                and type(sample.refreshPushAnchor) == "function") and allOk

        local cx, cy = sample.collider:getX(), sample.collider:getY()
        sample.collider:setPosition(cx + 8, cy - 4)
        sample:refreshPushAnchor()
        local ax, ay = sample.collider.pushAnchorX, sample.collider.pushAnchorY
        local nx, ny = sample.collider:getX(), sample.collider:getY()
        allOk = check("pushAnchor matches collider after refresh",
            nearlyEqual(ax, nx, 0.01) and nearlyEqual(ay, ny, 0.01),
            string.format("anchor %.1f,%.1f collider %.1f,%.1f", ax, ay, nx, ny)) and allOk

        sample:moveToward(nx + 50, ny + 50, sample.speed)
        ax, ay = sample.collider.pushAnchorX, sample.collider.pushAnchorY
        nx, ny = sample.collider:getX(), sample.collider:getY()
        allOk = check("pushAnchor matches collider after moveToward",
            nearlyEqual(ax, nx, 0.01) and nearlyEqual(ay, ny, 0.01),
            string.format("anchor %.1f,%.1f collider %.1f,%.1f", ax, ay, nx, ny)) and allOk

        -- Restore spawn pose so gameplay does not inherit selftest motion.
        sample.collider:setPosition(cx, cy)
        sample:stop()
        sample:syncFromCollider()
    end

    -- Typed enemies: chaser / fleer / keeper present with default tunables.
    local byType = {}
    for _, e in ipairs(enemyActors) do
        if e.enemyType then
            byType[e.enemyType] = e
        end
    end
    allOk = check("spawned enemy types include chaser, fleer, keeper",
        byType.chaser and byType.fleer and byType.keeper,
        string.format("chaser=%s fleer=%s keeper=%s",
            tostring(byType.chaser ~= nil),
            tostring(byType.fleer ~= nil),
            tostring(byType.keeper ~= nil))) and allOk

    if byType.chaser then
        local c = byType.chaser
        allOk = check("chaser default fields",
            nearlyEqual(c.speed, 75) and nearlyEqual(c.aggroRange, 140)
                and nearlyEqual(c.stopDistance, 22),
            string.format("speed=%.0f aggro=%.0f stop=%.0f",
                c.speed or -1, c.aggroRange or -1, c.stopDistance or -1)) and allOk
    end
    if byType.fleer then
        local f = byType.fleer
        allOk = check("fleer default fields",
            nearlyEqual(f.speed, 95) and nearlyEqual(f.fleeRange, 90),
            string.format("speed=%.0f flee=%.0f", f.speed or -1, f.fleeRange or -1)) and allOk
    end
    if byType.keeper then
        local k = byType.keeper
        allOk = check("keeper default fields",
            nearlyEqual(k.speed, 70) and nearlyEqual(k.aggroRange, 160)
                and nearlyEqual(k.preferredDistance, 70) and nearlyEqual(k.band, 12),
            string.format("speed=%.0f aggro=%.0f pref=%.0f band=%.0f",
                k.speed or -1, k.aggroRange or -1,
                k.preferredDistance or -1, k.band or -1)) and allOk
    end

    -- Diagonal vs cardinal: normalize BEFORE speed (FAIL if √2 speedup).
    local speed = (playerActor and playerActor.speed) or 120
    local cvx, cvy = player.normalizedVelocity(1, 0, speed)
    local dvx, dvy = player.normalizedVelocity(1, -1, speed)
    local cardinal = math.sqrt(cvx * cvx + cvy * cvy)
    local diagonal = math.sqrt(dvx * dvx + dvy * dvy)
    local ratio = diagonal / cardinal
    allOk = check("diagonal speed == cardinal speed",
        nearlyEqual(cardinal, diagonal, speed * 0.01),
        string.format("cardinal=%.3f diagonal=%.3f ratio=%.4f", cardinal, diagonal, ratio)) and allOk

    -- Unnormalized would be ~1.414; ensure we did not leave that bug in.
    allOk = check("no unnormalized √2 speedup",
        ratio < 1.05,
        string.format("ratio=%.4f", ratio)) and allOk

    print(allOk and "[physics_selftest] ALL PASS" or "[physics_selftest] SOME FAILED")
    return allOk
end

return selftest
