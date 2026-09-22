--!nocheck
-- Cobalt Arg Hooker Plugin v5 (без генератора, стабильная версия)

print("[ArgHooker] loading...")

Cobalt.PluginData = {
    Name = "Arg Hooker",
    Description = "Hook remotes and firesignal",
    Author = "you",
    Version = "5.0.0",
}

print("[ArgHooker] PluginData ok")

-- ============================================================
-- Toast
-- ============================================================
local function toastOk(msg)
    pcall(function()
        if Cobalt.Sonner and Cobalt.Sonner.success then
            Cobalt.Sonner.success(msg)
        else
            print("[ArgHooker] " .. msg)
        end
    end)
end

local function toastErr(msg)
    pcall(function()
        if Cobalt.Sonner and Cobalt.Sonner.error then
            Cobalt.Sonner.error(msg)
        else
            warn("[ArgHooker] " .. msg)
        end
    end)
end

-- ============================================================
-- Storage
-- ============================================================
local Hooks = {}
local nextId = 1
local globalEnabled = true

-- ============================================================
-- Helpers
-- ============================================================
local function getMethodNameFromString(method)
    local m = tostring(method or ""):lower()
    if m == "fireserver" then return "FireServer"
    elseif m == "invokeserver" then return "InvokeServer"
    elseif m == "fire" then return "Fire"
    elseif m == "invoke" then return "Invoke"
    elseif m == "firesignal" then return "FireSignal"
    end
    return method
end

local function hookMatches(hook, instanceName, method)
    if not hook.enabled then return false end
    if hook.remoteName ~= "*" and hook.remoteName ~= instanceName then return false end
    if hook.method ~= "*" and hook.method:lower() ~= method:lower() then return false end
    return true
end

local function serializeValue(v)
    if v == nil then return "nil" end
    local t = typeof(v)

    if t == "string" then
        return string.format("%q", v)
    elseif t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then
            return tostring(math.floor(v))
        end
        return tostring(v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "Vector3" then
        return string.format("Vector3.new(%g, %g, %g)", v.X, v.Y, v.Z)
    elseif t == "Vector2" then
        return string.format("Vector2.new(%g, %g)", v.X, v.Y)
    elseif t == "Instance" then
        local ok, full = pcall(function() return v:GetFullName() end)
        return (ok and full) or "nil"
    elseif t == "Color3" then
        return string.format("Color3.new(%g, %g, %g)", v.R, v.G, v.B)
    elseif t == "table" then
        local isArray = true
        local maxIndex = 0
        local count = 0
        for k, _ in pairs(v) do
            count = count + 1
            if type(k) == "number" and k > maxIndex then
                maxIndex = k
            end
            if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
                isArray = false
            end
        end
        if maxIndex ~= count then isArray = false end

        local parts = {}
        if isArray and maxIndex > 0 then
            for i = 1, maxIndex do
                table.insert(parts, serializeValue(v[i]))
            end
            return "{" .. table.concat(parts, ", ") .. "}"
        else
            for k, val in pairs(v) do
                local keyStr
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    keyStr = k
                elseif type(k) == "number" then
                    keyStr = "[" .. tostring(k) .. "]"
                else
                    keyStr = "[" .. serializeValue(k) .. "]"
                end
                table.insert(parts, keyStr .. " = " .. serializeValue(val))
            end
            return "{ " .. table.concat(parts, ", ") .. " }"
        end
    end
    local ok, s = pcall(tostring, v)
    return ok and string.format("%q", s) or "nil"
end

-- ============================================================
-- Парсер
-- ============================================================
local function extractArgs(s, startPos)
    local depth = 0
    local startArgs = nil
    local i = startPos
    while i <= #s do
        local ch = s:sub(i, i)
        if ch == "(" then
            depth = depth + 1
            if depth == 1 then startArgs = i + 1 end
        elseif ch == ")" then
            depth = depth - 1
            if depth == 0 then
                return s:sub(startArgs, i - 1)
            end
        end
        i = i + 1
    end
    return nil
end

local function splitTopLevel(str, sep)
    local parts = {}
    local depth = 0
    local current = ""
    local inString = false
    local stringChar = nil
    for i = 1, #str do
        local ch = str:sub(i, i)
        if inString then
            if ch == "\\" then
                current = current .. ch .. str:sub(i + 1, i + 1)
                i = i + 1
            elseif ch == stringChar then
                inString = false
                current = current .. ch
            else
                current = current .. ch
            end
        else
            if ch == '"' or ch == "'" then
                inString = true
                stringChar = ch
                current = current .. ch
            elseif ch == "(" or ch == "{" or ch == "[" then
                depth = depth + 1
                current = current .. ch
            elseif ch == ")" or ch == "}" or ch == "]" then
                depth = depth - 1
                current = current .. ch
            elseif ch == sep and depth == 0 then
                table.insert(parts, current)
                current = ""
            else
                current = current .. ch
            end
        end
    end
    if current ~= "" then
        table.insert(parts, current)
    end
    return parts
end

local function parseCode(code)
    if not code or code == "" then
        return nil, "Пустой код"
    end

    code = code:gsub("%-%-[^\n]*", "")

    local varName
    for name in code:gmatch("local%s+([%w_]+)%s*=%s*[^\n]*") do
        varName = name
        break
    end

    local method, argsStr, remoteName

    -- firesignal(...)
    if code:find("firesignal%s*%(") then
        local fpos = code:find("firesignal%s*%(")
        local openParen = code:find("(", fpos)
        if openParen then
            local argsFull = extractArgs(code, openParen)
            if argsFull then
                local parts = splitTopLevel(argsFull, ",")
                if #parts >= 1 then
                    local signalExpr = parts[1]:gsub("^%s+", ""):gsub("%s+$", "")
                    local signalVar = signalExpr:match("^([%w_]+)%.")
                    if signalVar then
                        local decl = code:match("local%s+" .. signalVar:gsub("(%W)", "%%%1") .. "%s*=%s*([^\n]+)")
                        if decl then
                            remoteName = decl:match("%.([%w_]+)%s*$")
                        end
                    end
                    method = "FireSignal"
                    local rest = {}
                    for i = 2, #parts do
                        table.insert(rest, parts[i])
                    end
                    argsStr = table.concat(rest, ","):gsub("^%s+", ""):gsub("%s+$", "")
                end
            end
        end
    end

    -- X:Method(...)
    if not method and varName then
        local pattern = varName:gsub("(%W)", "%%%1") .. "%s*:%s*([%w_]+)%s*%("
        local mStart, mEnd = code:find(pattern)
        if mStart then
            local methodName = code:sub(mStart, mEnd):match(":%s*([%w_]+)%s*%(")
            local openParen = code:find("(", mEnd - 1)
            if methodName and openParen then
                local a = extractArgs(code, openParen)
                if a then
                    method = methodName
                    argsStr = a
                end
            end
        end
    end

    if not method then
        return nil, "Не нашёл вызов вида Event:FireServer(...) или firesignal(...)"
    end

    if method ~= "FireSignal" then
        if not remoteName and varName then
            local decl = code:match("local%s+" .. varName:gsub("(%W)", "%%%1") .. "%s*=%s*([^\n]+)")
            if decl then
                remoteName = decl:match("%.([%w_]+)%s*$")
            end
        end
    end
    if not remoteName then remoteName = "*" end

    local argsTbl = {}
    if argsStr and argsStr ~= "" then
        local chunk = "return {" .. argsStr .. "}"
        local fn, err = loadstring(chunk)
        if not fn then
            return nil, "Ошибка в аргументах: " .. tostring(err)
        end
        local ok, res = pcall(fn)
        if not ok then
            return nil, "Ошибка выполнения: " .. tostring(res)
        end
        if type(res) ~= "table" then
            return nil, "Аргументы не дали таблицу"
        end
        argsTbl = res
    end

    return {
        remoteName = remoteName,
        method = getMethodNameFromString(method),
        args = argsTbl,
        argsString = argsStr,
    }
end

-- ============================================================
-- Хук на __namecall
-- ============================================================
local hookInstalled = false
local originalNamecall

do
    local ok, err = pcall(function()
        if not hookmetamethod then error("hookmetamethod недоступен") end
        if not getnamecallmethod then error("getnamecallmethod недоступен") end

        originalNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = { ... }

            if globalEnabled and method then
                local mLower = method:lower()
                if mLower == "fireserver" or mLower == "invokeserver"
                    or mLower == "fire" or mLower == "invoke" then
                    local normMethod
                    if mLower == "fireserver" then normMethod = "FireServer"
                    elseif mLower == "invokeserver" then normMethod = "InvokeServer"
                    elseif mLower == "fire" then normMethod = "Fire"
                    elseif mLower == "invoke" then normMethod = "Invoke"
                    end

                    local instanceName = self and self.Name or "*"
                    for _, hook in pairs(Hooks) do
                        if hook.method ~= "FireSignal"
                            and hookMatches(hook, instanceName, normMethod) then
                            for idx, val in pairs(hook.args or {}) do
                                args[idx] = val
                            end
                        end
                    end
                end
            end

            return originalNamecall(self, unpack(args))
        end))

        hookInstalled = true
    end)

    if not ok then
        warn("[ArgHooker] hookmetamethod failed: " .. tostring(err))
    else
        print("[ArgHooker] hookmetamethod installed OK")
    end
end

-- ============================================================
-- Хук на firesignal
-- ============================================================
local firesignalInstalled = false
local oldFiresignal

do
    local ok, err = pcall(function()
        if not firesignal then error("firesignal недоступен") end

        oldFiresignal = firesignal
        firesignal = function(signal, ...)
            local args = { ... }

            if globalEnabled and signal then
                local remoteName = "*"
                pcall(function()
                    if typeof(signal) == "RBXScriptSignal" then
                        local ok2, name = pcall(function() return signal.Name end)
                        if ok2 and name then remoteName = name end
                    elseif typeof(signal) == "Instance" then
                        remoteName = signal.Name
                    end
                end)

                for _, hook in pairs(Hooks) do
                    if hook.method == "FireSignal" or hook.method == "*" then
                        if hookMatches(hook, remoteName, "FireSignal") then
                            for idx, val in pairs(hook.args or {}) do
                                args[idx] = val
                            end
                        end
                    end
                end
            end

            return oldFiresignal(signal, unpack(args))
        end)

        firesignalInstalled = true
    end)

    if not ok then
        warn("[ArgHooker] firesignal hook failed: " .. tostring(err))
    else
        print("[ArgHooker] firesignal hook installed OK")
    end
end

-- ============================================================
-- GUI
-- ============================================================
local function getGuiParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
end

local function createOwnModal(title, contentHeight)
    contentHeight = contentHeight or 600
    local parent = getGuiParent()

    local screen = Instance.new("ScreenGui")
    screen.Name = "ArgHookerModal"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 999999
    screen.Parent = parent

    local backdrop = Instance.new("Frame")
    backdrop.Size = UDim2.new(1, 0, 1, 0)
    backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    backdrop.BackgroundTransparency = 0.5
    backdrop.BorderSizePixel = 0
    backdrop.Parent = screen

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 640, 0, contentHeight)
    frame.Position = UDim2.new(0.5, -320, 0.5, -contentHeight / 2)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    frame.BorderSizePixel = 0
    frame.Parent = screen

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(60, 60, 70)
    stroke.Thickness = 1
    stroke.Parent = frame

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
    header.BorderSizePixel = 0
    header.Active = true
    header.Parent = frame
    local hCorner = Instance.new("UICorner")
    hCorner.CornerRadius = UDim.new(0, 10)
    hCorner.Parent = header

    do
        local dragging, dragStart, startPos
        header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
            end
        end)
        header.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end)
        header.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
    end

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -60, 1, 0)
    titleLabel.Position = UDim2.new(0, 16, 0, 0)
    titleLabel.Text = title
    titleLabel.TextSize = 16
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Parent = header

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -38, 0, 5)
    closeBtn.Text = "X"
    closeBtn.TextSize = 15
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = header
    local cc = Instance.new("UICorner")
    cc.CornerRadius = UDim.new(0, 6)
    cc.Parent = closeBtn

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -32, 1, -56)
    content.Position = UDim2.new(0, 16, 0, 48)
    content.BackgroundTransparency = 1
    content.Parent = frame

    local function close()
        screen:Destroy()
    end

    closeBtn.MouseButton1Click:Connect(close)

    return { Container = content, Frame = frame, Close = close }
end

local function makeLabel(parent, text, y, size)
    size = size or 12
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.Position = UDim2.new(0, 0, 0, y)
    lbl.Text = text
    lbl.TextSize = size
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextColor3 = Color3.fromRGB(180, 180, 190)
    lbl.BackgroundTransparency = 1
    lbl.Parent = parent
    return lbl
end

local function makeScrollableTextBox(parent, text, y, height)
    height = height or 140

    local wrap = Instance.new("Frame")
    wrap.Size = UDim2.new(1, 0, 0, height)
    wrap.Position = UDim2.new(0, 0, 0, y)
    wrap.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
    wrap.BorderSizePixel = 0
    wrap.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = wrap

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -12, 1, -8)
    scroll.Position = UDim2.new(0, 6, 0, 4)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 8
    scroll.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 110)
    scroll.ScrollingEnabled = true
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = wrap

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -4, 0, 0)
    box.Position = UDim2.new(0, 0, 0, 0)
    box.Text = text or ""
    box.TextSize = 12
    box.Font = Enum.Font.Code
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextYAlignment = Enum.TextYAlignment.Top
    box.TextWrapped = true
    box.MultiLine = true
    box.ClearTextOnFocus = false
    box.BackgroundTransparency = 1
    box.TextColor3 = Color3.fromRGB(230, 230, 240)
    box.BorderSizePixel = 0
    box.Parent = scroll

    local function updateHeight()
        box.Size = UDim2.new(1, -4, 0, math.max(box.TextBounds.Y + 8, scroll.AbsoluteSize.Y))
        scroll.CanvasSize = UDim2.new(0, 0, 0, math.max(box.TextBounds.Y + 16, scroll.AbsoluteSize.Y))
    end

    box:GetPropertyChangedSignal("Text"):Connect(updateHeight)
    scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateHeight)
    updateHeight()

    return box
end

local function makeButton(parent, text, y, color, width, xOff)
    width = width or 1
    xOff = xOff or 0
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(width, width == 1 and 0 or -6, 0, 34)
    btn.Position = UDim2.new(xOff, xOff == 0 and 0 or 6, 0, y)
    btn.Text = text
    btn.TextSize = 13
    btn.Font = Enum.Font.GothamBold
    btn.BackgroundColor3 = color
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.BorderSizePixel = 0
    btn.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn
    return btn
end

local refreshHookListCallback = function() end

local function openHookEditor(prefill)
    prefill = prefill or {}

    local ok, err = pcall(function()
        local modal = createOwnModal("Hook Editor", 620)
        local c = modal.Container

        makeLabel(c, "1) Оригинальный код (что сгенерил Cobalt):", 0)
        local origBox = makeScrollableTextBox(c, prefill.origCode or "", 18, 220)

        makeLabel(c, "2) Изменённый код (то же самое, но с новыми значениями):", 246)
        local modBox = makeScrollableTextBox(c, prefill.modCode or "", 264, 220)

        makeLabel(c,
            "Плагин вытащит имя ремоута, метод и аргументы. Поддержка: FireServer / InvokeServer / Fire / Invoke / firesignal.",
            492)

        local saveBtn = makeButton(c, "Создать и захукать", 520, Color3.fromRGB(60, 140, 60), 0.6, 0)
        local cancelBtn = makeButton(c, "Отмена", 520, Color3.fromRGB(80, 80, 90), 0.4, 0.6)

        cancelBtn.MouseButton1Click:Connect(function()
            modal.Close()
        end)

        saveBtn.MouseButton1Click:Connect(function()
            local orig = parseCode(origBox.Text)
            if not orig then
                toastErr("Ошибка в оригинальном коде")
                return
            end

            local mod = parseCode(modBox.Text)
            if not mod then
                toastErr("Ошибка в изменённом коде")
                return
            end

            if orig.remoteName ~= mod.remoteName then
                toastErr(string.format("Ремоуты не совпадают: %s vs %s", orig.remoteName, mod.remoteName))
                return
            end
            if orig.method ~= mod.method then
                toastErr(string.format("Методы не совпадают: %s vs %s", orig.method, mod.method))
                return
            end

            local hook = {
                id = prefill.id or nextId,
                enabled = true,
                remoteName = mod.remoteName,
                method = mod.method,
                args = mod.args,
                argsString = mod.argsString,
                origArgsString = orig.argsString,
                origCode = origBox.Text,
                modCode = modBox.Text,
            }
            if not prefill.id then nextId = nextId + 1 end

            Hooks[hook.id] = hook
            toastOk(prefill.id and "Хук обновлён" or "Хук создан")
            refreshHookListCallback()
            modal.Close()
        end)
    end)

    if not ok then
        toastErr("Editor error: " .. tostring(err))
        warn("[ArgHooker] openHookEditor failed: " .. tostring(err))
    end
end

local function openHookList()
    local modal = createOwnModal("Мои хуки", 560)
    local c = modal.Container

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 8
    scroll.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 110)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = c

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.Parent = scroll

    local function rebuild()
        for _, child in ipairs(scroll:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end

        for id, hook in pairs(Hooks) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -8, 0, 118)
            row.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
            row.BorderSizePixel = 0
            row.Parent = scroll
            local rc = Instance.new("UICorner")
            rc.CornerRadius = UDim.new(0, 6)
            rc.Parent = row

            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, -12, 0, 50)
            lbl.Position = UDim2.new(0, 6, 0, 4)
            lbl.Text = string.format("[%s] %s\n  было: %s\n  стало: %s",
                hook.method, hook.remoteName,
                (hook.origArgsString or ""):sub(1, 100),
                (hook.argsString or ""):sub(1, 100))
            lbl.TextSize = 11
            lbl.Font = Enum.Font.Code
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextYAlignment = Enum.TextYAlignment.Top
            lbl.TextWrapped = true
            lbl.BackgroundTransparency = 1
            lbl.TextColor3 = Color3.fromRGB(230, 230, 240)
            lbl.Parent = row

            local function makeRowBtn(text, xPos, color, callback)
                local b = Instance.new("TextButton")
                b.Size = UDim2.new(0.24, -4, 0, 26)
                b.Position = UDim2.new(xPos, 2, 0, 58)
                b.Text = text
                b.TextSize = 11
                b.Font = Enum.Font.GothamBold
                b.BackgroundColor3 = color
                b.TextColor3 = Color3.fromRGB(255, 255, 255)
                b.BorderSizePixel = 0
                b.Parent = row
                local bc = Instance.new("UICorner")
                bc.CornerRadius = UDim.new(0, 6)
                bc.Parent = b
                b.MouseButton1Click:Connect(callback)
                return b
            end

            makeRowBtn("Изменить", 0, Color3.fromRGB(60, 90, 160), function()
                modal.Close()
                openHookEditor({
                    id = hook.id,
                    origCode = hook.origCode or "",
                    modCode = hook.modCode or "",
                })
            end)

            makeRowBtn(hook.enabled and "Выкл" or "Вкл", 0.24,
                hook.enabled and Color3.fromRGB(140, 100, 50) or Color3.fromRGB(60, 140, 60),
                function()
                    hook.enabled = not hook.enabled
                    rebuild()
                end)

            makeRowBtn("Скопир.", 0.48, Color3.fromRGB(70, 110, 180), function()
                -- Скопировать только модифицированный код хука как есть
                local text = hook.modCode or ""
                local okCopy = pcall(function()
                    if setclipboard then setclipboard(text) end
                end)
                if okCopy then
                    toastOk("Код скопирован")
                else
                    print("========= HOOK CODE =========")
                    print(text)
                    print("=============================")
                end
            end)

            makeRowBtn("Удалить", 0.72, Color3.fromRGB(140, 50, 50), function()
                Hooks[id] = nil
                rebuild()
            end)
        end
    end

    rebuild()
end

refreshHookListCallback = openHookList

-- ============================================================
-- Context menu
-- ============================================================
local function extractCallInfo(callData)
    local info = { remoteName = "*", method = "FireServer", argsString = "" }
    if not callData then return info end

    local inst = callData.Instance or callData.Remote or callData.instance or callData.Target
    if inst and typeof(inst) == "Instance" then
        info.remoteName = inst.Name
        info.method = getMethodNameFromString(
            callData.Method or callData.method or "FireServer")
    elseif callData.Name then
        info.remoteName = callData.Name
    end

    return info
end

do
    local function handler(callData)
        local info = extractCallInfo(callData)
        local origCode = string.format('%s:FireServer()', info.remoteName)
        local modCode = origCode
        openHookEditor({ origCode = origCode, modCode = modCode })
    end

    local function tryVariants(menuName)
        local variants = {
            { menuName, "Hook (edit args)", "wrench" },
            { "wrench", menuName, "Hook (edit args)" },
            { menuName, "wrench", "Hook (edit args)" },
        }
        for i, v in ipairs(variants) do
            local ok, err = pcall(function()
                Cobalt.UI.ContextMenu.AddOption(v[1], v[2], v[3], handler)
            end)
            print("[ArgHooker] " .. menuName .. " variant " .. i .. ":", ok, err)
            if ok then return true end
        end
        return false
    end

    tryVariants("CallList")
    tryVariants("RemoteList")
end

-- ============================================================
-- Plugin settings
-- ============================================================
do
    local ok, err = pcall(function()
        local section = Cobalt.UI.CreatePluginSettings()
        section:AddLabel("Arg Hooker v5")

        section:CreateCheckbox("Глобально включено", {
            Default = true,
        }, function(v)
            globalEnabled = v and true or false
        end)

        section:CreateButton("Добавить новый хук", function()
            openHookEditor({ origCode = "", modCode = "" })
        end)

        section:CreateButton("Открыть список хуков", function()
            openHookList()
        end)
    end)

    if not ok then
        warn("[ArgHooker] CreatePluginSettings failed: " .. tostring(err))
    else
        print("[ArgHooker] settings registered")
    end
end

-- ============================================================
-- Cleanup
-- ============================================================
pcall(function()
    Cobalt.BindToUnload(function()
        if hookInstalled and originalNamecall and hookmetamethod then
            pcall(function()
                hookmetamethod(game, "__namecall", originalNamecall)
            end)
        end
        if firesignalInstalled and oldFiresignal then
            pcall(function()
                firesignal = oldFiresignal
            end)
        end
        Hooks = {}
    end)
end)

print("[ArgHooker] loaded OK")
