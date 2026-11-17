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
