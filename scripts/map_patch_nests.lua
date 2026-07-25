-- Courtyard art reset: one Victorian decaying plaza, three subtle districts.
-- Rebuilds Floor (cobble everywhere) + Decals/Props from dungeon_tiles only.
-- Keeps Fountain Layer stamp + Circle Colliders fountain ellipse exactly.
--
-- Run: love . -- --patch-nests

local M = {}

local MAP_W, MAP_H, TILE = 30, 24, 16

-- dungeon_tiles (firstgid 1) — props / soot / crack accents
local T = {
    floorDark = { 73, 74, 96, 97, 119, 120 },
    floorSoot = { 75, 98, 99, 121 },
    floorWet = { 73, 74, 96, 119 },
    crate = 172,
    crateTall = 173,
    chest = 171,
    barrel = 174,
    crateLow = 194,
    torch = 197,
    lintel = 149,
    ruin = { 260, 261, 283, 284 },
    pillar = 262,
    grate = 218,
    door = 150,
}

-- dungeon_tiles2 ornate cobble (firstgid 553) — 6×6 seamless family already on map
local COBBLE = {
    { 681, 682, 683, 684, 685, 686 },
    { 713, 714, 715, 716, 717, 718 },
    { 745, 746, 747, 748, 749, 750 },
    { 777, 778, 779, 780, 781, 782 },
    { 809, 810, 811, 812, 813, 814 },
    { 841, 842, 843, 844, 845, 846 },
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

--- Continuous ornate cobble; slight phase shifts break perfect tiling without biome cuts.
local function buildFloor()
    local data = blank()
    for row = 0, MAP_H - 1 do
        for col = 0, MAP_W - 1 do
            -- Soft district phase (1–2 tile feel), not a knife-edge biome.
            local ox, oy = 0, 0
            if col <= 10 then
                ox = 1
            elseif col >= 20 then
                oy = 1
            end
            if ((col + row) % 11) == 0 then
                ox = (ox + 1) % 6
            end
            local c = (col + ox) % 6
            local r = (row + oy) % 6
            data[idx(col, row)] = COBBLE[r + 1][c + 1]
        end
    end
    return data
end

--- Nest A "Ash Market" — west: denser soot/cracks on shared cobble.
local function buildDecalsA()
    local data = blank()
    -- Light soot across whole yard so top doesn't read as a clean separate zone.
    for row = 1, MAP_H - 2 do
        for col = 1, MAP_W - 2 do
            if not inFountain(col, row) and ((col * 7 + row * 13) % 17) == 0 then
                put(data, col, row, pick(T.floorSoot, col, row))
            end
        end
    end
    -- Dense ash market west / lower-left.
    for row = 6, 22 do
        for col = 1, 11 do
            local dens = (col <= 8) and 2 or 3
            if ((col * 3 + row * 7) % dens) == 0 then
                put(data, col, row, pick(T.floorSoot, col, row))
            elseif ((col + row) % 5) == 0 then
                put(data, col, row, pick(T.floorDark, col, row))
            end
        end
    end
    return data
end

--- Nest B "Plague Well" — soft wet/stain ring; keep combat ring readable.
local function buildDecalsB()
    local data = blank()
    local cx, cy = 14.5, 11.5
    for row = 7, 16 do
        for col = 10, 19 do
            if not inFountain(col, row) then
                local dx = (col + 0.5) - cx
                local dy = (row + 0.5) - cy
                local d2 = dx * dx + dy * dy
                if d2 >= 6 and d2 <= 28 then
                    put(data, col, row, pick(T.floorWet, col, row))
                elseif d2 > 28 and d2 <= 40 and ((col + row) % 3) == 0 then
                    put(data, col, row, pick(T.floorSoot, col, row))
                end
            end
        end
    end
    return data
end

--- Nest C "Watch Yard" — east: sparse dark runners + rare grate accents.
local function buildDecalsC()
    local data = blank()
    for row = 2, 8 do
        for col = 18, 28 do
            if ((col + row) % 5) == 0 then
                put(data, col, row, pick(T.floorDark, col, row))
            end
        end
    end
    for row = 8, 21 do
        for col = 20, 28 do
            if col == 24 or col == 25 then
                if (row % 4) == 0 then
                    put(data, col, row, T.grate)
                elseif (row % 2) == 0 then
                    put(data, col, row, pick(T.floorDark, col, row))
                end
            elseif ((col * 2 + row) % 9) == 0 then
                put(data, col, row, pick(T.floorDark, col, row))
            end
        end
    end
    return data
end

local function buildProps()
    local data = blank()

    -- Nest A: denser crates/barrels (market clutter), walkable lanes remain.
    local market = {
        { 2, 8, T.chest }, { 3, 8, T.barrel }, { 4, 9, T.crate },
        { 2, 10, T.crate }, { 3, 11, T.crateLow }, { 5, 12, T.barrel },
        { 2, 13, T.crateTall }, { 4, 14, T.crate }, { 3, 15, T.barrel },
        { 6, 9, T.crate }, { 7, 16, T.barrel }, { 2, 17, T.crateLow },
        { 5, 18, T.chest }, { 8, 19, T.barrel }, { 4, 20, T.crate },
        { 1, 14, T.barrel }, { 9, 12, T.crateLow }, { 6, 21, T.crate },
    }
    for _, p in ipairs(market) do
        put(data, p[1], p[2], p[3])
    end

    -- West ruin stubs (framing only — not a sealed chamber).
    put(data, 1, 7, pick(T.ruin, 1, 7))
    put(data, 2, 7, pick(T.ruin, 2, 7))
    put(data, 1, 8, pick(T.ruin, 1, 8))
    put(data, 1, 18, pick(T.ruin, 1, 18))
    put(data, 2, 18, pick(T.ruin, 2, 18))

    -- Light debris on top edge so north matches the courtyard mood.
    put(data, 4, 2, T.crate)
    put(data, 8, 3, T.barrel)
    put(data, 12, 1, T.crateLow)
    put(data, 18, 2, T.barrel)

    -- Nest B: open ring — one lone barrel south of the well.
    put(data, 15, 16, T.barrel)

    -- Nest C: sparse watch — few torches, gate fragment, open sightlines.
    put(data, 22, 4, T.torch)
    put(data, 27, 4, T.torch)
    put(data, 26, 10, T.torch)
    put(data, 22, 18, T.torch)
    put(data, 26, 6, T.lintel)
    put(data, 27, 6, T.pillar)
    put(data, 28, 6, T.door)
    put(data, 21, 3, T.pillar)
    put(data, 28, 3, T.pillar)
    put(data, 28, 16, T.crateLow)
    put(data, 23, 20, T.barrel)

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
        objects[#objects + 1] = rect(
            id,
            name,
            col * TILE,
            row * TILE,
            wTiles * TILE,
            hTiles * TILE
        )
        id = id + 1
    end

    -- Real solids only: ruin stubs + a couple market crates + watch pillars.
    add("ruin_a_nw", 1, 7, 2, 2)
    add("ruin_a_sw", 1, 18, 2, 1)
    add("market_block_a", 3, 11, 1, 1)
    add("market_block_b", 4, 14, 1, 1)
    add("market_block_c", 5, 18, 1, 1)
    add("watch_pillar_n", 21, 3, 1, 1)
    add("watch_pillar_ne", 28, 3, 1, 1)
    add("watch_pillar_e", 27, 6, 1, 1)

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

    add("nest_a", 4, 14, 2, 2, { nest = "a", cleanseRadius = 72, district = "Ash Market" })
    add("nest_b", 14, 11, 2, 2, { nest = "b", cleanseRadius = 80, district = "Plague Well" })
    add("nest_c", 24, 12, 2, 2, { nest = "c", cleanseRadius = 72, district = "Watch Yard" })

    add("player_start", 6, 16, 1, 1, {})

    add("spawn_chaser_a", 3, 9, 1, 1, { type = "chaser", nest = "a" })
    add("spawn_fleer_a", 7, 18, 1, 1, { type = "fleer", nest = "a" })
    add("spawn_keeper_b", 17, 8, 1, 1, { type = "keeper", nest = "b" })
    add("spawn_chaser_b", 12, 16, 1, 1, { type = "chaser", nest = "b" })
    add("spawn_ranger_c", 25, 8, 1, 1, { type = "ranger", nest = "c" })

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

--- Full courtyard reset: cobble floor + dungeon_tiles overlays; fountain untouched.
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
        nestB = "Plague Well",
        nestC = "Watch Yard",
        tilesetNote = "PRIMARY floors/walls/decay: dungeon_tiles + dungeon_tiles2 cobble. Districts = props/decals, not biomes.",
    }

    -- Primary tilesets only — unregister Kenney town/dungeon from this map.
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
    }

    map.layers = {
        floor,
        tileLayer(5, "Decals A", buildDecalsA()),
        tileLayer(6, "Decals B", buildDecalsB()),
        tileLayer(7, "Decals C", buildDecalsC()),
        tileLayer(8, "Props", buildProps()),
        fountain,
        circles,
        rects,
        objectLayer(9, "Spawns", spawns),
    }
    map.nextlayerid = 10
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
                        if not (row == MAP_H - 1 and col == MAP_W - 1) then
                            parts[#parts + 1] = ", "
                        end
                    end
                    parts[#parts + 1] = row < MAP_H - 1 and "\n" or "\n"
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
