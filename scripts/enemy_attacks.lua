-- Per-type attack identities: lunge / pounce / slam / projectile.
-- Damage always routes enemy → player:onHitByEnemy → state:applyPlayerDamage.

local physics = require "scripts.physics"

local enemy_attacks = {}

local projectiles = {}

local ATTACK_DEFAULTS = {
    chaser = {
        attackStyle = "lunge",
        attackDamageSeconds = 4,
        attackTelegraph = 0.25,
        attackStrike = 0.18,
        attackRecovery = 0.9,
        attackRange = 42,
        lungeSpeed = 240,
        hitRadius = 22,
        attackPostGap = 0.45,
    },
    fleer = {
        attackStyle = "pounce",
        attackDamageSeconds = 3,
        attackTelegraph = 0.35,
        attackStrike = 0.32,
        attackRecovery = 0.75,
        attackRange = 58,
        pounceSpeed = 280,
        hitRadius = 20,
        attackPostGap = 0.4,
    },
    keeper = {
        attackStyle = "slam",
        attackDamageSeconds = 8,
        attackTelegraph = 0.65,
        attackStrike = 0.1,
        attackRecovery = 1.25,
        attackRange = 54,
        slamRadius = 38,
        attackPostGap = 0.5,
    },
    ranger = {
        attackStyle = "shot",
        attackDamageSeconds = 5,
        attackTelegraph = 0.45,
        attackStrike = 0.06,
        attackRecovery = 1.5,
        attackRange = 170,
        minShotDistance = 90,
        maxShotDistance = 110,
        projectileSpeed = 150,
        projectileRadius = 4,
        attackPostGap = 0.35,
    },
}

local ATTACK_FIELDS = {
    "attackStyle",
    "attackDamageSeconds",
    "attackTelegraph",
    "attackStrike",
    "attackRecovery",
    "attackPostGap",
    "attackRange",
    "lungeSpeed",
    "pounceSpeed",
    "hitRadius",
    "slamRadius",
    "minShotDistance",
    "maxShotDistance",
    "projectileSpeed",
    "projectileRadius",
}

function enemy_attacks.defaultsFor(typeId)
    return ATTACK_DEFAULTS[typeId] or ATTACK_DEFAULTS.chaser
end

function enemy_attacks.apply(e, options)
    options = options or {}
    local defaults = enemy_attacks.defaultsFor(e.enemyType)
    for _, field in ipairs(ATTACK_FIELDS) do
        if options[field] ~= nil then
            e[field] = options[field]
        elseif defaults[field] ~= nil then
            e[field] = defaults[field]
        end
    end
    -- Short gap after recovery before another telegraph can start.
    e.attackPostGap = options.attackPostGap or defaults.attackPostGap or 0.4
    e.attackState = "idle"
    e.attackTimer = 0
    e.attackHitApplied = false
    e.attackLockX = nil
    e.attackLockY = nil
    e.attackDirX = 0
    e.attackDirY = 0
    e.slamX = nil
    e.slamY = nil
    e.attackLabel = "idle"
    e.attackPhaseElapsed = 0
    e._attackStuckLogged = false
end

function enemy_attacks.cancel(e)
    if not e then
        return
    end
    e.attackState = "idle"
    e.attackTimer = 0
    e.attackHitApplied = false
    e.pendingAttack = false
    e.attackWindupTimer = 0
    e.attackFlash = 0
    e.attackLabel = "idle"
    e.slamX, e.slamY = nil, nil
    e.attackPhaseElapsed = 0
    e.wantsMeleeAttack = false
    enemy_attacks.clearOwnedProjectiles(e)
end

function enemy_attacks.clearAllProjectiles()
    for i = #projectiles, 1, -1 do
        projectiles[i] = nil
    end
end

function enemy_attacks.clearOwnedProjectiles(owner)
    for i = #projectiles, 1, -1 do
        if projectiles[i].owner == owner then
            table.remove(projectiles, i)
        end
    end
end

function enemy_attacks.clearAll()
    enemy_attacks.clearAllProjectiles()
end

local function dealDamageOnce(e, player)
    if e.attackHitApplied or not player or not player.onHitByEnemy then
        return false
    end
    e.attackHitApplied = true
    e.attackSerial = (e.attackSerial or 0) + 1
    player:onHitByEnemy(e)
    return true
end

local function playerPos(player)
    if not player or not player.collider then
        return nil, nil
    end
    return player.collider:getX(), player.collider:getY()
end

local function attackBudget(e)
    return (e.attackTelegraph or 0.25)
        + (e.attackStrike or 0.1)
        + (e.attackRecovery or 0.9)
        + (e.attackPostGap or 0.35)
        + 0.25
end

local function beginTelegraph(e, player, label)
    local px, py = playerPos(player)
    if not px then
        return false
    end
    local ex, ey = e.collider:getX(), e.collider:getY()
    local dx, dy = px - ex, py - ey
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > 0 then
        e.attackDirX, e.attackDirY = dx / dist, dy / dist
    else
        e.attackDirX, e.attackDirY = e.facing.x or 1, e.facing.y or 0
    end
    e.attackLockX, e.attackLockY = px, py
    e:faceToward(px, py)
    e.attackState = "telegraph"
    e.attackTimer = e.attackTelegraph or 0.25
    e.attackHitApplied = false
    e.pendingAttack = true
    e.attackWindupTimer = e.attackTimer
    e.attackFlash = e.attackTimer
    e.attackLabel = label or "telegraph"
    -- Cooldown is armed when the attack finishes, not here (avoids spam re-telegraph).
    e.attackPhaseElapsed = 0
    if e.attackStyle == "slam" then
        e.slamX, e.slamY = ex, ey
    end
    return true
end

local function beginStrike(e)
    e.attackState = "strike"
    e.attackTimer = e.attackStrike or 0.1
    e.pendingAttack = false
    e.attackWindupTimer = 0
    e.attackFlash = math.max(0.08, e.attackTimer)
    if e.attackStyle == "slam" then
        e.attackLabel = "slam"
        local ex, ey = e.collider:getX(), e.collider:getY()
        e.slamX, e.slamY = ex, ey
    elseif e.attackStyle == "shot" then
        e.attackLabel = "shot"
    elseif e.attackStyle == "pounce" then
        e.attackLabel = "pounce"
    else
        e.attackLabel = "lunge"
    end
end

local function beginRecovery(e)
    e.attackState = "recovery"
    e.attackTimer = e.attackRecovery or 0.9
    e.pendingAttack = false
    e.attackWindupTimer = 0
    e.attackFlash = 0
    e.attackLabel = "recovery"
    if e.collider then
        e.collider:setLinearVelocity(0, 0)
    end
end

local function finishToIdle(e)
    e.attackState = "idle"
    e.attackTimer = 0
    e.pendingAttack = false
    e.attackWindupTimer = 0
    e.attackFlash = 0
    e.attackLabel = "idle"
    e.slamX, e.slamY = nil, nil
    e.attackPhaseElapsed = 0
    -- Post-recovery gap so standing next to the player cannot chain telegraphs.
    e.attackCooldownTimer = math.max(
        e.attackCooldownTimer or 0,
        e.attackPostGap or 0.35
    )
end

local function spawnProjectile(e)
    local ex, ey = e.collider:getX(), e.collider:getY()
    local speed = e.projectileSpeed or 150
    projectiles[#projectiles + 1] = {
        x = ex + e.attackDirX * 10,
        y = ey + e.attackDirY * 10,
        vx = e.attackDirX * speed,
        vy = e.attackDirY * speed,
        r = e.projectileRadius or 4,
        owner = e,
        damageSeconds = e.attackDamageSeconds or 5,
        alive = true,
        hit = false,
    }
end

local function overlapPlayer(e, player, radius)
    local px, py = playerPos(player)
    if not px or not e.collider then
        return false
    end
    local ex, ey = e.collider:getX(), e.collider:getY()
    local dx, dy = px - ex, py - ey
    -- Include a small player body allowance so short lunges still connect.
    local reach = (radius or 16) + 8
    return (dx * dx + dy * dy) <= (reach * reach)
end

local function updateLungeStrike(e, dt, player)
    local speed = e.lungeSpeed or 230
    local vx = e.attackDirX * speed
    local vy = e.attackDirY * speed
    vx, vy = physics.constrainEnemyMotion(e.collider, vx, vy, dt, speed)
    e:applyVelocity(vx, vy)
    if overlapPlayer(e, player, e.hitRadius or 16) then
        dealDamageOnce(e, player)
    end
end

local function updatePounceStrike(e, dt, player)
    local speed = e.pounceSpeed or 270
    local vx = e.attackDirX * speed
    local vy = e.attackDirY * speed
    vx, vy = physics.constrainEnemyMotion(e.collider, vx, vy, dt, speed)
    e:applyVelocity(vx, vy)
    if overlapPlayer(e, player, e.hitRadius or 15) then
        dealDamageOnce(e, player)
    end
end

local function resolveSlam(e, player)
    local px, py = playerPos(player)
    if not px then
        return
    end
    local sx = e.slamX or e.collider:getX()
    local sy = e.slamY or e.collider:getY()
    local r = e.slamRadius or 38
    local dx, dy = px - sx, py - sy
    if (dx * dx + dy * dy) <= (r * r) then
        dealDamageOnce(e, player)
    end
end

local function canStartAttack(e, player)
    if e.attackState ~= "idle" then
        return false
    end
    if (e.attackCooldownTimer or 0) > 0 then
        return false
    end
    local px, py = playerPos(player)
    if not px then
        return false
    end
    local ex, ey = e.collider:getX(), e.collider:getY()
    local dx, dy = px - ex, py - ey
    local dist = math.sqrt(dx * dx + dy * dy)
    local style = e.attackStyle or "lunge"

    if style == "shot" then
        local minD = e.minShotDistance or 90
        local maxD = e.maxShotDistance or 110
        if dist < minD - 8 or dist > maxD + 20 then
            return false
        end
        if dist > (e.attackRange or 170) then
            return false
        end
        return e:hasLineOfSight(px, py)
    end

    if style == "pounce" then
        return dist <= (e.attackRange or 58)
    end

    if style == "slam" then
        return dist <= (e.attackRange or 54)
    end

    -- lunge
    return dist <= (e.attackRange or 42)
end

--- Returns true when the attack owns locomotion this frame.
function enemy_attacks.update(e, dt, player)
    if not e or e.dead or e.dying or not e.collider then
        return false
    end

    -- Only tick re-attack cooldown while idle (armed at end of recovery).
    if e.attackState == "idle" then
        e.attackCooldownTimer = math.max(0, (e.attackCooldownTimer or 0) - dt)
        e.attackPhaseElapsed = 0
        if canStartAttack(e, player) then
            local label = ({
                lunge = "lunge-tele",
                pounce = "pounce-tele",
                slam = "slam-tele",
                shot = "shot-tele",
            })[e.attackStyle or "lunge"] or "telegraph"
            beginTelegraph(e, player, label)
            e:stop(dt)
            return true
        end
        return false
    end

    e.attackPhaseElapsed = (e.attackPhaseElapsed or 0) + dt
    if e.attackPhaseElapsed > attackBudget(e) then
        if not e._attackStuckLogged then
            e._attackStuckLogged = true
            print(string.format(
                "[attack] stuck %s in %s for %.2fs — force idle",
                e.enemyType or "enemy",
                tostring(e.attackState),
                e.attackPhaseElapsed
            ))
        end
        enemy_attacks.cancel(e)
        e.attackCooldownTimer = math.max(e.attackCooldownTimer or 0, e.attackPostGap or 0.4)
        e:stop(dt)
        return false
    end

    e.attackTimer = math.max(0, (e.attackTimer or 0) - dt)
    if e.attackState == "telegraph" then
        e.attackWindupTimer = e.attackTimer
        e.attackFlash = e.attackTimer
        e:stop(dt)
        if e.attackStyle == "slam" then
            e.slamX, e.slamY = e.collider:getX(), e.collider:getY()
        end
        if e.attackTimer <= 0 then
            beginStrike(e)
            if e.attackStyle == "shot" then
                spawnProjectile(e)
            elseif e.attackStyle == "slam" then
                resolveSlam(e, player)
            end
        end
        return true
    end

    if e.attackState == "strike" then
        if e.attackStyle == "lunge" then
            updateLungeStrike(e, dt, player)
        elseif e.attackStyle == "pounce" then
            updatePounceStrike(e, dt, player)
        else
            e:stop(dt)
        end
        e.attackFlash = math.max(0, e.attackFlash - dt)
        if e.attackTimer <= 0 then
            if e.attackStyle == "pounce" then
                e._fleeing = true
            end
            beginRecovery(e)
        end
        return true
    end

    if e.attackState == "recovery" then
        -- Stay still, but presentation is normal (no yellow). Then return to AI.
        e.attackFlash = 0
        e:stop(dt)
        if e.attackTimer <= 0 then
            finishToIdle(e)
            return false
        end
        return true
    end

    -- Unknown state — recover safely.
    enemy_attacks.cancel(e)
    return false
end

--- Draw slam circles + shot aim lines for every living enemy.
function enemy_attacks.drawAll(actors)
    for _, actor in ipairs(actors or {}) do
        if actor.label == "enemy" and not actor.dead then
            enemy_attacks.drawWorld(actor)
        end
    end
    enemy_attacks.drawProjectiles()
end

--- True if any living enemy is stuck past telegraph+strike+recovery+slack.
function enemy_attacks.anyStuck(actors)
    for _, actor in ipairs(actors or {}) do
        if actor.label == "enemy"
            and not actor.dead
            and not actor.dying
            and actor.attackState
            and actor.attackState ~= "idle"
            and (actor.attackPhaseElapsed or 0) > attackBudget(actor)
        then
            return true, actor
        end
    end
    return false, nil
end

function enemy_attacks.updateProjectiles(dt, player)
    if #projectiles == 0 then
        return
    end
    local px, py = playerPos(player)
    for i = #projectiles, 1, -1 do
        local p = projectiles[i]
        if not p.alive then
            table.remove(projectiles, i)
        else
            local nx = p.x + p.vx * dt
            local ny = p.y + p.vy * dt
            local blocked = false
            if physics.world then
                local hits = physics.world:queryLine(p.x, p.y, nx, ny, { "Wall" })
                if hits and #hits > 0 then
                    blocked = true
                end
            end
            if blocked then
                table.remove(projectiles, i)
            else
                p.x, p.y = nx, ny
                if not p.hit and px then
                    local dx, dy = px - p.x, py - p.y
                    local pr = p.r + 7
                    if dx * dx + dy * dy <= pr * pr then
                        p.hit = true
                        if player and player.onHitByEnemy and p.owner then
                            local owner = p.owner
                            if not owner.dead and not owner.dying then
                                local saved = owner.attackDamageSeconds
                                owner.attackDamageSeconds = p.damageSeconds
                                -- One damage event per projectile.
                                if not p.damageApplied then
                                    p.damageApplied = true
                                    player:onHitByEnemy(owner)
                                end
                                owner.attackDamageSeconds = saved
                            end
                        end
                        table.remove(projectiles, i)
                    end
                end
            end
        end
    end
end

function enemy_attacks.drawWorld(e)
    if not e or e.dead then
        return
    end
    if e.attackStyle == "slam"
        and (e.attackState == "telegraph" or e.attackState == "strike")
        and e.slamX
        and e.slamY
    then
        local r = e.slamRadius or 38
        local pulse = e.attackState == "telegraph"
            and (0.45 + 0.35 * math.sin((e.attackTimer or 0) * 18))
            or 0.85
        love.graphics.setColor(0.95, 0.25, 0.2, pulse * 0.35)
        love.graphics.circle("fill", e.slamX, e.slamY, r)
        love.graphics.setColor(0.95, 0.35, 0.25, pulse)
        love.graphics.setLineWidth(1.5)
        love.graphics.circle("line", e.slamX, e.slamY, r)
    end
    if e.attackStyle == "shot" and e.attackState == "telegraph" then
        local ex, ey = e.collider:getX(), e.collider:getY()
        love.graphics.setColor(0.85, 0.55, 0.95, 0.55)
        love.graphics.setLineWidth(1)
        love.graphics.line(
            ex,
            ey,
            ex + e.attackDirX * 40,
            ey + e.attackDirY * 40
        )
    end
end

function enemy_attacks.drawProjectiles()
    for _, p in ipairs(projectiles) do
        love.graphics.setColor(0.85, 0.45, 0.95, 0.95)
        love.graphics.circle("fill", p.x, p.y, p.r)
        love.graphics.setColor(1, 0.85, 1, 0.7)
        love.graphics.circle("line", p.x, p.y, p.r + 1)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function enemy_attacks.getStateLabel(e)
    if not e then
        return "—"
    end
    return e.attackLabel or e.attackState or "idle"
end

function enemy_attacks.expectedDamage(e)
    return (e and e.attackDamageSeconds) or 0
end

function enemy_attacks.projectileCount()
    return #projectiles
end

return enemy_attacks
