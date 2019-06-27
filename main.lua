L = require('https://raw.githubusercontent.com/nikki93/L/3f63e72eef6b19a9bab9a937e17e527ae4e22230/L.lua')

local simulsim = require 'https://raw.githubusercontent.com/nikki93/simulsim/2f70863464fe1b573d1f07d947cdebbd9f710451/simulsim.lua'

local game = simulsim.defineGame()

local compileRule, callRule
do
    local compileCache = {}

    function compileRule(rule)
        local cached = compileCache[rule.code]
        if cached then
            return cached
        end

        local compiled, err = load('local self = ...\n' .. rule.code, rule.id, 't', _G)
        compileCache[rule.code] = compiled or err
        if err then
            print(err)
        end
        return compiled
    end

    function callRule(rule, ...)
        local compiled = compileRule(rule)
        if type(compiled) == 'function' then
            local succeeded, err = pcall(compiled, ...)
            if not succeeded then
                print(err)
            end
        end
    end
end

do
    local function compareRules(rule1, rule2)
        return (rule1.priority or 0) < (rule2.priority or 0)
    end

    function sortRules(rules)
        local sorted = {}
        for _, rule in pairs(rules) do
            table.insert(sorted, rule)
        end
        table.sort(sorted, compareRules)
        return sorted
    end
end

function game.load(self)
end

function game.update(self, dt)
    local sortedRules = sortRules(self:getEntitiesWhere({ type = 'rule' }))
    for _, rule in ipairs(sortedRules) do
        if rule.kind == 'update' then
            callRule(rule, self)
        end
    end
end

function game.handleEvent(self, eventType, eventData)
    if eventType == 'add-rule' then
        self:spawnEntity({
            type = 'rule',
            clientId = eventData.clientId,
            priority = assert(eventData.priority, 'rule needs `priority`'),
            kind = assert(eventData.kind, 'rule needs `kind`'),
            description = assert(eventData.description, 'rule needs `description`'),
            code = assert(eventData.code, 'rule needs `code`'),
        })
    end
    if eventType == 'update-rule' then
        assert(eventData.id, "'update-rule' needs `id`")
        local rule = self:getEntityById(eventData.id)
        rule.clientId = eventData.clientId
        rule.priority = assert(eventData.priority, 'rule needs `priority`')
        rule.kind = assert(eventData.kind, 'rule needs `kind`')
        rule.description = assert(eventData.description, 'rule needs `description`')
        rule.code = assert(eventData.code, 'rule needs `code`')
    end
end

local network, server, client = simulsim.createGameNetwork(game, { mode = 'localhost' })

function server.load(self)
    self:fireEvent('add-rule', {
        priority = 0,
        kind = 'draw',
        description = 'draw a circle!',
        code = [[
L.circle('fill', 200, 200, 40)
]],
    })
end

function server.clientconnected(self, client)
end

function server.clientdisconnected(self, client)
end

local clientSelf
function client.update(self, dt)
    clientSelf = self
end

function client.draw(self)
    local sortedRules = sortRules(self.game:getEntitiesWhere({ type = 'rule' }))
    for _, rule in ipairs(sortedRules) do
        if rule.kind == 'draw' then
            callRule(rule, self.game)
        end
        L.print('clientId: ' .. tostring(rule.clientId), 3, 23)
    end
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

do
    local selectedRuleId

    function castle.uiupdate()
        local self = clientSelf
        if not (self and self.game) then
            return
        end

        -- Button to add new rule
        if L.ui.button('new rule') then
            self:fireEvent('add-rule', {
                clientId = self.clientId,
                priority = 0,
                kind = 'draw',
                description = 'draw a circle!',
                code = [[
L.circle('fill', ]] .. math.random(0, L.getWidth()) .. [[, ]] .. math.random(0, L.getHeight()) .. [[, 40)
        ]],
            })
        end

        -- Dropdown to select rule
        local selectedRule
        do
            local selectedRuleLine
            local ruleLines = {}
            local ruleLineToRuleId = {}
            for _, rule in pairs(self.game:getEntitiesWhere({ type = 'rule' })) do
                local ruleLine = rule.description .. ' (' .. rule.id .. ')'
                table.insert(ruleLines, ruleLine)
                ruleLineToRuleId[ruleLine] = rule.id
                if rule.id == selectedRuleId then
                    selectedRuleLine = ruleLine
                end
            end
            local selectedRuleLine = L.ui.dropdown('rule', selectedRuleLine, ruleLines, {
                placeholder = 'select a rule...'
            })
            selectedRuleId = ruleLineToRuleId[selectedRuleLine]

            selectedRule = self.game:getEntityById(selectedRuleId)
            if not selectedRule then
                selectedRuleId = nil
            end
        end

        -- Editor for selected rule
        if selectedRule then
            local newRule = {}
            for k, v in pairs(selectedRule) do
                newRule[k] = v
            end

            newRule.priority = L.ui.numberInput('priority', selectedRule.priority)

            newRule.kind = L.ui.dropdown('kind', selectedRule.kind, {
                'draw', 'update', 'ui',
            })

            newRule.description = L.ui.textInput('description', selectedRule.description, {
                maxLength = 80,
            })

            newRule.code = L.ui.codeEditor('code', selectedRule.code)

            local changed = false
            for k, v in pairs(newRule) do
                if selectedRule[k] ~= newRule[k] then
                    changed = true
                    break
                end
            end
            for k, v in pairs(selectedRule) do
                if selectedRule[k] ~= newRule[k] then
                    changed = true
                    break
                end
            end
            if changed then
                newRule.clientId = self.clientId
                print('clientId: ' .. tostring(self.clientId))
                self:fireEvent('update-rule', newRule)
            end
        end
    end
end
