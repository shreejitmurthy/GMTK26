require "lib.spritesheet"

states = {
    IDLE = 0,
    RUN = 1,
    BACKRUN = 2,
    JUMP = 3,
    CLOSE = 4,
}

player = {}
setmetatable(player, {__index = actor})

function player:init()
    local p = actor.new(self, 50, 10, "player")
    setmetatable(p, {__index = player})
    p.img = love.graphics.newImage("res/images/dude.png")

    p.maxSpeed = 75
    p.acceleration = 850
    p.deceleration = 1000
    p.jumpForce = 45

    p.controls = {
        left = {"a", "left"},
        right = {"d", "right"},
        jump = {"space", "up"},
        close = {"lshift"}
    }

    p.vx = 0
    p.vy = 0
    p.collider = world:newBSGRectangleCollider(p.x, p.y, 10, 14, 3)
    p.collider:setFixedRotation(true)
    p.collider:setCollisionClass("Player")
    
    p.grounded = false

    p.backRunModifier = 0.5

    p.dir = 1

    p.eye_y = 9   -- 9 pixels from top of frame
    p.eye_x = 11  -- 11 pixels from the left of frame
    p.eye = {}
    p.fovn = 45
    p.length = 85
    p.visionAngle = 0
    p.coneTurnSpeed = 15
    p.visionDir = 1
    p.detectionScale = 0.3  -- ensure that detecting certain tiles is deliberate and not just caught

    p.rays = {}

    p.state = states.IDLE

    p.animations = {}
    p.spritesheet1 = newSpritesheet("res/images/player/atlas.png", 16, 16)
    p.animations.idle = p.spritesheet1:newAnimation({1, 5}, {1, 6}, 0.3)
    p.animations.idle_closed = p.spritesheet1:newAnimation({1, 7}, {1, 8}, 0.3)
    p.animations.run = p.spritesheet1:newAnimation({1, 1}, {1, 4}, 0.1)
    p.animations.run_reverse = p.spritesheet1:newAnimation({2, 1}, {2, 4}, 0.25)
    p.current_animation = p.animations.idle

    return p
end

function player:update(dt)
    local _, vy = self.collider:getLinearVelocity()
    local desiredVX = 0

    self.visionDir = self:getVisionDir()
    local inputDir = 0

    if love.keyboard.isDown(self.controls.right) then
        inputDir = 1
    elseif love.keyboard.isDown(self.controls.left) then
        inputDir = -1
    end

    if inputDir ~= 0 then
        self.dir = inputDir

        if inputDir ~= self.visionDir then
            desiredVX = self.maxSpeed * self.backRunModifier * inputDir
            self.state = states.BACKRUN
        else
            desiredVX = self.maxSpeed * inputDir
            self.state = states.RUN
        end
    else
        self.state = states.IDLE
    end

    -- Accelerate or decelerate
    if desiredVX ~= 0 then
        local change = self.acceleration * dt
        if math.abs(self.vx - desiredVX) < change then
            self.vx = desiredVX
        else
            self.vx = self.vx + math.sign(desiredVX - self.vx) * change
        end
    else
        local change = self.deceleration * dt
        if math.abs(self.vx) < change then
            self.vx = 0
        else
            self.vx = self.vx - math.sign(self.vx) * change
        end
    end

    self.vy = vy
    self.collider:setLinearVelocity(self.vx, self.vy)
    self.x, self.y = self.collider:getX(), self.collider:getY()

    if self.collider:enter('Ground') then
        self.grounded = true
    elseif self.collider:exit('Ground') then
        self.grounded = false
    end

    if self.state == states.IDLE then
        self.current_animation = self.animations.idle
    elseif self.state == states.RUN then
        self.current_animation = self.animations.run
    elseif self.state == states.BACKRUN then
        self.current_animation = self.animations.run_reverse
    end

    if self.y > map_height then
        self.collider:setPosition(50, 10)
    end

    -- local dir = self.dir == self.visionDir and self.dir or self.visionDir
    local eyeOffsetDir = self.visionDir or 1
    self.eye = {
        self.x + (self.eye_x / 2 - 2.75 --[[ -2.75 to bring into image --]]) * eyeOffsetDir, 
        self.y + 1 --[[ +1 to account for idle anim --]]
    }

    self.rays = self:shootRays(8)
    self:scanVisionCone()

    self.current_animation:flipV(self.dir)
    self.current_animation:update(dt)
end

function player:keypressed(key)
    if (key == "space") and self.grounded then
        self.collider:applyLinearImpulse(0, -self.jumpForce)
    end

    if key == 'up' then
        -- self.fovn = self.fovn + 5
        self.detectionScale = self.detectionScale + 0.1
    elseif key == 'down' then
        -- self.fovn = self.fovn - 5
        self.detectionScale = self.detectionScale - 0.1
    end
end

function player:shootRays(rayCount)
    rayCount = rayCount or 12

    local eyeOffsetDir = self.visionDir or 1
    local ex = self.x + (self.eye_x/2 - 2.75) * eyeOffsetDir
    local ey = self.y + 1

    -- full cone half‐angle
    local halfFOV  = math.rad(self.fovn) * 0.5
    -- subtract the feathered region
    local softness = halfFOV * coneEdgeSoftness
    -- half-angle of the full-opacity core
    local innerHalf = (halfFOV - softness) * self.detectionScale

    -- spread rays inside that core
    local startAngle = self.visionAngle - innerHalf
    local angleStep  = (innerHalf * 2) / rayCount

    local rays = {}
    for i = 0, rayCount do
        local a  = startAngle + i * angleStep
        local dx = math.cos(a) * self.length
        local dy = math.sin(a) * self.length
        rays[#rays+1] = { ex, ey, ex + dx, ey + dy }
    end

    return rays
end

function player:scanVisionCone()
    for _, tile in ipairs(collidables) do
        tile.isFound = false
    end

    for _, ray in ipairs(self.rays) do
        world:rayCast(ray[1], ray[2], ray[3], ray[4],
          function(fixture, x, y, nx, ny, frac)
            local tile = fixture:getUserData()
            if not tile or not tile.collision_class then
                return 1
            end

            local prefix = tile.collision_class:match("^(.-)_")
            if prefix == "Look" then
                tile.isFound = true
                return 0
            elseif prefix == "NoLook" then
                tile.isFound = true
            end
            return 1
        end
        )
    end
end

local py_offset = 0.5

function player:draw(alpha)
    love.graphics.setColor(1, 1, 1, alpha)
    self.spritesheet1:draw(self.current_animation, self.x, self.y + py_offset)
    love.graphics.setColor(1, 1, 1, 1)
end

function player:debugRays()
    for _, v in ipairs(self.rays) do
        love.graphics.line(v[1], v[2], v[3], v[4])
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function player:debugVisionCone(segments, fill)
    segments = segments or 20
    fill = fill or false

    local points = self.eye
    local startAngle = self.visionAngle - math.rad(self.fovn) / 2
    local angleStep = math.rad(self.fovn) / segments

    for i = 0, segments do
        local angle = startAngle + i * angleStep
        local px = points[1] + math.cos(angle) * self.length
        local py = points[2] + math.sin(angle) * self.length
        table.insert(points, px)
        table.insert(points, py)
    end

    if fill then
        love.graphics.setColor(1, 1, 0, 0.3)  -- yellowish translucent
        love.graphics.polygon("fill", points)
    end

    love.graphics.setColor(1, 1, 0, 0.6)
    love.graphics.polygon("line", points)

    love.graphics.setColor(1, 1, 1, 1)  -- reset color
end

function player:debug()
    love.graphics.setLineWidth(0.25)
    love.graphics.setColor(1, 1, 0)
    love.graphics.circle("fill", self.eye[1], self.eye[2], 0.5)
    love.graphics.setColor(1, 0, 0)
    love.graphics.circle("fill", self.x, self.y, 1)

    self:debugVisionCone()
    love.graphics.setColor(1, 1, 0, 0.6)
    -- self:debugRays()

    -- if self.foundLookie then
    --     love.graphics.setColor(1,0,1)
    --     for _, ray in ipairs(self.rays) do
    --         if ray.hitX then
    --             love.graphics.line(ray[1], ray[2], ray.hitX, ray.hitY)
    --             break
    --         end
    --     end
    --     love.graphics.setColor(1,1,1)
    -- end

    for _, ray in ipairs(self.rays) do
        if ray.hitX then
            love.graphics.setColor(1, 0, 1)               -- magenta
            love.graphics.line(ray[1], ray[2], ray.hitX, ray.hitY)
            love.graphics.setColor(1, 1, 1)               -- reset
            break
        end
    end

    love.graphics.setLineWidth(1)
end

function player:getVisionDir()
    local angle = self.visionAngle % (2 * math.pi)
    return (angle > math.pi / 2 and angle < 3 * math.pi / 2) and -1 or 1
end

function player:getWorldPos()
    local cx, cy = cam_x, cam_y
    local sw, sh = love.graphics.getDimensions()
    local ex, ey = self.eye[1], self.eye[2]
    local sx = (ex - cx) * cam_zoom + sw / 2
    local sy = (ey - cy) * cam_zoom + sh / 2
    return {sx, sy}
end

local COS_RIGHT = math.cos(math.rad(80))   -- ~+0.1736
local COS_LEFT = math.cos(math.rad(100))   -- ~–0.1736

function player:getDirVec(dt)
    local visionVec
    local mx, my = cam:mousePosition()
    local px, py = self.x, self.y

    local rawA = math.atan2(my - py, mx - px)
    if rawA < 0 then rawA = rawA + 2*math.pi end

    self.visionAngle = lerpAngle(self.visionAngle, rawA, self.coneTurnSpeed * dt)

    local c = math.cos(rawA)
    if     c >  COS_RIGHT then self.visionDir =  1
    elseif c <  COS_LEFT  then self.visionDir = -1
    end

    self.dir = self.visionDir

    visionVec = { math.cos(self.visionAngle), math.sin(self.visionAngle) }
    return visionVec
end

function player:getConeAngle()
    return math.rad(self.fovn)
end

function player:getConeLength()
    return self.length * cam_zoom
end