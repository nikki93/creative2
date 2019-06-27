L = require 'https://raw.githubusercontent.com/nikki93/L/3f63e72eef6b19a9bab9a937e17e527ae4e22230/L.lua'
serpent = require 'https://raw.githubusercontent.com/pkulchenko/serpent/879580fb21933f63eb23ece7d60ba2349a8d2848/src/serpent.lua'

local simulsim = require 'https://raw.githubusercontent.com/nikki93/simulsim/2f70863464fe1b573d1f07d947cdebbd9f710451/simulsim.lua'

local game = simulsim.defineGame()

local generateId
do
    local idChars = '01234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
    function generateId()
        local t = {}
        for i = 1, 8 do
            local r = L.math.random(1, #idChars)
            t[i] = idChars:sub(r, r)
        end
        return table.concat(t)
    end
end

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

local sortRules
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
            id = assert(eventData.id, "'add-rule' needs `id`"),
            clientId = eventData.clientId,
            priority = assert(eventData.priority, "'add-rule' needs `priority`"),
            kind = assert(eventData.kind, "'add-rule' needs `kind`"),
            description = assert(eventData.description, "'add-rule' needs `description`"),
            code = assert(eventData.code, "'add-rule' needs `code`"),
        })
    end
    if eventType == 'update-rule' then
        assert(eventData.id, "'update-rule' needs `id`")
        local rule = self:getEntityById(eventData.id)
        rule.clientId = eventData.clientId
        rule.priority = assert(eventData.priority, "'update-rule' needs `priority`")
        rule.kind = assert(eventData.kind, "'update-rule' needs `kind`")
        rule.description = assert(eventData.description, "'update-rule' needs `description`")
        rule.code = assert(eventData.code, "'update-rule' needs `code`")
    end

    if eventType == 'spawn-entity' then
        assert(eventData.id, "'spawn-entity' needs `id`")
        assert(eventData.type, "'spawn-entity' needs `type`")
        self:spawnEntity(eventData)
    end
end

local network, server, client = simulsim.createGameNetwork(game, { mode = SIMULSIM_MODE or 'local' })

function server.load(self)
    self:fireEvent('add-rule', {
        id = generateId(),
        priority = 0,
        kind = 'draw',
        description = 'draw circles',
        code = [[
self:forEachEntityWhere({ type = 'circle' }, function(e)
    L.circle('fill', e.x, e.y, e.radius)
end)
]],
    })
    self:fireEvent('spawn-entity', {
        id = generateId(),
        type = 'circle',
        x = math.random(0, L.getWidth()),
        y = math.random(0, L.getHeight()),
        radius = math.random(20, 40),
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
            L.stacked('all', function()
                callRule(rule, self.game)
            end)
        end
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
    local selectedEntityId

    function castle.uiupdate()
        local self = clientSelf
        if not (self and self.game) then
            return
        end

        L.ui.tabs('top', function()
            L.ui.tab('rules', function()
                -- Button to add new rule
                if L.ui.button('new rule') then
                    self:fireEvent('add-rule', {
                        id = generateId(),
                        clientId = self.clientId,
                        priority = 0,
                        kind = 'draw',
                        description = 'new rule',
                        code = '',
                    })
                end
                L.ui.box('spacer', { width = '100%', height = 14 }, function() end)

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
                        self.game:temporarilyDisableSyncForEntity(selectedRule)
                        self:fireEvent('update-rule', newRule, { maxFramesLate = 120 })
                    end
                end
            end)

            L.ui.tab('entities', function()
                -- Button to add new entity
                if L.ui.button('new entity') then
                    self:fireEvent('spawn-entity', {
                        id = generateId(),
                        type = 'circle',
                        x = math.random(0, L.getWidth()),
                        y = math.random(0, L.getHeight()),
                        radius = math.random(20, 40),
                    })
                end
                L.ui.box('spacer', { width = '100%', height = 14 }, function() end)

                -- Dropdown to select entity
                local selectedEntity
                do
                    local selectedEntityLine
                    local entityLines = {}
                    local entityLineToEntityId = {}
                    for _, entity in pairs(self.game:getEntitiesWhere(function(e)
                        return e.id and e.type ~= 'rule'
                    end)) do
                        local entityLine = entity.type .. ' (' .. entity.id .. ')'
                        table.insert(entityLines, entityLine)
                        entityLineToEntityId[entityLine] = entity.id
                        if entity.id == selectedEntityId then
                            selectedEntityLine = entityLine
                        end
                    end
                    local selectedEntityLine = L.ui.dropdown('entity', selectedEntityLine, entityLines, {
                        placeholder = 'select a entity...'
                    })
                    selectedEntityId = entityLineToEntityId[selectedEntityLine]

                    selectedEntity = self.game:getEntityById(selectedEntityId)
                    if not selectedEntity then
                        selectedEntityId = nil
                    end
                end

                -- Editor for selected entity
                if selectedEntity then
                    local pretty = serpent.block(selectedEntity)
                    L.ui.markdown('```\n' .. pretty .. '\n```')
                end
            end)
        end)
    end
end
