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
    Costs = {
        Water = math.huge,
    },
}

local REACH_DIST             = 4.5
local WAYPOINT_TIMEOUT       = 4
local JUMP_COOLDOWN          = 0.2
local MAX_PATH_ATTEMPTS      = 5
local WALK_HARD_TIMEOUT      = 90
local QUEUE_COOLDOWN         = 0.2
local RESCAN_INTERVAL        = 5
local STUCK_ESCAPE_THRESHOLD = 1   -- trigger escape after just 1 stuck_hard
local DETOUR_MAX_DISTANCE    = 20
local DETOUR_PATH_OVERHEAD   = 1.25
local FAIL_BEFORE_SKIP       = 3

-- ─── MANUAL PATHS ────────────────────────────────────────────────────────────
-- Island chain path 1: recorded manually, used when egg is in trigger zone
-- Trigger zone: any egg within 35 studs of (39.2, 96, -435.3)
local ISLAND_PATH_1 = {
    zone = { center = Vector3.new(39.2, 96, -435.3), radius = 35 },
    -- Last solid land point before islands — bot pathfinds here first
    entryPoint = Vector3.new(109.6, 92.0, -425.8),
    waypoints = {
        Vector3.new(109.6, 92.0, -425.8),
        Vector3.new(101.8, 99.5, -426.2),
        Vector3.new(95.4,  91.7, -426.6),
        Vector3.new(92.4,  92.0, -427.1),
        Vector3.new(86.4,  92.0, -428.9),
        Vector3.new(84.1,  92.0, -431.1),
        Vector3.new(83.2,  93.7, -433.4),
        Vector3.new(81.1,  99.0, -439.4),
        Vector3.new(80.0,  93.9, -442.1),
        Vector3.new(74.5,  94.0, -442.1),
        Vector3.new(68.2,  93.9, -442.2),
        Vector3.new(61.9, 101.2, -442.0),
        Vector3.new(59.6, 101.0, -441.9),
        Vector3.new(52.1, 101.0, -441.4),
        Vector3.new(45.8, 101.0, -441.0),
        Vector3.new(43.6, 101.0, -440.8),
    },
}

-- Blessing obby: recorded manually
-- Bot pathfinds to entryPoint then runs waypoints
-- Game TPs player back to spawn automatically at the end
local BLESSING_OBBY = {
    entryPoint = Vector3.new(175.0, 93.4, -567.8),
    waypoints = {
        Vector3.new(175.0,  93.4, -567.8),
        Vector3.new(175.5,  98.3, -573.2),
        Vector3.new(176.5,  97.1, -579.5),
        Vector3.new(177.1,  88.6, -582.2),
        Vector3.new(180.7,  92.9, -587.3),
        Vector3.new(184.5,  94.9, -592.3),
        Vector3.new(187.8,  88.6, -596.5),
        Vector3.new(189.2,  89.5, -598.2),
        Vector3.new(192.9,  96.4, -602.1),
        Vector3.new(197.3,  89.7, -606.2),
        Vector3.new(201.7,  90.0, -610.3),
        Vector3.new(206.7,  97.6, -614.2),
        Vector3.new(207.4, 103.0, -617.6),
        Vector3.new(207.8, 103.0, -624.0),
        Vector3.new(208.0, 100.9, -630.3),
        Vector3.new(208.5, 102.1, -636.2),
        Vector3.new(209.1, 103.2, -642.4),
        Vector3.new(209.7, 102.9, -648.5),
        Vector3.new(203.2, 105.8, -653.7),
        Vector3.new(199.0, 105.9, -657.9),
        Vector3.new(194.8, 105.9, -662.3),
        Vector3.new(190.6, 105.9, -666.7),
        Vector3.new(188.8, 105.9, -668.5),
        Vector3.new(183.4, 101.9, -672.6),
        Vector3.new(180.9, 104.1, -673.8),
        Vector3.new(175.2, 107.7, -675.5),
        Vector3.new(172.2,  97.9, -676.2),
        Vector3.new(169.4, 103.0, -676.2),
        Vector3.new(163.4, 103.6, -676.0),
        Vector3.new(157.1,  99.9, -675.8),
        Vector3.new(151.1, 100.0, -676.0),
        Vector3.new(144.8,  99.2, -676.4),
        Vector3.new(136.8, 105.2, -676.9),
        Vector3.new(130.9,  97.9, -677.2),
        Vector3.new(127.9, 105.3, -677.4),
        Vector3.new(120.7, 107.9, -677.6),
        Vector3.new(117.2, 113.6, -672.4),
        Vector3.new(113.1, 110.9, -667.6),
        Vector3.new(108.4, 110.0, -663.3),
        Vector3.new(106.6, 107.9, -662.0),
        Vector3.new(100.6, 107.9, -662.5),
        Vector3.new(96.2,  100.9, -662.1),
        Vector3.new(96.9,  100.9, -655.3),
        Vector3.new(96.6,  100.9, -651.8),
        Vector3.new(94.1,  102.7, -649.9),
        Vector3.new(89.2,  108.1, -646.3),
        Vector3.new(87.1,  108.0, -644.0),
        Vector3.new(82.0,  107.9, -642.8),
        Vector3.new(77.6,  107.9, -641.7),
        Vector3.new(72.3,  112.4, -639.3),
        Vector3.new(66.4,  114.9, -637.3),
        Vector3.new(64.2,  117.4, -637.2),
        Vector3.new(58.2,  121.6, -637.1),
        Vector3.new(55.3,  124.4, -636.7),
        Vector3.new(52.0,  128.7, -636.1),
        Vector3.new(47.2,  124.9, -635.3),
        Vector3.new(47.6,  132.5, -631.4),
        Vector3.new(48.3,  128.6, -624.9),
        Vector3.new(48.1,  130.6, -621.5),
    },
}

-- Spawn point (used to detect respawn)
local SPAWN_POINT = Vector3.new(210.1, 92.5, -361.5)

local EGG_COLORS = {
    [1] = Color3.fromRGB(255, 255, 255),
    [2] = Color3.fromRGB(0,   255, 0),
    [3] = Color3.fromRGB(0,   170, 255),
    [4] = Color3.fromRGB(170, 0,   255),
    [5] = Color3.fromRGB(255, 170, 0),
    [6] = Color3.fromRGB(255, 0,   0),
}
local JUMP_COLOR   = Color3.fromRGB(255, 100, 0)
local POTION_COLOR = Color3.fromRGB(255, 0, 200)
local DEFAULT_COLOR = Color3.new(1, 1, 1)

local queueDirty = false

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
    blessingEnabled = false,
    blessingInterval = 10,
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
        lastBlessingUnix = 0,
    }
}

local function deepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
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
        local okRead, contents = pcall(function() return readfile(CONFIG_FILE) end)
        if okRead and contents and contents ~= "" then
            local okJson, decoded = pcall(function() return HttpService:JSONDecode(contents) end)
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
    if not writefile then return end
    pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(config)) end)
end

config.stats.scriptStarts += 1
if config.runtime.lastJobId ~= "" and config.runtime.lastJobId ~= game.JobId then
    config.stats.autoExecCount += 1
    config.stats.rejoinCount   += 1
end
config.runtime.lastJobId     = game.JobId
config.runtime.lastPlaceId   = game.PlaceId
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
local blessingEnabled    = config.blessingEnabled or false
local blessingInterval   = tonumber(config.blessingInterval) or 10
local isRunningBlessing  = false

local antiAfkEnabled = true
local jumpInterval   = tonumber(config.jumpInterval) or 30

local recordedInputs     = {}
local isRecording        = false
local isPlayingRecording = false
local repeatRecording    = false
local repeatInterval     = tonumber(config.repeatInterval) or 10
local recordStartTime    = 0

shared.toggled         = farmEnabled
shared.autoExecEnabled = autoExecEnabled

local function syncConfig()
    config.farmEnabled        = farmEnabled
    config.autoExecEnabled    = autoExecEnabled
    config.autoRefreshEnabled = autoRefreshEnabled
    config.refreshMinutes     = refreshMinutes
    config.jumpInterval       = jumpInterval
    config.repeatInterval     = repeatInterval
    config.blessingEnabled    = blessingEnabled
    config.blessingInterval   = blessingInterval
    shared.toggled            = farmEnabled
    shared.autoExecEnabled    = autoExecEnabled
    saveConfig()
end

local function isAlive(inst)
    return inst ~= nil and inst.Parent ~= nil
end

local function safeGet(fn)
    local ok, val = pcall(fn)
    return ok and val or nil
end

local function getChar() return player.Character end
local function getHum(c) return c and c:FindFirstChildOfClass("Humanoid") end
local function getRoot(c) return c and c:FindFirstChild("HumanoidRootPart") end

local function resolvePos(inst)
    if not isAlive(inst) then return nil end
    return safeGet(function()
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Model") then
            if inst.PrimaryPart then return inst.PrimaryPart.Position end
            local bp = inst:FindFirstChildWhichIsA("BasePart", true)
            return bp and bp.Position
        end
    end)
end

local function buildUid(v)
    return v.Name .. "_" .. v:GetDebugId()
end

local function classifyEgg(v)
    if not v or not (v:IsA("Model") or v:IsA("BasePart")) then return nil end
    local name = v.Name
    if string.find(name, "potion", 1, true) then
        return { color = POTION_COLOR, priority = 7 }
    end
    local eggNum = tonumber(string.match(name, "egg_(%d+)$"))
    if eggNum then
        return { color = EGG_COLORS[eggNum] or DEFAULT_COLOR, priority = eggNum }
    end
    return nil
end

local function getDistanceToTarget(target)
    local root = getRoot(getChar())
    local pos  = resolvePos(target)
    if not root or not pos then return math.huge end
    return (root.Position - pos).Magnitude
end

local function markQueueDirty() queueDirty = true end

local function sortQueueIfDirty()
    if not queueDirty then return end
    queueDirty = false
    table.sort(eggQueue, function(a, b)
        local aPriority = a.priority - (a.failCount or 0)
        local bPriority = b.priority - (b.failCount or 0)
        if aPriority ~= bPriority then return aPriority > bPriority end
        local da = getDistanceToTarget(a.target)
        local db = getDistanceToTarget(b.target)
        if math.abs(da - db) > 8 then return da < db end
        return a.firstSeen < b.firstSeen
    end)
end

local function sortQueue()
    markQueueDirty()
    sortQueueIfDirty()
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
            pcall(function() if folder.Parent then folder:Destroy() end end)
        end)
    end
    return folder, cleanup
end

local function doJump(hum)
    if hum
        and hum:GetState() ~= Enum.HumanoidStateType.Jumping
        and hum:GetState() ~= Enum.HumanoidStateType.Freefall
    then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

local function buildRayParams(char)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Blacklist
    local ignore     = {char}
    local activePath = workspace:FindFirstChild("ActivePath")
    if activePath then table.insert(ignore, activePath) end
    rp.FilterDescendantsInstances = ignore
    return rp
end

-- ─── ESCAPE MANEUVER ─────────────────────────────────────────────────────────
local lastEscapeDir = {}

local function doEscapeManeuver(hum, root, eggUid)
    if not hum or not root then return end
    hum:MoveTo(root.Position)
    task.wait(0.1)
    local lastDir = lastEscapeDir[eggUid]
    local side = lastDir and -lastDir or ((math.random(0,1) == 0) and -1 or 1)
    lastEscapeDir[eggUid] = side
    local strafeDir   = root.CFrame.RightVector * side
    local escapeStart = tick()
    while tick() - escapeStart < 3 do
        if not farmEnabled then break end
        hum:MoveTo(root.Position + strafeDir * 5)
        task.wait(0.15)
    end
    doJump(hum)
    task.wait(0.2)
end

-- ─── MANUAL WAYPOINT WALKER ───────────────────────────────────────────────────
-- Walks a list of Vector3 positions directly, jumping when Y rises significantly.
-- Used for island paths and the blessing obby.
local function walkManualPath(waypoints, jumpThreshold)
    jumpThreshold = jumpThreshold or 1.5
    local char = getChar()
    local hum  = getHum(char)
    local root = getRoot(char)
    if not hum or not root then return "fail" end

    for i, wp in ipairs(waypoints) do
        if not farmEnabled and not isRunningBlessing then return "stopped" end

        -- Jump if next point is significantly higher
        if i < #waypoints then
            local nextWp = waypoints[i + 1]
            if nextWp.Y - root.Position.Y > jumpThreshold then
                doJump(hum)
                task.wait(0.1)
            end
        end

        hum:MoveTo(wp)

        local startT   = tick()
        local lastPos  = root.Position
        local stuckT   = tick()

        while true do
            task.wait()

            local dist = (root.Position - wp).Magnitude
            if dist < REACH_DIST then break end

            if tick() - startT > WAYPOINT_TIMEOUT * 2 then
                -- Timed out on this waypoint, try jumping and continuing
                doJump(hum)
                task.wait(0.3)
                break
            end

            -- Detect respawn (fell in water mid-manual-path)
            if (root.Position - SPAWN_POINT).Magnitude < 10 then
                return "respawned"
            end

            -- Nudge if stuck
            if tick() - stuckT > 1.0 then
                local moved = (root.Position - lastPos).Magnitude
                if moved < 0.5 then
                    doJump(hum)
                    hum:MoveTo(wp)
                end
                lastPos = root.Position
                stuckT  = tick()
            end
        end
    end

    return "done"
end

-- ─── STEP TO WAYPOINT ────────────────────────────────────────────────────────
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
        if result == nil then result = reached and "reached" or "timeout" end
    end)

    while result == nil do
        task.wait()
        if not farmEnabled then result = "stopped" break end
        if tick() - startT > WAYPOINT_TIMEOUT then result = "timeout" break end

        -- Detect respawn
        local teleportDist = (root.Position - lastPos).Magnitude
        if teleportDist > 50 and (tick() - lastPosTime) < 0.5 then
            result = "respawned"
            break
        end

        local dist = (root.Position - wp.Position).Magnitude
        if dist < REACH_DIST then
            result       = "reached"
            lastMoveTick = tick()
            break
        end

        local now = tick()
        if now - lastPosTime > PROGRESS_CHECK_INTERVAL then
            local moved = (root.Position - lastPos).Magnitude
            if moved < MIN_PROGRESS then
                stuckCount += 1
                local dir     = (wp.Position - root.Position)
                local flatDir = Vector3.new(dir.X, 0, dir.Z)
                if flatDir.Magnitude > 0 then flatDir = flatDir.Unit end
                local rayParams  = buildRayParams(char)
                local frontRay   = flatDir.Magnitude > 0 and workspace:Raycast(root.Position, flatDir * 3, rayParams) or nil
                local ceilingRay = workspace:Raycast(root.Position, Vector3.new(0, 3.5, 0), rayParams)

                -- Lower threshold: escalate after 2 micro-stucks
                if stuckCount >= 2 then result = "stuck_hard" break end

                if frontRay and not ceilingRay and (now - lastJumpTime) > JUMP_COOLDOWN then
                    lastJumpTime = now
                    doJump(hum)
                    hum:MoveTo(wp.Position)
                elseif frontRay then
                    if flatDir.Magnitude > 0 then
                        local side           = (math.random(0, 1) == 0) and -1 or 1
                        local sidestepTarget = root.Position + root.CFrame.RightVector * side * 3
                        hum:MoveTo(sidestepTarget)
                        task.wait(0.3)
                        hum:MoveTo(root.Position - flatDir * 2)
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

-- ─── CHECK MANUAL ZONE ───────────────────────────────────────────────────────
local function getManualPathForEgg(eggPos)
    for _, manualPath in ipairs({ ISLAND_PATH_1 }) do
        local zone = manualPath.zone
        local dist = Vector3.new(eggPos.X - zone.center.X, 0, eggPos.Z - zone.center.Z).Magnitude
        if dist <= zone.radius then
            return manualPath
        end
    end
    return nil
end

-- ─── WALK TO EGG ─────────────────────────────────────────────────────────────
local walkToEgg

local function grabNearbyEgg(currentWpPos, targetPos, primaryTarget)
    for _, data in ipairs(eggQueue) do
        if not isAlive(data.target) then continue end
        if data.target == primaryTarget then continue end
        local eggPos = resolvePos(data.target)
        if not eggPos then continue end
        local distToEgg      = (currentWpPos - eggPos).Magnitude
        local distEggToFinal = (eggPos - targetPos).Magnitude
        local distWpToFinal  = (currentWpPos - targetPos).Magnitude
        if distToEgg <= DETOUR_MAX_DISTANCE
            and distEggToFinal <= distWpToFinal * DETOUR_PATH_OVERHEAD
        then
            local grabResult = walkToEgg(data.target, data.color)
            if grabResult == "done" then
                trackedEggs[data.id] = nil
                queuedIds[data.id]   = nil
                for i, e in ipairs(eggQueue) do
                    if e.id == data.id then
                        table.remove(eggQueue, i)
                        markQueueDirty()
                        break
                    end
                end
            end
            return
        end
    end
end

walkToEgg = function(targetInstance, eggColor)
    local char = getChar()
    local hum  = getHum(char)
    local root = getRoot(char)
    if not hum or not root then return "fail" end

    local uid               = buildUid(targetInstance)
    local consecutiveStucks = 0
    local targetPos         = resolvePos(targetInstance)
    if not targetPos then return "done" end

    -- Check if this egg is in a manual path zone
    local manualPath = getManualPathForEgg(targetPos)

    if manualPath then
        -- Step 1: normal pathfind to the entry point
        local path = PathfindingService:CreatePath(PATH_PARAMS)
        pcall(function() path:ComputeAsync(root.Position, manualPath.entryPoint) end)

        if path.Status == Enum.PathStatus.Success then
            local waypoints           = path:GetWaypoints()
            local pathFolder, cleanup = makePathFolder(waypoints, eggColor)
            local ok = true

            for _, wp in ipairs(waypoints) do
                if not farmEnabled or not isAlive(targetInstance) then ok = false break end
                local stepResult = stepToWaypoint(hum, root, wp)
                if stepResult ~= "reached" and stepResult ~= "timeout" then
                    ok = false break
                end
            end
            cleanup()
            if not ok then return "fail" end
        end

        -- Step 2: walk the manual waypoints
        local result = walkManualPath(manualPath.waypoints)
        if result ~= "done" then return "fail" end

        -- Step 3: fire the proximity prompt if egg is still alive
        if isAlive(targetInstance) then
            for _, v in ipairs(targetInstance:GetDescendants()) do
                if v:IsA("ProximityPrompt") then
                    task.wait(0.5)
                    fireproximityprompt(v)
                end
            end
        end

        lastEscapeDir[uid] = nil
        task.wait(0.1)
        return "done"
    end

    -- Normal pathfinding for eggs not in any manual zone
    for attempt = 1, MAX_PATH_ATTEMPTS do
        if not farmEnabled then return "stopped" end
        targetPos = resolvePos(targetInstance)
        if not targetPos then return "done" end

        if consecutiveStucks >= STUCK_ESCAPE_THRESHOLD then
            print("[EggBot] Hard stuck x" .. consecutiveStucks .. " — running escape maneuver")
            doEscapeManeuver(hum, root, uid)
            consecutiveStucks = 0
            char = getChar()
            hum  = getHum(char)
            root = getRoot(char)
            if not hum or not root then return "fail" end
        end

        local path = PathfindingService:CreatePath(PATH_PARAMS)
        local ok   = pcall(function() path:ComputeAsync(root.Position, targetPos) end)

        if not ok or path.Status ~= Enum.PathStatus.Success then
            task.wait(0.2)
            continue
        end

        local waypoints           = path:GetWaypoints()
        local pathFolder, cleanup = makePathFolder(waypoints, eggColor)
        local pathBroken          = false

        for i, wp in ipairs(waypoints) do
            if not farmEnabled or not isAlive(targetInstance) then
                pathBroken = true break
            end

            local needsJump = wp.Action == Enum.PathWaypointAction.Jump
            if not needsJump and i < #waypoints then
                if (waypoints[i + 1].Position.Y - root.Position.Y) > 0.8 then
                    needsJump = true
                end
            end
            if needsJump then doJump(hum) end

            local stepResult = stepToWaypoint(hum, root, wp)

            if stepResult == "respawned" then
                warn("[EggBot] Respawn detected on " .. uid .. " — skipping attempt")
                consecutiveStucks += 1
                pathBroken = true
                break
            elseif stepResult == "stuck_hard" then
                consecutiveStucks += 1
                pathBroken = true
                break
            elseif stepResult == "timeout" or stepResult == "fail" or stepResult == "stopped" then
                pathBroken = true
                break
            else
                if i < #waypoints - 1 then
                    grabNearbyEgg(wp.Position, targetPos, targetInstance)
                end
            end
        end

        cleanup()
        if not farmEnabled then return "stopped" end
        if pathBroken then task.wait(0.2) continue end

        if isAlive(targetInstance) then
            for _, v in ipairs(targetInstance:GetDescendants()) do
                if v:IsA("ProximityPrompt") then
                    task.wait(0.5)
                    fireproximityprompt(v)
                end
            end
        end

        lastEscapeDir[uid] = nil
        task.wait(0.1)
        return "done"
    end

    return "fail"
end

-- ─── BLESSING OBBY RUNNER ────────────────────────────────────────────────────
local function runBlessingObby()
    if isRunningBlessing then return end
    isRunningBlessing = true

    local prevFarm = farmEnabled
    farmEnabled    = false  -- pause farming while doing blessing
    isWalking      = false

    print("[EggBot] Starting Basic Blessing obby")

    local char = getChar()
    local hum  = getHum(char)
    local root = getRoot(char)

    if not hum or not root then
        isRunningBlessing = false
        farmEnabled = prevFarm
        return
    end

    -- Pathfind to entry point first
    local path = PathfindingService:CreatePath(PATH_PARAMS)
    pcall(function() path:ComputeAsync(root.Position, BLESSING_OBBY.entryPoint) end)

    if path.Status == Enum.PathStatus.Success then
        local waypoints           = path:GetWaypoints()
        local pathFolder, cleanup = makePathFolder(waypoints, Color3.fromRGB(0, 200, 255))

        for _, wp in ipairs(waypoints) do
            stepToWaypoint(hum, root, wp)
        end
        cleanup()
    end

    -- Walk the obby
    -- isRunningBlessing=true so walkManualPath won't stop early
    local result = walkManualPath(BLESSING_OBBY.waypoints, 2.0)

    if result == "done" then
        print("[EggBot] Basic Blessing obby complete — waiting for TP")
        -- Game TPs player to spawn, wait for it
        task.wait(3)
    else
        warn("[EggBot] Basic Blessing obby failed: " .. result)
    end

    config.runtime.lastBlessingUnix = os.time()
    saveConfig()

    isRunningBlessing = false
    farmEnabled = prevFarm

    if farmEnabled then
        task.wait(0.5)
        scanAllEggs()
        processQueue()
    end
end

-- ─── QUEUE / SCAN ────────────────────────────────────────────────────────────
local function pruneTrackedEggs()
    for uid, data in pairs(trackedEggs) do
        if not isAlive(data.target) then
            trackedEggs[uid] = nil
            queuedIds[uid]   = nil
        end
    end
end

local function pruneQueue()
    local alive = {}
    for _, e in ipairs(eggQueue) do
        if isAlive(e.target) then
            table.insert(alive, e)
        else
            queuedIds[e.id]   = nil
            trackedEggs[e.id] = nil
        end
    end
    local changed = #alive ~= #eggQueue
    eggQueue = alive
    if changed then markQueueDirty() end
    sortQueueIfDirty()
end

local function queueEgg(v)
    local info = classifyEgg(v)
    if not info then return end
    if not isAlive(v) then return end
    local uid = buildUid(v)
    if trackedEggs[uid] then return end
    local data = {
        target    = v,
        color     = info.color,
        id        = uid,
        firstSeen = tick(),
        priority  = info.priority,
        failCount = 0,
    }
    trackedEggs[uid] = data
    if not queuedIds[uid] then
        queuedIds[uid] = true
        table.insert(eggQueue, data)
        markQueueDirty()
    end
end

function scanAllEggs()
    pruneTrackedEggs()
    pruneQueue()
    for _, v in ipairs(workspace:GetDescendants()) do
        queueEgg(v)
    end
    sortQueueIfDirty()
end

local function releaseWalking() isWalking = false end

function processQueue()
    if not farmEnabled or isWalking or isRunningBlessing or #eggQueue == 0 then return end
    isWalking = true

    task.spawn(function()
        local hardTimer = task.delay(WALK_HARD_TIMEOUT, function() releaseWalking() end)

        pruneQueue()
        sortQueueIfDirty()

        local data = table.remove(eggQueue, 1)

        if data then
            queuedIds[data.id] = nil

            if isAlive(data.target) and farmEnabled then
                local result = walkToEgg(data.target, data.color)

                if result == "done" or not isAlive(data.target) then
                    trackedEggs[data.id]   = nil
                    lastEscapeDir[data.id] = nil
                elseif result == "stopped" then
                    if isAlive(data.target) and not queuedIds[data.id] then
                        queuedIds[data.id] = true
                        table.insert(eggQueue, data)
                        markQueueDirty()
                    end
                else
                    if isAlive(data.target) then
                        data.failCount = (data.failCount or 0) + 1
                        if data.failCount >= FAIL_BEFORE_SKIP then
                            print("[EggBot] Deprioritizing " .. data.id .. " (fail #" .. data.failCount .. ")")
                            data.firstSeen = tick() + 9999
                        end
                        if not queuedIds[data.id] then
                            queuedIds[data.id] = true
                            table.insert(eggQueue, data)
                            markQueueDirty()
                        end
                    else
                        trackedEggs[data.id]   = nil
                        lastEscapeDir[data.id] = nil
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
            sortQueueIfDirty()
            processQueue()
        end
    end)
end

-- ─── WEBHOOK ─────────────────────────────────────────────────────────────────
local function getRequestFunc()
    return request or http_request or (syn and syn.request) or (fluxus and fluxus.request)
end

local function sendWebhookMessage(message)
    local webhookUrl = tostring(config.webhookUrl or "")
    if webhookUrl == "" then return end
    local req = getRequestFunc()
    if not req then return end
    task.spawn(function()
        pcall(function()
            req({
                Url     = webhookUrl,
                Method  = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body    = HttpService:JSONEncode({ content = message })
            })
        end)
    end)
end

local function buildStatusText(reason)
    return string.format(
        "**EggBot status**\nReason: %s\nPlayer: %s\nPlaceId: %s\nJobId: %s\nFarm: %s\nAutoExec: %s\nAutoRefresh: %s\nRefreshMinutes: %s\nScriptStarts: %s\nAutoExecCount: %s\nRejoinCount: %s\nSoftRefreshCount: %s",
        reason, tostring(player.Name), tostring(game.PlaceId), tostring(game.JobId),
        farmEnabled and "ON" or "OFF", autoExecEnabled and "ON" or "OFF",
        autoRefreshEnabled and "ON" or "OFF", tostring(refreshMinutes),
        tostring(config.stats.scriptStarts), tostring(config.stats.autoExecCount),
        tostring(config.stats.rejoinCount), tostring(config.stats.softRefreshCount)
    )
end

local function setupAutoExec()
    if not autoExecEnabled then return end
    if RAW_SCRIPT_URL == "" or RAW_SCRIPT_URL == "PASTE_YOUR_RAW_GITHUB_LINK_HERE" then
        warn("[EggBot] RAW_SCRIPT_URL not set") return
    end
    local qot = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
    if qot then
        qot(string.format('loadstring(game:HttpGet("%s"))()', RAW_SCRIPT_URL))
    else
        warn("[EggBot] queue_on_teleport not available")
    end
end

local function softRefreshMacro()
    isWalking     = false
    eggQueue      = {}
    queuedIds     = {}
    trackedEggs   = {}
    lastEscapeDir = {}
    local activePath = workspace:FindFirstChild("ActivePath")
    if activePath then pcall(function() activePath:Destroy() end) end
    scanAllEggs()
    if farmEnabled then task.wait(0.2) processQueue() end
end

-- ─── RECORDER ────────────────────────────────────────────────────────────────
local allowedKeys = {
    [Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true,
    [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
    [Enum.KeyCode.Space] = true,
}

local function startRecording()
    recordedInputs  = {}
    isRecording     = true
    recordStartTime = tick()
end

local function stopRecording() isRecording = false end

local function playRecording()
    if #recordedInputs == 0 then warn("No recording saved") return end
    if isPlayingRecording then return end
    isPlayingRecording = true
    task.spawn(function()
        local playStart = tick()
        for _, ev in ipairs(recordedInputs) do
            local waitTime = ev.t / 1000 - (tick() - playStart)
            if waitTime > 0 then task.wait(waitTime) end
            VIM:SendKeyEvent(ev.state == "begin", ev.key, false, game)
        end
        isPlayingRecording = false
    end)
end

UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or not isRecording then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if not allowedKeys[input.KeyCode] then return end
    table.insert(recordedInputs, { t = math.floor((tick() - recordStartTime) * 1000), key = input.KeyCode, state = "begin" })
end)

UIS.InputEnded:Connect(function(input, gameProcessed)
    if not isRecording then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if not allowedKeys[input.KeyCode] then return end
    table.insert(recordedInputs, { t = math.floor((tick() - recordStartTime) * 1000), key = input.KeyCode, state = "end" })
end)

-- ─── UI ──────────────────────────────────────────────────────────────────────
local screenGui        = Instance.new("ScreenGui")
screenGui.Name         = "EggBotUI"
screenGui.ResetOnSpawn = false
screenGui.Parent       = playerGui

local frame            = Instance.new("Frame")
frame.Size             = UDim2.new(0, 320, 0, 730)
frame.Position         = UDim2.new(0, 20, 0, 120)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
frame.BorderSizePixel  = 0
frame.Parent           = screenGui

Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local function makeLabel(text, yPos, height)
    height = height or 20
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0, 280, 0, height)
    l.Position = UDim2.new(0, 20, 0, yPos)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Color3.fromRGB(255, 255, 255)
    l.Font = Enum.Font.SourceSans
    l.TextScaled = true
    l.Parent = frame
    return l
end

local function makeButton(text, yPos)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 280, 0, 35)
    b.Position = UDim2.new(0, 20, 0, yPos)
    b.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.SourceSansBold
    b.TextScaled = true
    b.Text = text
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

local function makeBox(placeholder, value, yPos)
    local b = Instance.new("TextBox")
    b.Size = UDim2.new(0, 280, 0, 28)
    b.Position = UDim2.new(0, 20, 0, yPos)
    b.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.PlaceholderText = placeholder
    b.Text = tostring(value)
    b.Font = Enum.Font.SourceSans
    b.TextScaled = true
    b.ClearTextOnFocus = false
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

local title = makeLabel("Egg Macro", 0, 30)
title.Font = Enum.Font.SourceSansBold

local toggleButton   = makeButton(farmEnabled and "Macro: ON" or "Macro: OFF", 40)
toggleButton.BackgroundColor3 = Color3.fromRGB(60,60,60)

makeLabel("Jump every X seconds:", 85)
local jumpBox        = makeBox("Enter seconds", jumpInterval, 108)

local recordButton   = Instance.new("TextButton")
recordButton.Size    = UDim2.new(0, 135, 0, 35)
recordButton.Position = UDim2.new(0, 20, 0, 148)
recordButton.BackgroundColor3 = Color3.fromRGB(70,70,70)
recordButton.TextColor3 = Color3.fromRGB(255,255,255)
recordButton.Font = Enum.Font.SourceSansBold
recordButton.TextScaled = true
recordButton.Text = "Record: OFF"
recordButton.Parent = frame
Instance.new("UICorner", recordButton).CornerRadius = UDim.new(0,8)

local testButton     = Instance.new("TextButton")
testButton.Size      = UDim2.new(0, 135, 0, 35)
testButton.Position  = UDim2.new(0, 165, 0, 148)
testButton.BackgroundColor3 = Color3.fromRGB(70,70,70)
testButton.TextColor3 = Color3.fromRGB(255,255,255)
testButton.Font = Enum.Font.SourceSansBold
testButton.TextScaled = true
testButton.Text = "Test Recording"
testButton.Parent = frame
Instance.new("UICorner", testButton).CornerRadius = UDim.new(0,8)

makeLabel("Run recording every X seconds:", 194)
local repeatBox      = makeBox("Enter seconds", repeatInterval, 217)

local repeatToggle   = makeButton("Recorder Loop: OFF", 258)
local autoExecButton = makeButton(autoExecEnabled and "Auto Exec: ON" or "Auto Exec: OFF", 304)
local autoRefreshButton = makeButton(autoRefreshEnabled and "Soft Refresh: ON" or "Soft Refresh: OFF", 350)

makeLabel("Soft refresh every X minutes:", 395)
local refreshBox     = makeBox("Enter minutes", refreshMinutes, 418)

-- Blessing UI
local blessingButton = makeButton(blessingEnabled and "Basic Blessing: ON" or "Basic Blessing: OFF", 458)
blessingButton.BackgroundColor3 = Color3.fromRGB(50, 80, 50)

local runBlessingButton = makeButton("Run Blessing Now", 504)
runBlessingButton.BackgroundColor3 = Color3.fromRGB(50, 60, 90)

makeLabel("Blessing every X minutes:", 550)
local blessingIntervalBox = makeBox("Enter minutes", blessingInterval, 573)

makeLabel("Discord webhook (text only):", 607)
local webhookBox     = makeBox("Paste webhook URL", config.webhookUrl or "", 630)
webhookBox.TextScaled = false
webhookBox.TextXAlignment = Enum.TextXAlignment.Left

local statsLabel = Instance.new("TextLabel")
statsLabel.Size = UDim2.new(0, 280, 0, 60)
statsLabel.Position = UDim2.new(0, 20, 0, 665)
statsLabel.BackgroundTransparency = 1
statsLabel.TextColor3 = Color3.fromRGB(255,255,255)
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
        " | Blessing: " .. (blessingEnabled and "ON" or "OFF")
end

updateStatsLabel()

-- ─── BUTTON CALLBACKS ────────────────────────────────────────────────────────
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
    if num and num > 0 then jumpInterval = num end
    jumpBox.Text = tostring(jumpInterval)
    syncConfig()
end)

repeatBox.FocusLost:Connect(function()
    local num = tonumber(repeatBox.Text)
    if num and num > 0 then repeatInterval = num end
    repeatBox.Text = tostring(repeatInterval)
    syncConfig()
end)

refreshBox.FocusLost:Connect(function()
    local num = tonumber(refreshBox.Text)
    if num and num > 0 then refreshMinutes = math.max(1, math.floor(num)) end
    refreshBox.Text = tostring(refreshMinutes)
    syncConfig()
    updateStatsLabel()
end)

blessingIntervalBox.FocusLost:Connect(function()
    local num = tonumber(blessingIntervalBox.Text)
    if num and num > 0 then blessingInterval = math.max(1, math.floor(num)) end
    blessingIntervalBox.Text = tostring(blessingInterval)
    syncConfig()
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

testButton.MouseButton1Click:Connect(function() playRecording() end)

repeatToggle.MouseButton1Click:Connect(function()
    repeatRecording = not repeatRecording
    repeatToggle.Text = repeatRecording and "Recorder Loop: ON" or "Recorder Loop: OFF"
end)

autoExecButton.MouseButton1Click:Connect(function()
    autoExecEnabled = not autoExecEnabled
    syncConfig()
    autoExecButton.Text = autoExecEnabled and "Auto Exec: ON" or "Auto Exec: OFF"
    if autoExecEnabled then setupAutoExec() end
    updateStatsLabel()
end)

autoRefreshButton.MouseButton1Click:Connect(function()
    autoRefreshEnabled = not autoRefreshEnabled
    syncConfig()
    autoRefreshButton.Text = autoRefreshEnabled and "Soft Refresh: ON" or "Soft Refresh: OFF"
    updateStatsLabel()
end)

blessingButton.MouseButton1Click:Connect(function()
    blessingEnabled = not blessingEnabled
    syncConfig()
    blessingButton.Text = blessingEnabled and "Basic Blessing: ON" or "Basic Blessing: OFF"
    updateStatsLabel()
end)

runBlessingButton.MouseButton1Click:Connect(function()
    if not isRunningBlessing then
        task.spawn(runBlessingObby)
    end
end)

-- ─── DRAG ────────────────────────────────────────────────────────────────────
local dragging, dragStart, startPos = false, nil, nil

title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging  = true
        dragStart = input.Position
        startPos  = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- ─── BACKGROUND LOOPS ────────────────────────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(jumpInterval)
        if farmEnabled and antiAfkEnabled then
            local hum = getHum(getChar())
            if hum then doJump(hum) end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.2)
        if repeatRecording and #recordedInputs > 0 and not isPlayingRecording then
            playRecording()
            while isPlayingRecording do task.wait(0.1) end
            task.wait(repeatInterval)
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(RESCAN_INTERVAL)
        scanAllEggs()
        if farmEnabled then processQueue() end
    end
end)

task.spawn(function()
    while true do
        task.wait(1)
        -- Auto soft refresh
        if autoRefreshEnabled then
            local refreshSeconds = math.max(60, refreshMinutes * 60)
            local elapsed = os.time() - (config.runtime.lastStartUnix or os.time())
            if elapsed >= refreshSeconds then
                config.stats.softRefreshCount  += 1
                config.runtime.lastStartUnix    = os.time()
                saveConfig()
                updateStatsLabel()
                softRefreshMacro()
                sendWebhookMessage(buildStatusText("Scheduled soft refresh"))
            end
        end
        -- Auto blessing
        if blessingEnabled and not isRunningBlessing then
            local blessingSeconds = math.max(60, blessingInterval * 60)
            local lastBlessing    = config.runtime.lastBlessingUnix or 0
            local elapsed         = os.time() - lastBlessing
            if elapsed >= blessingSeconds then
                task.spawn(runBlessingObby)
            end
        end
    end
end)

workspace.DescendantAdded:Connect(onPossibleEgg)

task.spawn(function()
    task.wait(1)
    scanAllEggs()
    if farmEnabled then processQueue() end
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
