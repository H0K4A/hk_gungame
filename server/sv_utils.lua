-- ============================================================================
-- SPAWN SYSTEM - Gestion des spawns
-- ============================================================================

SpawnSystem = {}
local instanceSpawnIndexes = {}
local occupiedSpawns = {}





-- ============================================================================
-- SPAWN SYSTEM
-- ============================================================================





function SpawnSystem.GetSpawnForPlayer(instanceId, mapId, playerId)
    local mapData = Config.Maps[mapId]
    
    if not mapData or not mapData.spawnPoints or #mapData.spawnPoints == 0 then
        print("^1[SpawnSystem]^7 Erreur: Aucun spawn trouvé pour la map " .. mapId)
        return nil
    end
    
    local spawnPoints = mapData.spawnPoints
    
    if not instanceSpawnIndexes[instanceId] then
        instanceSpawnIndexes[instanceId] = 0
    end
    if not occupiedSpawns[instanceId] then
        occupiedSpawns[instanceId] = {}
    end
    
    SpawnSystem.CleanExpiredSpawns(instanceId)
    
    local selectedSpawn
    if Config.SpawnSystem.randomSpawn then
        selectedSpawn = SpawnSystem.GetRandomAvailableSpawn(instanceId, spawnPoints)
    else
        selectedSpawn = SpawnSystem.GetNextSequentialSpawn(instanceId, spawnPoints)
    end
    
    if selectedSpawn then
        local spawnIndex = SpawnSystem.FindSpawnIndex(spawnPoints, selectedSpawn)
        if spawnIndex then
            occupiedSpawns[instanceId][spawnIndex] = {
                playerId = playerId,
                timestamp = os.time()
            }
        end
    end
    
    return selectedSpawn
end

function SpawnSystem.GetRandomAvailableSpawn(instanceId, spawnPoints)
    local availableSpawns = {}
    
    for i, spawn in ipairs(spawnPoints) do
        if not SpawnSystem.IsSpawnOccupied(instanceId, i) then
            table.insert(availableSpawns, spawn)
        end
    end
    
    if #availableSpawns == 0 then
        availableSpawns = spawnPoints
    end
    
    local randomIndex = math.random(1, #availableSpawns)
    return availableSpawns[randomIndex]
end

function SpawnSystem.GetNextSequentialSpawn(instanceId, spawnPoints)
    local totalSpawns = #spawnPoints
    local attempts = 0
    local selectedSpawn = nil
    
    while attempts < totalSpawns do
        instanceSpawnIndexes[instanceId] = (instanceSpawnIndexes[instanceId] % totalSpawns) + 1
        local currentIndex = instanceSpawnIndexes[instanceId]
        
        if not SpawnSystem.IsSpawnOccupied(instanceId, currentIndex) then
            selectedSpawn = spawnPoints[currentIndex]
            break
        end
        
        attempts = attempts + 1
    end
    
    if not selectedSpawn then
        local currentIndex = instanceSpawnIndexes[instanceId]
        selectedSpawn = spawnPoints[currentIndex]
    end
    
    return selectedSpawn
end

function SpawnSystem.IsSpawnOccupied(instanceId, spawnIndex)
    if not Config.SpawnSystem.checkOccupiedSpawns then
        return false
    end
    
    if not occupiedSpawns[instanceId] or not occupiedSpawns[instanceId][spawnIndex] then
        return false
    end
    
    local occupation = occupiedSpawns[instanceId][spawnIndex]
    local timeSinceOccupation = os.time() - occupation.timestamp
    
    return timeSinceOccupation < 5
end

function SpawnSystem.CleanExpiredSpawns(instanceId)
    if not occupiedSpawns[instanceId] then return end
    
    local currentTime = os.time()
    
    for spawnIndex, occupation in pairs(occupiedSpawns[instanceId]) do
        if currentTime - occupation.timestamp > 5 then
            occupiedSpawns[instanceId][spawnIndex] = nil
        end
    end
end

function SpawnSystem.FindSpawnIndex(spawnPoints, targetSpawn)
    for i, spawn in ipairs(spawnPoints) do
        if spawn.x == targetSpawn.x and spawn.y == targetSpawn.y and spawn.z == targetSpawn.z then
            return i
        end
    end
    return nil
end

function SpawnSystem.FreeSpawn(instanceId, playerId)
    if not occupiedSpawns[instanceId] then return end
    
    for spawnIndex, occupation in pairs(occupiedSpawns[instanceId]) do
        if occupation.playerId == playerId then
            occupiedSpawns[instanceId][spawnIndex] = nil
            break
        end
    end
end

function SpawnSystem.ResetInstance(instanceId)
    instanceSpawnIndexes[instanceId] = 0
    occupiedSpawns[instanceId] = {}
end

-- Thread de nettoyage automatique
Citizen.CreateThread(function()
    while true do
        Wait(10000)
        
        for instanceId in pairs(occupiedSpawns) do
            SpawnSystem.CleanExpiredSpawns(instanceId)
        end
    end
end)





-- ============================================================================
-- ROUTING BUCKET MANAGER
-- ============================================================================





RoutingBucketManager = {}
local playerRoutingBuckets = {} -- Suivi des buckets par joueur
local instanceRoutingBuckets = {} -- Suivi des buckets par instance
local nextBucketId = 100 -- Commencer à 100 pour éviter les buckets par défaut

-- Réserver le bucket 0 pour le monde normal
local WORLD_BUCKET = 0

function RoutingBucketManager.AssignPlayerToInstance(source, instanceId)
    if not source or source == 0 then
        return false
    end
    
    if not instanceId then
        return false
    end
    
    -- Créer ou récupérer le bucket pour cette instance
    local bucketId = instanceRoutingBuckets[instanceId]
    
    if not bucketId then
        bucketId = nextBucketId
        nextBucketId = nextBucketId + 1
        instanceRoutingBuckets[instanceId] = bucketId
    end
    
    -- Assigner le joueur au bucket
    SetPlayerRoutingBucket(source, bucketId)
    playerRoutingBuckets[source] = bucketId
    
    -- Configuration du bucket (important pour la visibilité)
    SetRoutingBucketPopulationEnabled(bucketId, false) -- Désactiver les entités aléatoires
    
    return true
end

function RoutingBucketManager.ReturnPlayerToWorld(source)
    if not source or source == 0 then
        return false
    end
    
    local oldBucket = playerRoutingBuckets[source]
    
    -- Remettre le joueur dans le monde normal (bucket 0)
    SetPlayerRoutingBucket(source, WORLD_BUCKET)
    playerRoutingBuckets[source] = nil
    
    if Config.Debug and oldBucket then
        print(string.format("^3[RoutingBucket]^7 Joueur %d: Bucket %d -> Monde normal (0)", 
            source, oldBucket))
    end
    
    return true
end

function RoutingBucketManager.GetPlayerBucket(source)
    return playerRoutingBuckets[source] or WORLD_BUCKET
end

function RoutingBucketManager.GetInstanceBucket(instanceId)
    return instanceRoutingBuckets[instanceId]
end

function RoutingBucketManager.CleanupInstance(instanceId)
    if not instanceId then return end
    
    local bucketId = instanceRoutingBuckets[instanceId]
    
    if bucketId then
        if Config.Debug then
            print(string.format("^3[RoutingBucket]^7 Nettoyage bucket %d (Instance %d)", 
                bucketId, instanceId))
        end
        
        -- Optionnel: on peut garder le bucket pour réutilisation
        -- ou le supprimer complètement
        instanceRoutingBuckets[instanceId] = nil
    end
end

function RoutingBucketManager.ArePlayersInSameBucket(source1, source2)
    local bucket1 = playerRoutingBuckets[source1] or WORLD_BUCKET
    local bucket2 = playerRoutingBuckets[source2] or WORLD_BUCKET
    return bucket1 == bucket2
end

-- Nettoyage automatique des joueurs déconnectés
AddEventHandler('playerDropped', function(reason)
    local source = source
    
    if playerRoutingBuckets[source] then
        playerRoutingBuckets[source] = nil
        
        if Config.Debug then
            print(string.format("^3[RoutingBucket]^7 Joueur %d déconnecté, nettoyage bucket", 
                source))
        end
    end
end)





-- ============================================================================
-- INSTANCE MANAGER - Gestion des instances
-- ============================================================================





InstanceManager = {}
local instances = {}
local nextInstanceId = 1

function InstanceManager.FindOrCreateInstance(mapId)
    -- Chercher une instance active pour cette map
    for instanceId, instance in pairs(instances) do
        if instance.map == mapId and 
           instance.gameActive and 
           instance.currentPlayers and
           instance.currentPlayers < (Config.InstanceSystem.maxPlayersPerInstance or 20) then
            return instance
        end
    end
    
    -- Créer une nouvelle instance si autorisé
    if Config.InstanceSystem.autoCreateInstance then
        local instanceId = nextInstanceId
        nextInstanceId = nextInstanceId + 1
        
        local newInstance = {
            id = instanceId,
            map = mapId,
            players = {},
            gameActive = false,
            currentPlayers = 0,
            playersData = {},
            maxPlayers = Config.InstanceSystem.maxPlayersPerInstance or 20,
            lastActivity = os.time()
        }
        
        instances[instanceId] = newInstance
        
        if Config.Debug then
            print(string.format("^2[InstanceManager]^7 Instance créée: %d (Map: %s)", instanceId, mapId))
        end
        
        return newInstance
    end
    
    return nil
end

function InstanceManager.GetInstance(instanceId)
    return instances[instanceId]
end

function InstanceManager.GetAllInstances()
    return instances
end

function InstanceManager.GetActiveInstances()
    local active = {}
    
    for instanceId, instance in pairs(instances) do
        if instance.gameActive then
            table.insert(active, instance)
        end
    end
    
    return active
end

function InstanceManager.RemoveInstance(instanceId)
    if not instances[instanceId] then
        return false
    end
    
    -- Nettoyer le routing bucket
    RoutingBucketManager.CleanupInstance(instanceId)
    
    instances[instanceId] = nil
    
    if Config.Debug then
        print(string.format("^3[InstanceManager]^7 Instance %d supprimée", instanceId))
    end
    
    return true
end

function InstanceManager.UpdateActivity(instanceId)
    if instances[instanceId] then
        instances[instanceId].lastActivity = os.time()
    end
end

-- Thread de nettoyage automatique des instances vides
Citizen.CreateThread(function()
    while true do
        Wait(60000)
        
        local instancesToDelete = {}
        
        for instanceId, instance in pairs(instances) do
            if (not instance.currentPlayers or instance.currentPlayers == 0) and not instance.gameActive then
                table.insert(instancesToDelete, instanceId)
            end
        end
        
        for _, instanceId in ipairs(instancesToDelete) do
            InstanceManager.RemoveInstance(instanceId)
        end
    end
end)

-- ============================================================================
-- MAP ROTATION - NOUVEAU SYSTÈME 2 MAPS
-- ============================================================================

MapRotation = {}
local activeMaps = {}
local usedMapIndexes = {}
local mapIdleTimers = {}

function MapRotation.Initialize()
    if not Config.MapRotation or not Config.MapRotation.enabled then
        print("^1[MapRotation]^7 Système de rotation désactivé")
        return
    end
    
    if not Config.MapRotation.allMaps or #Config.MapRotation.allMaps < 2 then
        print("^1[MapRotation]^7 ERREUR: Au moins 2 maps requises dans allMaps")
        return
    end
    
    activeMaps = MapRotation.SelectRandomMaps(Config.MapRotation.simultaneousMaps or 2)
    
    for _, mapId in ipairs(activeMaps) do
        local mapData = Config.Maps[mapId]
    end
    
    MapRotation.StartIdleMonitoring()
end

function MapRotation.SelectRandomMaps(count)
    local allMaps = Config.MapRotation.allMaps
    local selected = {}
    local available = {}
    
    for _, mapId in ipairs(allMaps) do
        table.insert(available, mapId)
    end
    
    for i = 1, math.min(count, #available) do
        local randomIndex = math.random(1, #available)
        table.insert(selected, available[randomIndex])
        table.remove(available, randomIndex)
    end
    
    return selected
end

function MapRotation.GetActiveMaps()
    if not activeMaps then
        activeMaps = {}
    end
    return activeMaps
end

function MapRotation.IsMapActive(mapId)
    for _, activeMapId in ipairs(activeMaps) do
        if activeMapId == mapId then
            return true
        end
    end
    return false
end

function MapRotation.GetAvailableGames()
    local games = {}
    
    if not activeMaps or #activeMaps == 0 then
        
        if Config.MapRotation and Config.MapRotation.allMaps and #Config.MapRotation.allMaps >= 2 then
            activeMaps = MapRotation.SelectRandomMaps(Config.MapRotation.simultaneousMaps or 2)
        else
            return games
        end
    end
    
    for _, mapId in ipairs(activeMaps) do
        local mapData = Config.Maps[mapId]
        
        if mapData then
            local instance = InstanceManager.FindOrCreateInstance(mapId)
            
            if instance then
                table.insert(games, {
                    mapId = mapId,
                    label = mapData.label or mapData.name or mapId,
                    currentPlayers = instance.currentPlayers or 0,
                    maxPlayers = Config.InstanceSystem.maxPlayersPerInstance or 20,
                    isActive = instance.gameActive or false
                })
            end
        end
    end
    
    return games
end

function MapRotation.ReplaceMap(oldMapId, reason)
    reason = reason or "Rotation automatique"
    
    local allMaps = Config.MapRotation.allMaps
    local available = {}
    
    for _, mapId in ipairs(allMaps) do
        local isActive = false
        for _, activeMapId in ipairs(activeMaps) do
            if activeMapId == mapId then
                isActive = true
                break
            end
        end
        
        if not isActive then
            table.insert(available, mapId)
        end
    end
    
    if #available == 0 then
        return false
    end
    
    local newMapId = available[math.random(1, #available)]
    local oldMapData = Config.Maps[oldMapId]
    local newMapData = Config.Maps[newMapId]
    
    for i, mapId in ipairs(activeMaps) do
        if mapId == oldMapId then
            activeMaps[i] = newMapId
            break
        end
    end
    
    TriggerClientEvent('gungame:notifyMapRotation', -1, {
        previousMap = oldMapData and oldMapData.label or oldMapId,
        newMap = newMapData and newMapData.label or newMapId,
        reason = reason
    })
    
    MapRotation.KickPlayersFromMap(oldMapId)
    
    mapIdleTimers[newMapId] = os.time()
    mapIdleTimers[oldMapId] = nil
    
    return true
end

function MapRotation.KickPlayersFromMap(mapId)
    local affectedPlayers = {}
    
    for instanceId, instance in pairs(InstanceManager.GetAllInstances()) do
        if instance.map == mapId and instance.players then
            for _, playerId in ipairs(instance.players) do
                table.insert(affectedPlayers, {
                    source = playerId,
                    instanceId = instanceId
                })
            end
        end
    end
    
    if #affectedPlayers > 0 then        
        for _, playerInfo in ipairs(affectedPlayers) do
            TriggerEvent('gungame:rotationForcedQuit', playerInfo.source)
        end
    end
end

function MapRotation.OnVictory(mapId)
    if not Config.MapRotation.rotateOnVictory then
        return
    end
    
    SetTimeout(Config.MapRotation.victoryRotationDelay or 5000, function()
        MapRotation.ReplaceMap(mapId, "Victoire")
    end)
end

function MapRotation.CheckIdleMaps()
    local currentTime = os.time()
    local idleThreshold = (Config.MapRotation.idleRotationInterval or 3600000) / 1000
    
    for _, mapId in ipairs(activeMaps) do
        local hasPlayers = false
        
        for instanceId, instance in pairs(InstanceManager.GetAllInstances()) do
            if instance.map == mapId and instance.currentPlayers and instance.currentPlayers > 0 then
                hasPlayers = true
                mapIdleTimers[mapId] = currentTime
                break
            end
        end
        
        if not hasPlayers then
            if not mapIdleTimers[mapId] then
                mapIdleTimers[mapId] = currentTime
            end
            
            local idleTime = currentTime - mapIdleTimers[mapId]
            
            if idleTime >= idleThreshold then
                MapRotation.ReplaceMap(mapId, "Inactivité")
            end
        end
    end
end

function MapRotation.StartIdleMonitoring()
    for _, mapId in ipairs(activeMaps) do
        mapIdleTimers[mapId] = os.time()
    end
    
    Citizen.CreateThread(function()
        while Config.MapRotation.enabled do
            Wait(60000)
            
            if Config.MapRotation.rotateEmptyMaps then
                MapRotation.CheckIdleMaps()
            end
        end
    end)
end

function MapRotation.GetRotationInfo()
    return {
        activeMaps = activeMaps,
        totalMaps = #Config.MapRotation.allMaps,
        idleRotationMinutes = (Config.MapRotation.idleRotationInterval or 3600000) / 60000,
        rotateOnVictory = Config.MapRotation.rotateOnVictory
    }
end