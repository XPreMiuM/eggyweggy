local Players               = game:GetService("Players")
local PathfindingService    = game:GetService("PathfindingService")
local UIS                   = game:GetService("UserInputService")
local VIM                   = game:GetService("VirtualInputManager")
local HttpService           = game:GetService("HttpService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RAW_SCRIPT_URL = "https://raw.githubusercontent.com/XPreMiuM/eggyweggy/refs/heads/main/testary-hym.lua"
local CONFIG_FILE    = "eggbot_config.json"

local PATH_PARAMS = {
    AgentHeight     = 2,
    AgentRadius     = 2,
    AgentCanJump    = true,
    AgentJumpHeight = 35,
    WaypointSpacing = shared.spacing or 3,
}

local REACH_DIST           = 4.5
local WAYPOINT_TIMEOUT     = 4
local JUMP_COOLDOWN        = 0.2
local MAX_PATH_ATTEMPTS    = 5
local WALK_HARD_TIMEOUT    = 90
local QUEUE_COOLDOWN       = 0.2
local RESCAN_INTERVAL      = 5

local EGG_COLORS = {
    [1] = Color3.fromRGB(255, 255, 255),
    [2] = Color3.fromRGB(0,   255, 0),
    [3] = Color3.fromRGB(0,   170, 255),
    [4] = Color3.fromRGB(170, 0,   255),
    [5] = Color3.fromRGB(255, 170, 0),
    [6] = Color3.fromRGB(255, 0,   0),
}
local JUMP_COLOR     = Color3.fromRGB(255, 100, 0)
local POTION_COLOR   = Color3.fromRGB(170, 0,   255)
local DEFAULT_COLOR  = Color3.new(1, 1, 1)

local function cloneTable(t)
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            out[k] = cloneTable(v)
        else
            out[k] = v
        end
    end
    return out
end

local DEFAULT_CONFIG = {
    farmEnabled = false,
    autoExecEnabled = false,
    autoRefreshEnabled = false,
    refreshMinutes = 20,
    jumpInterval = 30,
    repeatInterval = 10,
    webhookUrl = "",
    stats = {
        scriptStarts = 0,
        autoExecCount = 0,
        rejoinCount = 0,
        softRefreshCount = 0,
    },
    runtime = {
        lastJobId = "",
        lastPlaceId = 0,
        lastStartUnix = 0,
    }
}

local function deepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            deepMerge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function loadConfig()
    local cfg = cloneTable(DEFAULT_CONFIG)

    local okFile, exists = pcall(function()
        return isfile and isfile(CONFIG_FILE)
    end)

    if okFile and exists and readfile then
        local okRead, contents = pcall(function()
            return readfile(CONFIG_FILE)
        end)

        if okRead and contents and contents ~= "" then
            local okJson, decoded = pcall(function()
                return HttpService:JSONDecode(contents)
            end)

            if okJson and type(decoded) == "table" then
                deepMerge(decoded, DEFAULT_CONFIG)
                cfg = decoded
            end
        end
    end

    return cfg
end

local config = loadConfig()

local function saveConfig()
    if not writefile then
        return
    end

    pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(config))
    end)
end

config.stats.scriptStarts += 1

if config.runtime.lastJobId ~= "" and config.runtime.lastJobId ~= game.JobId then
    config.stats.autoExecCount += 1
    config.stats.rejoinCount += 1
end

config.runtime.lastJobId = game.JobId
config.runtime.lastPlaceId = game.PlaceId
config.runtime.lastStartUnix = os.time()
saveConfig()

local farmEnabled        = config.farmEnabled
local isWalking          = false
local eggQueue           = {}
local queuedIds          = {}
local trackedEggs        = {}
local lastMoveTick       = tick()
local autoExecEnabled    = config.autoExecEnabled
local autoRefreshEnabled = config.autoRefreshEnabled
local refreshMinutes     = tonumber(config.refreshMinutes) or 20

-- anti afk
local antiAfkEnabled = true
local jumpInterval = tonumber(config.jumpInterval) or 30

-- recorder
local recordedInputs = {}
local isRecording = false
local isPlayingRecording = false
local repeatRecording = false
local repeatInterval = tonumber(config.repeatInterval) or 10
local recordStartTime = 0

shared.toggled = farmEnabled
shared.autoExecEnabled = autoExecEnabled

local function syncConfig()
    config.farmEnabled = farmEnabled
    config.autoExecEnabled = autoExecEnabled
    config.autoRefreshEnabled = autoRefreshEnabled
    config.refreshMinutes = refreshMinutes
    config.jumpInterval = jumpInterval
    config.repeatInterval = repeatInterval
    shared.toggled = farmEnabled
    shared.autoExecEnabled = autoExecEnabled
    saveConfig()
end

local function isAlive(inst)
    return inst ~= nil and inst.Parent ~= nil
end

local function safeGet(fn)
    local ok, val = pcall(fn)
    return ok and val or nil
end

local function getChar()
    return player.Character
end

local function getHum(c)
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getRoot(c)
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function resolvePos(inst)
    if not isAlive(inst) then return nil end
    return safeGet(function()
        if inst:IsA("BasePart") then
            return inst.Position
        end
        if inst:IsA("Model") then
            if inst.PrimaryPart then
                return inst.PrimaryPart.Position
            end
            local bp = inst:FindFirstChildWhichIsA("BasePart", true)
            return bp and bp.Position
        end
    end)
end

local function buildUid(v)
    return v.Name .. "_" .. tostring(v)
end

local function classifyEgg(v)
    if not v or not (v:IsA("Model") or v:IsA("BasePart")) then
        return nil
    end

    local name = v.Name
    local eggNum = tonumber(string.match(name, "egg_(%d+)$"))
    local isPotion = string.find(name, "potion", 1, true) ~= nil

    if eggNum then
        return {
            color = EGG_COLORS[eggNum] or DEFAULT_COLOR,
            priority = eggNum
        }
    end

    if isPotion then
        return {
            color = POTION_COLOR,
            priority = 0
        }
    end

    return nil
end

local function getDistanceToTarget(target)
    local root = getRoot(getChar())
    local pos = resolvePos(target)

    if not root or not pos then
        return math.huge
    end

    return (root.Position - pos).Magnitude
end

local function sortQueue()
    table.sort(eggQueue, function(a, b)
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end

        local da = getDistanceToTarget(a.target)
        local db = getDistanceToTarget(b.target)

        if math.abs(da - db) > 8 then
            return da < db
        end

        return a.firstSeen < b.firstSeen
    end)
end

local function makePathFolder(waypoints, eggColor)
    local folder = Instance.new("Folder")
    folder.Name  = "ActivePath"

    pcall(function()
        for _, wp in ipairs(waypoints) do
            local p      = Instance.new("Part")
            p.Shape      = Enum.PartType.Ball
            p.Size       = Vector3.new(0.6, 0.6, 0.6)
            p.Position   = wp.Position
            p.Anchored   = true
            p.CanCollide = false
            p.CastShadow = false
            p.Material   = Enum.Material.Neon
            p.Color      = (wp.Action == Enum.PathWaypointAction.Jump) and JUMP_COLOR or eggColor
            p.Name       = "PathBall"
            p.Parent     = folder
        end
    end)

    folder.Parent = workspace

    local function cleanup()
        task.spawn(function()
            pcall(function()
                if folder.Parent then
                    folder:Destroy()
                end
            end)
        end)
    end

    return folder, cleanup
end

local function doJump(hum)
    if hum and hum:GetState() ~= Enum.HumanoidStateType.Jumping and hum:GetState() ~= Enum.HumanoidStateType.Freefall then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

local function buildRayParams(char)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Blacklist

    local ignore = {char}
    local activePath = workspace:FindFirstChild("ActivePath")
    if activePath then
        table.insert(ignore, activePath)
    end

    rp.FilterDescendantsInstances = ignore
    return rp
end

local function stepToWaypoint(hum, root, wp)
    if not hum or not root then return "fail" end

    local char = root.Parent
    hum:MoveTo(wp.Position)

    local result       = nil
    local startT       = tick()
    local lastJumpTime = 0
    local lastPos      = root.Position
    local lastPosTime  = tick()
    local stuckCount   = 0
    local PROGRESS_CHECK_INTERVAL = 0.6
    local MIN_PROGRESS = 0.8

    local moveConn = hum.MoveToFinished:Connect(function(reached)
        if result == nil then
            result = reached and "reached" or "timeout"
        end
    end)

    while result == nil do
        task.wait()

        if not farmEnabled then
            result = "stopped"
            break
        end

        if tick() - startT > WAYPOINT_TIMEOUT then
            result = "timeout"
            break
        end

        local dist = (root.Position - wp.Position).Magnitude
        if dist < REACH_DIST then
            result = "reached"
            lastMoveTick = tick()
            break
        end

        local now = tick()

        if now - lastPosTime > PROGRESS_CHECK_INTERVAL then
            local moved = (root.Position - lastPos).Magnitude

            if moved < MIN_PROGRESS then
                stuckCount += 1

                local dir = (wp.Position - root.Position)
                local flatDir = Vector3.new(dir.X, 0, dir.Z)
                if flatDir.Magnitude > 0 then
                    flatDir = flatDir.Unit
                end

                local rayParams = buildRayParams(char)
                local frontRay = nil
                if flatDir.Magnitude > 0 then
                    frontRay = workspace:Raycast(root.Position, flatDir * 3, rayParams)
                end
                local ceilingRay = workspace:Raycast(root.Position, Vector3.new(0, 3.5, 0), rayParams)

                if stuckCount >= 3 then
                    result = "timeout"
                    break
                end

                if frontRay and not ceilingRay and (now - lastJumpTime) > JUMP_COOLDOWN then
                    lastJumpTime = now
                    doJump(hum)
                    hum:MoveTo(wp.Position)

                elseif frontRay then
                    if flatDir.Magnitude > 0 then
                        local side = (math.random(0, 1) == 0) and -1 or 1
                        local sidestep = root.CFrame.RightVector * side * 3
                        local sidestepTarget = root.Position + sidestep
                        hum:MoveTo(sidestepTarget)
                        task.wait(0.3)

                        local backTarget = root.Position - flatDir * 2
                        hum:MoveTo(backTarget)
                        task.wait(0.35)
                    end
                    hum:MoveTo(wp.Position)

                elseif (now - lastJumpTime) > JUMP_COOLDOWN then
                    lastJumpTime = now
                    doJump(hum)
                    hum:MoveTo(wp.Position)
                end
            else
                stuckCount = 0
            end

            lastPos     = root.Position
            lastPosTime = now
        end
    end

    moveConn:Disconnect()
    return result
end

local function walkToEgg(targetInstance, eggColor)
    local char = getChar()
    local hum = getHum(char)
    local root = getRoot(char)

    if not hum or not root then
        return "fail"
    end

    for attempt = 1, MAX_PATH_ATTEMPTS do
        if not farmEnabled then
            return "stopped"
        end

        local targetPos = resolvePos(targetInstance)
        if not targetPos then
            return "done"
        end

        local path = PathfindingService:CreatePath(PATH_PARAMS)
        local ok = pcall(function()
            path:ComputeAsync(root.Position, targetPos)
        end)

        if not ok or path.Status ~= Enum.PathStatus.Success then
            task.wait(0.2)
            continue
        end

        local waypoints = path:GetWaypoints()
        local pathFolder, cleanup = makePathFolder(waypoints, eggColor)
        local pathBroken = false

        for i, wp in ipairs(waypoints) do
            if not farmEnabled or not isAlive(targetInstance) then
                pathBroken = true
                break
            end

            local needsJump = wp.Action == Enum.PathWaypointAction.Jump
            if not needsJump and i < #waypoints then
                if (waypoints[i + 1].Position.Y - root.Position.Y) > 0.8 then
                    needsJump = true
                end
            end

            if needsJump then
                doJump(hum)
            end

            local stepResult = stepToWaypoint(hum, root, wp)

            if stepResult == "timeout" or stepResult == "fail" or stepResult == "stopped" then
                pathBroken = true
                break
            end
        end

        cleanup()

        if not farmEnabled then
            return "stopped"
        end

        if pathBroken then
            task.wait(0.2)
            continue
        end

        if isAlive(targetInstance) then
            for _, v in ipairs(targetInstance:GetDescendants()) do
                if v:IsA("ProximityPrompt") then
                    task.wait(0.5)
                    fireproximityprompt(v)
                end
            end
        end

        task.wait(0.1)
        return "done"
    end

    return "fail"
end

local function pruneTrackedEggs()
    for uid, data in pairs(trackedEggs) do
        if not isAlive(data.target) then
            trackedEggs[uid] = nil
            queuedIds[uid] = nil
        end
    end
end

local function pruneQueue()
    local alive = {}
    for _, e in ipairs(eggQueue) do
        if isAlive(e.target) then
            table.insert(alive, e)
        else
            queuedIds[e.id] = nil
            trackedEggs[e.id] = nil
        end
    end
    eggQueue = alive
    sortQueue()
end

local function queueEgg(v)
    local info = classifyEgg(v)
    if not info then return end
    if not isAlive(v) then return end

    local uid = buildUid(v)
    if trackedEggs[uid] then return end

    local data = {
        target = v,
        color = info.color,
        id = uid,
        firstSeen = tick(),
        priority = info.priority,
    }

    trackedEggs[uid] = data

    if not queuedIds[uid] then
        queuedIds[uid] = true
        table.insert(eggQueue, data)
        sortQueue()
    end
end

local function scanAllEggs()
    pruneTrackedEggs()
    pruneQueue()

    for _, v in ipairs(workspace:GetDescendants()) do
        queueEgg(v)
    end

    sortQueue()
end

local function releaseWalking()
    isWalking = false
end

local function processQueue()
    if not farmEnabled or isWalking or #eggQueue == 0 then return end
    isWalking = true

    task.spawn(function()
        local hardTimer = task.delay(WALK_HARD_TIMEOUT, function()
            releaseWalking()
        end)

        pruneQueue()
        sortQueue()

        local data = table.remove(eggQueue, 1)

        if data then
            queuedIds[data.id] = nil

            if isAlive(data.target) and farmEnabled then
                local result = walkToEgg(data.target, data.color)

                if result == "done" or not isAlive(data.target) then
                    trackedEggs[data.id] = nil
                else
                    if isAlive(data.target) then
                        if not queuedIds[data.id] then
                            queuedIds[data.id] = true
                            data.firstSeen = data.firstSeen or tick()
                            table.insert(eggQueue, data)
                            sortQueue()
                        end
                    else
                        trackedEggs[data.id] = nil
                    end
                end
            else
                trackedEggs[data.id] = nil
            end
        end

        task.cancel(hardTimer)
        releaseWalking()

        if farmEnabled then
            task.wait(QUEUE_COOLDOWN)
            processQueue()
        end
    end)
end

local function onPossibleEgg(v)
    task.spawn(function()
        task.wait(0.05)
        queueEgg(v)
        if farmEnabled then
            processQueue()
        end
    end)
end

local function getRequestFunc()
    return request
        or http_request
        or (syn and syn.request)
        or (fluxus and fluxus.request)
end

local function sendWebhookMessage(message)
    local webhookUrl = tostring(config.webhookUrl or "")
    if webhookUrl == "" then
        return
    end

    local req = getRequestFunc()
    if not req then
        return
    end

    task.spawn(function()
        pcall(function()
            req({
                Url = webhookUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = HttpService:JSONEncode({
                    content = message
                })
            })
        end)
    end)
end

local function buildStatusText(reason)
    return string.format(
        "**EggBot status**\nReason: %s\nPlayer: %s\nPlaceId: %s\nJobId: %s\nFarm: %s\nAutoExec: %s\nAutoRefresh: %s\nRefreshMinutes: %s\nScriptStarts: %s\nAutoExecCount: %s\nRejoinCount: %s\nSoftRefreshCount: %s",
        reason,
        tostring(player.Name),
        tostring(game.PlaceId),
        tostring(game.JobId),
        farmEnabled and "ON" or "OFF",
        autoExecEnabled and "ON" or "OFF",
        autoRefreshEnabled and "ON" or "OFF",
        tostring(refreshMinutes),
        tostring(config.stats.scriptStarts),
        tostring(config.stats.autoExecCount),
        tostring(config.stats.rejoinCount),
        tostring(config.stats.softRefreshCount)
    )
end

local function setupAutoExec()
    if not autoExecEnabled then
        return
    end

    if RAW_SCRIPT_URL == "" or RAW_SCRIPT_URL == "PASTE_YOUR_RAW_GITHUB_LINK_HERE" then
        warn("[EggBot] RAW_SCRIPT_URL not set")
        return
    end

    local qot = queue_on_teleport
        or queueonteleport
        or (syn and syn.queue_on_teleport)

    if qot then
        qot(string.format('loadstring(game:HttpGet("%s"))()', RAW_SCRIPT_URL))
    else
        warn("[EggBot] queue_on_teleport not available")
    end
end

local function softRefreshMacro()
    isWalking = false

    eggQueue = {}
    queuedIds = {}
    trackedEggs = {}

    local activePath = workspace:FindFirstChild("ActivePath")
    if activePath then
        pcall(function()
            activePath:Destroy()
        end)
    end

    scanAllEggs()

    if farmEnabled then
        task.wait(0.2)
        processQueue()
    end
end

-- recorder
local allowedKeys = {
    [Enum.KeyCode.W] = true,
    [Enum.KeyCode.A] = true,
    [Enum.KeyCode.S] = true,
    [Enum.KeyCode.D] = true,
    [Enum.KeyCode.Space] = true,
}

local function startRecording()
    recordedInputs = {}
    isRecording = true
    recordStartTime = tick()
end

local function stopRecording()
    isRecording = false
end

local function playRecording()
    if #recordedInputs == 0 then
        warn("No recording saved")
        return
    end

    if isPlayingRecording then
        return
    end

    isPlayingRecording = true

    task.spawn(function()
        local playStart = tick()

        for _, ev in ipairs(recordedInputs) do
            local targetTime = ev.t / 1000
            local now = tick() - playStart
            local waitTime = targetTime - now

            if waitTime > 0 then
                task.wait(waitTime)
            end

            local isDown = (ev.state == "begin")
            VIM:SendKeyEvent(isDown, ev.key, false, game)
        end

        isPlayingRecording = false
    end)
end

UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if not isRecording then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if not allowedKeys[input.KeyCode] then return end

    table.insert(recordedInputs, {
        t = math.floor((tick() - recordStartTime) * 1000),
        key = input.KeyCode,
        state = "begin"
    })
end)

UIS.InputEnded:Connect(function(input, gameProcessed)
    if not isRecording then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if not allowedKeys[input.KeyCode] then return end

    table.insert(recordedInputs, {
        t = math.floor((tick() - recordStartTime) * 1000),
        key = input.KeyCode,
        state = "end"
    })
end)

-- UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EggBotUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 320, 0, 610)
frame.Position = UDim2.new(0, 20, 0, 120)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.Position = UDim2.new(0, 0, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Egg Macro"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Font = Enum.Font.SourceSansBold
title.Parent = frame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0, 280, 0, 35)
toggleButton.Position = UDim2.new(0, 20, 0, 40)
toggleButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Font = Enum.Font.SourceSansBold
toggleButton.TextScaled = true
toggleButton.Text = farmEnabled and "Macro: ON" or "Macro: OFF"
toggleButton.Parent = frame

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

local jumpLabel = Instance.new("TextLabel")
jumpLabel.Size = UDim2.new(0, 280, 0, 20)
jumpLabel.Position = UDim2.new(0, 20, 0, 85)
jumpLabel.BackgroundTransparency = 1
jumpLabel.Text = "Jump every X seconds:"
jumpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
jumpLabel.Font = Enum.Font.SourceSans
jumpLabel.TextScaled = true
jumpLabel.Parent = frame

local jumpBox = Instance.new("TextBox")
jumpBox.Size = UDim2.new(0, 280, 0, 28)
jumpBox.Position = UDim2.new(0, 20, 0, 108)
jumpBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
jumpBox.TextColor3 = Color3.fromRGB(255, 255, 255)
jumpBox.PlaceholderText = "Enter seconds"
jumpBox.Text = tostring(jumpInterval)
jumpBox.Font = Enum.Font.SourceSans
jumpBox.TextScaled = true
jumpBox.ClearTextOnFocus = false
jumpBox.Parent = frame

local jumpCorner = Instance.new("UICorner")
jumpCorner.CornerRadius = UDim.new(0, 8)
jumpCorner.Parent = jumpBox

local recordButton = Instance.new("TextButton")
recordButton.Size = UDim2.new(0, 135, 0, 35)
recordButton.Position = UDim2.new(0, 20, 0, 148)
recordButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
recordButton.TextColor3 = Color3.fromRGB(255, 255, 255)
recordButton.Font = Enum.Font.SourceSansBold
recordButton.TextScaled = true
recordButton.Text = "Record: OFF"
recordButton.Parent = frame

local recordCorner = Instance.new("UICorner")
recordCorner.CornerRadius = UDim.new(0, 8)
recordCorner.Parent = recordButton

local testButton = Instance.new("TextButton")
testButton.Size = UDim2.new(0, 135, 0, 35)
testButton.Position = UDim2.new(0, 165, 0, 148)
testButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
testButton.TextColor3 = Color3.fromRGB(255, 255, 255)
testButton.Font = Enum.Font.SourceSansBold
testButton.TextScaled = true
testButton.Text = "Test Recording"
testButton.Parent = frame

local testCorner = Instance.new("UICorner")
testCorner.CornerRadius = UDim.new(0, 8)
testCorner.Parent = testButton

local repeatLabel = Instance.new("TextLabel")
repeatLabel.Size = UDim2.new(0, 280, 0, 20)
repeatLabel.Position = UDim2.new(0, 20, 0, 194)
repeatLabel.BackgroundTransparency = 1
repeatLabel.Text = "Run recording every X seconds:"
repeatLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
repeatLabel.Font = Enum.Font.SourceSans
repeatLabel.TextScaled = true
repeatLabel.Parent = frame

local repeatBox = Instance.new("TextBox")
repeatBox.Size = UDim2.new(0, 280, 0, 28)
repeatBox.Position = UDim2.new(0, 20, 0, 217)
repeatBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
repeatBox.TextColor3 = Color3.fromRGB(255, 255, 255)
repeatBox.PlaceholderText = "Enter seconds"
repeatBox.Text = tostring(repeatInterval)
repeatBox.Font = Enum.Font.SourceSans
repeatBox.TextScaled = true
repeatBox.ClearTextOnFocus = false
repeatBox.Parent = frame

local repeatCorner = Instance.new("UICorner")
repeatCorner.CornerRadius = UDim.new(0, 8)
repeatCorner.Parent = repeatBox

local repeatToggle = Instance.new("TextButton")
repeatToggle.Size = UDim2.new(0, 280, 0, 35)
repeatToggle.Position = UDim2.new(0, 20, 0, 258)
repeatToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
repeatToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
repeatToggle.Font = Enum.Font.SourceSansBold
repeatToggle.TextScaled = true
repeatToggle.Text = "Recorder Loop: OFF"
repeatToggle.Parent = frame

local repeatToggleCorner = Instance.new("UICorner")
repeatToggleCorner.CornerRadius = UDim.new(0, 8)
repeatToggleCorner.Parent = repeatToggle

local autoExecButton = Instance.new("TextButton")
autoExecButton.Size = UDim2.new(0, 280, 0, 35)
autoExecButton.Position = UDim2.new(0, 20, 0, 304)
autoExecButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
autoExecButton.TextColor3 = Color3.fromRGB(255, 255, 255)
autoExecButton.Font = Enum.Font.SourceSansBold
autoExecButton.TextScaled = true
autoExecButton.Text = autoExecEnabled and "Auto Exec: ON" or "Auto Exec: OFF"
autoExecButton.Parent = frame

local autoExecCorner = Instance.new("UICorner")
autoExecCorner.CornerRadius = UDim.new(0, 8)
autoExecCorner.Parent = autoExecButton

local autoRefreshButton = Instance.new("TextButton")
autoRefreshButton.Size = UDim2.new(0, 280, 0, 35)
autoRefreshButton.Position = UDim2.new(0, 20, 0, 350)
autoRefreshButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
autoRefreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
autoRefreshButton.Font = Enum.Font.SourceSansBold
autoRefreshButton.TextScaled = true
autoRefreshButton.Text = autoRefreshEnabled and "Soft Refresh: ON" or "Soft Refresh: OFF"
autoRefreshButton.Parent = frame

local autoRefreshCorner = Instance.new("UICorner")
autoRefreshCorner.CornerRadius = UDim.new(0, 8)
autoRefreshCorner.Parent = autoRefreshButton

local refreshLabel = Instance.new("TextLabel")
refreshLabel.Size = UDim2.new(0, 280, 0, 20)
refreshLabel.Position = UDim2.new(0, 20, 0, 395)
refreshLabel.BackgroundTransparency = 1
refreshLabel.Text = "Soft refresh every X minutes:"
refreshLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshLabel.Font = Enum.Font.SourceSans
refreshLabel.TextScaled = true
refreshLabel.Parent = frame

local refreshBox = Instance.new("TextBox")
refreshBox.Size = UDim2.new(0, 280, 0, 28)
refreshBox.Position = UDim2.new(0, 20, 0, 418)
refreshBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
refreshBox.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshBox.PlaceholderText = "Enter minutes"
refreshBox.Text = tostring(refreshMinutes)
refreshBox.Font = Enum.Font.SourceSans
refreshBox.TextScaled = true
refreshBox.ClearTextOnFocus = false
refreshBox.Parent = frame

local refreshCorner = Instance.new("UICorner")
refreshCorner.CornerRadius = UDim.new(0, 8)
refreshCorner.Parent = refreshBox

local webhookLabel = Instance.new("TextLabel")
webhookLabel.Size = UDim2.new(0, 280, 0, 20)
webhookLabel.Position = UDim2.new(0, 20, 0, 455)
webhookLabel.BackgroundTransparency = 1
webhookLabel.Text = "Discord webhook (text only):"
webhookLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
webhookLabel.Font = Enum.Font.SourceSans
webhookLabel.TextScaled = true
webhookLabel.Parent = frame

local webhookBox = Instance.new("TextBox")
webhookBox.Size = UDim2.new(0, 280, 0, 28)
webhookBox.Position = UDim2.new(0, 20, 0, 478)
webhookBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
webhookBox.TextColor3 = Color3.fromRGB(255, 255, 255)
webhookBox.PlaceholderText = "Paste webhook URL"
webhookBox.Text = tostring(config.webhookUrl or "")
webhookBox.Font = Enum.Font.SourceSans
webhookBox.TextScaled = false
webhookBox.ClearTextOnFocus = false
webhookBox.TextXAlignment = Enum.TextXAlignment.Left
webhookBox.Parent = frame

local webhookCorner = Instance.new("UICorner")
webhookCorner.CornerRadius = UDim.new(0, 8)
webhookCorner.Parent = webhookBox

local statsLabel = Instance.new("TextLabel")
statsLabel.Size = UDim2.new(0, 280, 0, 80)
statsLabel.Position = UDim2.new(0, 20, 0, 520)
statsLabel.BackgroundTransparency = 1
statsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statsLabel.Font = Enum.Font.SourceSans
statsLabel.TextScaled = false
statsLabel.TextWrapped = true
statsLabel.TextXAlignment = Enum.TextXAlignment.Left
statsLabel.TextYAlignment = Enum.TextYAlignment.Top
statsLabel.Parent = frame

local function updateStatsLabel()
    statsLabel.Text =
        "Starts: " .. tostring(config.stats.scriptStarts) ..
        " | AutoExec: " .. tostring(config.stats.autoExecCount) ..
        " | Rejoins: " .. tostring(config.stats.rejoinCount) ..
        "\nSoftRefresh: " .. tostring(config.stats.softRefreshCount) ..
        " | Farm: " .. (farmEnabled and "ON" or "OFF") ..
        " | AutoRefresh: " .. (autoRefreshEnabled and "ON" or "OFF")
end

updateStatsLabel()

toggleButton.MouseButton1Click:Connect(function()
    farmEnabled = not farmEnabled
    syncConfig()
    toggleButton.Text = farmEnabled and "Macro: ON" or "Macro: OFF"

    if farmEnabled then
        lastMoveTick = tick()
        scanAllEggs()
        processQueue()
    else
        isWalking = false
    end
    updateStatsLabel()
end)

jumpBox.FocusLost:Connect(function()
    local num = tonumber(jumpBox.Text)
    if num and num > 0 then
        jumpInterval = num
    end
    jumpBox.Text = tostring(jumpInterval)
    syncConfig()
end)

repeatBox.FocusLost:Connect(function()
    local num = tonumber(repeatBox.Text)
    if num and num > 0 then
        repeatInterval = num
    end
    repeatBox.Text = tostring(repeatInterval)
    syncConfig()
end)

refreshBox.FocusLost:Connect(function()
    local num = tonumber(refreshBox.Text)
    if num and num > 0 then
        refreshMinutes = math.max(1, math.floor(num))
    end
    refreshBox.Text = tostring(refreshMinutes)
    syncConfig()
    updateStatsLabel()
end)

webhookBox.FocusLost:Connect(function()
    config.webhookUrl = webhookBox.Text or ""
    saveConfig()
end)

recordButton.MouseButton1Click:Connect(function()
    if isRecording then
        stopRecording()
        recordButton.Text = "Record: OFF"
    else
        startRecording()
        recordButton.Text = "Record: ON"
    end
end)

testButton.MouseButton1Click:Connect(function()
    playRecording()
end)

repeatToggle.MouseButton1Click:Connect(function()
    repeatRecording = not repeatRecording
    repeatToggle.Text = repeatRecording and "Recorder Loop: ON" or "Recorder Loop: OFF"
end)

autoExecButton.MouseButton1Click:Connect(function()
    autoExecEnabled = not autoExecEnabled
    syncConfig()
    autoExecButton.Text = autoExecEnabled and "Auto Exec: ON" or "Auto Exec: OFF"

    if autoExecEnabled then
        setupAutoExec()
    end
    updateStatsLabel()
end)

autoRefreshButton.MouseButton1Click:Connect(function()
    autoRefreshEnabled = not autoRefreshEnabled
    syncConfig()
    autoRefreshButton.Text = autoRefreshEnabled and "Soft Refresh: ON" or "Soft Refresh: OFF"
    updateStatsLabel()
end)

local dragging = false
local dragStart
local startPos

title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

task.spawn(function()
    while true do
        task.wait(jumpInterval)
        if farmEnabled and antiAfkEnabled then
            local hum = getHum(getChar())
            if hum then
                doJump(hum)
            end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.2)

        if repeatRecording and #recordedInputs > 0 and not isPlayingRecording then
            playRecording()

            while isPlayingRecording do
                task.wait(0.1)
            end

            task.wait(repeatInterval)
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(RESCAN_INTERVAL)
        scanAllEggs()
        if farmEnabled then
            processQueue()
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(1)

        if autoRefreshEnabled then
            local refreshSeconds = math.max(60, refreshMinutes * 60)
            local elapsed = os.time() - (config.runtime.lastStartUnix or os.time())

            if elapsed >= refreshSeconds then
                config.stats.softRefreshCount += 1
                config.runtime.lastStartUnix = os.time()
                saveConfig()
                updateStatsLabel()

                softRefreshMacro()
                sendWebhookMessage(buildStatusText("Scheduled soft refresh"))
            end
        end
    end
end)

workspace.DescendantAdded:Connect(onPossibleEgg)

task.spawn(function()
    task.wait(1)
    scanAllEggs()
    if farmEnabled then
        processQueue()
    end
end)

player.Chatted:Connect(function(msg)
    local cmd = msg:lower():match("^/e%s+farm%s+(%a+)$")
    if cmd == "on" then
        farmEnabled = true
        syncConfig()
        toggleButton.Text = "Macro: ON"
        lastMoveTick = tick()
        scanAllEggs()
        processQueue()
    elseif cmd == "off" then
        farmEnabled = false
        syncConfig()
        toggleButton.Text = "Macro: OFF"
        isWalking = false
    end
    updateStatsLabel()
end)

setupAutoExec()
updateStatsLabel()

if farmEnabled then
    task.delay(1.5, function()
        scanAllEggs()
        processQueue()
    end)
end

sendWebhookMessage(buildStatusText("Script loaded"))

print("[EggBot] Bot Loaded - Saved State + Auto Exec + Soft Refresh + Webhook Text Status!")
