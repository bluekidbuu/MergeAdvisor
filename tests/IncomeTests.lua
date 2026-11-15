-- IncomeTests.lua
-- Tests for source-based IncomeCalculator.

-- Compatibility for standard Lua outside Roblox/Luau.
if not math.clamp then
    function math.clamp(value, minimum, maximum)
        return math.max(minimum, math.min(maximum, value))
    end
end

local Calculator = dofile("src/calculators/IncomeCalculator.lua")

local passed = 0
local failed = 0
local results = {}

local function test(name, callback)
    local ok, err = pcall(callback)

    if ok then
        passed = passed + 1
        results[#results + 1] = "[PASS] " .. name
    else
        failed = failed + 1
        results[#results + 1] = "[FAIL] " .. name .. ": " .. tostring(err)
    end
end

local function equal(actual, expected, message)
    assert(
        actual == expected,
        (message or "Value mismatch")
        .. " | expected=" .. tostring(expected)
        .. " actual=" .. tostring(actual)
    )
end

local function near(actual, expected, tolerance, message)
    assert(
        math.abs(actual - expected) <= tolerance,
        (message or "Value outside tolerance")
        .. " | expected=" .. tostring(expected)
        .. " actual=" .. tostring(actual)
    )
end

local animals = {
    AegisWarden = {
        Cash = 58000000000,
        Rarity = "Spectral",
        Zone = 14,
    },

    Dreki = {
        Cash = 80000000000,
        Rarity = "Ethereal",
        Zone = 14,
    },

    TridentTyrant = {
        Cash = 300000000000,
        Rarity = "Primordial",
        Zone = 14,
    },
}

local weightConfig = {
    AnimalKg = {},

    BaseKg = {
        Common = 50,
        Spectral = 165.7,
        Ethereal = 170,
        Primordial = 170,
    },

    CashSizeReference = {
        1.38, 1.48, 1.55, 1.65, 1.7,
        1.73, 1.79, 1.81, 1.81, 1.81, 1.81,
    },

    CashWeightExponent = {
        1.1, 1.12, 1.14, 1.16, 1.18,
        1.2, 1.22, 1.25, 1.27, 1.29, 1.31,
    },

    CashWeightTailExponent = {
        0.55, 0.57, 0.59, 0.61, 0.63,
        0.65, 0.67, 0.70, 0.72, 0.74, 0.76,
    },

    CashWeightKnee = 8,
    CashSizeExponent = 3,
    CashSizeKnee = 2,
    CashSizeTailExponent = 1,
    CashSizeMultMin = 0.2,

    CashSpeciesAnchorKg = 50,
    CashSpeciesWeightExponent = 0.5,
    CashSpeciesWeightMax = 3,
}

local dependencies = {
    AnimalInfo = animals,
    WeightConfig = weightConfig,

    MutationConfig = {
        CashMult = function(mutation)
            local values = {
                Normal = 1,
                Rainbow = 25,
                Radioactive = 12,
            }
            return values[mutation] or 1
        end,
    },

    VariantCashMult = function(variant)
        local values = {
            Normal = 1,
            Gold = 3.5,
            Diamond = 6,
        }
        return values[variant] or 1
    end,

    EnchantConfig = {
        CashMult = function(enchant)
            local values = {
                ["Cash:1"] = 1.2,
                ["Cash:2"] = 1.4,
                ["Cash:3"] = 1.75,
            }
            return values[enchant] or 1
        end,
    },
}

test("AegisWarden baseline Zone 14", function()
    local income = Calculator.Calculate({
        AnimalName = "AegisWarden",
        WeightKg = 165.7,
    }, dependencies)

    equal(income, 105585491428)
end)

test("Dreki baseline Zone 14", function()
    local income = Calculator.Calculate({
        AnimalName = "Dreki",
        WeightKg = 170,
    }, dependencies)

    equal(income, 147512711317)
end)

test("TridentTyrant baseline Zone 14", function()
    local income = Calculator.Calculate({
        AnimalName = "TridentTyrant",
        WeightKg = 170,
    }, dependencies)

    equal(income, 553172667438)
end)

test("WeightKg takes priority over SizeMult", function()
    local _, breakdown = Calculator.Calculate({
        AnimalName = "Dreki",
        WeightKg = 170,
        SizeMult = 2,
    }, dependencies)

    equal(breakdown.WeightSource, "WeightKg")
    equal(breakdown.WeightMultiplier, 1)
end)

test("SizeMult used when WeightKg is zero", function()
    local _, breakdown = Calculator.Calculate({
        AnimalName = "Dreki",
        WeightKg = 0,
        SizeMult = 1,
    }, dependencies)

    equal(breakdown.WeightSource, "SizeMult")
    near(breakdown.WeightMultiplier, 1, 0.000001)
end)

test("Rainbow mutation multiplier", function()
    local income, breakdown = Calculator.Calculate({
        AnimalName = "Dreki",
        WeightKg = 170,
        Mutation = "Rainbow",
    }, dependencies)

    equal(breakdown.MutationMultiplier, 25)
    equal(income, 3687817782917)
end)

test("Gold variant multiplier", function()
    local _, breakdown = Calculator.Calculate({
        AnimalName = "Dreki",
        WeightKg = 170,
        Variant = "Gold",
    }, dependencies)

    equal(breakdown.VariantMultiplier, 3.5)
end)

test("Cash:1 enchant multiplier", function()
    local _, breakdown = Calculator.Calculate({
        AnimalName = "Dreki",
        WeightKg = 170,
        Enchant = "Cash:1",
    }, dependencies)

    equal(breakdown.EnchantMultiplier, 1.2)
end)

test("Cash:2 enchant multiplier", function()
    local _, breakdown = Calculator.Calculate({
        AnimalName = "Dreki",
        WeightKg = 170,
        Enchant = "Cash:2",
    }, dependencies)

    equal(breakdown.EnchantMultiplier, 1.4)
end)

test("Cash:3 enchant multiplier", function()
    local _, breakdown = Calculator.Calculate({
        AnimalName = "Dreki",
        WeightKg = 170,
        Enchant = "Cash:3",
    }, dependencies)

    equal(breakdown.EnchantMultiplier, 1.75)
end)

test("All multipliers combine", function()
    local income, breakdown = Calculator.Calculate({
        AnimalName = "Dreki",
        WeightKg = 170,
        Mutation = "Rainbow",
        Variant = "Gold",
        Enchant = "Cash:3",
    }, dependencies)

    equal(breakdown.MutationMultiplier, 25)
    equal(breakdown.VariantMultiplier, 3.5)
    equal(breakdown.EnchantMultiplier, 1.75)

    equal(income, math.floor(
        80000000000 * math.sqrt(170 / 50) * 25 * 3.5 * 1.75 + 0.5
    ))
end)

test("Unknown animal is rejected", function()
    local ok = pcall(function()
        Calculator.Calculate({
            AnimalName = "UnknownAnimal",
            WeightKg = 100,
        }, dependencies)
    end)

    equal(ok, false)
end)

-- Visible output; no console dependency for Delta Executor.
local report = {
    "INCOME CALCULATOR TEST",
    "======================",
    "",
}

for _, result in ipairs(results) do
    report[#report + 1] = result
end

report[#report + 1] = ""
report[#report + 1] = "PASSED: " .. passed
report[#report + 1] = "FAILED: " .. failed
report[#report + 1] = "TOTAL: " .. (passed + failed)

local output = table.concat(report, "\n")

if type(shared) == "table" then
    shared.MergeAdvisorIncomeTestReport = output
end

if type(writefile) == "function" then
    pcall(writefile, "IncomeTestReport.txt", output)
end

print(output)

return {
    Passed = passed,
    Failed = failed,
    Report = output,
}
