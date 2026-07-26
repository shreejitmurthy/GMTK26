-- Console PASS/FAIL checks for the physics milestone (no LOVE key simulation needed).

local physics = require "scripts.physics"
local countdown = require "scripts.countdown"
local collapse = require "scripts.collapse"
local game_map = require "scripts.game_map"
require "scripts.enemy" -- global `enemy` module (no return value)
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
    allOk = check("map colliders spawned (1+)", wallCount >= 1,
        tostring(wallCount)) and allOk

    local ovalWall = nil
    for _, wall in ipairs(physics.walls) do
        if wall.mapObject and wall.mapObject.shape == "ellipse" then
            ovalWall = wall
            break
        end
    end
    allOk = check("map ellipse uses polygon Wall collider",
        ovalWall
            and ovalWall.type == "Polygon"
            and ovalWall.collision_class == "Wall"
            and ovalWall.body:getType() == "static") and allOk

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
                and type(physics.applyEnemySeparation) == "function"
                and type(physics.hasLineOfSight) == "function"
                and type(physics.lineOfSightStrafeDirection) == "function"
                and type(physics.findLineOfSightPosition) == "function") and allOk
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
        local expectedHY = cy + (sample.hurtOffsetY or 0)
        allOk = check("enemy EnemyHit hurtbox exists",
            sample.hurtbox.collision_class == "EnemyHit",
            tostring(sample.hurtbox.collision_class)) and allOk
        allOk = check("enemy hurtbox is sensor", sample.hurtbox:isSensor() == true) and allOk
        allOk = check("enemy hurtbox follows torso offset",
            nearlyEqual(hx, cx, 0.1) and nearlyEqual(hy, expectedHY, 0.1),
            string.format(
                "hurtbox %.1f,%.1f body %.1f,%.1f offsetY=%s",
                hx, hy, cx, cy, tostring(sample.hurtOffsetY)
            )) and allOk
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
                and type(sample.moveInDirection) == "function"
                and type(sample.moveWithoutApproaching) == "function"
                and type(sample.hasLineOfSight) == "function"
                and type(sample.faceToward) == "function"
                and type(sample.stop) == "function"
                and type(sample.holdApartFrom) == "function"
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

        -- Soft-push must not shove kinematic enemies into walls / OOB.
        local arena = physics.arena
        allOk = check("playable clamp helpers exist",
            type(physics.trySetEnemyPosition) == "function"
                and type(physics.clampEnemyToPlayable) == "function"
                and type(physics.enemyOverlapsWall) == "function"
                and type(physics.isEnemyInsidePlayable) == "function"
                and arena ~= nil) and allOk

        if arena then
            local hw = sample.collider.halfWidth or 7
            local hh = sample.collider.halfHeight or 7
            local nearWallX = arena.innerRight - hw - 1
            local nearWallY = arena.cy
            sample.collider:setPosition(nearWallX, nearWallY)
            sample:refreshPushAnchor()
            -- Player to the left → nudge pushes enemy right into the wall.
            physics.nudgeEnemy(sample.collider, -1, 0, 1, 1)
            physics.clampEnemyToPlayable(sample.collider)
            local nx2, ny2 = sample.collider:getX(), sample.collider:getY()
            allOk = check("nudge toward wall stays playable / clear of Wall",
                physics.enemyPositionValid(sample.collider, nx2, ny2)
                    and nx2 <= arena.innerRight - hw + 0.01
                    and nx2 >= arena.innerLeft + hw - 0.01,
                string.format("pos %.1f,%.1f wall=%s playable=%s",
                    nx2, ny2,
                    tostring(physics.enemyOverlapsWall(sample.collider, nx2, ny2)),
                    tostring(physics.isEnemyInsidePlayable(sample.collider, nx2, ny2)))) and allOk

            -- Deliberately embed in the right outer wall; recovery must go inward.
            local embedX = arena.innerRight + arena.thickness * 0.5
            local embedY = arena.cy
            sample.collider:setPosition(embedX, embedY)
            sample.collider.pushAnchorX, sample.collider.pushAnchorY = embedX, embedY
            physics.clampEnemyToPlayable(sample.collider)
            local rx, ry = sample.collider:getX(), sample.collider:getY()
            allOk = check("clamp recovers embedded enemy into playable (not OOB)",
                physics.enemyPositionValid(sample.collider, rx, ry)
                    and rx <= arena.innerRight - hw + 0.01
                    and rx >= arena.innerLeft + hw - 0.01
                    and ry <= arena.innerBottom - hh + 0.01
                    and ry >= arena.innerTop + hh - 0.01
                    and rx < arena.innerRight,
                string.format("from %.1f,%.1f → %.1f,%.1f", embedX, embedY, rx, ry)) and allOk

            sample.collider:setPosition(cx, cy)
            sample:refreshPushAnchor()
            sample:stop()
            sample:syncFromCollider()
        end
    end

    -- Typed enemies: chaser / fleer / keeper / ranger present with defaults.
    local byType = {}
    for _, e in ipairs(enemyActors) do
        if e.enemyType then
            byType[e.enemyType] = e
        end
    end
    allOk = check("spawned enemy types include chaser, fleer, keeper, ranger",
        byType.chaser and byType.fleer and byType.keeper and byType.ranger,
        string.format("chaser=%s fleer=%s keeper=%s ranger=%s",
            tostring(byType.chaser ~= nil),
            tostring(byType.fleer ~= nil),
            tostring(byType.keeper ~= nil),
            tostring(byType.ranger ~= nil))) and allOk

    if byType.chaser then
        local c = byType.chaser
        allOk = check("chaser default fields",
            nearlyEqual(c.speed, 58) and nearlyEqual(c.aggroRange, 140)
                and nearlyEqual(c.stopDistance, 32)
                and nearlyEqual(c.stopDeadzone, 6)
                and nearlyEqual(c.separationDistance, 28)
                and nearlyEqual(c.separationSpeed, 24)
                and c.attackStyle == "lunge"
                and nearlyEqual(c.attackDamageSeconds, 4),
            string.format("speed=%.0f aggro=%.0f stop=%.0f style=%s dmg=%s",
                c.speed or -1, c.aggroRange or -1,
                c.stopDistance or -1, tostring(c.attackStyle),
                tostring(c.attackDamageSeconds))) and allOk
    end
    if byType.fleer then
        local f = byType.fleer
        allOk = check("fleer default fields",
            nearlyEqual(f.speed, 85) and nearlyEqual(f.fleeRange, 90)
                and nearlyEqual(f.fleeDeadzone, 10)
                and f.attackStyle == "pounce"
                and nearlyEqual(f.attackDamageSeconds, 3),
            string.format("speed=%.0f flee=%.0f style=%s",
                f.speed or -1, f.fleeRange or -1, tostring(f.attackStyle))) and allOk
    end
    if byType.keeper then
        local k = byType.keeper
        allOk = check("keeper default fields",
            nearlyEqual(k.speed, 48) and nearlyEqual(k.aggroRange, 160)
                and nearlyEqual(k.preferredDistance, 44) and nearlyEqual(k.band, 10)
                and k.attackStyle == "slam"
                and nearlyEqual(k.attackDamageSeconds, 8)
                and nearlyEqual(k.attackRange, 58)
                and k.preferredDistance + k.band <= k.attackRange + 0.01,
            string.format("speed=%.0f pref=%.0f±%.0f range=%.0f style=%s",
                k.speed or -1, k.preferredDistance or -1, k.band or -1,
                k.attackRange or -1, tostring(k.attackStyle))) and allOk
    end
    if byType.ranger then
        local r = byType.ranger
        allOk = check("ranger default fields",
            nearlyEqual(r.speed, 65) and nearlyEqual(r.aggroRange, 190)
                and nearlyEqual(r.safeDistance, 100)
                and nearlyEqual(r.safeDeadzone, 8)
                and r.attackStyle == "shot"
                and nearlyEqual(r.attackDamageSeconds, 5)
                and nearlyEqual(r.attackTelegraph, 0.5)
                and nearlyEqual(r.minShotDistance, 90)
                and nearlyEqual(r.maxShotDistance, 110)
                and r.debugLetter == "R",
            string.format("speed=%.0f safe=%.0f style=%s dmg=%s band=%s-%s",
                r.speed or -1, r.safeDistance or -1,
                tostring(r.attackStyle), tostring(r.attackDamageSeconds),
                tostring(r.minShotDistance), tostring(r.maxShotDistance))) and allOk

        local clearLOS = physics.hasLineOfSight(190, 140, 290, 140)
        local blockedLOS = physics.hasLineOfSight(190, 200, 290, 200)
        allOk = check("wall-aware line of sight",
            clearLOS and not blockedLOS,
            string.format("clear=%s blocked=%s",
                tostring(clearLOS), tostring(blockedLOS))) and allOk

        local enemy_attacks = require "scripts.enemy_attacks"
        local rx, ry = r.collider:getX(), r.collider:getY()
        local px, py = playerActor.collider:getX(), playerActor.collider:getY()
        local startingHitCount = playerActor.enemyHitCount
        local liveCountdown = rawget(_G, "state") and state.countdown
        local savedRemaining = liveCountdown and liveCountdown:getRemaining()
        local savedExtracted = rawget(_G, "state") and state.extracted
        local savedPaused = liveCountdown and liveCountdown.paused
        enemy_attacks.cancel(r)
        enemy_attacks.clearAllProjectiles()
        r.collider:setPosition(px + 100, py)
        r:refreshPushAnchor()
        r.attackCooldownTimer = 0
        playerActor.hurtIFrame = 0
        if liveCountdown then
            liveCountdown.paused = false
        end
        r:update(1 / 60, playerActor)
        allOk = check("ranger shot telegraphs before damage",
            r.attackState == "telegraph"
                and r.attackFlash > 0
                and playerActor.enemyHitCount == startingHitCount
                and enemy_attacks.projectileCount() == 0,
            string.format("state=%s flash=%.2f hits=%d shots=%d",
                tostring(r.attackState), r.attackFlash or -1,
                playerActor.enemyHitCount - startingHitCount,
                enemy_attacks.projectileCount())) and allOk

        for _ = 1, 90 do
            r:update(1 / 60, playerActor)
            enemy_attacks.updateProjectiles(1 / 60, playerActor)
        end
        local drainedOk = true
        if liveCountdown and savedRemaining then
            drainedOk = liveCountdown:getRemaining()
                <= savedRemaining - (r.attackDamageSeconds or 5) + 0.01
        end
        allOk = check("ranger fires projectile and can drain after telegraph",
            playerActor.enemyHitCount >= startingHitCount + 1 and drainedOk,
            string.format(
                "hits=%d shots=%d drained=%s",
                playerActor.enemyHitCount - startingHitCount,
                enemy_attacks.projectileCount(),
                tostring(drainedOk)
            )) and allOk

        enemy_attacks.cancel(r)
        enemy_attacks.clearAllProjectiles()
        r.collider:setPosition(rx, ry)
        r:refreshPushAnchor()
        playerActor.enemyHitCount = startingHitCount
        playerActor.enemyHitFlash = 0
        playerActor.hurtIFrame = 0
        if liveCountdown and savedRemaining then
            liveCountdown.remaining = savedRemaining
            liveCountdown.damagePulse = 0
            liveCountdown.damagePulseTime = 0
            liveCountdown.paused = savedPaused
        end
        if rawget(_G, "state") and savedExtracted ~= nil then
            state.extracted = savedExtracted
        end
        r:stop()
        r:syncFromCollider()

        local blockedRangerX, blockedRangerY = 240, 144
        r.collider:setPosition(blockedRangerX, blockedRangerY)
        r:refreshPushAnchor()
        r._backingAway = false
        r._losGoalX, r._losGoalY = nil, nil
        r._repositioningForLOS = false
        enemy_attacks.cancel(r)
        r:update(1 / 60, playerActor)
        local vx, vy = r.collider:getLinearVelocity()
        local towardX, towardY =
            px - blockedRangerX,
            py - blockedRangerY
        local closingSpeed = vx * towardX + vy * towardY
        local moving = math.sqrt(vx * vx + vy * vy)
        allOk = check("ranger retreats while restoring LOS",
            r.hasPlayerLOS == false and moving > 0.01 and closingSpeed <= 0.01,
            string.format("los=%s vel=%.1f,%.1f closingDot=%.1f",
                tostring(r.hasPlayerLOS), vx, vy, closingSpeed)) and allOk

        r.collider:setPosition(blockedRangerX, blockedRangerY)
        r:refreshPushAnchor()
        r._backingAway = false
        r._losGoalX, r._losGoalY = nil, nil
        r._repositioningForLOS = false
        r.hasPlayerLOS = nil
        enemy_attacks.cancel(r)
        r:stop()
        r:syncFromCollider()
        local startDX, startDY = blockedRangerX - px, blockedRangerY - py
        local startDistance = math.sqrt(startDX * startDX + startDY * startDY)
        local minDistance = startDistance
        local retainedLOS = r:hasLineOfSight(px, py)
        local settledAtLOSPosition = false
        for _ = 1, 300 do
            if settledAtLOSPosition then
                break
            end
            r:update(1 / 60, playerActor)
            enemy_attacks.updateProjectiles(1 / 60, playerActor)
            physics.update(1 / 60)
            r:syncFromCollider()
            local dx = r.collider:getX() - px
            local dy = r.collider:getY() - py
            local currentDistance = math.sqrt(dx * dx + dy * dy)
            minDistance = math.min(minDistance, currentDistance)
            retainedLOS = r:hasLineOfSight(px, py)
            local currentVX, currentVY = r.collider:getLinearVelocity()
            local currentSpeed = math.sqrt(
                currentVX * currentVX + currentVY * currentVY
            )
            settledAtLOSPosition = retainedLOS
                and currentDistance >= r.safeDistance
                and not r._repositioningForLOS
                and currentSpeed < 0.01
        end
        local finalDX = r.collider:getX() - px
        local finalDY = r.collider:getY() - py
        local finalDistance = math.sqrt(finalDX * finalDX + finalDY * finalDY)
        local heldLOSFrames = 0
        if settledAtLOSPosition then
            for _ = 1, 60 do
                r:update(1 / 60, playerActor)
                enemy_attacks.updateProjectiles(1 / 60, playerActor)
                physics.update(1 / 60)
                r:syncFromCollider()
                local holdDX = r.collider:getX() - px
                local holdDY = r.collider:getY() - py
                local holdDistance = math.sqrt(
                    holdDX * holdDX + holdDY * holdDY
                )
                if r:hasLineOfSight(px, py)
                    and holdDistance >= r.safeDistance
                then
                    heldLOSFrames = heldLOSFrames + 1
                end
            end
        end
        allOk = check("ranger settles at a safe LOS position",
            settledAtLOSPosition
                and retainedLOS
                and finalDistance >= r.safeDistance
                and minDistance >= startDistance - 0.5,
            string.format("settled=%s los=%s start=%.1f nearest=%.1f final=%.1f",
                tostring(settledAtLOSPosition), tostring(retainedLOS),
                startDistance, minDistance, finalDistance)) and allOk
        allOk = check("ranger retains LOS after settling",
            heldLOSFrames >= 50,
            string.format("held=%d/60 frames", heldLOSFrames)) and allOk

        enemy_attacks.clearAllProjectiles()
        r.collider:setPosition(rx, ry)
        r:refreshPushAnchor()
        enemy_attacks.cancel(r)
        r._backingAway = false
        r._losGoalX, r._losGoalY = nil, nil
        r._repositioningForLOS = false
        r.hasPlayerLOS = nil
        r:stop()
        r:syncFromCollider()
    end

    allOk = check("pickSpawnPoint helper exists",
        type(physics.pickSpawnPoint) == "function"
            and physics.arena ~= nil) and allOk
    allOk = check("isSpawnClear / destroy helpers exist",
        type(physics.isSpawnClear) == "function"
            and type(physics.destroy) == "function") and allOk

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

    -- Plague countdown: damage reduces remaining and clamps at 0.
    local cd = countdown.new({ duration = 10 })
    cd:damage(3)
    allOk = check("countdown damage reduces remaining",
        nearlyEqual(cd:getRemaining(), 7),
        string.format("got %.2f", cd:getRemaining())) and allOk
    cd:damage(100)
    allOk = check("countdown damage clamps at 0",
        nearlyEqual(cd:getRemaining(), 0) and cd:isExpired(),
        string.format("got %.2f expired=%s", cd:getRemaining(), tostring(cd:isExpired()))) and allOk
    local cd2 = countdown.new({ duration = 10 })
    cd2:damage(4)
    cd2:addTime(2)
    allOk = check("countdown addTime refunds seconds",
        nearlyEqual(cd2:getRemaining(), 8),
        string.format("got %.2f", cd2:getRemaining())) and allOk
    cd2:addTime(100)
    allOk = check("countdown addTime clamps to duration",
        nearlyEqual(cd2:getRemaining(), 10),
        string.format("got %.2f", cd2:getRemaining())) and allOk
    allOk = check("player hit damage / iframe tunables",
        nearlyEqual(player.HIT_DAMAGE_SECONDS, 5)
            and nearlyEqual(player.HURT_IFRAME, 0.6),
        string.format("dmg=%.1f iframe=%.1f",
            player.HIT_DAMAGE_SECONDS, player.HURT_IFRAME)) and allOk

    local nestsMod = require "scripts.nests"
    allOk = check("nest cleanse constants",
        nearlyEqual(nestsMod.CLEANSE_SECONDS, 2)
            and nearlyEqual(nestsMod.CLEANSE_START_COST_SECONDS, 2)
            and nestsMod.CLEANSE_HOLD_KEY == "e",
        string.format("cleanse=%.1f cost=%.1f key=%s",
            nestsMod.CLEANSE_SECONDS, nestsMod.CLEANSE_START_COST_SECONDS,
            tostring(nestsMod.CLEANSE_HOLD_KEY))) and allOk
    if state and state.nests then
        allOk = check("nests loaded from map (3 districts + well)",
            #state.nests == 4
                and nestsMod.getWell(state.nests) ~= nil
                and not nestsMod.wellUnlocked(state.nests)
                and not nestsMod.allCleansed(state.nests),
            string.format(
                "count=%d well=%s unlocked=%s",
                #state.nests,
                tostring(nestsMod.getWell(state.nests) ~= nil),
                tostring(nestsMod.wellUnlocked(state.nests))
            )) and allOk
        local maxR = 0
        local wellOnFountain = false
        local districtOnFountain = false
        for _, nest in ipairs(state.nests) do
            maxR = math.max(maxR, nest.radius or 0)
            local onStamp = nest.x >= 13 * 16 and nest.x <= 16 * 16
                and nest.y >= 10 * 16 and nest.y <= 13 * 16
            if nestsMod.isWell(nest) then
                wellOnFountain = onStamp
                    or (math.abs(nest.x - 15 * 16) < 8
                        and math.abs(nest.y - 12 * 16) < 8)
            elseif onStamp then
                districtOnFountain = true
            end
        end
        allOk = check("nest cleanse radii are tight (<=40)",
            maxR <= 40,
            string.format("maxR=%.0f", maxR)) and allOk
        allOk = check("well sits on fountain; districts do not",
            wellOnFountain and not districtOnFountain,
            string.format("wellOn=%s districtOn=%s",
                tostring(wellOnFountain), tostring(districtOnFountain))) and allOk

        local protectedOk = true
        for row = 10, 13 do
            for col = 13, 16 do
                protectedOk = protectedOk and collapse.isProtectedCell(col, row)
            end
        end
        for _, nest in ipairs(state.nests) do
            local col = math.floor(nest.x / 16)
            local row = math.floor(nest.y / 16)
            for dr = -1, 1 do
                for dc = -1, 1 do
                    protectedOk = protectedOk
                        and collapse.isProtectedCell(col + dc, row + dr)
                end
            end
        end
        allOk = check("collapse protects fountain and nest footprints",
            protectedOk and collapse.getFallenCount() == 0) and allOk

        if state.gameMap then
            local coverOk, mismatches = game_map.auditColliderPropCoverage(state.gameMap)
            allOk = check(
                "every rectangle Wall collider has a Props silhouette",
                coverOk,
                (not coverOk and mismatches) and table.concat(mismatches, "; ") or nil
            ) and allOk
        end

        -- Abyss fairness: player center on fallen cell → EXTRACTED (abyss).
        local playerForAbyss = state:getActor("player")
        if playerForAbyss and playerForAbyss.collider then
            local savedX = playerForAbyss.collider:getX()
            local savedY = playerForAbyss.collider:getY()
            local savedExtracted = state.extracted
            local savedReason = state.extractReason
            local function findFreeCell()
                for row = 2, 20 do
                    for col = 2, 27 do
                        if not collapse.isProtectedCell(col, row)
                            and not collapse.isFallenCell(col, row)
                            and not collapse.isCrackingCell(col, row)
                        then
                            return col, row
                        end
                    end
                end
                return nil, nil
            end
            local fallCol, fallRow = findFreeCell()
            local extractOk = false
            if fallCol then
                playerForAbyss.collider:setPosition(
                    fallCol * 16 + 8,
                    fallRow * 16 + 8
                )
                playerForAbyss.pos.x = fallCol * 16 + 8
                playerForAbyss.pos.y = fallRow * 16 + 8
                state.extracted = false
                state.extractReason = nil
                collapse.debugForceFallAt(fallCol, fallRow, state)
                extractOk = state.extracted == true and state.extractReason == "abyss"
            end
            allOk = check(
                "player center on fallen cell → EXTRACTED (abyss)",
                extractOk,
                fallCol and string.format("cell=%d,%d reason=%s", fallCol, fallRow, tostring(state.extractReason))
                    or "no free cell"
            ) and allOk

            -- Enemy on fallen cell destroyed with no time reward.
            local rewardBefore = state.countdown and state.countdown:getRemaining() or 0
            local enemyCol, enemyRow = findFreeCell()
            local voidEnemyOk = false
            if enemyCol and state.countdown then
                state.extracted = false
                state.extractReason = nil
                -- Park player off the void cell so the probe fall does not EXTRACT.
                playerForAbyss.collider:setPosition(savedX, savedY)
                playerForAbyss.pos.x = savedX
                playerForAbyss.pos.y = savedY
                local probe = enemy:new(
                    enemyCol * 16 + 8,
                    enemyRow * 16 + 8,
                    { type = "fleer" }
                )
                probe.killRewardSeconds = 9
                state.actors[#state.actors + 1] = probe
                collapse.debugForceFallAt(enemyCol, enemyRow, state)
                local rewardAfter = state.countdown:getRemaining()
                local gone = probe.dead == true or probe.collider == nil
                voidEnemyOk = gone
                    and nearlyEqual(rewardAfter, rewardBefore, 0.05)
                    and probe.killRewardGranted ~= true
                if not gone and probe.destroyNow then
                    probe:destroyNow({ reward = false })
                end
            end
            allOk = check(
                "enemy on fallen cell destroyed without time reward",
                voidEnemyOk
            ) and allOk

            -- Restore playable state after abyss probes.
            state.extracted = savedExtracted
            state.extractReason = savedReason
            if state.countdown and state.countdown.resume then
                state.countdown:resume()
            elseif state.countdown then
                state.countdown.paused = false
            end
            playerForAbyss.collider:setPosition(savedX, savedY)
            playerForAbyss.pos.x = savedX
            playerForAbyss.pos.y = savedY
        end
    end
    local sampleEnemy = enemyActors and enemyActors[1]
    if sampleEnemy then
        allOk = check("enemy has hp for kill→time loop",
            (sampleEnemy.hp or 0) >= 1,
            string.format("hp=%s", tostring(sampleEnemy.hp))) and allOk

        local savedHP = sampleEnemy.hp
        local savedFlash = sampleEnemy.hurtFlash
        local savedSerial = sampleEnemy.lastPlayerSwingSerial
        local savedAttackHitbox = playerActor.attackHitbox
        local savedSwingHits = playerActor.swingHitEnemies
        local savedSwingSerial = playerActor.swingSerial
        local savedPose = {
            x = playerActor.attackPose.x,
            y = playerActor.attackPose.y,
            angle = playerActor.attackPose.angle,
        }
        playerActor.swingSerial = (savedSwingSerial or 0) + 1
        playerActor.attackHitbox = { active = true }
        playerActor.attackPose.x = sampleEnemy.hurtbox:getX()
        playerActor.attackPose.y = sampleEnemy.hurtbox:getY()
        playerActor.attackPose.angle = 0
        playerActor.swingHitEnemies = {}
        playerActor:pollAttackHits()
        playerActor:pollAttackHits()
        allOk = check("sword registers an enemy once per swing",
            sampleEnemy.hp == savedHP - 1,
            string.format("hp %d→%d", savedHP, sampleEnemy.hp)) and allOk
        sampleEnemy.hp = savedHP
        sampleEnemy.hurtFlash = savedFlash
        sampleEnemy.lastPlayerSwingSerial = savedSerial
        playerActor.attackHitbox = savedAttackHitbox
        playerActor.swingHitEnemies = savedSwingHits
        playerActor.swingSerial = savedSwingSerial
        playerActor.attackPose.x = savedPose.x
        playerActor.attackPose.y = savedPose.y
        playerActor.attackPose.angle = savedPose.angle
    end

    -- Damage foundation: per-type HP/hurtbox, HP decrement, once-per-swing,
    -- death physics removal, and one-time time reward for all four types.
    do
        local enemy_types = require "scripts.enemy_types"
        local expectedDamage = {
            fleer = { hp = 1, hurtW = 22, hurtH = 14, hurtOffsetY = -5 },
            chaser = { hp = 2, hurtW = 18, hurtH = 20, hurtOffsetY = -10 },
            ranger = { hp = 3, hurtW = 16, hurtH = 20, hurtOffsetY = -10 },
            keeper = { hp = 5, hurtW = 22, hurtH = 22, hurtOffsetY = -8 },
        }
        local typeConfigOk = true
        local typeConfigDetail = {}
        for typeId, expect in pairs(expectedDamage) do
            local defaults = enemy_types.defaults[typeId]
            local live = byType[typeId]
            local ok = defaults
                and defaults.hp == expect.hp
                and defaults.hurtW == expect.hurtW
                and defaults.hurtH == expect.hurtH
                and defaults.hurtOffsetY == expect.hurtOffsetY
                and live
                and live.hp == expect.hp
                and live.maxHp == expect.hp
                and live.hurtW == expect.hurtW
                and live.hurtH == expect.hurtH
                and live.hurtOffsetY == expect.hurtOffsetY
                and live.hitW == 14
                and live.hitH == 14
            if not ok then
                typeConfigOk = false
                typeConfigDetail[#typeConfigDetail + 1] = typeId
            end
        end
        allOk = check("per-type HP and torso hurtbox config",
            typeConfigOk,
            #typeConfigDetail > 0 and table.concat(typeConfigDetail, ",") or nil) and allOk

        if enemy and physics.arena then
            local savedState = rawget(_G, "state")
            local rewardCalls = 0
            local removed = {}
            local mockCountdown = {
                remaining = 50,
                addTime = function(self, amount)
                    rewardCalls = rewardCalls + 1
                    self.remaining = self.remaining + amount
                end,
                getRemaining = function(self)
                    return self.remaining
                end,
            }
            local mockState = {
                extracted = false,
                sectorCleared = false,
                countdown = mockCountdown,
                floats = {},
                actors = {},
                getActor = function()
                    return nil
                end,
                pushFloat = function() end,
                removeActor = function(_, actor)
                    removed[actor] = true
                end,
            }
            function mockState:onEnemyKilled(enemyActor)
                if self.extracted or self.sectorCleared or not self.countdown then
                    self:removeActor(enemyActor)
                    return
                end
                local reward = enemyActor.killRewardSeconds or 1.5
                self.countdown:addTime(reward)
                self:removeActor(enemyActor)
            end
            _G.state = mockState

            local killOk = true
            local killDetail = {}
            for _, typeId in ipairs({ "fleer", "chaser", "ranger", "keeper" }) do
                local expect = expectedDamage[typeId]
                rewardCalls = 0
                local probe = enemy:new(
                    physics.arena.cx + 40,
                    physics.arena.cy,
                    { type = typeId }
                )
                probe.killRewardSeconds = 1.5
                mockState.actors[1] = probe

                local hx, hy = probe.hurtbox:getX(), probe.hurtbox:getY()
                local cx, cy = probe.collider:getX(), probe.collider:getY()
                local torsoAligned = nearlyEqual(hx, cx, 0.1)
                    and nearlyEqual(hy, cy + expect.hurtOffsetY, 0.1)
                    and hy < cy
                    and (probe.hurtOffsetY or 0) < 0

                local before = probe.hp
                local hitOnce = probe:onHitByPlayer(1000 + expect.hp)
                local afterOne = probe.hp
                local hitDup = probe:onHitByPlayer(1000 + expect.hp)
                local afterDup = probe.hp
                local hpDecrementOk = hitOnce == true
                    and afterOne == before - 1
                    and hitDup == false
                    and afterDup == before - 1

                -- Finish the remaining hits with unique swing serials.
                local serial = 2000
                while probe.hp > 0 and not probe.dying do
                    serial = serial + 1
                    probe:onHitByPlayer(serial)
                end
                local diedAtZero = probe.dying and probe.hp == 0
                    and probe.collider ~= nil
                    and probe.hurtbox ~= nil

                probe:update(0.1)
                local heldDuringFade = not probe.dead
                    and not probe.readyForRemoval
                    and probe.collider ~= nil
                probe:update(0.15)
                probe:finishDeath()
                local destroyed = probe.dead
                    and probe.collider == nil
                    and probe.hurtbox == nil
                    and removed[probe] == true
                local rewardsAfterFirst = rewardCalls
                probe:finishDeath()
                probe:onHitByPlayer(serial + 99)
                local rewardOnce = rewardsAfterFirst == 1 and rewardCalls == 1

                if not (torsoAligned and hpDecrementOk and diedAtZero
                    and heldDuringFade and destroyed and rewardOnce)
                then
                    killOk = false
                    killDetail[#killDetail + 1] = string.format(
                        "%s torso=%s hp=%s die=%s fade=%s gone=%s reward=%d",
                        typeId,
                        tostring(torsoAligned),
                        tostring(hpDecrementOk),
                        tostring(diedAtZero),
                        tostring(heldDuringFade),
                        tostring(destroyed),
                        rewardCalls
                    )
                end
            end
            _G.state = savedState
            allOk = check(
                "all four types: HP decrement, once/swing, death removal, one reward",
                killOk,
                #killDetail > 0 and table.concat(killDetail, " | ") or nil
            ) and allOk
        end
    end

    local expectedSprites = {
        chaser = "res/images/enemies/chaser.png",
        fleer = "res/images/enemies/fleer.png",
        keeper = "res/images/enemies/keeper.png",
        ranger = "res/images/enemies/ranger.png",
    }
    local presentationConfigOk = true
    local presentationImagesLoaded = true
    for typeId, e in pairs(byType) do
        presentationConfigOk = presentationConfigOk
            and e.spritePath == expectedSprites[typeId]
            and e.hitW == 14
            and e.hitH == 14
        presentationImagesLoaded = presentationImagesLoaded
            and e.img ~= nil
            and e.img:getWidth() == 32
            and e.img:getHeight() == 32
    end
    allOk = check("enemy art cannot resize gameplay hitboxes",
        presentationConfigOk) and allOk
    allOk = check("all four 32x32 enemy images loaded",
        presentationImagesLoaded) and allOk
    local drawOrder = {
        byType.chaser,
        byType.fleer,
        byType.keeper,
        byType.ranger,
    }
    local drawOk, drawError = pcall(function()
        for i = 1, 9 do
            drawOrder[(i - 1) % #drawOrder + 1]:draw()
        end
    end)
    local drawDetail = nil
    if not drawOk then
        drawDetail = tostring(drawError)
    end
    allOk = check("nine-enemy presentation draw smoke",
        drawOk,
        drawDetail) and allOk

    if enemy and physics.arena then
        local savedState = rawget(_G, "state")
        _G.state = nil
        local deathProbe = enemy:new(physics.arena.cx, physics.arena.cy, {
            type = "fleer",
            hp = 1,
        })
        deathProbe:onHitByPlayer(42)
        local beganWithPhysics = deathProbe.dying
            and deathProbe.collider ~= nil
            and deathProbe.hurtbox ~= nil
        deathProbe:update(0.1)
        local heldDuringFade = not deathProbe.dead
            and not deathProbe.readyForRemoval
            and deathProbe.collider ~= nil
        deathProbe:update(0.11)
        deathProbe:finishDeath()
        local destroyedAfterFade = deathProbe.dead
            and deathProbe.collider == nil
            and deathProbe.hurtbox == nil
        local timerAfterDeath = deathProbe.deathTimer
        deathProbe:update(1)
        local deadUpdateSkipped = deathProbe.deathTimer == timerAfterDeath
        _G.state = savedState
        allOk = check("death fade precedes collider destruction",
            beganWithPhysics and heldDuringFade and destroyedAfterFade) and allOk
        allOk = check("dead enemy update is inert", deadUpdateSkipped) and allOk
    end

    print(allOk and "[physics_selftest] ALL PASS" or "[physics_selftest] SOME FAILED")
    return allOk
end

--- Live sword↔hurtbox overlap + kill for all four types; writes F1 overlay PNGs.
function selftest.verifyVisibleKills(playerActor)
    print("[damage_verify] running visible sword hit/kill checks...")
    local allOk = true
    if not playerActor or not playerActor.collider or not physics.arena or not enemy then
        check("damage verify prerequisites", false, "missing player/arena/enemy")
        return false
    end

    love.filesystem.createDirectory("damage_verify")
    local savedDebug = physics.debug
    local savedGlobalDebug = rawget(_G, "DEBUG")
    physics.debug = true
    _G.DEBUG = true

    local order = { "fleer", "chaser", "ranger", "keeper" }
    local expectedHp = { fleer = 1, chaser = 2, ranger = 3, keeper = 5 }
    local baseX, baseY = physics.arena.cx, physics.arena.cy
    playerActor.collider:setPosition(baseX - 28, baseY)
    playerActor:syncFromCollider()

    for _, typeId in ipairs(order) do
        local probe = enemy:new(baseX + 10, baseY, { type = typeId })
        probe:syncHurtbox()
        local liveState = rawget(_G, "state")
        if liveState and liveState.actors then
            liveState.actors[#liveState.actors + 1] = probe
        end
        local hx, hy = probe.hurtbox:getX(), probe.hurtbox:getY()

        -- Place PlayerAttack on the torso hurtbox; overlap poll must register a hit.
        playerActor.swingHitEnemies = {}
        playerActor.swingSerial = (playerActor.swingSerial or 0) + 1
        playerActor.swinging = true
        if playerActor.disableAttackHitbox then
            playerActor:disableAttackHitbox()
        end
        playerActor:enableAttackHitbox()
        playerActor.attackPose.x = hx
        playerActor.attackPose.y = hy
        playerActor.attackPose.angle = 0
        playerActor:syncAttackHitbox()
        playerActor:pollAttackHits()

        local hpAfter = probe.hp
        local hitOk = hpAfter == expectedHp[typeId] - 1
        allOk = check(
            string.format("visible sword overlaps %s hurtbox", typeId),
            hitOk,
            string.format("hp %s→%s @ hurtbox %.1f,%.1f",
                expectedHp[typeId], tostring(hpAfter), hx, hy)
        ) and allOk

        -- Finish the kill with unique swings so HP reaches 0.
        local serial = playerActor.swingSerial
        while probe.hp > 0 and not probe.dying do
            serial = serial + 1
            probe:onHitByPlayer(serial)
        end
        probe:update(0.25)
        if probe.readyForRemoval then
            probe:finishDeath()
        end
        allOk = check(
            string.format("%s reaches death and drops physics", typeId),
            probe.dead and probe.collider == nil and probe.hurtbox == nil,
            string.format("dead=%s collider=%s", tostring(probe.dead), tostring(probe.collider ~= nil))
        ) and allOk

        -- F1-style overlay: sprite, cyan feet collider, red torso hurtbox, magenta sword.
        local canvas = love.graphics.newCanvas(160, 160)
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0.08, 0.08, 0.1, 1)
        love.graphics.push()
        love.graphics.translate(80 - (baseX + 10), 80 - baseY)
        local portrait = enemy:new(baseX + 10, baseY, { type = typeId })
        portrait.hp = math.max(1, expectedHp[typeId] - 1)
        portrait.maxHp = expectedHp[typeId]
        portrait.hurtFlash = 0.08
        portrait.playerDistance = 0
        portrait:syncFromCollider()
        local phx, phy = portrait.hurtbox:getX(), portrait.hurtbox:getY()
        portrait:draw()
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 0.25, 0.85, 0.95)
        love.graphics.rectangle(
            "line",
            phx - playerActor.attackW / 2,
            phy - playerActor.attackH / 2,
            playerActor.attackW,
            playerActor.attackH
        )
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.pop()
        love.graphics.setCanvas()
        local imageData = canvas:newImageData()
        local path = string.format("damage_verify/%s.png", typeId)
        imageData:encode("png", path)
        imageData:release()
        canvas:release()
        portrait:destroyNow({ reward = false })
        print(string.format("[damage_verify] wrote %s", path))

        if playerActor.disableAttackHitbox then
            playerActor:disableAttackHitbox()
        end
        playerActor.swinging = false
    end

    physics.debug = savedDebug
    _G.DEBUG = savedGlobalDebug
    print(allOk and "[damage_verify] ALL PASS" or "[damage_verify] SOME FAILED")
    return allOk
end

return selftest
