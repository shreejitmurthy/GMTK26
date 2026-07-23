---@enum ComponentType
ComponentType = {
    SPRITE     =  1,
    SCALE      =  2,
    POSITION   =  3,
    CONTROLLER =  4,
    VELOCITY   =  5,
    ANIMATION  =  6,
    DEBUG      =  7,
    CAMERA     =  8,
    COLLIDER   =  9
}

---@class Component
Component = {
    v = nil,
    type = 0
}

font = love.graphics.newFont(11)

function DebugComponent(key)
    local self = setmetatable({}, {__index = Component})
    self.v = {key = key or '/'}
    self.type = ComponentType.DEBUG
    return self
end

function PositionComponent(x, y)
    local self = setmetatable({}, {__index = Component})
    self.v = {x = x or 0, y = y or 0}
    self.type = ComponentType.POSITION
    return self
end

function SpriteComponent(imagePath, width, height)
    local self = setmetatable({}, {__index = Component})
    local image = love.graphics.newImage(imagePath)
    self.v = {imagePath = imagePath, image = image, width = width, height = height}
    self.type = ComponentType.SPRITE
    return self
end

function ScaleComponent(scale)
    local self = setmetatable({}, {__index = Component})
    self.v = scale
    self.type = ComponentType.SCALE
    return self
end

function ControllerComponent(controls)
    local self = setmetatable({}, {__index = Component})
    self.v = controls
    self.type = ComponentType.CONTROLLER
    return self
end

function VelocityComponent(dx, dy, speed, direction)
    local self = setmetatable({}, {__index = Component})
    self.v = {dx = dx, dy = dy, speed = speed, dir = direction or {x = 0, y = 1}}
    self.type = ComponentType.VELOCITY
    return self
end

function AnimationComponent(loaded_animations, current_animation)
    local self = setmetatable({}, {__index = Component})
    self.v = {animations = loaded_animations, current_animation = current_animation}
    self.type = ComponentType.ANIMATION
    return self
end

function CameraComponent(offsetX, offsetY, default_zoom)
    local self = setmetatable({}, {__index = Component})
    self.v = {offsetX = offsetX, offsetY = offsetY, zoom = default_zoom or 1}
    self.type = ComponentType.CAMERA
    return self
end

function ColliderComponent(width, height, offsetX, offsetY, corners)
    local self = setmetatable({}, {__index = Component})
    body = world:newBSGRectangleCollider(0, 0, width, height, (corners or 1))
    self.v = {body = body, offsetX = offsetX, offsetY = offsetY}
    self.v.body:setFixedRotation(true)
    self.type = ComponentType.COLLIDER
    return self
end