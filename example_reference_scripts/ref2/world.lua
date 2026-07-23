sti = require "lib.sti"

world = wf.newWorld(0, 600, true)
world:addCollisionClass("Player")
world:addCollisionClass("Ground")
world:addCollisionClass("Look_Floor")
world:addCollisionClass("NoLook_Platform")

gameMap = sti("res/maps/test.lua")

tile_size = 8
map_width = gameMap.layers["Platform"].width * tile_size
map_height = gameMap.layers["Platform"].height * tile_size

function drawMapBorders()
    love.graphics.setColor(0, 0, 0.8)
    love.graphics.setLineWidth(0.25)
    love.graphics.line(0, 0, 0, gameMap.layers["Platform"].height * 8)
    love.graphics.line(0, map_height, map_width, gameMap.layers["Platform"].height * 8)
    love.graphics.line(map_width, map_height, map_width, 0)
    love.graphics.line(map_width, 0, 0, 0)
    love.graphics.setLineWidth(1)
end

function createCollidable(object, collisionClass)
    local collidable

    if object.shape == "rectangle" then
        collidable = world:newRectangleCollider(
            object.x, object.y,
            object.width, object.height
        )
    elseif object.shape == "polygon" then
        local verts = {}
        for _, v in ipairs(object.polygon) do
            verts[#verts+1] = v.x
            verts[#verts+1] = v.y
        end
        collidable = world:newPolygonCollider(verts)
    end

    if not collidable then return end

    collidable:setType("static")
    collidable:setCollisionClass(collisionClass)
    collidable:setObject(collidable)

    -- **per–tile state**  
    collidable.isFound = false

    -- install per–tile preSolve
    local prefix = collisionClass:match("^(.-)_")
    if prefix == "Look" or prefix == "NoLook" then
        local isLook = (prefix == "Look")
        collidable:setSensor(true)
        -- collidable:setPreSolve(function(selfCol, otherCol, contact)
        --     -- only care when Player hits this tile
        --     if otherCol.collision_class ~= "Player" then return end

        --     -- enable only if this tile’s isFound matches the rule
        --     if isLook then
        --         contact:setEnabled(selfCol.isFound)
        --     else
        --         contact:setEnabled(not selfCol.isFound)
        --     end
        -- end)
    end

    return collidable
end


function processLayer(layerName, collisionClass)
    if gameMap.layers[layerName] then
        for _, object in pairs(gameMap.layers[layerName].objects) do
            local collidable = createCollidable(object, collisionClass)
            if collidable then
                collidables[#collidables+1] = collidable
            end
        end
    end
end

function initMap()
    collidables = {}

    processLayer("Ground", "Ground")
    processLayer("Look_Floor", "Look_Floor")
    processLayer("NoLook_Platform", "NoLook_Platform")

    -- if gameMap.layers["Climbable"] then
    --     for _, object in pairs(gameMap.layers["Climbable"].objects) do
    --         if object.shape == "rectangle" then
    --             local zone = newZone(object.x, object.y, object.width, object.height)
    --             zone:addType("pole")
    --         end
    --     end
    -- end
end

function drawMap()
    gameMap:drawLayer(gameMap.layers["Background"])
    gameMap:drawLayer(gameMap.layers["Platform"])
end

function drawScene(canvas, shader, func)
    love.graphics.setCanvas(canvas)
    love.graphics.clear()
    cam:attach()
        func()
    cam:detach()
    love.graphics.setCanvas()

    love.graphics.setShader(shader)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, 0, 0)
    love.graphics.setShader()
end