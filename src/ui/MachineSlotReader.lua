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
