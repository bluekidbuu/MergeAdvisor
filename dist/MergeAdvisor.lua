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
        {modules.MergeConfig, "TraitOdds"},
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

-- MODULE: src/calculators/MergeCalculator.lua
local MergeCalculator = (function()
-- MergeCalculator.lua
-- Mesin rekomendasi berbasis MergeConfig dan EggRewards asli.
-- Read-only: tidak menjalankan merge dan tidak mengubah Tool pemain.

local MergeCalculator = {}

local DEFAULTS = {
    SlotCount = 3,
    MaxPerSpecies = 60,
    MinGain = 0,
    SortBy = "gain", -- "gain" atau "ratio"
}

local function getName(pet)
    return pet and (pet.AnimalName or pet.Name or pet.name) or nil
end

local function getWeight(pet)
    return tonumber(pet and (pet.WeightKg or pet.kg)) or 0
end

local function getIncome(pet)
    return tonumber(pet and (
        pet.Income or pet.CashPerSecond
        or pet.PlacedCashPerSecond or pet.income
    )) or 0
end

local function getVariant(pet)
    local value = pet and (pet.Variant or pet.var)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local function getMutation(pet)
    local value = pet and (pet.Mutation or pet.mut)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local function makeVariantOptions(odds, remain)
    local options = {}
    if type(odds) == "table" then
        for tier, chance in pairs(odds) do
            if type(chance) == "number" and chance > 0 then
                table.insert(options, {Name = tier, Chance = chance})
            end
        end
    end
    if type(remain) == "number" and remain > 0 then
        table.insert(options, {Name = false, Chance = remain})
    end
    table.sort(options, function(a, b)
        return tostring(a.Name or "Normal") < tostring(b.Name or "Normal")
    end)
    return options
end

local function makeMutationOptions(odds, remain)
    local options = {}
    if type(odds) == "table" then
        for _, entry in ipairs(odds) do
            if type(entry) == "table"
                and type(entry.Chance) == "number"
                and entry.Chance > 0 then
                table.insert(options, {
                    Name = entry.Name,
                    Chance = entry.Chance,
                })
            end
        end
    end
    if type(remain) == "number" and remain > 0 then
        table.insert(options, {Name = false, Chance = remain})
    end
    table.sort(options, function(a, b)
        return tostring(a.Name or "None") < tostring(b.Name or "None")
    end)
    return options
end

local function calculateIncome(configs, name, totalWeight, mutation, variant)
    local eggRewards = configs.EggRewards
    local enchantConfig = configs.EnchantConfig

    if enchantConfig and type(enchantConfig.CashMult) == "function" then
        return eggRewards.PlacedCashPerSecond(
            name, nil, mutation, totalWeight, variant, nil
        )
    end

    return eggRewards.PlacedCashPerSecond(
        name, nil, mutation, totalWeight, variant
    )
end

function MergeCalculator.Evaluate(a, b, c, configs)
    if not a or not b or not c then
        return nil, "Tiga hewan wajib tersedia"
    end

    local name = getName(a)
    if type(name) ~= "string" or name == ""
        or getName(b) ~= name or getName(c) ~= name then
        return nil, "Spesies ketiga hewan harus sama"
    end

    local wa, wb, wc = getWeight(a), getWeight(b), getWeight(c)
    if wa <= 0 or wb <= 0 or wc <= 0 then
        return nil, "Berat input tidak valid"
    end

    local mergeConfig = configs and configs.MergeConfig
    local eggRewards = configs and configs.EggRewards

    if type(mergeConfig) ~= "table"
        or type(mergeConfig.TraitOdds) ~= "function"
        or type(eggRewards) ~= "table"
        or type(eggRewards.PlacedCashPerSecond) ~= "function" then
        return nil, "API TraitOdds/EggRewards tidak tersedia"
    end

    local totalWeight = wa + wb + wc
    local variants = {getVariant(a), getVariant(b), getVariant(c)}
    local mutations = {getMutation(a), getMutation(b), getMutation(c)}

    local okOdds, traitOptions = pcall(
        mergeConfig.TraitOdds, variants, mutations, 3
    )
    if not okOdds then
        return nil, "TraitOdds gagal: " .. tostring(traitOptions)
    end

    if type(traitOptions) ~= "table" then
        return nil, "TraitOdds tidak mengembalikan tabel distribusi"
    end

    local expected = 0
    local best = -math.huge
    local worst = math.huge
    local outcomes = {}
    local probabilityTotal = 0
    local failedProbability = 0

    for _, trait in ipairs(traitOptions) do
        if type(trait) == "table"
            and type(trait.Chance) == "number"
            and trait.Chance > 0 then

            -- TraitOdds menggunakan pecahan 0 sampai 1.
            local chance = trait.Chance
            if chance > 1 then
                return nil, "Peluang TraitOdds melebihi 1.0: "
                    .. tostring(trait.Name)
            end

            -- SingleTrait menentukan salah satu trait efektif.
            -- Jangan membuat kombinasi silang Variant x Mutation.
            local variant = trait.Variant
            local mutation = trait.Mutation

            local okIncome, income = pcall(
                calculateIncome,
                configs,
                name,
                totalWeight,
                mutation,
                variant
            )

            if okIncome and type(income) == "number"
                and income == income and income >= 0 then

                expected = expected + chance * income
                best = math.max(best, income)
                worst = math.min(worst, income)
                probabilityTotal = probabilityTotal + chance

                table.insert(outcomes, {
                    Name = tostring(trait.Name or "Normal"),
                    Variant = variant,
                    Mutation = mutation,
                    Chance = chance,
                    Income = income,
                })
            else
                failedProbability = failedProbability + chance
            end
        end
    end

    if failedProbability > 0.000001 then
        return nil, "Sebagian outcome TraitOdds gagal dihitung"
    end

    -- TraitOdds menghilangkan outcome Normal.
    -- Normal adalah sisa probabilitas dari seluruh trait khusus.
    local remainingProbability = 1 - probabilityTotal

    if remainingProbability < -0.005 then
        return nil, string.format(
            "Total probabilitas trait melebihi 100%%: %.4f%%",
            probabilityTotal * 100
        )
    end

    if remainingProbability > 0.000001 then
        local okIncome, income = pcall(
            calculateIncome,
            configs,
            name,
            totalWeight,
            nil,
            nil
        )

        if not okIncome or type(income) ~= "number"
            or income ~= income or income < 0 then
            return nil, "Income outcome Normal gagal dihitung: "
                .. tostring(income)
        end

        table.insert(outcomes, {
            Name = "Normal",
            Variant = nil,
            Mutation = nil,
            Chance = remainingProbability,
            Income = income,
        })

        probabilityTotal = probabilityTotal + remainingProbability
    end

    if #outcomes == 0 then
        return nil, "Tidak ada outcome TraitOdds yang berhasil dihitung"
    end

    if math.abs(probabilityTotal - 1) > 0.005 then
        return nil, string.format(
            "Total probabilitas TraitOdds tidak valid: %.4f%%",
            probabilityTotal * 100
        )
    end

    table.sort(outcomes, function(x, y)
        if x.Chance == y.Chance then
            return x.Income > y.Income
        end
        return x.Chance > y.Chance
    end)

    local inputIncome = getIncome(a) + getIncome(b) + getIncome(c)
    local growth = 0

    if type(mergeConfig.GrowthSeconds) == "function" then
        local rarity
        if type(eggRewards.RarityOf) == "function" then
            local ok, value = pcall(eggRewards.RarityOf, name)
            if ok then rarity = value end
        end

        local ok, value = pcall(
            mergeConfig.GrowthSeconds, totalWeight, rarity
        )
        if ok and type(value) == "number" then
            growth = value
        end
    end

    return {
        Pets = {a, b, c},
        Name = name,
        WeightKg = totalWeight,
        Expected = expected,
        Best = best,
        Worst = worst,
        Input = inputIncome,
        Gain = expected - inputIncome,
        Ratio = inputIncome > 0 and expected / inputIncome or 0,
        TraitOdds = traitOptions,
        Outcomes = outcomes,
        ProbabilityTotal = probabilityTotal,
        FailedProbability = failedProbability,
        GrowthSeconds = growth,
    }
end

function MergeCalculator.Advise(pets, configs, options)
    options = options or {}
    local slotCount = tonumber(options.SlotCount)
        or tonumber(configs and configs.SlotCount)
        or DEFAULTS.SlotCount
    local maxPerSpecies = tonumber(options.MaxPerSpecies)
        or DEFAULTS.MaxPerSpecies
    local minGain = tonumber(options.MinGain)
    if minGain == nil then minGain = DEFAULTS.MinGain end
    local sortBy = options.SortBy == "ratio" and "Ratio" or "Gain"

    if slotCount ~= 3 then
        return {}, {"Merge Advisor v10.2.0 memakai tepat 3 slot; SlotCount aktif bukan 3."}
    end

    local groups = {}
    for _, pet in ipairs(pets or {}) do
        local name = getName(pet)
        if type(name) == "string" and name ~= "" then
            groups[name] = groups[name] or {}
            table.insert(groups[name], pet)
        end
    end

    local results, diagnostics, diagnosticMap = {}, {}, {}
    for species, list in pairs(groups) do
        if #list >= slotCount then
            table.sort(list, function(x, y)
                local xWeight, yWeight = getWeight(x), getWeight(y)
                if xWeight == yWeight then return getIncome(x) > getIncome(y) end
                return xWeight > yWeight
            end)

            while #list > maxPerSpecies do table.remove(list) end
            local evaluations = {}

            for i = 1, #list - 2 do
                for j = i + 1, #list - 1 do
                    for k = j + 1, #list do
                        local result, err = MergeCalculator.Evaluate(
                            list[i], list[j], list[k], configs
                        )
                        if result then
                            result.Indices = {i, j, k}
                            table.insert(evaluations, result)
                        elseif err then
                            -- Simpan satu diagnostik per spesies, bukan spam per triplet.
                            if not diagnosticMap[species] then
                                diagnosticMap[species] = err
                            end
                        end
                    end
                end
            end

            table.sort(evaluations, function(x, y)
                if x[sortBy] == y[sortBy] then
                    return x.Gain > y.Gain
                end
                return x[sortBy] > y[sortBy]
            end)

            -- Pilih kandidat non-overlap seperti implementasi legacy.
            local used = {}
            for _, result in ipairs(evaluations) do
                local idx = result.Indices
                if result.Gain >= minGain
                    and not used[idx[1]]
                    and not used[idx[2]]
                    and not used[idx[3]] then
                    used[idx[1]], used[idx[2]], used[idx[3]] = true, true, true
                    table.insert(results, result)
                end
            end
        end
    end

    local diagnosticSpecies = {}
    for species in pairs(diagnosticMap) do
        table.insert(diagnosticSpecies, species)
    end
    table.sort(diagnosticSpecies)
    for _, species in ipairs(diagnosticSpecies) do
        table.insert(diagnostics, "[" .. species .. "] " .. tostring(diagnosticMap[species]))
    end

    table.sort(results, function(x, y)
        if x[sortBy] == y[sortBy] then return x.Gain > y.Gain end
        return x[sortBy] > y[sortBy]
    end)

    return results, diagnostics
end

return MergeCalculator
end)()

-- MODULE: src/ui/MergePreparation.lua
local MergePreparation = (function()
-- MergePreparation.lua
-- Menyiapkan 3 slot UI. Tidak menjalankan merge dan tidak memanggil RemoteEvent.
local MergePreparation = {}

local function report(cb,msg,ok)
    if type(cb)=="function" then pcall(cb,tostring(msg),ok==true) end
end
local function owned(player,tool)
    if not tool or not tool:IsA("Tool") then return false end
    local bag=player:FindFirstChildOfClass("Backpack")
    local char=player.Character
    return (bag and tool:IsDescendantOf(bag)) or (char and tool:IsDescendantOf(char))
end
local function norm(s) return tostring(s or ""):lower():gsub("[^%w]","") end
local function weight(s)
    s=tostring(s or ""):upper():gsub("KG",""):gsub("%s",""):gsub(",","")
    local n=s:match("[%d%.]+")
    return n and tonumber(n) or nil
end
local function rowText(button)
    local t={button:IsA("TextButton") and button.Text or ""}
    for _,v in ipairs(button:GetDescendants()) do
        if (v:IsA("TextLabel") or v:IsA("TextButton")) and v.Visible and v.Text~="" then table.insert(t,v.Text) end
    end
    return table.concat(t," ")
end
local function findRow(list,pet,displayName)
    local names={norm(pet.name),norm(displayName and displayName(pet.name) or pet.name)}
    local found={}
    for _,obj in ipairs(list:GetDescendants()) do
        if obj:IsA("GuiButton") and obj.Visible then
            local text=rowText(obj);local n=norm(text);local kg=weight(text);local match=false
            for _,name in ipairs(names) do if name~="" and n:find(name,1,true) then match=true end end
            if match and kg and math.abs(kg-pet.kg)<=0.51 then
                local nested=false
                for i=#found,1,-1 do
                    if obj:IsDescendantOf(found[i]) then nested=true end
                    if found[i]:IsDescendantOf(obj) then table.remove(found,i) end
                end
                if not nested then table.insert(found,obj) end
            end
        end
    end
    return found
end


function MergePreparation.OpenMachine(player)
    local controllers = player:FindFirstChild("PlayerScripts")
        and player.PlayerScripts:FindFirstChild("Client")
        and player.PlayerScripts.Client:FindFirstChild("Controllers")

    local module = controllers and controllers:FindFirstChild("UiFrames")
    if not module then
        return nil, "UiFrames tidak ditemukan."
    end

    local ok, api = pcall(require, module)
    if not ok or type(api) ~= "table"
        or type(api.Open) ~= "function" then
        return nil, "Gagal memuat UiFrames.Open."
    end

    local pg = player:FindFirstChildOfClass("PlayerGui")
    local main = pg and pg:FindFirstChild("MainGUI")
    local frames = main and main:FindFirstChild("Frames")
    local panel = frames and frames:FindFirstChild("MergeMachine")

    if not panel then
        return nil, "Panel MergeMachine tidak ditemukan."
    end

    local opened, err = pcall(api.Open, panel)
    if not opened then
        return nil, "Gagal membuka panel: " .. tostring(err)
    end

    task.wait(0.6)
    return panel
end

function MergePreparation.Prepare(player,pets,callback,displayName)
    if type(pets)~="table" or #pets~=3 then report(callback,"Tiga hewan wajib dipilih.",false);return false end
    if pets[1].name~=pets[2].name or pets[1].name~=pets[3].name then report(callback,"Spesies ketiga hewan harus sama.",false);return false end
    local CS=game:GetService("CollectionService");local used={}
    for i,p in ipairs(pets) do
        local tool=p.tool or p.Tool
        if not owned(player,tool) or not CS:HasTag(tool,"AnimalTool") then report(callback,"Slot "..i..": hewan tidak lagi valid di inventory.",false);return false end
        if used[tool] then report(callback,"Hewan yang sama tidak boleh dipakai dua kali.",false);return false end
        used[tool]=true
    end
    local panel, openErr = MergePreparation.OpenMachine(player)
    if not panel then
        report(callback, openErr, false)
        return false
    end
    local fusion=panel:FindFirstChild("AnimalFusion")
    local slots=fusion and fusion:FindFirstChild("PetsPlacementList")
    local root=panel:FindFirstChild("ScrollingFrameContainer")
    local list=root and root:FindFirstChild("AnimalList")
    if not slots or not list then report(callback,"Struktur slot/picker tidak dikenali.",false);return false end
    if type(firesignal)~="function" then report(callback,"Executor tidak menyediakan firesignal.",false);return false end
    for i,p in ipairs(pets) do
        local slot=slots:FindFirstChild("Slot_"..i)
        local add=slot and slot:FindFirstChild("AddPet") and slot.AddPet:FindFirstChild("Add")
        if not add or not add:IsA("GuiButton") then report(callback,"Tombol Add Slot "..i.." tidak ditemukan.",false);return false end
        if not owned(player,p.tool or p.Tool) then report(callback,"Hewan Slot "..i.." tidak lagi dimiliki.",false);return false end
        local added,addErr=pcall(firesignal,add.Activated)
        if not added then report(callback,"Gagal membuka picker: "..tostring(addErr),false);return false end
        local matches={}
        for attempt=1,30 do
            task.wait(0.1);matches=findRow(list,p,displayName)
            if #matches>0 then break end
        end
        if #matches~=1 then
            report(callback,#matches==0 and ("Hewan tidak ditemukan untuk Slot "..i..". Proses dihentikan.")
                or ("Ada beberapa baris cocok untuk Slot "..i.."; proses dihentikan."),false)
            return false
        end
        local chosen,chooseErr=pcall(firesignal,matches[1].Activated)
        if not chosen then report(callback,"Gagal memilih Slot "..i..": "..tostring(chooseErr),false);return false end
        task.wait(0.4);report(callback,"Slot "..i.." dipilih: "..p.name.." / "..string.format("%.1f kg",p.kg),true)
    end
    report(callback,"3/3 slot siap. Periksa mesin; tombol MERGE tidak disentuh.",true)
    return true
end
return MergePreparation
end)()

-- MODULE: src/ui/MachineSlotReader.lua
local MachineSlotReader = (function()
-- MachineSlotReader.lua
-- Membaca tiga slot Merge Machine secara read-only. Tidak mengubah slot/menjalankan merge.
local MachineSlotReader = {}

local function norm(s)
    return tostring(s or ""):lower():gsub("[^%w]", "")
end

local function valueOf(root, key)
    local ok, value = pcall(function() return root:GetAttribute(key) end)
    if ok and value ~= nil then return value end
    local child = root:FindFirstChild(key, true)
    if child and child:IsA("ValueBase") then
        local good, result = pcall(function() return child.Value end)
        if good then return result end
    end
    return nil
end

local function textOf(root)
    local parts = {}
    if root:IsA("TextLabel") or root:IsA("TextButton") then
        if root.Text ~= "" then table.insert(parts, root.Text) end
    end
    for _, item in ipairs(root:GetDescendants()) do
        if item:IsA("TextLabel") or item:IsA("TextButton") then
            if item.Visible and item.Text ~= "" then table.insert(parts, item.Text) end
        end
    end
    return table.concat(parts, " ")
end

local function parseWeight(text)
    local upper = tostring(text or ""):upper():gsub(",", "")
    local n = upper:match("([%d%.]+)%s*KG")
    return n and tonumber(n) or nil
end

local function findReferencedTool(slot)
    local nodes = {slot}
    for _, item in ipairs(slot:GetDescendants()) do table.insert(nodes, item) end
    for _, item in ipairs(nodes) do
        if item:IsA("ObjectValue") and item.Value and item.Value:IsA("Tool") then
            return item.Value
        end
    end
    return nil
end

local function findInventoryMatch(slot, animals)
    local text = textOf(slot)
    local normalized = norm(text)
    local kg = parseWeight(text)
    if normalized == "" then return nil, "teks slot kosong" end
    local matches = {}
    for _, pet in ipairs(animals or {}) do
        local name = norm(pet.name or pet.AnimalName or pet.Name)
        local weight = tonumber(pet.kg or pet.WeightKg)
        if name ~= "" and normalized:find(name, 1, true)
            and kg and weight and math.abs(weight-kg) <= 0.51 then
            table.insert(matches, pet)
        end
    end
    if #matches == 1 then return matches[1] end
    if #matches == 0 then return nil, "hewan tidak cocok dengan inventory (nama/berat)" end
    return nil, "lebih dari satu hewan cocok; identitas ambigu"
end

local function buildFromTool(tool, slot, calculateIncome)
    local name = valueOf(tool, "AnimalName")
    local kg = valueOf(tool, "WeightKg")
    if type(name) ~= "string" or name == "" then name = tool.Name end
    if type(kg) ~= "number" or kg <= 0 then return nil end
    local variant = valueOf(tool, "Variant")
    local mutation = valueOf(tool, "Mutation")
    local size = valueOf(tool, "SizeMult")
    local enchant = valueOf(tool, "Enchant")
    local income = calculateIncome and calculateIncome(name, kg, variant, mutation, size, enchant) or nil
    return {
        name=name, AnimalName=name, Name=name,
        kg=kg, WeightKg=kg,
        var=variant, Variant=variant, mut=mutation, Mutation=mutation,
        size=size, SizeMult=size, enchant=enchant, Enchant=enchant,
        income=income, Income=income, tool=tool, Tool=tool,
        MachineSlot=slot.Name,
    }
end

local function fromSlotMetadata(slot, calculateIncome)
    local name = valueOf(slot, "AnimalName")
    local kg = valueOf(slot, "WeightKg")
    if type(name) ~= "string" or name == "" or type(kg) ~= "number" or kg <= 0 then
        return nil
    end
    local variant = valueOf(slot, "Variant")
    local mutation = valueOf(slot, "Mutation")
    local size = valueOf(slot, "SizeMult")
    local enchant = valueOf(slot, "Enchant")
    local income = calculateIncome and calculateIncome(name, kg, variant, mutation, size, enchant) or nil
    return {
        name=name, AnimalName=name, Name=name,
        kg=kg, WeightKg=kg,
        var=variant, Variant=variant, mut=mutation, Mutation=mutation,
        size=size, SizeMult=size, enchant=enchant, Enchant=enchant,
        income=income, Income=income, MachineSlot=slot.Name,
    }
end

function MachineSlotReader.Read(player, animals, calculateIncome)
    local pg = player and player:FindFirstChildOfClass("PlayerGui")
    local main = pg and pg:FindFirstChild("MainGUI")
    local frames = main and main:FindFirstChild("Frames")
    local panel = frames and frames:FindFirstChild("MergeMachine")
    if not panel then return nil, "Panel MergeMachine tidak ditemukan. Buka mesin terlebih dahulu." end
    if panel:IsA("GuiObject") and not panel.Visible then
        return nil, "Merge Machine belum terbuka. Buka panel mesin terlebih dahulu."
    end
    local fusion = panel:FindFirstChild("AnimalFusion")
    local placement = fusion and fusion:FindFirstChild("PetsPlacementList")
    if not placement then return nil, "PetsPlacementList tidak ditemukan; struktur slot belum dikenali." end

    local pets, used = {}, {}
    for i=1,3 do
        local slot = placement:FindFirstChild("Slot_"..i)
        if not slot then return nil, "Slot_"..i.." tidak ditemukan." end
        local pet
        local tool = findReferencedTool(slot)
        if tool then pet = buildFromTool(tool, slot, calculateIncome) end
        if not pet then pet = fromSlotMetadata(slot, calculateIncome) end
        if not pet then
            local matched, why = findInventoryMatch(slot, animals)
            if matched then
                pet = {}
                for k,v in pairs(matched) do pet[k]=v end
                pet.MachineSlot = slot.Name
            else
                return nil, "Slot "..i.." belum dapat dibaca: "..tostring(why)
            end
        end
        if not pet.income and calculateIncome then
            local ok, income = pcall(calculateIncome, pet.name, pet.kg, pet.var, pet.mut, pet.size, pet.enchant)
            if ok then pet.income = income; pet.Income = income end
        end
        if not tonumber(pet.kg) or pet.kg <= 0 or not pet.name or pet.name == "" then
            return nil, "Data nama/berat Slot "..i.." tidak valid."
        end
        if pet.tool and used[pet.tool] then return nil, "Slot mesin menunjuk hewan yang sama lebih dari sekali." end
        if pet.tool then used[pet.tool] = true end
        pets[i] = pet
    end
    if pets[1].name ~= pets[2].name or pets[1].name ~= pets[3].name then
        return nil, "Isi mesin berbeda spesies. Data tidak disalin ke simulator."
    end
    return pets
end

return MachineSlotReader
end)()

-- MODULE: src/ui/ManualMergeTab.lua
local ManualMergeTab = (function()
-- ManualMergeTab.lua
-- Manual simulator + inventory picker. Read-only terhadap hewan; tidak melakukan merge.
local ManualMergeTab={}
local function make(class,props,parent)
    local o=Instance.new(class);for k,v in pairs(props or {}) do o[k]=v end;o.Parent=parent;return o
end
local function round(o) Instance.new("UICorner",o).CornerRadius=UDim.new(0,7) end
local function label(parent,text,size,color,height)
    return make("TextLabel",{BackgroundTransparency=1,Size=UDim2.new(1,-10,0,height or 24),
        Font=Enum.Font.Gotham,Text=text,TextColor3=color or Color3.fromRGB(225,235,248),
        TextSize=size or 10,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center},parent)
end
local function button(parent,text,color,size)
    local b=make("TextButton",{Size=size or UDim2.new(1,-6,0,28),BackgroundColor3=color or Color3.fromRGB(48,91,145),
        BorderSizePixel=0,Text=text,TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamBold,TextSize=10},parent)
    round(b);return b
end
local function box(parent,placeholder)
    local b=make("TextBox",{Size=UDim2.new(1,-6,0,24),BackgroundColor3=Color3.fromRGB(42,55,76),
        BorderSizePixel=0,Text="",PlaceholderText=placeholder,ClearTextOnFocus=false,
        TextColor3=Color3.fromRGB(245,248,255),PlaceholderColor3=Color3.fromRGB(160,177,201),
        Font=Enum.Font.Gotham,TextSize=10,TextXAlignment=Enum.TextXAlignment.Left},parent)
    round(b);return b
end
local function trim(s) return tostring(s or ""):gsub("^%s+",""):gsub("%s+$","") end
local function fmt(n)
    n=tonumber(n) or 0
    if math.abs(n)>=1e12 then return string.format("%.2fT/s",n/1e12)
    elseif math.abs(n)>=1e9 then return string.format("%.2fB/s",n/1e9)
    elseif math.abs(n)>=1e6 then return string.format("%.2fM/s",n/1e6)
    elseif math.abs(n)>=1e3 then return string.format("%.2fK/s",n/1e3) end
    return string.format("%.2f/s",n)
end

function ManualMergeTab.Create(parent,opts)
    opts=opts or {}
    local panel=make("Frame",{Name="ManualMergeTab",Size=UDim2.fromScale(1,1),
        BackgroundColor3=Color3.fromRGB(16,22,34),BorderSizePixel=0,Visible=false},parent);round(panel)
    label(panel,"MANUAL MERGE SIMULATOR",14,Color3.fromRGB(255,218,104),25).Position=UDim2.fromOffset(8,3)
    label(panel,"Pilih 3 hewan inventory atau isi data custom. Spesies harus sama.",9,Color3.fromRGB(170,190,215),25).Position=UDim2.fromOffset(8,27)
    local scroll=make("ScrollingFrame",{Position=UDim2.fromOffset(6,55),Size=UDim2.new(1,-12,1,-158),
        BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new()},panel)
    local layout=Instance.new("UIListLayout",scroll);layout.Padding=UDim.new(0,6)
    local slots,selected,animals={},{},{}
    local picker=make("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(12,17,27),Visible=false,ZIndex=20},panel)
    label(picker,"PILIH HEWAN INVENTORY",13,Color3.fromRGB(255,218,104),27).Position=UDim2.fromOffset(8,4)
    local close=button(picker,"TUTUP",Color3.fromRGB(85,99,122),UDim2.fromOffset(66,24));close.Position=UDim2.new(1,-74,0,5)
    local list=make("ScrollingFrame",{Position=UDim2.fromOffset(6,36),Size=UDim2.new(1,-12,1,-42),BackgroundTransparency=1,
        BorderSizePixel=0,ScrollBarThickness=4,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),ZIndex=21},picker)
    local listLayout=Instance.new("UIListLayout",list);listLayout.Padding=UDim.new(0,4)
    local target

    local function getPetImage(p)
        if type(opts.GetImage) ~= "function" or not p then return "" end
        local name = p.name or p.AnimalName or p.Name
        if not name then return "" end
        local ok,value = pcall(opts.GetImage,name,
            p.var or p.Variant, p.mut or p.Mutation)
        if ok and type(value) == "string" then return value end
        return ""
    end

    local function clearList() for _,v in ipairs(list:GetChildren()) do if v:IsA("GuiObject") and v~=listLayout then v:Destroy() end end end
    local function setSlot(i,p)
        selected[i]=p;local s=slots[i]
        if p then
            s.name.Text=tostring(p.name or p.AnimalName or "");s.kg.Text=tostring(p.kg or p.WeightKg or "")
            s.income.Text=tostring(p.income or p.Income or "");s.variant.Text=tostring(p.var or p.Variant or "Normal")
            s.mutation.Text=tostring(p.mut or p.Mutation or "None");s.source.Text=p.tool and "Inventory" or "Custom"
            s.image.Image=getPetImage(p)
        else
            s.name.Text="";s.kg.Text="";s.income.Text="";s.variant.Text="";s.mutation.Text="";s.source.Text="Belum dipilih"
            s.image.Image=""
        end
    end
    local function openPicker(i)
        target=i;clearList();local source=opts.GetAnimals and opts.GetAnimals() or animals;local count=0
        for _,p in ipairs(source or {}) do
            local item=button(list,string.format("%s | %.1f kg | %s",p.name or p.AnimalName,tonumber(p.kg or p.WeightKg) or 0,fmt(p.income or p.Income)),Color3.fromRGB(43,60,84),UDim2.new(1,-5,0,38))
            item.TextWrapped=true;item.TextXAlignment=Enum.TextXAlignment.Left;item.ZIndex=22
            item.Text="       "..item.Text

            local thumb=make("ImageLabel",{
                Name="AnimalImage",
                Position=UDim2.fromOffset(4,3),
                Size=UDim2.fromOffset(32,32),
                BackgroundColor3=Color3.fromRGB(24,34,49),
                BorderSizePixel=0,
                ScaleType=Enum.ScaleType.Fit,
                Image=getPetImage(p),
                ZIndex=23
            },item)
            thumb.Active=false

            item.Activated:Connect(function()
                for j,old in pairs(selected) do if j~=i and old and old.tool and old.tool==p.tool then
                    slots[i].source.Text="Sudah dipakai di Slot "..j;return end end
                setSlot(i,p);picker.Visible=false
            end);count=count+1
        end
        if count==0 then local e=label(list,"Inventory kosong. Isi data custom pada slot.",10,nil,40);e.ZIndex=22 end
        picker.Visible=true
    end
    for i=1,3 do
        local card=make("Frame",{Size=UDim2.new(1,-4,0,153),BackgroundColor3=Color3.fromRGB(39,53,74),BorderSizePixel=0,LayoutOrder=i},scroll);round(card)
        label(card,"SLOT "..i,10,Color3.fromRGB(255,218,104),18).Position=UDim2.fromOffset(6,2)
        local pick=button(card,"PILIH INVENTORY",Color3.fromRGB(39,128,111),UDim2.new(0.43,-4,0,21));pick.Position=UDim2.new(0.55,0,0,2)
        local preview=make("ImageLabel",{
            Name="AnimalPreview",
            Position=UDim2.fromOffset(6,30),
            Size=UDim2.fromOffset(54,54),
            BackgroundColor3=Color3.fromRGB(24,34,49),
            BorderSizePixel=0,
            ScaleType=Enum.ScaleType.Fit
        },card)

        local fields=make("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(66,26),Size=UDim2.new(1,-70,0,124)},card)
        local grid=Instance.new("UIGridLayout",fields);grid.CellSize=UDim2.new(0.49,-2,0,23);grid.CellPadding=UDim2.new(0.02,0,0,3);grid.FillDirectionMaxCells=2
        local n=box(fields,"Nama spesies");local kg=box(fields,"Berat kg");local inc=box(fields,"Income/s (opsional)")
        local var=box(fields,"Variant");local mut=box(fields,"Mutation");local src=label(fields,"Belum dipilih",8,Color3.fromRGB(164,187,213),20);src.LayoutOrder=6
        slots[i]={name=n,kg=kg,income=inc,variant=var,mutation=mut,source=src,image=preview}
        pick.Activated:Connect(function() openPicker(i) end)
    end
    close.Activated:Connect(function() picker.Visible=false end)
    local analyze=button(panel,"ANALISIS",Color3.fromRGB(36,148,103),UDim2.new(0.23,-4,0,27));analyze.Position=UDim2.new(0,6,1,-96)
    local clear=button(panel,"KOSONGKAN",Color3.fromRGB(100,76,88),UDim2.new(0.22,-4,0,27));clear.Position=UDim2.new(0.245,0,1,-96)
    local sync=button(panel,"AMBIL MESIN",Color3.fromRGB(121,91,48),UDim2.new(0.25,-4,0,27));sync.Position=UDim2.new(0.475,0,1,-96)
    local prepare=button(panel,"SIAPKAN SLOT",Color3.fromRGB(42,111,153),UDim2.new(0.25,-5,0,27));prepare.Position=UDim2.new(0.735,0,1,-96)
    local output=make("TextLabel",{Position=UDim2.new(0,7,1,-65),Size=UDim2.new(1,-14,0,57),BackgroundColor3=Color3.fromRGB(34,47,66),
        BorderSizePixel=0,Font=Enum.Font.Code,Text="Hasil analisis akan muncul di sini.",TextColor3=Color3.fromRGB(225,235,248),
        TextSize=9,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top},panel);round(output)
    local function readSlots()
        local pets={}
        for i,s in ipairs(slots) do
            local name=trim(s.name.Text);local kg=tonumber(trim(s.kg.Text));local income=tonumber(trim(s.income.Text))
            local var=trim(s.variant.Text);local mut=trim(s.mutation.Text)
            if name=="" or not kg or kg<=0 then return nil,"Slot "..i..": nama dan berat positif wajib diisi." end
            if var=="" or var:lower()=="normal" or var:lower()=="none" then var=nil end
            if mut=="" or mut:lower()=="none" then mut=nil end
            if income==nil and opts.CalculateIncome then local ok,v=pcall(opts.CalculateIncome,name,kg,var,mut);if ok then income=v end end
            if not income or income<0 then return nil,"Slot "..i..": income tidak valid." end
            local original=selected[i];if original and (original.name~=name or math.abs(original.kg-kg)>0.001) then original=nil end
            pets[i]={name=name,AnimalName=name,kg=kg,WeightKg=kg,income=income,Income=income,var=var,Variant=var,mut=mut,Mutation=mut,tool=original and original.tool or nil}
        end
        if pets[1].name~=pets[2].name or pets[1].name~=pets[3].name then return nil,"Tiga hewan harus dari spesies yang sama." end
        return pets
    end
    analyze.Activated:Connect(function()
        local pets,err=readSlots();if not pets then output.Text=err;return end
        local ok,r,why=pcall(opts.Evaluate,pets[1],pets[2],pets[3])
        if not ok then output.Text="CALCULATION ERROR: "..tostring(r);return end
        if not r then output.Text=tostring(why or "Outcome tidak dapat dihitung.");return end
        local lines={pets[1].name.." | Total "..string.format("%.2f kg",r.WeightKg),
            "Input "..fmt(r.Input).." -> Expected "..fmt(r.Expected),
            "Gain "..fmt(r.Gain).." | Ratio x"..string.format("%.3f",r.Ratio),
            "Best "..fmt(r.Best).." | Worst "..fmt(r.Worst),"Outcome Trait (satu trait efektif):"}
        for _,o in ipairs(r.Outcomes) do
            table.insert(lines,string.format("%s | %.2f%% | %s",
                tostring(o.Name or "Normal"),o.Chance*100,fmt(o.Income)))
        end
        output.Text=table.concat(lines,"\n");output.TextColor3=Color3.fromRGB(126,214,176)
    end)
    clear.Activated:Connect(function() for i=1,3 do setSlot(i,nil) end;output.Text="Slot dikosongkan." end)
    sync.Activated:Connect(function()
        if type(opts.ReadMachine) ~= "function" then
            output.Text = "Pembaca slot mesin belum tersedia."
            return
        end
        sync.Active=false;sync.Text="MEMBACA..."
        local ok,pets,err=pcall(opts.ReadMachine)
        if not ok then
            output.Text="MACHINE READ ERROR: "..tostring(pets)
            output.TextColor3=Color3.fromRGB(255,170,150)
        elseif not pets then
            output.Text=tostring(err or "Data mesin tidak dapat dibaca.")
            output.TextColor3=Color3.fromRGB(255,170,150)
        else
            for i=1,3 do setSlot(i,pets[i]) end
            output.Text="3/3 slot berhasil disalin dari Merge Machine. Tekan ANALISIS untuk menghitung peluang."
            output.TextColor3=Color3.fromRGB(126,214,176)
        end
        sync.Active=true;sync.Text="AMBIL MESIN"
    end)
    prepare.Activated:Connect(function()
        local pets,err=readSlots();if not pets then output.Text=err;return end
        for i,p in ipairs(pets) do if not p.tool then output.Text="Slot "..i.." adalah data custom. Persiapan mesin hanya untuk hewan inventory.";return end end
        prepare.Active=false;prepare.Text="MEMPROSES..."
        local ok,success=pcall(opts.Prepare,pets,function(msg,good)
            output.Text=tostring(msg);output.TextColor3=good and Color3.fromRGB(126,214,176) or Color3.fromRGB(255,170,150)
        end)
        if not ok then output.Text="PREPARATION ERROR: "..tostring(success) end
        prepare.Active=true;prepare.Text=success and "SLOT SIAP" or "COBA LAGI"
    end)
    local api={}
    function api.SetAnimals(v) animals=v or {} end
    function api.SetSlots(v)
        if type(v) ~= "table" or #v ~= 3 then return false end
        for i=1,3 do setSlot(i,v[i]) end
        return true
    end
    function api.Destroy() panel:Destroy() end
    return api
end
return ManualMergeTab
end)()

-- MODULE: src/ui/MainWindow.lua
local MainWindow = (function()
-- MainWindow.lua
-- Modular GUI: Inventory, Recommendation, Manual Merge.
local MainWindow = {}

local function make(class, props, parent)
    local o = Instance.new(class)
    for k,v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end

local function corner(o, radius)
    Instance.new("UICorner", o).CornerRadius = UDim.new(0, radius or 7)
end

function MainWindow.Create(playerGui)
    local old = playerGui:FindFirstChild("MergeAdvisorModular")
    if old then old:Destroy() end

    local gui = make("ScreenGui", {
        Name="MergeAdvisorModular", ResetOnSpawn=false,
        DisplayOrder=999, ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    }, playerGui)

    local frame = make("Frame", {
        Name="Main", Size=UDim2.new(0.94,0,0.84,0),
        Position=UDim2.fromScale(0.5,0.5), AnchorPoint=Vector2.new(0.5,0.5),
        BackgroundColor3=Color3.fromRGB(25,32,46), BorderSizePixel=0,
        ClipsDescendants=true
    }, gui)
    corner(frame, 12)
    local stroke=Instance.new("UIStroke",frame)
    stroke.Color=Color3.fromRGB(65,105,155)
    stroke.Thickness=1

    local header=make("Frame",{
        Name="Header",Size=UDim2.new(1,0,0,43),
        BackgroundColor3=Color3.fromRGB(35,105,180),BorderSizePixel=0
    },frame)

    make("TextLabel",{
        Name="Title",Position=UDim2.fromOffset(12,0),
        Size=UDim2.new(1,-125,1,0),BackgroundTransparency=1,
        Text="MERGE ADVISOR",TextColor3=Color3.fromRGB(255,225,130),
        Font=Enum.Font.GothamBold,TextSize=15,
        TextXAlignment=Enum.TextXAlignment.Left
    },header)

    local function headerButton(name, text, x, color)
        local b=make("TextButton",{
            Name=name,Size=UDim2.fromOffset(30,28),
            Position=UDim2.new(1,x,0,7),BackgroundColor3=color,
            BorderSizePixel=0,Text=text,TextColor3=Color3.new(1,1,1),
            Font=Enum.Font.GothamBold,TextSize=16
        },header)
        corner(b,6)
        return b
    end

    local expand=headerButton("Expand","↗",-105,Color3.fromRGB(42,135,110))
    local minimize=headerButton("Minimize","−",-70,Color3.fromRGB(70,85,110))
    local close=headerButton("Close","×",-35,Color3.fromRGB(160,60,70))

    local floating=make("TextButton",{
        Name="MergeAdvisorFloatingIcon",Size=UDim2.fromOffset(54,54),
        Position=UDim2.new(1,-18,1,-90),AnchorPoint=Vector2.new(1,1),
        BackgroundColor3=Color3.fromRGB(42,115,195),
        BorderSizePixel=0,Text="🐾",TextSize=24,
        Visible=false,ZIndex=100
    },gui)
    corner(floating,27)
    local fs=Instance.new("UIStroke",floating)
    fs.Color=Color3.fromRGB(255,215,110)
    fs.Thickness=2

    local status=make("TextLabel",{
        Name="Status",Position=UDim2.fromOffset(10,45),
        Size=UDim2.new(1,-20,0,22),BackgroundTransparency=1,
        Text="Status: Starting...",TextColor3=Color3.fromRGB(255,205,110),
        Font=Enum.Font.Gotham,TextSize=10,
        TextXAlignment=Enum.TextXAlignment.Left
    },frame)

    local tabs=make("Frame",{
        Name="Tabs",Position=UDim2.fromOffset(10,70),
        Size=UDim2.new(1,-20,0,30),BackgroundTransparency=1
    },frame)

    local content=make("Frame",{
        Name="Content",Position=UDim2.fromOffset(10,106),
        Size=UDim2.new(1,-20,1,-116),
        BackgroundTransparency=1
    },frame)

    local pages={}
    local tabButtons={}
    local function page(name)
        local f=make("ScrollingFrame",{
            Name=name,Size=UDim2.fromScale(1,1),
            BackgroundColor3=Color3.fromRGB(15,20,30),
            BorderSizePixel=0,ScrollBarThickness=5,
            CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,
            Visible=false
        },content)
        corner(f,7)
        local layout=Instance.new("UIListLayout",f)
        layout.Padding=UDim.new(0,5)
        layout.SortOrder=Enum.SortOrder.LayoutOrder
        local pad=Instance.new("UIPadding",f)
        pad.PaddingTop=UDim.new(0,7)
        pad.PaddingLeft=UDim.new(0,7)
        pad.PaddingRight=UDim.new(0,7)
        pad.PaddingBottom=UDim.new(0,7)
        pages[name]=f
        return f
    end

    local inventoryPage=page("InventoryPage")
    local recommendationPage=page("RecommendationPage")
    local manualPage=make("Frame",{
        Name="ManualPage",Size=UDim2.fromScale(1,1),
        BackgroundTransparency=1,Visible=false
    },content)
    pages.ManualPage=manualPage

    local function tab(name,text,x)
        local b=make("TextButton",{
            Name=name,Position=UDim2.new(x,0,0,0),
            Size=UDim2.new(0.333,-5,1,0),
            BackgroundColor3=Color3.fromRGB(50,70,100),
            BorderSizePixel=0,Text=text,TextColor3=Color3.new(1,1,1),
            Font=Enum.Font.GothamBold,TextSize=10
        },tabs)
        corner(b,6)
        tabButtons[name]=b
        return b
    end

    local function show(which)
        for name,p in pairs(pages) do p.Visible=(name==which) end
        for name,b in pairs(tabButtons) do
            b.BackgroundColor3=(name==which)
                and Color3.fromRGB(38,135,110)
                or Color3.fromRGB(50,70,100)
        end
    end

    tab("InventoryTab","INVENTORY",0).Activated:Connect(function() show("InventoryPage") end)
    tab("RecommendationTab","RECOMMENDATION",0.333).Activated:Connect(function() show("RecommendationPage") end)
    tab("ManualTab","MANUAL MERGE",0.666).Activated:Connect(function() show("ManualPage") end)

    local function clearRows(parent)
        for _,v in ipairs(parent:GetChildren()) do
            if v:IsA("GuiObject") and not v:IsA("UIListLayout")
                and not v:IsA("UIPadding") then v:Destroy() end
        end
    end

    local function addText(parent,text,height,color,size)
        return make("TextLabel",{
            Size=UDim2.new(1,-4,0,height or 30),
            BackgroundColor3=Color3.fromRGB(34,46,65),
            BorderSizePixel=0,Text=tostring(text),
            TextColor3=color or Color3.fromRGB(225,235,248),
            Font=Enum.Font.Code,TextSize=size or 10,
            TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
            TextYAlignment=Enum.TextYAlignment.Center
        },parent)
    end

    local api={}
    function api.GetManualRoot() return manualPage end

    function api.SetStatus(text,success)
        status.Text="Status: "..tostring(text)
        status.TextColor3=success and Color3.fromRGB(125,230,160)
            or Color3.fromRGB(255,195,110)
    end

    function api.SetText(text)
        clearRows(inventoryPage)
        local label=addText(inventoryPage,text, math.max(90, math.min(6000, #tostring(text)*0.19)),
            Color3.fromRGB(220,230,245),10)
        label.AutomaticSize=Enum.AutomaticSize.Y
        label.Size=UDim2.new(1,-4,0,0)
        label.TextYAlignment=Enum.TextYAlignment.Top
        label.BackgroundTransparency=1
        label.Position=UDim2.fromOffset(3,3)
        inventoryPage.CanvasPosition=Vector2.new(0,0)
    end

    function api.SetInventory(animals,getImage,summary)
        clearRows(inventoryPage)

        addText(inventoryPage, summary or
            ("INVENTORY  •  " .. tostring(#(animals or {})) .. " hewan"),
            30, Color3.fromRGB(255,220,120), 12)

        if type(animals) ~= "table" or #animals == 0 then
            addText(inventoryPage, "Belum ada hewan terbaca.", 42)
            return
        end

        for i,pet in ipairs(animals) do
            local name = tostring(pet.name or pet.AnimalName or pet.Name or "Unknown")
            local kg = tonumber(pet.kg or pet.WeightKg) or 0
            local income = tonumber(pet.income or pet.Income
                or pet.CashPerSecond or pet.PlacedCashPerSecond) or 0
            local variant = tostring(pet.var or pet.Variant or "Normal")
            local mutation = tostring(pet.mut or pet.Mutation or "None")

            local card = make("Frame", {
                Size = UDim2.new(1,-4,0,66),
                BackgroundColor3 = Color3.fromRGB(35,49,70),
                BorderSizePixel = 0,
                LayoutOrder = i
            }, inventoryPage)
            corner(card,7)

            local image = ""
            if type(getImage) == "function" then
                local ok,value = pcall(getImage,name,
                    pet.var or pet.Variant, pet.mut or pet.Mutation)
                if ok and type(value) == "string" then image = value end
            end

            make("ImageLabel", {
                Name = "AnimalImage",
                Position = UDim2.fromOffset(5,5),
                Size = UDim2.fromOffset(56,56),
                BackgroundColor3 = Color3.fromRGB(24,34,49),
                BorderSizePixel = 0,
                ScaleType = Enum.ScaleType.Fit,
                Image = image
            },card)

            make("TextLabel", {
                Position = UDim2.fromOffset(68,5),
                Size = UDim2.new(1,-74,0,21),
                BackgroundTransparency = 1,
                Text = name,
                TextColor3 = Color3.fromRGB(255,220,120),
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left
            },card)

            make("TextLabel", {
                Position = UDim2.fromOffset(68,27),
                Size = UDim2.new(1,-74,0,32),
                BackgroundTransparency = 1,
                Text = string.format("%.1f kg  |  %s/s\n%s  •  %s",
                    kg, tostring(income), variant, mutation),
                TextColor3 = Color3.fromRGB(215,228,245),
                Font = Enum.Font.Code,
                TextSize = 9,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left
            },card)
        end

        inventoryPage.CanvasPosition = Vector2.new(0,0)
    end

    function api.SetRecommendations(results,onPick,getImage)
        clearRows(recommendationPage)
        addText(recommendationPage,"REKOMENDASI MERGE  •  "..tostring(#(results or {})).." kandidat",30,
            Color3.fromRGB(255,220,120),12)
        if not results or #results==0 then
            addText(recommendationPage,"Belum ada kandidat merge yang memenuhi syarat.",45)
            return
        end
        for i,result in ipairs(results) do
            local pets=result.Pets or {}
            local names={}
            for _,pet in ipairs(pets) do
                table.insert(names,tostring(pet.AnimalName or pet.Name or pet.name or "Hewan"))
            end
            local card=make("Frame",{
                Size=UDim2.new(1,-4,0,94),
                BackgroundColor3=Color3.fromRGB(35,49,70),
                BorderSizePixel=0,LayoutOrder=i
            },recommendationPage)
            corner(card,7)

            local firstPet = pets[1]
            local image = ""
            if firstPet and type(getImage) == "function" then
                local petName = firstPet.name or firstPet.AnimalName
                    or firstPet.Name
                local ok,value = pcall(getImage,petName,
                    firstPet.var or firstPet.Variant,
                    firstPet.mut or firstPet.Mutation)
                if ok and type(value) == "string" then image = value end
            end

            make("ImageLabel", {
                Name = "AnimalImage",
                Position = UDim2.fromOffset(7,34),
                Size = UDim2.fromOffset(52,52),
                BackgroundColor3 = Color3.fromRGB(24,34,49),
                BorderSizePixel = 0,
                ScaleType = Enum.ScaleType.Fit,
                Image = image
            },card)

            make("TextLabel",{
                Position=UDim2.fromOffset(66,5),Size=UDim2.new(1,-158,0,23),
                BackgroundTransparency=1,
                Text="#"..i.."  "..tostring(result.Name or table.concat(names," / ")),
                TextColor3=Color3.fromRGB(255,220,120),
                Font=Enum.Font.GothamBold,TextSize=11,
                TextXAlignment=Enum.TextXAlignment.Left
            },card)
            make("TextLabel",{
                Position=UDim2.fromOffset(66,29),Size=UDim2.new(1,-158,0,58),
                BackgroundTransparency=1,
                Text="Gain: "..tostring(result.Gain).."  |  Ratio: x"..string.format("%.3f",tonumber(result.Ratio) or 0)
                    .."\nExpected: "..tostring(result.Expected).."  |  Best: "..tostring(result.Best)
                    .."  |  Worst: "..tostring(result.Worst),
                TextColor3=Color3.fromRGB(215,228,245),
                Font=Enum.Font.Code,TextSize=9,TextWrapped=true,
                TextXAlignment=Enum.TextXAlignment.Left
            },card)
            local pick=make("TextButton",{
                Name="SelectCandidate",Position=UDim2.new(1,-88,0,5),
                Size=UDim2.fromOffset(80,25),
                BackgroundColor3=Color3.fromRGB(38,135,110),
                BorderSizePixel=0,Text="PILIH",
                TextColor3=Color3.new(1,1,1),
                Font=Enum.Font.GothamBold,TextSize=10
            },card)
            corner(pick,5)
            pick.MouseButton1Click:Connect(function()
                if type(onPick)=="function" then
                    local ok,err=pcall(onPick,result)
                    if not ok then
                        warn("[MergeAdvisor] PILIH ERROR: "..tostring(err))
                    end
                end
            end)
        end
        recommendationPage.CanvasPosition=Vector2.new(0,0)
    end

    function api.ShowTab(which)
        if which=="manual" then show("ManualPage")
        elseif which=="recommendation" then show("RecommendationPage")
        else show("InventoryPage") end
    end

    function api.OnRefresh(callback) end
    function api.OnCopy(callback) end
    function api.Destroy() gui:Destroy() end

    local minimized=false
    local expanded=true
    local function setMinimized(value)
        minimized=value
        frame.Visible=not value
        floating.Visible=value
    end
    minimize.Activated:Connect(function() setMinimized(true) end)
    close.Activated:Connect(function() setMinimized(true) end)
    floating.Activated:Connect(function() setMinimized(false) end)
    expand.Activated:Connect(function()
        expanded=not expanded
        frame.Size=expanded and UDim2.new(0.94,0,0.84,0)
            or UDim2.new(0.82,0,0.70,0)
        expand.Text=expanded and "↗" or "↙"
    end)

    local UIS=game:GetService("UserInputService")
    local dragging,dragStart,startPos=false,nil,nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1
            or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true;dragStart=input.Position;startPos=frame.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement
            or input.UserInputType==Enum.UserInputType.Touch) then
            local d=input.Position-dragStart
            frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,
                startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1
            or input.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)

    show("InventoryPage")
    return api
end

return MainWindow
end)()

-- MODULE: src/core/Bootstrap.lua
local Bootstrap = (function()
-- Bootstrap.lua
-- Menghubungkan config, inventory, merge engine, live refresh, dan GUI diagnostik.

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
    value = tonumber(value) or 0
    if math.abs(value) >= 1e12 then return string.format("%.2fT/s", value / 1e12)
    elseif math.abs(value) >= 1e9 then return string.format("%.2fB/s", value / 1e9)
    elseif math.abs(value) >= 1e6 then return string.format("%.2fM/s", value / 1e6)
    elseif math.abs(value) >= 1e3 then return string.format("%.2fK/s", value / 1e3) end
    return string.format("%.2f/s", value)
end

local function formatDuration(seconds, configs)
    local mergeConfig = configs and configs.MergeConfig
    if mergeConfig and type(mergeConfig.FormatDuration) == "function" then
        local ok, value = pcall(mergeConfig.FormatDuration, seconds)
        if ok and value ~= nil then return tostring(value) end
    end
    seconds = math.max(0, tonumber(seconds) or 0)
    if seconds >= 3600 then
        return string.format("%dh %dm", math.floor(seconds / 3600),
            math.floor((seconds % 3600) / 60))
    elseif seconds >= 60 then
        return string.format("%dm %ds", math.floor(seconds / 60), math.floor(seconds % 60))
    end
    return string.format("%ds", math.floor(seconds))
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

local function petDescription(pet)
    local parts = {
        getAnimalName(pet),
        string.format("%.1f kg", tonumber(pet.WeightKg or pet.kg) or 0),
        formatIncome(getIncome(pet)),
    }
    local variant = pet.Variant or pet.var
    local mutation = pet.Mutation or pet.mut
    if variant then table.insert(parts, "Var " .. tostring(variant)) end
    if mutation then table.insert(parts, "Mut " .. tostring(mutation)) end
    return table.concat(parts, " | ")
end

local function describeMerge(result, rank, configs)
    local lines = {}
    local sign = result.Gain >= 0 and "+" or "-"
    table.insert(lines, string.format("#%d %s | %s%s | x%.3f",
        rank, result.Name, sign, formatIncome(math.abs(result.Gain)), result.Ratio))

    for _, pet in ipairs(result.Pets) do
        table.insert(lines, "  - " .. petDescription(pet))
    end

    table.insert(lines, string.format(
        "  Total %.2f kg | Expected %s | Input %s",
        result.WeightKg, formatIncome(result.Expected), formatIncome(result.Input)
    ))
    table.insert(lines, string.format(
        "  Best %s | Worst %s | Growth %s",
        formatIncome(result.Best), formatIncome(result.Worst),
        formatDuration(result.GrowthSeconds, configs)
    ))
    table.insert(lines, string.format(
        "  Outcome Trait: %d | Probabilitas termodel: %.2f%%",
        #result.Outcomes, result.ProbabilityTotal * 100
    ))

    table.insert(lines, "  DISTRIBUSI TRAIT:")
    for _, outcome in ipairs(result.Outcomes) do
        table.insert(lines, string.format("    %s: %.2f%%",
            tostring(outcome.Name or "Normal"), outcome.Chance * 100))
    end

    table.insert(lines, "  OUTCOME TERATAS:")
    for index = 1, math.min(6, #result.Outcomes) do
        local outcome = result.Outcomes[index]
        table.insert(lines, string.format("    %s | %.2f%% | %s",
            tostring(outcome.Name or "Normal"),
            outcome.Chance * 100,
            formatIncome(outcome.Income)))
    end

    return table.concat(lines, "\n")
end

function Bootstrap.Start(options)
    options = options or {}
    local modules = options.Modules or {}
    local ConfigLoader = assert(modules.GameConfigLoader, "GameConfigLoader belum dimasukkan")
    local InventoryReader = assert(modules.InventoryReader, "InventoryReader belum dimasukkan")
    local IncomeCalculator = assert(modules.IncomeCalculator, "IncomeCalculator belum dimasukkan")
    local MergeCalculator = assert(modules.MergeCalculator, "MergeCalculator belum dimasukkan")
    local MainWindow = assert(modules.MainWindow, "MainWindow belum dimasukkan")
    local ManualMergeTab = assert(modules.ManualMergeTab, "ManualMergeTab belum dimasukkan")
    local MergePreparation = assert(modules.MergePreparation, "MergePreparation belum dimasukkan")
    local MachineSlotReader = assert(modules.MachineSlotReader, "MachineSlotReader belum dimasukkan")

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
        Configs = nil, Animals = {}, MergeResults = {}, Diagnostics = {},
        TotalIncome = 0, LastReport = "", Destroyed = false,
        Watcher = nil, Refreshing = false, RefreshQueued = false,
    }

    local manualTab = ManualMergeTab.Create(window.GetManualRoot(), {
        GetAnimals = function() return controller.Animals end,
        GetImage = function(name,variant,mutation)
            local renders = controller.Configs and controller.Configs.AnimalRenders
            if renders and type(renders.GetImage) == "function" then
                return renders.GetImage(name,variant,mutation)
            end
            return ""
        end,
        Evaluate = function(a,b,c) return MergeCalculator.Evaluate(a,b,c,controller.Configs) end,
        CalculateIncome = function(name,kg,variant,mutation)
            return IncomeCalculator.CalculateFromGame(controller.Configs,name,nil,mutation,kg,variant,nil)
        end,
        Prepare = function(pets,callback)
            return MergePreparation.Prepare(player,pets,callback,function(name)
                local rewards=controller.Configs and controller.Configs.EggRewards
                if rewards and type(rewards.DisplayName)=="function" then
                    local ok,value=pcall(rewards.DisplayName,name)
                    if ok and value then return value end
                end
                return name
            end)
        end,
        ReadMachine = function()
            local panel, openErr = MergePreparation.OpenMachine(player)
            if not panel then
                return nil, openErr
            end

            return MachineSlotReader.Read(player, controller.Animals, function(name,kg,variant,mutation,size,enchant)
                return IncomeCalculator.CalculateFromGame(
                    controller.Configs,name,size,mutation,kg,variant,enchant
                )
            end)
        end,
    })

    local function makeReport(animals, diagnostics, totalIncome, scannedTools, mergeResults, mergeDiagnostics, configs)
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
        table.insert(lines, "MERGE RECOMMENDATIONS")
        table.insert(lines, "------------------------------")
        table.insert(lines, "Kandidat terpilih: " .. #mergeResults
            .. " | syarat: 3 spesies sama | Expected Gain >= 0")
        table.insert(lines, "Catatan: estimasi output merge memakai Enchant=nil sesuai v10.2.0; income input memakai data aktual.")
        if #mergeResults == 0 then
            table.insert(lines, "Tidak ditemukan kombinasi merge menguntungkan yang memenuhi odds lengkap.")
        else
            for index = 1, math.min(options.TopMergeResults or 8, #mergeResults) do
                table.insert(lines, describeMerge(mergeResults[index], index, configs))
                table.insert(lines, "")
            end
        end

        if #mergeDiagnostics > 0 then
            table.insert(lines, "DIAGNOSTIK MERGE")
            for _, message in ipairs(mergeDiagnostics) do
                table.insert(lines, "- " .. safeString(message))
            end
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

        window.SetStatus("Menghitung peluang merge...", false)
        local mergeOK, mergeResults, mergeDiagnostics = pcall(function()
            return MergeCalculator.Advise(animals, configs, {
                SlotCount = configs.SlotCount or 3,
                MaxPerSpecies = options.MaxPerSpecies or 60,
                MinGain = options.MinGain or 0,
                SortBy = options.SortBy or "gain",
            })
        end)
        if not mergeOK then
            local mergeError = mergeResults
            mergeResults = {}
            mergeDiagnostics = {"MergeCalculator gagal: " .. tostring(mergeError)}
        end
        if type(mergeResults) ~= "table" then mergeResults = {} end
        if type(mergeDiagnostics) ~= "table" then mergeDiagnostics = {} end

        controller.Animals = animals
        manualTab.SetAnimals(animals)
        controller.MergeResults = mergeResults
        window.SetRecommendations(mergeResults, function(result)
            window.SetStatus("PILIH terdeteksi. Membuka Merge Machine...", false)

            local pets = result and result.Pets
            if type(pets) ~= "table" or #pets ~= 3 then
                window.SetStatus("GAGAL: kandidat tidak memiliki tepat 3 hewan.", false)
                return
            end

            local ok,success = pcall(function()
                return MergePreparation.Prepare(player, pets, function(msg, good)
                    window.SetStatus(msg, good)
                end, function(name)
                    local rewards = controller.Configs and controller.Configs.EggRewards
                    if rewards and type(rewards.DisplayName) == "function" then
                        local displayOK, value = pcall(rewards.DisplayName, name)
                        if displayOK and value then return value end
                    end
                    return name
                end)
            end)

            if not ok then
                window.SetStatus("PREPARATION ERROR: " .. tostring(success), false)
                return
            end

            if success == true then
                window.SetStatus("BERHASIL: 3/3 slot Merge Machine siap. MERGE tidak disentuh.", true)
            elseif success == false then
                window.SetStatus("Persiapan gagal. Periksa pesan diagnostik.", false)
            end
        end, function(name,variant,mutation)
            local renders = configs and configs.AnimalRenders
            if renders and type(renders.GetImage) == "function" then
                return renders.GetImage(name,variant,mutation)
            end
            return ""
        end)
        controller.Diagnostics = diagnostics
        controller.TotalIncome = totalIncome
        local report = makeReport(
            animals, diagnostics, totalIncome, scannedTools,
            mergeResults, mergeDiagnostics, configs
        )
        controller.LastReport = report
        window.SetText(report)
        window.SetInventory(animals, function(name,variant,mutation)
            local renders = configs and configs.AnimalRenders
            if renders and type(renders.GetImage) == "function" then
                return renders.GetImage(name,variant,mutation)
            end
            return ""
        end, "INVENTORY  •  " .. #animals .. " hewan  •  TOTAL INCOME: " .. formatIncome(totalIncome))
        window.SetStatus("Selesai - " .. #animals .. " hewan | "
            .. #mergeResults .. " rekomendasi", true)
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
        manualTab.Destroy()
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
        MergeCalculator = MergeCalculator,
        MergePreparation = MergePreparation,
        MachineSlotReader = MachineSlotReader,
        ManualMergeTab = ManualMergeTab,
        MainWindow = MainWindow,
    }
})

return controller
