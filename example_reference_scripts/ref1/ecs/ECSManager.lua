require "scripts.ecs.component"
require "scripts.ecs.entity"
require "scripts.ecs.systems"

ECSManager = {
    entities = {},
    components = {}
}

function ECSManager:init()
    self.entities = {}
    self.components = {}
end

function ECSManager.newEntity()
    local self = setmetatable({}, {__index = Entity})
    table.insert(ECSManager.entities, self)
    self.ID = #ECSManager.entities
    return self
end

---@param component Component
function Entity:add(component)
    if not ECSManager.components[component.type] then
        ECSManager.components[component.type] = {}
    end
    ECSManager.components[component.type][self.ID] = component
end

function ECSManager:get(entityID, componentType)
    local componentsOfType = ECSManager.components[componentType]
    if componentsOfType then
        return componentsOfType[entityID] and componentsOfType[entityID].v
    end
    return nil
end
