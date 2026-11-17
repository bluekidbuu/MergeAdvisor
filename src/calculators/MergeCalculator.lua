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
