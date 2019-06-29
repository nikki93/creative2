L = require 'https://raw.githubusercontent.com/nikki93/L/3f63e72eef6b19a9bab9a937e17e527ae4e22230/L.lua'
serpent = require 'https://raw.githubusercontent.com/pkulchenko/serpent/879580fb21933f63eb23ece7d60ba2349a8d2848/src/serpent.lua'

simulsim = require 'https://raw.githubusercontent.com/nikki93/simulsim/6ce85976c13545613810677af67f2f2fc1cc4e2d/simulsim.lua'


local WIDTH, HEIGHT = 800, 450


local function uiSpacer()
    L.ui.box('spacer', { width = '100%', height = 14 }, function() end)
    L.ui.markdown('---')
    L.ui.box('spacer', { width = '100%', height = 14 }, function() end)
end


local errCache = {}

local function reportError(rule, err)
    local file, line, message = err:match('^(.-):(%d+):(.+)')
    file = file:gsub('^%[string "', '')
    file = file:gsub('"%]$', '')

    message = message:match('^[^\n]*')

    local cacheKey = rule.id .. file .. line .. message
    local cached = errCache[cacheKey]
    if cached then
        cached.count = cached.count + 1
        cached.time = L.getTime()
    else
        cached = {}
        errCache[cacheKey] = cached
        cached.short = file:gsub(' %(' .. rule.id .. '%)', '') .. ':' .. line .. ':' .. message .. ' (' .. rule.id .. ')'
        cached.key = rule.cacheKey
        cached.ruleId = rule.id
        cached.file = file
        cached.line = line
        cached.message = message
        cached.full = err
        cached.count = 1
        cached.time = L.getTime()

        print("ERROR: New error in rule '" .. rule.description .. "' (" .. rule.id .. "):\n" .. message)
    end
end


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
        local cacheKey = rule.id .. L.data.hash('md5', rule.code)

        local cached = compileCache[cacheKey]
        if cached then
            return cached
        end

        local env = setmetatable({}, { __index = _G })
        local compiled, err = load(rule.code, rule.description:sub(1, 24) .. ' (' .. rule.id .. ')', 't', env)
        if not compiled then
            reportError(rule, err)
            return
        end
        local succeeded, err = xpcall(compiled, debug.traceback)
        if not succeeded then
            reportError(rule, err)
            return
        end

        compileCache[cacheKey] = env
        return env
    end

    function callRule(rule, funcName, ...)
        local compiled = compileRule(rule)
        if compiled then
            local func = compiled[funcName]
            if not func then
                reportError(rule, "rule '" .. rule.id .. "' didn't define function '" .. funcName .. "'")
                return
            end
            local succeeded, err = xpcall(func, debug.traceback, ...)
            if not succeeded then
                reportError(rule, err)
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


local game = simulsim.defineGame()

function game:load()
end

function game:update(dt)
    local sortedRules = sortRules(self:getEntitiesWhere({ type = 'rule' }))
    for _, rule in ipairs(sortedRules) do
        if rule.kind == 'update' then
            callRule(rule, 'update', self, dt)
        end
    end
end

function game:handleEvent(eventType, eventData)
    if eventType == 'add-rule' then
        self:spawnEntity({
            type = 'rule',
            id = assert(eventData.id, "'add-rule' needs `id`"),
            priority = assert(eventData.priority, "'add-rule' needs `priority`"),
            kind = assert(eventData.kind, "'add-rule' needs `kind`"),
            description = assert(eventData.description, "'add-rule' needs `description`"),
            code = assert(eventData.code, "'add-rule' needs `code`"),
        })
    end
    if eventType == 'update-rule-prop' then
        assert(eventData.id, "'update-rule-prop' needs `id`")
        assert(eventData.propName, "'update-rule-prop' needs `propVal`")
        local rule = self:getEntityById(eventData.id)
        if rule then
            rule[eventData.propName] = eventData.propVal
        end
    end
    if eventType == 'remove-rule' then
        assert(eventData.id, "'remove-rule' needs `id`")
        local rule = self:getEntityById(eventData.id)
        if rule then
            self:despawnEntity(rule)
        end
    end

    if eventType == 'spawn-entity' then
        assert(eventData.id, "'spawn-entity' needs `id`")
        assert(eventData.type, "'spawn-entity' needs `type`")
        self:spawnEntity(eventData)
    end
    if eventType == 'update-entity-prop' then
        assert(eventData.id, "'update-entity-prop' needs `id`")
        assert(eventData.propName, "'update-entity-prop' needs `propName`")
        local entity = self:getEntityById(eventData.id)
        if entity then
            entity[eventData.propName] = eventData.propVal
        end
    end
    if eventType == 'despawn-entity' then
        assert(eventData.id, "'remove-rule' needs `id`")
        local entity = self:getEntityById(eventData.id)
        if entity then
            self:despawnEntity(entity)
        end
    end
end


local network, server, client = simulsim.createGameNetwork(game, { mode = SIMULSIM_MODE or 'localhost' })
-- local network, server, client = simulsim.createGameNetwork(game, {
--     mode = 'development',
--     numClients = 1,
--     latency = 0,
--     latencyDeviation = 0,
--     latencySpikeChance = 0,
--     packetLossChance = 0,
-- })

function server:load()
    self:fireEvent('add-rule', {
        id = generateId(),
        priority = 0,
        kind = 'draw',
        description = 'draw circles',
        code = [[
function draw(game)
    game:forEachEntityWhere({ type = 'circle' }, function(e)
        L.circle('fill', e.x, e.y, e.radius)
    end)
end
]],
    })
    self:fireEvent('spawn-entity', {
        id = generateId(),
        type = 'circle',
        x = math.random(0, WIDTH),
        y = math.random(0, HEIGHT),
        radius = math.random(20, 40),
    })
end

function server:clientconnected(client)
end

function server:clientdisconnected(client)
end

function client:draw()
    local sortedRules = sortRules(self.game:getEntitiesWhere({ type = 'rule' }))
    for _, rule in ipairs(sortedRules) do
        if rule.kind == 'draw' then
            L.stacked('all', function()
                callRule(rule, 'draw', self.game)
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

function client:isEntityUsingPrediction(entity)
    return true
end

local selectedRuleId
local selectedEntityId
local selectedErrShort

function client:uiupdate()
    L.ui.tabs('top', function()
        L.ui.tab('rules', function()
            -- Button to add new rule
            if L.ui.button('add rule') then
                local newId = generateId()
                self:fireEvent('add-rule', {
                    id = newId,
                    priority = 0,
                    kind = 'draw',
                    description = 'new rule',
                    code = [[
function draw(game)
end
]],
                }, { maxFramesLate = 120 })
                selectedRuleId = newId
            end
            uiSpacer()

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
                selectedRuleLine = L.ui.dropdown('rule', selectedRuleLine, ruleLines, {
                    placeholder = 'select a rule...'
                })
                selectedRuleId = ruleLineToRuleId[selectedRuleLine] or selectedRuleId

                selectedRule = self.game:getEntityById(selectedRuleId)
            end
            if selectedRule then
                if L.ui.button('remove rule') then
                    self:fireEvent('remove-rule', {
                        id = selectedRuleId
                    }, { maxFramesLate = 120 })
                    selectedRule, selectedRuleId = nil, nil
                end
            end
            uiSpacer()

            -- Editor for selected rule
            if selectedRule then
                L.ui.box('editor-' .. selectedRuleId, function()
                    local function onChange(propName)
                        return function(newVal)
                            self.game:temporarilyDisableSyncForEntity(selectedRule)
                            self:fireEvent('update-rule-prop', {
                                id = selectedRule.id,
                                propName = propName,
                                propVal = newVal,
                            })
                        end
                    end

                    L.ui.dropdown('kind', selectedRule.kind, {
                        'draw', 'update', 'ui',
                    }, {
                        onChange = onChange('kind'),
                    })

                    L.ui.textInput('description', selectedRule.description, {
                        maxLength = 80,
                        onChange = onChange('description'),
                    })

                    L.ui.numberInput('priority', selectedRule.priority, {
                        onChange = onChange('priority'),
                    })

                    L.ui.codeEditor('code', selectedRule.code, {
                        onChange = onChange('code'),
                    })
                end)
            end
        end)

        L.ui.tab('entities', function()
            -- Button to add new entity
            if L.ui.button('add entity') then
                local newId = generateId()
                self:fireEvent('spawn-entity', {
                    id = newId,
                    type = 'circle',
                    x = math.random(0, WIDTH),
                    y = math.random(0, HEIGHT),
                    radius = math.random(20, 40),
                }, { maxFramesLate = 120 })
                selectedEntityId = newId
            end
            uiSpacer()

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
                selectedEntityLine = L.ui.dropdown('entity', selectedEntityLine, entityLines, {
                    placeholder = 'select a entity...'
                })
                selectedEntityId = entityLineToEntityId[selectedEntityLine] or selectedEntityId

                selectedEntity = self.game:getEntityById(selectedEntityId)
            end
            if selectedEntity then
                if L.ui.button('remove entity') then
                    self:fireEvent('despawn-entity', {
                        id = selectedEntityId
                    }, { maxFramesLate = 120 })
                    selectedEntity, selectedEntityId = nil, nil
                end
            end
            uiSpacer()

            -- Editor for selected entity
            if selectedEntity then
                L.ui.box('editor-' .. selectedEntityId, function()
                    local pretty = serpent.block(selectedEntity)

                    local sortedPropNames = {}
                    for propName in pairs(selectedEntity) do
                        if propName ~= 'id' then
                            table.insert(sortedPropNames, propName)
                        end
                    end
                    table.sort(sortedPropNames, function(a, b)
                        if a == 'type' then
                            return true
                        end
                        if b == 'type' then
                            return false
                        end
                        return a < b
                    end)

                    for _, propName in ipairs(sortedPropNames) do
                        local propVal = selectedEntity[propName]
                        local newPropVal

                        local propType = type(propVal)

                        if propType == 'number' then
                            newPropVal = L.ui.numberInput(propName, propVal)
                        elseif propType == 'string' then
                            newPropVal = L.ui.textInput(propName, propVal)
                        elseif propType == 'boolean' then
                            newPropVal = L.ui.checkbox(propName, propVal)
                        end

                        if newPropVal ~= propVal then
                            self.game:temporarilyDisableSyncForEntity(selectedEntity)
                            self:fireEvent('update-entity-prop', {
                                id = selectedEntity.id,
                                propName = propName,
                                propVal = newPropVal,
                            }, { maxFramesLate = 120 })
                        end
                    end
                end)
            end
        end)

        L.ui.tab('errors', function()
            local sortedErrs = {}
            for _, err in pairs(errCache) do
                table.insert(sortedErrs, err)
            end
            table.sort(sortedErrs, function(e1, e2)
                return e1.time > e2.time
            end)

            local selectedErr
            local errShorts = {}
            local errShortToErrKey = {}
            for i = 1, #sortedErrs do
                local err = sortedErrs[i]
                table.insert(errShorts, err.short)
                errShortToErrKey[err.short] = err.key
                if selectedErrShort == err.short then
                    selectedErr = err
                end
            end
            selectedErrShort = L.ui.dropdown('error', selectedErrShort, errShorts, {
                placeholder = 'select an error...',
            })

            if selectedErr then
                L.ui.markdown(
                    '```\n' ..
                    'rule: ' .. selectedErr.ruleId .. '\n' ..
                    'count: ' .. selectedErr.count .. '\n' ..
                    'file: ' .. selectedErr.file .. '\n' ..
                    'line: ' .. selectedErr.line .. '\n' ..
                    'stacktrace:\n' .. selectedErr.full .. '\n' ..
                    '```'
                )
            end
        end)
    end)
end
