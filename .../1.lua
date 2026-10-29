queueonteleport([[
print("Hello, world!")
]])

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Plr = Players.LocalPlayer
local PlayerGui = Plr:WaitForChild("PlayerGui")
local Char = Plr.Character or Plr.CharacterAdded:Wait()
local PumpkinsFolder = workspace:WaitForChild("MyPumpkins")

local SpawnBikeEvent = ReplicatedStorage:WaitForChild("SpawnBikeEvent")
local RagdollEvent = ReplicatedStorage:WaitForChild("RagdollEvent")

Plr.CharacterAdded:Connect(function(character) Char = character end)

local CONFIG = {
    STEP            = Vector3.new(100, 0, 0),
    START_POS       = Vector3.new(0, 20, 0),
    ROAM_DELAY      = 0.2,
    PUMPKIN_RECHECK = 0.15,
    SEAT_ATTEMPTS   = 4,
    SEAT_WAIT       = 0.35,
}

--------------------------------------------------------------------------------
-- UI (monochrome, sharp corners)
--------------------------------------------------------------------------------
local function createStatusUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "PumpkinFarmerStatus"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = PlayerGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 340, 0, 132)
    frame.Position = UDim2.new(0, 16, 0, 16)
    frame.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(75, 75, 75)
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = frame

    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(0, 3, 1, 0)
    accent.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
    accent.BorderSizePixel = 0
    accent.ZIndex = 2
    accent.Parent = frame

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, -3, 0, 26)
    header.Position = UDim2.new(0, 3, 0, 0)
    header.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
    header.BorderSizePixel = 0
    header.Parent = frame

    local sep = Instance.new("Frame")
    sep.Size = UDim2.new(1, -3, 0, 1)
    sep.Position = UDim2.new(0, 3, 0, 26)
    sep.BackgroundColor3 = Color3.fromRGB(75, 75, 75)
    sep.BorderSizePixel = 0
    sep.ZIndex = 2
    sep.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -70, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.Code
    title.Text = "PUMPKIN_FARMER.EXE"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local ticker = Instance.new("Frame")
    ticker.Size = UDim2.new(0, 44, 0, 10)
    ticker.Position = UDim2.new(1, -56, 0, 8)
    ticker.BackgroundTransparency = 1
    ticker.Parent = header

    local blocks = {}
    for i = 1, 4 do
        local b = Instance.new("Frame")
        b.Size = UDim2.new(0, 8, 0, 10)
        b.Position = UDim2.new(0, (i - 1) * 11, 0, 0)
        b.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
        b.BorderSizePixel = 0
        b.Parent = ticker
        blocks[i] = b
    end

    task.spawn(function()
        local idx = 1
        while gui.Parent do
            for i, b in ipairs(blocks) do
                b.BackgroundColor3 = (i == idx)
                    and Color3.fromRGB(255, 255, 255)
                    or  Color3.fromRGB(55, 55, 55)
            end
            idx = (idx % #blocks) + 1
            task.wait(0.12)
        end
    end)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -22, 1, -38)
    content.Position = UDim2.new(0, 14, 0, 32)
    content.BackgroundTransparency = 1
    content.Parent = frame

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 2)
    layout.Parent = content

    local statusHeader = Instance.new("TextLabel")
    statusHeader.Size = UDim2.new(1, 0, 0, 12)
    statusHeader.BackgroundTransparency = 1
    statusHeader.Font = Enum.Font.Code
    statusHeader.Text = "STATUS"
    statusHeader.TextColor3 = Color3.fromRGB(115, 115, 115)
    statusHeader.TextSize = 10
    statusHeader.TextXAlignment = Enum.TextXAlignment.Left
    statusHeader.LayoutOrder = 1
    statusHeader.Parent = content

    local statusValue = Instance.new("TextLabel")
    statusValue.Size = UDim2.new(1, 0, 0, 18)
    statusValue.BackgroundTransparency = 1
    statusValue.Font = Enum.Font.Code
    statusValue.Text = "> initializing"
    statusValue.TextColor3 = Color3.fromRGB(255, 255, 255)
    statusValue.TextSize = 14
    statusValue.TextXAlignment = Enum.TextXAlignment.Left
    statusValue.LayoutOrder = 2
    statusValue.Parent = content

    local infoValue = Instance.new("TextLabel")
    infoValue.Size = UDim2.new(1, 0, 0, 14)
    infoValue.BackgroundTransparency = 1
    infoValue.Font = Enum.Font.Code
    infoValue.Text = ""
    infoValue.TextColor3 = Color3.fromRGB(160, 160, 160)
    infoValue.TextSize = 11
    infoValue.TextXAlignment = Enum.TextXAlignment.Left
    infoValue.LayoutOrder = 3
    infoValue.Parent = content

    local statsValue = Instance.new("TextLabel")
    statsValue.Size = UDim2.new(1, 0, 0, 14)
    statsValue.BackgroundTransparency = 1
    statsValue.Font = Enum.Font.Code
    statsValue.Text = "COLLECTED: 0  |  CHUNKS: 0"
    statsValue.TextColor3 = Color3.fromRGB(215, 215, 215)
    statsValue.TextSize = 11
    statsValue.TextXAlignment = Enum.TextXAlignment.Left
    statsValue.LayoutOrder = 4
    statsValue.Parent = content

    local api = {}
    api.gui = gui
    api._statusText = "initializing"

    function api.setStatus(text)
        if text ~= api._statusText then
            api._statusText = text
            statusValue.Text = "> " .. text
        end
    end
    function api.setInfo(text) infoValue.Text = text end
    function api.setStats(text) statsValue.Text = text end

    return api
end

local UI = createStatusUI()
local session = { collected = 0, chunks = 0 }
local function refreshStats()
    UI.setStats(string.format("COLLECTED: %d  |  CHUNKS: %d",
        session.collected, session.chunks))
end
refreshStats()

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function findMyChassis()
    local prefix = Plr.Name .. "'s "
    for _, vehicle in ipairs(workspace:GetChildren()) do
        if vehicle:IsA("Model") and vehicle.Name:sub(1, #prefix) == prefix then
            local chassis = vehicle:FindFirstChild("Chassis")
            if chassis then return chassis end
        end
    end
    return nil
end

local function spawnVehicle() SpawnBikeEvent:FireServer() end

local function stopRagdoll()
    local c = Char
    if not c or not c:GetAttribute("Ragdolled") then return end
    RagdollEvent:FireServer(false)
    local root = c:FindFirstChild("HumanoidRootPart")
    if root then root.AssemblyLinearVelocity = Vector3.zero end
end

local function getRidePrompt(vehicle)
    if not vehicle then return nil end
    return vehicle:FindFirstChild("RidePrompt", true)
end

local function hasPumpkins()
    for _, p in ipairs(PumpkinsFolder:GetChildren()) do
        if p:IsA("Model") and p:FindFirstChildOfClass("MeshPart") then
            return true
        end
    end
    return false
end

local function countPumpkins()
    local n = 0
    for _, p in ipairs(PumpkinsFolder:GetChildren()) do
        if p:IsA("Model") and p:FindFirstChildOfClass("MeshPart") then
            n = n + 1
        end
    end
    return n
end

-- Returns the position we're currently "controlling":
-- the chassis if we're seated, otherwise the HumanoidRootPart.
local function getCurrentPosition()
    local c = Char
    if not c then return nil end
    local humanoid = c:FindFirstChildOfClass("Humanoid")
    local root = c:FindFirstChild("HumanoidRootPart")
    local chassis = findMyChassis()

    if humanoid and humanoid.SeatPart and chassis and chassis.Parent then
        return chassis.Position
    end
    return root and root.Position or nil
end

local function teleportTo(cf)
    local c = Char
    if not c then return end
    local humanoid = c:FindFirstChildOfClass("Humanoid")
    local root = c:FindFirstChild("HumanoidRootPart")
    local chassis = findMyChassis()

    if humanoid and humanoid.SeatPart and chassis and chassis.Parent then
        chassis.AssemblyLinearVelocity = Vector3.zero
        chassis.CFrame = cf
    elseif root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = cf
    end
end

--------------------------------------------------------------------------------
-- Seating (robust)
--------------------------------------------------------------------------------
local function trySeat(chassis, seat)
    local c = Char
    if not c then return false end
    local humanoid = c:FindFirstChildOfClass("Humanoid")
    local root = c:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return false end
    if humanoid.SeatPart == seat then return true end

    if humanoid.SeatPart and humanoid.SeatPart ~= seat then
        pcall(function() humanoid.Sit = false; humanoid.Jump = true end)
        task.wait(0.25)
    end

    local bike = chassis.Parent
    local prompt = getRidePrompt(bike)

    if prompt then
        root.CFrame = seat.CFrame * CFrame.new(0, 2, 3)
        task.wait(0.15)
        pcall(function() fireproximityprompt(prompt) end)
        task.wait(CONFIG.SEAT_WAIT)
        if humanoid.SeatPart == seat then return true end
        pcall(function()
            prompt:InputHoldBegin()
            task.wait(0.15)
            prompt:InputHoldEnd()
        end)
        task.wait(CONFIG.SEAT_WAIT)
        if humanoid.SeatPart == seat then return true end
    end

    root.CFrame = seat.CFrame * CFrame.new(0, 2, 0)
    task.wait(CONFIG.SEAT_WAIT)
    if humanoid.SeatPart == seat then return true end

    if prompt then
        pcall(function() fireproximityprompt(prompt) end)
        task.wait(CONFIG.SEAT_WAIT)
        if humanoid.SeatPart == seat then return true end
    end

    pcall(function() humanoid.Sit = true end)
    task.wait(CONFIG.SEAT_WAIT)
    if humanoid.SeatPart == seat then return true end

    return false
end

local function ensureOnBike()
    local c = Char
    if not c then return nil end
    local humanoid = c:FindFirstChildOfClass("Humanoid")
    local root = c:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return nil end

    UI.setStatus("finding bike")
    local chassis = findMyChassis()

    if not chassis then
        UI.setStatus("spawning bike")
        spawnVehicle()
        for _ = 1, 40 do
            task.wait(0.1)
            chassis = findMyChassis()
            if chassis then break end
        end
    end

    if not chassis then
        UI.setStatus("bike not found")
        return nil
    end

    local bike = chassis.Parent
    local seat = bike and bike:FindFirstChild("DriverSeat", true)
    if not seat then
        UI.setStatus("driver seat missing")
        return nil
    end

    if humanoid.SeatPart == seat then return chassis end

    for attempt = 1, CONFIG.SEAT_ATTEMPTS do
        UI.setStatus(string.format("getting on bike %d/%d", attempt, CONFIG.SEAT_ATTEMPTS))
        if trySeat(chassis, seat) then
            UI.setStatus("seated")
            return chassis
        end
        task.wait(0.2)
    end

    UI.setStatus("couldn't seat - will retry")
    return nil
end

--------------------------------------------------------------------------------
-- Linear scan (reads ACTUAL current position each hop)
--------------------------------------------------------------------------------
local function roamForPumpkins()
    -- Read the real current position each call, not a cached value.
    local current = getCurrentPosition()

    local target
    if current == nil then
        -- No character/bike available yet — fall back to start pos.
        target = CONFIG.START_POS
    elseif current.Magnitude == 0 then
        -- Sitting exactly at the origin on the very first call.
        target = CONFIG.START_POS
    else
        -- Round to whole studs so tiny physics nudges don't accumulate drift,
        -- then step forward from wherever we actually are.
        local rounded = Vector3.new(
            math.floor(current.X + 0.5),
            math.floor(current.Y + 0.5),
            math.floor(current.Z + 0.5)
        )
        target = rounded + CONFIG.STEP
    end

    session.chunks = session.chunks + 1
    refreshStats()

    teleportTo(CFrame.new(target))

    UI.setStatus("scanning for pumpkins")
    UI.setInfo(string.format("from (%.0f,%.0f,%.0f) -> (%.0f,%.0f,%.0f)",
        current and current.X or 0, current and current.Y or 0, current and current.Z or 0,
        target.X, target.Y, target.Z))

    task.wait(CONFIG.ROAM_DELAY)

    if hasPumpkins() then
        task.wait(CONFIG.PUMPKIN_RECHECK)
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Collect
--------------------------------------------------------------------------------
local function collect()
    local list = {}
    for _, p in ipairs(PumpkinsFolder:GetChildren()) do
        if p:IsA("Model") and p:FindFirstChildOfClass("MeshPart") then
            list[#list + 1] = p
        end
    end
    local total = #list

    for i, pumpkin in ipairs(list) do
        if not pumpkin.Parent then continue end
        local mesh = pumpkin:FindFirstChildOfClass("MeshPart")
        if not mesh then continue end

        local c = Char
        local root = c and c:FindFirstChild("HumanoidRootPart")
        local humanoid = c and c:FindFirstChildOfClass("Humanoid")
        if not root or not humanoid then continue end

        UI.setStatus("collecting pumpkin")
        UI.setInfo(string.format("%d/%d", i, total))

        local chassis = ensureOnBike()
        if not chassis or not chassis.Parent then continue end

        local seat = chassis.Parent:FindFirstChild("DriverSeat", true)
        local targetCF = mesh.CFrame * CFrame.new(0, 5, 10)
        if seat and humanoid.SeatPart == seat then
            chassis.CFrame = targetCF
        else
            root.CFrame = targetCF
        end

        task.wait(0.15)

        if seat and humanoid.SeatPart ~= seat then
            UI.setStatus("re-seating")
            ensureOnBike()
        end
        if seat and humanoid.SeatPart ~= seat then
            UI.setStatus("seat lost - skipping")
            task.wait(0.2)
            continue
        end

        chassis.AssemblyLinearVelocity = chassis.CFrame.LookVector * 15
        task.wait(0.5)
        if chassis.Parent then
            chassis.AssemblyLinearVelocity = Vector3.zero
        end

        session.collected = session.collected + 1
        refreshStats()
        task.wait(0.2)
    end
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------
local function mainLoop()
    while true do
        local n = countPumpkins()
        if n > 0 then
            UI.setStatus("pumpkins detected")
            UI.setInfo(string.format("%d visible", n))
            task.wait(0.1)
            collect()
        else
            roamForPumpkins()
        end
        task.wait(0.1)
    end
end

--RunService.RenderStepped:Connect(stopRagdoll)

mainLoop()
