-- MainWindow.lua
-- Modular GUI: Inventory, Recommendation, Manual Merge.
local MainWindow = {}

local function make(class, props, parent)
    local o = Instance.new(class)
    for k,v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end

local function corner(o, radius)
    Instance.new("UICorner", o).CornerRadius = UDim.new(0, radius or 7)
end

function MainWindow.Create(playerGui)
    local old = playerGui:FindFirstChild("MergeAdvisorModular")
    if old then old:Destroy() end

    local gui = make("ScreenGui", {
        Name="MergeAdvisorModular", ResetOnSpawn=false,
        DisplayOrder=999, ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    }, playerGui)

    local frame = make("Frame", {
        Name="Main", Size=UDim2.new(0.94,0,0.84,0),
        Position=UDim2.fromScale(0.5,0.5), AnchorPoint=Vector2.new(0.5,0.5),
        BackgroundColor3=Color3.fromRGB(25,32,46), BorderSizePixel=0,
        ClipsDescendants=true
    }, gui)
    corner(frame, 12)
    local stroke=Instance.new("UIStroke",frame)
    stroke.Color=Color3.fromRGB(65,105,155)
    stroke.Thickness=1

    local header=make("Frame",{
        Name="Header",Size=UDim2.new(1,0,0,43),
        BackgroundColor3=Color3.fromRGB(35,105,180),BorderSizePixel=0
    },frame)

    make("TextLabel",{
        Name="Title",Position=UDim2.fromOffset(12,0),
        Size=UDim2.new(1,-125,1,0),BackgroundTransparency=1,
        Text="MERGE ADVISOR",TextColor3=Color3.fromRGB(255,225,130),
        Font=Enum.Font.GothamBold,TextSize=15,
        TextXAlignment=Enum.TextXAlignment.Left
    },header)

    local function headerButton(name, text, x, color)
        local b=make("TextButton",{
            Name=name,Size=UDim2.fromOffset(30,28),
            Position=UDim2.new(1,x,0,7),BackgroundColor3=color,
            BorderSizePixel=0,Text=text,TextColor3=Color3.new(1,1,1),
            Font=Enum.Font.GothamBold,TextSize=16
        },header)
        corner(b,6)
        return b
    end

    local expand=headerButton("Expand","↗",-105,Color3.fromRGB(42,135,110))
    local minimize=headerButton("Minimize","−",-70,Color3.fromRGB(70,85,110))
    local close=headerButton("Close","×",-35,Color3.fromRGB(160,60,70))

    local floating=make("TextButton",{
        Name="MergeAdvisorFloatingIcon",Size=UDim2.fromOffset(54,54),
        Position=UDim2.new(1,-18,1,-90),AnchorPoint=Vector2.new(1,1),
        BackgroundColor3=Color3.fromRGB(42,115,195),
        BorderSizePixel=0,Text="🐾",TextSize=24,
        Visible=false,ZIndex=100
    },gui)
    corner(floating,27)
    local fs=Instance.new("UIStroke",floating)
    fs.Color=Color3.fromRGB(255,215,110)
    fs.Thickness=2

    local status=make("TextLabel",{
        Name="Status",Position=UDim2.fromOffset(10,45),
        Size=UDim2.new(1,-20,0,22),BackgroundTransparency=1,
        Text="Status: Starting...",TextColor3=Color3.fromRGB(255,205,110),
        Font=Enum.Font.Gotham,TextSize=10,
        TextXAlignment=Enum.TextXAlignment.Left
    },frame)

    local tabs=make("Frame",{
        Name="Tabs",Position=UDim2.fromOffset(10,70),
        Size=UDim2.new(1,-20,0,30),BackgroundTransparency=1
    },frame)

    local content=make("Frame",{
        Name="Content",Position=UDim2.fromOffset(10,106),
        Size=UDim2.new(1,-20,1,-116),
        BackgroundTransparency=1
    },frame)

    local pages={}
    local tabButtons={}
    local function page(name)
        local f=make("ScrollingFrame",{
            Name=name,Size=UDim2.fromScale(1,1),
            BackgroundColor3=Color3.fromRGB(15,20,30),
            BorderSizePixel=0,ScrollBarThickness=5,
            CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,
            Visible=false
        },content)
        corner(f,7)
        local layout=Instance.new("UIListLayout",f)
        layout.Padding=UDim.new(0,5)
        layout.SortOrder=Enum.SortOrder.LayoutOrder
        local pad=Instance.new("UIPadding",f)
        pad.PaddingTop=UDim.new(0,7)
        pad.PaddingLeft=UDim.new(0,7)
        pad.PaddingRight=UDim.new(0,7)
        pad.PaddingBottom=UDim.new(0,7)
        pages[name]=f
        return f
    end

    local inventoryPage=page("InventoryPage")
    local recommendationPage=page("RecommendationPage")
    local manualPage=make("Frame",{
        Name="ManualPage",Size=UDim2.fromScale(1,1),
        BackgroundTransparency=1,Visible=false
    },content)
    pages.ManualPage=manualPage

    local function tab(name,text,x)
        local b=make("TextButton",{
            Name=name,Position=UDim2.new(x,0,0,0),
            Size=UDim2.new(0.333,-5,1,0),
            BackgroundColor3=Color3.fromRGB(50,70,100),
            BorderSizePixel=0,Text=text,TextColor3=Color3.new(1,1,1),
            Font=Enum.Font.GothamBold,TextSize=10
        },tabs)
        corner(b,6)
        tabButtons[name]=b
        return b
    end

    local function show(which)
        for name,p in pairs(pages) do p.Visible=(name==which) end
        for name,b in pairs(tabButtons) do
            b.BackgroundColor3=(name==which)
                and Color3.fromRGB(38,135,110)
                or Color3.fromRGB(50,70,100)
        end
    end

    tab("InventoryTab","INVENTORY",0).Activated:Connect(function() show("InventoryPage") end)
    tab("RecommendationTab","RECOMMENDATION",0.333).Activated:Connect(function() show("RecommendationPage") end)
    tab("ManualTab","MANUAL MERGE",0.666).Activated:Connect(function() show("ManualPage") end)

    local function clearRows(parent)
        for _,v in ipairs(parent:GetChildren()) do
            if v:IsA("GuiObject") and not v:IsA("UIListLayout")
                and not v:IsA("UIPadding") then v:Destroy() end
        end
    end

    local function addText(parent,text,height,color,size)
        return make("TextLabel",{
            Size=UDim2.new(1,-4,0,height or 30),
            BackgroundColor3=Color3.fromRGB(34,46,65),
            BorderSizePixel=0,Text=tostring(text),
            TextColor3=color or Color3.fromRGB(225,235,248),
            Font=Enum.Font.Code,TextSize=size or 10,
            TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
            TextYAlignment=Enum.TextYAlignment.Center
        },parent)
    end

    local api={}
    function api.GetManualRoot() return manualPage end

    function api.SetStatus(text,success)
        status.Text="Status: "..tostring(text)
        status.TextColor3=success and Color3.fromRGB(125,230,160)
            or Color3.fromRGB(255,195,110)
    end

    function api.SetText(text)
        clearRows(inventoryPage)
        local label=addText(inventoryPage,text, math.max(90, math.min(6000, #tostring(text)*0.19)),
            Color3.fromRGB(220,230,245),10)
        label.AutomaticSize=Enum.AutomaticSize.Y
        label.Size=UDim2.new(1,-4,0,0)
        label.TextYAlignment=Enum.TextYAlignment.Top
        label.BackgroundTransparency=1
        label.Position=UDim2.fromOffset(3,3)
        inventoryPage.CanvasPosition=Vector2.new(0,0)
    end

    function api.SetInventory(animals,getImage,summary)
        clearRows(inventoryPage)

        addText(inventoryPage, summary or
            ("INVENTORY  •  " .. tostring(#(animals or {})) .. " hewan"),
            30, Color3.fromRGB(255,220,120), 12)

        if type(animals) ~= "table" or #animals == 0 then
            addText(inventoryPage, "Belum ada hewan terbaca.", 42)
            return
        end

        for i,pet in ipairs(animals) do
            local name = tostring(pet.name or pet.AnimalName or pet.Name or "Unknown")
            local kg = tonumber(pet.kg or pet.WeightKg) or 0
            local income = tonumber(pet.income or pet.Income
                or pet.CashPerSecond or pet.PlacedCashPerSecond) or 0
            local variant = tostring(pet.var or pet.Variant or "Normal")
            local mutation = tostring(pet.mut or pet.Mutation or "None")

            local card = make("Frame", {
                Size = UDim2.new(1,-4,0,66),
                BackgroundColor3 = Color3.fromRGB(35,49,70),
                BorderSizePixel = 0,
                LayoutOrder = i
            }, inventoryPage)
            corner(card,7)

            local image = ""
            if type(getImage) == "function" then
                local ok,value = pcall(getImage,name,
                    pet.var or pet.Variant, pet.mut or pet.Mutation)
                if ok and type(value) == "string" then image = value end
            end

            make("ImageLabel", {
                Name = "AnimalImage",
                Position = UDim2.fromOffset(5,5),
                Size = UDim2.fromOffset(56,56),
                BackgroundColor3 = Color3.fromRGB(24,34,49),
                BorderSizePixel = 0,
                ScaleType = Enum.ScaleType.Fit,
                Image = image
            },card)

            make("TextLabel", {
                Position = UDim2.fromOffset(68,5),
                Size = UDim2.new(1,-74,0,21),
                BackgroundTransparency = 1,
                Text = name,
                TextColor3 = Color3.fromRGB(255,220,120),
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left
            },card)

            make("TextLabel", {
                Position = UDim2.fromOffset(68,27),
                Size = UDim2.new(1,-74,0,32),
                BackgroundTransparency = 1,
                Text = string.format("%.1f kg  |  %s/s\n%s  •  %s",
                    kg, tostring(income), variant, mutation),
                TextColor3 = Color3.fromRGB(215,228,245),
                Font = Enum.Font.Code,
                TextSize = 9,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left
            },card)
        end

        inventoryPage.CanvasPosition = Vector2.new(0,0)
    end

    function api.SetRecommendations(results,onPick,getImage)
        clearRows(recommendationPage)
        addText(recommendationPage,"REKOMENDASI MERGE  •  "..tostring(#(results or {})).." kandidat",30,
            Color3.fromRGB(255,220,120),12)
        if not results or #results==0 then
            addText(recommendationPage,"Belum ada kandidat merge yang memenuhi syarat.",45)
            return
        end
        for i,result in ipairs(results) do
            local pets=result.Pets or {}
            local names={}
            for _,pet in ipairs(pets) do
                table.insert(names,tostring(pet.AnimalName or pet.Name or pet.name or "Hewan"))
            end
            local card=make("Frame",{
                Size=UDim2.new(1,-4,0,94),
                BackgroundColor3=Color3.fromRGB(35,49,70),
                BorderSizePixel=0,LayoutOrder=i
            },recommendationPage)
            corner(card,7)

            local firstPet = pets[1]
            local image = ""
            if firstPet and type(getImage) == "function" then
                local petName = firstPet.name or firstPet.AnimalName
                    or firstPet.Name
                local ok,value = pcall(getImage,petName,
                    firstPet.var or firstPet.Variant,
                    firstPet.mut or firstPet.Mutation)
                if ok and type(value) == "string" then image = value end
            end

            make("ImageLabel", {
                Name = "AnimalImage",
                Position = UDim2.fromOffset(7,34),
                Size = UDim2.fromOffset(52,52),
                BackgroundColor3 = Color3.fromRGB(24,34,49),
                BorderSizePixel = 0,
                ScaleType = Enum.ScaleType.Fit,
                Image = image
            },card)

            make("TextLabel",{
                Position=UDim2.fromOffset(66,5),Size=UDim2.new(1,-158,0,23),
                BackgroundTransparency=1,
                Text="#"..i.."  "..tostring(result.Name or table.concat(names," / ")),
                TextColor3=Color3.fromRGB(255,220,120),
                Font=Enum.Font.GothamBold,TextSize=11,
                TextXAlignment=Enum.TextXAlignment.Left
            },card)
            make("TextLabel",{
                Position=UDim2.fromOffset(66,29),Size=UDim2.new(1,-158,0,58),
                BackgroundTransparency=1,
                Text="Gain: "..tostring(result.Gain).."  |  Ratio: x"..string.format("%.3f",tonumber(result.Ratio) or 0)
                    .."\nExpected: "..tostring(result.Expected).."  |  Best: "..tostring(result.Best)
                    .."  |  Worst: "..tostring(result.Worst),
                TextColor3=Color3.fromRGB(215,228,245),
                Font=Enum.Font.Code,TextSize=9,TextWrapped=true,
                TextXAlignment=Enum.TextXAlignment.Left
            },card)
            local pick=make("TextButton",{
                Name="SelectCandidate",Position=UDim2.new(1,-88,0,5),
                Size=UDim2.fromOffset(80,25),
                BackgroundColor3=Color3.fromRGB(38,135,110),
                BorderSizePixel=0,Text="PILIH",
                TextColor3=Color3.new(1,1,1),
                Font=Enum.Font.GothamBold,TextSize=10
            },card)
            corner(pick,5)
            pick.MouseButton1Click:Connect(function()
                if type(onPick)=="function" then
                    local ok,err=pcall(onPick,result)
                    if not ok then
                        warn("[MergeAdvisor] PILIH ERROR: "..tostring(err))
                    end
                end
            end)
        end
        recommendationPage.CanvasPosition=Vector2.new(0,0)
    end

    function api.ShowTab(which)
        if which=="manual" then show("ManualPage")
        elseif which=="recommendation" then show("RecommendationPage")
        else show("InventoryPage") end
    end

    function api.OnRefresh(callback) end
    function api.OnCopy(callback) end
    function api.Destroy() gui:Destroy() end

    local minimized=false
    local expanded=true
    local function setMinimized(value)
        minimized=value
        frame.Visible=not value
        floating.Visible=value
    end
    minimize.Activated:Connect(function() setMinimized(true) end)
    close.Activated:Connect(function() setMinimized(true) end)
    floating.Activated:Connect(function() setMinimized(false) end)
    expand.Activated:Connect(function()
        expanded=not expanded
        frame.Size=expanded and UDim2.new(0.94,0,0.84,0)
            or UDim2.new(0.82,0,0.70,0)
        expand.Text=expanded and "↗" or "↙"
    end)

    local UIS=game:GetService("UserInputService")
    local dragging,dragStart,startPos=false,nil,nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1
            or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true;dragStart=input.Position;startPos=frame.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement
            or input.UserInputType==Enum.UserInputType.Touch) then
            local d=input.Position-dragStart
            frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,
                startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1
            or input.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)

    show("InventoryPage")
    return api
end

return MainWindow
