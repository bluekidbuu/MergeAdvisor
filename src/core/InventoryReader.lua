-- InventoryReader.lua
-- Scanner read-only + live change watcher untuk inventory AnimalTool.

local InventoryReader = {}

local function readValue(tool, key)
    local ok, value = pcall(function() return tool:GetAttribute(key) end)
    if ok and value ~= nil then return value end
    local child = tool:FindFirstChild(key, true)
    if child and child:IsA("ValueBase") then
        local success, result = pcall(function() return child.Value end)
        if success then return result end
    end
    return nil
end

local function isOwnedTool(tool, player)
    if not tool or not tool:IsA("Tool") then return false end
    local backpack = player:FindFirstChildOfClass("Backpack") or player:FindFirstChild("Backpack")
    local character = player.Character
    return (backpack and tool:IsDescendantOf(backpack))
        or (character and tool:IsDescendantOf(character))
end

local function validString(value)
    return type(value) == "string" and value ~= ""
end

local function safeFullName(instance)
    local ok, result = pcall(function() return instance:GetFullName() end)
    return ok and result or (instance and instance.Name or "Unknown")
end

function InventoryReader.ReadValue(tool, key)
    return readValue(tool, key)
end

function InventoryReader.Scan(player, collectionService, incomeCalculator, configs)
    assert(player, "Player wajib tersedia")
    assert(collectionService, "CollectionService wajib tersedia")
    assert(incomeCalculator, "IncomeCalculator wajib tersedia")
    assert(configs, "Game configs wajib tersedia")

    local pets, diagnostics, tools, seen = {}, {}, {}, {}
    for _, tool in ipairs(collectionService:GetTagged("AnimalTool")) do
        if isOwnedTool(tool, player) and not seen[tool] then
            seen[tool] = true
            table.insert(tools, tool)
        end
    end

    for _, tool in ipairs(tools) do
        local tagged = false
        pcall(function() tagged = collectionService:HasTag(tool, "AnimalTool") end)
        if tagged then
            local name = readValue(tool, "AnimalName")
            local weight = readValue(tool, "WeightKg")
            if not validString(name) then
                local fallback = tool.Name
                if validString(fallback) and fallback ~= "Tool" then name = fallback end
            end

            local reason
            if not validString(name) then
                reason = "AnimalName dan nama Tool tidak tersedia"
            elseif type(weight) ~= "number" or weight <= 0 then
                reason = "WeightKg hilang atau tidak valid"
            else
                local variant = readValue(tool, "Variant")
                local mutation = readValue(tool, "Mutation")
                local size = readValue(tool, "SizeMult")
                local enchant = readValue(tool, "Enchant")
                local pet = {
                    name = name, AnimalName = name, Name = name,
                    kg = weight, WeightKg = weight,
                    var = validString(variant) and variant or nil,
                    Variant = validString(variant) and variant or nil,
                    mut = validString(mutation) and mutation or nil,
                    Mutation = validString(mutation) and mutation or nil,
                    size = type(size) == "number" and size or nil,
                    SizeMult = type(size) == "number" and size or nil,
                    enchant = validString(enchant) and enchant or nil,
                    Enchant = validString(enchant) and enchant or nil,
                    tool = tool, Tool = tool,
                }

                local ok, income = pcall(function()
                    return incomeCalculator.CalculateFromGame(
                        configs, name, pet.size, pet.mut, weight, pet.var, pet.enchant
                    )
                end)
                if ok and type(income) == "number" and income >= 0 then
                    pet.income = income
                    pet.Income = income
                    pet.CashPerSecond = income
                    pet.PlacedCashPerSecond = income
                    table.insert(pets, pet)
                else
                    reason = "Income gagal dihitung: " .. tostring(income)
                end
            end

            if reason then
                table.insert(diagnostics, "[SKIP] " .. safeFullName(tool) .. " | " .. reason)
            end
        end
    end

    return pets, diagnostics, #tools
end

-- Live watcher: perubahan atribut/ValueObject, isi Backpack/Character,
-- serta tag AnimalTool memicu scan ulang dengan debounce.
function InventoryReader.Watch(player, collectionService, callback, debounceSeconds)
    assert(player and collectionService and type(callback) == "function",
        "Watch membutuhkan player, CollectionService, dan callback")

    local delaySeconds = tonumber(debounceSeconds) or 0.5
    local alive, pending = true, false
    local connections, toolConnections = {}, {}

    local function connect(signal, handler, bucket)
        if not signal then return end
        local ok, connection = pcall(function() return signal:Connect(handler) end)
        if ok and connection then table.insert(bucket or connections, connection) end
    end

    local function schedule()
        if not alive or pending then return end
        pending = true
        task.delay(delaySeconds, function()
            pending = false
            if alive then
                local ok, err = pcall(callback)
                if not ok then warn("[MergeAdvisor] Auto-refresh gagal: " .. tostring(err)) end
            end
        end)
    end

    local function watchTool(tool)
        if not tool or not tool:IsA("Tool") or toolConnections[tool] then return end
        local bucket, watchedValues = {}, {}
        toolConnections[tool] = bucket

        local function watchValue(instance)
            if not instance:IsA("ValueBase") or watchedValues[instance] then return end
            watchedValues[instance] = true
            connect(instance.Changed, schedule, bucket)
        end

        connect(tool.AttributeChanged, schedule, bucket)
        connect(tool.DescendantAdded, function(instance)
            watchValue(instance)
            schedule()
        end, bucket)
        connect(tool.AncestryChanged, schedule, bucket)
        for _, descendant in ipairs(tool:GetDescendants()) do watchValue(descendant) end
    end

    local function unwatchTool(tool)
        local bucket = toolConnections[tool]
        if not bucket then return end
        for _, connection in ipairs(bucket) do
            pcall(function() connection:Disconnect() end)
        end
        toolConnections[tool] = nil
    end

    local function watchContainer(container)
        if not container then return end
        connect(container.ChildAdded, function(child)
            if child:IsA("Tool") then watchTool(child) end
            schedule()
        end)
        connect(container.ChildRemoved, schedule)
        connect(container.DescendantAdded, function(instance)
            if instance:IsA("Tool") then watchTool(instance) end
        end)
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") then watchTool(child) end
        end
    end

    local backpack = player:FindFirstChildOfClass("Backpack") or player:FindFirstChild("Backpack")
    watchContainer(backpack)
    watchContainer(player.Character)

    connect(player.ChildAdded, function(child)
        if child:IsA("Backpack") then watchContainer(child); schedule() end
    end)
    connect(player.CharacterAdded, function(character)
        watchContainer(character)
        schedule()
    end)
    connect(collectionService:GetInstanceAddedSignal("AnimalTool"), function(instance)
        if isOwnedTool(instance, player) then watchTool(instance) end
        schedule()
    end)
    connect(collectionService:GetInstanceRemovedSignal("AnimalTool"), function(instance)
        unwatchTool(instance)
        schedule()
    end)

    for _, tool in ipairs(collectionService:GetTagged("AnimalTool")) do
        if isOwnedTool(tool, player) then watchTool(tool) end
    end

    local handle = {}
    function handle.Disconnect()
        if not alive then return end
        alive = false
        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
        for tool in pairs(toolConnections) do unwatchTool(tool) end
        table.clear(connections)
    end
    handle.Destroy = handle.Disconnect
    return handle
end

return InventoryReader
