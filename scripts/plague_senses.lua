-- Shared near-death sensory ramp and full-screen plague vignette.

local plague_senses = {}

plague_senses.THRESHOLD_SECONDS = 30

local RESPONSE_SPEED = 4.5
local vignetteShader
local shaderAttempted = false
local shaderWarningPrinted = false

local function clamp01(value)
    return math.max(0, math.min(1, value or 0))
end

--- Returns a smooth 0..1 sensory intensity during the final 30 seconds.
function plague_senses.getTargetIntensity(remaining)
    if type(remaining) ~= "number"
        or remaining >= plague_senses.THRESHOLD_SECONDS
    then
        return 0
    end

    local t = clamp01(
        1 - remaining / plague_senses.THRESHOLD_SECONDS
    )
    -- Smoothstep keeps the onset subtle while still becoming oppressive near zero.
    return t * t * (3 - 2 * t)
end

--- Smooth abrupt damage/heal jumps without lagging behind the ticking timer.
function plague_senses.approach(current, target, dt)
    current = clamp01(current)
    target = clamp01(target)
    if not dt or dt <= 0 then
        return current
    end
    local blend = 1 - math.exp(-RESPONSE_SPEED * dt)
    return current + (target - current) * blend
end

local function getVignetteShader()
    if shaderAttempted then
        return vignetteShader
    end
    shaderAttempted = true

    local ok, shader = pcall(love.graphics.newShader, [[
        extern number plagueIntensity;

        vec4 effect(
            vec4 color,
            Image texture,
            vec2 textureCoords,
            vec2 screenCoords
        ) {
            vec2 uv = screenCoords / love_ScreenSize.xy;
            vec2 centered = (uv - vec2(0.5)) * 2.0;
            number radius = length(centered);

            // Begin in the extreme corners, then creep in toward the centre.
            number innerRadius = mix(1.14, 0.22, plagueIntensity);
            number outerRadius = mix(1.48, 1.02, plagueIntensity);
            number vignette = smoothstep(innerRadius, outerRadius, radius);
            number opacity =
                vignette
                * plagueIntensity
                * mix(0.20, 0.92, plagueIntensity);
            vec3 plagueColor = mix(
                vec3(0.16, 0.025, 0.02),
                vec3(0.008, 0.012, 0.006),
                plagueIntensity
            );

            return vec4(plagueColor, opacity) * color;
        }
    ]])

    if not ok then
        if not shaderWarningPrinted then
            print(
                "[plague] warning: vignette shader unavailable: "
                    .. tostring(shader)
            )
            shaderWarningPrinted = true
        end
        return nil
    end

    vignetteShader = shader
    return vignetteShader
end

function plague_senses.load()
    return getVignetteShader() ~= nil
end

local function drawFallbackVignette(sw, sh, intensity)
    local edge = math.floor(
        math.min(sw, sh) * (0.12 + 0.22 * intensity)
    )
    local layers = 10
    local band = edge / layers
    for i = 0, layers - 1 do
        local t = i / layers
        local alpha = 0.055 * intensity * (1 - t)
        love.graphics.setColor(0.03, 0.008, 0.01, alpha)
        love.graphics.rectangle("fill", 0, i * band, sw, band)
        love.graphics.rectangle(
            "fill",
            0,
            sh - (i + 1) * band,
            sw,
            band
        )
        love.graphics.rectangle(
            "fill",
            i * band,
            edge,
            band,
            sh - 2 * edge
        )
        love.graphics.rectangle(
            "fill",
            sw - (i + 1) * band,
            edge,
            band,
            sh - 2 * edge
        )
    end
end

function plague_senses.drawVignette(intensity)
    intensity = clamp01(intensity)
    if intensity <= 0.001 then
        return
    end

    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local shader = getVignetteShader()

    love.graphics.push("all")
    love.graphics.setColor(1, 1, 1, 1)
    if shader then
        shader:send("plagueIntensity", intensity)
        love.graphics.setShader(shader)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
    else
        drawFallbackVignette(sw, sh, intensity)
    end
    love.graphics.pop()
end

return plague_senses
