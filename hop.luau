setfpscap(25)

local rs = game:GetService("ReplicatedStorage")
local pl = game:GetService("Players")
local ws = game:GetService("Workspace")
local tps = game:GetService("TeleportService")
local https = game:GetService("HttpService")
local lighting = game:GetService("Lighting")
local replicatedFirst = game:GetService("ReplicatedFirst")

local lp = pl.LocalPlayer or pl:GetPropertyChangedSignal("LocalPlayer"):Wait() or pl.LocalPlayer
if not lp then
    lp = pl:WaitForChild("LocalPlayer", 10) or pl.LocalPlayer
end

local pid = game.PlaceId
local job = game.JobId
local initialJobId = job

local name = "Unknown"
if lp then
    name = lp.Name or lp.DisplayName or "Unknown"
end

local hasHopped = false
local hopInProgress = false
local currentTeleportJob = nil
local lastTeleportAttemptTime = 0
local teleportAttemptCount = 0
local isRejoinAttempt = false

local API_URL = "http://163.245.200.159:1000"
local SECRET = "9fA3QwRZ7M2xKJdB8H6sE0TnYpC5LVaUeGmF4cW1rXkqSihO"
local HEADERS = {
    ["Authorization"] = "Bearer " .. SECRET,
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    ["Connection"] = "close"
}

-- Ignored owners (will skip brainrots from these bases)
local IGNORED_OWNERS = {
    ["SpyderSammy"] = true,      -- Name
    ["Sammy"] = true,            -- DisplayName
    [2678001507] = true,         -- UserId
}

local runservice = game:GetService("RunService")
runservice:Set3dRenderingEnabled(false)

if not game:IsLoaded() then game.Loaded:Wait() end

local function getRequestFunc()
    return (syn and syn.request) 
        or (http and http.request) 
        or http_request 
        or (fluxus and fluxus.request) 
        or request
end

local requestFunc = getRequestFunc()

local function buildUrl(path)
    local base = API_URL
    while base:sub(-1) == "/" do base = base:sub(1, -2) end
    while path:sub(1, 1) == "/" do path = path:sub(2) end
    return base .. "/" .. path
end

local lastRequest = 0
local minInterval = 0

local function sendRequest(method, url, headers, body)
    if not requestFunc then
        return false, "No request function"
    end
    
    local now = tick()
    if now - lastRequest < minInterval then
        task.wait(minInterval - (now - lastRequest))
    end
    lastRequest = tick()
    
    local finalHeaders = {}
    for k, v in pairs(headers) do finalHeaders[k] = v end
    finalHeaders["Connection"] = "close"
    
    local bodyStr = body and https:JSONEncode(body) or nil
    if bodyStr then
        finalHeaders["Content-Type"] = "application/json"
    end
    
    local ok, res = pcall(requestFunc, {
        Url = url,
        Method = method,
        Headers = finalHeaders,
        Body = bodyStr,
    })
    
    if ok and res and res.Success then
        return true, res.Body
    end
    return false, res and res.StatusMessage or "Request failed"
end

-- Get new job from API
local function getNewJobFromAPI()
    local ok, res = sendRequest("GET", buildUrl("/api/v1/getjobs"), HEADERS)
    if ok then
        local ok2, parsed = pcall(https.JSONDecode, https, res)
        if ok2 and type(parsed) == "table" then
            local newJob = parsed.JobId or parsed.jobId or parsed[1] or parsed.job_id
            if newJob and newJob ~= "" and newJob ~= job then
                return newJob
            end
        end
    end
    return nil
end

-- Listen for teleport failures
local teleportFailedConnection = nil
local lastFailedJob = nil
local lastIsTeleportingErrorTime = 0
local minWaitAfterIsTeleporting = 1  -- Wait 2 seconds after IsTeleporting error
local activeConnections = {}  -- Track all connections for cleanup

pcall(function()
    teleportFailedConnection = tps.TeleportInitFailed:Connect(function(player, result, errorMessage)
        if player == lp then
            local resultStr = tostring(result)
            warn("[Teleport] Failed: " .. resultStr .. " - " .. tostring(errorMessage))
            
            -- If it's IsTeleporting error, track the time and wait before next attempt
            if resultStr:find("IsTeleporting") or tostring(errorMessage):find("previous teleport") or tostring(errorMessage):find("in processing") then
                lastIsTeleportingErrorTime = tick()
                warn("[Hop] IsTeleporting error detected, will wait before next attempt")
            end
            
            lastFailedJob = currentTeleportJob
            hopInProgress = false
            hasHopped = false
            currentTeleportJob = nil
        end
    end)
    table.insert(activeConnections, teleportFailedConnection)
end)

-- Cleanup function to disconnect everything and free resources before hop
local lastCleanupTime = 0
local cleanupCooldown = 2  -- Only cleanup every 2 seconds max

local function cleanupBeforeHop(force)
    local now = tick()
    if not force and (now - lastCleanupTime) < cleanupCooldown then
        return  -- Skip cleanup if done recently
    end
    lastCleanupTime = now
    
    -- Disconnect all tracked connections (except teleportFailedConnection which we keep)
    for _, conn in ipairs(activeConnections) do
        if conn and conn ~= teleportFailedConnection then
            pcall(function() conn:Disconnect() end)
        end
    end
    
    -- Clear active connections list (but keep teleportFailedConnection)
    activeConnections = {teleportFailedConnection}
    
    -- Clear synchronizer channels cache if it exists (only if force cleanup)
    if force and synchronizer then
        pcall(function()
            local channels = synchronizer:GetAllChannels()
            if channels then
                for _, channel in pairs(channels) do
                    pcall(function()
                        if channel and typeof(channel) == "Instance" then
                            -- Just clear references, don't destroy
                        end
                    end)
                end
            end
        end)
    end
    
    -- Force garbage collection if available (only if force cleanup)
    if force then
        pcall(function()
            if collectgarbage then
                collectgarbage("collect")
            end
        end)
    end
end

-- Try to teleport to a specific job
local function tryTeleport(targetJobId)
    if not targetJobId or targetJobId == "" or targetJobId == job then
        return false
    end
    
    -- Cleanup before attempting teleport (only light cleanup, not force)
    cleanupBeforeHop(false)
    
    -- Don't retry the same failed job immediately (unless it's been a while)
    -- For IsTeleporting errors, we might want to retry after a delay
    local timeSinceLastFailure = tick() - lastIsTeleportingErrorTime
    if targetJobId == lastFailedJob and timeSinceLastFailure < minWaitAfterIsTeleporting then
        return false
    end
    
    -- Check if we need to wait after an IsTeleporting error
    local timeSinceIsTeleportingError = tick() - lastIsTeleportingErrorTime
    if timeSinceIsTeleportingError < minWaitAfterIsTeleporting and timeSinceIsTeleportingError > 0 then
        local waitTime = minWaitAfterIsTeleporting - timeSinceIsTeleportingError
        warn("[Hop] Waiting " .. string.format("%.2f", waitTime) .. "s after IsTeleporting error before retrying...")
        task.wait(waitTime)
    end
    
    -- Don't attempt if we're already in progress and it's been less than 3 seconds
    if hopInProgress then
        local timeSinceLastAttempt = tick() - lastTeleportAttemptTime
        if timeSinceLastAttempt < 3 then
            return false
        else
            -- Timeout, reset the flag
            hopInProgress = false
        end
    end
    
    hopInProgress = true
    currentTeleportJob = targetJobId
    hasHopped = true  -- Optimistically set
    lastTeleportAttemptTime = tick()
    teleportAttemptCount = teleportAttemptCount + 1
    
    local success = pcall(tps.TeleportToPlaceInstance, tps, pid, targetJobId, lp)
    
    if not success then
        hopInProgress = false
        hasHopped = false
        currentTeleportJob = nil
        return false
    end
    
    return true
end

-- Force rejoin to the same place (random server)
local function forceRejoin()
    cleanupBeforeHop(true)  -- Force cleanup before rejoin
    isRejoinAttempt = true
    lastTeleportAttemptTime = tick()
    
    local success = pcall(function()
        tps:Teleport(pid, lp)
    end)
    
    return success
end

-- Check if we're actively trying to teleport (within last 5 seconds)
local function isActivelyTeleporting()
    if not hopInProgress then return false end
    local timeSinceLastAttempt = tick() - lastTeleportAttemptTime
    return timeSinceLastAttempt < 5
end

-- MAIN SERVER HOP LOGIC
-- 1. Get job from API
-- 2. Try to teleport
-- 3. If fails, get NEW job and try again
-- 4. Never retry same failed job (unless enough time passed)
local function serverHopWithRetry()
    -- Cleanup before starting hop process (force cleanup only once)
    cleanupBeforeHop(true)
    
    local failedJobs = {}
    local failedJobTimestamps = {}
    local maxAttempts = 100  -- Increased max attempts
    local attempts = 0
    local consecutiveFailures = 0
    local maxConsecutiveFailures = 5
    
    while not hasHopped and attempts < maxAttempts do
        attempts = attempts + 1
        
        -- Check if we actually hopped (in case it happened asynchronously)
        if game.JobId ~= initialJobId then
            hasHopped = true
            return true
        end
        
        -- If we had IsTeleporting error recently, wait longer
        local timeSinceIsTeleportingError = tick() - lastIsTeleportingErrorTime
        if timeSinceIsTeleportingError < minWaitAfterIsTeleporting and timeSinceIsTeleportingError > 0 then
            local waitTime = minWaitAfterIsTeleporting - timeSinceIsTeleportingError + 0.5
            task.wait(waitTime)
        end
        
        -- Get a new job
        local newJob = getNewJobFromAPI()
        
        -- Check if job was previously failed, but allow retry after 10 seconds
        local canRetry = true
        if failedJobs[newJob] then
            local timeSinceFailure = tick() - (failedJobTimestamps[newJob] or 0)
            if timeSinceFailure < 10 then
                canRetry = false
            else
                -- Reset after timeout
                failedJobs[newJob] = nil
                failedJobTimestamps[newJob] = nil
            end
        end
        
        if newJob and canRetry and newJob ~= job then
            -- Try to teleport
            local success = tryTeleport(newJob)
            
            if success then
                -- Wait a bit to see if teleport actually works (reduced from 3s to 2s)
                local waitStart = tick()
                local waitDuration = 1
                
                while tick() - waitStart < waitDuration do
                    task.wait(0.25)  -- Reduced from 0.5 to 0.25 for faster checks
                    
                    -- Check if we actually hopped
                    if game.JobId ~= initialJobId then
                        hasHopped = true
                        return true
                    end
                    
                    -- Check if teleport failed while waiting
                    if not hopInProgress and not hasHopped then
                        -- Teleport failed event fired, break early
                        break
                    end
                end
                
                -- Check one more time if we hopped
                if game.JobId ~= initialJobId then
                    hasHopped = true
                    return true
                end
                
                -- If still here, teleport failed (game ended, IsTeleporting, etc)
                warn("[Hop] Teleport to " .. string.sub(newJob, 1, 8) .. "... failed, getting new job")
                failedJobs[newJob] = true
                failedJobTimestamps[newJob] = tick()
                hasHopped = false
                hopInProgress = false
                consecutiveFailures = consecutiveFailures + 1
                
                -- If too many consecutive failures, wait a bit longer
                if consecutiveFailures >= maxConsecutiveFailures then
                    warn("[Hop] Too many consecutive failures, waiting 1s before retrying...")
                    task.wait(1)  -- Reduced from 2s to 1s
                    consecutiveFailures = 0
                end
            else
                -- Teleport call failed immediately
                if newJob then
                    failedJobs[newJob] = true
                    failedJobTimestamps[newJob] = tick()
                end
                consecutiveFailures = consecutiveFailures + 1
            end
        elseif not newJob then
            -- API returned no job, wait a bit (reduced)
            task.wait(0.2)  -- Reduced from 0.5
        end
        
        -- Small delay before next attempt (longer if we had IsTeleporting errors)
        if timeSinceIsTeleportingError < 5 and timeSinceIsTeleportingError > 0 then
            task.wait(0.3)  -- Reduced from 0.5
        else
            task.wait(0.05)  -- Reduced from 0.1
        end
    end
    
    -- If we've tried many times but still haven't hopped, reset and try again
    if attempts >= maxAttempts and not hasHopped and game.JobId == initialJobId then
        warn("[Hop] Max attempts reached (" .. maxAttempts .. "), resetting failed jobs and retrying...")
        failedJobs = {}
        failedJobTimestamps = {}
        consecutiveFailures = 0
        lastFailedJob = nil
        lastIsTeleportingErrorTime = 0
        
        -- Wait a bit before retrying (reduced from 2s to 1s)
        task.wait(1)
        return serverHopWithRetry()
    end
    
    return hasHopped
end

local function isGameFullyLoaded()
    local clientLoaded = replicatedFirst:GetAttribute("ClientLoaded")
    local dataLoaded = replicatedFirst:GetAttribute("DataLoaded")
    
    if clientLoaded ~= true or dataLoaded ~= true then return false end
    
    local success, result = pcall(function()
        local required = {
            {rs, "Packages"},
            {rs, "Utils"},
            {rs, "Shared"},
            {rs, "Datas"},
            {rs, "ReplicatedGui"},
            {ws, "Map"},
        }
        
        for _, check in ipairs(required) do
            if not check[1]:FindFirstChild(check[2]) then return false end
        end
        
        local packages = rs:FindFirstChild("Packages")
        local utils = rs:FindFirstChild("Utils")
        local sharedF = rs:FindFirstChild("Shared")
        local datas = rs:FindFirstChild("Datas")
        
        if not packages:FindFirstChild("Net") then return false end
        if not packages:FindFirstChild("Synchronizer") then return false end
        if not utils:FindFirstChild("NumberUtils") then return false end
        if not sharedF:FindFirstChild("Animals") then return false end
        if not datas:FindFirstChild("Animals") then return false end
        
        local t1, _ = pcall(function() require(utils.NumberUtils) end)
        local t2, _ = pcall(function() require(sharedF.Animals) end)
        local t3, _ = pcall(function() require(datas.Animals) end)
        local t4, _ = pcall(function() require(packages.Synchronizer) end)
        
        return t1 and t2 and t3 and t4
    end)
    
    return success and result == true
end

local startTime = tick()
local timeout = 10  -- Reduced from 15 to 10 seconds
local loaded = false

repeat
    task.wait(0.3)  -- Reduced from 0.5 to 0.3 for faster checks
    if isGameFullyLoaded() then
        loaded = true
        break
    end
until tick() - startTime > timeout

-- If game didn't load, hop immediately
if not loaded then
    serverHopWithRetry()
    return
end

local packages = rs:WaitForChild("Packages")
local utils = rs:WaitForChild("Utils")
local sharedF = rs:WaitForChild("Shared")
local datas = rs:WaitForChild("Datas")

local _, numbersU = pcall(function() return require(utils.NumberUtils) end)
if not numbersU then return end

local _, brainrotsShared = pcall(function() return require(sharedF.Animals) end)
if not brainrotsShared then return end

local _, brainrotsData = pcall(function() return require(datas.Animals) end)
if not brainrotsData then return end

local _, synchronizer = pcall(function() return require(packages.Synchronizer) end)
if not synchronizer then return end

local plots = ws:FindFirstChild("Plots")

local function getChannel(index)
    local channels = synchronizer:GetAllChannels()
    if channels[index] then return channels[index] end
    return synchronizer:Create(nil, index, nil)
end

local function waitChannel(index)
    local channel = getChannel(index)
    if channel then return channel end
    
    local start = tick()
    local maxWait = 0.5  -- Reduced from 2 to 0.5 seconds for faster checks
    repeat
        task.wait(0.05)  -- Reduced from 0.1 to 0.05
        channel = getChannel(index)
        if tick() - start > maxWait then return nil end
    until channel
    return channel
end

local function getGen(index, mutation, traits)
    if index == "Coffin Tung Tung Tung Sahur" then return "N/A" end
    local gen = brainrotsShared:GetGeneration(index, mutation, traits, nil)
    return "$" .. numbersU:ToString(gen) .. "/s"
end

local function getTimer(plot)
    local purchases = plot:FindFirstChild("Purchases")
    if not purchases then return "N/A" end
    
    local main = purchases:FindFirstChild("Main", true)
    if not main then return "N/A" end
    
    local billboardGui = main:FindFirstChild("BillboardGui")
    if not billboardGui then return "N/A" end
    
    local remainingTime = billboardGui:FindFirstChild("RemainingTime")
    return remainingTime and remainingTime.Text or "N/A"
end

local function parseGenValue(genStr)
    if genStr == "N/A" or not genStr or type(genStr) ~= "string" then return 0 end
    
    local clean = genStr:gsub("%$", ""):gsub("/s", ""):gsub(",", ""):gsub(" ", "")
    if clean == "" then return 0 end
    
    local multipliers = {K = 1e3, M = 1e6, B = 1e9}
    for suffix, mult in pairs(multipliers) do
        if clean:find(suffix) then
            local numStr = clean:gsub(suffix, "")
            local base = tonumber(numStr)
            return base and (base * mult) or 0
        end
    end
    
    return tonumber(clean) or 0
end

-- Check if an owner should be ignored
local function isIgnoredOwner(ownerData)
    if not ownerData then return false end
    
    -- If ownerData is a string (just the name)
    if type(ownerData) == "string" then
        return IGNORED_OWNERS[ownerData] == true
    end
    
    -- If ownerData is a table/object with properties
    if type(ownerData) == "table" or typeof(ownerData) == "Instance" then
        -- Check Name
        local ownerName = ownerData.Name
        if ownerName and IGNORED_OWNERS[ownerName] then
            return true
        end
        
        -- Check DisplayName
        local displayName = ownerData.DisplayName
        if displayName and IGNORED_OWNERS[displayName] then
            return true
        end
        
        -- Check UserId
        local userId = ownerData.UserId
        if userId and IGNORED_OWNERS[userId] then
            return true
        end
    end
    
    return false
end

-- Quick check if there's any brainrot with 10M+ (fast, returns immediately on first match)
local function hasAnyBrainrot10MPlus()
    if not plots then return false end
    
    local maxPlotsToCheck = 10  -- Limit plots to check for speed
    local plotsChecked = 0
    
    for _, plot in plots:GetChildren() do
        if plotsChecked >= maxPlotsToCheck then break end
        if not plot:IsA("Model") or not plot:GetAttribute("Tier") then continue end
        
        plotsChecked = plotsChecked + 1
        
        local channel = getChannel(plot.Name)  -- Use getChannel instead of waitChannel for speed
        if not channel then continue end
        
        -- Skip if owner is in ignored list
        local channelData = channel:GetTable()
        if channelData and channelData.Owner then
            if isIgnoredOwner(channelData.Owner) then
                continue  -- Skip this plot
            end
        end
        
        local animals = channel:Get("AnimalList") or {}
        if #animals == 0 then continue end
        
        -- Quick check: only check first few animals for speed
        local maxAnimalsToCheck = math.min(5, #animals)
        for i = 1, maxAnimalsToCheck do
            local entry = animals[i]
            if type(entry) ~= "table" or not entry.Index or entry == "Empty" then continue end
            
            local genValue = getGen(entry.Index, entry.Mutation, entry.Traits)
            local genNum = parseGenValue(genValue)
            if genNum >= 10000000 then
                return true  -- Found one, return immediately
            end
        end
    end
    return false
end

local function getBrainrots()
    local results = {}
    if not plots then return results end
    
    for _, plot in plots:GetChildren() do
        if not plot:IsA("Model") or not plot:GetAttribute("Tier") then continue end
        
        local channel = waitChannel(plot.Name)
        if not channel then continue end
        
        local channelData = channel:GetTable()
        
        -- Skip if owner is in ignored list
        if channelData and channelData.Owner then
            if isIgnoredOwner(channelData.Owner) then
                continue  -- Skip this entire plot
            end
        end
        
        local animals = channel:Get("AnimalList") or {}
        local plotTimer = getTimer(plot)
        
        for _, entry in ipairs(animals) do
            if type(entry) ~= "table" or not entry.Index or entry == "Empty" then continue end
            
            local animalData = brainrotsData[entry.Index]
            
            local genValue = getGen(entry.Index, entry.Mutation, entry.Traits)
            local genNum = parseGenValue(genValue)
            if genNum < 10000000 then continue end
            
            local owner = "Unknown"
            if channelData and channelData.Owner then
                owner = type(channelData.Owner) == "string" and channelData.Owner or channelData.Owner.Name
            end
            
            table.insert(results, {
                name = (animalData and animalData.DisplayName) or entry.Index or "",
                mutation = entry.Mutation or "",
                gen = genValue,
                owner = owner,
                timer = plotTimer,
            })
        end
    end
    return results
end

local function getBrainrotsGroupedByOwner()
    if not plots then return {} end
    
    local all = getBrainrots()
    if #all == 0 then return {} end
    
    local byOwner = {}
    for _, br in all do
        local owner = br.owner
        if not byOwner[owner] then 
            byOwner[owner] = {
                brainrots = {},
                timer = br.timer
            }
        end
        table.insert(byOwner[owner].brainrots, br)
    end
    
    return byOwner
end

local function formatData(brainrots, timer, owner)
    local data = {
        Timer = timer,
        Owner = owner,
        PlayerCount = #pl:GetPlayers(),
        BestBrainrot = nil,
        Brainrots = {},
        JobId = job
    }
    
    local best = -math.huge
    for _, br in ipairs(brainrots) do
        local num = parseGenValue(br.gen)
        local formatted = {"%s %s (%s)", br.mutation, br.name, br.gen}
        table.insert(data.Brainrots, formatted)
        if num > best then
            best = num
            data.BestBrainrot = formatted
        end
    end
    return data
end

local function sendAllBrainrotsToAPI()
    local startTime = tick()
    local maxTime = 5  -- Max 5 seconds for all API calls
    
    local grouped = getBrainrotsGroupedByOwner()
    
    local ownerCount = 0
    for _ in pairs(grouped) do ownerCount = ownerCount + 1 end
    if ownerCount == 0 then
        return nil
    end
    
    local lastJobId = nil
    local maxOwners = 5  -- Limit to first 5 owners for speed
    
    local ownerIndex = 0
    for owner, ownerData in pairs(grouped) do
        if tick() - startTime > maxTime then break end  -- Timeout check
        if ownerIndex >= maxOwners then break end  -- Limit owners
        ownerIndex = ownerIndex + 1
        
        local data = formatData(ownerData.brainrots, ownerData.timer, owner)
        
        -- Reduced attempts from 3 to 2
        for attempt = 1, 2 do
            if tick() - startTime > maxTime then break end  -- Timeout check
            
            local ok, res = sendRequest("POST", buildUrl("/api/v1/addbrainrots"), HEADERS, data)
            
            if ok and res then
                local ok2, parsed = pcall(https.JSONDecode, https, res)
                if ok2 and type(parsed) == "table" then
                    local receivedJob = parsed.JobId or parsed.jobId
                    if receivedJob and receivedJob ~= "" and receivedJob ~= job then
                        lastJobId = receivedJob
                    end
                    break
                end
            end
            
            if attempt < 2 then
                task.wait(0.05)  -- Reduced from 0.1
            end
        end
        
        task.wait(0.01)  -- Reduced from 0.02
    end
    
    return lastJobId
end

local function markOnline()
    sendRequest("POST", buildUrl("/api/v1/markonline"), HEADERS, { Username = name })
end

local function startMarkOnlineLoop()
    markOnline()
    while true do
        task.wait(20)
        markOnline()
    end
end

local function monitorJobId()
    while true do
        task.wait(0.5)
        local currentJobId = game.JobId
        if currentJobId ~= initialJobId then
            hasHopped = true
            break
        end
    end
end

local function startProcess()
    -- Quick check: if no brainrots with 10M+, hop immediately
    local hasBrainrots = hasAnyBrainrot10MPlus()
    
    if not hasBrainrots then
        -- No brainrots found, hop immediately without API calls
        warn("[Hop] No brainrots with 10M+ found, hopping immediately...")
        serverHopWithRetry()
        return
    end
    
    -- Has brainrots, send to API and then hop
    warn("[Hop] Brainrots with 10M+ found, sending to API...")
    local newJobId = sendAllBrainrotsToAPI()
    
    -- If we got a job from addbrainrots, try it first
    if newJobId and newJobId ~= "" and newJobId ~= job then
        local success = tryTeleport(newJobId)
        if success then
            -- Wait and check if teleport worked (reduced from 3s to 2s)
            local waitStart = tick()
            while tick() - waitStart < 2 do
                task.wait(0.25)  -- Reduced from 0.5 to 0.25
                if game.JobId ~= initialJobId then
                    hasHopped = true
                    return
                end
                -- If teleport failed event fired, break early
                if not hopInProgress and not hasHopped then
                    break
                end
            end
            
            -- Final check
            if game.JobId ~= initialJobId then
                hasHopped = true
                return
            end
            
            -- Teleport from addbrainrots failed, mark as failed
            warn("[Hop] Initial teleport from addbrainrots failed, starting retry logic...")
            lastFailedJob = newJobId
            hopInProgress = false
            hasHopped = false
        end
    end
    
    -- Use the retry logic to find a working server
    -- This will keep retrying until it succeeds or max attempts
    serverHopWithRetry()
end

local function timeoutChecker()
    -- Phase 1: Wait 10 seconds, checking if we're actively trying to hop (reduced from 15)
    local phase1Start = tick()
    
    while tick() - phase1Start < 10 do
        task.wait(0.5)  -- Reduced from 1s to 0.5s for faster checks
        
        -- Already hopped? We're done
        if hasHopped or game.JobId ~= initialJobId then
            return
        end
    end
    
    -- After 15 seconds, check status
    if hasHopped or game.JobId ~= initialJobId then
        return
    end
    
    -- Phase 2: Check if we're actively teleporting
    if isActivelyTeleporting() then
        warn("[Hop] 10s passed but teleport is in progress, waiting...")
        
        -- Give it more time if actively teleporting (reduced from 10s to 5s)
        local extendedWait = tick()
        while tick() - extendedWait < 5 do
            task.wait(0.5)  -- Reduced from 1s to 0.5s
            if hasHopped or game.JobId ~= initialJobId then
                return
            end
            
            -- Still actively trying? Keep waiting
            if isActivelyTeleporting() then
                extendedWait = tick() - 2.5  -- Reset timer partially (reduced from 5)
            end
        end
    end
    
    -- Phase 3: Not actively teleporting or extended wait exceeded
    -- Try to rejoin (random server in same place)
    if not hasHopped and game.JobId == initialJobId then
        warn("[Hop] Not actively teleporting, attempting rejoin...")
        task.spawn(function()
            while true do
                task.wait(1)
                local newJob = getNewJobFromAPI()
                if newJob then
                    tryTeleport(newJob)
                end
            end
        end)
    end
    
    -- Phase 4: Rejoin didn't work after 3 seconds
    -- Try one more time with a fresh job from API
    if not hasHopped and game.JobId == initialJobId then
        warn("[Hop] Rejoin failed, trying one last API hop...")
        
        local newJob = getNewJobFromAPI()
        if newJob then
            tryTeleport(newJob)
            
            -- Wait 3 more seconds (reduced from 5)
            local lastChanceStart = tick()
            while tick() - lastChanceStart < 3 do
                task.wait(0.25)  -- Reduced from 0.5
                if game.JobId ~= initialJobId then
                    hasHopped = true
                    return
                end
            end
        end
    end
    
    -- Phase 5: Everything failed, shutdown as last resort
    if not hasHopped and game.JobId == initialJobId then
        warn("[Hop] All attempts failed after 30+ seconds, shutting down...")
        pcall(function()
            while true do
                task.wait(1)
                local newJob = getNewJobFromAPI()
                if newJob then
                    tryTeleport(newJob)
                end
            end
        end)
    end
end

task.spawn(startMarkOnlineLoop)
task.spawn(startProcess)
task.spawn(timeoutChecker)
task.spawn(monitorJobId)
