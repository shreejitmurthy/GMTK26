-- Development-only arena: one of each enemy type, no director/collapse decay.
-- Launch: love . -- --enemy-test

local physics = require "scripts.physics"
local enemy_attacks = require "scripts.enemy_attacks"
require "scripts.enemy"

local enemy_test = {}

local ORDER = { "chaser", "fleer", "keeper", "ranger" }

function enemy_test.isActive(stateRef)
    return stateRef and stateRef.enemyTestMode == true
end

--- Spawn exactly one of each type with clear separation around the player.
function enemy_test.spawnSet(playerX, playerY)
    local cx = playerX or (physics.arena and physics.arena.cx) or 240
    local cy = playerY or (physics.arena and physics.arena.cy) or 192
    local slots = {
        chaser = { cx - 72, cy - 48 },
        fleer = { cx + 72, cy - 48 },
        keeper = { cx - 72, cy + 56 },
        ranger = { cx + 72, cy + 56 },
    }
    local enemies = {}
    for _, typeId in ipairs(ORDER) do
        local pos = slots[typeId]
        local e = enemy:new(pos[1], pos[2], { type = typeId })
        e.killRewardSeconds = 0
        e.nest = nil
        enemies[#enemies + 1] = e
    end
    return enemies
end

function enemy_test.countByType(actors)
    local counts = { chaser = 0, fleer = 0, keeper = 0, ranger = 0 }
    for _, actor in ipairs(actors or {}) do
        if actor.label == "enemy" and not actor.dead and counts[actor.enemyType] then
            counts[actor.enemyType] = counts[actor.enemyType] + 1
        end
    end
    return counts
end

function enemy_test.drawHud(stateRef)
    if not enemy_test.isActive(stateRef) then
        return
    end
    local helpFont = stateRef.hudHelpFont
    local labelFont = stateRef.hudLabelFont
    if labelFont then
        love.graphics.setFont(labelFont)
    end
    love.graphics.setColor(0.95, 0.85, 0.55, 0.95)
    love.graphics.print("ENEMY TEST", 12, 10)
    if helpFont then
        love.graphics.setFont(helpFont)
    end
    love.graphics.setColor(0.85, 0.85, 0.8, 0.85)
    love.graphics.print("R reset · Esc quit · Space/LMB swing · countdown paused", 12, 34)

    local y = 56
    for _, actor in ipairs(stateRef.actors or {}) do
        if actor.label == "enemy" and not actor.dead then
            local hp = actor.hp or 0
            local maxHp = actor.maxHp or hp
            local atk = enemy_attacks.getStateLabel(actor)
            local dmg = enemy_attacks.expectedDamage(actor)
            love.graphics.setColor(0.15, 0.12, 0.1, 0.72)
            love.graphics.rectangle("fill", 10, y - 2, 220, 18)
            love.graphics.setColor(0.95, 0.9, 0.82, 0.95)
            love.graphics.print(
                string.format(
                    "%s  HP %d/%d  %s  hit -%ds",
                    string.upper(actor.enemyType or "?"),
                    hp,
                    maxHp,
                    atk,
                    dmg
                ),
                14,
                y
            )
            y = y + 20
        elseif actor.label == "enemy" and actor.dead then
            love.graphics.setColor(0.5, 0.45, 0.4, 0.7)
            love.graphics.print(
                string.format("%s  DEAD", string.upper(actor.enemyType or "?")),
                14,
                y
            )
            y = y + 20
        end
    end

    local counts = enemy_test.countByType(stateRef.actors)
    love.graphics.setColor(0.7, 0.75, 0.7, 0.8)
    love.graphics.print(
        string.format(
            "alive C%d F%d K%d R%d · shots %d",
            counts.chaser,
            counts.fleer,
            counts.keeper,
            counts.ranger,
            enemy_attacks.projectileCount()
        ),
        12,
        y + 6
    )
    love.graphics.setColor(1, 1, 1, 1)
end

--- Console smoke: one-of-each spawn + kill + attack damage identities.
function enemy_test.runSmoke(stateRef, playerActor)
    print("[enemy_test] smoke running...")
    local ok = true
    local counts = enemy_test.countByType(stateRef.actors)
    for _, typeId in ipairs(ORDER) do
        if counts[typeId] ~= 1 then
            ok = false
            print(string.format(
                "[enemy_test] FAIL: expected 1 %s, got %d",
                typeId,
                counts[typeId] or 0
            ))
        else
            print(string.format("[enemy_test] PASS: one %s", typeId))
        end
    end

    local expect = {
        chaser = { dmg = 4, style = "lunge" },
        fleer = { dmg = 3, style = "pounce" },
        keeper = { dmg = 8, style = "slam" },
        ranger = { dmg = 5, style = "shot" },
    }
    for _, actor in ipairs(stateRef.actors or {}) do
        if actor.label == "enemy" and expect[actor.enemyType] then
            local exp = expect[actor.enemyType]
            if actor.attackStyle ~= exp.style
                or actor.attackDamageSeconds ~= exp.dmg
            then
                ok = false
                print(string.format(
                    "[enemy_test] FAIL: %s style/dmg %s/%s",
                    actor.enemyType,
                    tostring(actor.attackStyle),
                    tostring(actor.attackDamageSeconds)
                ))
            else
                print(string.format(
                    "[enemy_test] PASS: %s %s -%ds",
                    actor.enemyType,
                    actor.attackStyle,
                    actor.attackDamageSeconds
                ))
            end
        end
    end

    if playerActor and physics.arena and playerActor.collider then
        local savedState = rawget(_G, "state")
        for _, typeId in ipairs(ORDER) do
            local probe = enemy:new(physics.arena.cx, physics.arena.cy, {
                type = typeId,
            })
            local hp = probe.hp
            local serial = 1
            while probe.hp > 0 and not probe.dying and serial < 20 do
                probe:onHitByPlayer(9000 + serial)
                serial = serial + 1
            end
            probe:update(0.25)
            if probe.readyForRemoval then
                probe:finishDeath()
            end
            if not (probe.dead and probe.collider == nil and hp >= 1) then
                ok = false
                print(string.format(
                    "[enemy_test] FAIL: %s not killable (hp0=%s dead=%s)",
                    typeId,
                    tostring(hp),
                    tostring(probe.dead)
                ))
            else
                print(string.format(
                    "[enemy_test] PASS: %s killable (%d hp)",
                    typeId,
                    hp
                ))
            end
        end

        -- Deliberate hit + dodge checks for each attack identity.
        -- Use a clear plaza point (player start), not the fountain center.
        local clearX, clearY = 200, 300
        local function resetPlayerCombat()
            playerActor.hurtIFrame = 0
            playerActor.enemyHitCount = 0
            if stateRef.countdown then
                stateRef.countdown.remaining = 80
                stateRef.countdown.paused = true
            end
        end

        local function stepEnemy(e, frames)
            for _ = 1, frames do
                e:update(1 / 60, playerActor)
                enemy_attacks.updateProjectiles(1 / 60, playerActor)
                physics.update(1 / 60)
                if e.syncFromCollider then
                    e:syncFromCollider()
                end
                playerActor:syncFromCollider()
            end
        end

        -- Keeper slam: inside circle = hit, outside = dodge.
        do
            resetPlayerCombat()
            local k = enemy:new(clearX, clearY, { type = "keeper" })
            enemy_attacks.cancel(k)
            k.attackCooldownTimer = 0
            playerActor.collider:setPosition(k.collider:getX() + 10, k.collider:getY())
            playerActor:syncFromCollider()
            stepEnemy(k, 1)
            local teleOk = k.attackState == "telegraph" and playerActor.enemyHitCount == 0
            stepEnemy(k, 50)
            local hitOk = playerActor.enemyHitCount >= 1
                and stateRef.countdown:getRemaining() <= 80 - 7.9
            k:destroyNow({ reward = false })

            resetPlayerCombat()
            k = enemy:new(clearX, clearY, { type = "keeper" })
            enemy_attacks.cancel(k)
            k.attackCooldownTimer = 0
            playerActor.collider:setPosition(k.collider:getX() + 10, k.collider:getY())
            playerActor:syncFromCollider()
            stepEnemy(k, 1)
            -- Sidestep out of the danger circle during telegraph.
            playerActor.collider:setPosition(
                k.collider:getX() + (k.slamRadius or 38) + 20,
                k.collider:getY()
            )
            playerActor:syncFromCollider()
            stepEnemy(k, 50)
            local dodgeOk = playerActor.enemyHitCount == 0
            k:destroyNow({ reward = false })
            if not (teleOk and hitOk and dodgeOk) then
                ok = false
                print(string.format(
                    "[enemy_test] FAIL: keeper slam hit/dodge tele=%s hit=%s dodge=%s",
                    tostring(teleOk), tostring(hitOk), tostring(dodgeOk)
                ))
            else
                print("[enemy_test] PASS: keeper slam hit inside / dodge outside")
            end
        end

        -- Chaser lunge: standing in path = hit; sidestep = dodge.
        do
            resetPlayerCombat()
            local c = enemy:new(clearX - 28, clearY, { type = "chaser" })
            enemy_attacks.cancel(c)
            c.attackCooldownTimer = 0
            playerActor.collider:setPosition(clearX, clearY)
            playerActor:syncFromCollider()
            stepEnemy(c, 1)
            local teleOk = c.attackState == "telegraph" and playerActor.enemyHitCount == 0
            stepEnemy(c, 45)
            local hitOk = playerActor.enemyHitCount >= 1
            c:destroyNow({ reward = false })

            resetPlayerCombat()
            c = enemy:new(clearX - 28, clearY, { type = "chaser" })
            enemy_attacks.cancel(c)
            c.attackCooldownTimer = 0
            playerActor.collider:setPosition(clearX, clearY)
            playerActor:syncFromCollider()
            stepEnemy(c, 1)
            playerActor.collider:setPosition(clearX, clearY + 42)
            playerActor:syncFromCollider()
            stepEnemy(c, 45)
            local dodgeOk = playerActor.enemyHitCount == 0
            c:destroyNow({ reward = false })
            if not (teleOk and hitOk and dodgeOk) then
                ok = false
                print(string.format(
                    "[enemy_test] FAIL: chaser lunge hit/dodge tele=%s hit=%s dodge=%s",
                    tostring(teleOk), tostring(hitOk), tostring(dodgeOk)
                ))
            else
                print("[enemy_test] PASS: chaser lunge hit / sidestep dodge")
            end
        end

        -- Fleer pounce: contact during strike hits; sidestep dodges.
        do
            resetPlayerCombat()
            local f = enemy:new(clearX - 36, clearY, { type = "fleer" })
            enemy_attacks.cancel(f)
            f.attackCooldownTimer = 0
            playerActor.collider:setPosition(clearX, clearY)
            playerActor:syncFromCollider()
            stepEnemy(f, 1)
            local teleOk = f.attackState == "telegraph" and playerActor.enemyHitCount == 0
            stepEnemy(f, 55)
            local hitOk = playerActor.enemyHitCount >= 1
            f:destroyNow({ reward = false })

            resetPlayerCombat()
            f = enemy:new(clearX - 36, clearY, { type = "fleer" })
            enemy_attacks.cancel(f)
            f.attackCooldownTimer = 0
            playerActor.collider:setPosition(clearX, clearY)
            playerActor:syncFromCollider()
            stepEnemy(f, 1)
            playerActor.collider:setPosition(clearX, clearY + 48)
            playerActor:syncFromCollider()
            stepEnemy(f, 55)
            local dodgeOk = playerActor.enemyHitCount == 0
            f:destroyNow({ reward = false })
            if not (teleOk and hitOk and dodgeOk) then
                ok = false
                print(string.format(
                    "[enemy_test] FAIL: fleer pounce hit/dodge tele=%s hit=%s dodge=%s",
                    tostring(teleOk), tostring(hitOk), tostring(dodgeOk)
                ))
            else
                print("[enemy_test] PASS: fleer pounce hit / sidestep dodge")
            end
        end

        -- Ranger shot: standing in lane = hit; sidestep = dodge.
        do
            resetPlayerCombat()
            enemy_attacks.clearAllProjectiles()
            local r = enemy:new(clearX + 100, clearY, { type = "ranger" })
            enemy_attacks.cancel(r)
            r.attackCooldownTimer = 0
            playerActor.collider:setPosition(clearX, clearY)
            playerActor:syncFromCollider()
            stepEnemy(r, 1)
            local teleOk = r.attackState == "telegraph" and playerActor.enemyHitCount == 0
            stepEnemy(r, 90)
            local hitOk = playerActor.enemyHitCount >= 1
            r:destroyNow({ reward = false })
            enemy_attacks.clearAllProjectiles()

            resetPlayerCombat()
            r = enemy:new(clearX + 100, clearY, { type = "ranger" })
            enemy_attacks.cancel(r)
            r.attackCooldownTimer = 0
            playerActor.collider:setPosition(clearX, clearY)
            playerActor:syncFromCollider()
            stepEnemy(r, 1)
            playerActor.collider:setPosition(clearX, clearY + 40)
            playerActor:syncFromCollider()
            stepEnemy(r, 90)
            local dodgeOk = playerActor.enemyHitCount == 0
            r:destroyNow({ reward = false })
            enemy_attacks.clearAllProjectiles()
            if not (teleOk and hitOk and dodgeOk) then
                ok = false
                print(string.format(
                    "[enemy_test] FAIL: ranger shot hit/dodge tele=%s hit=%s dodge=%s",
                    tostring(teleOk), tostring(hitOk), tostring(dodgeOk)
                ))
            else
                print("[enemy_test] PASS: ranger shot hit / sidestep dodge")
            end
        end

        local spawnX = physics.arena.cx
        local spawnY = physics.arena.cy
        if stateRef.gameMap then
            local game_map = require "scripts.game_map"
            local sx, sy = game_map.getPlayerStart(stateRef.gameMap)
            if sx then
                spawnX, spawnY = sx, sy
            end
        end
        playerActor.collider:setPosition(spawnX, spawnY)
        playerActor:syncFromCollider()
        playerActor.hurtIFrame = 0
        if stateRef.countdown then
            stateRef.countdown.remaining = 90
            stateRef.countdown.paused = true
        end

        -- Stuck-state safety: living enemies must leave non-idle within budget.
        do
            local stuckProbe = enemy:new(clearX, clearY, { type = "chaser" })
            enemy_attacks.cancel(stuckProbe)
            stuckProbe.attackCooldownTimer = 0
            playerActor.collider:setPosition(clearX + 20, clearY)
            playerActor:syncFromCollider()
            -- Force a bogus hung state past the timeout budget.
            stuckProbe.attackState = "recovery"
            stuckProbe.attackTimer = 99
            stuckProbe.attackPhaseElapsed = 10
            stuckProbe._attackStuckLogged = false
            stuckProbe:update(1 / 60, playerActor)
            local cleared = stuckProbe.attackState == "idle"
            stuckProbe:destroyNow({ reward = false })
            if not cleared then
                ok = false
                print("[enemy_test] FAIL: stuck attack state was not force-cancelled")
            else
                print("[enemy_test] PASS: stuck attack state force-cancels to idle")
            end

            -- Full cycle: telegraph → strike → recovery → idle with post-gap.
            local cycleOk = true
            for _, typeId in ipairs(ORDER) do
                local e = enemy:new(clearX - 30, clearY, { type = typeId })
                enemy_attacks.cancel(e)
                e.attackCooldownTimer = 0
                if typeId == "ranger" then
                    e.collider:setPosition(clearX + 100, clearY)
                    e:refreshPushAnchor()
                end
                playerActor.collider:setPosition(clearX, clearY)
                playerActor:syncFromCollider()
                local sawTele, sawIdle = false, false
                for _ = 1, 220 do
                    e:update(1 / 60, playerActor)
                    enemy_attacks.updateProjectiles(1 / 60, playerActor)
                    physics.update(1 / 60)
                    e:syncFromCollider()
                    if e.attackState == "telegraph" then
                        sawTele = true
                    end
                    if sawTele and e.attackState == "idle" then
                        sawIdle = true
                        break
                    end
                    local stuck = enemy_attacks.anyStuck({ e })
                    if stuck then
                        cycleOk = false
                        break
                    end
                end
                if not (sawTele and sawIdle and e.attackState == "idle") then
                    cycleOk = false
                    print(string.format(
                        "[enemy_test] FAIL: %s did not recover to idle (state=%s tele=%s)",
                        typeId,
                        tostring(e.attackState),
                        tostring(sawTele)
                    ))
                end
                e:destroyNow({ reward = false })
                enemy_attacks.clearAllProjectiles()
            end
            if cycleOk then
                print("[enemy_test] PASS: all types attack then return to idle")
            else
                ok = false
            end

            local liveStuck, culprit = enemy_attacks.anyStuck(stateRef.actors)
            if liveStuck then
                ok = false
                print(string.format(
                    "[enemy_test] FAIL: live enemy stuck in %s (%s)",
                    tostring(culprit and culprit.attackState),
                    tostring(culprit and culprit.enemyType)
                ))
            else
                print("[enemy_test] PASS: no living enemy stuck in attack state")
            end
        end

        _G.state = savedState
    end

    print(ok and "[enemy_test] SMOKE PASS" or "[enemy_test] SMOKE FAIL")
    return ok
end

return enemy_test
