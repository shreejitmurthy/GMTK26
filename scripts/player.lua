-- -- PLAYER

-- PLAYER_STATES = {
--     IDLE = 0,
--     WALK = 1,
--     RUN = 3,
--     ATTACK = 4
-- }

-- player = {}
-- setmetatable(player, {__index = actor})

-- function player:new()
--     local p = actor.new(self, 250, 250, "player")
--     setmetatable(p, {__index = player})
--     p.img = love.graphics.newImage("res/images/player.png")
--     p.img:setFilter("nearest", "nearest")
--     p.highlight = love.graphics.newImage("res/images/highlight.png")
--     p.maxSpeed = 125
--     p.speed = p.maxSpeed
--     p.acceleration = 1000
--     p.deceleration = 1500
--     p.velocity = {x = 0, y = 0}
--     p.dir = {x = 1, y = 0}
--     p.attack_timer = 0
--     p.controls = {
--         left   = {keys = {"left", "a"}},
--         right  = {keys = {"right", "d"}},
--         up     = {keys = {"up", "w"},    pressed = false, lastTime = 0},
--         down   = {keys = {"down", "s"},  pressed = false, lastTime = 0},
--         attack = {keys = {"j"}}
--     }
--     p.black_hole = newSpritesheet("res/black_hole.png", 200, 200)
--     p.black_hole_anim = p.black_hole:newAnimation({1, 1}, {1, 50}, 0.05)
--     p.move_sheet = newSpritesheet("res/images/player/turn-idle-run-walk-1.png", 128, 128)
--     p.attack_sheet = newSpritesheet("res/images/player/melee-meleerun.png", 128, 128)
--     p.animations = {
--         -- Opposite animations, since right turns into left, up turns into down
--         l_turn  = p.move_sheet:newAnimation({1, 1}, {1, 15}, 0.03),
--         ul_turn = p.move_sheet:newAnimation({2, 1}, {2, 15}, 0.03),
--         u_turn  = p.move_sheet:newAnimation({3, 1}, {3, 15}, 0.03),
--         ur_turn = p.move_sheet:newAnimation({4, 1}, {4, 15}, 0.03),
--         r_turn  = p.move_sheet:newAnimation({5, 1}, {5, 15}, 0.03),
--         dr_turn = p.move_sheet:newAnimation({6, 1}, {6, 15}, 0.03),
--         d_turn  = p.move_sheet:newAnimation({7, 1}, {7, 15}, 0.03),
--         dl_turn = p.move_sheet:newAnimation({8, 1}, {8, 15}, 0.03),

--         r_idle  = p.move_sheet:newAnimation({1 + 8, 1}, {1 + 8, 15}, 0.1),
--         dr_idle = p.move_sheet:newAnimation({2 + 8, 1}, {2 + 8, 15}, 0.1),
--         d_idle  = p.move_sheet:newAnimation({3 + 8, 1}, {3 + 8, 15}, 0.1),
--         dl_idle = p.move_sheet:newAnimation({4 + 8, 1}, {4 + 8, 15}, 0.1),
--         l_idle  = p.move_sheet:newAnimation({5 + 8, 1}, {5 + 8, 15}, 0.1),
--         ul_idle = p.move_sheet:newAnimation({6 + 8, 1}, {6 + 8, 15}, 0.1),
--         u_idle  = p.move_sheet:newAnimation({7 + 8, 1}, {7 + 8, 15}, 0.1),
--         ur_idle = p.move_sheet:newAnimation({8 + 8, 1}, {8 + 8, 15}, 0.1),

--         r_run  = p.move_sheet:newAnimation({9 + 8, 1}, {9 + 8, 15},   0.06),
--         dr_run = p.move_sheet:newAnimation({10 + 8, 1}, {10 + 8, 15}, 0.06),
--         d_run  = p.move_sheet:newAnimation({11 + 8, 1}, {11 + 8, 15}, 0.06),
--         dl_run = p.move_sheet:newAnimation({12 + 8, 1}, {12 + 8, 15}, 0.06),
--         l_run  = p.move_sheet:newAnimation({13 + 8, 1}, {13 + 8, 15}, 0.06),
--         ul_run = p.move_sheet:newAnimation({14 + 8, 1}, {14 + 8, 15}, 0.06),
--         u_run  = p.move_sheet:newAnimation({15 + 8, 1}, {15 + 8, 15}, 0.06),
--         ur_run = p.move_sheet:newAnimation({16 + 8, 1}, {16 + 8, 15}, 0.06),

--         r_mel1  = p.attack_sheet:newAnimation({1, 1}, {1, 15}, 0.03),
--         dr_mel1 = p.attack_sheet:newAnimation({2, 1}, {2, 15}, 0.03),
--         d_mel1  = p.attack_sheet:newAnimation({3, 1}, {3, 15}, 0.03),
--         dl_mel1 = p.attack_sheet:newAnimation({4, 1}, {4, 15}, 0.03),
--         l_mel1  = p.attack_sheet:newAnimation({5, 1}, {5, 15}, 0.03),
--         ul_mel1 = p.attack_sheet:newAnimation({6, 1}, {6, 15}, 0.03),
--         u_mel1  = p.attack_sheet:newAnimation({7, 1}, {7, 15}, 0.03),
--         ur_mel1 = p.attack_sheet:newAnimation({8, 1}, {8, 15}, 0.03),

--     }
--     p.current_animation = p.animations.d_idle
--     p.state = PLAYER_STATES.IDLE

--     p.attack_duration = #p.animations.d_mel1.frames * p.animations.d_mel1.delay
--     p.attack_cooldown = 0.5
--     p.attack_cooldown_timer = 0

--     return p
-- end

-- local function applyDeceleration(velocity, deceleration, dt)
--     if velocity > 0 then
--         velocity = velocity - deceleration * dt
--         if velocity < 0 then velocity = 0 end
--     elseif velocity < 0 then
--         velocity = velocity + deceleration * dt
--         if velocity > 0 then velocity = 0 end
--     end
--     return velocity
-- end

-- function player:checkQuickChange(current_dir, last_dir, threshold, currentTime)
--     local timeSinceLastMove = currentTime - (self.lastMoveTime or 0)
--     local isQuick = timeSinceLastMove <= threshold
--     local isReversal = current_dir.x == -last_dir.x and current_dir.y == -last_dir.y

--     return isQuick and isReversal
-- end

-- function player:update(dt)
--     local currentTime = love.timer.getTime()
--     local dir_x, dir_y = 0, 0
--     local moving = false

--     if self.attack_cooldown_timer > 0 then
--         self.attack_cooldown_timer = self.attack_cooldown_timer - dt
--         if self.attack_cooldown_timer < 0 then
--             self.attack_cooldown_timer = 0
--         end
--     end

--     -- Input handling
--     if love.keyboard.isDown(self.controls.left.keys) then
--         self.velocity.x = self.velocity.x - self.acceleration * dt
--         dir_x = -1
--         moving = true
--     elseif love.keyboard.isDown(self.controls.right.keys) then
--         self.velocity.x = self.velocity.x + self.acceleration * dt
--         dir_x = 1
--         moving = true
--     else
--         self.velocity.x = applyDeceleration(self.velocity.x, self.deceleration, dt)
--     end

--     if love.keyboard.isDown(self.controls.up.keys) then
--         self.velocity.y = self.velocity.y - self.acceleration * dt
--         dir_y = -1
--         moving = true
--     elseif love.keyboard.isDown(self.controls.down.keys) then
--         self.velocity.y = self.velocity.y + self.acceleration * dt
--         dir_y = 1
--         moving = true
--     else
--         self.velocity.y = applyDeceleration(self.velocity.y, self.deceleration, dt)
--     end

--     if love.keyboard.isDown(self.controls.attack.keys) and self.state ~= PLAYER_STATES.ATTACK and self.attack_cooldown_timer == 0 then
--         -- self.state = PLAYER_STATES.ATTACK
--         self.attack_timer = self.attack_duration
--         self.attack_cooldown_timer = self.attack_cooldown
--     end

--     -- Normalize velocity
--     local length = math.sqrt(self.velocity.x^2 + self.velocity.y^2)
--     if length > self.speed then
--         self.velocity.x = (self.velocity.x / length) * self.speed
--         self.velocity.y = (self.velocity.y / length) * self.speed
--     end

--     -- Update direction if moving
--     if dir_x ~= 0 or dir_y ~= 0 then
--         self.dir.x = dir_x
--         self.dir.y = dir_y

--         self.lastMoveTime = currentTime
--     end

--     if self.state == PLAYER_STATES.ATTACK then
--         self.attack_timer = self.attack_timer - dt
--         if self.attack_timer <= 0 then
--             self.state = PLAYER_STATES.IDLE
--         end
--     else
--         self.state = moving and PLAYER_STATES.RUN or PLAYER_STATES.IDLE
--     end
    
--     local dir2anim = {
--         ["0,-1"]  = "u_idle",
--         ["1,-1"]  = "ur_idle",
--         ["1,0"]   = "r_idle",
--         ["1,1"]   = "dr_idle",
--         ["0,1"]   = "d_idle",
--         ["-1,1"]  = "dl_idle",
--         ["-1,0"]  = "l_idle",
--         ["-1,-1"] = "ul_idle"
--     }

--     if self.state == PLAYER_STATES.RUN then
--         for k, v in pairs(dir2anim) do
--             dir2anim[k] = v:gsub("_idle", "_run")
--         end
--     elseif self.state == PLAYER_STATES.ATTACK then
--         for k, v in pairs(dir2anim) do
--             -- Replace with melee attack 1 for now, later we count attack presses
--             dir2anim[k] = v:gsub("_idle", "_mel1")
--         end
--     end

--     local animation_key = dir2anim[string.format("%d,%d", self.dir.x, self.dir.y)]
--     self.current_animation = self.animations[animation_key] or self.animations.d_idle

--     -- self.current_animation:update(dt)
--     self.black_hole_anim:update(dt)

--     if self.state ~= PLAYER_STATES.ATTACK then
--         self.x = self.x + self.velocity.x * dt
--         self.y = self.y + self.velocity.y * dt
--     end
-- end

-- function player:draw()
--     -- love.graphics.draw(self.img, self.x, self.y, 0, self.dir.x, 1, self.img:getWidth() / 2, self.img:getHeight() / 2)
--     love.graphics.push()
--     love.graphics.translate(-128/2, -128/2)
--     love.graphics.setColor(1, 1, 1, 0.8)
--     love.graphics.draw(self.highlight, self.x - 128/2, self.y - 128/2 + 64/2)
--     love.graphics.setColor(1, 1, 1, 1)
--     sheet = (self.state == PLAYER_STATES.ATTACK and self.attack_sheet or self.move_sheet)
--     -- sheet:draw(self.current_animation, self.x, self.y)
--     self.black_hole:draw(self.black_hole_anim, self.x, self.y)
--     love.graphics.pop()
-- end