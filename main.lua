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
local encounter_director = require "scripts.encounter_director"
local enemy_test = require "scripts.enemy_test"
local enemy_attacks = require "scripts.enemy_attacks"
local game_flow = require "scripts.game_flow"
local sound_effects = require "scripts.sound_effects"
local plague_senses = require "scripts.plague_senses"
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

--- Cached DCSS potion tiles for a compact top HUD (~22px tall).
local hudVialImages = {}
local HUD_PAD = 8
local HUD_GAP = 8
local HUD_VIAL_SCALE = 0.7 -- 32px tile → ~22px; timer stays the hero

local function ensureHudVials()
    if next(hudVialImages) then
        return
    end
    local files = {
        a = "res/images/nests/vial_a.png",
        b = "res/images/nests/vial_b.png",
        c = "res/images/nests/vial_c.png",
        well = "res/images/nests/vial_well.png",
        empty = "res/images/nests/vial_empty.png",
    }
    for key, path in pairs(files) do
        local ok, img = pcall(love.graphics.newImage, path)
        if ok and img then
            img:setFilter("nearest", "nearest")
            hudVialImages[key] = img
        end
    end
end

local function drawHudVial(id, x, y, scale, nest)
    local live = nest and not nest.cleansed
    local locked = live and nest.locked
    local open = live and nest.isWell and not nest.locked
    local img = live and hudVialImages[id] or hudVialImages.empty
    if not img and live then
        img = hudVialImages.a
    end
    local col = nests.color(id)
    if img then
        local iw, ih = img:getWidth(), img:getHeight()
        if locked then
            love.graphics.setColor(0.7, 0.7, 0.74, 0.95)
        elseif open then
            local pulse = 0.85 + 0.15 * math.abs(math.sin(love.timer.getTime() * 3.5))
            love.graphics.setColor(1, 1, 1, pulse)
        elseif live then
            love.graphics.setColor(1, 1, 1, 1)
        else
            love.graphics.setColor(0.86, 0.86, 0.8, 0.88)
        end
        love.graphics.draw(img, x, y, 0, scale, scale, iw * 0.5, ih * 0.55)
    else
        love.graphics.setColor(col[1], col[2], col[3], live and 0.9 or 0.35)
        love.graphics.circle(live and "fill" or "line", x, y, 7)
    end
    if locked then
        local prev = love.graphics.getLineWidth()
        love.graphics.setLineWidth(1.4)
        local half = 9 * scale
        love.graphics.setColor(0.72, 0.6, 0.32, 0.9)
        love.graphics.rectangle("line", x - half, y - half - 1, half * 2, half * 2 + 2)
        love.graphics.line(x - half * 0.5, y - half, x - half * 0.5, y + half)
        love.graphics.line(x + half * 0.5, y - half, x + half * 0.5, y + half)
        love.graphics.line(x - half * 0.7, y, x + half * 0.7, y)
        love.graphics.setLineWidth(prev)
    elseif not live then
        local prev = love.graphics.getLineWidth()
        love.graphics.setLineWidth(1.6)
        love.graphics.setColor(0.55, 0.75, 0.45, 0.85)
        love.graphics.line(x - 4, y + 1, x - 1, y + 4, x + 5, y - 4)
        love.graphics.setLineWidth(prev)
    elseif nest and nest.channeling and nest.progress and nest.progress > 0 then
        local prev = love.graphics.getLineWidth()
        love.graphics.setLineWidth(1.5)
        love.graphics.setColor(col[1], col[2], col[3], 0.85)
        love.graphics.arc(
            "line",
            "open",
            x,
            y,
            10 * scale,
            -math.pi / 2,
            -math.pi / 2 + nest.progress * math.pi * 2,
            16
        )
        love.graphics.setLineWidth(prev)
    end
end

GAME_STATE = {
    TITLE = 0,
    NARRATIVE = 1,
    GAMEPLAY = 2,
    PAUSE = 3,
}

state = {
    actors = {},
    canvas = nil,
    gameState = GAME_STATE.TITLE,
    countdown = nil,
    extracted = false,
    sectorCleared = false,
    nests = nil,
    floats = {},
    hintTime = 4,
    hudTimerFont = nil,
    hudTitleFont = nil,
    hudLabelFont = nil,
    hudHelpFont = nil,
    hudBodyFont = nil,
    hudSmallFont = nil,
    hudSubtitleFont = nil,
    gameMap = nil,
    extractReason = nil,
    enemyTestMode = false,
    winPresenting = false,
    winReady = false,
    winTimer = 0,
    lastFrameDt = 0,
    plagueSenseIntensity = 0,
}

function state.onAfterFloor()
    collapse.drawFloorFx()
end

function state.onAfterActors()
    collapse.drawFalling()
    collapse.drawFallenOverlay()
end

-- STATE
function state:init(...)
    if not self.canvas then
        self.canvas = love.graphics.newCanvas()
    end
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
    local reward = enemyActor.killRewardSeconds
        or encounter_director.timeRewardFor(enemyActor.enemyType)
    self.countdown:addTime(reward)
    local px, py = enemyActor.pos.x, enemyActor.pos.y - 10
    local playerActor = self:getActor("player")
    if playerActor then
        px, py = playerActor.pos.x, playerActor.pos.y - 14
    end
    local label = string.format("+%.1fs", reward)
    self:pushFloat(label, px, py, 0.45, 0.95, 0.55, 0.85)
    print(string.format(
        "[countdown] %s from %s kill → %.1fs left",
        label,
        enemyActor.enemyType or "enemy",
        self.countdown:getRemaining()
    ))
    self:removeActor(enemyActor)
end

function state:onNestCleansed(nest)
    local col = nests.color(nest.id)
    local label = nests.isWell(nest) and "WELL CLEANSED" or "POTION COLLECTED"
    local fx, fy = nest.x, nest.y
    if nests.isWell(nest) then
        fx, fy = 15 * 16, 12 * 16
    end
    self:pushFloat(label, fx, fy - 18, col[1], col[2], col[3], 1.1)
    atmosphere.notifyNestCleansed(nest)
    encounter_director.onNestCleansed(nest)
    if nests.isWell(nest) then
        print(string.format(
            "[nest] Plague Well cleansed — sector clear (%.0f seals)",
            nests.countCleansed(self.nests)
        ))
    else
        print(string.format(
            "[nest] nest_%s sealed (districts %d/3)",
            nest.id,
            nests.countDistrictCleansed(self.nests)
        ))
    end
end

--- Fired when district nests hit 3/3 — unlocks the fountain well (not a win).
function state:onWellUnlocked()
    local fx, fy = 15 * 16, 12 * 16
    self:pushFloat("THE WELL AWAKENS", fx, fy - 28, 0.45, 0.85, 0.4, 1.6)
    atmosphere.notifyWellUnlocked()
    if encounter_director.onWellUnlocked then
        encounter_director.onWellUnlocked(self)
    end
    sound_effects.playWellUnlock()
    print("[nest] THE WELL AWAKENS — Hold E at the fountain")
end

function state:onSectorCleared()
    print(string.format(
        "[nest] SECTOR CLEANSED — %.1fs remaining",
        self.countdown and self.countdown:getRemaining() or 0
    ))
    game_flow.beginWinPresentation(self)
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
        self.extractReason = "time"
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
    self.lastFrameDt = dt
    if self.gameState == GAME_STATE.TITLE
        or self.gameState == GAME_STATE.NARRATIVE
    then
        atmosphere.update(dt, 1, self.nests)
        return
    end
    if self.gameState == GAME_STATE.PAUSE then
        return
    end

    if state.gameState == GAME_STATE.GAMEPLAY then
        if self.gameMap then
            game_map.update(self.gameMap, dt)
        end

        local playerActor = self:getActor("player")
        local frozen = self.extracted or self.sectorCleared
        if self.sectorCleared then
            game_flow.updateWin(self, dt)
        end

        -- Timer-as-health: always update (pulse decays even after extract/clear).
        if self.countdown then
            self.countdown:update(dt)
            if not frozen and self.countdown:isExpired() then
                self.extracted = true
                self.extractReason = "time"
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
            if not self.enemyTestMode then
                nests.update(self, dt)
                collapse.update(dt, self)
                encounter_director.update(self, dt)
            end
            frozen = self.extracted or self.sectorCleared
            for _, actor in ipairs(self.actors) do
                if actor.label == "enemy" and not actor.dead then
                    actor:update(dt, playerActor)
                elseif actor.label ~= "enemy" then
                    actor:update(dt)
                end
            end
            enemy_attacks.updateProjectiles(dt, playerActor)
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

        -- Freeze the sim on EXTRACTED / clear — further world steps cause camera jitter
        -- (soft contact / clamps micro-nudging the player while lookAt follows).
        if not frozen then
            physics.update(dt)
            physics.clampAllEnemiesToPlayable()
            if playerActor and playerActor.collider then
                physics.clampColliderToPlayable(playerActor.collider)
            end

            if playerActor and playerActor.pollAttackHits then
                playerActor:pollAttackHits()
            end

            for _, actor in ipairs(self.actors) do
                if actor.syncFromCollider then
                    actor:syncFromCollider(dt)
                end
            end

            if playerActor and cam then
                local sx, sy = atmosphere.getChannelShake()
                cam:lookAt(playerActor.pos.x + sx, playerActor.pos.y + sy)
                self._freezeCamX = nil
                self._freezeCamY = nil
            end
        elseif cam then
            if self.sectorCleared then
                local fx, fy = game_flow.fountainFocus()
                self._freezeCamX = fx
                self._freezeCamY = fy
            elseif playerActor and not self._freezeCamX then
                self._freezeCamX = playerActor.pos.x
                self._freezeCamY = playerActor.pos.y
            end
            if self._freezeCamX then
                cam:lookAt(self._freezeCamX, self._freezeCamY)
            end
        end
    end
end

function state:updateSoundEffects(dt)
    local playerActor = self:getActor("player")
    local active = self.gameState == GAME_STATE.GAMEPLAY
        and not self.extracted
        and not self.sectorCleared
    local walking = false

    if active
        and playerActor
        and playerActor.collider
        and not playerActor.isDashing
    then
        walking = playerActor.hasMovementInput == true
    end

    local sensoryActive = self.countdown
        and (
            self.gameState == GAME_STATE.GAMEPLAY
            or self.gameState == GAME_STATE.PAUSE
        )
        and not self.sectorCleared
    local targetIntensity = 0
    if sensoryActive then
        targetIntensity = plague_senses.getTargetIntensity(
            self.countdown:getRemaining()
        )
    end
    self.plagueSenseIntensity = plague_senses.approach(
        self.plagueSenseIntensity,
        targetIntensity,
        dt
    )

    sound_effects.update(dt, {
        active = active,
        dead = self.extracted,
        walking = walking,
        remaining = self.countdown and self.countdown:getRemaining() or nil,
        plagueIntensity = self.plagueSenseIntensity,
    })
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

function state:drawHud()
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local prevFont = love.graphics.getFont()

    -- Hero HUD: plague timer (health) top-center. Hidden once end cards take over.
    local endCardUp = self.extracted
        or (self.sectorCleared and self.winReady)
        or (
            self.sectorCleared
            and self.winPresenting
            and (self.winTimer or 0) >= 2.5
        )
    if self.countdown and not endCardUp then
        local ratio = self.countdown:getRatio()
        local dmgPulse, dmgAmount = self.countdown:getDamagePulse()

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
        local labelFont = self.hudSmallFont or self.hudHelpFont or prevFont
        love.graphics.setFont(timerFont)

        local text = self.countdown:format()
        local tw = timerFont:getWidth(text)
        local th = timerFont:getHeight()
        local cx = sw / 2
        -- Italianno getHeight() is taller than the visible glyphs; stack with
        -- measured cursors so labels / plate / hints never collide.
        local timerY = 14
        local stackY = timerY + th * 0.58

        love.graphics.push()
        love.graphics.translate(cx, timerY)
        love.graphics.scale(scale, scale)
        love.graphics.setColor(0, 0, 0, 0.5 * a)
        love.graphics.print(text, -tw / 2 + 2, 2)
        love.graphics.setColor(r, g, b, a)
        love.graphics.print(text, -tw / 2, 0)
        love.graphics.pop()

        local fuseW = 200
        local fuseH = 4
        local fuseX = cx - fuseW / 2
        local fuseY = stackY
        local filled = fuseW * ratio
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.rectangle("fill", fuseX - 1, fuseY - 1, fuseW + 2, fuseH + 2)
        love.graphics.setColor(r * 0.35, g * 0.28, b * 0.22, 0.7)
        love.graphics.rectangle("fill", fuseX, fuseY, fuseW, fuseH)
        if filled > 0 then
            love.graphics.setColor(r, g, b, 0.9 * a)
            love.graphics.rectangle("fill", fuseX, fuseY, filled, fuseH)
        end
        local segments = 6
        love.graphics.setColor(0.12, 0.08, 0.06, 0.55)
        for i = 1, segments - 1 do
            local tx = fuseX + (fuseW / segments) * i
            love.graphics.rectangle("fill", tx, fuseY - 1, 1, fuseH + 2)
        end

        stackY = fuseY + fuseH + 6
        local label = "Plague Tolerance"
        local lw = labelFont:getWidth(label)
        local labelH = labelFont:getHeight()
        game_flow.printShadow(
            labelFont,
            label,
            cx - lw / 2,
            stackY,
            r,
            g,
            b,
            0.88 * a
        )
        stackY = stackY + labelH * 0.72 + HUD_GAP

        if dmgPulse > 0 and dmgAmount > 0 then
            local floatText = string.format("-%.0fs", dmgAmount)
            local rise = (1 - dmgPulse) * 18
            love.graphics.setFont(labelFont)
            love.graphics.setColor(1, 0.35, 0.28, dmgPulse)
            love.graphics.print(
                floatText,
                cx + tw * 0.42 * scale,
                timerY + 4 - rise
            )
        end
        local healPulse, healAmount = self.countdown:getHealPulse()
        if healPulse > 0 and healAmount > 0 then
            local floatText = string.format("+%.0fs", healAmount)
            local rise = (1 - healPulse) * 18
            love.graphics.setFont(labelFont)
            love.graphics.setColor(0.45, 0.95, 0.55, healPulse)
            love.graphics.print(
                floatText,
                cx - tw * 0.55 * scale,
                timerY + 4 - rise
            )
        end

        -- Hide objective strip on end screens (victory / extract own the frame).
        local showObjectives = not self.extracted and not self.sectorCleared
        if showObjectives then
            ensureHudVials()
            local districtCount = nests.countDistrictCleansed(self.nests)
            local well = nests.getWell(self.nests)
            local wellState = "Locked"
            if well and well.cleansed then
                wellState = "Cleansed"
            elseif well and not well.locked then
                wellState = "Ready"
            end
            local potionsLine = string.format("Potions  %d/3", districtCount)
            local wellLine = "Well  " .. wellState
            local statusGap = 20
            local statusW = labelFont:getWidth(potionsLine)
                + statusGap
                + labelFont:getWidth(wellLine)
            local vialIds = { "a", "b", "c", "well" }
            local vialPitch = 26
            local vialRowW = vialPitch * (#vialIds - 1)
            local plateInnerW = math.max(statusW, vialRowW)
            local plateW = plateInnerW + HUD_PAD * 4
            local vialH = 32 * HUD_VIAL_SCALE
            -- Full line metrics so script glyphs + vials sit inside the plate.
            local plateH = HUD_PAD
                + labelH
                + HUD_GAP
                + vialH
                + HUD_PAD
            local plateX = cx - plateW / 2
            local plateY = stackY
            game_flow.drawHudPlate(plateX, plateY, plateW, plateH, 0.55)

            local statusY = plateY + HUD_PAD
            local statusX = cx - statusW / 2
            game_flow.printShadow(
                labelFont,
                potionsLine,
                statusX,
                statusY,
                0.95,
                0.9,
                0.78,
                0.92
            )
            local wellCol = nests.color("well")
            local wellAlpha = (wellState == "Cleansed" and 0.92)
                or (wellState == "Ready" and 0.92)
                or 0.65
            game_flow.printShadow(
                labelFont,
                wellLine,
                statusX + labelFont:getWidth(potionsLine) + statusGap,
                statusY,
                wellCol[1],
                wellCol[2],
                wellCol[3],
                wellAlpha
            )

            local vialY = statusY + labelH + HUD_GAP * 0.35 + vialH * 0.35
            local vialStartX = cx - vialRowW / 2
            local nestById = {}
            if self.nests then
                for _, nest in ipairs(self.nests) do
                    nestById[nest.id] = nest
                end
            end
            for i, id in ipairs(vialIds) do
                local px = vialStartX + (i - 1) * vialPitch
                drawHudVial(id, px, vialY, HUD_VIAL_SCALE, nestById[id])
            end
            stackY = plateY + plateH + HUD_GAP + 4
        end
        self._hudStackBottom = stackY
    end

    if self.hintTime and self.hintTime > 0
        and not self.extracted
        and not self.sectorCleared
        and self.gameState == GAME_STATE.GAMEPLAY
    then
        local alpha = math.min(1, self.hintTime / 1.2)
        if self.hintTime > 3 then
            alpha = math.min(1, (4 - self.hintTime) / 0.5)
        end
        local font = self.hudHelpFont or prevFont
        local msg =
            "Collect three potions, then cleanse the Well."
        local tw = font:getWidth(msg)
        local th = font:getHeight()
        local bx = (sw - tw) / 2 - 14
        -- Always below the measured HUD stack (never on top of Potions plate).
        local by = math.max(
            (self._hudStackBottom or (sh * 0.22)) + 4,
            sh * 0.22
        )
        game_flow.drawHudPlate(bx, by - 2, tw + 28, th + 10, 0.55 * alpha)
        game_flow.printfShadow(
            font,
            msg,
            0,
            by,
            sw,
            "center",
            0.96,
            0.9,
            0.78,
            0.95 * alpha
        )
    end

    -- Cleanse / locked-well prompt when standing in an uncleansed site.
    local promptNest = nests.promptNest(self.nests)
    local promptMsg = nests.promptText(self.nests)
    if promptNest
        and promptMsg
        and not self.extracted
        and not self.sectorCleared
        and self.gameState == GAME_STATE.GAMEPLAY
    then
        local msg = promptMsg
        local font = self.hudHelpFont or prevFont
        local tw = font:getWidth(msg)
        local th = font:getHeight()
        local bx = (sw - tw) / 2 - 14
        local by = sh * 0.76
        game_flow.drawHudPlate(bx, by - 2, tw + 28, th + 8, 0.6)
        game_flow.printfShadow(
            font,
            msg,
            0,
            by,
            sw,
            "center",
            0.98,
            0.92,
            0.78,
            1
        )
    end

    local subtitle, subtitleAlpha = sound_effects.getNearDeathSubtitle()
    if subtitle then
        local font = self.hudHelpFont or prevFont
        local textWidth = font:getWidth(subtitle)
        local boxWidth = math.min(sw - 48, textWidth + 36)
        local boxX = (sw - boxWidth) / 2
        local textY = sh - font:getHeight() - 48
        game_flow.drawHudPlate(
            boxX,
            textY - 4,
            boxWidth,
            font:getHeight() + 10,
            0.6 * subtitleAlpha
        )
        game_flow.printfShadow(
            font,
            subtitle,
            24,
            textY,
            sw - 48,
            "center",
            0.98,
            0.92,
            0.82,
            subtitleAlpha
        )
    end

    if self.sectorCleared and self.winReady then
        game_flow.drawVictory(self)
    elseif self.sectorCleared and self.winPresenting then
        -- Stage C begins mid-presentation: show victory copy once daylight is up.
        if (self.winTimer or 0) >= 2.5 then
            game_flow.drawVictory(self)
        end
    elseif self.extracted then
        game_flow.drawExtract(self)
    end

    local playerActor = self:getActor("player")
    if not playerActor then
        love.graphics.setFont(prevFont)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    if state.enemyTestMode then
        love.graphics.setFont(self.hudSmallFont or self.hudHelpFont or prevFont)
        love.graphics.setColor(1, 1, 1, 0.75)
        love.graphics.print(
            "ENEMY TEST · WASD · Shift dash · Space swing · R reset · Esc quit",
            10,
            sh - 28
        )
    end

    enemy_test.drawHud(state)

    if physics.debug then
        love.graphics.setFont(self.hudSmallFont or self.hudHelpFont or prevFont)
        love.graphics.setColor(1, 1, 1, 0.85)
        local speed = playerActor:getSpeed()
        love.graphics.print(
            string.format(
                "DEBUG | col %.0f,%.0f |v| %.2f | pos %.0f,%.0f",
                playerActor.collider:getX(),
                playerActor.collider:getY(),
                speed,
                playerActor.pos.x,
                playerActor.pos.y
            ),
            10,
            sh - 72
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
        local enc = encounter_director.debugCounts(self)
        love.graphics.print(
            string.format(
                "C:%d F:%d K:%d R:%d near %s | enc %d+%d/%d",
                counts.chaser,
                counts.fleer,
                counts.keeper,
                counts.ranger,
                nearest and string.format("%.0f", nearest) or "-",
                enc.active,
                enc.pending,
                enc.cap
            ),
            10,
            sh - 88
        )
        love.graphics.print(
            string.format(
                "frame %.2fms | last collapse wave %.2fms",
                (self.lastFrameDt or 0) * 1000,
                collapse.getLastWaveMs()
            ),
            10,
            sh - 40
        )
    end

    love.graphics.setFont(prevFont)
    love.graphics.setColor(1, 1, 1, 1)
end

local function argvHas(argv, flag)
    for _, value in ipairs(argv or {}) do
        if value == flag then
            return true
        end
    end
    return false
end

--- Build a fresh playable run (physics world, map colliders, actors, director).
--- Safe to call again after state:prepareRestart.
local function beginRun(opts)
    opts = opts or {}
    local enemyTest = opts.enemyTest == true

    physics.destroy()
    physics.init()
    enemy_attacks.clearAll()
    sound_effects.reset()

    state.actors = {}
    state.enemyTestMode = enemyTest
    state.gameMap = game_map.load("res/maps/map.lua")
    state.nests = nests.fromMap(state.gameMap)
    state.sectorCleared = false
    state.extracted = false
    state.extractReason = nil
    state.plagueSenseIntensity = 0
    state._freezeCamX = nil
    state._freezeCamY = nil
    state.floats = {}
    state.hintTime = enemyTest and 0 or 4
    game_flow.resetWin(state)
    game_flow.ensureFonts(state)
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

    state.countdown = countdown.new({ duration = 90 })
    if enemyTest then
        -- Natural decay off; combat damage / sword kills still work.
        state.countdown:pause()
    end
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
    if enemyTest then
        enemies = enemy_test.spawnSet(spawnX, spawnY)
        print("[enemy_test] one of each type — director/collapse off, timer paused")
    else
        for _, point in ipairs(spawnData.enemies) do
            local e = enemy:new(point.x, point.y, { type = point.type })
            e.nest = point.nest
            e.killRewardSeconds = encounter_director.timeRewardFor(point.type)
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
            for _, e in ipairs(enemies) do
                e.killRewardSeconds = encounter_director.timeRewardFor(e.enemyType)
            end
            print("[map] warning: no Spawns enemies; using plaza fallbacks")
        end
    end

    cam = camera(playerActor.pos.x, playerActor.pos.y, zoom)
    if not state.canvas then
        state.canvas = love.graphics.newCanvas()
    end
    state.gameState = GAME_STATE.GAMEPLAY
    for _, actor in ipairs({ playerActor, swordActor, trailBehind, trailFront }) do
        state.actors[#state.actors + 1] = actor
    end
    for _, e in ipairs(enemies) do
        state.actors[#state.actors + 1] = e
    end

    playerActor.applyDamage = function(amount, source, dmgOpts)
        return state:applyPlayerDamage(amount, source, dmgOpts)
    end

    if not enemyTest then
        encounter_director.load(state, spawnData)
    else
        encounter_director.reset()
    end

    if opts.runPhysicsSelftest ~= false then
        physics_selftest.run(playerActor, enemies)
    end

    return playerActor, enemies
end

--- Tear down actors/physics and rebuild a clean 90s run (no Windfield leaks).
function state:prepareRestart()
    print("[run] prepareRestart — safe teardown + rebuild")
    encounter_director.reset()
    enemy_attacks.clearAll()
    local keepEnemyTest = self.enemyTestMode == true
    self.actors = {}
    beginRun({
        runPhysicsSelftest = false,
        enemyTest = keepEnemyTest,
    })
    self.gameState = GAME_STATE.GAMEPLAY
    print("[run] restart ready")
end

local function startFromNarrative()
    beginRun({
        runPhysicsSelftest = false,
        enemyTest = false,
    })
    state.gameState = GAME_STATE.GAMEPLAY
end

function love.load(args)
    local argv = args or arg or {}
    sound_effects.load()
    plague_senses.load()
    game_flow.ensureFonts(state)

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

    local enemyTest = argvHas(argv, "--enemy-test")
    local mapReadability = argvHas(argv, "--map-readability-quit")
    if argvHas(argv, "--collapse-bench-quit") then
        beginRun({ runPhysicsSelftest = false, enemyTest = false })
        state.gameState = GAME_STATE.GAMEPLAY
        local samples = {}
        local sum = 0
        for i = 1, 8 do
            local ms = collapse.debugRunWaveNow(state)
            samples[i] = ms
            sum = sum + ms
        end
        table.sort(samples)
        print(string.format(
            "[collapse_bench] n=8 avg=%.2fms median=%.2fms max=%.2fms samples=%s",
            sum / #samples,
            samples[math.ceil(#samples / 2)],
            samples[#samples],
            table.concat((function()
                local t = {}
                for i, v in ipairs(samples) do
                    t[i] = string.format("%.2f", v)
                end
                return t
            end)(), ",")
        ))
        love.event.quit()
        return
    end

    if argvHas(argv, "--flow-smoke-quit") then
        local ok = true
        local function check(name, cond)
            print(string.format("[flow_smoke] %s: %s", cond and "PASS" or "FAIL", name))
            ok = ok and cond
        end
        game_flow.enterTitle(state)
        check("boot lands on TITLE", state.gameState == GAME_STATE.TITLE)
        game_flow.enterNarrative(state)
        check("Play opens NARRATIVE", state.gameState == GAME_STATE.NARRATIVE)
        startFromNarrative()
        check("Continue starts GAMEPLAY", state.gameState == GAME_STATE.GAMEPLAY)
        check("run has countdown", state.countdown ~= nil)
        check("3 districts + well loaded", state.nests and #state.nests == 4)
        local well = nests.getWell(state.nests)
        check("well locked at start", well ~= nil and well.locked == true)
        check("not win before seals", not nests.allCleansed(state.nests))
        for _, nest in ipairs(state.nests) do
            if not nests.isWell(nest) then
                nest.cleansed = true
            end
        end
        check("districts 3/3 unlocks well", nests.wellUnlocked(state.nests))
        check("never win at district 3/3 alone", not nests.allCleansed(state.nests))
        well.cleansed = true
        well.locked = false
        check("well cleanse is the win condition", nests.allCleansed(state.nests))
        -- Reset nest flags before win-presentation smoke (which sets sectorCleared).
        for _, nest in ipairs(state.nests) do
            nest.cleansed = false
            nest.locked = nests.isWell(nest)
        end
        state.sectorCleared = true
        state:onSectorCleared()
        for _ = 1, 400 do
            game_flow.updateWin(state, 1 / 60)
        end
        check("win presentation reaches victory", state.winReady == true)
        check("cleanse amount is full", atmosphere.getCleanse() >= 0.99)
        check(
            "win flash cleared after beat",
            (atmosphere.getWinFlash and atmosphere.getWinFlash() or 0) <= 0.01
        )
        for i = 1, 3 do
            state:prepareRestart()
            check(
                "restart " .. i .. " clears win tint",
                atmosphere.getCleanse() == 0
                    and (atmosphere.getWinFlash and atmosphere.getWinFlash() or 0) <= 0.01
                    and state.winReady == false
                    and state.sectorCleared == false
            )
            local wellAfter = nests.getWell(state.nests)
            check(
                "restart " .. i .. " relocks well",
                wellAfter ~= nil and wellAfter.locked == true and not wellAfter.cleansed
            )
        end
        state.extracted = true
        state.extractReason = "abyss"
        check("extract reason abyss", state.extractReason == "abyss")
        print(ok and "[flow_smoke] ALL PASS" or "[flow_smoke] FAILED")
        love.event.quit()
        return
    end

    local skipTitle = enemyTest
        or mapReadability
        or argvHas(argv, "--selftest-quit")
        or argvHas(argv, "--encounter-selftest")
        or argvHas(argv, "--damage-verify")

    if skipTitle then
        local playerActor = select(1, beginRun({
            runPhysicsSelftest = not enemyTest and not mapReadability,
            enemyTest = enemyTest,
        }))
        state.gameState = GAME_STATE.GAMEPLAY

        if enemyTest then
            local smokeOk = enemy_test.runSmoke(
                state,
                playerActor or state:getActor("player")
            )
            if argvHas(argv, "--enemy-test-quit") then
                print(smokeOk and "[enemy_test] DONE PASS" or "[enemy_test] DONE FAIL")
                love.event.quit()
                return
            end
        end

        if argvHas(argv, "--encounter-selftest") then
            local ok = encounter_director.runSelftest(state)
            print(ok and "[encounter_selftest] ALL PASS" or "[encounter_selftest] FAILED")
            love.event.quit()
            return
        end

        if argvHas(argv, "--damage-verify") then
            local ok = physics_selftest.verifyVisibleKills(playerActor or state:getActor("player"))
            print(ok and "[damage_verify] DONE PASS" or "[damage_verify] DONE FAIL")
            love.event.quit()
            return
        end

        if argvHas(argv, "--selftest-quit") then
            love.event.quit()
            return
        end

        if mapReadability then
            state._mapReadabilityCapture = {
                frame = 0,
                done = false,
            }
            physics.debug = true
            DEBUG = true
            print("[map_readability] capture armed (F1 on, forced cracks)")
        end
    else
        game_flow.enterTitle(state)
    end
end

function love.update(dt)
    state:update(dt)
    state:updateSoundEffects(dt)

    local cap = state._mapReadabilityCapture
    if cap and not cap.done then
        cap.frame = cap.frame + 1
        if cap.frame == 3 then
            collapse.debugCrackNearPlayer(state)
            collapse.debugCrackNearPlayer(state)
        elseif cap.frame == 10 then
            -- Instantly drop any cracking cells so abyss depth is visible.
            local dropped = 0
            for row = 0, 23 do
                for col = 0, 29 do
                    if collapse.isCrackingCell(col, row) then
                        if collapse.debugForceFallAt(col, row, state) then
                            dropped = dropped + 1
                        end
                    end
                end
            end
            print(string.format(
                "[map_readability] forced %d falls (fallen total %d)",
                dropped,
                collapse.getFallenCount()
            ))
        elseif cap.frame == 40 and not cap.queuedShot then
            cap.queuedShot = true
        end
    end
end

function love.draw()
    -- Near-black clear — map must fully cover playable cells (no grey voids).
    love.graphics.setBackgroundColor(0.04, 0.04, 0.05)

    if state.gameState == GAME_STATE.TITLE then
        game_flow.drawTitle(state)
        return
    end
    if state.gameState == GAME_STATE.NARRATIVE then
        game_flow.drawNarrative(state)
        return
    end

    if cam and state.gameMap then
        cam:attach()
        -- Perspective order: behind the fountain from above, in front from below.
        game_map.drawWithActors(state.gameMap, state.drawActors, state)
        atmosphere.drawWorld()
        atmosphere.drawCleanseWorld()
        if not state.enemyTestMode then
            encounter_director.drawWorld()
        end
        enemy_attacks.drawAll(state.actors)
        if state.hudHelpFont then
            love.graphics.setFont(state.hudHelpFont)
        elseif state.hudLabelFont then
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
    end

    atmosphere.drawGrade()
    if not state.sectorCleared then
        plague_senses.drawVignette(state.plagueSenseIntensity)
    end
    atmosphere.drawWinFlash()
    if cam
        and state.gameState == GAME_STATE.GAMEPLAY
        and not state.extracted
        and not state.sectorCleared
    then
        atmosphere.drawNestChevrons(cam, state.nests)
    end
    state:drawHud()

    if state.gameState == GAME_STATE.PAUSE then
        game_flow.drawPause(state)
    end

    local cap = state._mapReadabilityCapture
    if cap and cap.queuedShot and not cap.done then
        cap.done = true
        love.graphics.captureScreenshot(function(imageData)
            local path = "map_readability_after.png"
            imageData:encode("png", path)
            love.filesystem.write(
                "map_readability_notes.txt",
                "Map readability capture\n"
            )
            print("[map_readability] wrote " .. love.filesystem.getSaveDirectory() .. "/" .. path)
            love.event.quit()
        end)
    end
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

local function startPlayerDash()
    local playerActor = state:getActor("player")
    if playerActor and playerActor.startDash then
        playerActor:startDash()
    end
end

function love.keypressed(k)
    if state.gameState == GAME_STATE.TITLE then
        if k == "escape" then
            love.event.quit()
        else
            game_flow.enterNarrative(state)
        end
        return
    end

    if state.gameState == GAME_STATE.NARRATIVE then
        if k == "escape" then
            game_flow.enterTitle(state)
        elseif k == "down" or k == "s" or k == "pagedown" then
            game_flow.scrollNarrative(state, 36)
        elseif k == "up" or k == "w" or k == "pageup" then
            game_flow.scrollNarrative(state, -36)
        elseif k == "return" or k == "kpenter" or k == "space" then
            startFromNarrative()
        end
        return
    end

    if state.gameState == GAME_STATE.PAUSE then
        if k == "escape" then
            state.gameState = GAME_STATE.GAMEPLAY
        elseif k == "r" then
            state:prepareRestart()
        elseif k == "q" then
            love.event.quit()
        end
        return
    end

    -- End screens / cleanse beat: no combat input.
    if state.extracted or state.sectorCleared then
        if state.winReady or state.extracted then
            if k == "escape" then
                love.event.quit()
            elseif k == "r" then
                state:prepareRestart()
            end
        end
        return
    end

    if k == "escape" then
        if state.gameState == GAME_STATE.GAMEPLAY
            and not state.extracted
            and not state.sectorCleared
        then
            state.gameState = GAME_STATE.PAUSE
        end
    elseif k == "f1" or k == "`" then
        local on = physics.toggleDebug()
        DEBUG = on
        print("[physics] debug draw: " .. (on and "ON" or "OFF"))
    elseif k == "f2" then
        -- Synchronous selftest is expensive — only when F1 debug is already on.
        if physics.debug then
            local enemies = {}
            for _, actor in ipairs(state.actors) do
                if actor.label == "enemy" then
                    enemies[#enemies + 1] = actor
                end
            end
            physics_selftest.run(state:getActor("player"), enemies)
        end
    elseif k == "h" then
        -- Debug-only plague damage (hidden from normal HUD prompts).
        if physics.debug then
            local ok, left = state:applyPlayerDamage(3, "debug", { bypassIFrames = true })
            if ok then
                print(string.format("[countdown] damage 3.0 → %.1fs left", left))
            end
        end
    elseif k == "g" then
        if physics.debug and state.countdown and not state.extracted then
            state.countdown:addTime(5)
            print(string.format("[countdown] +5s → %.1fs left", state.countdown:getRemaining()))
        end
    elseif k == "v" then
        if physics.debug and not state.extracted and not state.sectorCleared then
            collapse.debugCrackNearPlayer(state)
        end
    elseif k == "r" then
        -- Mid-run hard restart is a hitch; use pause-menu Restart instead.
        if physics.debug then
            state:prepareRestart()
        end
    elseif k == "space" then
        if not state.extracted and not state.sectorCleared then
            startPlayerSwingAt(love.mouse.getPosition())
        end
    elseif k == "lshift" or k == "rshift" then
        if not state.extracted and not state.sectorCleared then
            startPlayerDash()
        end
    end
end

function love.wheelmoved(_, y)
    if state.gameState == GAME_STATE.NARRATIVE then
        game_flow.scrollNarrative(state, -y * 28)
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then
        return
    end
    if state.gameState == GAME_STATE.TITLE then
        game_flow.enterNarrative(state)
        return
    end
    if state.gameState == GAME_STATE.NARRATIVE then
        -- Click continues only when fully scrolled (or no overflow).
        local maxScroll = state.narrativeMaxScroll or 0
        if maxScroll > 2 and (state.narrativeScroll or 0) < maxScroll - 2 then
            game_flow.scrollNarrative(state, 48)
            return
        end
        startFromNarrative()
        return
    end
    if state.gameState == GAME_STATE.PAUSE
        or state.extracted
        or (state.sectorCleared and state.winReady)
    then
        return
    end
    if state.gameState == GAME_STATE.GAMEPLAY
        and not state.extracted
        and not state.sectorCleared
    then
        startPlayerSwingAt(x, y)
    end
end
