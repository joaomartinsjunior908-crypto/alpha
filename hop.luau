local rs = game:GetService("ReplicatedStorage")
local pl = game:GetService("Players")
local ws = game:GetService("Workspace")
local tps = game:GetService("TeleportService")
local https = game:GetService("HttpService")
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

local API_URL = "http://163.245.200.159:1000"
local SECRET = "9fA3QwRZ7M2xKJdB8H6sE0TnYpC5LVaUeGmF4cW1rXkqSihO"
local HEADERS = {
    ["Authorization"] = "Bearer " .. SECRET,
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    ["Connection"] = "close"
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

local function sendRequest(method, url, headers, body)
    if not requestFunc then
        return false, "No request function"
    end
    
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

-- Notifica (marca online)
local function markOnline()
    sendRequest("POST", buildUrl("/api/v1/markonline"), HEADERS, { Username = name })
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

-- Tenta teleportar para um job
local function tryTeleport(targetJobId)
    if not targetJobId or targetJobId == "" or targetJobId == job then
        return false
    end
    
    local success = pcall(tps.TeleportToPlaceInstance, tps, pid, targetJobId, lp)
    return success
end

-- Verifica se o jogo carregou completamente
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

-- Espera o jogo carregar
local startTime = tick()
local timeout = 10
local loaded = false

repeat
    task.wait(0.3)
    if isGameFullyLoaded() then
        loaded = true
        break
    end
until tick() - startTime > timeout

if not loaded then
    warn("[Hop] Game didn't load, starting hop immediately...")
    -- Se não carregou, vai direto para o hop
else
    -- Carrega os módulos necessários
    local packages = rs:WaitForChild("Packages")
    local utils = rs:WaitForChild("Utils")
    local sharedF = rs:WaitForChild("Shared")
    local datas = rs:WaitForChild("Datas")
    
    local _, numbersU = pcall(function() return require(utils.NumberUtils) end)
    local _, brainrotsShared = pcall(function() return require(sharedF.Animals) end)
    local _, brainrotsData = pcall(function() return require(datas.Animals) end)
    local _, synchronizer = pcall(function() return require(packages.Synchronizer) end)
    
    if not numbersU or not brainrotsShared or not brainrotsData or not synchronizer then
        warn("[Hop] Failed to load required modules, starting hop...")
        loaded = false
    end
    
    if loaded then
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
            local maxWait = 2
            repeat
                task.wait(0.05)
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
        
        -- Pega todos os brainrots (pets)
        local function getAllBrainrots()
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
                    local genValue = getGen(entry.Index, entry.Mutation, entry.Traits)
                    local genNum = parseGenValue(genValue)
                    
                    local channelData = channel:GetTable()
                    local owner = "Unknown"
                    if channelData and channelData.Owner then
                        owner = type(channelData.Owner) == "string" and channelData.Owner or channelData.Owner.Name
                    end
                    
                    table.insert(results, {
                        name = (animalData and animalData.DisplayName) or entry.Index or "",
                        mutation = entry.Mutation or "",
                        gen = genValue,
                        genNum = genNum,
                        owner = owner,
                        timer = plotTimer,
                        index = entry.Index,
                    })
                end
            end
            return results
        end
        
        -- Compara duas listas de brainrots e retorna os novos
        local function getNewBrainrots(oldList, newList)
            local newOnes = {}
            local oldMap = {}
            
            -- Cria mapa dos antigos (index + mutation como chave)
            for _, br in ipairs(oldList) do
                local key = (br.index or "") .. "|" .. (br.mutation or "")
                oldMap[key] = true
            end
            
            -- Verifica quais são novos
            for _, br in ipairs(newList) do
                local key = (br.index or "") .. "|" .. (br.mutation or "")
                if not oldMap[key] then
                    table.insert(newOnes, br)
                end
            end
            
            return newOnes
        end
        
        -- Formata dados para notificar
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
                local formatted = {"%s %s (%s)", br.mutation, br.name, br.gen}
                table.insert(data.Brainrots, formatted)
                if br.genNum > best then
                    best = br.genNum
                    data.BestBrainrot = formatted
                end
            end
            return data
        end
        
        -- Notifica novos brainrots
        local function notifyNewBrainrots(newBrainrots)
            if #newBrainrots == 0 then return end
            
            -- Agrupa por owner
            local byOwner = {}
            for _, br in ipairs(newBrainrots) do
                local owner = br.owner
                if not byOwner[owner] then 
                    byOwner[owner] = {
                        brainrots = {},
                        timer = br.timer
                    }
                end
                table.insert(byOwner[owner].brainrots, br)
            end
            
            -- Envia para API
            for owner, ownerData in pairs(byOwner) do
                local data = formatData(ownerData.brainrots, ownerData.timer, owner)
                sendRequest("POST", buildUrl("/api/v1/addbrainrots"), HEADERS, data)
            end
        end
        
        -- FASE 1: Verifica pets a cada 2s por 30 segundos
        warn("[Hop] Iniciando verificação de pets por 30 segundos...")
        markOnline() -- Notifica ao entrar
        
        local lastBrainrots = {}
        local monitoringStart = tick()
        local monitoringDuration = 20
        
        while tick() - monitoringStart < monitoringDuration do
            task.wait(2) -- Espera 2 segundos
            
            -- Verifica se já mudou de servidor
            if game.JobId ~= initialJobId then
                warn("[Hop] Já está em outro servidor!")
                return
            end
            
            -- Pega todos os brainrots
            local currentBrainrots = getAllBrainrots()
            
            -- Compara com os anteriores
            local newBrainrots = getNewBrainrots(lastBrainrots, currentBrainrots)
            
            if #newBrainrots > 0 then
                warn("[Hop] Novos pets detectados: " .. #newBrainrots)
                notifyNewBrainrots(newBrainrots)
            end
            
            -- Atualiza a lista anterior
            lastBrainrots = currentBrainrots
        end
        
        warn("[Hop] 30 segundos de monitoramento concluídos, iniciando hop...")
    end
end

-- FASE 2: Tenta fazer hop a cada 1s até conseguir
local function startHopLoop()
    while true do
        -- Verifica se já mudou de servidor
        if game.JobId ~= initialJobId then
            warn("[Hop] Já está em outro servidor!")
            break
        end
        
        -- Pega um novo job da API
        local newJob = getNewJobFromAPI()
        
        if newJob then
            warn("[Hop] Tentando teleportar para job: " .. string.sub(newJob, 1, 8) .. "...")
            local success = tryTeleport(newJob)
            
            if success then
                -- Espera um pouco para ver se funcionou
                task.wait(1)
                if game.JobId ~= initialJobId then
                    warn("[Hop] Teleport realizado com sucesso!")
                    break
                end
            end
        end
        
        task.wait(1) -- Espera 1 segundo antes da próxima tentativa
    end
end

task.spawn(startHopLoop)
