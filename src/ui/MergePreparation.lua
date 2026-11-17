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
