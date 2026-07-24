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
