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
local hopMutex = false

local API_URL = "http://163.245.200.159:1000"
local SECRET = "9fA3QwRZ7M2xKJdB8H6sE0TnYpC5LVaUeGmF4cW1rXkqSihO"
local HEADERS = {
    ["Authorization"] = "Bearer " .. SECRET,
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    ["Connection"] = "close"
}

pcall(function()
    local runservice = game:GetService("RunService")
    runservice:Set3dRenderingEnabled(false)
    
    local renderSettings = settings().Rendering
    renderSettings.QualityLevel = Enum.QualityLevel.Level01
    renderSettings.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level01
    renderSettings.EditQualityLevel = Enum.QualityLevel.Level01
    
    lighting.GlobalShadows = false
    lighting.Brightness = 3
    lighting.FogEnd = 9e9
    lighting.Technology = Enum.Technology.Legacy
    lighting.EnvironmentDiffuseScale = 0
    lighting.EnvironmentSpecularScale = 0
    
    for _, effect in ipairs(lighting:GetChildren()) do
        if effect:IsA("PostEffect") then
            pcall(function() 
                effect.Enabled = false 
                effect:Destroy() 
            end)
        end
    end
    
    if setfflag then
        pcall(function() setfflag("DFIntDebugFRMQualityLevelOverride", "1") end)
        pcall(function() setfflag("FFlagDisablePostFx", "True") end)
        pcall(function() setfflag("FIntRenderShadowIntensity", "0") end)
    end
end)

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
local minInterval = 0.1

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

local function performTeleport(targetJobId)
    if targetJobId and targetJobId ~= "" then
        hasHopped = true
        pcall(tps.TeleportToPlaceInstance, tps, pid, targetJobId, lp)
    end
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
local timeout = 15
local loaded = false

repeat
    task.wait(0.5)
    if isGameFullyLoaded() then
        loaded = true
        break
    end
until tick() - startTime > timeout

if not loaded then
    while true do
        local ok, res = sendRequest("GET", buildUrl("/api/v1/getjobs"), HEADERS)
        if ok then
            local ok2, parsed = pcall(https.JSONDecode, https, res)
            if ok2 and type(parsed) == "table" then
                local jid = parsed.JobId or parsed.jobId
                if jid and jid ~= "" and jid ~= job then
                    performTeleport(jid)
                end
            end
        end
        task.wait(0.5)
    end
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
    repeat
        task.wait(0.1)
        channel = getChannel(index)
        if tick() - start > 10 then return nil end
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

local function getBrainrots()
    local results = {}
    if not plots then return results end
    
    for _, plot in plots:GetChildren() do
        if not plot:IsA("Model") or not plot:GetAttribute("Tier") then continue end
        
        local channel = waitChannel(plot.Name)
        if not channel then continue end
        
        local animals = channel:Get("AnimalList") or {}
        local plotTimer = getTimer(plot)
        
        for _, entry in ipairs(animals) do
            if type(entry) ~= "table" or not entry.Index or entry == "Empty" then continue end
            
            local animalData = brainrotsData[entry.Index]
            local rarity = animalData and animalData.Rarity or "N/A"
            if rarity ~= "Secret" then continue end
            
            local genValue = getGen(entry.Index, entry.Mutation, entry.Traits)
            local genNum = parseGenValue(genValue)
            if genNum < 1000000 then continue end
            
            local channelData = channel:GetTable()
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

local function getNewJobId()
    for attempt = 1, 3 do
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
        task.wait(0.1)
    end
    return nil
end

local function forceServerHop()
    if hopMutex then return end
    hopMutex = true
    
    local newJobId = getNewJobId()
    if newJobId then
        performTeleport(newJobId)
    else
        -- If API fails, try multiple times quickly
        for i = 1, 5 do
            task.wait(0.1)
            newJobId = getNewJobId()
            if newJobId then
                performTeleport(newJobId)
                break
            end
        end
    end
    
    hopMutex = false
end

local function serverHop()
    while true do
        if not hopMutex then
            local newJobId = getNewJobId()
            if newJobId then
                performTeleport(newJobId)
            end
        end
        task.wait(0.5)
    end
end

local function markOnline()
    sendRequest("POST", buildUrl("/api/v1/markonline"), HEADERS, { Username = name })
end

local function startMarkOnlineLoop()
    markOnline()
    while true do
        task.wait(25)
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

local function sendAllBrainrotsToAPI()
    local grouped = getBrainrotsGroupedByOwner()
    
    local ownerCount = 0
    for _ in pairs(grouped) do ownerCount = ownerCount + 1 end
    if ownerCount == 0 then
        return nil
    end
    
    local lastJobId = nil
    local allSuccess = true
    local sentCount = 0
    
    for owner, ownerData in pairs(grouped) do
        local data = formatData(ownerData.brainrots, ownerData.timer, owner)
        
        local success = false
        for attempt = 1, 3 do
            local ok, res = sendRequest("POST", buildUrl("/api/v1/addbrainrots"), HEADERS, data)
            
            if ok and res then
                local ok2, parsed = pcall(https.JSONDecode, https, res)
                if ok2 and type(parsed) == "table" then
                    local receivedJob = parsed.JobId or parsed.jobId
                    if receivedJob and receivedJob ~= "" and receivedJob ~= job then
                        lastJobId = receivedJob
                    end
                    success = true
                    sentCount = sentCount + 1
                    break
                end
            end
            
            task.wait(0.2)
        end
        
        if not success then
            allSuccess = false
        end
        
        task.wait(0.05)
    end
    
    if allSuccess and sentCount > 0 then
        return lastJobId
    end
    
    return nil
end

local function startProcess()
    local newJobId = sendAllBrainrotsToAPI()
    
    if newJobId and newJobId ~= "" and newJobId ~= job then
        performTeleport(newJobId)
        task.wait(0.2)
    end
    
    serverHop()
end

local function timeoutChecker()
    -- Wait 5 seconds, then force hop
    task.wait(5)
    
    local currentJobId = game.JobId
    if not hasHopped and currentJobId == initialJobId then
        warn("[Server Hop] 5 seconds passed, forcing server hop...")
        forceServerHop()
    end
    
    -- Wait additional 5 seconds (total 10 seconds)
    task.wait(5)
    
    -- Check if hopped after 10 seconds total
    currentJobId = game.JobId
    if not hasHopped and currentJobId == initialJobId then
        warn("[Server Hop] 10 seconds passed without server hop, shutting down game...")
        pcall(function()
            game:Shutdown()
        end)
    end
end

task.spawn(startMarkOnlineLoop)
task.spawn(startProcess)
task.spawn(timeoutChecker)
task.spawn(monitorJobId)
