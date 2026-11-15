-- MainWindow.lua
-- GUI diagnostik dengan output scrollable untuk inventory panjang.

local MainWindow = {}

function MainWindow.Create(playerGui)
    local old = playerGui:FindFirstChild("MergeAdvisorModular")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "MergeAdvisorModular"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.fromOffset(350, 430)
    frame.Position = UDim2.new(0.5, -175, 0.5, -215)
    frame.BackgroundColor3 = Color3.fromRGB(23, 26, 34)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(65, 76, 96)
    stroke.Thickness = 1

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 38)
    title.Position = UDim2.fromOffset(10, 5)
    title.BackgroundTransparency = 1
    title.Text = "MERGE ADVISOR"
    title.TextColor3 = Color3.fromRGB(235, 240, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 17
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.Size = UDim2.new(1, -20, 0, 25)
    status.Position = UDim2.fromOffset(10, 43)
    status.BackgroundTransparency = 1
    status.Text = "Status: Starting..."
    status.TextColor3 = Color3.fromRGB(255, 205, 100)
    status.Font = Enum.Font.Gotham
    status.TextSize = 11
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextTruncate = Enum.TextTruncate.AtEnd
    status.Parent = frame

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "ReportScroll"
    scroll.Position = UDim2.fromOffset(10, 72)
    scroll.Size = UDim2.new(1, -20, 1, -125)
    scroll.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 5
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.Parent = frame
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)

    local output = Instance.new("TextLabel")
    output.Name = "Output"
    output.BackgroundTransparency = 1
    output.Position = UDim2.fromOffset(8, 7)
    output.Size = UDim2.new(1, -16, 0, 0)
    output.AutomaticSize = Enum.AutomaticSize.Y
    output.TextColor3 = Color3.fromRGB(215, 225, 240)
    output.Font = Enum.Font.Code
    output.TextSize = 11
    output.TextXAlignment = Enum.TextXAlignment.Left
    output.TextYAlignment = Enum.TextYAlignment.Top
    output.TextWrapped = true
    output.Text = "Menunggu data..."
    output.Parent = scroll

    local function makeButton(name, text, x, width)
        local button = Instance.new("TextButton")
        button.Name = name
        button.Size = UDim2.new(0, width, 0, 34)
        button.Position = UDim2.new(0, x, 1, -43)
        button.BackgroundColor3 = Color3.fromRGB(48, 91, 155)
        button.BorderSizePixel = 0
        button.Text = text
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Font = Enum.Font.GothamBold
        button.TextSize = 12
        button.Parent = frame
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
        return button
    end

    local refresh = makeButton("Refresh", "REFRESH", 10, 160)
    local copy = makeButton("Copy", "COPY REPORT", 180, 160)

    local UserInputService = game:GetService("UserInputService")
    local dragging, dragStart, startPosition = false, nil, nil
    local dragConnections = {}
    table.insert(dragConnections, title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = frame.Position
        end
    end))
    table.insert(dragConnections, title.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
    table.insert(dragConnections, UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X,
                startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end))

    local api = {}
    function api.SetStatus(text, success)
        status.Text = "Status: " .. tostring(text)
        status.TextColor3 = success and Color3.fromRGB(120, 230, 150)
            or Color3.fromRGB(255, 190, 100)
    end
    function api.SetText(text)
        output.Text = tostring(text)
        scroll.CanvasPosition = Vector2.new(0, 0)
    end
    function api.OnRefresh(callback) refresh.Activated:Connect(callback) end
    function api.OnCopy(callback) copy.Activated:Connect(callback) end
    function api.Destroy()
        for _, connection in ipairs(dragConnections) do
            pcall(function() connection:Disconnect() end)
        end
        gui:Destroy()
    end
    return api
end

return MainWindow
