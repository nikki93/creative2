L = require 'https://raw.githubusercontent.com/nikki93/L/3f63e72eef6b19a9bab9a937e17e527ae4e22230/L.lua'
serpent = require 'https://raw.githubusercontent.com/pkulchenko/serpent/879580fb21933f63eb23ece7d60ba2349a8d2848/src/serpent.lua'

local simulsim = require 'https://raw.githubusercontent.com/nikki93/simulsim/2f70863464fe1b573d1f07d947cdebbd9f710451/simulsim.lua'

local WIDTH, HEIGHT = 800, 450

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

function game.load(self)
end

function game.update(self, dt)
    local sortedRules = sortRules(self:getEntitiesWhere({ type = 'rule' }))
    for _, rule in ipairs(sortedRules) do
        if rule.kind == 'update' then
            callRule(rule, 'update', self, dt)
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
        if rule then
            rule.clientId = eventData.clientId
            rule.priority = assert(eventData.priority, "'update-rule' needs `priority`")
            rule.kind = assert(eventData.kind, "'update-rule' needs `kind`")
            rule.description = assert(eventData.description, "'update-rule' needs `description`")
            rule.code = assert(eventData.code, "'update-rule' needs `code`")
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
        assert(eventData.propVal, "'update-entity-prop' needs `propVal`")
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

local network, server, client = simulsim.createGameNetwork(game, { mode = SIMULSIM_MODE or 'local' })

function server.load(self)
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

do
    local selectedRuleId
    local selectedEntityId
    local selectedErrShort

    function castle.uiupdate()
        local self = clientSelf
        if not (self and self.game) then
            return
        end

        L.ui.tabs('top', function()
            L.ui.tab('rules', function()
                -- Button to add new rule
                if L.ui.button('add rule') then
                    local newId = generateId()
                    self:fireEvent('add-rule', {
                        id = newId,
                        clientId = self.clientId,
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
                L.ui.box('spacer', { width = '100%', height = 14 }, function() end)
                L.ui.markdown('---')
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
                    selectedRuleLine = L.ui.dropdown('rule', selectedRuleLine, ruleLines, {
                        placeholder = 'select a rule...'
                    })
                    selectedRuleId = ruleLineToRuleId[selectedRuleLine]

                    selectedRule = self.game:getEntityById(selectedRuleId)
                end
                if selectedRule then
                    if L.ui.button('remove rule') then
                        self:fireEvent('remove-rule', {
                            id = selectedRuleId
                        })
                        selectedRule, selectedRuleId = nil, nil
                    end
                end
                L.ui.box('spacer', { width = '100%', height = 14 }, function() end)
                L.ui.markdown('---')
                L.ui.box('spacer', { width = '100%', height = 14 }, function() end)

                -- Editor for selected rule
                if selectedRule then
                    L.ui.box('editor-' .. selectedRuleId, function()
                        local newRule = {}
                        for k, v in pairs(selectedRule) do
                            newRule[k] = v
                        end

                        newRule.kind = L.ui.dropdown('kind', selectedRule.kind, {
                            'draw', 'update', 'ui',
                        })

                        newRule.description = L.ui.textInput('description', selectedRule.description, {
                            maxLength = 80,
                        })

                        newRule.priority = L.ui.numberInput('priority', selectedRule.priority)

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
                L.ui.box('spacer', { width = '100%', height = 14 }, function() end)
                L.ui.markdown('---')
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
                    selectedEntityLine = L.ui.dropdown('entity', selectedEntityLine, entityLines, {
                        placeholder = 'select a entity...'
                    })
                    selectedEntityId = entityLineToEntityId[selectedEntityLine]

                    selectedEntity = self.game:getEntityById(selectedEntityId)
                end
                if selectedEntity then
                    if L.ui.button('remove entity') then
                        self:fireEvent('despawn-entity', {
                            id = selectedEntityId
                        })
                        selectedEntity, selectedEntityId = nil, nil
                    end
                end
                L.ui.box('spacer', { width = '100%', height = 14 }, function() end)
                L.ui.markdown('---')
                L.ui.box('spacer', { width = '100%', height = 14 }, function() end)

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
                                self:fireEvent('update-entity-prop', {
                                    id = selectedEntity.id,
                                    propName = propName,
                                    propVal = newPropVal,
                                })
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
end
