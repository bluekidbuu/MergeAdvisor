-- MERGE ADVISOR
-- Generated automatically by tools/build.py
-- Do not edit this generated file directly.

-- MODULE: src/core/GameConfigLoader.lua
local GameConfigLoader = (function()
-- GameConfigLoader
-- Memuat konfigurasi asli dari ReplicatedStorage.Shared.
-- Mengikuti mekanisme MergeAdvisor v10.2.0.

local GameConfigLoader = {}

local REQUIRED = {
    "EggRewards",
    "MergeConfig",
}

local OPTIONAL = {
    "FormatNumber",
    "AnimalRenders",
    "ZoneAnimalsConfig",
    "EggRarity",
    "MutationConfig",
    "EnchantConfig",
}

local function loadModule(shared, name)
    local module = shared and shared:FindFirstChild(name)

    if not module then
        return nil, "Module tidak ditemukan: " .. name
    end

    local ok, result = pcall(require, module)

    if not ok then
        return nil, "Require gagal (" .. name .. "): " .. tostring(result)
    end

    if type(result) ~= "table" then
        return nil, name .. " tidak mengembalikan table"
    end

    return result
end

function GameConfigLoader.Load(replicatedStorage)
    if not replicatedStorage then
        return nil, {Shared = "ReplicatedStorage tidak tersedia"}
    end

    local shared = replicatedStorage:FindFirstChild("Shared")

    if not shared then
        return nil, {
            Shared = "ReplicatedStorage.Shared tidak ditemukan"
        }
    end

    local modules = {}
    local errors = {}

    for _, name in ipairs(REQUIRED) do
        local result, err = loadModule(shared, name)

        if result then
            modules[name] = result
        else
            errors[name] = err
        end
    end

    for _, name in ipairs(OPTIONAL) do
        local result, err = loadModule(shared, name)

        if result then
            modules[name] = result
        else
            errors[name] = err
        end
    end

    if not modules.EggRewards or not modules.MergeConfig then
        return nil, errors
    end

    local requiredFunctions = {
        {modules.EggRewards, "PlacedCashPerSecond"},
        {modules.MergeConfig, "VariantOdds"},
        {modules.MergeConfig, "MutationOdds"},
    }

    for _, item in ipairs(requiredFunctions) do
        if type(item[1][item[2]]) ~= "function" then
            return nil, {
                API = "API game tidak cocok: " .. item[2]
            }
        end
    end

    modules.SlotCount = modules.MergeConfig.SlotCount or 3
    modules.Errors = errors
    modules.Shared = shared

    return modules, errors
end

return GameConfigLoader
end)()

-- MODULE: src/core/InventoryReader.lua
local InventoryReader = (function()
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
end)()

-- MODULE: src/calculators/IncomeCalculator.lua
local IncomeCalculator = (function()
-- IncomeCalculator.lua
-- Source-based implementation of EggRewards.PlacedCashPerSecond.
-- Calculates income for ONE placed animal.

local IncomeCalculator = {}

local function isNumber(value)
    return type(value) == "number" and value == value
end

local function numberOr(value, fallback)
    if isNumber(value) then
        return value
    end
    return fallback
end

local function getAnimalInfo(animalName, source)
    if type(source) == "function" then
        return source(animalName)
    elseif type(source) == "table" then
        return source[animalName]
    end
    return nil
end

local function getMultiplier(source, methodName, value, fallback)
    if type(source) == "function" then
        return numberOr(source(value), fallback)
    end

    if type(source) == "table" then
        local method = source[methodName]
        if type(method) == "function" then
            return numberOr(method(value), fallback)
        elseif type(method) == "number" then
            return method
        end
    end

    return fallback
end

local function getZoneValue(values, zone, fallback)
    if type(values) ~= "table" then
        return fallback
    end

    local value = values[zone]
    if isNumber(value) then
        return value
    end

    -- Source falls back to the first exponent for unknown zones.
    value = values[1]
    if isNumber(value) then
        return value
    end

    return fallback
end

local function getAnimalBaseKg(animalName, info, weightConfig)
    local animalKg = weightConfig.AnimalKg

    if type(animalKg) == "table"
        and isNumber(animalKg[animalName]) then
        return animalKg[animalName]
    end

    local baseKg = weightConfig.BaseKg
    local rarity = info and info.Rarity

    if type(baseKg) == "table" then
        if rarity and isNumber(baseKg[rarity]) then
            return baseKg[rarity]
        end

        if isNumber(baseKg.Common) then
            return baseKg.Common
        end
    end

    return 50
end

local function cashSizeMultiplier(sizeMult, reference, config)
    local size = math.max(numberOr(sizeMult, 1), 0)
    local x = size / math.max(reference, 0.01)

    local knee = numberOr(config.CashSizeKnee, 2)
    local exponent = numberOr(config.CashSizeExponent, 3)
    local tail = numberOr(config.CashSizeTailExponent, 1)

    local multiplier

    if x <= knee then
        multiplier = x ^ exponent
    else
        multiplier = knee ^ exponent * (x / knee) ^ tail
    end

    return math.max(multiplier, numberOr(config.CashSizeMultMin, 0.2))
end

local function cashWeightMultiplier(weightKg, baseKg, reference, zone, config)
    local exponent = getZoneValue(config.CashWeightExponent, zone, 1.1)
    local tail = getZoneValue(config.CashWeightTailExponent, zone, 0.55)
    local knee = numberOr(config.CashWeightKnee, 8)

    local x = weightKg / (baseKg * math.max(reference, 0.01) ^ 3)
    local multiplier

    if x <= knee then
        multiplier = x ^ exponent
    else
        multiplier = knee ^ exponent * (x / knee) ^ tail
    end

    return math.max(multiplier, numberOr(config.CashSizeMultMin, 0.2))
end

local function speciesWeightCashMultiplier(baseKg, config)
    local anchor = numberOr(config.CashSpeciesAnchorKg, 50)
    local exponent = numberOr(config.CashSpeciesWeightExponent, 0.5)
    local maximum = numberOr(config.CashSpeciesWeightMax, 3)

    return math.clamp((baseKg / anchor) ^ exponent, 1, maximum)
end

-- Dependencies:
-- AnimalInfo: function(animalName) or table keyed by AnimalName
-- WeightConfig: extracted Weight configuration
-- MutationConfig: exposes CashMult(mutation)
-- EnchantConfig: exposes CashMult(enchantAttribute)
-- VariantCashMult: function(variant), optional
--
-- Input:
-- {
--     AnimalName = "Dreki",
--     SizeMult = 1,
--     WeightKg = 170,
--     Mutation = "Normal",
--     Variant = "Normal",
--     Enchant = "Cash:1"
-- }
--
-- Returns: incomePerSecond, breakdown

function IncomeCalculator.Calculate(animal, dependencies)
    assert(type(animal) == "table", "animal must be a table")
    assert(type(dependencies) == "table", "dependencies must be a table")
    assert(type(animal.AnimalName) == "string",
        "animal.AnimalName is required")

    local name = animal.AnimalName
    local info = getAnimalInfo(name, dependencies.AnimalInfo)
    local config = dependencies.WeightConfig

    assert(type(info) == "table", "AnimalInfo not found: " .. name)
    assert(type(config) == "table", "WeightConfig is required")

    local baseCash = numberOr(info.Cash, 1)
    local baseKg = getAnimalBaseKg(name, info, config)

    local zone = info.Zone or info.CashZone or 1

    -- Important: SizeReferenceFor uses [zone] or 1.
    -- It does NOT fall back to index 1 for an unknown zone.
    local sizeReferences = config.CashSizeReference
    local sizeReference = 1

    if type(sizeReferences) == "table"
        and isNumber(sizeReferences[zone]) then
        sizeReference = sizeReferences[zone]
    end

    local weightKg = numberOr(animal.WeightKg, 0)
    local sizeMult = numberOr(animal.SizeMult, 1)

    local weightMultiplier
    local weightSource

    -- Source uses WeightKg when > 0; otherwise it uses SizeMult.
    if weightKg > 0 then
        weightMultiplier = cashWeightMultiplier(
            weightKg, baseKg, sizeReference, zone, config
        )
        weightSource = "WeightKg"
    else
        weightMultiplier = cashSizeMultiplier(
            sizeMult, sizeReference, config
        )
        weightSource = "SizeMult"
    end

    local speciesMultiplier =
        speciesWeightCashMultiplier(baseKg, config)

    local mutationMultiplier = getMultiplier(
        dependencies.MutationConfig,
        "CashMult",
        animal.Mutation,
        1
    )

    local variantMultiplier = getMultiplier(
        dependencies.VariantCashMult,
        "CashMult",
        animal.Variant,
        1
    )

    local enchantMultiplier = getMultiplier(
        dependencies.EnchantConfig,
        "CashMult",
        animal.Enchant,
        1
    )

    local raw = baseCash
        * weightMultiplier
        * speciesMultiplier
        * mutationMultiplier
        * variantMultiplier
        * enchantMultiplier

    -- Matches source: floor(raw + 0.5), minimum 1.
    local income = math.max(math.floor(raw + 0.5), 1)

    local breakdown = {
        AnimalName = name,
        BaseCash = baseCash,
        BaseKg = baseKg,
        Zone = zone,
        SizeReference = sizeReference,
        WeightSource = weightSource,
        WeightMultiplier = weightMultiplier,
        SpeciesMultiplier = speciesMultiplier,
        MutationMultiplier = mutationMultiplier,
        VariantMultiplier = variantMultiplier,
        EnchantMultiplier = enchantMultiplier,
        RawIncome = raw,
        IncomePerSecond = income,
    }

    return income, breakdown
end


-- Menggunakan kalkulator income ASLI dari game.
-- Parameter mengikuti EggRewards.PlacedCashPerSecond.

function IncomeCalculator.CalculateFromGame(
    configs,
    animalName,
    sizeMult,
    mutation,
    weightKg,
    variant,
    enchant
)
    assert(configs and configs.EggRewards,
        "EggRewards belum dimuat")

    local eggRewards = configs.EggRewards
    assert(type(eggRewards.PlacedCashPerSecond) == "function",
        "PlacedCashPerSecond tidak tersedia")

    local enchantConfig = configs.EnchantConfig

    if enchantConfig and type(enchantConfig.CashMult) == "function" then
        return eggRewards.PlacedCashPerSecond(
            animalName,
            sizeMult,
            mutation,
            weightKg,
            variant,
            enchant
        )
    end

    return eggRewards.PlacedCashPerSecond(
        animalName,
        sizeMult,
        mutation,
        weightKg,
        variant
    )
end

return IncomeCalculator
end)()

-- MODULE: src/ui/MainWindow.lua
local MainWindow = (function()
-- MainWindow.lua
-- GUI diagnostik dengan output scrollable untuk inventory panjang.

local MainWindow = {}

function MainWindow.Create(playerGui)
    local old = playerGui:FindFirstChild("MergeAdvisorModular")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "MergeAdvisorModular"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.fromOffset(350, 430)
    frame.Position = UDim2.new(0.5, -175, 0.5, -215)
    frame.BackgroundColor3 = Color3.fromRGB(23, 26, 34)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(65, 76, 96)
    stroke.Thickness = 1

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 38)
    title.Position = UDim2.fromOffset(10, 5)
    title.BackgroundTransparency = 1
    title.Text = "MERGE ADVISOR"
    title.TextColor3 = Color3.fromRGB(235, 240, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 17
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.Size = UDim2.new(1, -20, 0, 25)
    status.Position = UDim2.fromOffset(10, 43)
    status.BackgroundTransparency = 1
    status.Text = "Status: Starting..."
    status.TextColor3 = Color3.fromRGB(255, 205, 100)
    status.Font = Enum.Font.Gotham
    status.TextSize = 11
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextTruncate = Enum.TextTruncate.AtEnd
    status.Parent = frame

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "ReportScroll"
    scroll.Position = UDim2.fromOffset(10, 72)
    scroll.Size = UDim2.new(1, -20, 1, -125)
    scroll.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 5
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.Parent = frame
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)

    local output = Instance.new("TextLabel")
    output.Name = "Output"
    output.BackgroundTransparency = 1
    output.Position = UDim2.fromOffset(8, 7)
    output.Size = UDim2.new(1, -16, 0, 0)
    output.AutomaticSize = Enum.AutomaticSize.Y
    output.TextColor3 = Color3.fromRGB(215, 225, 240)
    output.Font = Enum.Font.Code
    output.TextSize = 11
    output.TextXAlignment = Enum.TextXAlignment.Left
    output.TextYAlignment = Enum.TextYAlignment.Top
    output.TextWrapped = true
    output.Text = "Menunggu data..."
    output.Parent = scroll

    local function makeButton(name, text, x, width)
        local button = Instance.new("TextButton")
        button.Name = name
        button.Size = UDim2.new(0, width, 0, 34)
        button.Position = UDim2.new(0, x, 1, -43)
        button.BackgroundColor3 = Color3.fromRGB(48, 91, 155)
        button.BorderSizePixel = 0
        button.Text = text
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Font = Enum.Font.GothamBold
        button.TextSize = 12
        button.Parent = frame
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
        return button
    end

    local refresh = makeButton("Refresh", "REFRESH", 10, 160)
    local copy = makeButton("Copy", "COPY REPORT", 180, 160)

    local UserInputService = game:GetService("UserInputService")
    local dragging, dragStart, startPosition = false, nil, nil
    local dragConnections = {}
    table.insert(dragConnections, title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = frame.Position
        end
    end))
    table.insert(dragConnections, title.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
    table.insert(dragConnections, UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X,
                startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end))

    local api = {}
    function api.SetStatus(text, success)
        status.Text = "Status: " .. tostring(text)
        status.TextColor3 = success and Color3.fromRGB(120, 230, 150)
            or Color3.fromRGB(255, 190, 100)
    end
    function api.SetText(text)
        output.Text = tostring(text)
        scroll.CanvasPosition = Vector2.new(0, 0)
    end
    function api.OnRefresh(callback) refresh.Activated:Connect(callback) end
    function api.OnCopy(callback) copy.Activated:Connect(callback) end
    function api.Destroy()
        for _, connection in ipairs(dragConnections) do
            pcall(function() connection:Disconnect() end)
        end
        gui:Destroy()
    end
    return api
end

return MainWindow
end)()

-- MODULE: src/core/Bootstrap.lua
local Bootstrap = (function()
-- Bootstrap.lua
-- Penghubung konfigurasi, inventory, live refresh, dan GUI.

local Bootstrap = {}

local function safeString(value)
    if value == nil then return "-" end
    return tostring(value)
end

local function getIncome(animal)
    return tonumber(animal.Income or animal.CashPerSecond
        or animal.PlacedCashPerSecond or animal.income) or 0
end

local function getAnimalName(animal)
    return safeString(animal.AnimalName or animal.Name or animal.name or animal.ToolName)
end

local function formatIncome(value)
    if value >= 1e12 then return string.format("%.2fT/s", value / 1e12)
    elseif value >= 1e9 then return string.format("%.2fB/s", value / 1e9)
    elseif value >= 1e6 then return string.format("%.2fM/s", value / 1e6)
    elseif value >= 1e3 then return string.format("%.2fK/s", value / 1e3) end
    return string.format("%.2f/s", value)
end

local function sortedErrorMessages(errors, prefix)
    local result, keys = {}, {}
    if type(errors) ~= "table" then return result end
    for key in pairs(errors) do table.insert(keys, key) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local value = errors[key]
        if type(value) == "table" then
            table.insert(result, (prefix or "") .. tostring(key) .. ": "
                .. safeString(value.message or value.error or value))
        else
            table.insert(result, (prefix or "") .. tostring(key) .. ": " .. safeString(value))
        end
    end
    return result
end

function Bootstrap.Start(options)
    options = options or {}
    local modules = options.Modules or {}
    local ConfigLoader = assert(modules.GameConfigLoader, "GameConfigLoader belum dimasukkan")
    local InventoryReader = assert(modules.InventoryReader, "InventoryReader belum dimasukkan")
    local IncomeCalculator = assert(modules.IncomeCalculator, "IncomeCalculator belum dimasukkan")
    local MainWindow = assert(modules.MainWindow, "MainWindow belum dimasukkan")

    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local CollectionService = game:GetService("CollectionService")
    local player = Players.LocalPlayer
    assert(player, "LocalPlayer tidak ditemukan")

    local playerGui = player:FindFirstChildOfClass("PlayerGui")
        or player:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui tidak ditemukan")

    local window = MainWindow.Create(playerGui)
    local controller = {
        Configs = nil, Animals = {}, Diagnostics = {},
        TotalIncome = 0, LastReport = "", Destroyed = false,
        Watcher = nil, Refreshing = false, RefreshQueued = false,
    }

    local function makeReport(animals, diagnostics, totalIncome, scannedTools)
        local lines = {
            "MERGE ADVISOR",
            "==============================",
            "Player: " .. player.Name,
            "Hewan terbaca: " .. #animals
                .. (scannedTools and (" / " .. scannedTools .. " tagged") or ""),
            "TOTAL INCOME: " .. formatIncome(totalIncome),
            "",
            "INVENTORY",
            "------------------------------",
        }

        if #animals == 0 then table.insert(lines, "Belum ada hewan yang terbaca.") end
        for index, animal in ipairs(animals) do
            local name = getAnimalName(animal)
            local income = getIncome(animal)
            local kg = tonumber(animal.WeightKg or animal.kg)
            local variant = animal.Variant or animal.var or "-"
            local mutation = animal.Mutation or animal.mut or "-"
            local enchant = animal.Enchant or animal.enchant or "-"
            local details = {}
            if kg then table.insert(details, string.format("%.2f kg", kg)) end
            if variant ~= "-" then table.insert(details, "Var " .. tostring(variant)) end
            if mutation ~= "-" then table.insert(details, "Mut " .. tostring(mutation)) end
            if enchant ~= "-" then table.insert(details, "Enc " .. tostring(enchant)) end
            local suffix = #details > 0 and (" | " .. table.concat(details, " | ")) or ""
            table.insert(lines, string.format("%02d. %s | %s%s",
                index, name, formatIncome(income), suffix))
        end

        table.insert(lines, "")
        table.insert(lines, "DIAGNOSTIK")
        table.insert(lines, "------------------------------")
        if #diagnostics == 0 then
            table.insert(lines, "Tidak ada diagnostik tambahan.")
        else
            for _, message in ipairs(diagnostics) do
                table.insert(lines, "- " .. safeString(message))
            end
        end
        return table.concat(lines, "\n")
    end

    function controller.Refresh()
        if controller.Destroyed then return false, "Controller sudah dihentikan" end
        if controller.Refreshing then
            controller.RefreshQueued = true
            return false, "Refresh sedang berjalan"
        end
        controller.Refreshing = true
        window.SetStatus("Memuat konfigurasi...", false)

        local configOK, configs, configErrors = pcall(function()
            return ConfigLoader.Load(ReplicatedStorage)
        end)
        if not configOK or type(configs) ~= "table" then
            local messages = sortedErrorMessages(configErrors)
            local message = "ConfigLoader gagal: "
                .. safeString(configOK and "konfigurasi tidak valid" or configs)
            if #messages == 0 and type(configs) == "table" then
                messages = sortedErrorMessages(configs)
            end
            if #messages > 0 then message = message .. "\n" .. table.concat(messages, "\n") end
            controller.Diagnostics = messages
            controller.LastReport = message
            window.SetText(message)
            window.SetStatus("Config gagal", false)
            controller.Refreshing = false
            return false, message
        end

        controller.Configs = configs
        local diagnostics = sortedErrorMessages(configErrors, "[CONFIG] ")
        window.SetStatus("Membaca inventory...", false)

        local scanOK, animals, scanDiagnostics, scannedTools = pcall(function()
            return InventoryReader.Scan(player, CollectionService, IncomeCalculator, configs)
        end)
        if not scanOK then
            local message = "InventoryReader gagal: " .. safeString(animals)
            controller.LastReport = message
            window.SetText(message)
            window.SetStatus("Scan gagal", false)
            controller.Refreshing = false
            return false, message
        end

        if type(animals) ~= "table" then
            animals = {}
            table.insert(diagnostics, "InventoryReader tidak mengembalikan daftar hewan")
        end
        if type(scanDiagnostics) == "table" then
            for _, item in ipairs(scanDiagnostics) do table.insert(diagnostics, item) end
        end

        table.sort(animals, function(a, b) return getIncome(a) > getIncome(b) end)
        local totalIncome = 0
        for _, animal in ipairs(animals) do totalIncome = totalIncome + getIncome(animal) end

        controller.Animals = animals
        controller.Diagnostics = diagnostics
        controller.TotalIncome = totalIncome
        local report = makeReport(animals, diagnostics, totalIncome, scannedTools)
        controller.LastReport = report
        window.SetText(report)
        window.SetStatus("Selesai - " .. #animals .. " hewan | " .. formatIncome(totalIncome), true)
        controller.Refreshing = false

        if controller.RefreshQueued then
            controller.RefreshQueued = false
            task.defer(function()
                if not controller.Destroyed then controller.Refresh() end
            end)
        end
        return true, report
    end

    window.OnRefresh(function() controller.Refresh() end)
    window.OnCopy(function()
        local clipboard = setclipboard or toclipboard
        if type(clipboard) == "function" then
            local ok = pcall(clipboard, controller.LastReport)
            window.SetStatus(ok and "Report disalin" or "Gagal menyalin report", ok)
        else
            window.SetStatus("Clipboard tidak tersedia", false)
        end
    end)

    if type(InventoryReader.Watch) == "function" then
        local ok, watcher = pcall(function()
            return InventoryReader.Watch(player, CollectionService, function()
                if not controller.Destroyed then controller.Refresh() end
            end, options.RefreshDebounce or 0.5)
        end)
        if ok then
            controller.Watcher = watcher
        else
            table.insert(controller.Diagnostics, "Auto-refresh watcher gagal: " .. tostring(watcher))
        end
    end

    function controller.Destroy()
        if controller.Destroyed then return end
        controller.Destroyed = true
        if controller.Watcher and controller.Watcher.Disconnect then
            pcall(function() controller.Watcher.Disconnect() end)
        end
        window.Destroy()
    end

    controller.Refresh()
    return controller
end

return Bootstrap
end)()

-- START APPLICATION
local controller = Bootstrap.Start({
    Modules = {
        GameConfigLoader = GameConfigLoader,
        InventoryReader = InventoryReader,
        IncomeCalculator = IncomeCalculator,
        MainWindow = MainWindow,
    }
})

return controller
