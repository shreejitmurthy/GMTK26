-- Gameplay sound effects and their playback rules.

local sound_effects = {}

local FOOTSTEP_INTERVAL = 0.3
local BACKGROUND_MUSIC_COOLDOWN = 2
local NEAR_DEATH_SECONDS = 15
local NEAR_DEATH_SUBTITLE = "*Argh*. The Plague... It consumes me"
local SUBTITLE_FADE_SECONDS = 0.35
local MUFFLE_MIN_HIGH_GAIN = 0.06
local MUFFLE_MAX_VOLUME_REDUCTION = 0.3

sound_effects.VOLUME = {
    footstep = 0.05,
    hit = 0.8,
    impact = 0.65,
    largeDeathImpact = 0.8,
    dashVoice = 1.0,
    squelch = 0.3,
    nearDeathVoice = 1.0,
    backgroundMusic = 0.15,
}

local HIT_PATHS = {
    "res/sounds/hit_1.wav",
    "res/sounds/hit_2.wav",
    "res/sounds/hit_3.wav",
}

local SQUELCH_PATHS = {
    "res/sounds/squelching_1.wav",
    "res/sounds/squelching_2.wav",
    "res/sounds/squelching_3.wav",
    "res/sounds/squelching_4.wav",
}

local sources
local loaded = false
local lastHitIndex
local lastDashIndex
local footstepTimer = 0
local nearDeathActive = false
local nearDeathSubtitleTime = 0
local playerDead = false
local backgroundMusicState = "ready"
local backgroundMusicCooldown = 0
local sourceBaseVolumes = {}
local lastMuffleIntensity
local filterWarningPrinted = false

local function newSource(path, volume, sourceType)
    if not love.filesystem.getInfo(path) then
        print("[sound] warning: missing " .. path)
        return nil
    end

    local ok, source = pcall(
        love.audio.newSource,
        path,
        sourceType or "static"
    )
    if not ok then
        print(string.format(
            "[sound] warning: could not load %s: %s",
            path,
            tostring(source)
        ))
        return nil
    end
    source:setVolume(volume or 1)
    sourceBaseVolumes[source] = volume or 1
    return source
end

local function newSourceList(paths, volume)
    local result = {}
    for _, path in ipairs(paths) do
        local source = newSource(path, volume)
        if source then
            result[#result + 1] = source
        end
    end
    return result
end

local function stopSource(source)
    if source then
        source:stop()
    end
end

local function stopSourceList(list)
    for _, source in ipairs(list or {}) do
        stopSource(source)
    end
end

local function playSource(source)
    if not source then
        return false
    end
    source:stop()
    source:play()
    return true
end

local function forEachSource(callback)
    if not sources then
        return
    end
    callback(sources.footstep)
    for _, source in ipairs(sources.hits or {}) do
        callback(source)
    end
    for _, source in ipairs(sources.impacts or {}) do
        callback(source)
    end
    callback(sources.largeDeathImpact)
    for _, source in ipairs(sources.dashes or {}) do
        callback(source)
    end
    for _, source in ipairs(sources.squelches or {}) do
        callback(source)
    end
    callback(sources.nearDeath)
    callback(sources.backgroundMusic)
end

local function applyMuffle(intensity, force)
    intensity = math.max(0, math.min(1, intensity or 0))
    if not force
        and lastMuffleIntensity
        and math.abs(intensity - lastMuffleIntensity) < 0.001
    then
        return
    end
    lastMuffleIntensity = intensity

    local shaped = intensity ^ 1.1
    local highGain = 1
        - (1 - MUFFLE_MIN_HIGH_GAIN) * shaped
    local volumeScale = 1
        - MUFFLE_MAX_VOLUME_REDUCTION * shaped

    forEachSource(function(source)
        if not source then
            return
        end

        local baseVolume = sourceBaseVolumes[source] or 1
        source:setVolume(baseVolume * volumeScale)

        local ok, applied
        if intensity <= 0.001 then
            ok, applied = pcall(source.setFilter, source)
        else
            ok, applied = pcall(source.setFilter, source, {
                type = "lowpass",
                volume = 1,
                highgain = highGain,
            })
        end
        if (not ok or applied == false) and not filterWarningPrinted then
            print(
                "[sound] warning: low-pass filtering unavailable; "
                    .. "using volume muffling only"
            )
            filterWarningPrinted = true
        end
    end)
end

local function randomIndexExcept(count, previousIndex)
    if count <= 1 then
        return count == 1 and 1 or nil
    end
    if not previousIndex or previousIndex < 1 or previousIndex > count then
        return love.math.random(count)
    end

    -- Pick from count - 1 slots, then skip the previous slot.
    local index = love.math.random(count - 1)
    if index >= previousIndex then
        index = index + 1
    end
    return index
end

function sound_effects.load()
    if loaded then
        return
    end

    -- The supplied first dash variant is named dash.wav; prefer dash_1.wav
    -- automatically if the asset is renamed later.
    local dashOnePath = "res/sounds/dash_1.wav"
    if not love.filesystem.getInfo(dashOnePath) then
        dashOnePath = "res/sounds/dash.wav"
    end

    sources = {
        footstep = newSource(
            "res/sounds/foley_footstep_concrete_4.wav",
            sound_effects.VOLUME.footstep
        ),
        hits = newSourceList(HIT_PATHS, sound_effects.VOLUME.hit),
        impacts = newSourceList({
            "res/sounds/Impact 2.wav",
            "res/sounds/Impact 3.wav",
        }, sound_effects.VOLUME.impact),
        largeDeathImpact = newSource(
            "res/sounds/Impact 4.wav",
            sound_effects.VOLUME.largeDeathImpact
        ),
        dashes = newSourceList({
            dashOnePath,
            "res/sounds/dash_2.wav",
        }, sound_effects.VOLUME.dashVoice),
        squelches = newSourceList(
            SQUELCH_PATHS,
            sound_effects.VOLUME.squelch
        ),
        nearDeath = newSource(
            "res/sounds/near_death.wav",
            sound_effects.VOLUME.nearDeathVoice
        ),
        backgroundMusic = newSource(
            "res/sounds/bg_music.mp3",
            sound_effects.VOLUME.backgroundMusic,
            "stream"
        ),
    }
    if sources.backgroundMusic then
        sources.backgroundMusic:setLooping(false)
    end
    loaded = true
end

local function ensureLoaded()
    if not loaded then
        sound_effects.load()
    end
end

function sound_effects.stopVoiceSounds()
    if not loaded then
        return
    end
    stopSourceList(sources.dashes)
    stopSource(sources.nearDeath)
    nearDeathActive = false
    nearDeathSubtitleTime = 0
end

function sound_effects.stopAll()
    if not loaded then
        return
    end
    stopSource(sources.footstep)
    stopSourceList(sources.hits)
    stopSourceList(sources.impacts)
    stopSource(sources.largeDeathImpact)
    stopSourceList(sources.dashes)
    stopSourceList(sources.squelches)
    stopSource(sources.nearDeath)
    -- Background music intentionally continues through run resets.
end

function sound_effects.reset()
    ensureLoaded()
    sound_effects.stopAll()
    lastHitIndex = nil
    lastDashIndex = nil
    footstepTimer = 0
    nearDeathActive = false
    nearDeathSubtitleTime = 0
    playerDead = false
    applyMuffle(0, true)
end

--- Accepted enemy hits have a 50% chance to produce a non-repeating hit sound.
function sound_effects.playPlayerHit()
    ensureLoaded()
    if love.math.random() >= 0.75 then
        return false
    end

    local index = randomIndexExcept(#sources.hits, lastHitIndex)
    if index and playSource(sources.hits[index]) then
        lastHitIndex = index
        return true
    end
    return false
end

--- Accepted dashes have a 50% chance to produce a non-repeating dash sound.
--- With two sounds, played variants naturally alternate after the first pick.
function sound_effects.playDash()
    ensureLoaded()
    if playerDead or love.math.random() >= 0.5 then
        return false
    end

    local index = randomIndexExcept(#sources.dashes, lastDashIndex)
    if not index then
        return false
    end

    -- Voice clips should not stack across consecutive dashes.
    stopSourceList(sources.dashes)
    if playSource(sources.dashes[index]) then
        lastDashIndex = index
        return true
    end
    return false
end

function sound_effects.playEnemyHitImpact()
    ensureLoaded()
    local count = #sources.impacts
    if count == 0 then
        return false
    end
    return playSource(sources.impacts[love.math.random(count)])
end

function sound_effects.playEnemyKilled(isLargeEnemy)
    ensureLoaded()
    local count = #sources.squelches
    local played = false
    if count > 0 then
        played = playSource(sources.squelches[love.math.random(count)])
    end
    if isLargeEnemy then
        played = playSource(sources.largeDeathImpact) or played
    end
    return played
end

--- Districts sealed — Plague Well unlocks (heavy impact + wet cue).
function sound_effects.playWellUnlock()
    ensureLoaded()
    local played = playSource(sources.largeDeathImpact)
    local count = #sources.squelches
    if count > 0 then
        played = playSource(sources.squelches[love.math.random(count)]) or played
    end
    return played
end

--- Well cleansed — bright resolve sting; clear plague ducking / near-death.
function sound_effects.playWellCleansed()
    ensureLoaded()
    stopSource(sources.nearDeath)
    nearDeathActive = false
    nearDeathSubtitleTime = 0
    applyMuffle(0, true)
    local played = playSource(sources.largeDeathImpact)
    if sources.impacts and #sources.impacts > 0 then
        played = playSource(sources.impacts[1]) or played
    end
    return played
end

local function updateFootsteps(dt, walking)
    if not walking then
        stopSource(sources.footstep)
        footstepTimer = 0
        return
    end

    footstepTimer = footstepTimer - dt
    if footstepTimer <= 0 then
        playSource(sources.footstep)
        repeat
            footstepTimer = footstepTimer + FOOTSTEP_INTERVAL
        until footstepTimer > 0
    end
end

local function updateBackgroundMusic(dt)
    local music = sources.backgroundMusic
    if not music then
        return
    end

    if backgroundMusicState == "playing" then
        if music:isPlaying() then
            return
        end
        backgroundMusicState = "cooldown"
        backgroundMusicCooldown = BACKGROUND_MUSIC_COOLDOWN
        return
    end

    if backgroundMusicState == "cooldown" then
        backgroundMusicCooldown =
            math.max(0, backgroundMusicCooldown - dt)
        if backgroundMusicCooldown > 0 then
            return
        end
        backgroundMusicState = "ready"
    end

    music:stop()
    music:play()
    backgroundMusicState = "playing"
end

local function updateNearDeath(remaining)
    local shouldPlay = remaining
        and remaining > 0
        and remaining < NEAR_DEATH_SECONDS

    if shouldPlay and not nearDeathActive then
        nearDeathActive = playSource(sources.nearDeath)
        if nearDeathActive then
            nearDeathSubtitleTime = sources.nearDeath:getDuration()
        end
    elseif not shouldPlay and nearDeathActive then
        stopSource(sources.nearDeath)
        nearDeathActive = false
        nearDeathSubtitleTime = 0
    end
end

function sound_effects.getNearDeathSubtitle()
    if nearDeathSubtitleTime <= 0 then
        return nil, 0
    end
    local alpha = math.min(1, nearDeathSubtitleTime / SUBTITLE_FADE_SECONDS)
    return NEAR_DEATH_SUBTITLE, alpha
end

--- context: { active, dead, walking, remaining, plagueIntensity }.
function sound_effects.update(dt, context)
    ensureLoaded()
    context = context or {}
    nearDeathSubtitleTime = math.max(0, nearDeathSubtitleTime - dt)
    playerDead = context.dead == true
    updateBackgroundMusic(dt)
    applyMuffle(context.plagueIntensity)

    if playerDead or not context.active then
        stopSource(sources.footstep)
        footstepTimer = 0
        sound_effects.stopVoiceSounds()
        return
    end

    updateFootsteps(dt, context.walking == true)
    updateNearDeath(context.remaining)
end

return sound_effects
