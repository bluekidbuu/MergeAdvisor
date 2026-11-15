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

return IncomeCalculator
