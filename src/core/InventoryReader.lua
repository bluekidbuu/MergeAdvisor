-- InventoryReader
-- Migrasi scanner inventory dari MergeAdvisor v10.2.0.
-- Read-only: tidak mengubah Tool, atribut, atau tag game.

local InventoryReader = {}

local ATTRIBUTES = {
    "AnimalName",
    "WeightKg",
    "Variant",
    "Mutation",
    "SizeMult",
    "Enchant",
}

local function readValue(tool, key)
    local ok, value = pcall(function()
        return tool:GetAttribute(key)
    end)

    if ok and value ~= nil then
        return value
    end

    local child = tool:FindFirstChild(key, true)

    if child and child:IsA("ValueBase") then
        return child.Value
    end

    return nil
end

local function isOwnedTool(tool, player)
    if not tool or not tool:IsA("Tool") then
        return false
    end

    local backpack = player:FindFirstChildOfClass("Backpack")
        or player:FindFirstChild("Backpack")

    local character = player.Character

    return (backpack and tool:IsDescendantOf(backpack))
        or (character and tool:IsDescendantOf(character))
end

local function validString(value)
    return type(value) == "string" and value ~= ""
end

function InventoryReader.ReadValue(tool, key)
    return readValue(tool, key)
end

function InventoryReader.Scan(player, collectionService, incomeCalculator, configs)
    assert(player, "Player wajib tersedia")
    assert(collectionService, "CollectionService wajib tersedia")
    assert(incomeCalculator, "IncomeCalculator wajib tersedia")
    assert(configs, "Game configs wajib tersedia")

    local pets = {}
    local diagnostics = {}
    local tools = {}
    local seen = {}

    -- Sumber resmi inventory: tag AnimalTool.
    for _, tool in ipairs(collectionService:GetTagged("AnimalTool")) do
        if isOwnedTool(tool, player) and not seen[tool] then
            seen[tool] = true
            table.insert(tools, tool)
        end
    end

    for _, tool in ipairs(tools) do
        local tagged = false

        pcall(function()
            tagged = collectionService:HasTag(tool, "AnimalTool")
        end)

        if tagged then
            local name = readValue(tool, "AnimalName")
            local weight = readValue(tool, "WeightKg")

            if not validString(name) then
                local fallback = tool.Name

                if validString(fallback) and fallback ~= "Tool" then
                    name = fallback
                end
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
                    name = name,
                    kg = weight,
                    var = validString(variant) and variant or nil,
                    mut = validString(mutation) and mutation or nil,
                    size = type(size) == "number" and size or nil,
                    enchant = validString(enchant) and enchant or nil,
                    tool = tool,
                }

                local ok, income = pcall(function()
                    return incomeCalculator.CalculateFromGame(
                        configs,
                        pet.name,
                        pet.size,
                        pet.mut,
                        pet.kg,
                        pet.var,
                        pet.enchant
                    )
                end)

                if ok and type(income) == "number" and income >= 0 then
                    pet.income = income
                    table.insert(pets, pet)
                else
                    reason = "Income gagal dihitung: " .. tostring(income)
                end
            end

            if reason then
                table.insert(
                    diagnostics,
                    "[SKIP] " .. tool:GetFullName() .. " | " .. reason
                )
            end
        end
    end

    return pets, diagnostics, #tools
end

return InventoryReader
