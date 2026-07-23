player = ECSManager.newEntity()
player.controls = {
    up = {"up", "w"},
    down = {"down", "s"},
    left = {"left", "a"},
    right = {"right", "d"}
}
player.width = 15
player.height = 23
function player:load()

    self.animations = {
        idle = {
            up    = Animation.new("resources/player/up_idle.png", 12, 1, 0.1),
            down  = Animation.new("resources/player/down_idle.png", 12, 1, 0.1),
            left  = Animation.new("resources/player/left_idle.png", 12, 1, 0.1),
            right = Animation.new("resources/player/right_idle.png", 12, 1, 0.1),
        },
        walk = {
            up    = Animation.new("resources/player/up_walk.png", 6, 1, 0.1),
            down  = Animation.new("resources/player/down_walk.png", 6, 1, 0.1),
            left  = Animation.new("resources/player/left_walk.png", 6, 1, 0.1),
            right = Animation.new("resources/player/right_walk.png", 6, 1, 0.1),
        }
    }

    self:add(DebugComponent())
    self:add(PositionComponent(100, 100))
    self:add(ScaleComponent(1.5))
    self:add(SpriteComponent("resources/cool_guy.png", 12, 16))
    self:add(AnimationComponent(self.animations, self.animations.idle.down))
    self:add(VelocityComponent(0, 0, 70))
    self:add(ControllerComponent(self.controls))
    self:add(CameraComponent(self.width - 3, self.height, 1.75))
    self:add(ColliderComponent(21, self.height/2 + 1, -11, -self.height - 4, 4))
end

function player:update(dt)
    System.controllerSystem(self, dt)
end

function player:draw()
    System.renderSystem(self)
end
