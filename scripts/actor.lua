actor = {} -- Moving guys
actor.__index = actor

function actor:new(x, y, label)
    local instance = setmetatable({}, actor)
    instance.x = x
    instance.y = y
    instance.label = label or ""
    return instance
end

function actor:update(dx, dy)
    self.x = dx
    self.y = dy
end