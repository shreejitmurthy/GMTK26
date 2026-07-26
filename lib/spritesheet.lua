--[[
    MIT License

    Copyright (c) 2024 Shreejit Murthy

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]

local Spritesheet = {}
Spritesheet.__index = Spritesheet

local Animation = {}
Animation.__index = Animation

function Animation.new(frames, delay)
    return setmetatable({
        frames = frames,
        delay = delay,
        currentTime = 0,
        currentIndex = 1
    }, Animation)
end

---@param spritesheet_path string
---@param frameWidth integer
---@param frameHeight integer
function newSpritesheet(spritesheet_path, frameWidth, frameHeight, left, top)
    local self = setmetatable({}, Spritesheet)
    self.path = spritesheet_path
    self.image = love.graphics.newImage(self.path)
    self.frameWidth = frameWidth
    self.frameHeight = frameHeight
    self.left = left or 0
    self.top = top or 0
    return self
end

--- Create another frame-grid view over the same loaded image.
--- Useful when rows in one image use different frame dimensions.
function Spritesheet:newView(frameWidth, frameHeight, left, top)
    return setmetatable({
        path = self.path,
        image = self.image,
        frameWidth = frameWidth or self.frameWidth,
        frameHeight = frameHeight or self.frameHeight,
        left = left or self.left,
        top = top or self.top,
    }, Spritesheet)
end

function Spritesheet:getFrames(sx, sy, fx, fy)
    local frames = {}
    for y = sy, fy do
        for x = sx, fx do
            local quad = love.graphics.newQuad(
                ((x - 1) * self.frameWidth) + self.left,
                ((y - 1) * self.frameHeight) + self.top,
                self.frameWidth,
                self.frameHeight,
                self.image:getDimensions()
            )
            frames[#frames+1] = quad
        end
    end

    return frames
end

function Spritesheet:newAnimation(s, f, delay)
    if not delay then
        error("No delay value given to animation (" .. self.path .. ")")
    end
    local sx, sy = unpack(s)
    local fx, fy = unpack(f)
    local frames = self:getFrames(sy, sx, fy, fx)

    return Animation.new(frames, delay)
end

function Animation:update(dt, frameStep)
    frameStep = frameStep or 1
    self.currentTime = self.currentTime + dt
    if self.currentTime >= self.delay then
        self.currentTime = self.currentTime - self.delay
        self.currentIndex =
            ((self.currentIndex - 1 + frameStep) % #self.frames) + 1
    end
end

function Spritesheet:draw(animation, x, y, debug)
    love.graphics.push()
    -- love.graphics.translate(-(self.frameWidth / 2), -(self.frameHeight / 2))
    love.graphics.draw(self.image, animation.frames[animation.currentIndex], x, y, nil, nil)
    if debug then
        love.graphics.rectangle("line", x, y, self.frameWidth, self.frameHeight)
        love.graphics.print(tostring(animation.currentIndex), x + self.frameWidth + 3, y)
    end
    love.graphics.pop()
end
