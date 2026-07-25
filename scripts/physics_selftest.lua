-- Console PASS/FAIL checks for the physics milestone (no LOVE key simulation needed).

local physics = require "scripts.physics"
local countdown = require "scripts.countdown"
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
            nearlyEqual(c.speed, 75) and nearlyEqual(c.aggroRange, 140)
                and nearlyEqual(c.stopDistance, 28)
                and nearlyEqual(c.stopDeadzone, 6)
                and nearlyEqual(c.separationDistance, 28)
                and nearlyEqual(c.separationSpeed, 24),
            string.format("speed=%.0f aggro=%.0f stop=%.0f dead=%.0f sep=%.0f@%.0f",
                c.speed or -1, c.aggroRange or -1,
                c.stopDistance or -1, c.stopDeadzone or -1,
                c.separationDistance or -1, c.separationSpeed or -1)) and allOk
    end
    if byType.fleer then
        local f = byType.fleer
        allOk = check("fleer default fields",
            nearlyEqual(f.speed, 95) and nearlyEqual(f.fleeRange, 90)
                and nearlyEqual(f.fleeDeadzone, 10),
            string.format("speed=%.0f flee=%.0f dead=%.0f",
                f.speed or -1, f.fleeRange or -1, f.fleeDeadzone or -1)) and allOk
    end
    if byType.keeper then
        local k = byType.keeper
        allOk = check("keeper default fields",
            nearlyEqual(k.speed, 70) and nearlyEqual(k.aggroRange, 160)
                and nearlyEqual(k.preferredDistance, 70) and nearlyEqual(k.band, 18),
            string.format("speed=%.0f aggro=%.0f pref=%.0f band=%.0f",
                k.speed or -1, k.aggroRange or -1,
                k.preferredDistance or -1, k.band or -1)) and allOk
    end
    if byType.ranger then
        local r = byType.ranger
        allOk = check("ranger default fields",
            nearlyEqual(r.speed, 65) and nearlyEqual(r.aggroRange, 190)
                and nearlyEqual(r.safeDistance, 95)
                and nearlyEqual(r.safeDeadzone, 12)
                and nearlyEqual(r.meleeRange, 32)
                and nearlyEqual(r.meleeReleaseRange, 39)
                and nearlyEqual(r.meleeCooldown, 0.8)
                and nearlyEqual(r.losDistanceBuffer, 10)
                and nearlyEqual(r.losGoalTolerance, 7)
                and nearlyEqual(r.losProbeDistance, 32)
                and nearlyEqual(r.losRetreatWeight, 0.65)
                and r.debugLetter == "R",
            string.format("speed=%.0f aggro=%.0f safe=%.0f melee=%.0f/%.0f",
                r.speed or -1, r.aggroRange or -1,
                r.safeDistance or -1, r.meleeRange or -1,
                r.meleeReleaseRange or -1)) and allOk

        local clearLOS = physics.hasLineOfSight(120, 150, 180, 150)
        local blockedLOS = physics.hasLineOfSight(200, 60, 200, 150)
        allOk = check("wall-aware line of sight",
            clearLOS and not blockedLOS,
            string.format("clear=%s blocked=%s",
                tostring(clearLOS), tostring(blockedLOS))) and allOk

        local rx, ry = r.collider:getX(), r.collider:getY()
        local px, py = playerActor.collider:getX(), playerActor.collider:getY()
        local startingHitCount = playerActor.enemyHitCount
        local startingAttackSerial = r.attackSerial
        local liveCountdown = rawget(_G, "state") and state.countdown
        local savedRemaining = liveCountdown and liveCountdown:getRemaining()
        local savedExtracted = rawget(_G, "state") and state.extracted
        r.collider:setPosition(px + r.meleeRange - 2, py)
        r:refreshPushAnchor()
        r._meleeEngaged = false
        r.wantsMeleeAttack = false
        r.attackCooldownTimer = 0
        playerActor.hurtIFrame = 0
        r:update(1 / 60, playerActor)
        local meleeVX, meleeVY = r.collider:getLinearVelocity()
        local meleeSpeed = math.sqrt(
            meleeVX * meleeVX + meleeVY * meleeVY
        )
        local drainedOk = true
        if liveCountdown and savedRemaining then
            drainedOk = liveCountdown:getRemaining()
                <= savedRemaining - (playerActor.hitDamageSeconds or player.HIT_DAMAGE_SECONDS) + 0.01
        end
        allOk = check("cornered ranger stops, faces, and hits",
            r._meleeEngaged
                and r.wantsMeleeAttack
                and meleeSpeed < 0.01
                and r.facing.x < -0.99
                and math.abs(r.facing.y) < 0.01
                and r.attackSerial == startingAttackSerial + 1
                and playerActor.enemyHitCount == startingHitCount + 1
                and drainedOk,
            string.format(
                "engaged=%s speed=%.2f facing=%.2f,%.2f attacks=%d hits=%d drained=%s",
                tostring(r._meleeEngaged), meleeSpeed,
                r.facing.x, r.facing.y,
                r.attackSerial - startingAttackSerial,
                playerActor.enemyHitCount - startingHitCount,
                tostring(drainedOk)
            )) and allOk

        r:update(1 / 60, playerActor)
        allOk = check("ranger melee obeys cooldown",
            r.attackSerial == startingAttackSerial + 1,
            string.format("cooldown=%.2f attacks=%d",
                r.attackCooldownTimer,
                r.attackSerial - startingAttackSerial)) and allOk

        r.collider:setPosition(rx, ry)
        r:refreshPushAnchor()
        r._meleeEngaged = false
        r.wantsMeleeAttack = false
        r.attackCooldownTimer = 0
        r.attackFlash = 0
        playerActor.enemyHitCount = startingHitCount
        playerActor.enemyHitFlash = 0
        playerActor.hurtIFrame = 0
        if liveCountdown and savedRemaining then
            liveCountdown.remaining = savedRemaining
            liveCountdown.damagePulse = 0
            liveCountdown.damagePulseTime = 0
            liveCountdown.paused = false
        end
        if rawget(_G, "state") and savedExtracted ~= nil then
            state.extracted = savedExtracted
        end
        r:stop()
        r:syncFromCollider()

        -- Put the ranger above the vertical test block: it is too close and
        -- occluded, so its chosen velocity must restore LOS without closing in.
        r.collider:setPosition(200, 60)
        r:update(1 / 60, playerActor)
        local vx, vy = r.collider:getLinearVelocity()
        local towardX, towardY = 0, 90
        local closingSpeed = vx * towardX + vy * towardY
        local moving = math.sqrt(vx * vx + vy * vy)
        allOk = check("ranger retreats while restoring LOS",
            r.hasPlayerLOS == false and moving > 0.01 and closingSpeed <= 0,
            string.format("los=%s vel=%.1f,%.1f closingDot=%.1f",
                tostring(r.hasPlayerLOS), vx, vy, closingSpeed)) and allOk

        -- Exercise the real collider/world loop from the ranger's blocked demo
        -- spawn and confirm that its strafe actually clears the obstruction.
        r.collider:setPosition(rx, ry)
        r:refreshPushAnchor()
        r._backingAway = false
        r._losGoalX, r._losGoalY = nil, nil
        r._repositioningForLOS = false
        r._meleeEngaged = false
        r.wantsMeleeAttack = false
        r.hasPlayerLOS = nil
        r:stop()
        r:syncFromCollider()
        local startDX, startDY = rx - px, ry - py
        local startDistance = math.sqrt(startDX * startDX + startDY * startDY)
        local minDistance = startDistance
        local retainedLOS = r:hasLineOfSight(px, py)
        local settledAtLOSPosition = false
        for _ = 1, 300 do
            if settledAtLOSPosition then
                break
            end
            r:update(1 / 60, playerActor)
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
            heldLOSFrames == 60,
            string.format("held=%d/60 frames", heldLOSFrames)) and allOk

        r.collider:setPosition(rx, ry)
        r:refreshPushAnchor()
        r._backingAway = false
        r._losGoalX, r._losGoalY = nil, nil
        r._repositioningForLOS = false
        r._meleeEngaged = false
        r.wantsMeleeAttack = false
        r.attackCooldownTimer = 0
        r.attackFlash = 0
        r.hasPlayerLOS = nil
        r:stop()
        r:syncFromCollider()
    end

    allOk = check("pickSpawnPoint helper exists",
        type(physics.pickSpawnPoint) == "function"
            and physics.arena ~= nil) and allOk

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
    allOk = check("player hit damage / iframe tunables",
        nearlyEqual(player.HIT_DAMAGE_SECONDS, 5)
            and nearlyEqual(player.HURT_IFRAME, 0.6),
        string.format("dmg=%.1f iframe=%.1f",
            player.HIT_DAMAGE_SECONDS, player.HURT_IFRAME)) and allOk

    print(allOk and "[physics_selftest] ALL PASS" or "[physics_selftest] SOME FAILED")
    return allOk
end

return selftest
