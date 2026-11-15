-- Bootstrap.lua
-- Penghubung modul utama MergeAdvisor.

local Bootstrap = {}

local function safeString(value)
    if value == nil then
        return "-"
    end

    return tostring(value)
end

local function getIncome(animal)
    return tonumber(
        animal.Income
        or animal.CashPerSecond
        or animal.PlacedCashPerSecond
        or animal.income
    ) or 0
end

local function getAnimalName(animal)
    return safeString(
        animal.AnimalName
        or animal.Name
        or animal.name
        or animal.ToolName
    )
end

local function formatIncome(value)
    if value >= 1e12 then
        return string.format("%.2fT/s", value / 1e12)
    elseif value >= 1e9 then
        return string.format("%.2fB/s", value / 1e9)
    elseif value >= 1e6 then
        return string.format("%.2fM/s", value / 1e6)
    elseif value >= 1e3 then
        return string.format("%.2fK/s", value / 1e3)
    end

    return string.format("%.2f/s", value)
end

function Bootstrap.Start(options)
    options = options or {}

    local modules = options.Modules or {}

    local ConfigLoader = assert(
        modules.GameConfigLoader,
        "GameConfigLoader belum dimasukkan"
    )

    local InventoryReader = assert(
        modules.InventoryReader,
        "InventoryReader belum dimasukkan"
    )

    local IncomeCalculator = assert(
        modules.IncomeCalculator,
        "IncomeCalculator belum dimasukkan"
    )

    local MainWindow = assert(
        modules.MainWindow,
        "MainWindow belum dimasukkan"
    )

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
        Configs = nil,
        Animals = {},
        Diagnostics = {},
        LastReport = "",
        Destroyed = false
    }

    local function makeReport(animals, diagnostics)
        local lines = {}

        table.insert(lines, "MERGE ADVISOR")
        table.insert(lines, "==============================")
        table.insert(lines, "Player: " .. player.Name)
        table.insert(lines, "Hewan terbaca: " .. #animals)
        table.insert(lines, "")

        table.insert(lines, "INVENTORY")
        table.insert(lines, "------------------------------")

        if #animals == 0 then
            table.insert(lines, "Belum ada hewan yang terbaca.")
        end

        for index, animal in ipairs(animals) do
            local name = getAnimalName(animal)
            local income = getIncome(animal)

            table.insert(
                lines,
                string.format(
                    "%02d. %s | %s",
                    index,
                    name,
                    formatIncome(income)
                )
            )
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
        if controller.Destroyed then
            return false, "Controller sudah dihentikan"
        end

        window.SetStatus("Memuat konfigurasi...", false)

        local configOK, configs, configErrors = pcall(function()
            return ConfigLoader.Load(ReplicatedStorage)
        end)

        if not configOK then
            local message = "ConfigLoader gagal: " .. safeString(configs)
            window.SetStatus("Config gagal", false)
            window.SetText(message)
            controller.LastReport = message
            return false, message
        end

        if type(configs) ~= "table" then
            local message = "ConfigLoader tidak mengembalikan tabel konfigurasi"
            window.SetStatus("Config tidak valid", false)
            window.SetText(message)
            controller.LastReport = message
            return false, message
        end

        controller.Configs = configs

        local diagnostics = {}

        if type(configErrors) == "table" then
            for _, message in ipairs(configErrors) do
                table.insert(diagnostics, message)
            end
        end

        if type(configs.Errors) == "table" then
            for _, message in ipairs(configs.Errors) do
                table.insert(diagnostics, message)
            end
        end

        window.SetStatus("Membaca inventory...", false)

        local scanOK, animals, scanDiagnostics = pcall(function()
            return InventoryReader.Scan(
                player,
                CollectionService,
                IncomeCalculator,
                configs
            )
        end)

        if not scanOK then
            local message = "InventoryReader gagal: " .. safeString(animals)
            window.SetStatus("Scan gagal", false)
            window.SetText(message)
            controller.LastReport = message
            return false, message
        end

        if type(animals) ~= "table" then
            animals = {}
            table.insert(diagnostics, "InventoryReader tidak mengembalikan daftar hewan")
        end

        if type(scanDiagnostics) == "table" then
            for _, message in ipairs(scanDiagnostics) do
                table.insert(diagnostics, message)
            end
        end

        table.sort(animals, function(a, b)
            return getIncome(a) > getIncome(b)
        end)

        controller.Animals = animals
        controller.Diagnostics = diagnostics

        local report = makeReport(animals, diagnostics)

        controller.LastReport = report
        window.SetText(report)
        window.SetStatus(
            "Selesai - " .. #animals .. " hewan terbaca",
            true
        )

        return true, report
    end

    window.OnRefresh(function()
        controller.Refresh()
    end)

    window.OnCopy(function()
        local clipboard = setclipboard or toclipboard

        if type(clipboard) == "function" then
            local ok = pcall(clipboard, controller.LastReport)

            if ok then
                window.SetStatus("Report disalin", true)
            else
                window.SetStatus("Gagal menyalin report", false)
            end
        else
            window.SetStatus("Clipboard tidak tersedia", false)
        end
    end)

    function controller.Destroy()
        if controller.Destroyed then
            return
        end

        controller.Destroyed = true
        window.Destroy()
    end

    controller.Refresh()

    return controller
end

return Bootstrap
