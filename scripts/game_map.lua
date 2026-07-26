-- STI map loading and the explicit render/physics layer contract for this map.

local sti = require "lib.sti"

local game_map = {}

-- Drawn under actors. Fountain is perspective-sorted with actors.
-- Decals A/B/C + Props are optional nest-district overlays on the plaza.
-- Floor/decals first, then solid bases + darkened Props/Walls so blockers read.
game_map.FLOOR_DECAL_LAYERS = {
    "Floor Layer",
    "Decals A",
    "Decals B",
    "Decals C",
}

game_map.SOLID_TILE_LAYERS = {
    "Props",
    -- Legacy / optional names
    "Walls Layer",
    "Props Layer",
}

-- Multiplicative draw tints (RGB). Cobble floor stays full-bright; solids darken.
game_map.LAYER_DRAW_TINT = {
    ["Props"] = { 0.55, 0.5, 0.46 },
    ["Props Layer"] = { 0.55, 0.5, 0.46 },
    ["Walls Layer"] = { 0.32, 0.3, 0.28 },
}

game_map.BELOW_ACTOR_LAYERS = {
    "Floor Layer",
    "Decals A",
    "Decals B",
    "Decals C",
    "Props",
    "Walls Layer",
    "Props Layer",
}

game_map.PERSPECTIVE_ACTOR_LAYERS = {
    "Fountain Layer",
}

game_map.COLLIDER_LAYER_ORDER = {
    "Circle Colliders",
    "Rectangle Colliders",
}

game_map.OPTIONAL_TILE_LAYERS = {
    "Decals A",
    "Decals B",
    "Decals C",
    "Props",
    "Walls Layer",
    "Props Layer",
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

local function objectCenter(object)
    if object.shape == "point" then
        return object.x, object.y
    end
    return object.x + (object.width or 0) * 0.5,
        object.y + (object.height or 0) * 0.5
end

local function property(object, key, default)
    local props = object.properties or {}
    local value = props[key]
    if value == nil then
        return default
    end
    return value
end

local function parseSpawns(map)
    local layer = map.layers["Spawns"]
    local spawns = {
        playerStart = nil,
        enemies = {},
        nests = {},
        all = {},
    }
    if not layer or layer.type ~= "objectgroup" then
        map.spawnData = spawns
        return spawns
    end

    for _, object in ipairs(layer.objects or {}) do
        local cx, cy = objectCenter(object)
        local entry = {
            name = object.name or "",
            type = property(object, "type"),
            nest = property(object, "nest"),
            cleanseRadius = tonumber(property(object, "cleanseRadius")),
            x = cx,
            y = cy,
            object = object,
        }
        spawns.all[#spawns.all + 1] = entry

        local name = entry.name
        if name == "player_start" then
            spawns.playerStart = entry
        elseif name == "nest_a" or name == "nest_b" or name == "nest_c" then
            local key = name:sub(-1) -- a|b|c
            spawns.nests[key] = entry
            spawns.nests[name] = entry
        elseif entry.type == "chaser"
            or entry.type == "fleer"
            or entry.type == "keeper"
            or entry.type == "ranger"
        then
            spawns.enemies[#spawns.enemies + 1] = entry
        end
    end

    map.spawnData = spawns
    return spawns
end

function game_map.load(path)
    local map = sti(loadMapTable(path))

    for _, layerName in ipairs(game_map.BELOW_ACTOR_LAYERS) do
        local layer = map.layers[layerName]
        if layer == nil then
            -- Walls/Props are optional for older maps; Floor is required.
            if layerName == "Floor Layer" then
                error("Map is missing tile layer: " .. layerName)
            end
        else
            assert(layer.type == "tilelayer", layerName .. " must be a tile layer")
        end
    end
    for _, layerName in ipairs(game_map.PERSPECTIVE_ACTOR_LAYERS) do
        local layer = assert(map.layers[layerName], "Map is missing tile layer: " .. layerName)
        assert(layer.type == "tilelayer", layerName .. " must be a tile layer")
    end
    for _, layerName in ipairs(game_map.COLLIDER_LAYER_ORDER) do
        local layer = assert(map.layers[layerName], "Map is missing collider layer: " .. layerName)
        assert(layer.type == "objectgroup", layerName .. " must be an object layer")
    end

    parseSpawns(map)
    return map
end

function game_map.getSpawnPoints(map)
    local data = map.spawnData or parseSpawns(map)
    return data
end

function game_map.getNests(map)
    local data = map.spawnData or parseSpawns(map)
    return data.nests
end

function game_map.getPlayerStart(map)
    local data = map.spawnData or parseSpawns(map)
    if data.playerStart then
        return data.playerStart.x, data.playerStart.y
    end
    return nil
end

--- Walkable AABB (map interior). Defaults to full map pixel bounds.
--- main.lua feeds this to physics.setPlayableArea + addBoundaryWalls so the
--- dynamic player cannot leave the tiled courtyard.
--- Optional map properties playableX/Y/W/H + wallThickness override.
function game_map.getPlayableArea(map)
    local props = map.properties or {}
    local x = tonumber(props.playableX)
    local y = tonumber(props.playableY)
    local w = tonumber(props.playableW)
    local h = tonumber(props.playableH)
    local thick = tonumber(props.wallThickness) or 16
    if not (x and y and w and h) then
        x = 0
        y = 0
        w = map.width * map.tilewidth
        h = map.height * map.tileheight
    end
    return {
        x = x,
        y = y,
        w = w,
        h = h,
        thickness = thick,
    }
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
    for _, layerName in ipairs(layerNames) do
        local layer = map.layers[layerName]
        if layer and layer.visible and layer.opacity > 0 then
            local tint = game_map.LAYER_DRAW_TINT[layerName]
            if tint then
                love.graphics.setColor(tint[1], tint[2], tint[3], 1)
            else
                love.graphics.setColor(1, 1, 1, 1)
            end
            map:drawLayer(layer)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

--- Dark footprints under Rectangle Colliders so every Wall solid has a silhouette
--- even when prop art is light against busy cobble. Torches/decals stay untinted.
function game_map.drawSolidBases(map)
    local layer = map.layers["Rectangle Colliders"]
    if not layer or not layer.objects then
        return
    end
    for _, object in ipairs(layer.objects) do
        local shape = object.shape
        if (not shape or shape == "rectangle")
            and (object.width or 0) > 0
            and (object.height or 0) > 0
        then
            local x, y = object.x, object.y
            local w, h = object.width, object.height
            -- Soft pad so the base reads larger/darker than the thin foot collider.
            -- Warm dark brown (not pitch black) so solids never read as abyss holes.
            local pad = 2
            love.graphics.setColor(0.16, 0.11, 0.08, 0.88)
            love.graphics.rectangle("fill", x - pad, y - pad - 4, w + pad * 2, h + pad * 2 + 5)
            love.graphics.setColor(0.08, 0.05, 0.04, 0.95)
            love.graphics.rectangle("line", x - pad, y - pad - 4, w + pad * 2, h + pad * 2 + 5)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function game_map.drawBelowActors(map)
    drawLayers(map, game_map.FLOOR_DECAL_LAYERS)
    game_map.drawSolidBases(map)
    drawLayers(map, game_map.SOLID_TILE_LAYERS)
end

--- Every rectangle Wall collider center must sit on a Props tile (no invisible walls).
function game_map.auditColliderPropCoverage(map)
    local props = map and map.layers and map.layers["Props"]
    local rects = map and map.layers and map.layers["Rectangle Colliders"]
    if not props or not rects or not rects.objects then
        return false, { "missing Props or Rectangle Colliders" }
    end
    local mismatches = {}
    for _, object in ipairs(rects.objects) do
        local shape = object.shape
        if (not shape or shape == "rectangle")
            and (object.width or 0) > 0
            and (object.height or 0) > 0
        then
            local cx = object.x + object.width * 0.5
            local cy = object.y + object.height * 0.5
            local col = math.floor(cx / map.tilewidth)
            local row = math.floor(cy / map.tileheight)
            local rowData = props.data and props.data[row + 1]
            local tile = rowData and rowData[col + 1]
            local gid = tile and (tile.gid or tile) or 0
            if type(gid) == "table" then
                gid = gid.gid or 0
            end
            if not gid or gid == 0 then
                mismatches[#mismatches + 1] = string.format(
                    "%s @ tile %d,%d (no Props gid)",
                    object.name or "wall",
                    col,
                    row
                )
            end
        end
    end
    return #mismatches == 0, mismatches
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

    -- Optional: abyss voids + crack telegraph after floor/decals/props.
    if context and context.onAfterFloor then
        context.onAfterFloor(context)
    end

    local perspectiveLayerName = game_map.PERSPECTIVE_ACTOR_LAYERS[1]
    local fountainGroundDepth =
        game_map.getLayerGroundDepth(map, perspectiveLayerName)

    drawActors(context, fountainGroundDepth, false)
    game_map.drawPerspectiveActors(map)
    drawActors(context, fountainGroundDepth, true)

    -- Optional: falling tile quads above scenery (does not split fountain sort).
    if context and context.onAfterActors then
        context.onAfterActors(context)
    end
end

return game_map
