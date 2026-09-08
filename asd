local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local root = char:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(c)
    char = c
    root = char:WaitForChild("HumanoidRootPart")
end)

-- Создание GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 300, 0, 380)
frame.Position = UDim2.new(0.5, -150, 0.5, -190)
frame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Visible = false
frame.Parent = screenGui

-- Заголовок
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
title.Text = "Телепорт меню (Z - открыть/закрыть)"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.SourceSansBold
title.TextSize = 14
title.Parent = frame

-- Поле для ввода дистанции
local distLabel = Instance.new("TextLabel")
distLabel.Size = UDim2.new(1, 0, 0, 20)
distLabel.Position = UDim2.new(0, 0, 0, 35)
distLabel.BackgroundTransparency = 1
distLabel.Text = "Дистанция (в см):"
distLabel.TextColor3 = Color3.new(1, 1, 1)
distLabel.Font = Enum.Font.SourceSans
distLabel.TextSize = 14
distLabel.Parent = frame

local distBox = Instance.new("TextBox")
distBox.Size = UDim2.new(1, -20, 0, 30)
distBox.Position = UDim2.new(0, 10, 0, 55)
distBox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
distBox.Text = "10"
distBox.TextColor3 = Color3.new(1, 1, 1)
distBox.Font = Enum.Font.SourceSans
distBox.TextSize = 14
distBox.Parent = frame

-- Выбор направления
local dirLabel = Instance.new("TextLabel")
dirLabel.Size = UDim2.new(1, 0, 0, 20)
dirLabel.Position = UDim2.new(0, 0, 0, 90)
dirLabel.BackgroundTransparency = 1
dirLabel.Text = "Направление:"
dirLabel.TextColor3 = Color3.new(1, 1, 1)
dirLabel.Font = Enum.Font.SourceSans
dirLabel.TextSize = 14
dirLabel.Parent = frame

local directions = {"Вниз", "Вверх", "Вправо", "Влево", "Вперед", "Назад", "По взгляду", "По мышке"}
local dirButtons = {}
local selectedDir = "Вниз"

for i, dir in ipairs(directions) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.31, 0, 0, 25)
    
    -- Размещение кнопок в 3 колонки
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    btn.Position = UDim2.new(0, 5 + col * 95, 0, 110 + row * 30)
    
    btn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    btn.Text = dir
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = Enum.Font.SourceSans
    btn.TextSize = 11
    btn.Parent = frame
    
    btn.MouseButton1Click:Connect(function()
        selectedDir = dir
        for _, b in pairs(dirButtons) do
            b.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
        end
        btn.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
    end)
    
    table.insert(dirButtons, btn)
end

-- Выбор клавиши
local keyLabel = Instance.new("TextLabel")
keyLabel.Size = UDim2.new(1, 0, 0, 20)
keyLabel.Position = UDim2.new(0, 0, 0, 230)
keyLabel.BackgroundTransparency = 1
keyLabel.Text = "Нажмите клавишу для назначения:"
keyLabel.TextColor3 = Color3.new(1, 1, 1)
keyLabel.Font = Enum.Font.SourceSans
keyLabel.TextSize = 14
keyLabel.Parent = frame

local keyButton = Instance.new("TextButton")
keyButton.Size = UDim2.new(1, -20, 0, 30)
keyButton.Position = UDim2.new(0, 10, 0, 250)
keyButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
keyButton.Text = "N (нажмите чтобы изменить)"
keyButton.TextColor3 = Color3.new(1, 1, 1)
keyButton.Font = Enum.Font.SourceSans
keyButton.TextSize = 14
keyButton.Parent = frame

local selectedKey = Enum.KeyCode.N
local isSelectingKey = false

keyButton.MouseButton1Click:Connect(function()
    isSelectingKey = true
    keyButton.Text = "Нажмите клавишу..."
end)

-- Функция телепортации
local function teleport()
    local dist = tonumber(distBox.Text) or 0
    local offset = Vector3.new(0, 0, 0)
    
    if selectedDir == "Вниз" then
        offset = Vector3.new(0, -dist, 0)
    elseif selectedDir == "Вверх" then
        offset = Vector3.new(0, dist, 0)
    elseif selectedDir == "Вправо" then
        offset = Vector3.new(dist, 0, 0)
    elseif selectedDir == "Влево" then
        offset = Vector3.new(-dist, 0, 0)
    elseif selectedDir == "Вперед" then
        -- Вперед относительно направления камеры (по горизонтали)
        local camera = workspace.CurrentCamera
        local lookVector = camera.CFrame.LookVector
        lookVector = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
        offset = lookVector * dist
    elseif selectedDir == "Назад" then
        -- Назад относительно направления камеры (по горизонтали)
        local camera = workspace.CurrentCamera
        local lookVector = camera.CFrame.LookVector
        lookVector = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
        offset = -lookVector * dist
    elseif selectedDir == "По взгляду" then
        -- Точно по направлению взгляда (включая вверх/вниз)
        local camera = workspace.CurrentCamera
        offset = camera.CFrame.LookVector * dist
    elseif selectedDir == "По мышке" then
        -- Телепорт в сторону курсора мыши
        local mouse = player:GetMouse()
        local camera = workspace.CurrentCamera
        
        -- Создаем луч из камеры через позицию мыши
        local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
        
        -- Направление от персонажа к точке, куда указывает мышь (по горизонтали)
        local direction = (ray.Direction * Vector3.new(1, 0, 1)).Unit
        
        if direction.Magnitude > 0 then
            offset = direction * dist
        else
            -- Если мышь в центре экрана, используем направление камеры
            local lookVector = camera.CFrame.LookVector
            lookVector = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
            offset = lookVector * dist
        end
    end
    
    root.CFrame = root.CFrame + offset
end

-- Обработка клавиш
local keyHeld = false
local lastTeleportTime = 0
local TELEPORT_DELAY = 0.1 -- задержка между телепортами при удержании

UIS.InputBegan:Connect(function(input, gpe)
    if isSelectingKey and input.KeyCode ~= Enum.KeyCode.Unknown then
        selectedKey = input.KeyCode
        keyButton.Text = input.KeyCode.Name .. " (нажмите чтобы изменить)"
        isSelectingKey = false
        return
    end
    
    if input.KeyCode == Enum.KeyCode.Z and not gpe then
        frame.Visible = not frame.Visible
        return
    end
    
    if input.KeyCode == selectedKey and not gpe then
        keyHeld = true
        teleport() -- Телепорт сразу при нажатии
        lastTeleportTime = tick()
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.KeyCode == selectedKey then
        keyHeld = false
    end
end)

RunService.Heartbeat:Connect(function()
    if keyHeld then
        local currentTime = tick()
        if currentTime - lastTeleportTime >= TELEPORT_DELAY then
            teleport()
            lastTeleportTime = currentTime
        end
    end
end)

-- Подсветка выбранного направления
dirButtons[1].BackgroundColor3 = Color3.fromRGB(0, 120, 200)
