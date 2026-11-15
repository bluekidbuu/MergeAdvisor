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
        "  Joint outcomes: %d | Probabilitas termodel: %.2f%%",
        #result.Outcomes, result.ProbabilityTotal * 100
    ))

    table.insert(lines, "  HASIL VARIANT:")
    for _, option in ipairs(result.VariantOdds) do
        table.insert(lines, string.format("    %s: %.2f%%",
            tostring(option.Name or "Normal"), option.Chance * 100))
    end
    table.insert(lines, "  HASIL MUTATION:")
    for _, option in ipairs(result.MutationOdds) do
        table.insert(lines, string.format("    %s: %.2f%%",
            tostring(option.Name or "None"), option.Chance * 100))
    end

    table.insert(lines, "  OUTCOME TERATAS:")
    for index = 1, math.min(6, #result.Outcomes) do
        local outcome = result.Outcomes[index]
        table.insert(lines, string.format("    %s / %s | %.2f%% | %s",
            tostring(outcome.Variant), tostring(outcome.Mutation),
            outcome.Chance * 100, formatIncome(outcome.Income)))
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
        controller.Diagnostics = diagnostics
        controller.TotalIncome = totalIncome
        local report = makeReport(
            animals, diagnostics, totalIncome, scannedTools,
            mergeResults, mergeDiagnostics, configs
        )
        controller.LastReport = report
        window.SetText(report)
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
