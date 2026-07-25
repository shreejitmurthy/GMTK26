-- STI map loading and the explicit render/physics layer contract for this map.

local sti = require "lib.sti"

local game_map = {}

game_map.BELOW_ACTOR_LAYERS = {
    "Floor Layer",
}

game_map.PERSPECTIVE_ACTOR_LAYERS = {
    "Fountain Layer",
}

game_map.COLLIDER_LAYER_ORDER = {
    "Circle Colliders",
    "Rectangle Colliders",
}

local function normalizePath(path)
    local parts = {}
    path = path:gsub("\\", "/")

    for part in path:gmatch("[^/]+") do
        if part == ".." then
            table.remove(parts)
        elseif part ~= "." and part ~= "" then
            parts[#parts + 1] = part
        end
    end

    return table.concat(parts, "/")
end

local function directoryOf(path)
    return path:match("^(.*)/[^/]+$") or ""
end

local function joinPath(base, relative)
    if base == "" then
        return normalizePath(relative)
    end
    return normalizePath(base .. "/" .. relative)
end

local function decodeXml(value)
    return (value
        :gsub("&quot;", "\"")
        :gsub("&apos;", "'")
        :gsub("&lt;", "<")
        :gsub("&gt;", ">")
        :gsub("&amp;", "&"))
end

local function attributes(tag)
    local result = {}
    for key, quote, value in tag:gmatch(
        "([%w_:.-]+)%s*=%s*([\"'])(.-)%2"
    ) do
        result[key] = decodeXml(value)
    end
    return result
end

-- This STI release only accepts embedded tilesets. Hydrate this project's
-- simple external TSX tilesets before passing the Lua map table to STI.
local function loadExternalTileset(reference, mapDirectory)
    local tsxPath = joinPath(mapDirectory, reference.filename)
    local xml, readError = love.filesystem.read(tsxPath)
    assert(xml, string.format("Could not read tileset %s: %s", tsxPath, readError or "unknown error"))

    local tilesetTag = assert(
        xml:match("<tileset%s+([^>]-)>"),
        "Invalid TSX tileset: " .. tsxPath
    )
    local imageTag = assert(
        xml:match("<image%s+([^>]-)/?>"),
        "TSX tileset has no image: " .. tsxPath
    )
    local tilesetAttributes = attributes(tilesetTag)
    local imageAttributes = attributes(imageTag)
    local tileOffsetTag = xml:match("<tileoffset%s+([^>]-)/?>")
    local tileOffset = tileOffsetTag and attributes(tileOffsetTag) or {}

    assert(imageAttributes.source, "TSX tileset image has no source: " .. tsxPath)

    return {
        firstgid = reference.firstgid,
        name = tilesetAttributes.name or reference.name,
        tilewidth = assert(tonumber(tilesetAttributes.tilewidth), "TSX has no tilewidth: " .. tsxPath),
        tileheight = assert(tonumber(tilesetAttributes.tileheight), "TSX has no tileheight: " .. tsxPath),
        tilecount = assert(tonumber(tilesetAttributes.tilecount), "TSX has no tilecount: " .. tsxPath),
        columns = tonumber(tilesetAttributes.columns) or 0,
        spacing = tonumber(tilesetAttributes.spacing) or 0,
        margin = tonumber(tilesetAttributes.margin) or 0,
        image = joinPath(directoryOf(tsxPath), imageAttributes.source),
        imagewidth = assert(tonumber(imageAttributes.width), "TSX image has no width: " .. tsxPath),
        imageheight = assert(tonumber(imageAttributes.height), "TSX image has no height: " .. tsxPath),
        tileoffset = {
            x = tonumber(tileOffset.x) or 0,
            y = tonumber(tileOffset.y) or 0,
        },
        properties = {},
        terrains = {},
        tiles = {},
    }
end

local function loadMapTable(path)
    local chunk, loadError = love.filesystem.load(path)
    assert(chunk, string.format("Could not load map %s: %s", path, loadError or "unknown error"))

    local map = chunk()
    local mapDirectory = directoryOf(path)
    for index, tileset in ipairs(map.tilesets or {}) do
        if tileset.filename then
            map.tilesets[index] = loadExternalTileset(tileset, mapDirectory)
        end
    end
    return map
end

function game_map.load(path)
    local map = sti(loadMapTable(path))

    for _, layerNames in ipairs({
        game_map.BELOW_ACTOR_LAYERS,
        game_map.PERSPECTIVE_ACTOR_LAYERS,
    }) do
        for _, layerName in ipairs(layerNames) do
            local layer = assert(map.layers[layerName], "Map is missing tile layer: " .. layerName)
            assert(layer.type == "tilelayer", layerName .. " must be a tile layer")
        end
    end
    for _, layerName in ipairs(game_map.COLLIDER_LAYER_ORDER) do
        local layer = assert(map.layers[layerName], "Map is missing collider layer: " .. layerName)
        assert(layer.type == "objectgroup", layerName .. " must be an object layer")
    end

    return map
end

function game_map.addColliders(map, physics)
    local added = 0
    for _, layerName in ipairs(game_map.COLLIDER_LAYER_ORDER) do
        added = added + physics.addWallsFromObjects(map.layers[layerName].objects)
    end
    return added
end

function game_map.update(map, dt)
    map:update(dt)
end

local function drawLayers(map, layerNames)
    love.graphics.setColor(1, 1, 1, 1)
    for _, layerName in ipairs(layerNames) do
        local layer = map.layers[layerName]
        if layer.visible and layer.opacity > 0 then
            map:drawLayer(layer)
        end
    end
end

function game_map.drawBelowActors(map)
    drawLayers(map, game_map.BELOW_ACTOR_LAYERS)
end

function game_map.drawPerspectiveActors(map)
    drawLayers(map, game_map.PERSPECTIVE_ACTOR_LAYERS)
end

--- The bottom occupied tile row is the ground contact used for perspective.
function game_map.getLayerGroundDepth(map, layerName)
    local layer = assert(map.layers[layerName], "Map is missing tile layer: " .. layerName)
    local deepestOccupiedRow = nil

    for rowIndex, row in ipairs(layer.data) do
        if next(row) ~= nil then
            deepestOccupiedRow = rowIndex
        end
    end

    assert(deepestOccupiedRow, layerName .. " has no tiles to depth-sort")
    return (layer.y or 0) + deepestOccupiedRow * map.tileheight
end

--- Split actors around the fountain's ground contact: northern actors first,
--- then the fountain, then southern actors. Coordinated actor visuals provide
--- the same ground depth so scenery cannot split their internal draw order.
function game_map.drawWithActors(map, drawActors, context)
    assert(type(drawActors) == "function", "drawWithActors requires an actor draw function")

    game_map.drawBelowActors(map)

    local perspectiveLayerName = game_map.PERSPECTIVE_ACTOR_LAYERS[1]
    local fountainGroundDepth =
        game_map.getLayerGroundDepth(map, perspectiveLayerName)

    drawActors(context, fountainGroundDepth, false)
    game_map.drawPerspectiveActors(map)
    drawActors(context, fountainGroundDepth, true)
end

return game_map
