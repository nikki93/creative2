L = require('https://raw.githubusercontent.com/nikki93/L/3f63e72eef6b19a9bab9a937e17e527ae4e22230/L.lua')

local simulsim = require 'https://raw.githubusercontent.com/nikki93/simulsim/2f70863464fe1b573d1f07d947cdebbd9f710451/simulsim.lua'

local game = simulsim.defineGame()

function game.load(self)
    self.data.backgroundColor = { 0.1, 0.1, 0.1 }
end

function game.update(self, dt)
    for _, entity in ipairs(self.entities) do
        local inputs = self:getInputsForClient(entity.clientId) or {}
        local moveX = (inputs.right and 1 or 0) - (inputs.left and 1 or 0)
        local moveY = (inputs.down and 1 or 0) - (inputs.up and 1 or 0)
        entity.x = math.min(math.max(0, entity.x + 200 * moveX * dt), 380)
        entity.y = math.min(math.max(0, entity.y + 200 * moveY * dt), 380)
    end
end

function game.handleEvent(self, eventType, eventData)
    if eventType == 'spawn-player' then
        self:spawnEntity({
            clientId = eventData.clientId,
            x = eventData.x,
            y = eventData.y,
            width = 20,
            height = 20,
            color = eventData.color
        })
    elseif eventType == 'despawn-player' then
        self:despawnEntity(self:getEntityWhere({ clientId = eventData.clientId }))
    end
end

local network, server, client = simulsim.createGameNetwork(game, { mode = 'localhost' })

function server.clientconnected(self, client)
    self:fireEvent('spawn-player', {
        clientId = client.clientId,
        x = 100 + 200 * math.random(),
        y = 100 + 200 * math.random(),
        color = { math.random(), 1, math.random() }
    })
end

function server.clientdisconnected(self, client)
    self:fireEvent('despawn-player', { clientId = client.clientId })
end

function client.update(self, dt)
    self:setInputs({
        up = L.keyboard.isDown('w') or L.keyboard.isDown('up'),
        left = L.keyboard.isDown('a') or L.keyboard.isDown('left'),
        down = L.keyboard.isDown('s') or L.keyboard.isDown('down'),
        right = L.keyboard.isDown('d') or L.keyboard.isDown('right')
    })
end

function client.draw(self)
    L.setColor(self.game.data.backgroundColor)
    L.rectangle('fill', 0, 0, 400, 400)
    for _, entity in ipairs(self.game.entities) do
        L.setColor(entity.color)
        L.rectangle('fill', entity.x, entity.y, entity.width, entity.height)
    end
    L.setColor(1, 1, 1)
    if self:isConnecting() then
        L.print('Connecting...', 3, 3)
    elseif not self:isConnected() then
        L.print('Disconnected! :(', 3, 3)
    elseif not self:isStable() then
        L.print('Connected! Stabilizing...', 3, 3)
    else
        L.print('Connected! Frames of latency: ' .. self:getFramesOfLatency(), 3, 3)
    end
end

function castle.uiupdate()
    L.ui.markdown([[
## Hello, world!

Hey there! :)
    ]])
end
