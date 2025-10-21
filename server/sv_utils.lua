-- ============================================================================
-- GUNGAME v2.0.0 - server/sv_utils.lua - ROTATION 2 MAPS
-- ============================================================================

-- ============================================================================
-- SPAWN SYSTEM - Gestion des spawns
-- ============================================================================

SpawnSystem = {}
local instanceSpawnIndexes = {}
local occupiedSpawns = {}

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
            lastActivity = os.time() -- Timestamp de dernière activité
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
local activeMaps = {} -- Les 2 maps actuellement actives
local usedMapIndexes = {} -- Historique des maps utilisées
local mapIdleTimers = {} -- Timers d'inactivité pour chaque map

function MapRotation.Initialize()
    if not Config.MapRotation or not Config.MapRotation.enabled then
        print("^1[MapRotation]^7 Système de rotation désactivé")
        return
    end
    
    if not Config.MapRotation.allMaps or #Config.MapRotation.allMaps < 2 then
        print("^1[MapRotation]^7 ERREUR: Au moins 2 maps requises dans allMaps")
        return
    end
    
    -- Sélectionner 2 maps aléatoires au démarrage
    activeMaps = MapRotation.SelectRandomMaps(Config.MapRotation.simultaneousMaps or 2)
    
    print("^2[MapRotation]^7 ==========================================")
    print("^2[MapRotation]^7 Système de rotation 2 maps activé")
    print("^2[MapRotation]^7 Maps actives:")
    for _, mapId in ipairs(activeMaps) do
        local mapData = Config.Maps[mapId]
        print(string.format("^3[MapRotation]^7   - %s (%s)", mapId, mapData and mapData.label or "Inconnu"))
    end
    print("^2[MapRotation]^7 ==========================================")
    
    -- Démarrer la surveillance d'inactivité
    MapRotation.StartIdleMonitoring()
end

function MapRotation.SelectRandomMaps(count)
    local allMaps = Config.MapRotation.allMaps
    local selected = {}
    local available = {}
    
    -- Créer une liste des maps disponibles
    for _, mapId in ipairs(allMaps) do
        table.insert(available, mapId)
    end
    
    -- Sélectionner 'count' maps aléatoires
    for i = 1, math.min(count, #available) do
        local randomIndex = math.random(1, #available)
        table.insert(selected, available[randomIndex])
        table.remove(available, randomIndex)
    end
    
    return selected
end

function MapRotation.GetActiveMaps()
    -- S'assurer qu'on retourne toujours une table valide
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
    
    -- Vérifier que activeMaps est initialisé
    if not activeMaps or #activeMaps == 0 then
        print("^1[MapRotation]^7 ERREUR: activeMaps non initialisé ou vide")
        
        -- Fallback: initialiser avec 2 maps aléatoires
        if Config.MapRotation and Config.MapRotation.allMaps and #Config.MapRotation.allMaps >= 2 then
            activeMaps = MapRotation.SelectRandomMaps(Config.MapRotation.simultaneousMaps or 2)
            print("^3[MapRotation]^7 Fallback: activation de 2 maps aléatoires")
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
        else
            print("^1[MapRotation]^7 ERREUR: Map " .. mapId .. " introuvable dans Config.Maps")
        end
    end
    
    return games
end

function MapRotation.ReplaceMap(oldMapId, reason)
    reason = reason or "Rotation automatique"
    
    local allMaps = Config.MapRotation.allMaps
    local available = {}
    
    -- Trouver les maps non utilisées
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
        print("^3[MapRotation]^7 Aucune map disponible pour remplacer " .. oldMapId)
        return false
    end
    
    -- Sélectionner une map aléatoire
    local newMapId = available[math.random(1, #available)]
    local oldMapData = Config.Maps[oldMapId]
    local newMapData = Config.Maps[newMapId]
    
    -- Remplacer dans la liste active
    for i, mapId in ipairs(activeMaps) do
        if mapId == oldMapId then
            activeMaps[i] = newMapId
            break
        end
    end
    
    print(string.format("^2[MapRotation]^7 Rotation (%s): %s -> %s", 
        reason,
        oldMapData and oldMapData.label or oldMapId, 
        newMapData and newMapData.label or newMapId))
    
    -- Notifier tous les joueurs
    TriggerClientEvent('gungame:notifyMapRotation', -1, {
        previousMap = oldMapData and oldMapData.label or oldMapId,
        newMap = newMapData and newMapData.label or newMapId,
        reason = reason
    })
    
    -- Forcer les joueurs de cette map à quitter
    MapRotation.KickPlayersFromMap(oldMapId)
    
    -- Réinitialiser le timer d'inactivité
    mapIdleTimers[newMapId] = os.time()
    mapIdleTimers[oldMapId] = nil
    
    return true
end

function MapRotation.KickPlayersFromMap(mapId)
    local affectedPlayers = {}
    
    -- Trouver toutes les instances de cette map
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
        print(string.format("^3[MapRotation]^7 Expulsion de %d joueur(s) de la map %s", 
            #affectedPlayers, mapId))
        
        for _, playerInfo in ipairs(affectedPlayers) do
            TriggerEvent('gungame:rotationForcedQuit', playerInfo.source)
        end
    end
end

function MapRotation.OnVictory(mapId)
    if not Config.MapRotation.rotateOnVictory then
        return
    end
    
    print(string.format("^2[MapRotation]^7 Victoire détectée sur %s, rotation programmée", mapId))
    
    SetTimeout(Config.MapRotation.victoryRotationDelay or 5000, function()
        MapRotation.ReplaceMap(mapId, "Victoire")
    end)
end

function MapRotation.CheckIdleMaps()
    local currentTime = os.time()
    local idleThreshold = (Config.MapRotation.idleRotationInterval or 3600000) / 1000 -- Convertir en secondes
    
    for _, mapId in ipairs(activeMaps) do
        -- Vérifier si la map a des joueurs
        local hasPlayers = false
        
        for instanceId, instance in pairs(InstanceManager.GetAllInstances()) do
            if instance.map == mapId and instance.currentPlayers and instance.currentPlayers > 0 then
                hasPlayers = true
                mapIdleTimers[mapId] = currentTime -- Reset timer
                break
            end
        end
        
        if not hasPlayers then
            -- Initialiser le timer si nécessaire
            if not mapIdleTimers[mapId] then
                mapIdleTimers[mapId] = currentTime
            end
            
            -- Vérifier si le délai d'inactivité est dépassé
            local idleTime = currentTime - mapIdleTimers[mapId]
            
            if idleTime >= idleThreshold then
                print(string.format("^3[MapRotation]^7 Map %s inactive depuis %d secondes", 
                    mapId, idleTime))
                MapRotation.ReplaceMap(mapId, "Inactivité")
            end
        end
    end
end

function MapRotation.StartIdleMonitoring()
    -- Initialiser les timers
    for _, mapId in ipairs(activeMaps) do
        mapIdleTimers[mapId] = os.time()
    end
    
    -- Thread de surveillance
    Citizen.CreateThread(function()
        while Config.MapRotation.enabled do
            Wait(60000) -- Vérifier toutes les minutes
            
            if Config.MapRotation.rotateEmptyMaps then
                MapRotation.CheckIdleMaps()
            end
        end
    end)
    
    print("^2[MapRotation]^7 Surveillance d'inactivité démarrée")
end

function MapRotation.GetRotationInfo()
    return {
        activeMaps = activeMaps,
        totalMaps = #Config.MapRotation.allMaps,
        idleRotationMinutes = (Config.MapRotation.idleRotationInterval or 3600000) / 60000,
        rotateOnVictory = Config.MapRotation.rotateOnVictory
    }
end