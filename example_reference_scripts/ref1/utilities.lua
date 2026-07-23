function clamp(v, max, min)
    if v >= max then v = max end
    if v <= min then v = min end
    return v
end

function generateRotation()
    return math.random(0, 2 * math.pi)
end

function screenToTile(x, y, tileSize)
    local tileX = math.floor(x / tileSize) + 1
    local tileY = math.floor(y / tileSize) + 1
    return tileX, tileY
end

function tileToScreen(tileX, tileY, tileSize)
    local screenX = tileX * tileSize
    local screenY = tileY * tileSize
    return screenX, screenY
end
