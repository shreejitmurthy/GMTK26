love.profiler = require "lib.profile"
require "scripts.dbg"

require "lib.spritesheet"
camera = require "lib.camera"

require "scripts.actor"
local physics = require "scripts.physics"
local countdown = require "scripts.countdown"
local game_map = require "scripts.game_map"
local atmosphere = require "scripts.atmosphere"
local nests = require "scripts.nests"
local collapse = require "scripts.collapse"
require "scripts.player"
require "scripts.sword"
require "scripts.slash_trail"
require "scripts.enemy"
local physics_selftest = require "scripts.physics_selftest"

local zoom = 3
ZOOM_MULT = 0.1
ZOOM_MAX = 2
ZOOM_MIN = 0.1

DEBUG = false

love.graphics.setDefaultFilter("nearest", "nearest")

GAME_STATE = {
    MAIN_MENU = 0,
    GAMEPLAY = 1,
    PAUSE_MENU = 2,
}

state = {
    actors = {},
    canvas = nil,
    gameState = GAME_STATE.GAMEPLAY,
    countdown = nil,
    extracted = false,
    sectorCleared = false,
    nests = nil,
    floats = {},
    hintTime = 4,
    hudTimerFont = nil,
    hudLabelFont = nil,
    hudHelpFont = nil,
    gameMap = nil,
    extractReason = nil,
}

function state.onAfterFloor()
    collapse.drawFloorFx()
end

function state.onAfterActors()
    collapse.drawFalling()
end

-- STATE
function state:init(...)
    self.canvas = love.graphics.newCanvas()
    local args = { ... }
    for _, actor in ipairs(args) do
        self.actors[#self.actors + 1] = actor
    end
end

function state:getActor(label)
    for _, actor in ipairs(self.actors) do
        if actor.label == label then
            return actor
        end
    end
    return nil
end

function state:pushFloat(text, x, y, r, g, b, life)
    self.floats[#self.floats + 1] = {
        text = text,
        x = x,
        y = y,
        r = r or 1,
        g = g or 1,
        b = b or 1,
        life = life or 0.9,
        maxLife = life or 0.9,
        world = true,
    }
end

function state:removeActor(target)
    for i = #self.actors, 1, -1 do
        if self.actors[i] == target then
            table.remove(self.actors, i)
            break
        end
    end
end

function state:onEnemyKilled(enemyActor)
    if self.extracted or self.sectorCleared or not self.countdown then
        self:removeActor(enemyActor)
        return
    end
    self.countdown:addTime(1)
    local px, py = enemyActor.pos.x, enemyActor.pos.y - 10
    local playerActor = self:getActor("player")
    if playerActor then
        px, py = playerActor.pos.x, playerActor.pos.y - 14
    end
    self:pushFloat("+1s", px, py, 0.45, 0.95, 0.55, 0.85)
    print(string.format(
        "[countdown] +1s from kill → %.1fs left",
        self.countdown:getRemaining()
    ))
    self:removeActor(enemyActor)
end

function state:onNestCleansed(nest)
    local col = nests.color(nest.id)
    self:pushFloat("NEST SEALED", nest.x, nest.y - 18, col[1], col[2], col[3], 1.1)
    atmosphere.notifyNestCleansed(nest)
    print(string.format(
        "[nest] nest_%s sealed (%d/3)",
        nest.id,
        nests.countCleansed(self.nests)
    ))
end

function state:onSectorCleared()
    print(string.format(
        "[nest] SECTOR CLEANSED — %.1fs remaining",
        self.countdown and self.countdown:getRemaining() or 0
    ))
end

--- Single gameplay entry for plague damage (timer = health).
--- opts.bypassIFrames: debug key may ignore invuln for testing.
--- Returns ok, remainingSeconds.
function state:applyPlayerDamage(amount, source, opts)
    opts = opts or {}
    if self.extracted or self.sectorCleared or not self.countdown then
        return false, 0
    end

    local playerActor = self:getActor("player")
    if not opts.bypassIFrames
        and playerActor
        and (playerActor.hurtIFrame or 0) > 0
    then
        return false, self.countdown:getRemaining()
    end

    amount = amount or 0
    self.countdown:damage(amount)

    if playerActor and not opts.bypassIFrames then
        playerActor.hurtIFrame = playerActor.hurtIFrameDuration or player.HURT_IFRAME
    end

    if self.countdown:isExpired() then
        self.extracted = true
        self.countdown:pause()
        print("[countdown] EXTRACTED — plague time exhausted")
    end

    return true, self.countdown:getRemaining()
end

-- Frame order during gameplay:
--   1) actors setLinearVelocity / sync sensors (no manual pos writes)
--   2) physics.world:update(dt)
--   3) poll PlayerAttack :enter("EnemyHit") hit logs
--   4) actors sync visual pos from collider:getX/Y
--   5) camera follows synced player pos
function state:update(dt)
    if state.gameState == GAME_STATE.GAMEPLAY then
        if self.gameMap then
            game_map.update(self.gameMap, dt)
        end

        local playerActor = self:getActor("player")
        local frozen = self.extracted or self.sectorCleared

        -- Timer-as-health: always update (pulse decays even after extract/clear).
        if self.countdown then
            self.countdown:update(dt)
            if not frozen and self.countdown:isExpired() then
                self.extracted = true
                frozen = true
                self.countdown:pause()
                print("[countdown] EXTRACTED — plague time exhausted")
            end
        end

        local ratio = self.countdown and self.countdown:getRatio() or 1
        atmosphere.update(dt, ratio, self.nests)

        if self.hintTime and self.hintTime > 0 then
            self.hintTime = math.max(0, self.hintTime - dt)
        end

        for i = #self.floats, 1, -1 do
            local f = self.floats[i]
            f.life = f.life - dt
            f.y = f.y - 18 * dt
            if f.life <= 0 then
                table.remove(self.floats, i)
            end
        end

        if not frozen then
            nests.update(self, dt)
            collapse.update(dt, self)
            frozen = self.extracted or self.sectorCleared
            for _, actor in ipairs(self.actors) do
                if actor.label == "enemy" and not actor.dead then
                    actor:update(dt, playerActor)
                elseif actor.label ~= "enemy" then
                    actor:update(dt)
                end
            end
        elseif playerActor and playerActor.collider then
            playerActor.collider:setLinearVelocity(0, 0)
            for _, actor in ipairs(self.actors) do
                if actor.label == "enemy" and actor.collider then
                    actor.collider:setLinearVelocity(0, 0)
                    if actor.dying and actor.updateDeath then
                        actor:updateDeath(dt)
                    end
                end
            end
        end

        -- Finalize faded enemies after iteration; removal cannot skip another actor.
        for i = #self.actors, 1, -1 do
            local actor = self.actors[i]
            if actor.label == "enemy"
                and actor.readyForRemoval
                and actor.finishDeath
            then
                actor:finishDeath()
            end
        end

        physics.update(dt)
        physics.clampAllEnemiesToPlayable()
        if playerActor and playerActor.collider then
            physics.clampColliderToPlayable(playerActor.collider)
        end

        if not frozen and playerActor and playerActor.pollAttackHits then
            playerActor:pollAttackHits()
        end

        -- Sword / trails sync from the player pose — they have no collider.
        for _, actor in ipairs(self.actors) do
            if actor.syncFromCollider then
                actor:syncFromCollider(dt)
            end
        end

        if playerActor and cam then
            local rx, ry = collapse.getRumble()
            cam:lookAt(playerActor.pos.x + rx, playerActor.pos.y + ry)
        end
    end
end

function state:drawActors(perspectiveBoundary, drawInFront)
    local drawList = {}
    for index, sceneActor in ipairs(self.actors) do
        local depth = index
        if sceneActor.getDrawDepth then
            depth = sceneActor:getDrawDepth()
        elseif sceneActor.pos then
            depth = sceneActor.pos.y
        end

        local groundDepth = depth
        if sceneActor.getGroundDepth then
            groundDepth = sceneActor:getGroundDepth()
        elseif sceneActor.owner and sceneActor.owner.getGroundDepth then
            -- Sword and trail actors cross scenery with their player owner.
            groundDepth = sceneActor.owner:getGroundDepth()
        end

        local isInFront = perspectiveBoundary
            and groundDepth >= perspectiveBoundary
        if perspectiveBoundary == nil or isInFront == drawInFront then
            drawList[#drawList + 1] = {
                actor = sceneActor,
                -- Keep the complete player/sword stack above enemies. Sword,
                -- player, and trail ordering still comes from their depth values.
                layer = sceneActor.label == "enemy" and 0 or 1,
                depth = depth,
                index = index,
            }
        end
    end

    table.sort(drawList, function(a, b)
        if a.layer ~= b.layer then
            return a.layer < b.layer
        end
        if a.depth == b.depth then
            return a.index < b.index
        end
        return a.depth < b.depth
    end)

    for _, item in ipairs(drawList) do
        item.actor:draw()
    end
end

--- Soft edge tint when plague tolerance is nearly spent (ratio < 0.15).
local function drawPlagueEdgeTint(sw, sh, strength)
    if strength <= 0 then
        return
    end
    local edge = math.floor(math.min(sw, sh) * 0.12)
    local layers = 5
    for i = 0, layers - 1 do
        local t = i / layers
        local band = edge / layers
        local a = 0.07 * strength * (1 - t)
        love.graphics.setColor(0.55, 0.08, 0.06, a)
        love.graphics.rectangle("fill", 0, i * band, sw, band)
        love.graphics.rectangle("fill", 0, sh - (i + 1) * band, sw, band)
        love.graphics.rectangle("fill", i * band, edge, band, sh - 2 * edge)
        love.graphics.rectangle("fill", sw - (i + 1) * band, edge, band, sh - 2 * edge)
    end
end

function state:drawHud()
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local prevFont = love.graphics.getFont()

    -- Hero HUD: plague timer (health) top-center ΓÇö dominant readout.
    if self.countdown then
        local ratio = self.countdown:getRatio()
        local dmgPulse, dmgAmount = self.countdown:getDamagePulse()

        if ratio < 0.15 and not self.extracted then
            local urgency = 1 - (ratio / 0.15)
            drawPlagueEdgeTint(sw, sh, urgency)
        end

        local r, g, b, a = 0.96, 0.90, 0.78, 1
        if ratio < 0.25 then
            local t = 1 - (ratio / 0.25)
            r = 0.96 + 0.04 * t
            g = 0.90 - 0.55 * t
            b = 0.78 - 0.65 * t
        end
        -- Damage flash: brief white ΓåÆ red over the digits + fuse.
        if dmgPulse > 0 then
            local flash = dmgPulse
            r = r + (1.0 - r) * flash * 0.85
            g = g + (0.25 - g) * flash
            b = b + (0.20 - b) * flash
            a = 1
        end

        local scale = 1
        if ratio < 0.1 and not self.extracted and dmgPulse <= 0 then
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 6)
            a = 0.65 + 0.35 * pulse
            scale = 1 + 0.04 * pulse
        elseif dmgPulse > 0 then
            scale = 1 + 0.06 * dmgPulse
        end

        local timerFont = self.hudTimerFont or prevFont
        local labelFont = self.hudLabelFont or prevFont
        love.graphics.setFont(timerFont)

        local text = self.countdown:format()
        local tw = timerFont:getWidth(text)
        local th = timerFont:getHeight()
        local cx = sw / 2
        local cy = 22

        love.graphics.push()
        love.graphics.translate(cx, cy)
        love.graphics.scale(scale, scale)
        love.graphics.setColor(0, 0, 0, 0.5 * a)
        love.graphics.print(text, -tw / 2 + 2, 2)
        love.graphics.setColor(r, g, b, a)
        love.graphics.print(text, -tw / 2, 0)
        love.graphics.pop()

        -- Fuse track: same resource as the clock (width = getRatio()), not a heart bar.
        local fuseW = 220
        local fuseH = 5
        local fuseX = cx - fuseW / 2
        local fuseY = cy + th * 0.92
        local filled = fuseW * ratio
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.rectangle("fill", fuseX - 1, fuseY - 1, fuseW + 2, fuseH + 2)
        love.graphics.setColor(r * 0.35, g * 0.28, b * 0.22, 0.7)
        love.graphics.rectangle("fill", fuseX, fuseY, fuseW, fuseH)
        if filled > 0 then
            love.graphics.setColor(r, g, b, 0.9 * a)
            love.graphics.rectangle("fill", fuseX, fuseY, filled, fuseH)
        end
        -- Segment ticks ΓåÆ timer/fuse metaphor (not a solid HP chunk bar).
        local segments = 6
        love.graphics.setColor(0.12, 0.08, 0.06, 0.55)
        for i = 1, segments - 1 do
            local tx = fuseX + (fuseW / segments) * i
            love.graphics.rectangle("fill", tx, fuseY - 1, 1, fuseH + 2)
        end

        love.graphics.setFont(labelFont)
        -- Title case reads cleaner in roundhand than all-caps.
        local label = "Plague Tolerance"
        local lw = labelFont:getWidth(label)
        love.graphics.setColor(r, g, b, 0.55 * a)
        love.graphics.print(label, cx - lw / 2, fuseY + fuseH + 4)

        -- Floating damage / heal readout near the timer.
        if dmgPulse > 0 and dmgAmount > 0 then
            love.graphics.setFont(labelFont)
            local floatText = string.format("-%.0fs", dmgAmount)
            local rise = (1 - dmgPulse) * 18
            love.graphics.setColor(1, 0.35, 0.28, dmgPulse)
            love.graphics.print(floatText, cx + tw * 0.42 * scale, cy + 4 - rise)
        end
        local healPulse, healAmount = self.countdown:getHealPulse()
        if healPulse > 0 and healAmount > 0 then
            love.graphics.setFont(labelFont)
            local floatText = string.format("+%.0fs", healAmount)
            local rise = (1 - healPulse) * 18
            love.graphics.setColor(0.45, 0.95, 0.55, healPulse)
            love.graphics.print(floatText, cx - tw * 0.55 * scale, cy + 4 - rise)
        end

        -- Nest cleanse pips under Plague Tolerance.
        local nestY = fuseY + fuseH + 28
        local cleansedCount = nests.countCleansed(self.nests)
        local nestLabel = string.format("NESTS %d/3", cleansedCount)
        love.graphics.setFont(labelFont)
        local nlw = labelFont:getWidth(nestLabel)
        love.graphics.setColor(0.9, 0.86, 0.78, 0.7)
        love.graphics.print(nestLabel, cx - nlw / 2, nestY)

        local pipR = 7
        local pipGap = 22
        local pipStart = cx - pipGap
        for i, id in ipairs(nests.order()) do
            local nest = self.nests and self.nests[i]
            local col = nests.color(id)
            local px = pipStart + (i - 1) * pipGap
            local py = nestY + 28
            if nest and nest.cleansed then
                love.graphics.setColor(col[1], col[2], col[3], 0.95)
                love.graphics.circle("fill", px, py, pipR)
            else
                love.graphics.setColor(col[1], col[2], col[3], 0.25)
                love.graphics.circle("line", px, py, pipR)
                if nest and nest.channeling and nest.progress > 0 then
                    love.graphics.setColor(col[1], col[2], col[3], 0.7)
                    love.graphics.arc(
                        "fill",
                        px,
                        py,
                        pipR - 1,
                        -math.pi / 2,
                        -math.pi / 2 + nest.progress * math.pi * 2,
                        16
                    )
                end
            end
        end
    end

    if self.hintTime and self.hintTime > 0 and not self.extracted and not self.sectorCleared then
        local alpha = math.min(1, self.hintTime / 1.2)
        if self.hintTime > 3 then
            alpha = math.min(1, (4 - self.hintTime) / 0.5)
        end
        love.graphics.setFont(self.hudHelpFont or prevFont)
        love.graphics.setColor(0.92, 0.88, 0.78, 0.85 * alpha)
        love.graphics.printf(
            "Your time is your life — seal the three nests.",
            0,
            sh * 0.18,
            sw,
            "center"
        )
    end

    -- Hold-E prompt only when standing in an uncleansed nest (not while walking past).
    local promptNest = nests.promptNest(self.nests)
    if promptNest and not self.extracted and not self.sectorCleared then
        love.graphics.setFont(self.hudHelpFont or prevFont)
        love.graphics.setColor(0.92, 0.88, 0.78, 0.8)
        love.graphics.printf("Hold E to cleanse", 0, sh * 0.78, sw, "center")
    end

    if self.sectorCleared then
        local msg = "SECTOR CLEANSED"
        if self.hudTimerFont then
            love.graphics.setFont(self.hudTimerFont)
        end
        local tw = love.graphics.getFont():getWidth(msg)
        local th = love.graphics.getFont():getHeight()
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 0, sh / 2 - th, sw, th * 2.8)
        love.graphics.setColor(0.75, 0.92, 0.7, 1)
        love.graphics.print(msg, (sw - tw) / 2, sh / 2 - th / 2)
        love.graphics.setColor(0.95, 0.9, 0.78, 0.9)
        love.graphics.setFont(self.hudLabelFont or prevFont)
        local left = self.countdown and self.countdown:format() or "0"
        love.graphics.printf(
            "Time remaining  " .. left,
            0,
            sh / 2 + th * 0.55,
            sw,
            "center"
        )
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.setFont(self.hudHelpFont or prevFont)
        love.graphics.printf("Esc to quit", 0, sh / 2 + th * 1.15, sw, "center")
    elseif self.extracted then
        local msg = "EXTRACTED"
        if self.hudTimerFont then
            love.graphics.setFont(self.hudTimerFont)
        end
        local tw = love.graphics.getFont():getWidth(msg)
        local th = love.graphics.getFont():getHeight()
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 0, sh / 2 - th, sw, th * 2.8)
        love.graphics.setColor(0.95, 0.85, 0.7, 1)
        love.graphics.print(msg, (sw - tw) / 2, sh / 2 - th / 2)
        love.graphics.setColor(0.9, 0.7, 0.55, 0.9)
        love.graphics.setFont(self.hudLabelFont or prevFont)
        local subtitle = self.extractReason == "abyss"
            and "The courtyard gave way beneath you"
            or string.format("Nests remaining: %d", nests.remaining(self.nests))
        love.graphics.printf(
            subtitle,
            0,
            sh / 2 + th * 0.55,
            sw,
            "center"
        )
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.setFont(self.hudHelpFont or prevFont)
        love.graphics.printf("Esc to quit", 0, sh / 2 + th * 1.15, sw, "center")
    end

    local playerActor = self:getActor("player")
    if not playerActor then
        love.graphics.setFont(prevFont)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    -- Secondary help: smaller, dimmer, bottom-left ΓÇö must not compete with timer.
    local helpFont = self.hudHelpFont or prevFont
    love.graphics.setFont(helpFont)
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.print(
        string.format("pos %.0f, %.0f", playerActor.pos.x, playerActor.pos.y),
        10,
        sh - 40
    )
    love.graphics.print(
        "WASD · Space swing · Hold E cleanse · V crack test · H/G time · Esc",
        10,
        sh - 24
    )

    if physics.debug then
        love.graphics.setColor(1, 1, 1, 0.7)
        local vx, vy = playerActor:getVelocity()
        local speed = playerActor:getSpeed()
        love.graphics.print(
            string.format(
                "DEBUG | col %.0f,%.0f |v| %.2f",
                playerActor.collider:getX(),
                playerActor.collider:getY(),
                speed
            ),
            10,
            sh - 56
        )

        local counts = { chaser = 0, fleer = 0, keeper = 0, ranger = 0 }
        local nearest = nil
        local px, py = playerActor.pos.x, playerActor.pos.y
        for _, actor in ipairs(self.actors) do
            if actor.label == "enemy" then
                local t = actor.enemyType
                if counts[t] ~= nil then
                    counts[t] = counts[t] + 1
                end
                local dx, dy = actor.pos.x - px, actor.pos.y - py
                local d = math.sqrt(dx * dx + dy * dy)
                if not nearest or d < nearest then
                    nearest = d
                end
            end
        end
        love.graphics.print(
            string.format(
                "C:%d F:%d K:%d R:%d near %s",
                counts.chaser,
                counts.fleer,
                counts.keeper,
                counts.ranger,
                nearest and string.format("%.0f", nearest) or "-"
            ),
            10,
            sh - 72
        )
    end

    love.graphics.setFont(prevFont)
    love.graphics.setColor(1, 1, 1, 1)
end

local function loadScriptFont(size)
    -- Italianno: copperplate / roundhand cursive (18thΓÇô19th c. feel). OFL.
    local font = love.graphics.newFont("res/fonts/Italianno-Regular.ttf", size)
    font:setFilter("linear", "linear")
    return font
end

local function argvHas(argv, flag)
    for _, value in ipairs(argv or {}) do
        if value == flag then
            return true
        end
    end
    return false
end

function love.load(args)
    local argv = args or arg or {}

    -- Courtyard art reset (cobble floor + dungeon_tiles districts; fountain kept):
    --   love . -- --patch-nests
    if argvHas(argv, "--patch-nests") then
        local patcher = require "scripts.map_patch_nests"
        local map, luaPath, tmxPath = patcher.write("res/maps/map.lua", "res/maps/map.tmx")
        local empty = patcher.countEmptyFloor(map)
        print("[map_patch] wrote " .. tostring(luaPath))
        print("[map_patch] wrote " .. tostring(tmxPath))
        print(string.format("[map_patch] Floor Layer empty cells: %d (want 0)", empty))
        love.event.quit()
        return
    end

    physics.init()

    state.gameMap = game_map.load("res/maps/map.lua")
    state.nests = nests.fromMap(state.gameMap)
    state.sectorCleared = false
    state.extracted = false
    state.extractReason = nil
    state.floats = {}
    state.hintTime = 4
    atmosphere.load(state.nests)
    collapse.load(state.gameMap, state.nests)
    local playable = game_map.getPlayableArea(state.gameMap)
    physics.setPlayableArea(
        playable.x,
        playable.y,
        playable.w,
        playable.h,
        playable.thickness
    )
    -- Outer Wall rim (player is dynamic and only stops on Wall). Map objects alone
    -- are fountain/props — without this the player walks off the tiled courtyard.
    local boundaryCount = physics.addBoundaryWalls(
        playable.x,
        playable.y,
        playable.w,
        playable.h,
        playable.thickness
    )
    local mapColliderCount = game_map.addColliders(state.gameMap, physics)
    print(string.format(
        "[map] loaded res/maps/map.lua (%d colliders + %d boundary)",
        mapColliderCount,
        boundaryCount
    ))

    -- Plague resistance window (seconds). Timer IS health.
    state.countdown = countdown.new({ duration = 90 })
    state.extracted = false
    state.hudTimerFont = loadScriptFont(72)
    state.hudLabelFont = loadScriptFont(26)
    state.hudHelpFont = loadScriptFont(20)
    love.graphics.setFont(state.hudHelpFont)

    local spawnData = game_map.getSpawnPoints(state.gameMap)
    local spawnX, spawnY = game_map.getPlayerStart(state.gameMap)
    if not spawnX then
        spawnX, spawnY = 200, 150
        print("[map] warning: missing player_start; using plaza fallback")
    end

    local playerActor = player:new(spawnX, spawnY)
    local swordActor = sword:new(playerActor)
    local trailBehind = slashTrail:new(playerActor, true)
    local trailFront = slashTrail:new(playerActor, false)

    local enemies = {}
    for _, point in ipairs(spawnData.enemies) do
        local e = enemy:new(point.x, point.y, { type = point.type })
        e.nest = point.nest
        enemies[#enemies + 1] = e
    end
    if #enemies == 0 then
        enemies = {
            enemy:new(120, 100, { type = "chaser" }),
            enemy:new(280, 100, { type = "chaser" }),
            enemy:new(120, 200, { type = "fleer" }),
            enemy:new(315, 120, { type = "keeper" }),
            enemy:new(280, 200, { type = "ranger" }),
        }
        print("[map] warning: no Spawns enemies; using plaza fallbacks")
    end

    cam = camera(playerActor.pos.x, playerActor.pos.y, zoom)

    -- Sword and its split ribbon layers are separate coordinated scene actors.
    state:init(playerActor, swordActor, trailBehind, trailFront, unpack(enemies))

    -- Combat → countdown: player hits call into state (keeps drain logic centralized).
    playerActor.applyDamage = function(amount, source, opts)
        return state:applyPlayerDamage(amount, source, opts)
    end

    physics_selftest.run(playerActor, enemies)

    if argvHas(argv, "--selftest-quit") then
        love.event.quit()
    end
end

function love.update(dt)
    state:update(dt)
end

function love.draw()
    -- Near-black clear — map must fully cover playable cells (no grey voids).
    love.graphics.setBackgroundColor(0.04, 0.04, 0.05)

    cam:attach()
    -- Perspective order: behind the fountain from above, in front from below.
    -- Body, sword, and trails move across the scenery layer as one stack.
    game_map.drawWithActors(state.gameMap, state.drawActors, state)
    atmosphere.drawWorld()
    -- World-space float juice (+1s / NEST SEALED).
    if state.hudLabelFont then
        love.graphics.setFont(state.hudLabelFont)
    end
    for _, f in ipairs(state.floats or {}) do
        if f.world then
            local a = math.max(0, f.life / f.maxLife)
            love.graphics.setColor(f.r, f.g, f.b, a)
            local tw = love.graphics.getFont():getWidth(f.text)
            love.graphics.print(f.text, f.x - tw / 2, f.y)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    physics.drawDebug()
    cam:detach()

    atmosphere.drawGrade()
    state:drawHud()
end

local function startPlayerSwingAt(screenX, screenY)
    local playerActor = state:getActor("player")
    if not playerActor or not playerActor.startSwing then
        return
    end

    local worldX, worldY = screenX, screenY
    if cam then
        worldX, worldY = cam:worldCoords(screenX, screenY)
    end
    playerActor:startSwing(worldX, worldY)
end

function love.keypressed(k)
    if k == "escape" then
        love.event.quit()
    elseif k == "f1" or k == "`" then
        local on = physics.toggleDebug()
        DEBUG = on
        print("[physics] debug draw: " .. (on and "ON" or "OFF"))
    elseif k == "f2" then
        local enemies = {}
        for _, actor in ipairs(state.actors) do
            if actor.label == "enemy" then
                enemies[#enemies + 1] = actor
            end
        end
        physics_selftest.run(state:getActor("player"), enemies)
    elseif k == "h" then
        -- Debug plague damage (bypasses i-frames for tuning).
        local ok, left = state:applyPlayerDamage(3, "debug", { bypassIFrames = true })
        if ok then
            print(string.format("[countdown] damage 3.0 → %.1fs left", left))
        end
    elseif k == "g" then
        if state.countdown and not state.extracted then
            state.countdown:addTime(5)
            print(string.format("[countdown] +5s → %.1fs left", state.countdown:getRemaining()))
        end
    elseif k == "v" then
        if not state.extracted and not state.sectorCleared then
            collapse.debugCrackNearPlayer(state)
        end
    elseif k == "space" then
        if not state.extracted and not state.sectorCleared then
            startPlayerSwingAt(love.mouse.getPosition())
        end
    end
end

function love.mousepressed(x, y, button)
    if button == 1 and not state.extracted and not state.sectorCleared then
        startPlayerSwingAt(x, y)
    end
end
