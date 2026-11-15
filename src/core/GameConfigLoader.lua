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
