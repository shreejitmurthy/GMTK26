require "lib.animate_class"
require "scripts.utilities"

System = {}

local zoom = 1.75
ZOOM_MULT = 0.1
ZOOM_MAX = 2.75
ZOOM_MIN = 0.75

local function addDebugData(components, format, ...)
    local str = string.format(format, ...)
    components[#components+1] = str
end

local debug_key
local debug_bool = true

function System.debugSystem(entity, x, y)
    local e = "E-" .. entity.ID
    local debug = ECSManager:get(entity.ID, ComponentType.DEBUG)
    if debug then
        debug_key = debug.key

        if debug_bool then
            local pos = ECSManager:get(entity.ID, ComponentType.POSITION)
            local velocity = ECSManager:get(entity.ID, ComponentType.VELOCITY)
            local player_cam = ECSManager:get(entity.ID, ComponentType.CAMERA)
            local maxWidth = 0
            local lineHeight = font:getHeight()
            local padding = 5

            love.graphics.setFont(font)

            local components = {}
            if pos then
                local screenX, screenY = math.floor(pos.x), math.floor(pos.y)
                local tileX, tileY = screenToTile(screenX, screenY, 24)
                local mouseX, mouseY = cam:mousePosition()
                local tmouseX, tmouseY = screenToTile(mouseX, mouseY, 24)

                addDebugData(components, "%s pos {", e)
                addDebugData(components, "\tscreen (x=%d, y=%d)", screenX, screenY)
                addDebugData(components, "\ttile (x=%d, y=%d)", tileX, tileY)
                addDebugData(components, "\tmouse (x=%d, y=%d)", mouseX, mouseY)
                addDebugData(components, "\ttmouse (x=%d, y=%d)", tmouseX, tmouseY)
                addDebugData(components, "} -----------")

            end
            if velocity then
                addDebugData(components, "%s vel {", e)
                addDebugData(components, "\tv (%d, %d)", math.floor(velocity.dx), math.floor(velocity.dy))
                addDebugData(components, "\tdir (%d, %d)", velocity.dir.x, velocity.dir.y)
                addDebugData(components, "} -----------")
            end

            if player_cam and pos then
                addDebugData(components, "%s cam {", e)
                addDebugData(components, "\tpos (x=%d, y=%d)", math.floor(pos.x + (player_cam.offsetX or 0)), math.floor(pos.y + (player_cam.offsetY or 0)))
                addDebugData(components, "\tzoom (%.2f)", player_cam.zoom)
                addDebugData(components, "} -----------")
            end

            -- required size of the debug box
            for _, str in ipairs(components) do
                local textWidth = font:getWidth(str)
                maxWidth = math.max(maxWidth, textWidth)
            end

            -- background rectangle
            if #components > 0 then
                local boxWidth = maxWidth + padding * 2
                local boxHeight = #components * lineHeight + padding * 2
                love.graphics.setColor(0, 0, 0, 0.5)
                love.graphics.rectangle("fill", x - padding, y - padding, boxWidth, boxHeight)
                love.graphics.setColor(0, 0, 0, 0.8)
                love.graphics.rectangle("line", x - padding, y - padding, boxWidth, boxHeight)
                love.graphics.setColor(1, 1, 1, 1)

                for i, str in ipairs(components) do
                    love.graphics.print(str, x, y + ((i-1) * lineHeight))
                end
            end
        end
    end
end

---@param entity Entity
function System.renderSystem(entity)
    local pos = ECSManager:get(entity.ID, ComponentType.POSITION)
    local sprite = ECSManager:get(entity.ID, ComponentType.SPRITE)
    local anim = ECSManager:get(entity.ID, ComponentType.ANIMATION)
    local scale = ECSManager:get(entity.ID, ComponentType.SCALE)
    local s = scale or 1

    
    if pos then
        if sprite then
            local shared_img = sprite.image
            love.graphics.push()
            love.graphics.scale(s)
            love.graphics.draw(shared_img, pos.x/s, pos.y/s)
            love.graphics.draw(sprite.image, pos.x/s, pos.y/s)
            love.graphics.pop()
        end
        if anim then
            anim.current_animation:Animate(pos.x, pos.y, s)
        end
        love.graphics.draw(hover_tile, hoverX, hoverY)
    end

    if debug_bool then
        world:draw(0.5)
    end
end


---@param entity Entity
function System.controllerSystem(entity, dt)
    local controls = ECSManager:get(entity.ID, ComponentType.CONTROLLER)
    local pos = ECSManager:get(entity.ID, ComponentType.POSITION)
    local velocity = ECSManager:get(entity.ID, ComponentType.VELOCITY)
    local anim = ECSManager:get(entity.ID, ComponentType.ANIMATION)
    local player_cam = ECSManager:get(entity.ID, ComponentType.CAMERA)
    local collider = ECSManager:get(entity.ID, ComponentType.COLLIDER)

    mouseX, mouseY = cam:mousePosition()
    tileX, tileY = screenToTile(mouseX, mouseY, 24)
    hoverX, hoverY = tileToScreen(tileX - 1, tileY - 1, 24)

    if pos and controls then

        if velocity then
            
            velocity.dx, velocity.dy = 0, 0

            if love.keyboard.isDown(controls.up) then
                velocity.dy = -1
                velocity.dir.x = 0
                velocity.dir.y = -1
            elseif love.keyboard.isDown(controls.down) then
                velocity.dy = 1
                velocity.dir.x = 0
                velocity.dir.y = 1
            end

            if love.keyboard.isDown(controls.left) then
                velocity.dx = -1
                velocity.dir.x = -1
                velocity.dir.y = 0
            elseif love.keyboard.isDown(controls.right) then
                velocity.dx = 1
                velocity.dir.x = 1
                velocity.dir.y = 0
            end
            
            -- pos.x = pos.x + velocity.dx * dt
            -- pos.y = pos.y + velocity.dy * dt
            
            local length = math.sqrt(velocity.dx^2 + velocity.dy^2)
            if length > 0 then
                velocity.dx = (velocity.dx / length) * velocity.speed
                velocity.dy = (velocity.dy / length) * velocity.speed
            end

            if collider then 
                collider.body:setLinearVelocity(velocity.dx, velocity.dy)
                pos.x = collider.body:getX() + (collider.offsetX or 0)
                pos.y = collider.body:getY() + (collider.offsetY or 0)
            end
            
            if anim then
                frameWidth, frameHeight = anim.current_animation.dimensions.width, anim.current_animation.dimensions.height
                if velocity.dx == 0 and velocity.dy == 0 then
                    if velocity.dir.y == -1 then
                        anim.current_animation = anim.animations.idle.up
                    end
                    if velocity.dir.y == 1 then
                        anim.current_animation = anim.animations.idle.down
                    end
                    if velocity.dir.x == -1 then
                        anim.current_animation = anim.animations.idle.left
                    end
                    if velocity.dir.x == 1 then
                        anim.current_animation = anim.animations.idle.right
                    end
                else
                    if velocity.dir.y == -1 then
                        anim.current_animation = anim.animations.walk.up
                    end
                    if velocity.dir.y == 1 then
                        anim.current_animation = anim.animations.walk.down
                    end
                    if velocity.dir.x == -1 then
                        anim.current_animation = anim.animations.walk.left
                    end
                    if velocity.dir.x == 1 then
                        anim.current_animation = anim.animations.walk.right
                    end
                end
                
                anim.current_animation:Update(dt)
            end
            
        else
            if love.keyboard.isDown(controls.up) then
                pos.y = pos.y - 100 * dt
            elseif love.keyboard.isDown(controls.down) then
                pos.y = pos.y + 100 * dt
            end
            if love.keyboard.isDown(controls.left) then
                pos.x = pos.x - 100 * dt
            elseif love.keyboard.isDown(controls.right) then
                pos.x = pos.x + 100 * dt
            end
        end

        player_cam.zoom = zoom

        if player_cam and anim then
            cam:lookAt(pos.x + (player_cam.offsetX or 0), pos.y + (player_cam.offsetY or 0))
            cam:zoomTo(player_cam.zoom)
        end
    end    
end

function love.wheelmoved(x, y)
    zoom = zoom + y * ZOOM_MULT
    zoom = clamp(zoom, ZOOM_MAX, ZOOM_MIN)
end

function love.keypressed(key)
    if key == 'escape' then
        love.event.quit()
    end
    if key == debug_key then
        debug_bool = not debug_bool
    end
    if key == 'r' then
        love.load()
    end
end