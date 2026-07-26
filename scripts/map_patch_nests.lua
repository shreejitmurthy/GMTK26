-- Deterministic courtyard authoring source: one Victorian plague-city plaza.
-- Rebuilds Floor + district decals/props/walls and matching collision/spawns.
-- Keeps Fountain Layer stamp + Circle Colliders fountain ellipse exactly.
--
-- DESTRUCTIVE: this regenerates both map.tmx and map.lua. The generated TMX is
-- the canonical Tiled editing source afterward; do not rerun this reset over
-- later hand edits unless intentionally rebuilding the complete courtyard.
-- Run intentionally with: love . -- --patch-nests

local M = {}

local MAP_W, MAP_H, TILE = 30, 24, 16

-- dungeon_tiles (firstgid 1) — props / soot / crack accents
local T = {
    floorDark = { 264, 265, 266, 267, 268 },
    floorSoot = { 288 },
    floorWet = { 1591, 1592, 1593, 1594, 1595, 1596, 1597 },
    crate = 172,
    crateTall = 173,
    chest = 171,
    barrel = 174,
    crateLow = 194,
    torch = 197,
    lintel = 149,
    ruin = { 260, 261, 283, 284 },
    pillar = 262,
    grate = 159,
    door = 150,
    barricade = 218,
    wallTop = 50,
    wallBottom = 143,
    wallLeft = 62,
    wallRight = 63,
    wallCornerNW = 48,
    wallCornerNE = 56,
    wallCornerSW = 141,
    wallCornerSE = 145,
}

-- Daniel Siegmund grey cobbles (firstgid 1577) — packed 7×4 source crop.
local COBBLE = {
    { 1577, 1578, 1579, 1580, 1581, 1582, 1583 },
    { 1584, 1585, 1586, 1587, 1588, 1589, 1590 },
    { 1591, 1592, 1593, 1594, 1595, 1596, 1597 },
    { 1598, 1599, 1600, 1601, 1602, 1603, 1604 },
}

-- Fountain footprint (0-based) — do not cover with props/decals.
local FOUNTAIN = { c0 = 13, c1 = 16, r0 = 10, r1 = 13 }

local function idx(col, row)
    return row * MAP_W + col + 1
end

local function inFountain(col, row)
    return col >= FOUNTAIN.c0 and col <= FOUNTAIN.c1
        and row >= FOUNTAIN.r0 and row <= FOUNTAIN.r1
end

local function blank()
    local data = {}
    for i = 1, MAP_W * MAP_H do
        data[i] = 0
    end
    return data
end

local function pick(list, col, row)
    return list[1 + ((col * 5 + row * 11) % #list)]
end

local function put(data, col, row, gid)
    if col < 0 or col >= MAP_W or row < 0 or row >= MAP_H then
        return
    end
    if inFountain(col, row) then
        return
    end
    data[idx(col, row)] = gid
end

--- One continuous muted cobble foundation across all three districts.
local function buildFloor()
    local data = blank()
    for row = 0, MAP_H - 1 do
        for col = 0, MAP_W - 1 do
            local cobbleRow = COBBLE[(row % #COBBLE) + 1]
            data[idx(col, row)] = cobbleRow[(col % #cobbleRow) + 1]
        end
    end
    return data
end

--- Ash Market: restrained soot clusters, heavier near the SW nest and west wall.
local function buildDecalsA()
    local data = blank()
    for row = 2, MAP_H - 3 do
        for col = 1, 10 do
            -- Nest A sits SW at ~col 3–4, row 16–17.
            local nearNest = math.abs(col - 3.5) + math.abs(row - 16.5) <= 5
            local boundaryDecay = col <= 2 or row >= 20
            local modulus = (nearNest or boundaryDecay) and 5 or 9
            -- Soot only — dark floor chips read as fake walls on busy cobble.
            if ((col * 5 + row * 7) % modulus) == 0 then
                put(data, col, row, pick(T.floorSoot, col, row))
            elseif nearNest and ((col + row * 2) % 7) == 0 then
                put(data, col, row, pick(T.floorSoot, col, row))
            end
        end
    end
    -- A few shared stains prevent a hard visual seam between districts.
    for _, p in ipairs({ { 11, 5 }, { 9, 9 }, { 12, 18 }, { 7, 3 } }) do
        put(data, p[1], p[2], pick(T.floorSoot, p[1], p[2]))
    end
    return data
end

--- Plague Well wet ring (landmark) + SE Drain Court nest stains.
local function buildDecalsB()
    local data = blank()
    local cx, cy = 15, 12
    for row = 6, 17 do
        for col = 9, 20 do
            if not inFountain(col, row) then
                local dx = (col + 0.5) - cx
                local dy = (row + 0.5) - cy
                local d2 = dx * dx + dy * dy
                if d2 >= 9 and d2 <= 32 and ((col + row) % 3 ~= 0) then
                    put(data, col, row, pick(T.floorWet, col, row))
                elseif d2 > 32 and d2 <= 46 and ((col + row) % 5) == 0 then
                    put(data, col, row, pick(T.floorSoot, col, row))
                end
            end
        end
    end
    -- Drainage run toward SE Drain Court nest (~col 21–22, row 18–19).
    for row = 15, 20, 2 do
        put(data, 18, row, T.grate)
    end
    for row = 17, 21 do
        for col = 19, 24 do
            local nearDrain = math.abs(col - 21.5) + math.abs(row - 18.5) <= 4
            if nearDrain and ((col + row) % 3) == 0 then
                put(data, col, row, pick(T.floorWet, col, row))
            end
        end
    end
    return data
end

--- Watch Yard: straight drainage/soot lines; scorched ring around NE warning pyre.
local function buildDecalsC()
    local data = blank()
    for row = 2, 21 do
        for col = 20, 28 do
            -- Nest C sits NE at ~col 25–26, row 5–6.
            local nearNest = math.abs(col - 25.5) + math.abs(row - 5.5) <= 5
            local atBoundary = col >= 27 or row <= 3
            if (nearNest or atBoundary) and ((col * 3 + row * 5) % 7) == 0 then
                put(data, col, row, pick(T.floorSoot, col, row))
            end
        end
    end
    for row = 6, 20, 3 do
        put(data, 21, row, T.grate)
    end
    for col = 22, 27, 2 do
        put(data, col, 18, pick(T.floorSoot, col, 18))
    end
    return data
end

--- Visible masonry occupies the same one-tile rim as the runtime boundary walls.
local function buildWalls()
    local data = blank()
    for col = 0, MAP_W - 1 do
        put(data, col, 0, col == 0 and T.wallCornerNW
            or (col == MAP_W - 1 and T.wallCornerNE or T.wallTop))
        put(data, col, MAP_H - 1, col == 0 and T.wallCornerSW
            or (col == MAP_W - 1 and T.wallCornerSE or T.wallBottom))
    end
    for row = 1, MAP_H - 2 do
        put(data, 0, row, T.wallLeft)
        put(data, MAP_W - 1, row, T.wallRight)
    end
    return data
end

local function buildProps()
    local data = blank()

    -- Ash Market: northern stall ruin + SW ash-heap nest site (walkable center).
    local market = {
        -- Burned stall shell (north landmark).
        { 2, 6, T.ruin[1] }, { 3, 6, T.ruin[2] },
        { 4, 6, T.ruin[3] }, { 5, 6, T.ruin[4] },
        -- Mid-west abandoned load (approach cue toward SW nest).
        { 2, 12, T.chest }, { 3, 12, T.barrel },
        -- Nest A ash heap — crates/ruins ring the site; center stays open.
        { 2, 15, T.crateLow }, { 5, 15, T.barrel },
        { 1, 17, T.ruin[1] }, { 5, 17, T.crateLow },
        { 2, 18, T.barrel }, { 3, 18, T.crateLow }, { 4, 18, T.ruin[3] },
    }
    for _, p in ipairs(market) do
        put(data, p[1], p[2], p[3])
    end

    -- Plague Well: four small offering lights; the complete combat ring stays open.
    put(data, 11, 8, T.torch)
    put(data, 18, 8, T.torch)
    put(data, 11, 16, T.torch)
    put(data, 18, 16, T.torch)

    -- Watch Yard: gate posts + NE warning-pyre nest + southern supply.
    put(data, 21, 4, T.pillar)
    put(data, 28, 4, T.pillar)
    put(data, 22, 5, T.torch)
    put(data, 27, 5, T.torch)
    -- Nest C pyre shrine (NE) — frame the open channel pad; do not cover its center.
    put(data, 24, 4, T.torch)
    put(data, 26, 4, T.torch)
    put(data, 25, 3, T.pillar)
    put(data, 24, 7, T.crateLow)
    put(data, 26, 7, T.barrel)
    for col = 23, 25 do
        put(data, col, 9, T.barricade)
    end
    for row = 12, 14 do
        put(data, 27, row, T.pillar)
    end
    put(data, 26, 10, T.torch)
    put(data, 22, 17, T.crateLow)
    put(data, 23, 17, T.barrel)

    -- Drain Court (SE district nest) — wet ruin ring; center pad stays open.
    put(data, 20, 18, T.barrel)
    put(data, 23, 18, T.crateLow)
    put(data, 20, 20, T.ruin[2])
    put(data, 23, 20, T.ruin[4])
    put(data, 24, 19, T.torch)

    return data
end

local function rect(id, name, x, y, w, h, properties)
    return {
        id = id,
        name = name or "",
        type = "",
        shape = "rectangle",
        x = x,
        y = y,
        width = w,
        height = h,
        rotation = 0,
        visible = true,
        properties = properties or {},
    }
end

local function buildRectangleColliders(startId)
    local objects = {}
    local id = startId
    local function add(name, col, row, wTiles, hTiles)
        local insetX, insetY = 2, 3
        objects[#objects + 1] = rect(
            id,
            name,
            col * TILE + insetX,
            row * TILE + insetY,
            wTiles * TILE - insetX * 2,
            hTiles * TILE - insetY - 2
        )
        id = id + 1
    end

    -- Every rectangle corresponds to the complete visible prop cluster above.
    add("market_burned_stall", 2, 6, 4, 1)
    add("market_abandoned_load", 2, 12, 2, 1)
    -- Ash-heap ring (does not cover nest center pad).
    add("market_ash_crate_n", 2, 15, 1, 1)
    add("market_ash_barrel_n", 5, 15, 1, 1)
    add("market_ash_ruin_w", 1, 17, 1, 1)
    add("market_ash_crate_e", 5, 17, 1, 1)
    add("market_ash_heap_s", 2, 18, 3, 1)
    add("watch_gate_post_w", 21, 4, 1, 1)
    add("watch_gate_post_e", 28, 4, 1, 1)
    add("watch_pyre_post", 25, 3, 1, 1)
    add("watch_pyre_torch_w", 24, 4, 1, 1)
    add("watch_pyre_torch_e", 26, 4, 1, 1)
    add("watch_pyre_crate_w", 24, 7, 1, 1)
    add("watch_pyre_crate_e", 26, 7, 1, 1)
    add("watch_barricade_n", 23, 9, 3, 1)
    add("watch_barricade_e", 27, 12, 1, 3)
    add("watch_supply", 22, 17, 2, 1)
    add("drain_barrel_w", 20, 18, 1, 1)
    add("drain_crate_e", 23, 18, 1, 1)
    add("drain_ruin_sw", 20, 20, 1, 1)
    add("drain_ruin_se", 23, 20, 1, 1)

    return objects, id
end

local function buildSpawns(startId)
    local objects = {}
    local id = startId
    local function add(name, col, row, wTiles, hTiles, properties)
        objects[#objects + 1] = rect(
            id,
            name,
            col * TILE,
            row * TILE,
            (wTiles or 1) * TILE,
            (hTiles or 1) * TILE,
            properties
        )
        id = id + 1
    end

    -- 3 district nests scattered (SW / NE / SE) + locked Plague Well on the fountain.
    add("nest_a", 3, 16, 2, 2, { nest = "a", cleanseRadius = 36, district = "Ash Market" })
    add("nest_b", 21, 18, 2, 2, { nest = "b", cleanseRadius = 36, district = "Ossuary" })
    add("nest_c", 25, 5, 2, 2, { nest = "c", cleanseRadius = 40, district = "Watch Yard" })
    add("nest_well", 14, 11, 2, 2, {
        nest = "well",
        cleanseRadius = 40,
        district = "Plague Well",
        lockedUntilDistricts = true,
    })

    add("player_start", 14, 20, 1, 1, {})

    -- Openers clustered on district potions (a bit denser for contest).
    add("spawn_chaser_a", 3, 13, 1, 1, { type = "chaser", nest = "a" })
    add("spawn_fleer_a", 7, 19, 1, 1, { type = "fleer", nest = "a" })
    add("spawn_keeper_a", 5, 15, 1, 1, { type = "keeper", nest = "a" })
    add("spawn_keeper_b", 18, 16, 1, 1, { type = "keeper", nest = "b" })
    add("spawn_chaser_b", 24, 19, 1, 1, { type = "chaser", nest = "b" })
    add("spawn_fleer_b", 20, 20, 1, 1, { type = "fleer", nest = "b" })
    add("spawn_ranger_c", 22, 6, 1, 1, { type = "ranger", nest = "c" })
    add("spawn_chaser_c", 26, 8, 1, 1, { type = "chaser", nest = "c" })

    return objects, id
end

local function tileLayer(id, name, data)
    return {
        type = "tilelayer",
        x = 0,
        y = 0,
        width = MAP_W,
        height = MAP_H,
        id = id,
        name = name,
        class = "",
        visible = true,
        opacity = 1,
        offsetx = 0,
        offsety = 0,
        parallaxx = 1,
        parallaxy = 1,
        properties = {},
        encoding = "lua",
        data = data,
    }
end

local function objectLayer(id, name, objects)
    return {
        type = "objectgroup",
        draworder = "topdown",
        id = id,
        name = name,
        class = "",
        visible = true,
        opacity = 1,
        offsetx = 0,
        offsety = 0,
        parallaxx = 1,
        parallaxy = 1,
        properties = {},
        objects = objects,
    }
end

local function findLayer(map, name)
    for i, layer in ipairs(map.layers) do
        if layer.name == name then
            return layer, i
        end
    end
    return nil, nil
end

local function removeLayer(map, name)
    local _, i = findLayer(map, name)
    if i then
        table.remove(map.layers, i)
    end
end

--- Full authored courtyard rebuild; fountain stamp and ellipse remain untouched.
function M.patch(map)
    assert(map and map.layers, "map_patch_nests.patch requires a map table")
    local floor = assert(findLayer(map, "Floor Layer"), "Floor Layer missing")
    local fountain = assert(findLayer(map, "Fountain Layer"), "Fountain Layer missing")
    local circles = assert(findLayer(map, "Circle Colliders"), "Circle Colliders missing")
    assert(floor.type == "tilelayer" and fountain.type == "tilelayer")

    -- Preserve fountain ellipse object bytes (position/size).
    local fountainEllipse = circles.objects and circles.objects[1]
    assert(fountainEllipse, "Circle Colliders missing fountain ellipse")

    for _, name in ipairs({
        "Decals A", "Decals B", "Decals C", "Props",
        "Walls Layer", "Props Layer", "Spawns",
    }) do
        removeLayer(map, name)
    end
    local rects = findLayer(map, "Rectangle Colliders")
    if not rects then
        error("Rectangle Colliders missing")
    end

    floor.data = buildFloor()

    local nextId = 2
    local rectObjects, nextId2 = buildRectangleColliders(nextId)
    rects.objects = rectObjects
    local spawns, lastId = buildSpawns(nextId2)

    map.properties = {
        sector = "infested_courtyard",
        nestA = "Ash Market",
        nestB = "Ossuary",
        nestC = "Watch Yard",
        nestWell = "Plague Well",
        playableX = TILE,
        playableY = TILE,
        playableW = (MAP_W - 2) * TILE,
        playableH = (MAP_H - 2) * TILE,
        wallThickness = TILE,
        tilesetNote = "One cobble court; seal 3 district nests, then cleanse the locked Plague Well fountain.",
    }

    -- Two existing prop/fountain sheets plus one credited cobblestone sheet.
    map.tilesets = {
        {
            name = "dungeon_tiles",
            firstgid = 1,
            filename = "dungeon_tiles.tsx",
        },
        {
            name = "dungeon_tiles2",
            firstgid = 553,
            filename = "dungeon_tiles2.tsx",
        },
        {
            name = "victorian_cobbles",
            firstgid = 1577,
            filename = "victorian_cobbles.tsx",
        },
    }

    map.layers = {
        floor,
        tileLayer(5, "Decals A", buildDecalsA()),
        tileLayer(6, "Decals B", buildDecalsB()),
        tileLayer(7, "Decals C", buildDecalsC()),
        tileLayer(8, "Props", buildProps()),
        tileLayer(10, "Walls Layer", buildWalls()),
        fountain,
        circles,
        rects,
        objectLayer(9, "Spawns", spawns),
    }
    map.nextlayerid = 11
    map.nextobjectid = lastId

    if circles.objects[1] and (circles.objects[1].name == nil or circles.objects[1].name == "") then
        circles.objects[1].name = "fountain"
    end

    return map
end

-- --- serialization (minimal, Tiled-compatible) ---------------------------------

local function serializeValue(value, indent)
    indent = indent or 0
    local pad = string.rep("  ", indent)
    local pad1 = string.rep("  ", indent + 1)
    local t = type(value)
    if t == "string" then
        return string.format("%q", value)
    elseif t == "number" then
        if value == math.floor(value) then
            return string.format("%d", value)
        end
        return tostring(value)
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "table" then
        if #value > 0 then
            local allNumbers = true
            for i = 1, #value do
                if type(value[i]) ~= "number" then
                    allNumbers = false
                    break
                end
            end
            if allNumbers and #value == MAP_W * MAP_H then
                local parts = { "{\n" }
                for row = 0, MAP_H - 1 do
                    parts[#parts + 1] = pad1
                    for col = 0, MAP_W - 1 do
                        parts[#parts + 1] = tostring(value[idx(col, row)])
                        if col < MAP_W - 1 then
                            parts[#parts + 1] = ", "
                        elseif row < MAP_H - 1 then
                            parts[#parts + 1] = ","
                        end
                    end
                    parts[#parts + 1] = "\n"
                end
                parts[#parts + 1] = pad .. "}"
                return table.concat(parts)
            end
            local parts = { "{\n" }
            for i, v in ipairs(value) do
                parts[#parts + 1] = pad1 .. serializeValue(v, indent + 1)
                parts[#parts + 1] = i < #value and ",\n" or "\n"
            end
            parts[#parts + 1] = pad .. "}"
            return table.concat(parts)
        end
        local preferred = {
            "version", "luaversion", "tiledversion", "class", "orientation",
            "renderorder", "width", "height", "tilewidth", "tileheight",
            "nextlayerid", "nextobjectid", "properties", "tilesets", "layers",
            "type", "x", "y", "id", "name", "visible", "opacity", "offsetx",
            "offsety", "parallaxx", "parallaxy", "encoding", "data", "draworder",
            "objects", "firstgid", "filename", "shape", "rotation", "width",
            "height",
        }
        local seenPref = {}
        local ordered = {}
        for _, k in ipairs(preferred) do
            if value[k] ~= nil and not seenPref[k] then
                ordered[#ordered + 1] = k
                seenPref[k] = true
            end
        end
        local keys = {}
        for k in pairs(value) do
            if not seenPref[k] then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            ordered[#ordered + 1] = k
        end
        local parts = { "{\n" }
        for i, k in ipairs(ordered) do
            local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k
                or ("[" .. serializeValue(k) .. "]")
            parts[#parts + 1] = pad1 .. key .. " = " .. serializeValue(value[k], indent + 1)
            parts[#parts + 1] = i < #ordered and ",\n" or "\n"
        end
        parts[#parts + 1] = pad .. "}"
        return table.concat(parts)
    end
    error("unsupported " .. t)
end

local function escapeXml(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;"))
end

local function propertiesXml(properties, indent)
    if not properties or next(properties) == nil then
        return ""
    end
    local pad = string.rep(" ", indent)
    local parts = { pad .. "<properties>\n" }
    local keys = {}
    for k in pairs(properties) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = properties[k]
        local typeAttr = ""
        if type(v) == "number" then
            typeAttr = (v == math.floor(v)) and " type=\"int\"" or " type=\"float\""
        elseif type(v) == "boolean" then
            typeAttr = " type=\"bool\""
            v = v and "true" or "false"
        end
        parts[#parts + 1] = string.format(
            "%s <property name=\"%s\"%s value=\"%s\"/>\n",
            pad, escapeXml(k), typeAttr, escapeXml(v)
        )
    end
    parts[#parts + 1] = pad .. "</properties>\n"
    return table.concat(parts)
end

local function layerDataCsv(data)
    local lines = {}
    for row = 0, MAP_H - 1 do
        local cells = {}
        for col = 0, MAP_W - 1 do
            cells[#cells + 1] = tostring(data[idx(col, row)])
        end
        lines[#lines + 1] = table.concat(cells, ",") .. (row < MAP_H - 1 and "," or "")
    end
    return table.concat(lines, "\n")
end

function M.toTmx(map)
    local parts = {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
        string.format(
            "<map version=\"1.10\" tiledversion=\"1.10.2\" orientation=\"orthogonal\" renderorder=\"right-down\" width=\"%d\" height=\"%d\" tilewidth=\"%d\" tileheight=\"%d\" infinite=\"0\" nextlayerid=\"%d\" nextobjectid=\"%d\">\n",
            map.width, map.height, map.tilewidth, map.tileheight,
            map.nextlayerid, map.nextobjectid
        ),
        propertiesXml(map.properties, 1),
        " <tileset firstgid=\"1\" source=\"dungeon_tiles.tsx\"/>\n",
        " <tileset firstgid=\"553\" source=\"dungeon_tiles2.tsx\"/>\n",
        " <tileset firstgid=\"1577\" source=\"victorian_cobbles.tsx\"/>\n",
    }
    for _, layer in ipairs(map.layers) do
        if layer.type == "tilelayer" then
            parts[#parts + 1] = string.format(
                " <layer id=\"%d\" name=\"%s\" width=\"%d\" height=\"%d\">\n",
                layer.id, escapeXml(layer.name), layer.width, layer.height
            )
            parts[#parts + 1] = "  <data encoding=\"csv\">\n"
            parts[#parts + 1] = layerDataCsv(layer.data) .. "\n"
            parts[#parts + 1] = "  </data>\n </layer>\n"
        else
            parts[#parts + 1] = string.format(
                " <objectgroup id=\"%d\" name=\"%s\">\n",
                layer.id, escapeXml(layer.name)
            )
            for _, object in ipairs(layer.objects or {}) do
                parts[#parts + 1] = string.format(
                    "  <object id=\"%d\" name=\"%s\" x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\">\n",
                    object.id, escapeXml(object.name or ""),
                    object.x, object.y, object.width, object.height
                )
                if object.shape == "ellipse" then
                    parts[#parts + 1] = "   <ellipse/>\n"
                end
                parts[#parts + 1] = propertiesXml(object.properties, 3)
                parts[#parts + 1] = "  </object>\n"
            end
            parts[#parts + 1] = " </objectgroup>\n"
        end
    end
    parts[#parts + 1] = "</map>\n"
    return table.concat(parts)
end

local function resolvePath(relative)
    if love and love.filesystem and love.filesystem.getSource then
        local source = love.filesystem.getSource()
        if source and source ~= "" then
            local sep = package.config:sub(1, 1)
            return source .. sep .. relative:gsub("[/\\]", sep)
        end
    end
    return relative
end

local function writeFile(path, body)
    local f, err = io.open(path, "wb")
    assert(f, err or path)
    f:write(body)
    f:close()
end

function M.write(luaPath, tmxPath)
    local relLua = luaPath or "res/maps/map.lua"
    local relTmx = tmxPath or "res/maps/map.tmx"
    luaPath = resolvePath(relLua)
    tmxPath = resolvePath(relTmx)

    local chunk
    if love and love.filesystem then
        chunk = assert(love.filesystem.load(relLua:gsub("\\", "/")))
    else
        chunk = assert(loadfile(luaPath))
    end
    local map = chunk()
    M.patch(map)

    writeFile(luaPath, "return " .. serializeValue(map) .. "\n")
    writeFile(tmxPath, M.toTmx(map))
    return map, luaPath, tmxPath
end

--- Acceptance helper: count Floor Layer gid-0 cells (must be 0).
function M.countEmptyFloor(map)
    local floor = findLayer(map, "Floor Layer")
    if not floor then
        return -1
    end
    local n = 0
    for i = 1, #floor.data do
        if floor.data[i] == 0 then
            n = n + 1
        end
    end
    return n
end

return M
